// TI TMS57002 "DASP" effects DSP for the Taito Zoom sound board (FC PCB).
// Own implementation from docs/zoom_zsg2_tms57002_design.md and the
// TMS57002 User's Guide (TI 1992, "guide" below); MAME 0.288
// (src/devices/cpu/tms57002 at tag mame0288) is used only where the guide is silent,
// and the comments say so. Status and verification: docs/tms57002_rtl.md.
//
// Scope: the instructions and modes of the two programs the Zoom firmware
// downloads (design study 4.3): 16 primary, 18 secondary and 3 category 3
// opcodes, no branches other than IDLE, no RPTK, DMEM0 only (DBP = 0), the
// external RAM in 64K / 8-bit port / 16-bit word mode (ST0 = 0x0084AA),
// output on SO1 only. Anything else sets dbg_unsup (and prints once in
// simulation); the core then carries on as if the word were a NOP.
//
// Timing: one instruction slot per `step` pulse (the 12.5 MHz instruction
// cycle, 384 per sample), executed in two clocks (RUN: operand addresses,
// EXEC: datapath and write back), so clk must be at least twice the slot
// rate (G-NET clk_1x 33.8688 MHz: 16.9 M slots/s against 12.5 M needed).
// Slots that arrive while an instruction is in flight are banked in a
// credit counter. `sync` is the sample boundary: it is applied after the
// slots banked before it and before any granted after it (guide 3.6.6).
//
// Parameters select MAME 0.288 behaviour where it differs from the guide,
// for the bit-exact replay against MAME (sim/tms57002/tb.cpp):
//   XM_CYCLES       external RAM access length in slots: 6 = guide (DRAM,
//                   8-bit port, 16-bit word: 2(m+1), p.3-72); 2 = MAME
//                   (one byte per executed instruction, tms57002.cpp:852)
//   XM_COUNT_IDLE   1 = the access runs on in idle slots (guide: machine
//                   cycles); 0 = only executed instructions advance it (MAME)
//   UPD_AFTER_CLOAD 1 = a CMEM update starts only at a CMEM read after
//                   CLOAD has returned high (guide p.3-43); 0 = as soon as
//                   the word is complete (MAME tms57002.cpp:146, 685)
//   MPY_A32         0 = MPY/MAC with AACC use AACC bits 31-8 as the 24-bit
//                   multiplier input (guide p.3-22, Fig. 3-10: 32 x 25
//                   array); 1 = the full 32-bit AACC, product >> 15 (MAME
//                   tmsinstr.lst:301-305, 266-270)
//   SI_RAW          0 = with ST0.SIM = 1 the serial words are 16 bits and
//                   the low 8 bits read 0 (guide p.3-32); 1 = all 24 input
//                   bits pass (MAME's float route can set bit 7, see the doc)
module tms57002 #(
    parameter int XM_CYCLES       = 6,
    parameter bit XM_COUNT_IDLE   = 1,
    parameter bit UPD_AFTER_CLOAD = 1,
    parameter bit MPY_A32         = 0,
    parameter bit SI_RAW          = 0
) (
    input  logic        clk,
    input  logic        rst,            // RS (active high here)
    input  logic        step,           // pulse: one instruction slot
    input  logic        sync,           // pulse: sample boundary (SYNC)
    // host interface (MN10200 data port 0xC00000 and port 1)
    input  logic        host_wr,        // pulse: byte write
    input  logic [7:0]  host_din,
    input  logic        pload_n,        // PLOAD pin level (0 = ST0/ST1/PMEM or CMEM download)
    input  logic        cload_n,        // CLOAD pin level (0 = CMEM download or update)
    output logic        empty,          // EMPTY pin: all UPDATE registers empty
    // serial ports, one word per channel and sample, MSB aligned
    input  logic [23:0] si0_l,
    input  logic [23:0] si0_r,
    input  logic [23:0] si1_l,
    input  logic [23:0] si1_r,
    output logic [23:0] so1_l,          // SO1 words latched at sync, 24 bits
    output logic [23:0] so1_r,
    output logic [15:0] so1_l16,        // SOM = 2: the 16-bit words on SO1
    output logic [15:0] so1_r16,
    // debug
    input  logic        dbg_hold,       // testbench: start no slot (tie 0)
    output logic        dbg_idle,       // halted by IDLE (or never started)
    output logic        busy,           // a slot, SYNC, host byte or pin change given and not yet taken
                                        // (the Zoom board delivers a host event only when low)
    output logic [7:0]  dbg_pc,
    output logic        dbg_unsup       // sticky: unimplemented instruction or mode
);
    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    typedef enum logic [1:0] { PH_RUN, PH_FETCH, PH_EXEC } ph_t;
    ph_t         ph;

    logic [23:0] st0, st1;              // Fig. 3-24 p.3-31
    logic [7:0]  pc, ca, id, ba0;
    logic [18:0] xba;                   // external RAM base (p.3-66); 15 bits used in 64K mode
    logic [31:0] aacc;
    logic [51:0] macc;                  // 52-bit MACC (p.3-18)
    logic [51:0] mw;                    // MACC as the previous instruction saw it (p.3-28 note)
    logic [23:0] xrd;                   // external RAM read buffer
    logic [2:0]  xm_cnt;                // slots until the running RDE/WRE completes
    logic        xm_rd;                 // the running access is a read
    logic [23:0] si [0:3];
    logic [23:0] si_sync [0:3];         // serial inputs taken at the sync pulse, applied with the sync
    logic [23:0] so2, so3;              // SO1 left / right registers
    logic        halted;                // IDLE executed or reset, until the next sync
    logic        ir_valid;              // pmem_q holds PMEM[pc]
    logic [23:0] ir;                    // instruction in EXEC
    logic [3:0]  credit;                // slots granted and not yet used
    logic [3:0]  pend;                  // of those, slots that precede the pending sync
    logic        sync_req;
    logic        host_req;
    logic [7:0]  host_byte;
    logic        pload_q, cload_q;      // pin levels as last processed (1 = high)
    logic [1:0]  hidx;
    logic [23:0] hbuf;
    logic [1:0]  su;                    // download target: 0 ST0, 1 ST1, 2 PMEM
    logic [7:0]  sa;
    logic        expect_sa;
    logic [3:0]  upd_head, upd_tail;
    logic [4:0]  upd_cnt;
    logic        upd_active;            // an update sequence has started (p.3-43)
    logic        unsup;
    logic        mode_unsup;
    logic [7:0]  dmem_ra_x;
    logic [23:0] si_in [0:3];

    // ------------------------------------------------------------------
    // Memories: PMEM 256 x 24, CMEM 256 x 32, DMEM0 256 x 24 (M10K), the
    // 16 UPDATE registers (MLAB) and the 32K x 16 delay RAM (64 M10K).
    // Synchronous reads with read enables: the data stay until the next read.
    // ------------------------------------------------------------------
    logic [23:0] pmem [0:255];
    logic [31:0] cmem [0:255];
    logic [23:0] dmem [0:255];
    logic [31:0] upd  [0:15];
    logic        pmem_re, pmem_we, cmem_re, cmem_we, dmem_re, dmem_we, upd_we;
    logic [7:0]  pmem_ra, pmem_wa, cmem_ra, cmem_wa, dmem_ra, dmem_wa;
    logic [23:0] pmem_q, pmem_wd, dmem_q, dmem_wd;
    logic [31:0] cmem_q, cmem_wd, upd_q, upd_wd;
    // EXEC writes CMEM / DMEM at its own clock edge (combinational port
    // control), so an instruction that starts right after reads the new
    // data; host CMEM downloads (core stopped) use the registered h_ port.
    logic        h_cmem_we;
    logic [7:0]  h_cmem_wa;
    logic [31:0] h_cmem_wd;
    logic [3:0]  upd_wa;
    logic        xram_en, xram_we;
    logic [14:0] xram_a;
    logic [15:0] xram_d, xram_q;

    always_ff @(posedge clk) begin
        if (pmem_we) pmem[pmem_wa] <= pmem_wd;
        if (pmem_re) pmem_q <= pmem[pmem_ra];
    end
    always_ff @(posedge clk) begin
        if (cmem_we) cmem[cmem_wa] <= cmem_wd;
        if (cmem_re) cmem_q <= cmem[cmem_ra];
    end
    always_ff @(posedge clk) begin
        if (dmem_we) dmem[dmem_wa] <= dmem_wd;
        if (dmem_re) dmem_q <= dmem[dmem_ra];
    end
    always_ff @(posedge clk) begin
        if (upd_we) upd[upd_wa] <= upd_wd;
        upd_q <= upd[upd_tail];
    end
    tms57002_xram u_xram (.clk, .en(xram_en), .we(xram_we), .a(xram_a), .d(xram_d), .q(xram_q));

    // ------------------------------------------------------------------
    // Decode (guide 4.2, Fig. 4-2 and 4-3): bits 23:18 primary (0x3F:
    // category 3), 17:11 secondary or category 3 opcode, bit 10 D (memory
    // X is CMEM), 9 E (memory Y post increment), 8 F (memory X direct),
    // 7:0 G (direct address; indirect: bit 7 = X post increment).
    // Opcode numbers as in MAME's tmsinstr.lst.
    // ------------------------------------------------------------------
    typedef struct packed {
        logic       cat3;
        logic [5:0] p;
        logic [6:0] s;
        logic       rd_c, rd_d;         // the primary reads CMEM / DMEM
        logic       wr_c, wr_d;         // the secondary writes CMEM / DMEM
        logic       c_dir, d_dir;
        logic       inc_ca, inc_id;
        logic       known;
    } dec_t;

    function automatic dec_t decode(input logic [23:0] w);
        dec_t r;
        logic xc, xinc;
        r = '0;
        r.cat3 = (w[23:18] == 6'h3f);
        r.p = r.cat3 ? 6'h00 : w[23:18];
        r.s = w[17:11];
        if (r.cat3) begin
            r.known = (r.s == 7'h08) || (r.s == 7'h18) || (r.s == 7'h20);   // idle, lcak, lirk
        end else begin
            case (r.p)
                6'h04, 6'h06, 6'h12, 6'h15, 6'h22, 6'h26, 6'h39: r.rd_c = 1'b1;
                6'h05, 6'h09, 6'h11, 6'h31:                      r.rd_d = 1'b1;
                6'h21, 6'h24, 6'h38:                             begin r.rd_c = 1'b1; r.rd_d = 1'b1; end
                default: ;
            endcase
            case (r.s)
                7'h01, 7'h05:                                    r.wr_c = 1'b1;     // sacc, smhc
                7'h02, 7'h03, 7'h06, 7'h07, 7'h0f,
                7'h10, 7'h11, 7'h12, 7'h13:                      r.wr_d = 1'b1;     // sacd smhd slmh slml srbd dis
                default: ;
            endcase
            case (r.p)
                6'h00, 6'h01, 6'h04, 6'h05, 6'h06, 6'h09, 6'h11, 6'h12, 6'h15,
                6'h21, 6'h22, 6'h24, 6'h26, 6'h31, 6'h35, 6'h38, 6'h39: r.known = 1'b1;
                default: r.known = 1'b0;
            endcase
            case (r.s)
                7'h00, 7'h01, 7'h02, 7'h03, 7'h05, 7'h06, 7'h07, 7'h0f,
                7'h10, 7'h11, 7'h12, 7'h13, 7'h22, 7'h23,
                7'h3c, 7'h3d, 7'h60, 7'h61, 7'h62, 7'h63: ;
                default: r.known = 1'b0;
            endcase
            xc   = w[10];
            xinc = !w[8] && w[7];
            r.c_dir = xc && w[8];
            r.d_dir = !xc && w[8];
            // Post increments apply to an operand the word references
            // (MAME tms57kdec.cpp:15-30; the guide is silent; both programs
            // set E or P only on referenced operands, docs/tms57002_rtl.md).
            r.inc_ca = (r.rd_c || r.wr_c) && (xc ? xinc : w[9]);
            r.inc_id = (r.rd_d || r.wr_d) && (xc ? w[9] : xinc);
        end
        return r;
    endfunction

    dec_t dr, dx;                       // dr: word at pmem_q (RUN), dx: word in EXEC
    assign dr = decode(pmem_q);
    assign dx = decode(ir);

    // ------------------------------------------------------------------
    // MACC output paths (p.3-22, 3-23): output shifter (SFMO), rounder
    // (RND) and overflow limiter (MOVM) for DOMH / SMHD / SMHC and the
    // ALU's MACC operand; overflow check and limiter only for SLMH / SLML.
    // Both read mw, the MACC value one instruction old (p.3-28 note).
    // ------------------------------------------------------------------
    localparam logic [57:0] SAT_POS = {11'h000, {47{1'b1}}};
    localparam logic [57:0] SAT_NEG = {{11{1'b1}}, 47'h0};

    function automatic logic uni(input logic [8:0] v, input int n);   // top n bits of v equal
        logic [8:0] m;
        m = 9'h1ff << (9 - n);
        return ((v & m) == 9'h000) || ((v & m) == m);
    endfunction

    logic [57:0] mo, mv, mo_sh, mo_rd, mw58;
    logic        mo_ov, mv_ov;
    always_comb begin
        logic ov1;
        mw58 = {{6{mw[51]}}, mw};
        unique case (st1[12:11])
            2'd0: begin ov1 = !uni(mw[51:43], 5); mo_sh = mw58; end
            2'd1: begin ov1 = !uni(mw[51:43], 7); mo_sh = mw58 << 2; end
            2'd2: begin ov1 = !uni(mw[51:43], 9); mo_sh = mw58 << 4; end
            default: begin ov1 = 1'b0; mo_sh = $signed(mw58) >>> 8; end
        endcase
        // RND 1 rounds to 32 bits (bit 15, MAME tmsmake.py:48); RND 0 is 48 bits
        mo_rd = (st1[17:15] == 3'd1) ? ((mo_sh + 58'h8000) & ~58'hffff) : mo_sh;
        mo_ov = ov1 || !uni(mo_rd[51:43], 5);
        mo = (mo_ov && st1[5]) ? (mo_rd[51] ? SAT_NEG : SAT_POS) : mo_rd;
        mv_ov = ov1;
        mv = (mv_ov && st1[5]) ? (mw[51] ? SAT_NEG : SAT_POS) : mw58;
    end

    // ------------------------------------------------------------------
    // EXEC datapath
    // ------------------------------------------------------------------
    logic        xm_busy;
    logic        upd_take;
    logic [23:0] d24, dwr;
    logic [31:0] cop, cwr;
    logic        mo_used, mv_used;
    logic [31:0] aacc_n;
    logic        aov_set, wa;
    logic [51:0] macc_n, prod;
    logic        macc_we;
    logic [42:0] r43;
    logic [14:0] xaddr;

    assign xm_busy = (xm_cnt != 3'd0);

    always_comb begin
        logic [56:0] p57;
        logic [63:0] p64;
        logic [24:0] mb;
        logic [41:0] m16;
        // secondary (category 2) results first: they use the old AACC and MACC
        // and own the bus, so a primary reading the same operand sees them
        // (guide p.4-2; MAME runs them first, tmsmake.py EmitCdec)
        p64 = '0; macc_n = macc; macc_we = 1'b0; xaddr = '0;
        dwr = 24'h0; cwr = 32'h0; mo_used = 1'b0; mv_used = 1'b0;
        case (dx.s)
            7'h01: cwr = aacc;                                  // sacc
            7'h05: begin cwr = mo[47:16]; mo_used = 1'b1; end   // smhc
            7'h02: dwr = aacc[31:8];                            // sacd
            7'h03: begin dwr = mo[47:24]; mo_used = 1'b1; end   // smhd
            7'h06: begin dwr = {mv[47:32], 8'h00}; mv_used = 1'b1; end  // slmh
            7'h07: begin dwr = mv[31:8]; mv_used = 1'b1; end    // slml
            7'h0f: dwr = xrd;                                   // srbd
            7'h10: dwr = si[0];                                 // dis si0_l
            7'h11: dwr = si[1];
            7'h12: dwr = si[2];
            7'h13: dwr = si[3];
            7'h22, 7'h23: mo_used = 1'b1;                       // domh so1_l / so1_r
            default: ;
        endcase
        if (dx.cat3) begin dwr = 24'h0; cwr = 32'h0; mo_used = 1'b0; mv_used = 1'b0; end

        d24 = (dx.wr_d) ? dwr : dmem_q;
        // CMEM update (p.3-43): the UPDATE word replaces the CMEM read. An
        // RDE / WRE ignored while the external RAM is busy reads no CMEM.
        upd_take = !dx.cat3 && dx.rd_c && !((dx.p == 6'h38 || dx.p == 6'h39) && xm_busy) &&
                   (upd_cnt != 5'd0) &&
                   (upd_active || ((dx.c_dir ? ir[7:0] : ca) == sa && (cload_q || !UPD_AFTER_CLOAD)));
        cop = upd_take ? upd_q : (dx.wr_c ? cwr : cmem_q);

        // primary: ALU (p.3-16)
        m16 = 42'($signed(mo) >>> 16);
        r43 = '0; wa = 1'b0; aacc_n = aacc; aov_set = 1'b0;
        case (dx.p)
            6'h01: begin                                        // abs
                aacc_n = aacc[31] ? -aacc : aacc;
                aov_set = aacc[31] && aacc_n[31];
            end
            6'h04: begin r43 = 43'($signed(cop)) + 43'($signed(aacc)); wa = 1'b1; end          // add c,a
            6'h05: begin r43 = 43'($signed({d24, 8'h00})) + 43'($signed(m16)); wa = 1'b1; end  // add d,m
            6'h06: begin r43 = 43'($signed(cop)) + 43'($signed(m16)); wa = 1'b1; end           // add c,m
            6'h09: begin r43 = 43'($signed({d24, 8'h00})) - 43'($signed(aacc)); wa = 1'b1; end // sub d,a
            6'h11: aacc_n = {d24, 8'h00};                       // lacd
            6'h12: aacc_n = cop;                                // lacc
            6'h15: aacc_n = aacc & cop;                         // and c,a
            default: ;
        endcase
        if (wa) begin
            // 32-bit overflow sets AOV; ST1 bit 3 (MAME's AOVM, set by SAOM)
            // saturates. Bit 3 is "reserved" in Fig. 3-24 and SAOM / RAOM are
            // not in the guide: MAME tmsmake.py:70 and tmsinstr.lst:549.
            aacc_n = r43[31:0];
            if ($signed(r43) > 43'sh7fffffff || $signed(r43) < -43'sh80000000) begin
                aov_set = 1'b1;
                if (st1[3]) aacc_n = r43[42] ? 32'h80000000 : 32'h7fffffff;
            end
        end
        if (dx.cat3) begin aacc_n = aacc; aov_set = 1'b0; end

        // primary: MAC (p.3-18 to 3-22): CREG (32) x DREG (24, sign
        // extended to 25), MSB and 7 LSBs dropped from the 57-bit product,
        // sign extended to 52 bits. With AACC as DREG input, bits 31-8.
        mb = (dx.p == 6'h22 || dx.p == 6'h26) ? {aacc[31], aacc[31:8]} : {d24[23], d24};
        p57 = 57'($signed(cop) * $signed(mb));
        prod = {{3{p57[55]}}, p57[55:7]};
        if (MPY_A32 && (dx.p == 6'h22 || dx.p == 6'h26)) begin
            p64 = 64'($signed(cop) * $signed(aacc));
            prod = 52'($signed(p64) >>> 15);
        end
        macc_we = 1'b1;
        case (dx.p)
            6'h21, 6'h22: macc_n = prod;                        // mpy d,c / mpy c,a
            6'h24, 6'h26: macc_n = macc + prod;                 // mac d,c / mac c,a (SFMA = 0)
            6'h31: macc_n = {{4{d24[23]}}, d24, 24'h0};         // lmhd
            6'h35: macc_n = {macc[51], macc[51:1]};             // sfmr
            default: begin macc_n = macc; macc_we = 1'b0; end
        endcase
        if (dx.cat3) begin macc_n = macc; macc_we = 1'b0; end

        // external RAM address (p.3-66): XBA + XOA, 15 bits in 64K / 16-bit mode
        xaddr = 15'(cop[14:0] + xba[14:0]);
    end

    // ------------------------------------------------------------------
    // Sequencer, host interface, memories' port control
    // ------------------------------------------------------------------
    logic start_insn;                   // RUN: an instruction slot starts executing
    logic slot_take;                    // RUN: a slot is consumed
    logic pin_evt;
    logic run_ok;
    assign pin_evt = (pload_n != pload_q) || (cload_n != cload_q);
    assign run_ok = !halted && pload_q;

    always_comb begin
        start_insn = 1'b0; slot_take = 1'b0;
        if (ph == PH_RUN && !pin_evt && !host_req && !dbg_hold && credit != 4'd0 && (!sync_req || pend != 4'd0)) begin
            if (!run_ok) slot_take = 1'b1;
            else if (ir_valid) begin slot_take = 1'b1; start_insn = 1'b1; end
        end
    end

    // memory read ports
    always_comb begin
        pmem_re = 1'b0; pmem_ra = pc;
        cmem_re = 1'b0; cmem_ra = dr.c_dir ? pmem_q[7:0] : ca;
        dmem_re = 1'b0; dmem_ra = 8'((dr.d_dir ? pmem_q[7:0] : id) + ba0);
        if (ph == PH_FETCH || (ph == PH_RUN && run_ok && !ir_valid)) begin
            pmem_re = (ph == PH_RUN);
        end
        if (start_insn) begin
            cmem_re = 1'b1;
            dmem_re = 1'b1;
        end
        if (ph == PH_EXEC) begin
            pmem_re = 1'b1; pmem_ra = pc + 8'd1;  // prefetch the next word
        end
    end

    always_ff @(posedge clk) begin
        // defaults for one-clock strobes
        pmem_we <= 1'b0; h_cmem_we <= 1'b0; upd_we <= 1'b0;
        xram_en <= 1'b0; xram_we <= 1'b0;

        if (rst) begin
            // RS (p.3-34) plus MAME tms57002.cpp:76-102 for what the guide omits
            ph <= PH_RUN;
            pc <= 8'h00; ca <= 8'h00; id <= 8'h00; ba0 <= 8'h00; xba <= 19'h0;
            st0 <= st0 & 24'h23c000;            // keep M, SEL, WORD, SRAM
            st1 <= st1 & 24'h200000;            // keep CAS
            halted <= 1'b1; ir_valid <= 1'b0;
            credit <= 4'd0; pend <= 4'd0; sync_req <= 1'b0; host_req <= 1'b0;
            pload_q <= 1'b1; cload_q <= 1'b1;
            hidx <= 2'd0; su <= 2'd0; sa <= 8'h00; expect_sa <= 1'b1;
            upd_head <= 4'd0; upd_tail <= 4'd0; upd_cnt <= 5'd0; upd_active <= 1'b0;
            xm_cnt <= 3'd0; xm_rd <= 1'b0;
            so1_l <= 24'h0; so1_r <= 24'h0;
            unsup <= 1'b0;
        end else begin
            case (ph)
            PH_RUN: begin
                if (pin_evt) begin
                    // MAME tms57002.cpp:40-74: PLOAD low restarts the download
                    // at ST0 and resets PC and CA; CLOAD low expects SA next.
                    if (!pload_n && pload_q) begin
                        hidx <= 2'd0; pc <= 8'h00; ca <= 8'h00; su <= 2'd0; ir_valid <= 1'b0;
                    end
                    if (!cload_n && cload_q) begin hidx <= 2'd0; expect_sa <= 1'b1; end
                    pload_q <= pload_n; cload_q <= cload_n;
                end else if (host_req) begin
                    host_req <= 1'b0;
                    if (!pload_q && cload_q) begin
                        // ST0, ST1, PMEM: 3 bytes MSB first (p.3-39, 3-40)
                        hbuf <= {hbuf[15:0], host_byte};
                        hidx <= (hidx == 2'd2) ? 2'd0 : hidx + 2'd1;
                        if (hidx == 2'd2) begin
                            case (su)
                                2'd0: begin st0 <= {hbuf[15:0], host_byte}; su <= 2'd1; end
                                2'd1: begin st1 <= {hbuf[15:0], host_byte}; su <= 2'd2; end
                                default: begin
                                    pmem_we <= 1'b1; pmem_wa <= pc; pmem_wd <= {hbuf[15:0], host_byte};
                                    pc <= pc + 8'd1;
                                end
                            endcase
                        end
                    end else if (!pload_q && !cload_q) begin
                        // CMEM download: 4 bytes MSB first (p.3-41)
                        hbuf <= {hbuf[15:0], host_byte};
                        hidx <= hidx + 2'd1;
                        if (hidx == 2'd3) begin
                            h_cmem_we <= 1'b1; h_cmem_wa <= ca; h_cmem_wd <= {hbuf, host_byte};
                            ca <= ca + 8'd1;
                        end
                    end else if (pload_q && !cload_q) begin
                        // CMEM update: SA, then up to 16 words (p.3-42)
                        if (expect_sa) begin
                            sa <= host_byte; expect_sa <= 1'b0; hidx <= 2'd0;
                        end else begin
                            hbuf <= {hbuf[15:0], host_byte};
                            hidx <= hidx + 2'd1;
                            if (hidx == 2'd3 && upd_cnt != 5'd16) begin
                                upd_we <= 1'b1; upd_wa <= upd_head; upd_wd <= {hbuf, host_byte};
                                upd_head <= upd_head + 4'd1;
                                upd_cnt <= upd_cnt + 5'd1;
                            end
                        end
                    end
                    // normal mode: writes are ignored (p.3-37)
                end else if (sync_req && pend == 4'd0) begin
                    // SYNC (p.3-36, 3-66). Ignored while PLOAD is low (MAME
                    // tms57002.cpp:220; the guide is silent).
                    sync_req <= 1'b0;
                    for (int k = 0; k < 4; k++) si[k] <= si_sync[k];
                    so1_l <= so2; so1_r <= so3;
                    if (pload_q) begin
                        pc <= 8'h00; ca <= 8'h00; id <= 8'h00;
                        if (!st0[0]) ba0 <= ba0 - 8'd1;
                        xba <= xba - 19'd1;
                        st1[0] <= 1'b0; st1[6] <= 1'b0;
                        halted <= 1'b0; ir_valid <= 1'b0;
                    end
                end else if (slot_take) begin
                    // the running external access advances one slot
                    if (xm_busy && (start_insn || XM_COUNT_IDLE)) begin
                        xm_cnt <= xm_cnt - 3'd1;
                        if (xm_cnt == 3'd1 && xm_rd) xrd <= {xram_q, 8'h00};
                    end
                    if (start_insn) begin
                        ir <= pmem_q;
                        ph <= PH_EXEC;
                    end
                end else if (run_ok && !ir_valid && credit != 4'd0) begin
                    ph <= PH_FETCH;             // pmem read of pc issued this clock
                end
            end
            PH_FETCH: begin
                ir_valid <= 1'b1;
                ph <= PH_RUN;
            end
            PH_EXEC: begin
                ph <= PH_RUN;
                ir_valid <= 1'b1;               // pmem read of pc + 1 issued this clock
                pc <= pc + 8'd1;
                // secondary writes, or the update word into CMEM
                if (upd_take) begin
                    upd_tail <= upd_tail + 4'd1;
                    upd_cnt <= upd_cnt - 5'd1;
                    upd_active <= (upd_cnt != 5'd1);
                end
                case (dx.s)
                    7'h22: if (!dx.cat3) so2 <= mo[47:24];
                    7'h23: if (!dx.cat3) so3 <= mo[47:24];
                    default: ;
                endcase
                // ALU and MAC
                aacc <= aacc_n;
                mw <= macc_we && dx.p == 6'h31 ? macc_n : macc;   // LMHD is seen one instruction later
                macc <= macc_n;
                // ST1: overflow flags, then the secondary mode bits
                if (aov_set) st1[0] <= 1'b1;
                if ((mo_used && mo_ov) || (mv_used && mv_ov)) st1[6] <= 1'b1;
                if (!dx.cat3) case (dx.s)
                    7'h3c: st1[3] <= 1'b0;                      // raom
                    7'h3d: st1[3] <= 1'b1;                      // saom
                    7'h60, 7'h61, 7'h62, 7'h63: st1[12:11] <= dx.s[1:0];  // sfmo 0, 2, 4, -8
                    default: ;
                endcase
                // external RAM (p.3-71, 3-72): ignored while an access runs
                if (!dx.cat3 && (dx.p == 6'h38 || dx.p == 6'h39) && !xm_busy) begin
                    xram_en <= 1'b1;
                    xram_we <= (dx.p == 6'h38);
                    xram_a <= xaddr;
                    xram_d <= d24[23:8];
                    xm_cnt <= 3'(XM_CYCLES);
                    xm_rd <= (dx.p == 6'h39);
                end
                // category 3 and post increments
                if (dx.cat3) begin
                    case (dx.s)
                        7'h08: halted <= 1'b1;                  // idle
                        7'h18: ca <= ir[7:0];                   // lcak
                        7'h20: id <= ir[7:0];                   // lirk
                        default: ;
                    endcase
                end else begin
                    if (dx.inc_ca) ca <= ca + 8'd1;
                    if (dx.inc_id) id <= id + 8'd1;
                end
                if (!dx.known) unsup <= 1'b1;
            end
            default: ph <= PH_RUN;
            endcase
            if (mode_unsup) unsup <= 1'b1;
            // slot accounting: a sync splits the banked slots into those of
            // the old sample (pend, used before the sync applies) and the new
            credit <= credit + ((step && credit != 4'hf) ? 4'd1 : 4'd0) - (slot_take ? 4'd1 : 4'd0);
            if (sync && !sync_req) begin
                sync_req <= 1'b1;
                pend <= credit - (slot_take ? 4'd1 : 4'd0);
                // the serial words belong to the sync pulse, not to the
                // clock in which the banked slots run out and the sync is
                // applied: the source (zoom_board's queue) moves on to the
                // next sample in between
                for (int k = 0; k < 4; k++) si_sync[k] <= si_in[k];
            end else if (slot_take && sync_req) begin
                pend <= pend - 4'd1;
            end
            // requests last: a strobe in the clock that serves the previous one is kept
            if (host_wr) begin host_req <= 1'b1; host_byte <= host_din; end
        end
    end

    // EXEC write ports: the secondary's DMEM / CMEM result, or the update word
    always_comb begin
        dmem_we = (ph == PH_EXEC) && !dx.cat3 && dx.wr_d;
        dmem_wa = dmem_ra_x;
        dmem_wd = dwr;
        if (ph == PH_EXEC) begin
            cmem_we = !dx.cat3 && (upd_take || dx.wr_c);
            cmem_wa = dx.c_dir ? ir[7:0] : ca;
            cmem_wd = cop;
        end else begin
            cmem_we = h_cmem_we; cmem_wa = h_cmem_wa; cmem_wd = h_cmem_wd;
        end
    end

    // DMEM write address of the instruction in EXEC (same operand as its read)
    assign dmem_ra_x = 8'((dx.d_dir ? ir[7:0] : id) + ba0);

    // serial input framing: SIM = 1 takes 16-bit words, the low 8 bits read 0
    always_comb begin
        si_in[0] = si0_l; si_in[1] = si0_r; si_in[2] = si1_l; si_in[3] = si1_r;
        if (st0[3] && !SI_RAW)
            for (int k = 0; k < 4; k++) si_in[k][7:0] = 8'h00;
    end

    // modes outside the implemented set (ST0 = 0x0084AA and ST1 as the programs set it)
    assign mode_unsup = ph == PH_EXEC && ir != 24'h0 && (
        st0[17:16] != 2'd0 || st0[14] || !st0[15] ||             // 64K, 16-bit word, 8-bit port
        st1[1] || st1[2] || st1[8:7] != 2'd0 ||                  // SFAI, SFAO, SFMA
        st1[17:15] > 3'd1 || st1[19:18] != 2'd0 || st1[20]);     // RND, CRM, DBP

    assign empty = (upd_cnt == 5'd0);
    assign so1_l16 = so1_l[23:8];
    assign so1_r16 = so1_r[23:8];
    assign dbg_idle = halted;
    assign busy = step || sync || credit != 4'd0 || sync_req || host_req || pin_evt || ph != PH_RUN;
    assign dbg_pc = pc;
    assign dbg_unsup = unsup;

    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (!rst && ph == PH_EXEC && !dx.known && !unsup)
            $display("tms57002: unimplemented word %06x at pc %02x", ir, pc);
        if (!rst && mode_unsup && !unsup)
            $display("tms57002: unimplemented mode st0 %06x st1 %06x", st0, st1);
        if (!rst && step && credit == 4'hf)
            $display("tms57002: slot credit overflow, a slot was lost");
        if (!rst && ph == PH_EXEC && !dx.cat3 && (dx.s == 7'h20 || dx.s == 7'h21))
            $display("tms57002: domh to SO0 is not implemented (pc %02x)", pc);
    end
    // synthesis translate_on
endmodule

// Delay RAM: 32K x 16 (64 KB, 1.007 s at 32.552 kHz), 64 M10K. Contents
// start at 0 (M10K power-up); the PCB's DRAM starts with noise (design
// study 4.4, Z13).
module tms57002_xram (
    input  logic        clk,
    input  logic        en,
    input  logic        we,
    input  logic [14:0] a,
    input  logic [15:0] d,
    output logic [15:0] q
);
    logic [15:0] mem [0:32767];
    always_ff @(posedge clk) begin
        if (en) begin
            if (we) mem[a] <= d;
            else q <= mem[a];
        end
    end
endmodule
