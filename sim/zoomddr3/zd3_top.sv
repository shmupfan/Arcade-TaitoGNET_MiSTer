// Bench top: the Taito Zoom board reading its flash area through the DDR3
// path of GNET_Z1FULL (PSX.sv): zoom_board m_* -> gnet_ddr3_zport ->
// gnet_ddr3_arb Z port; the flash mirror (gnet_ddr3_mirror) fed by a
// channel 3 write stream on clk_cpu writes the area into DDR3 through the
// arbiter's G port; the core's C port and the DDRAM port are driven by the
// C++ bench (tb_zd3.cpp). Wired as PSX.sv and psx_top.vhd wire them:
// zoom_board rst/hrst and zport zrst = the PS1-group reset (p_rst),
// hclk = clk_1x, dbg_hold = zoom_hold (the core pause).
module zd3_top #(
    parameter int ZSG_INFL = 8
) (
    input  logic        clk1x,
    input  logic        clk2x,
    input  logic        clk_cpu,
    input  logic        p_rst,
    input  logic        arb_rst,
    input  logic        zoom_reset,
    input  logic        zoom_hold,
    // host port (clk_1x), as zoom_cdc delivers it
    input  logic        h_req,
    input  logic        h_we,
    input  logic [23:0] h_addr,
    input  logic [3:0]  h_be,
    input  logic [31:0] h_wdata,
    // channel 3 write stream (clk_cpu)
    input  logic        w_req,
    input  logic [26:0] w_addr,
    input  logic [31:0] w_din,
    input  logic [3:0]  w_be,
    output logic        stall,
    // DDRAM port (clk_2x)
    input  logic        ddr_busy,
    output logic [7:0]  ddr_burstcnt,
    output logic [28:0] ddr_addr,
    input  logic [63:0] ddr_dout,
    input  logic        ddr_dout_ready,
    output logic        ddr_rd,
    output logic [63:0] ddr_din,
    output logic [7:0]  ddr_be,
    output logic        ddr_we,
    // core client (clk_2x)
    input  logic        c_rd,
    input  logic        c_we,
    input  logic [28:0] c_addr,
    input  logic [7:0]  c_burstcnt,
    input  logic [63:0] c_din,
    input  logic [7:0]  c_be,
    output logic        c_busy,
    output logic        c_dout_ready,
    output logic [63:0] rdata,
    // observation
    output logic        m_req,
    output logic [20:0] m_line,
    output logic        m_ready,
    output logic        m_rvalid,
    output logic [63:0] m_rdata,
    output logic        dbg_insn,
    output logic        dbg_bound,
    output logic [23:0] dbg_pc,
    output logic [15:0] dbg_psw,
    output logic [15:0] dbg_mdr,
    output logic [191:0] dbg_regs,
    output logic [7:0]  flags,
    output logic        aud_tick,
    output logic [15:0] aud_l,
    output logic [15:0] aud_r,
    output logic        mir_ovf,
    output logic        rot_ovf,
    output logic        own_ovf
);
    logic        h_ack, h_hit;
    logic [31:0] h_rdata;
    logic        z_req, z_ready, z_rvalid;
    logic [20:0] z_line;
    logic        g_we, g_busy;
    logic [28:0] g_addr;
    logic [63:0] g_din;
    logic [7:0]  g_be;
    logic [9:0]  rot_hiwater;

    zoom_board #(.CLK_H(4), .PACE_CAP(1024), .ZSG_INFL(ZSG_INFL), .TIMER_EXACT(0), .DEBUG(0)) zb (
        .clk(clk1x), .clk2x, .rst(p_rst), .hclk(clk1x), .hrst(p_rst), .zoom_reset,
        .h_req, .h_we, .h_addr, .h_be, .h_wdata, .h_ack, .h_rdata, .h_hit,
        .m_req, .m_line, .m_ready, .m_rvalid, .m_rdata, .prog_inval(1'b0),
        .aud_tick, .aud_l, .aud_r, .pace_en(1'b1), .dbg_hold(zoom_hold),
        .dbg_bound, .dbg_insn, .dbg_pc, .dbg_psw, .dbg_mdr, .dbg_cycles(), .dbg_regs,
        .tb_pin1_ovr(1'b0), .tb_pin1(1'b0), .tb_ld(1'b0), .tb_ld_left(9'd0), .tb_ld_rem(16'd0),
        .dbg_flags(flags));

    gnet_ddr3_zport zport (
        .clk2x, .clk1x, .zrst(p_rst),
        .m_req, .m_line, .m_ready, .m_rvalid, .m_rdata,
        .z_req, .z_line, .z_ready, .z_rvalid, .z_rdata(rdata));

    gnet_ddr3_mirror mirror (
        .clk_src(clk_cpu), .w_req, .w_addr, .w_din, .w_be, .stall,
        .clk2x, .g_we, .g_addr, .g_din, .g_be, .g_busy, .ovf(mir_ovf));

    gnet_ddr3_arb arb (
        .clk(clk2x), .rst(arb_rst),
        .ddr_busy, .ddr_burstcnt, .ddr_addr, .ddr_dout, .ddr_dout_ready, .ddr_rd, .ddr_din, .ddr_be, .ddr_we,
        .rot_clk(clk1x), .rot_we(1'b0), .rot_addr(29'd0), .rot_din(64'd0), .rot_be(8'd0),
        .z_req, .z_line, .z_ready, .z_rvalid,
        .g_rd(1'b0), .g_we, .g_addr, .g_burstcnt(8'd1), .g_din, .g_be, .g_busy, .g_dout_ready(),
        .c_rd, .c_we, .c_addr, .c_burstcnt, .c_din, .c_be, .c_busy, .c_dout_ready,
        .rdata, .rot_ovf, .rot_hiwater, .own_ovf);
endmodule
