// Taito Zoom sound board (FC PCB) for the G-NET core: MN10200 sound CPU,
// ZSG-2 wavetable chip, TMS57002 effects DSP, M66220FP mailbox, MB87078
// volume, program cache for flash U27, work RAM, wave memory port, time
// base and output stage. Design: docs/zoom_board_design.md.
//
// Clocks (docs/zoom_board_design.md 6.1): clk is clk_1x (33.8688 MHz) and
// clk2x is clk_2x (67.7376 MHz), phase aligned (one PLL).
//   CLK_H = 2: the whole board runs on clk; clk2x clocks only the program
//     cache and work RAM read ports, which then answer in the next clk cycle
//     (zoom_pcache.sv).
//   CLK_H = 4: the MN10200 side (CPU, bus decoder, program cache, work RAM,
//     mailbox port B, time base) runs on clk2x, the RAMs answering with one
//     wait clock; the ZSG-2, the TMS57002, the slot feeder, the memory
//     arbiter and the output stay on clk. The crossings are synchronous: s_en
//     marks the clk2x cycles that end on a clk edge; pulses from the clk2x
//     side are held over such a cycle, and clk-side pulses are taken in one.
//   The pacer and the time base's real-time source scale with CLK_H;
//   behaviour in virtual time is the same for both.
// hclk is the main-CPU side of the mailbox and the host registers (clk_1x in
// the first integration, the CPU clock under R1).
//
// Reset sequencing (taitogn.cpp:513-533, taito_zm.cpp:73-79):
//   - zoom_reset is control bit 4 (gnet_fc). While it is 1 the MN10200 is
//     held in reset and the program cache is invalidated.
//   - On its falling edge MAME resets the taito_zoom device, so the ZSG-2,
//     the TMS57002 and the MN10200 restart; the ZSG-2 and the TMS57002 are
//     not held during the reset period (MAME) unless RST_LEVEL = 1 (the
//     PCB's wiring is unknown, docs/zoom_board_design.md 9).
//   - The MN10200 also waits for the cache sweep, which only matters for a
//     reset pulse shorter than about 512 clocks (none in the traces).
module zoom_board #(
    parameter int READB_SHIFT = 3,              // ZSG-2 register 0xB read (MAME 61c7940)
    parameter int ZSG_INFL    = 4,              // ZSG-2 wave reads outstanding (1 to 8); 8 behind the DDR3 arbiter (docs/zoom_board_design.md 14)
    parameter int ZSG_MID_READ = 1,             // ZSG-2 reads of rendered channels answered inside a pass (15.3)
    parameter int TIMER_EXACT = 0,              // MN10200 timers: 1 = MAME phase (verification)
    parameter int CLK_H       = 4,              // 2: one clock; 4: MN10200 side on clk2x (see above)
    parameter int PACE_CAP    = 1024,           // MN10200 pacer credit, machine cycles (6.4)
    parameter int WRAM_AW     = 14,             // work RAM 2^AW words (32 KB)
    parameter int PC_IDX_W    = 11,             // program cache lines (2^PC_IDX_W): 32 KB
    parameter int PC_LN_W     = 1,              // beats of 8 bytes per line (2^PC_LN_W)
    parameter logic [23:0] U27_BASE  = 24'h200000,  // flash area layout (zn2_layer_design.md 13.4)
    parameter logic [23:0] WAVE_BASE = 24'h400000,
    parameter int TB_P_INT    = 192,            // time base (zoom_tbase.sv)
    parameter int TB_REM_ADD  = 0,
    parameter int TB_REM_MOD  = 1,
    parameter int OUT_ADD     = 15625,          // output rate 25 MHz / 768 from clk_1x (zoom_out.sv);
    parameter int OUT_MOD     = 16257024,       // the lockstep testbench uses MAME's 32,552 Hz
    parameter bit MAME_GAIN   = 1'b0,           // volume law: 0 MB87078, 1 MAME linear
    parameter bit RST_LEVEL   = 1'b0,           // 1: ZSG-2/TMS57002 held while zoom_reset = 1
    parameter bit TMS_MAME    = 1'b0,           // TMS57002: 0 the User's Guide (default), 1 MAME 0.288 (oracle)
    parameter int DEBUG       = 0               // MN10200 debug cycle counter
) (
    input  logic        clk,
    input  logic        clk2x,
    input  logic        rst,
    // main-CPU side (hclk): offsets from 0x1F000000, zn bus conventions
    input  logic        hclk,
    input  logic        hrst,
    input  logic        zoom_reset,     // control bit 4 (hclk domain)
    input  logic        h_req,
    input  logic        h_we,
    input  logic [23:0] h_addr,
    input  logic [3:0]  h_be,
    input  logic [31:0] h_wdata,
    output logic        h_ack,
    output logic [31:0] h_rdata,
    output logic        h_hit,
    // flash area memory: 64-bit lines, in-order responses (zoom_memarb.sv)
    output logic        m_req,
    output logic [20:0] m_line,         // byte address bits 23:3
    input  logic        m_ready,
    input  logic        m_rvalid,
    input  logic [63:0] m_rdata,
    input  logic        prog_inval,     // U27 written while the Zoom runs (glue; none seen)
    // audio (clk): Zoom output with the volume applied, held per sample
    output logic        aud_tick,
    output logic signed [15:0] aud_l,
    output logic signed [15:0] aud_r,
    // pacer and debug
    input  logic        pace_en,
    input  logic        dbg_hold,
    output logic        dbg_bound,
    output logic        dbg_insn,
    output logic [23:0] dbg_pc,
    output logic [15:0] dbg_psw,
    output logic [15:0] dbg_mdr,
    output logic [47:0] dbg_cycles,
    output logic [191:0] dbg_regs,
    input  logic        tb_pin1_ovr,    // testbench: IRQ1 pin from tb_pin1 (MAME FC57)
    input  logic        tb_pin1,
    input  logic        tb_ld,          // testbench: time base phase
    input  logic [8:0]  tb_ld_left,
    input  logic [15:0] tb_ld_rem,
    output logic [7:0]  dbg_flags
);
    // ================================================================== clocks
    // fclk: the MN10200 side. A constant select, so a plain clock net.
    wire  fclk = (CLK_H == 4) ? clk2x : clk;
    // s_en: this fclk cycle ends on a clk edge (always, with one clock)
    logic s_t, f_t;
    always_ff @(posedge clk)  s_t <= ~s_t;
    always_ff @(posedge fclk) f_t <= s_t;
    wire  s_en = (CLK_H == 4) ? (f_t == s_t) : 1'b1;

    // ================================================================== resets
    // MN10200 side
    logic [2:0] zr_sync;
    always_ff @(posedge fclk) zr_sync <= {zr_sync[1:0], zoom_reset};
    wire  zr       = zr_sync[2];
    logic zr_q;
    always_ff @(posedge fclk) zr_q <= rst ? 1'b1 : zr;
    wire  zr_rise  = !zr_q && zr;
    logic pc_busy;
    wire  cpu_rst  = rst || zr || pc_busy;
    // ZSG-2 and TMS57002 (clk): their own synchroniser. The release reaches
    // them within a clock of the MN10200 side, long before the MN10200 runs
    // (it waits for the cache sweep).
    logic [2:0] zrs_sync;
    always_ff @(posedge clk) zrs_sync <= {zrs_sync[1:0], zoom_reset};
    wire  zrs      = zrs_sync[2];
    logic zrs_q;
    always_ff @(posedge clk) zrs_q <= rst ? 1'b1 : zrs;
    wire  chip_rst = rst || (RST_LEVEL ? zrs : (zrs_q && !zrs));

    logic zrh_q;
    always_ff @(posedge hclk) zrh_q <= zoom_reset;
    wire  zrel_h = zrh_q && !zoom_reset;

    // ================================================================== host side
    logic        mbh_we, irq_tog;
    logic [6:0]  mbh_a;
    logic [1:0]  mbh_be;
    logic [15:0] mbh_wd, mbh_q, gain_l_h, gain_r_h;
    zoom_host #(.MAME_GAIN(MAME_GAIN)) u_host (
        .hclk, .hrst, .zoom_release(zrel_h),
        .h_req, .h_we, .h_addr, .h_be, .h_wdata, .h_ack, .h_rdata, .h_hit,
        .mb_we(mbh_we), .mb_a(mbh_a), .mb_be(mbh_be), .mb_wd(mbh_wd), .mb_q(mbh_q),
        .irq_tog, .gain_l(gain_l_h), .gain_r(gain_r_h));

    // doorbell: toggle synchroniser, then a two-clock low pulse on IRQ0
    logic [3:0] irq_s;
    logic [1:0] irq0_low;
    always_ff @(posedge fclk) begin
        irq_s <= {irq_s[2:0], irq_tog};
        if (rst) irq0_low <= '0;
        else if (irq_s[3] != irq_s[2]) irq0_low <= 2'd2;
        else if (irq0_low != '0) irq0_low <= irq0_low - 2'd1;
    end
    // gains: quasi-static, double registered
    logic [15:0] gl_s [0:1], gr_s [0:1];
    always_ff @(posedge clk) begin
        gl_s[0] <= gain_l_h; gl_s[1] <= gl_s[0];
        gr_s[0] <= gain_r_h; gr_s[1] <= gr_s[0];
    end

    // ================================================================== MN10200
    logic [23:0] bus_addr;
    logic        bus_rd, bus_wr, bus_ack;
    logic [1:0]  bus_be;
    logic [15:0] bus_wdata, bus_rdata;
    logic [7:0]  p0_out, p1_out, p2_out, p3_out, p1_lat;
    logic [3:0]  p_wr;
    logic        mc_step, tms_empty;
    // The TMS57002 executes at most one slot per two clk cycles (16.9 M/s,
    // 1.35 times the slot rate). While the slot feeder holds a SYNC behind
    // undelivered slots, the MN10200 starts no instruction, so its virtual
    // time can run ahead of the DSP by at most one instruction (20 cycles,
    // less than a sample) and no SYNC is ever merged. It only slows the
    // catch-up after a lag (6.4).
    // Host events (15): the MN10200 also starts no instruction while the host
    // event queue is nearly full (ev_hold).
    logic        feed_sp, ev_hold;
    logic [4:0]  acc_cyc, io_cyc;
    wire  [3:0]  irq_pin = {1'b1, 1'b1, tb_pin1_ovr ? tb_pin1 : tms_empty, irq0_low == '0};

    // port 1 input: MAME's tms_ctrl_r returns the last value written
    // (taito_zm.cpp:99-112), which is out | ~dir (mn10200.cpp:2080)
    always_ff @(posedge fclk)
        if (rst) p1_lat <= 8'h00;
        else if (p_wr[1]) p1_lat <= p1_out;

    mn10200 #(.PACE_CAP(PACE_CAP), .PACE_SUB(42336 * CLK_H), .DEBUG(DEBUG), .TIMER_EXACT(TIMER_EXACT),
             .PIPE(CLK_H == 4),
             // register file in flip-flops: the MLAB's write-address register
             // left clk_2x hold at +0.035 ns in the 2026-10-06 z1full fit
             // (tools/sta/clk1x_hold.tcl); same timing and contents
             .RF_MLAB(0)) u_cpu (
        .clk(fclk), .rst(cpu_rst), .pace_en, .ext_go(!feed_sp && !ev_hold),
        .bus_addr, .bus_rd, .bus_wr, .bus_be, .bus_wdata, .bus_rdata, .bus_ack,
        .irq_pin, .p0_in(8'hFF), .p1_in(p1_lat), .p2_in(8'hFF), .p3_in(8'hFF),
        .p0_out, .p1_out, .p2_out, .p3_out, .p_wr, .mc_step, .acc_cyc, .io_cyc,
        .dbg_hold, .dbg_bound, .dbg_insn, .dbg_pc, .dbg_psw, .dbg_mdr, .dbg_cycles, .dbg_regs);

    // ================================================================== bus decoder and targets
    logic        pc_rd, pc_hit, pc_miss;
    logic [15:0] pc_q, wr_q, z_rdata, mbz_q;
    logic        wr_we, wr_cur, z_rd, z_wr, z_ack, look_req, look_ack, tms_wr, mbz_we, t_idle;
    logic [4:0]  look_cyc;
    logic        f_wram_hi, f_unmapped, f_tms_rd;
    zoom_bus #(.WRAM_AW(WRAM_AW)) u_bus (
        .clk(fclk), .rst(cpu_rst),
        .bus_addr, .bus_rd, .bus_wr, .bus_be, .bus_wdata, .bus_rdata, .bus_ack, .acc_cyc,
        .pc_rd, .pc_hit, .pc_q, .wr_we, .wr_q, .wr_cur,
        .z_rd, .z_wr, .z_rdata, .z_ack,
        .look_req, .look_cyc, .look_ack, .t_idle, .s_en, .tms_wr,
        .mb_we(mbz_we), .mb_q(mbz_q),
        .dbg_wram_hi(f_wram_hi), .dbg_unmapped(f_unmapped), .dbg_tms_rd(f_tms_rd));

    logic        pm_req, pm_ready, pm_rvalid;
    logic [20:0] pm_line;
    zoom_pcache #(.IDX_W(PC_IDX_W), .LN_W(PC_LN_W), .BASE(U27_BASE)) u_pcache (
        .clk(fclk), .clk2x, .rst, .inval(zr_rise || prog_inval), .busy(pc_busy),
        .a(bus_addr[18:1]), .rd(pc_rd), .hit(pc_hit), .q(pc_q), .miss(pc_miss),
        .mem_req(pm_req), .mem_line(pm_line), .mem_ready(pm_ready),
        .mem_rvalid(pm_rvalid), .mem_rdata(m_rdata), .men(s_en));

    zoom_wram #(.AW(WRAM_AW)) u_wram (
        .clk2x, .a(bus_addr[WRAM_AW:1]), .we(wr_we), .be(bus_be), .wd(bus_wdata),
        .q(wr_q), .cur(wr_cur));

    zoom_mbox u_mbox (
        .hclk, .h_we(mbh_we), .h_a(mbh_a), .h_be(mbh_be), .h_wd(mbh_wd), .h_q(mbh_q),
        .clk(fclk), .z_we(mbz_we), .z_a(bus_addr[7:1]), .z_be(bus_be), .z_wd(bus_wdata), .z_q(mbz_q));

    // ================================================================== time base
    logic       sample_tick, bound, tms_step, tms_sync, f_sync_ovf, bnd_tog;
    logic [15:0] cyc_cnt;
    logic [7:0]  bnd_cnt;
    zoom_tbase #(.P_INT(TB_P_INT), .REM_ADD(TB_REM_ADD), .REM_MOD(TB_REM_MOD), .RT_SUB(42336 * CLK_H)) u_tbase (
        .clk(fclk), .rst, .cpu_run(!cpu_rst), .mc_step,
        .look_req, .look_cyc, .look_ack,
        .sample_tick, .bound, .cyc_cnt, .bnd_tog, .bnd_cnt,
        .ld(tb_ld), .ld_left(tb_ld_left), .ld_rem(tb_ld_rem));

    // sample tick to the ZSG-2 (clk): held over an s_en cycle
    logic tick_s, tpend;
    always_ff @(posedge fclk) begin
        if (rst) begin
            tick_s <= 1'b0; tpend <= 1'b0;
        end else if (!s_en) begin
            tick_s <= tpend || sample_tick; tpend <= 1'b0;
        end else begin
            tick_s <= 1'b0;
            if (sample_tick) tpend <= 1'b1;
        end
    end
    wire zs_tick = (CLK_H == 4) ? tick_s : sample_tick;
    assign t_idle = (CLK_H == 4) ? !(tpend || tick_s || sample_tick) : 1'b1;

    // TMS57002 host events (docs/zoom_board_design.md 15, I5). A host byte
    // (0xC00000) and a PLOAD/CLOAD change (port 1 bits 0 and 1) reach the
    // DSP at the end of the writing instruction in virtual time, where MAME
    // places every access (mn10200.cpp charges the cycles first): machine
    // cycle cyc_cnt + acc_cyc (io_cyc for the port write, which shows on
    // p1_out the clock after it), slot twice that. Cycles are never stepped
    // during an access, so cyc_cnt is the count before the instruction. While
    // the MN10200 is held a pin change (its reset value) lands at once. The
    // event crosses to clk like the other pulses (held over an s_en cycle),
    // waits in a queue and is delivered by the slot feeder between the right
    // two slots.
    logic        ev_f;                  // fclk: one event this cycle
    logic        ev_fk;                 // 0 host byte, 1 pins
    logic [7:0]  ev_fd;
    logic [16:0] ev_ft;
    logic [1:0]  p1q;
    logic        ev_s, ev_pend;
    always_ff @(posedge fclk) begin
        ev_f <= 1'b0;
        if (rst) begin
            p1q <= 2'b11; ev_s <= 1'b0; ev_pend <= 1'b0;
        end else begin
            if (tms_wr) begin
                ev_f <= 1'b1; ev_fk <= 1'b0; ev_fd <= bus_wdata[7:0];
                ev_ft <= {cyc_cnt + {11'd0, acc_cyc}, 1'b0};
            end else if (p1_out[1:0] != p1q) begin
                // a byte write and a port write are different instructions,
                // so they never meet here; if they did the pins would follow
                // one clock later
                ev_f <= 1'b1; ev_fk <= 1'b1; ev_fd <= {6'd0, p1_out[1:0]};
                ev_ft <= {cyc_cnt + (cpu_rst ? 16'd0 : {11'd0, io_cyc}), 1'b0};
                p1q <= p1_out[1:0];
            end
            if (!s_en) begin
                ev_s <= ev_pend || ev_f; ev_pend <= 1'b0;
            end else begin
                ev_s <= 1'b0;
                if (ev_f) ev_pend <= 1'b1;
            end
        end
    end
    wire ev_push = (CLK_H == 4) ? ev_s : ev_f;

    // queue (clk): 16 entries of {kind, data, slot}
    localparam int EQ_AW = 4;
    localparam logic [EQ_AW:0] K_EQ_FULL = 5'd16;   // 1 << EQ_AW (no casts: Quartus 17 audit Zs3)
    localparam logic [EQ_AW:0] K_EQ_HOLD = 5'd12;   // at most one event per instruction plus the crossing
    logic [25:0]     evq [0:(1<<EQ_AW)-1];
    logic [EQ_AW:0]  eq_wp, eq_rp;
    wire  [EQ_AW:0]  eq_n = eq_wp - eq_rp;
    wire  [25:0]     eq_head = evq[eq_rp[EQ_AW-1:0]];
    logic            ev_fire, tms_busy, f_ev_ovf;
    always_ff @(posedge clk) begin
        if (ev_push) evq[eq_wp[EQ_AW-1:0]] <= {ev_fk, ev_fd, ev_ft};
        if (rst) begin
            eq_wp <= '0; eq_rp <= '0; ev_hold <= 1'b0; f_ev_ovf <= 1'b0;
        end else begin
            if (ev_push) begin
                eq_wp <= eq_wp + 1'd1;
                if (eq_n == K_EQ_FULL) f_ev_ovf <= 1'b1;
            end
            if (ev_fire) eq_rp <= eq_rp + 1'd1;
            ev_hold <= eq_n >= K_EQ_HOLD;
        end
    end

    // the events as the TMS57002 sees them
    logic       th_wr;
    logic [7:0] th_d;
    logic [1:0] pins_q;                 // {CLOAD, PLOAD} pins
    always_ff @(posedge clk) begin
        th_wr <= 1'b0;
        if (rst) pins_q <= 2'b11;
        else if (ev_fire) begin
            if (eq_head[25]) pins_q <= eq_head[18:17];
            else begin th_wr <= 1'b1; th_d <= eq_head[24:17]; end
        end
    end

    zoom_tmsfeed u_feed (
        .clk, .rst, .cyc_cnt(cyc_cnt[7:0]), .bnd_tog, .bnd_cnt, .tms_ready(1'b1),
        .tms_busy, .ev_valid(eq_n != '0), .ev_slot(eq_head[16:0]), .ev_fire,
        .tms_step, .tms_sync, .sync_pend(feed_sp), .dbg_sync_ovf(f_sync_ovf));

    // ================================================================== ZSG-2
    logic        zo_valid, zm_req, zm_ready, zm_rvalid, f_late, f_overrun;
    logic [15:0] zo_s0, zo_s1, zo_s2, zo_s3;
    logic [23:0] zo_si0, zo_si1, zo_si2, zo_si3;
    logic [22:0] zm_addr;
    logic [10:0] pass_clocks;
    zsg2 #(.READB_SHIFT(READB_SHIFT), .INFL(ZSG_INFL), .MID_READ(ZSG_MID_READ)) u_zsg2 (
        .clk, .rst(chip_rst),
        .cpu_rd(z_rd), .cpu_wr(z_wr), .cpu_addr(bus_addr[10:1]), .cpu_wdata(bus_wdata),
        .cpu_rdata(z_rdata), .cpu_ack(z_ack),
        .sample_tick(zs_tick),
        .out_valid(zo_valid), .out_send0(zo_s0), .out_send1(zo_s1), .out_send2(zo_s2), .out_send3(zo_s3),
        .out_si0(zo_si0), .out_si1(zo_si1), .out_si2(zo_si2), .out_si3(zo_si3),
        .mem_req(zm_req), .mem_addr(zm_addr), .mem_ready(zm_ready),
        .mem_rvalid(zm_rvalid), .mem_rdata(m_rdata),
        .dbg_late(f_late), .dbg_overrun(f_overrun), .dbg_pass_clocks(pass_clocks));

    // wave and program memory
    logic f_arb_ovf;
    zoom_memarb u_arb (
        .clk, .rst,
        .p_req(pm_req), .p_line(pm_line), .p_ready(pm_ready), .p_rvalid(pm_rvalid),
        .z_req(zm_req), .z_line(WAVE_BASE[23:3] + zm_addr[20:0]), .z_ready(zm_ready), .z_rvalid(zm_rvalid),
        .m_req, .m_line, .m_ready, .m_rvalid, .dbg_ovf(f_arb_ovf));

    // ================================================================== ZSG-2 to TMS57002
    // One ZSG-2 output per pass, consumed at each SYNC; the SYNC for sample
    // k takes pass k - 1 (the serial link on the PCB, design study 6.1).
    // Primed with one zero entry at each chip reset.
    logic [63:0] sq [0:3];
    logic [2:0]  sq_n;
    logic [63:0] si_head;
    assign si_head = sq[0];
    always_ff @(posedge clk) begin
        if (chip_rst) begin
            sq[0] <= '0;
            sq_n  <= 3'd1;
        end else begin : sq_step
            logic [2:0] n;
            n = sq_n;
            if (tms_sync && n != 3'd0) begin
                sq[0] <= sq[1]; sq[1] <= sq[2]; sq[2] <= sq[3];
                n = n - 3'd1;
            end
            if (zo_valid && n != 3'd4) begin
                sq[n[1:0]] <= {zo_s3, zo_s2, zo_s1, zo_s0};
                n = n + 3'd1;
            end
            sq_n <= n;
        end
    end
    // route gains 0.5 / 0.5 / 1 / 1 and SIM = 1 (taito_zm.cpp:205-208, tms57002.cpp:927-931)
    wire [23:0] si0 = {{1{si_head[15]}}, si_head[15:0], 7'd0};
    wire [23:0] si1 = {{1{si_head[31]}}, si_head[31:16], 7'd0};
    wire [23:0] si2 = {si_head[47:32], 8'd0};
    wire [23:0] si3 = {si_head[63:48], 8'd0};

    logic [23:0] so_l, so_r;
    logic [15:0] so_l16, so_r16;
    logic        tms_idle, tms_unsup;
    logic [7:0]  tms_pc;
    // TMS57002 parameters (docs/tms57002_rtl.md 5): the guide's behaviour by
    // default; TMS_MAME = 1 selects the set that is bit-exact with MAME 0.288
    tms57002 #(
        .XM_CYCLES(TMS_MAME ? 2 : 6), .XM_COUNT_IDLE(!TMS_MAME), .UPD_AFTER_CLOAD(!TMS_MAME),
        .MPY_A32(TMS_MAME), .SI_RAW(TMS_MAME)
    ) u_tms (
        .clk, .rst(chip_rst), .step(tms_step), .sync(tms_sync),
        .host_wr(th_wr), .host_din(th_d),
        .pload_n(pins_q[0]), .cload_n(pins_q[1]), .empty(tms_empty), .busy(tms_busy),
        .si0_l(si0), .si0_r(si1), .si1_l(si2), .si1_r(si3),
        .so1_l(so_l), .so1_r(so_r), .so1_l16(so_l16), .so1_r16(so_r16),
        .dbg_hold(1'b0), .dbg_idle(tms_idle), .dbg_pc(tms_pc), .dbg_unsup(tms_unsup));

    // ================================================================== output
    logic sync_q, f_under, f_over;
    // FIFO depth and lead follow the pacer cap: the virtual time may lag real
    // time by up to PACE_CAP cycles, PACE_CAP / 192 samples (6.4)
    localparam int OUT_LEAD = PACE_CAP / 192 + 2;
    localparam int OUT_AW   = (OUT_LEAD + 2 <= 8) ? 3 : (OUT_LEAD + 2 <= 16) ? 4 : (OUT_LEAD + 2 <= 32) ? 5 : 6;
    logic [OUT_AW:0] out_level;
    always_ff @(posedge clk) sync_q <= tms_sync;
    zoom_out #(.OUT_ADD(OUT_ADD), .OUT_MOD(OUT_MOD), .LEAD(OUT_LEAD), .AW(OUT_AW)) u_out (
        .clk, .rst, .push(sync_q), .in_l(so_l16), .in_r(so_r16),
        .gain_l(gl_s[1]), .gain_r(gr_s[1]),
        .tick(aud_tick), .out_l(aud_l), .out_r(aud_r),
        .dbg_under(f_under), .dbg_over(f_over), .dbg_level(out_level));

    // bit 6: a SYNC merged, or the host event queue overflowed (15)
    assign dbg_flags = {f_arb_ovf, f_sync_ovf | f_ev_ovf, f_late, f_overrun, f_wram_hi, f_unmapped, f_tms_rd, f_under};
endmodule
