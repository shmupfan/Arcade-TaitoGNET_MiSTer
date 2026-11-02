// Bench top for gnet_ddr3_flcopy (docs/i12_ddr3_load.md 6.1): the copier and
// the flash mirror share gnet_ddr3_arb's glue port through gnet_ddr3_gmux, as
// PSX.sv wires them with GNET_DDR3_LOAD; the core port and the DDRAM port are
// driven by tb_flcopy.cpp (random core reads, random BUSY and latency).
module tb_flcopy_top #(
    parameter int TRIES = 1    // copier TRIES (run.sh: FLC_TRIES)
) (
    input  logic        clk1x,
    input  logic        clk2x,
    input  logic        clk_cpu,
    input  logic        rst,
    // copier, clk1x
    input  logic        start,
    input  logic [26:0] len,
    output logic        busy,
    output logic        w_req,
    output logic        w_rnw,
    output logic [26:0] w_addr,
    output logic [31:0] w_data,
    input  logic        w_done,
    input  logic [31:0] r_data,
    output logic [31:0] sum_copy,
    output logic [31:0] sum_sdram,
    output logic [31:0] sum_ddr3,
    output logic  [3:0] flags,
    output logic        retried,
    output logic [23:0] tmo_info,
    // channel 3 writes seen by the mirror, clk_cpu
    input  logic        m_req,
    input  logic [26:0] m_addr,
    input  logic [31:0] m_din,
    output logic        m_stall,
    // core client, clk2x
    input  logic        c_rd,
    input  logic [28:0] c_addr,
    input  logic  [7:0] c_burstcnt,
    output logic        c_busy,
    output logic        c_dout_ready,
    // DDRAM port, clk2x
    input  logic        ddr_busy,
    output logic  [7:0] ddr_burstcnt,
    output logic [28:0] ddr_addr,
    input  logic [63:0] ddr_dout,
    input  logic        ddr_dout_ready,
    output logic        ddr_rd,
    output logic [63:0] ddr_din,
    output logic  [7:0] ddr_be,
    output logic        ddr_we,
    output logic [63:0] rdata,
    output logic        mir_ovf,
    output logic        own_orphan
);
    wire        mir_we, mir_busy;
    wire [28:0] mir_addr;
    wire [63:0] mir_din;
    wire  [7:0] mir_be;
    gnet_ddr3_mirror mirror (.clk_src(clk_cpu), .w_req(m_req), .w_addr(m_addr), .w_din(m_din), .w_be(4'hF),
        .stall(m_stall), .clk2x(clk2x), .g_we(mir_we), .g_addr(mir_addr), .g_din(mir_din), .g_be(mir_be),
        .g_busy(mir_busy), .ovf(mir_ovf));

    wire        g_rd, g_we, g_busy, g_dout_ready;
    wire [28:0] g_addr;
    wire  [7:0] g_burstcnt, g_be;
    wire [63:0] g_din;
    wire        f_rd, f_busy, f_dout_ready;
    wire [28:0] f_addr;
    wire  [7:0] f_burstcnt;
    gnet_ddr3_gmux gmux (.a_we(mir_we), .a_addr(mir_addr), .a_din(mir_din), .a_be(mir_be), .a_busy(mir_busy),
        .b_rd(f_rd), .b_we(1'b0), .b_addr(f_addr), .b_burstcnt(f_burstcnt), .b_din(64'd0), .b_be(8'hFF),
        .b_busy(f_busy), .b_dout_ready(f_dout_ready),
        .g_rd(g_rd), .g_we(g_we), .g_addr(g_addr), .g_burstcnt(g_burstcnt), .g_din(g_din), .g_be(g_be),
        .g_busy(g_busy), .g_dout_ready(g_dout_ready));

    gnet_ddr3_flcopy #(.TMO_BITS(16), .TRIES(TRIES)) flcopy (.clk1x(clk1x), .start(start), .len(len), .busy(busy), .w_req(w_req), .w_rnw(w_rnw),
        .w_addr(w_addr), .w_data(w_data), .w_done(w_done), .r_data(r_data), .clk2x(clk2x), .g_rd(f_rd), .g_addr(f_addr),
        .g_burstcnt(f_burstcnt), .g_busy(f_busy), .g_dout_ready(f_dout_ready), .g_dout(rdata),
        .sum_copy(sum_copy), .sum_sdram(sum_sdram), .sum_ddr3(sum_ddr3), .flags(flags), .retried(retried), .tmo_info(tmo_info));

    gnet_ddr3_arb arb (.clk(clk2x), .rst(rst),
        .ddr_busy(ddr_busy), .ddr_burstcnt(ddr_burstcnt), .ddr_addr(ddr_addr), .ddr_dout(ddr_dout),
        .ddr_dout_ready(ddr_dout_ready), .ddr_rd(ddr_rd), .ddr_din(ddr_din), .ddr_be(ddr_be), .ddr_we(ddr_we),
        .rot_clk(clk2x), .rot_we(1'b0), .rot_addr(29'd0), .rot_din(64'd0), .rot_be(8'd0),
        .z_req(1'b0), .z_line(21'd0), .z_ready(), .z_rvalid(),
        .g_rd(g_rd), .g_we(g_we), .g_addr(g_addr), .g_burstcnt(g_burstcnt), .g_din(g_din), .g_be(g_be),
        .g_busy(g_busy), .g_dout_ready(g_dout_ready),
        .c_rd(c_rd), .c_we(1'b0), .c_addr(c_addr), .c_burstcnt(c_burstcnt), .c_din(64'd0), .c_be(8'hFF),
        .c_busy(c_busy), .c_dout_ready(c_dout_ready),
        .rdata(rdata), .rot_ovf(), .rot_hiwater(), .own_orphan(own_orphan));
endmodule
