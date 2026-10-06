// Wrapper for sim/zoomboard/tb_host.cpp: zoom_host with its mailbox, one clock.
module zoom_host_tb #(
    parameter bit MAME_GAIN = 1'b0
) (
    input  logic        clk,
    input  logic        hrst,
    input  logic        zoom_release,
    input  logic        h_req,
    input  logic        h_we,
    input  logic [23:0] h_addr,
    input  logic [3:0]  h_be,
    input  logic [31:0] h_wdata,
    output logic        h_ack,
    output logic [31:0] h_rdata,
    output logic        h_hit,
    output logic        irq_tog,
    output logic [15:0] gain_l,
    output logic [15:0] gain_r,
    input  logic        z_we,
    input  logic [6:0]  z_a,
    input  logic [1:0]  z_be,
    input  logic [15:0] z_wd,
    output logic [15:0] z_q
);
    logic        mb_we;
    logic [6:0]  mb_a;
    logic [1:0]  mb_be;
    logic [15:0] mb_wd, mb_q;
    zoom_host #(.MAME_GAIN(MAME_GAIN)) u_host (
        .hclk(clk), .hrst, .zoom_release, .h_req, .h_we, .h_addr, .h_be, .h_wdata,
        .h_ack, .h_rdata, .h_hit, .mb_we, .mb_a, .mb_be, .mb_wd, .mb_q,
        .irq_tog, .gain_l, .gain_r);
    zoom_mbox u_mbox (
        .hclk(clk), .h_we(mb_we), .h_a(mb_a), .h_be(mb_be), .h_wd(mb_wd), .h_q(mb_q),
        .clk, .z_we, .z_a, .z_be, .z_wd, .z_q);
endmodule
