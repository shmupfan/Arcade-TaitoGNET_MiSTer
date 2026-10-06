// Panasonic MN10200 (MN1020012A) CPU core for the Taito Zoom sound board.
// Own implementation from docs/mn10200_design.md (section 5); no code from
// other MN10200 cores.
//
// Multi-cycle sequencer: BOUND (interrupt sample) -> FETCH -> DEC (ROM) ->
// EXEC (+ MEM / MD steps) -> RET. Each instruction retires the manual's
// minimum cycle count (MN102L manual pp.145-151, design study 2.4) as
// virtual machine cycles on retire/retire_cyc; the peripheral block steps
// its timers by them and the pacer in mn10200.sv locks them to real time.
// How many FPGA clocks an instruction takes does not change behaviour.
//
// Semantics follow the MN102L manual; where the MN1020012A differs or the
// manual is silent, MAME 0.288 mn10200.cpp is the reference (design study
// 1.1, 1.2, 2.5) and the comments say so.
module mn10200_core #(
    parameter FORM_HEX = "rtl/zoom/mn10200_form.hex",
    parameter CTL_HEX  = "rtl/zoom/mn10200_ctl.hex",
    parameter DEBUG    = 1,       // 0: no cumulative cycle counter (dbg_cycles = 0)
    parameter RF_MLAB  = 1,       // register file in MLAB (1) or flip-flops (0)
    parameter PIPE     = 0        // 1: extra registers for a 67.7 MHz clock (docs/zoom_board_design.md 6.5):
                                  // decode fields, DIVU overflow compare and the interrupt
                                  // request registered, two more clocks at the boundary
) (
    input  logic        clk,
    input  logic        rst,
    // external bus: 16-bit, little-endian, byte enables, held until ack
    output logic [23:0] bus_addr,
    output logic        bus_rd,
    output logic        bus_wr,
    output logic [1:0]  bus_be,
    output logic [15:0] bus_wdata,
    input  logic [15:0] bus_rdata,
    input  logic        bus_ack,
    // internal I/O 0x00FC00-0x00FFFF, one clock, combinational read data
    output logic        io_rd,
    output logic        io_wr,
    output logic [9:0]  io_addr,
    output logic [1:0]  io_be,
    output logic [15:0] io_wdata,
    input  logic [15:0] io_rdata,
    // interrupt controller
    input  logic        irq_cand,       // a group with IR & IE and level < PSW.IM
    input  logic [2:0]  irq_level,
    input  logic [3:0]  irq_group,
    input  logic        nmi_req,        // NMICR != 0
    input  logic        pirq_set,       // peripheral event: re-check interrupts
    output logic [2:0]  psw_im,
    output logic        irq_take,       // pulse: interrupt accepted
    output logic [3:0]  irq_take_group, // -> IAGR
    output logic        ill,            // pulse: illegal opcode (NMICR bit 1)
    // virtual machine cycles
    output logic        retire,         // pulse: instruction retired
    output logic [4:0]  retire_cyc,     // its cycles (+7 after interrupt entry)
    input  logic        tmr_busy,       // peripherals still stepping cycles
    input  logic        go,             // pacer credit
    input  logic        hold,           // testbench: stay at the boundary
    output logic [4:0]  acc_cyc,        // cycles of the instruction in EXEC/MEM, with a pending
                                        // interrupt entry: MAME charges them before the access
    // debug / trace port (design study 5.8)
    output logic        dbg_bound,      // waiting at an instruction boundary
    output logic        dbg_insn,       // pulse: instruction starts (after interrupt entry)
    output logic [23:0] dbg_pc,
    output logic [15:0] dbg_psw,
    output logic [15:0] dbg_mdr,
    output logic [47:0] dbg_cycles,     // cycles before this instruction
    output logic [191:0] dbg_regs       // {A3,A2,A1,A0,D3,D2,D1,D0}
);
    // ------------------------------------------------------------------
    // control word fields (tools/mn102/mn102_rom.py)
    localparam K_ALU = 4'd0, K_LD = 4'd1, K_ST = 4'd2, K_BSET = 4'd3, K_BCLR = 4'd4,
               K_MUL = 4'd5, K_MULU = 4'd6, K_DIVU = 4'd7, K_BCC = 4'd8, K_JMP = 4'd9,
               K_JSR = 4'd10, K_JMPA = 4'd11, K_JSRA = 4'd12, K_RTS = 4'd13, K_RTI = 4'd14,
               K_ILL = 4'd15;
    localparam EA_AN = 3'd0, EA_D8 = 3'd1, EA_D16 = 3'd2, EA_D24 = 3'd3, EA_DI = 3'd4,
               EA_ABS16 = 3'd5, EA_ABS24 = 3'd6;
    localparam A_ADD = 4'd0, A_SUB = 4'd1, A_ADDC = 4'd2, A_SUBC = 4'd3, A_AND = 4'd4,
               A_OR = 4'd5, A_XOR = 4'd6, A_PASSB = 4'd7, A_ROL = 4'd8, A_ROR = 4'd9,
               A_ASR = 4'd10, A_LSR = 4'd11, A_EXTX = 4'd12, A_EXTXU = 4'd13,
               A_EXTXB = 4'd14, A_EXTXBU = 4'd15;
    localparam F_NONE = 3'd0, F_ARITH = 3'd1, F_STICKY = 3'd2, F_LOGIC = 3'd3, F_SHIFT = 3'd4;
    localparam W_NONE = 3'd0, W_REG = 3'd1, W_MDR = 3'd2, W_PSW = 3'd3, W_MDREXT = 3'd4;

    // ------------------------------------------------------------------
    // architectural state
    typedef enum logic [3:0] {
        S_CLR, S_FETCH, S_IRQ1, S_IRQ2, S_EXEC, S_PUSH, S_EXEC2, S_EXEC3, S_MEM, S_MD,
        S_MDF, S_RET
    } state_t;
    state_t st, m_ret;
    logic [23:0] pc;
    logic [15:0] psw, mdr;
    logic        pirq;              // MAME m_possible_irq: re-check at next boundary
    logic [47:0] cycles;

    assign psw_im = psw[10:8];
    assign dbg_pc = pc;
    assign dbg_psw = psw;
    assign dbg_mdr = mdr;
    assign dbg_cycles = cycles;

    // ------------------------------------------------------------------
    // sequencer

    // instruction bytes
    logic [7:0] ib0, ib1, ib2, ib3, ib4;
    logic [2:0] nb;
    // one-word fetch buffer
    logic [15:0] fbuf;
    logic [22:0] fbuf_wa;
    logic        fbuf_v;
    // prefetch word: the word after the current instruction, read while the
    // core waits at the boundary (decode ROM latency, timer stepping)
    logic [15:0] pbuf;
    logic [22:0] pbuf_wa, pf_wa_q;
    logic        pbuf_v, pf_busy;

    // length from the first byte only (design study 2.2)
    function automatic logic [2:0] len_of(input logic [7:0] b);
        if (b < 8'h40) len_of = 3'd1;
        else if (b < 8'h80) len_of = 3'd2;
        else if (b < 8'h90) len_of = (b[3:2] == b[1:0]) ? 3'd2 : 3'd1;
        else if (b < 8'hC0) len_of = 3'd1;
        else if (b < 8'hD0) len_of = 3'd3;
        else if (b < 8'hDC) len_of = 3'd2;
        else if (b < 8'hE0) len_of = 3'd3;
        else if (b < 8'hEB) len_of = 3'd2;
        else if (b == 8'hEB) len_of = 3'd1;
        else if (b < 8'hF0) len_of = 3'd3;
        else if (b < 8'hF4) len_of = 3'd2;
        else if (b == 8'hF4) len_of = 3'd5;
        else if (b == 8'hF5) len_of = 3'd3;
        else if (b == 8'hF6) len_of = 3'd1;
        else if (b == 8'hF7) len_of = 3'd4;
        else if (b < 8'hFE) len_of = 3'd3;
        else len_of = 3'd1;   // FE rts, FF undefined
    endfunction

    // fetch position, length and how many bytes the buffer word supplies.
    // Bytes come from the one-word buffer, or straight from the bus on ack.
    logic       f_done;                 // all instruction bytes fetched
    logic       f_done_q;               // PIPE: f_done one clock ago (registered fields settled)
    logic [1:0] dec_cnt;                // clocks since the decode ROM address settled
    localparam logic [1:0] DEC_N = PIPE ? 2'd3 : 2'd2;
    wire [23:0] fpos    = pc + {21'h0, nb};
    wire        hit0    = fbuf_v && fbuf_wa == fpos[23:1];
    wire        hit1    = pbuf_v && pbuf_wa == fpos[23:1];
    wire        f_hit   = hit0 || hit1;
    wire        f_ack   = bus_rd && bus_ack && !pf_busy;
    wire [15:0] f_word  = hit0 ? fbuf : (hit1 ? pbuf : bus_rdata);
    wire [7:0]  f_first = fpos[0] ? f_word[15:8] : f_word[7:0];
    wire [2:0]  f_len   = (nb == 3'd0) ? len_of(f_first) : len_of(ib0);
    wire [2:0]  f_take  = (!fpos[0] && (f_len - nb) >= 3'd2) ? 3'd2 : 3'd1;

    // page: 0 first byte, 1-7 second byte after F0-F5, F7
    logic [2:0] page_c;
    always_comb begin
        case (ib0)
            8'hF0: page_c = 3'd1;
            8'hF1: page_c = 3'd2;
            8'hF2: page_c = 3'd3;
            8'hF3: page_c = 3'd4;
            8'hF4: page_c = 3'd5;
            8'hF5: page_c = 3'd6;
            8'hF7: page_c = 3'd7;
            default: page_c = 3'd0;
        endcase
    end
    wire  [7:0] kb_c = (page_c != 3'd0) ? ib1 : ib0;
    wire  [7:0] i0_c = (page_c != 3'd0) ? ib2 : ib1;
    wire  [7:0] i1_c = (page_c != 3'd0) ? ib3 : ib2;
    // PIPE: the same fields one clock later from registers (the instruction
    // bytes are stable from the end of the fetch to the next fetch)
    logic [2:0] page_r;
    logic [7:0] kb_r, i0_r, i1_r, i2_r;
    always_ff @(posedge clk) begin
        page_r <= page_c; kb_r <= kb_c; i0_r <= i0_c; i1_r <= i1_c; i2_r <= ib4;
    end
    wire  [2:0] page = PIPE ? page_r : page_c;
    wire  [7:0] kb  = PIPE ? kb_r : kb_c;           // key byte: register fields
    wire  [1:0] f10 = kb[1:0];                      // Dm / Am / Dn
    wire  [1:0] f32 = kb[3:2];                      // An / source register
    wire  [1:0] f54 = kb[5:4];                      // Di
    wire  [7:0] i0  = PIPE ? i0_r : i0_c;           // immediate / displacement bytes
    wire  [7:0] i1  = PIPE ? i1_r : i1_c;
    wire  [7:0] i2  = PIPE ? i2_r : ib4;            // third byte: F4 page only

    // decode ROMs
    logic [39:0] ctl;
    mn10200_decode #(.FORM_HEX(FORM_HEX), .CTL_HEX(CTL_HEX)) u_dec (
        .clk(clk), .addr({page, kb}), .ctl(ctl));
    wire [3:0] c_kind = ctl[3:0];
    wire [2:0] c_ea   = ctl[6:4];
    wire [1:0] c_mw   = ctl[8:7];
    wire       c_msx  = ctl[9];
    wire       c_dsta = ctl[10];
    wire       c_srca = ctl[11];
    wire [1:0] c_bsel = ctl[13:12];
    wire [2:0] c_imm  = ctl[16:14];
    wire [3:0] c_alu  = ctl[20:17];
    wire [2:0] c_flg  = ctl[23:21];
    wire [2:0] c_wb   = ctl[26:24];
    wire       c_apsw = ctl[27];
    wire [3:0] c_cond = ctl[31:28];
    wire       c_cx   = ctl[32];
    wire [3:0] c_cyc  = ctl[36:33];
    wire [2:0] c_len  = ctl[39:37];

    // ------------------------------------------------------------------
    // register file: one write port, written the clock after the request
    // (every state that writes is followed by one that does not read the
    // register), four read ports. The An port reads A3 in the states that
    // use the stack.
    logic        rf_we;
    logic [2:0]  rf_wa;
    logic [23:0] rf_wd;
    logic [23:0] r_dst, r_src, r_an, r_di;
    wire stk = (st == S_FETCH) || (st == S_IRQ1) || (st == S_IRQ2) || (st == S_PUSH)
            || ((st == S_EXEC || st == S_EXEC2 || st == S_EXEC3) && (c_kind == K_RTS || c_kind == K_RTI))
            || (st == S_EXEC2 && (c_kind == K_JSR || c_kind == K_JSRA));
    mn10200_rf #(.MLAB(RF_MLAB)) u_rf (
        .clk(clk), .we(rf_we), .wa(rf_wa), .wd(rf_wd),
        .ra0({c_dsta, f10}), .ra1({c_srca, f32}), .ra2(stk ? 3'd7 : {1'b1, f32}), .ra3({1'b0, f54}),
        .rd0(r_dst), .rd1(r_src), .rd2(r_an), .rd3(r_di), .dbg(dbg_regs));

    logic [23:0] immv;
    always_comb begin
        case (c_imm)
            3'd1: immv = {{16{i0[7]}}, i0};
            3'd2: immv = {16'h0, i0};
            3'd3: immv = {{8{i1[7]}}, i1, i0};
            3'd4: immv = {8'h0, i1, i0};
            3'd5: immv = {i2, i1, i0};
            3'd6: immv = 24'h00FFFF;
            default: immv = 24'h0;
        endcase
    end

    // effective address
    logic [23:0] ea_base, ea_disp;
    always_comb begin
        ea_base = (c_ea == EA_ABS16 || c_ea == EA_ABS24) ? 24'h0 : r_an;
        case (c_ea)
            EA_D8:    ea_disp = {{16{i0[7]}}, i0};
            EA_D16:   ea_disp = {{8{i1[7]}}, i1, i0};
            EA_D24:   ea_disp = {i2, i1, i0};
            EA_DI:    ea_disp = r_di;
            EA_ABS16: ea_disp = {8'h0, i1, i0};
            EA_ABS24: ea_disp = {i2, i1, i0};
            default:  ea_disp = 24'h0;
        endcase
    end
    // after the fetch, nb is the instruction length, so fpos is the next PC
    wire [23:0] pc_seq = fpos;

    // address unit: one adder for effective addresses, branch targets,
    // stack pointer steps and the second word of 24-bit accesses
    logic [23:0] agu_b, agu_o;
    always_comb begin
        agu_b = ea_base;
        agu_o = ea_disp;
        case (st)
            // stack states: the An port reads A3 (stk), the base must not
            // follow the next instruction's addressing mode
            S_FETCH, S_PUSH: begin agu_b = r_an; agu_o = 24'hFFFFFC; end   // A3 - 4
            S_IRQ1, S_IRQ2:  begin agu_b = r_an; agu_o = 24'hFFFFFA; end   // A3 - 6
            S_EXEC: if (c_kind == K_BCC || c_kind == K_JMP || c_kind == K_JSR) begin
                        agu_b = pc_seq;                     // label8/16/24 target
                        agu_o = immv;
                    end
            S_EXEC2: case (c_kind)
                        K_JSR, K_JSRA: begin agu_b = r_an; agu_o = 24'hFFFFFC; end  // A3 - 4
                        K_RTS:         begin agu_b = r_an; agu_o = 24'd4; end
                        K_RTI:         begin agu_b = r_an; agu_o = 24'd2; end
                        default: ;                          // BSET/BCLR write: EA again
                    endcase
            S_EXEC3: begin agu_b = r_an; agu_o = 24'd6; end // RTI: A3 + 6
            S_MEM: begin
                agu_b = {m_addr[23:1], 1'b0};               // 24-bit access: byte at +2
                agu_o = 24'd2;
            end
            default: ;
        endcase
    end
    wire [23:0] agu = agu_b + agu_o;

    // ------------------------------------------------------------------
    // ALU (design study 2.5; flag rules as MN102L manual, ADDC/SUBC p.71)
    wire [23:0] alu_a = c_apsw ? {8'h0, psw} : r_dst;
    logic [23:0] alu_b;
    always_comb begin
        case (c_bsel)
            2'd0: alu_b = r_src;
            2'd1: alu_b = immv;
            2'd2: alu_b = {8'h0, mdr};
            default: alu_b = {8'h0, psw};
        endcase
    end
    wire        is_sub = (c_alu == A_SUB) || (c_alu == A_SUBC);
    wire        cin    = (c_alu == A_ADDC || c_alu == A_SUBC) ? psw[2] : 1'b0;
    wire [23:0] bx     = alu_b ^ {24{is_sub}};
    wire [24:0] sum    = {1'b0, alu_a} + {1'b0, bx} + {24'h0, cin ^ is_sub};
    wire        c24    = sum[24] ^ is_sub;                       // carry / borrow out of bit 23
    wire        c16    = sum[16] ^ alu_a[16] ^ bx[16] ^ is_sub;  // carry / borrow out of bit 15
    wire        v24    = (alu_a[23] ^ sum[23]) & (bx[23] ^ sum[23]);
    wire        v16    = (alu_a[15] ^ sum[15]) & (bx[15] ^ sum[15]);

    logic [23:0] alu_r;
    logic        sh_c;
    always_comb begin
        sh_c = 1'b0;
        case (c_alu)
            A_ADD, A_SUB, A_ADDC, A_SUBC: alu_r = sum[23:0];
            A_AND:   alu_r = {alu_a[23:16], alu_a[15:0] & alu_b[15:0]};
            A_OR:    alu_r = {alu_a[23:16], alu_a[15:0] | alu_b[15:0]};
            A_XOR:   alu_r = {alu_a[23:16], alu_a[15:0] ^ alu_b[15:0]};
            A_PASSB: alu_r = alu_b;
            A_ROL:   begin alu_r = {alu_a[23:16], alu_a[14:0], psw[2]}; sh_c = alu_a[15]; end
            A_ROR:   begin alu_r = {alu_a[23:16], psw[2], alu_a[15:1]}; sh_c = alu_a[0]; end
            A_ASR:   begin alu_r = {alu_a[23:15], alu_a[15:1]}; sh_c = alu_a[0]; end
            A_LSR:   begin alu_r = {alu_a[23:16], 1'b0, alu_a[15:1]}; sh_c = alu_a[0]; end
            A_EXTX:  alu_r = {{8{alu_a[15]}}, alu_a[15:0]};
            A_EXTXU: alu_r = {8'h0, alu_a[15:0]};
            A_EXTXB: alu_r = {{16{alu_a[7]}}, alu_a[7:0]};
            default: alu_r = {16'h0, alu_a[7:0]};    // EXTXBU
        endcase
    end
    // PSW low byte: VX CX NX ZX VF CF NF ZF
    logic [7:0] alu_f;
    always_comb begin
        case (c_flg)
            F_ARITH, F_STICKY: alu_f = {v24, c24, sum[23], sum[23:0] == 24'h0,
                                        v16, c16, sum[15],
                                        (sum[15:0] == 16'h0) & ((c_flg == F_ARITH) | psw[0])};
            F_LOGIC: alu_f = {psw[7:4], 2'b00, alu_r[15], alu_r[15:0] == 16'h0};
            F_SHIFT: alu_f = {psw[7:4], 1'b0, sh_c, alu_r[15], alu_r[15:0] == 16'h0};
            default: alu_f = psw[7:0];
        endcase
    end

    // branch condition
    wire fz = c_cx ? psw[4] : psw[0];
    wire fn = c_cx ? psw[5] : psw[1];
    wire fc = c_cx ? psw[6] : psw[2];
    wire fv = c_cx ? psw[7] : psw[3];
    logic taken_c;
    always_comb begin
        case (c_cond)
            4'd0:  taken_c = fn ^ fv;
            4'd1:  taken_c = ~((fn ^ fv) | fz);
            4'd2:  taken_c = ~(fn ^ fv);
            4'd3:  taken_c = (fn ^ fv) | fz;
            4'd4:  taken_c = fc;
            4'd5:  taken_c = ~(fc | fz);
            4'd6:  taken_c = ~fc;
            4'd7:  taken_c = fc | fz;
            4'd8:  taken_c = fz;
            4'd9:  taken_c = ~fz;
            4'd10: taken_c = 1'b1;
            4'd11: taken_c = ~fv;
            4'd12: taken_c = fv;
            4'd13: taken_c = ~fn;
            default: taken_c = fn;
        endcase
    end

    // ------------------------------------------------------------------
    // memory access engine: m_w = 1 byte, 2 word (even), 3 word + byte at +2
    logic [23:0] m_addr, m_wd, md;
    logic [1:0]  m_w;
    logic        m_we, m_ph, m_busy;
    logic [23:0] ph_addr;
    logic [1:0]  ph_be;
    logic [15:0] ph_wd;
    always_comb begin
        if (!m_ph) begin
            ph_addr = (m_w == 2'd1) ? m_addr : {m_addr[23:1], 1'b0};
            ph_be   = (m_w == 2'd1) ? (m_addr[0] ? 2'b10 : 2'b01) : 2'b11;
            ph_wd   = (m_w == 2'd1) ? {m_wd[7:0], m_wd[7:0]} : m_wd[15:0];
        end else begin
            ph_addr = m_addr;                                // set to +2 by the AGU
            ph_be   = 2'b01;
            ph_wd   = {m_wd[23:16], m_wd[23:16]};
        end
    end
    wire ph_io = (ph_addr[23:10] == 14'h003F);
    wire mem_io_now = (st == S_MEM) && !m_busy && ph_io;
    assign io_rd    = mem_io_now && !m_we;
    assign io_wr    = mem_io_now && m_we;
    assign io_addr  = ph_addr[9:0];
    assign io_be    = ph_be;
    assign io_wdata = ph_wd;
    // read data of the current phase (bus or I/O), and phase completion
    wire [15:0] ph_rd  = ph_io ? io_rdata : bus_rdata;
    wire        ph_fin = (!m_busy && ph_io) || (m_busy && bus_ack);

    // ------------------------------------------------------------------
    // multiply / divide (iterative, 16 steps; design study 5.5)
    logic [15:0] md_acc, md_q, md_m;
    logic [4:0]  md_n;
    logic        md_signed;
    wire         mul_neg = md_signed && (md_n == 5'd15);  // signed: the sign bit's weight is negative
    wire  [16:0] mul_a   = {md_signed & md_acc[15], md_acc};
    wire  [16:0] mul_m   = {md_signed & md_m[15], md_m} ^ {17{mul_neg}};
    wire  [16:0] mul_add = mul_a + mul_m + {16'h0, mul_neg};
    wire  [16:0] mul_sum = md_q[0] ? mul_add : mul_a;
    wire  [16:0] div_t   = {md_acc, md_q[15]};
    wire  [16:0] div_d   = div_t - {1'b0, md_m};
    wire         div_ge  = ~div_d[16];

    // ------------------------------------------------------------------
    logic        irq7;              // interrupt entry cycles to retire with the next instruction
    // Zoom board time base (docs/zoom_board_design.md 6.2): an external access
    // lands at the end of its instruction in machine time (mn10200.cpp charges
    // every cycle before the access), so the board looks this far ahead.
    assign acc_cyc = {1'b0, c_cyc} + (irq7 ? 5'd7 : 5'd0);
    logic        irq_skip;          // first instruction of a handler: no interrupt check (MAME)
    logic [2:0]  irq_lvl_q;
    logic [3:0]  irq_grp_q;
    logic [23:0] pc_next;
    logic [3:0]  kind_q;

    // start a memory access (MEM state), continue at ret when done
`define MN102_MEM(a, w, we, d, ret) \
        begin m_addr <= (a); m_w <= (w); m_we <= (we); m_wd <= (d); m_ph <= 1'b0; \
              m_busy <= 1'b0; m_ret <= (ret); st <= S_MEM; end

    // register file write request (performed at the next clock edge)
`define MN102_WR(a, d) begin rf_we <= 1'b1; rf_wa <= (a); rf_wd <= (d); end

    // retire: commit PC, report the cycles to the peripherals and the pacer,
    // and start fetching the next instruction
`define MN102_RETIRE(npc, extra) \
        begin pc <= (npc); retire <= 1'b1; \
              retire_cyc <= {1'b0, c_cyc} + {4'h0, (extra)} + (irq7 ? 5'd7 : 5'd0); \
              if (DEBUG) cycles <= cycles + {44'h0, c_cyc} + {47'h0, (extra)}; irq7 <= 1'b0; \
              st <= S_FETCH; nb <= 3'd0; f_done <= 1'b0; end

    // instruction boundary: bytes fetched, decode valid, timers caught up.
    // The next instruction is fetched and decoded while the timers step the
    // previous one's cycles; interrupts are sampled here, before execution.
    wire at_bound = (st == S_FETCH) && f_done && (dec_cnt == DEC_N) && (!PIPE || f_done_q);

    // prefetch candidate: the word holding the next sequential byte, or the
    // one after it when that is already buffered (f_done: fpos is the next PC)
    wire        has_w0  = (fbuf_v && fbuf_wa == fpos[23:1]) || (pbuf_v && pbuf_wa == fpos[23:1]);
    wire [22:0] w1      = fpos[23:1] + 23'd1;
    wire        has_w1  = (fbuf_v && fbuf_wa == w1) || (pbuf_v && pbuf_wa == w1);
    wire        pf_want = (st == S_FETCH) && f_done && !bus_rd && !bus_wr && !pf_busy && !(has_w0 && has_w1);
    wire [22:0] pf_wa   = has_w0 ? w1 : fpos[23:1];
    // PIPE: the interrupt request is registered (cand_q etc.), so the sample
    // waits one more clock after the timers finish stepping
    logic        tmr_busy_q, cand_q, nmi_q, pset_q, div_ovf_q;
    logic [2:0]  lvl_q;
    logic [3:0]  grp_q;
    always_ff @(posedge clk) begin
        tmr_busy_q <= tmr_busy;
        cand_q <= irq_cand; nmi_q <= nmi_req; lvl_q <= irq_level; grp_q <= irq_group;
        pset_q <= pirq_set;
        f_done_q <= f_done;
    end
    wire        i_cand  = PIPE ? cand_q : irq_cand;
    wire        i_nmi   = PIPE ? nmi_q : nmi_req;
    wire [2:0]  i_lvl   = PIPE ? lvl_q : irq_level;
    wire [3:0]  i_grp   = PIPE ? grp_q : irq_group;
    wire        i_pset  = PIPE ? pset_q : pirq_set;
    wire chk_now  = at_bound && !tmr_busy && (!PIPE || !tmr_busy_q) && go && !hold;
    // PIPE: DIVU overflow compare one clock ahead (operands are stable at the boundary)
    always_ff @(posedge clk) div_ovf_q <= (mdr >= r_src[15:0]);
    assign dbg_bound = at_bound;

    integer i;
    always_ff @(posedge clk) begin
        irq_take <= 1'b0;
        ill <= 1'b0;
        retire <= 1'b0;
        dbg_insn <= 1'b0;
        rf_we <= 1'b0;
        if (i_pset && !(chk_now && !irq_skip)) pirq <= 1'b1;
        if (rst) begin
            st <= S_CLR;
            rf_wa <= 3'd0;
            f_done <= 1'b0;
            dec_cnt <= 2'd0;
            irq_skip <= 1'b0;
            cycles <= 48'h0;
            pc <= 24'h080000;
            psw <= 16'h0;
            mdr <= 16'h0;
            pirq <= 1'b0;
            irq7 <= 1'b0;
            fbuf_v <= 1'b0;
            pbuf_v <= 1'b0;
            pf_busy <= 1'b0;
            bus_rd <= 1'b0;
            bus_wr <= 1'b0;
            m_busy <= 1'b0;
            nb <= 3'd0;
        end else begin
            // prefetch issue and completion (any state; other accesses wait for it)
            if (pf_busy && bus_ack) begin
                bus_rd <= 1'b0;
                pf_busy <= 1'b0;
                pbuf <= bus_rdata;
                pbuf_wa <= pf_wa_q;
                pbuf_v <= 1'b1;
            end else if (pf_want) begin
                bus_addr <= {pf_wa, 1'b0};
                bus_be <= 2'b11;
                bus_rd <= 1'b1;
                pf_busy <= 1'b1;
                pf_wa_q <= pf_wa;
            end
            if (st == S_FETCH && !f_done && (f_hit || f_ack) && nb < 3'd2) dec_cnt <= 2'd0;
            else if (dec_cnt != DEC_N) dec_cnt <= dec_cnt + 2'd1;
            case (st)
            // ---------------------------------------------------------- reset: clear D0-D3, A0-A3 (MAME device_reset)
            S_CLR: begin
                `MN102_WR(rf_wa + (rf_we ? 3'd1 : 3'd0), 24'h0)
                if (rf_we && rf_wa == 3'd6) st <= S_FETCH;
            end
            // ---------------------------------------------------------- interrupt entry
            // PC (24 bits) at A3-4, PSW at A3-6, A3 -= 6, PC = 0x080008,
            // PSW.IE = 0, PSW.IM = level, IAGR = group, 7 cycles (design study 4.2)
            S_IRQ1: `MN102_MEM(agu, 2'd2, 1'b1, {8'h0, psw}, S_IRQ2)
            S_IRQ2: begin
                `MN102_WR(3'd7, agu)
                pc <= 24'h080008;
                // MAME take_irq: psw = (psw & 0xf0ff) | level << 8, which clears IE
                // (bit 11) too; the MN102H manual also clears IE on acceptance.
                psw[11:8] <= {1'b0, irq_lvl_q};
                irq_take <= 1'b1;
                irq_take_group <= irq_grp_q;
                irq7 <= 1'b1;
                irq_skip <= 1'b1;
                if (DEBUG) cycles <= cycles + 48'd7;
                st <= S_FETCH;
                nb <= 3'd0;
                f_done <= 1'b0;
            end
            // ---------------------------------------------------------- fetch, boundary
            S_FETCH: begin
                if (!f_done) begin
                    if (f_hit || f_ack) begin
                        if (!fpos[0]) begin
                            case (nb)
                                3'd0: begin ib0 <= f_word[7:0]; ib1 <= f_word[15:8]; end
                                3'd1: begin ib1 <= f_word[7:0]; ib2 <= f_word[15:8]; end
                                3'd2: begin ib2 <= f_word[7:0]; ib3 <= f_word[15:8]; end
                                3'd3: begin ib3 <= f_word[7:0]; ib4 <= f_word[15:8]; end
                                default: ib4 <= f_word[7:0];
                            endcase
                        end else begin
                            case (nb)
                                3'd0: ib0 <= f_word[15:8];
                                3'd1: ib1 <= f_word[15:8];
                                3'd2: ib2 <= f_word[15:8];
                                3'd3: ib3 <= f_word[15:8];
                                default: ib4 <= f_word[15:8];
                            endcase
                        end
                        nb <= nb + f_take;
                        if (nb + f_take >= f_len) f_done <= 1'b1;
                        if (f_ack) begin
                            bus_rd <= 1'b0;
                            fbuf <= bus_rdata;
                            fbuf_wa <= fpos[23:1];
                            fbuf_v <= 1'b1;
                        end
                    end else if (!bus_rd) begin
                        bus_addr <= {fpos[23:1], 1'b0};
                        bus_be <= 2'b11;
                        bus_rd <= 1'b1;
                    end
                end else if (chk_now) begin
                    // MAME samples interrupts only when m_possible_irq is set
                    // (mn10200.cpp execute_run); the core keeps the same flag.
                    // pirq_set arrives registered, in the clock tmr_busy drops.
                    irq_skip <= 1'b0;
                    if (!irq_skip && pirq) pirq <= 1'b0;
                    if (!irq_skip && (pirq || i_pset) && (i_nmi || (psw[11] && i_cand))) begin
                        irq_lvl_q <= i_cand ? i_lvl : 3'd0;
                        irq_grp_q <= i_nmi ? 4'd0 : i_grp;
                        `MN102_MEM(agu, 2'd3, 1'b1, pc, S_IRQ1)
                    end else begin
                        st <= S_EXEC;
                        dbg_insn <= 1'b1;
                    end
                end
            end
            // ---------------------------------------------------------- execute
            S_EXEC: begin
                kind_q <= c_kind;
                pc_next <= pc_seq;
                case (c_kind)
                    K_ALU: begin
                        case (c_wb)
                            W_REG: `MN102_WR({c_dsta, f10}, alu_r)
                            W_MDR: mdr <= alu_b[15:0];
                            W_MDREXT: mdr <= {16{alu_b[15]}};
                            default: ;
                        endcase
                        if (c_wb == W_PSW) begin
                            psw <= alu_r[15:0];
                            // MAME sets m_possible_irq on MOV Dn,PSW and OR imm16,PSW, not on AND imm16,PSW
                            if (c_alu != A_AND) pirq <= 1'b1;
                        end else begin
                            psw[7:0] <= alu_f;
                        end
                        `MN102_RETIRE(pc_seq, 1'b0)
                    end
                    K_LD, K_BSET, K_BCLR: `MN102_MEM(agu, c_mw, 1'b0, 24'h0, S_EXEC2)
                    K_ST: `MN102_MEM(agu, c_mw, 1'b1, r_dst, S_RET)
                    K_MUL, K_MULU: begin
                        md_signed <= (c_kind == K_MUL);
                        md_m <= r_dst[15:0];
                        md_q <= r_src[15:0];
                        md_acc <= 16'h0;
                        md_n <= 5'd0;
                        st <= S_MD;
                    end
                    K_DIVU: begin
                        // n = MDR:Dm, d = Dn; overflow (q >= 0x10000, includes d = 0)
                        // exactly when MDR >= d. MAME: VF set, Dm and MDR unchanged.
                        md_signed <= 1'b0;
                        md_m <= r_src[15:0];
                        md_q <= r_dst[15:0];
                        md_acc <= mdr;
                        md_n <= 5'd0;
                        if (PIPE ? div_ovf_q : (mdr >= r_src[15:0])) begin
                            psw[7:0] <= 8'h08;
                            st <= S_RET;
                        end else begin
                            st <= S_MD;
                        end
                    end
                    K_BCC: `MN102_RETIRE(taken_c ? agu : pc_seq, taken_c)
                    K_JMP: `MN102_RETIRE(agu, 1'b0)
                    K_JMPA: `MN102_RETIRE(r_an, 1'b0)
                    K_JSR: begin pc_next <= agu; st <= S_PUSH; end
                    K_JSRA: begin pc_next <= r_an; st <= S_PUSH; end
                    K_RTS: `MN102_MEM(r_an, 2'd3, 1'b0, 24'h0, S_EXEC2)
                    K_RTI: `MN102_MEM(r_an, 2'd2, 1'b0, 24'h0, S_EXEC2)
                    default: begin
                        // undefined opcode: MAME sets NMICR bit 1 (illegal()) and re-checks
                        // synthesis translate_off
                        $error("MN10200: undefined opcode %02x %02x at %06x", ib0, ib1, pc);
                        // synthesis translate_on
                        ill <= 1'b1;
                        pirq <= 1'b1;
                        `MN102_RETIRE(pc_seq, 1'b0)
                    end
                endcase
            end
            S_PUSH: `MN102_MEM(agu, 2'd3, 1'b1, pc_seq, S_EXEC2)   // return address at A3 - 4
            S_EXEC2: begin
                case (kind_q)
                    K_LD: begin
                        case (c_mw)
                            2'd1: `MN102_WR({c_dsta, f10}, c_msx ? {{16{md[7]}}, md[7:0]} : {16'h0, md[7:0]})
                            2'd2: `MN102_WR({c_dsta, f10}, {{8{md[15]}}, md[15:0]})
                            default: `MN102_WR({c_dsta, f10}, md)
                        endcase
                        st <= S_RET;
                    end
                    K_BSET, K_BCLR: begin
                        // flags from (byte & Dm) on 16 bits: NF = 0, ZF, CF = VF = 0 (MAME test_nz16)
                        psw[3:0] <= {3'b000, (md[7:0] & r_dst[7:0]) == 8'h0};
                        `MN102_MEM(agu, 2'd1, 1'b1,
                                  {16'h0, (kind_q == K_BSET) ? (md[7:0] | r_dst[7:0]) : (md[7:0] & ~r_dst[7:0])},
                                  S_RET)
                    end
                    K_JSR, K_JSRA: begin `MN102_WR(3'd7, agu) st <= S_RET; end
                    K_RTS: begin pc_next <= md; `MN102_WR(3'd7, agu) st <= S_RET; end
                    K_RTI: begin
                        psw <= md[15:0];
                        `MN102_MEM(agu, 2'd3, 1'b0, 24'h0, S_EXEC3)
                    end
                    default: st <= S_RET;
                endcase
            end
            S_EXEC3: begin   // RTI tail
                pc_next <= md;
                `MN102_WR(3'd7, agu)
                pirq <= 1'b1;
                st <= S_RET;
            end
            // ---------------------------------------------------------- multiply / divide
            S_MD: begin
                if (kind_q == K_DIVU) begin
                    md_acc <= div_ge ? div_d[15:0] : div_t[15:0];
                    md_q <= {md_q[14:0], div_ge};
                end else begin
                    md_acc <= mul_sum[16:1];
                    md_q <= {mul_sum[0], md_q[15:1]};
                end
                md_n <= md_n + 5'd1;
                if (md_n == 5'd15) st <= S_MDF;
            end
            S_MDF: begin
                // MAME: PSW &= 0xff00 first. MUL/MULU: NF = bit 31, else ZF if the
                // 32-bit product is 0; Dm = product[23:0], MDR = product[31:16].
                // DIVU: Dm = quotient, MDR = remainder, ZF and ZX if 0, NF = bit 15.
                if (kind_q == K_DIVU) begin
                    `MN102_WR({1'b0, f10}, {8'h0, md_q})
                    mdr <= md_acc;
                    psw[7:0] <= {3'b000, md_q == 16'h0, 2'b00, md_q[15], md_q == 16'h0};
                end else begin
                    `MN102_WR({1'b0, f10}, {md_acc[7:0], md_q})
                    mdr <= md_acc;
                    psw[7:0] <= {6'b000000, md_acc[15], ~md_acc[15] & ({md_acc, md_q} == 32'h0)};
                end
                st <= S_RET;
            end
            S_RET: `MN102_RETIRE(pc_next, 1'b0)
            // ---------------------------------------------------------- memory
            S_MEM: begin
                if (ph_fin) begin
                    if (m_busy) begin
                        bus_rd <= 1'b0;
                        bus_wr <= 1'b0;
                        m_busy <= 1'b0;
                    end
                    if (!m_ph) md[15:0] <= (m_w == 2'd1) ? {8'h0, m_addr[0] ? ph_rd[15:8] : ph_rd[7:0]} : ph_rd;
                    else md[23:16] <= ph_rd[7:0];
                    if (m_w == 2'd3 && !m_ph) begin
                        m_ph <= 1'b1;
                        m_addr <= agu;
                    end else begin
                        st <= m_ret;
                    end
                end else if (!m_busy && !ph_io && !pf_busy) begin
                    bus_addr <= ph_addr;
                    bus_be <= ph_be;
                    bus_wdata <= ph_wd;
                    bus_rd <= !m_we;
                    bus_wr <= m_we;
                    m_busy <= 1'b1;
                    if (m_we && fbuf_wa == ph_addr[23:1]) fbuf_v <= 1'b0;
                    if (m_we && pbuf_wa == ph_addr[23:1]) pbuf_v <= 1'b0;
                end
            end
            default: st <= S_FETCH;
            endcase
        end
    end
endmodule
`undef MN102_MEM
`undef MN102_RETIRE
`undef MN102_WR
