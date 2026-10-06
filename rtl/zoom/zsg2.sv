// Zoom ZSG-2 wavetable chip for the Taito Zoom sound board (G-NET core).
// Written from docs/zoom_zsg2_tms57002_design.md (sections 3 and 6.2) and
// the behaviour of MAME's zsg2.cpp (0.288 and commit 61c7940); status and
// verification in docs/zsg2_rtl.md.
//
// One shared engine renders the 48 channels in turn for each sample_tick
// (one output sample, 25 MHz / 768 on the board). It uses one 18 x 18
// multiplier, three RAMs (registers, channel state, line buffers) and a
// per-channel 64-bit prefetch line fed by zsg2_fetch.
//
// Ordering (design study 6.1): a CPU write is tagged with the number of
// ticks seen when it arrives and applied after the passes of those ticks
// and before the next one; a CPU read waits until every pass for the ticks
// seen so far and every earlier write are done. The bus therefore sees the
// state MAME shows at the same sample position. A read of a channel the
// running pass has already rendered, or of a global register, is answered
// at the next channel step of that pass (MID_READ = 1): those values are
// final for the tick (only the channel's own step and the CPU writes, which
// wait for the pass, change them), so the answer is the same and the
// MN10200 waits less (docs/zoom_board_design.md 15.3).
module zsg2 #(
    parameter READB_SHIFT = 3,                       // reg 0xB read = vol >> 3 (MAME 61c7940); 0 = MAME 0.288
    parameter logic [23:0] MEM_BLOCKS = 24'h180000,  // 32-bit blocks of wave memory (6 MB)
    parameter WF_AW = 5,                             // CPU write FIFO, 2^WF_AW entries
    parameter RQ_AW = 6,                             // prefetch request queue, 2^RQ_AW entries
    parameter INFL  = 4,                             // memory requests outstanding at most
    parameter MID_READ = 1                           // 1: answer reads of rendered channels inside a pass
) (
    input  logic        clk,
    input  logic        rst,             // Zoom reset: MAME device_reset semantics (zsg2.cpp:193-205)
    // MN10200 bus: 16-bit accesses at 0x800000-0x8007ff; rd/wr held until ack
    input  logic        cpu_rd,
    input  logic        cpu_wr,
    input  logic [9:0]  cpu_addr,        // word offset (byte address bits 10:1)
    input  logic [15:0] cpu_wdata,
    output logic [15:0] cpu_rdata,
    output logic        cpu_ack,
    // time base: one pulse per output sample
    input  logic        sample_tick,
    // outputs after each pass (out_valid one clock): sends 0-3 = reverb,
    // chorus, left direct, right direct; si0-si3 = the TMS57002 serial input
    // words as taito_zm.cpp:205-208 routes them (sends 0/1 at 0.5) with
    // SIM = 1 (tms57002.cpp:927-931)
    output logic        out_valid,
    output logic [15:0] out_send0,
    output logic [15:0] out_send1,
    output logic [15:0] out_send2,
    output logic [15:0] out_send3,
    output logic [23:0] out_si0,
    output logic [23:0] out_si1,
    output logic [23:0] out_si2,
    output logic [23:0] out_si3,
    // wave memory (see zsg2_fetch)
    output logic        mem_req,
    output logic [22:0] mem_addr,
    input  logic        mem_ready,
    input  logic        mem_rvalid,
    input  logic [63:0] mem_rdata,
    // debug
    output logic        dbg_late,        // sticky: a pass waited for a block
    output logic        dbg_overrun,     // sticky: a tick was dropped (3 pending)
    output logic [10:0] dbg_pass_clocks  // clocks of the last pass
);
    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------
    // send gain table: 65535 * 10^(-(31 - i) / 20) truncated, entry 0 = 0
    // (MAME's -1 dB per step law, zsg2.cpp:148-154)
    function automatic logic [15:0] gtab(input logic [4:0] i);
        case (i)
            5'd0:  gtab = 16'd0;     5'd1:  gtab = 16'd2072;  5'd2:  gtab = 16'd2325;  5'd3:  gtab = 16'd2608;
            5'd4:  gtab = 16'd2927;  5'd5:  gtab = 16'd3284;  5'd6:  gtab = 16'd3685;  5'd7:  gtab = 16'd4134;
            5'd8:  gtab = 16'd4639;  5'd9:  gtab = 16'd5205;  5'd10: gtab = 16'd5840;  5'd11: gtab = 16'd6553;
            5'd12: gtab = 16'd7353;  5'd13: gtab = 16'd8250;  5'd14: gtab = 16'd9257;  5'd15: gtab = 16'd10386;
            5'd16: gtab = 16'd11653; 5'd17: gtab = 16'd13075; 5'd18: gtab = 16'd14671; 5'd19: gtab = 16'd16461;
            5'd20: gtab = 16'd18470; 5'd21: gtab = 16'd20723; 5'd22: gtab = 16'd23252; 5'd23: gtab = 16'd26089;
            5'd24: gtab = 16'd29273; 5'd25: gtab = 16'd32845; 5'd26: gtab = 16'd36853; 5'd27: gtab = 16'd41349;
            5'd28: gtab = 16'd46395; 5'd29: gtab = 16'd52056; 5'd30: gtab = 16'd58408; default: gtab = 16'd65535;
        endcase
    endfunction

    // ramp byte to step: low nibble sign-extended, XOR 8, shifted left by
    // the high nibble, truncated to 16 bits, arithmetic shift right 4
    // (zsg2.cpp:494-499)
    function automatic logic [15:0] get_ramp(input logic [7:0] v);
        logic [4:0]  x;
        logic [31:0] w;
        x = {v[3], v[3:0]} ^ 5'b01000;
        w = {{27{x[4]}}, x} << v[7:4];
        get_ramp = {{4{w[15]}}, w[15:4]};
    endfunction

    // one ramp step with clamp at the target (zsg2.cpp:501-510)
    function automatic logic [15:0] ramp(input logic [15:0] cur, input logic [15:0] tgt, input logic [15:0] d);
        logic [17:0] r;
        r = {2'b00, cur} + {{2{d[15]}}, d};
        if (d[15]) ramp = ($signed(r) < $signed({2'b00, tgt})) ? tgt : r[15:0];
        else       ramp = ($signed(r) > $signed({2'b00, tgt})) ? tgt : r[15:0];
    endfunction

    // decode sample i of a block: 42222222 51111111 60000000 ssss3333,
    // 7-bit value left-aligned in 16 bits, arithmetic shift right by s
    // (zsg2.cpp:249-262)
    function automatic logic [15:0] dec(input logic [31:0] b, input logic [1:0] i);
        logic [6:0] r;
        case (i)
            2'd0: r = b[14:8];
            2'd1: r = b[22:16];
            2'd2: r = b[30:24];
            default: r = {b[15], b[23], b[31], b[3:0]};
        endcase
        dec = $signed({r, 9'd0}) >>> b[7:4];
    endfunction

    // position after the next block advance: cur + 1, or the loop point at
    // the end; stop when loop + 1 >= end (zsg2.cpp:301-312). Positions are
    // 17 bits so that start - 1 wraps like MAME's 32-bit cur_pos.
    function automatic logic [17:0] nextpos(input logic [16:0] cur, input logic [15:0] e, input logic [15:0] lp);
        logic [16:0] np;
        logic        stop;
        np = cur + 17'd1;
        stop = 1'b0;
        if (np >= {1'b0, e}) begin
            np = {1'b0, lp};
            stop = ({1'b0, lp} + 17'd1) >= {1'b0, e};
        end
        nextpos = {stop, np};
    endfunction

    function automatic logic [15:0] clamp16(input logic [23:0] v);
        if ($signed(v) > 24'sd32767)       clamp16 = 16'h7fff;
        else if ($signed(v) < -24'sd32768) clamp16 = 16'h8000;
        else                               clamp16 = v[15:0];
    endfunction

    // ------------------------------------------------------------------
    // RAMs
    // ------------------------------------------------------------------
    // registers: words 0-191 = channel ch registers 4w..4w+3 at {ch, w};
    // words 192-199 = control registers 0x00-0x1f (MAME m_reg)
    logic        rw_we;
    logic [3:0]  rw_be;
    logic [7:0]  rw_addr, rr_addr;
    logic [63:0] rw_data, rr_q;
    // one 16-bit RAM per register lane with its own write enable (Quartus 17
    // did not infer a byte-enabled 64-bit RAM from a lane loop)
    // (explicit generate and genvar: Quartus 17 rejects an inline genvar loop)
    genvar l;
    generate
        for (l = 0; l < 4; l = l + 1) begin : g_regs
            zsg2_ram #(.AW(8), .DW(16)) u_regs (
                .clk(clk), .we(rw_we && rw_be[l]), .waddr(rw_addr), .wdata(rw_data[l*16 +: 16]),
                .raddr(rr_addr), .q(rr_q[l*16 +: 16]));
        end
    endgenerate

    // channel state at {ch, w}:
    //   W0 = {vdf, cur_pos[16:0], step_ptr[16:0], ofilt[31:0]}
    //   W1 = {vol, cutoff, 1'b0, emph[23:0], req_line[22:0]}
    //   W2 = {s4, s3, s2, s1, s0}
    logic        sw_we;
    logic [7:0]  sw_addr, sr_addr;
    logic [79:0] sw_data, sr_q;
    zsg2_ram #(.AW(8), .DW(80)) u_state (
        .clk, .we(sw_we), .waddr(sw_addr), .wdata(sw_data), .raddr(sr_addr), .q(sr_q));

    // line buffers: {line[22:0], data[63:0]} per channel, filled by zsg2_fetch
    logic        lb_we;
    logic [5:0]  lb_waddr, lr_addr;
    logic [86:0] lb_wdata, lb_q;
    zsg2_ram #(.AW(6), .DW(87)) u_lbuf (
        .clk, .we(lb_we), .waddr(lb_waddr), .wdata(lb_wdata), .raddr(lr_addr), .q(lb_q));

    // ------------------------------------------------------------------
    // fetch unit
    // ------------------------------------------------------------------
    logic        enq, enq_full, rb_req, rb_valid;
    logic [5:0]  enq_ch;
    logic [22:0] enq_line;
    logic [29:0] rb_addr;
    logic [31:0] rb_data;
    zsg2_fetch #(.MEM_BLOCKS(MEM_BLOCKS), .RQ_AW(RQ_AW), .INFL(INFL)) u_fetch (
        .clk, .rst, .enq, .enq_ch, .enq_line, .enq_full,
        .rb_req, .rb_addr, .rb_data, .rb_valid,
        .lb_we, .lb_waddr, .lb_wdata,
        .mem_req, .mem_addr, .mem_ready, .mem_rvalid, .mem_rdata);

    // ------------------------------------------------------------------
    // CPU write FIFO: {epoch[1:0], addr[9:0], data[15:0]}
    // ------------------------------------------------------------------
    // In an M10K with a registered read of the next head (wf_rp_n), plus a
    // bypass for a word written to that address in the same clock (read
    // during write returns the old word): wf_head is the same word in the
    // same clock as an asynchronous read of wf[wf_rp]. It was an MLAB; the
    // clk_1x hold check from wf_wp to the MLAB's write address register
    // failed by up to 0.063 ns in the GNET_Z1FULL2 fit (20 endpoints, the
    // fitter's hold fixing on), tools/sta/clk1x_hold.tcl.
    (* ramstyle = "M10K, no_rw_check" *) logic [27:0] wf [0:(1<<WF_AW)-1];
    logic [WF_AW:0]   wf_wp, wf_rp;
    wire              wf_empty = (wf_wp == wf_rp);
    wire              wf_full  = (wf_wp[WF_AW-1:0] == wf_rp[WF_AW-1:0]) && (wf_wp[WF_AW] != wf_rp[WF_AW]);
    logic [27:0]      wf_q, wf_byp;
    logic             wf_bv;
    wire  [27:0]      wf_head  = wf_bv ? wf_byp : wf_q;
    logic [1:0]       tick_n, done_n;     // ticks seen, passes done (mod 4)
    logic             crd_mid;            // the CPU read being answered interrupted a pass
    wire              wf_push  = cpu_wr && !cpu_ack && !wf_full;
    wire              head_ok  = !wf_empty && (wf_head[27:26] == done_n);
    wire  [27:0]      wf_wd    = {tick_n, cpu_addr, cpu_wdata};

    // ------------------------------------------------------------------
    // sequencer
    // ------------------------------------------------------------------
    typedef enum logic [5:0] {
        S_INIT, S_IDLE,
        S_AP, S_AP_W0, S_AP_W1,
        S_KEY, S_KOFF0, S_KOFF1, S_KON0, S_KON1, S_KON2, S_KON3, S_KON4,
        S_CRD0, S_CRD1, S_CRD_RB,
        P_SCAN, P_R1, P_R2, P_STEP, P_MISS, P_DEC, P_INT, P_FILT, P_VOL,
        P_G0, P_G1, P_G2, P_G3, P_WB0, P_WB1, P_WB2, P_STOP, P_END
    } st_t;
    st_t st;

    // write FIFO read side (above): wf_rp after this clock (the sequencer
    // below: reset clears it, S_IDLE takes the head)
    wire  [WF_AW:0]   wf_rp_n  = rst ? '0 : (st == S_IDLE && head_ok) ? wf_rp + 1'd1 : wf_rp;

    always_ff @(posedge clk) begin
        if (wf_push) wf[wf_wp[WF_AW-1:0]] <= wf_wd;
        wf_q   <= wf[wf_rp_n[WF_AW-1:0]];
        wf_bv  <= wf_push && (wf_wp[WF_AW-1:0] == wf_rp_n[WF_AW-1:0]);
        wf_byp <= wf_wd;
    end

    logic [47:0] active;
    logic [47:0] lbv;                     // line buffer holds a fetched line
    logic        lb_we_d;
    logic [5:0]  lb_wa_d;
    logic [47:0] rqv;                     // req_line names a requested line (cleared by rst)
    logic        parity;                  // m_sample_count bit 0
    logic [5:0]  ch;
    logic [3:0]  ki;                      // key bit / init / decode step
    logic [1:0]  isub;
    logic [9:0]  ea;                      // applied entry
    logic [15:0] ed;
    logic [15:0] kmask;
    logic        kon;
    logic [9:0]  ca;                      // CPU read address

    // channel working registers
    logic        vdf;                     // vol_delta forced to 0x400 since key-on
    logic [16:0] cur, sp;
    logic [31:0] ofilt;
    logic [15:0] vol, cutoff;
    logic [23:0] emph;
    logic [22:0] rtag, need;
    logic [15:0] smp [0:4];
    logic [63:0] rg0, rg1, rg3;           // register words 0, 1, 3
    logic [15:0] v8;
    logic [31:0] blk32;
    logic        emph_rst;
    logic [15:0] ia, s3r;
    logic signed [17:0] ma, mb;
    logic signed [35:0] p;
    logic [23:0] mix0, mix1, mix2, mix3;
    logic [10:0] pclk;

    // register fields (zsg2.cpp:365-465)
    wire [15:0] f_start = {rg0[23:16], rg0[15:8]};
    wire [7:0]  f_page  = rg0[31:24];
    wire [16:0] f_step  = {1'b0, rg1[15:0]} + 17'd1;
    wire [15:0] f_loop  = {rg1[55:48], rg1[23:16]};
    wire [15:0] f_end   = rg1[47:32];
    wire [7:0]  f_g3    = rg1[31:24];
    wire [7:0]  f_g2    = rg1[63:56];
    wire [15:0] f_ctgt  = rg3[15:0];
    wire [7:0]  f_cramp = rg3[23:16];
    wire [7:0]  f_g1    = rg3[31:24];
    wire [15:0] f_vtgt  = rg3[47:32];
    wire [7:0]  f_vramp = rg3[55:48];
    wire [7:0]  f_g0    = rg3[63:56];

    // step / advance (P_STEP)
    wire [17:0] sum     = {1'b0, sp} + {1'b0, f_step};
    wire        adv     = |sum[17:16];
    wire [17:0] npx     = nextpos(cur, f_end, f_loop);
    wire [16:0] np      = npx[16:0];
    wire [23:0] nblk    = {f_page, np[15:0]};
    wire        lb_hit_n = lbv[ch] && (lb_q[86:64] == nblk[23:1]);

    // decode step (P_DEC)
    wire [15:0] raw     = dec(blk32, ki[1:0]);
    wire [23:0] e_in    = (ki[1:0] == 2'd0 && emph_rst) ? 24'd0 : emph;
    wire [23:0] e_rnd   = e_in + 24'd32;
    wire [23:0] e_out   = e_in + {{8{raw[15]}}, raw} - {{6{e_rnd[23]}}, e_rnd[23:6]};

    // interpolation, filter, volume (P_INT .. P_VOL)
    wire [1:0]  ipos    = sp[15:14];
    wire [15:0] ia_n    = smp[{1'b0, ipos}];
    wire [15:0] ib_n    = smp[ipos + 3'd1];
    wire [15:0] idiff   = ib_n - ia_n;
    wire [16:0] s_int   = {ia[15], ia} + p[32:16];
    wire [17:0] fdiff   = {s_int[16], s_int} - {{2{ofilt[31]}}, ofilt[31:16]};
    wire [31:0] f2      = ofilt + p[31:0];
    wire [15:0] s3      = p[31:16];
    wire [7:0]  gsel    = (st == P_G0) ? f_g0 : (st == P_G1) ? f_g1 : (st == P_G2) ? f_g2 : f_g3;
    wire [15:0] sg      = (st == P_G0) ? s3 : s3r;
    wire [16:0] osg     = gsel[7] ? -{sg[15], sg} : {sg[15], sg};
    wire [23:0] pacc    = {{8{p[31]}}, p[31:16]};

    // prefetch for the next advance (P_WB0, S_KON3)
    wire [17:0] ppx     = nextpos(cur, f_end, f_loop);
    wire [23:0] pblk    = {f_page, ppx[15:0]};
    wire        pwant   = !ppx[17] && (pblk < MEM_BLOCKS) && (!rqv[ch] || pblk[23:1] != rtag);
    wire        mwant   = !rqv[ch] || (rtag != need);

    // multiplier operands
    always_comb begin
        ma = '0; mb = '0;
        case (st)
            P_INT:  begin ma = $signed({2'b00, sp[13:0], 2'b00}); mb = $signed({{2{idiff[15]}}, idiff}); end
            P_FILT: begin ma = $signed(fdiff);                    mb = $signed({2'b00, cutoff}); end
            P_VOL:  begin ma = $signed({{2{f2[31]}}, f2[31:16]}); mb = $signed({2'b00, vol}); end
            P_G0, P_G1, P_G2, P_G3:
                    begin ma = $signed({osg[16], osg});           mb = $signed({2'b00, gtab(gsel[4:0])}); end
            default: ;
        endcase
    end
    always_ff @(posedge clk) p <= ma * mb;

    // RAM ports and the prefetch enqueue, by state
    always_comb begin
        rw_we = 1'b0; rw_be = 4'h0; rw_addr = '0; rw_data = '0;
        rr_addr = '0;
        sw_we = 1'b0; sw_addr = '0; sw_data = '0;
        sr_addr = '0;
        lr_addr = ch;
        enq = 1'b0; enq_ch = ch; enq_line = '0;
        case (st)
            S_INIT: begin
                rw_we = 1'b1; rw_be = 4'hf; rw_addr = {ch, isub};
                case (isub)
                    2'd0: sr_addr = {ch, 2'd1};
                    2'd1: begin sw_we = 1'b1; sw_addr = {ch, 2'd1}; sw_data = {32'd0, sr_q[47:0]}; end
                    2'd2: begin sw_we = 1'b1; sw_addr = {ch, 2'd0}; sw_data = '0; end
                    default: ;
                endcase
            end
            S_AP: begin
                if (ea < 10'h300) begin
                    rw_we = 1'b1; rw_be = 4'b0001 << ea[1:0]; rw_addr = {ea[9:4], ea[3:2]}; rw_data = {4{ed}};
                    sr_addr = {ea[9:4], (ea[3:0] == 4'hf) ? 2'd0 : 2'd1};
                end else if (ea[7:0] < 8'h20 && !(ea[7:0] <= 8'h06 && ea[1:0] != 2'd3) && ea[7:1] != 7'h0e) begin
                    rw_we = 1'b1; rw_be = 4'b0001 << ea[1:0]; rw_addr = 8'd192 + {5'd0, ea[4:2]}; rw_data = {4{ed}};
                end
            end
            S_AP_W0: begin sw_we = 1'b1; sw_addr = {ea[9:4], 2'd0}; sw_data = {14'd0, sr_q[65:0]}; end
            S_AP_W1: begin
                sw_we = 1'b1; sw_addr = {ea[9:4], 2'd1};
                sw_data = (ea[3:0] == 4'hb) ? {ed, sr_q[63:0]} : {sr_q[79:64], ed, sr_q[47:0]};
            end
            S_KOFF0: sr_addr = {ch, 2'd1};
            S_KOFF1: begin sw_we = 1'b1; sw_addr = {ch, 2'd1}; sw_data = {16'd0, sr_q[63:0]}; end
            S_KON0:  begin rr_addr = {ch, 2'd0}; sr_addr = {ch, 2'd1}; end
            S_KON1:  rr_addr = {ch, 2'd1};
            S_KON2:  rr_addr = {ch, 2'd2};
            S_KON3: begin
                // cur = start - 1 here (set by S_KON2)
                sw_we = 1'b1; sw_addr = {ch, 2'd0};
                sw_data = {13'd0, 1'b1, cur, 17'h10000, 32'd0};
                enq = pwant && !enq_full; enq_line = pblk[23:1];
            end
            S_KON4: begin sw_we = 1'b1; sw_addr = {ch, 2'd1}; sw_data = {16'd0, v8, 1'b0, emph, rtag}; end
            S_CRD0: begin
                if (ca < 10'h300) begin rr_addr = {ca[9:4], ca[3:2]}; sr_addr = {ca[9:4], 2'd1}; end
                else rr_addr = 8'd192 + {5'd0, ca[4:2]};
            end
            P_SCAN:  begin sr_addr = {ch, 2'd0}; rr_addr = {ch, 2'd0}; end
            P_R1:    begin sr_addr = {ch, 2'd1}; rr_addr = {ch, 2'd1}; end
            P_R2:    begin sr_addr = {ch, 2'd2}; rr_addr = {ch, 2'd3}; end
            P_MISS:  begin enq = mwant && !enq_full; enq_line = need; end
            P_WB0: begin
                sw_we = 1'b1; sw_addr = {ch, 2'd0}; sw_data = {13'd0, vdf, cur, sp, ofilt};
                enq = pwant && !enq_full; enq_line = pblk[23:1];
            end
            P_WB1:   begin sw_we = 1'b1; sw_addr = {ch, 2'd1}; sw_data = {vol, cutoff, 1'b0, emph, rtag}; end
            P_WB2:   begin sw_we = 1'b1; sw_addr = {ch, 2'd2}; sw_data = {smp[4], smp[3], smp[2], smp[1], smp[0]}; end
            P_STOP:  begin sw_we = 1'b1; sw_addr = {ch, 2'd1}; sw_data = {16'd0, cutoff, 1'b0, emph, rtag}; end
            default: ;
        endcase
    end

    wire tick_ok = sample_tick && (tick_n - done_n != 2'd3);

    always_ff @(posedge clk) begin
        cpu_ack   <= 1'b0;
        out_valid <= 1'b0;
        rb_req    <= 1'b0;
        if (rst) begin
            st      <= S_INIT;
            ch      <= '0;
            isub    <= '0;
            active  <= '0;
            rqv     <= '0;
            parity  <= 1'b0;
            tick_n  <= '0;
            done_n  <= '0;
            wf_wp   <= '0;
            wf_rp   <= '0;
            rb_addr <= '0;
            dbg_late <= 1'b0;
            dbg_overrun <= 1'b0;
        end else begin
            // valid one clock after the write, when the registered read port
            // can return the new word (read during write gives the old one)
            lb_we_d <= lb_we;
            lb_wa_d <= lb_waddr;
            if (lb_we_d) lbv[lb_wa_d] <= 1'b1;
            if (wf_push) begin
                wf_wp   <= wf_wp + 1'd1;
                cpu_ack <= 1'b1;
            end
            if (sample_tick) begin
                if (tick_ok) tick_n <= tick_n + 1'd1;
                else dbg_overrun <= 1'b1;
            end

            case (st)
            // ---------------- reset sweep (MAME device_reset) ----------------
            S_INIT: begin
                isub <= isub + 1'd1;
                if (isub == 2'd3) begin
                    ch <= ch + 1'd1;
                    if (ch == 6'd47) begin
                        rb_req <= 1'b1;          // read address 0
                        st <= S_IDLE;
                    end
                end
            end

            S_IDLE: begin
                if (head_ok) begin
                    ea    <= wf_head[25:16];
                    ed    <= wf_head[15:0];
                    wf_rp <= wf_rp + 1'd1;
                    st    <= S_AP;
                end else if (tick_n != done_n) begin
                    ch   <= '0;
                    mix0 <= '0; mix1 <= '0; mix2 <= '0; mix3 <= '0;
                    pclk <= '0;
                    st   <= P_SCAN;
                end else if (cpu_rd && !cpu_ack && wf_empty) begin
                    ca <= cpu_addr;
                    crd_mid <= 1'b0;
                    st <= S_CRD0;
                end
            end

            // ---------------- apply one CPU write ----------------
            S_AP: begin
                st <= S_IDLE;
                if (ea < 10'h300) begin
                    if (ea[3:0] == 4'h9 || ea[3:0] == 4'hb) st <= S_AP_W1;
                    else if (ea[3:0] == 4'hf) st <= S_AP_W0;
                end else begin
                    case (ea[7:0])
                        8'h00, 8'h01, 8'h02, 8'h04, 8'h05, 8'h06: begin
                            kon   <= !ea[2];
                            kmask <= ed;
                            ki    <= '0;
                            st    <= S_KEY;
                        end
                        8'h1c: begin rb_addr <= {rb_addr[29:14], ed[15:2]}; rb_req <= 1'b1; end
                        8'h1d: begin rb_addr <= {ed, rb_addr[13:0]};        rb_req <= 1'b1; end
                        default: ;
                    endcase
                end
            end
            S_AP_W0, S_AP_W1: st <= S_IDLE;

            // ---------------- key on / key off (zsg2.cpp:518-554) ----------------
            S_KEY: begin
                ch <= {ea[1:0], ki};
                if (kmask[ki]) st <= kon ? S_KON0 : S_KOFF0;
                else begin
                    ki <= ki + 1'd1;
                    if (ki == 4'd15) st <= S_IDLE;
                end
            end
            S_KOFF0: begin active[ch] <= 1'b0; st <= S_KOFF1; end
            S_KOFF1: begin
                ki <= ki + 1'd1;
                st <= (ki == 4'd15) ? S_IDLE : S_KEY;
            end
            S_KON0: st <= S_KON1;
            S_KON1: begin
                rg0  <= rr_q;
                emph <= sr_q[46:23];
                rtag <= sr_q[22:0];
                st   <= S_KON2;
            end
            S_KON2: begin
                rg1 <= rr_q;
                cur <= {1'b0, f_start} - 17'd1;
                st  <= S_KON3;
            end
            S_KON3: begin
                v8 <= rr_q[15:0];
                if (pwant && !enq_full) begin rtag <= pblk[23:1]; rqv[ch] <= 1'b1; end
                st <= S_KON4;
            end
            S_KON4: begin
                active[ch] <= 1'b1;
                ki <= ki + 1'd1;
                st <= (ki == 4'd15) ? S_IDLE : S_KEY;
            end

            // ---------------- CPU read ----------------
            S_CRD0: begin
                if (ca >= 10'h300 && (ca[7:0] == 8'h1e || ca[7:0] == 8'h1f)) st <= S_CRD_RB;
                else if (ca >= 10'h300 && (ca[7:0] >= 8'h20 || ca[7:0] == 8'h14)) begin
                    cpu_rdata <= 16'd0; cpu_ack <= 1'b1; st <= crd_mid ? P_SCAN : S_IDLE;
                end else st <= S_CRD1;
            end
            S_CRD1: begin
                if (ca < 10'h300) begin
                    case (ca[3:0])
                        4'h3: cpu_rdata <= {active[ca[9:4]], rr_q[{ca[1:0], 4'd0} +: 15]};
                        4'h9: cpu_rdata <= sr_q[63:48];
                        4'hb: cpu_rdata <= sr_q[79:64] >> READB_SHIFT;
                        default: cpu_rdata <= rr_q[{ca[1:0], 4'd0} +: 16];
                    endcase
                end else cpu_rdata <= rr_q[{ca[1:0], 4'd0} +: 16];
                cpu_ack <= 1'b1;
                st <= crd_mid ? P_SCAN : S_IDLE;
            end
            S_CRD_RB: if (rb_valid) begin
                cpu_rdata <= ca[0] ? rb_data[31:16] : rb_data[15:0];
                cpu_ack <= 1'b1;
                st <= crd_mid ? P_SCAN : S_IDLE;
            end

            // ---------------- one sample: the channel pass (zsg2.cpp:286-361) ----------------
            P_SCAN: begin
                pclk <= pclk + 1'd1;
                if (MID_READ && cpu_rd && !cpu_ack && wf_empty && tick_n - done_n == 2'd1 &&
                    (cpu_addr >= 10'h300 || cpu_addr[9:4] < ch)) begin
                    // only this pass is outstanding and it has rendered the
                    // channel read (or the register is global)
                    ca      <= cpu_addr;
                    crd_mid <= 1'b1;
                    st      <= S_CRD0;
                end else if (ch == 6'd48) st <= P_END;
                else if (!active[ch]) ch <= ch + 1'd1;
                else st <= P_R1;
            end
            P_R1: begin
                pclk <= pclk + 1'd1;
                {vdf, cur, sp, ofilt} <= sr_q[66:0];
                rg0 <= rr_q;
                st <= P_R2;
            end
            P_R2: begin
                pclk <= pclk + 1'd1;
                {vol, cutoff} <= sr_q[79:48];
                {emph, rtag}  <= sr_q[46:0];
                rg1 <= rr_q;
                st <= P_STEP;
            end
            P_STEP: begin
                pclk <= pclk + 1'd1;
                {smp[4], smp[3], smp[2], smp[1], smp[0]} <= sr_q;
                rg3 <= rr_q;
                ki  <= '0;
                if (adv) begin
                    if (npx[17]) st <= P_STOP;
                    else begin
                        cur      <= np;
                        sp       <= {1'b0, sum[15:0]};
                        emph_rst <= (np == {1'b0, f_start});
                        need     <= nblk[23:1];
                        if (nblk >= MEM_BLOCKS) begin
                            blk32 <= 32'd0;
                            st <= P_DEC;
                        end else if (lb_hit_n) begin
                            blk32 <= nblk[0] ? lb_q[63:32] : lb_q[31:0];
                            st <= P_DEC;
                        end else st <= P_MISS;
                    end
                end else begin
                    sp <= sum[16:0];
                    st <= P_INT;
                end
            end
            P_MISS: begin
                pclk <= pclk + 1'd1;
                dbg_late <= 1'b1;
                if (mwant && !enq_full) begin rtag <= need; rqv[ch] <= 1'b1; end
                if (lbv[ch] && lb_q[86:64] == need) begin
                    blk32 <= cur[0] ? lb_q[63:32] : lb_q[31:0];
                    st <= P_DEC;
                end
            end
            P_DEC: begin
                pclk <= pclk + 1'd1;
                emph <= e_out;
                if (ki[1:0] == 2'd0) smp[0] <= smp[4];
                smp[ki[1:0] + 3'd1] <= clamp16({e_out[23], e_out[23:1]});
                ki <= ki + 1'd1;
                if (ki[1:0] == 2'd3) st <= P_INT;
            end
            P_INT: begin
                pclk <= pclk + 1'd1;
                ia <= ia_n;
                st <= P_FILT;
            end
            P_FILT: begin
                pclk <= pclk + 1'd1;
                st <= P_VOL;
            end
            P_VOL: begin
                pclk <= pclk + 1'd1;
                ofilt <= (cutoff == 16'd0) ? {f2[31], f2[31:1]} : f2;
                st <= P_G0;
            end
            P_G0: begin pclk <= pclk + 1'd1; s3r <= s3; st <= P_G1; end
            P_G1: begin pclk <= pclk + 1'd1; mix0 <= mix0 + pacc; st <= P_G2; end
            P_G2: begin pclk <= pclk + 1'd1; mix1 <= mix1 + pacc; st <= P_G3; end
            P_G3: begin pclk <= pclk + 1'd1; mix2 <= mix2 + pacc; st <= P_WB0; end
            P_WB0: begin
                pclk <= pclk + 1'd1;
                mix3 <= mix3 + pacc;
                if (parity) begin
                    vol    <= ramp(vol, f_vtgt, vdf ? 16'h0400 : get_ramp(f_vramp));
                    cutoff <= ramp(cutoff, f_ctgt, get_ramp(f_cramp));
                end
                if (pwant && !enq_full) begin rtag <= pblk[23:1]; rqv[ch] <= 1'b1; end
                st <= P_WB1;
            end
            P_WB1: begin pclk <= pclk + 1'd1; st <= P_WB2; end
            P_WB2: begin pclk <= pclk + 1'd1; ch <= ch + 1'd1; st <= P_SCAN; end
            P_STOP: begin
                pclk <= pclk + 1'd1;
                active[ch] <= 1'b0;
                ch <= ch + 1'd1;
                st <= P_SCAN;
            end
            P_END: begin
                out_send0 <= clamp16(mix0);
                out_send1 <= clamp16(mix1);
                out_send2 <= clamp16(mix2);
                out_send3 <= clamp16(mix3);
                out_valid <= 1'b1;
                parity    <= !parity;
                done_n    <= done_n + 1'd1;
                dbg_pass_clocks <= pclk + 1'd1;
                st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end

    // TMS57002 serial input words (route gain 0.5 on sends 0 and 1)
    assign out_si0 = {out_send0[15], out_send0, 7'd0};
    assign out_si1 = {out_send1[15], out_send1, 7'd0};
    assign out_si2 = {out_send2, 8'd0};
    assign out_si3 = {out_send3, 8'd0};
endmodule
