// Bench top: rotation of the GNET_Z1FULL video path. arcade_video (Fx,
// scandoubler, gamma) as PSX.sv instantiates it in GNET_SHELL builds ->
// screen_rotate -> gnet_ddr3_arb's rotation FIFO and the DDRAM port, with
// the core's C port driven by the C++ bench. FEED selects screen_rotate's
// input: 0 = arcade_video's outputs (the MiSTer template's way, gnet-full up
// to 2c8476d), 1 = a separate gamma_corr on the pre-scandoubler video with
// the core's dot enable (PSX.sv since then). video_mixer is the Verilator
// copy sim/rotfx/video_mixer_sim.sv. sync_fix below is sys/sys_top.v's.
module rot_top #(
    parameter int FEED = 0
) (
    input  logic        clk_vid,
    input  logic        clk2x,
    input  logic        arb_rst,
    input  logic        ce_pix,
    input  logic [23:0] rgb,
    input  logic        hs, vs, hb, vb,
    input  logic [2:0]  fx,
    input  logic        forced_sd,
    input  logic        rot_en,
    input  logic        rot_ccw,
    input  logic        fb_vbl,
    // DDRAM port (clk2x)
    input  logic        ddr_busy,
    output logic [7:0]  ddr_burstcnt,
    output logic [28:0] ddr_addr,
    input  logic [63:0] ddr_dout,
    input  logic        ddr_dout_ready,
    output logic        ddr_rd,
    output logic [63:0] ddr_din,
    output logic [7:0]  ddr_be,
    output logic        ddr_we,
    // core client (clk2x)
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
    output logic        rot_we,
    output logic [28:0] rot_addr,
    output logic [63:0] rot_din,
    output logic [7:0]  rot_be,
    output logic        rot_ovf,
    output logic [9:0]  rot_hiwater,
    output logic        own_ovf,
    output logic        fb_en,
    output logic [11:0] fb_width,
    output logic [11:0] fb_height,
    output logic        ce_out,
    output logic        de_out,
    output logic        vs_out,
    output logic [23:0] rgb_out
);
    wire [21:0] gamma_bus;
    assign gamma_bus[20:0] = 21'd0;
    logic        CE_PIXEL, VGA_HS, VGA_VS, VGA_DE;
    logic [7:0]  VGA_R, VGA_G, VGA_B;
    logic [1:0]  VGA_SL;

    arcade_video #(.WIDTH(640), .DW(24)) arcade_video (
        .clk_video(clk_vid), .ce_pix, .RGB_in(rgb), .HBlank(hb), .VBlank(vb), .HSync(hs), .VSync(vs),
        .CLK_VIDEO(), .CE_PIXEL, .VGA_R, .VGA_G, .VGA_B, .VGA_HS, .VGA_VS, .VGA_DE, .VGA_SL,
        .fx, .forced_scandoubler(forced_sd), .gamma_bus);

    // rotation feed
    logic        r_ce, r_hs, r_vs, r_de;
    logic [7:0]  r_r, r_g, r_b;
    generate
        if (FEED == 1) begin : g_pre
            logic        g_hs, g_vs, g_hb, g_vb;
            logic [23:0] g_rgb;
            gamma_corr rot_gamma (
                .clk_sys(gamma_bus[20]), .clk_vid, .ce_pix,
                .gamma_en(gamma_bus[19]), .gamma_wr(gamma_bus[18]), .gamma_wr_addr(gamma_bus[17:8]), .gamma_value(gamma_bus[7:0]),
                .HSync(hs), .VSync(vs), .HBlank(hb), .VBlank(vb), .RGB_in(rgb),
                .HSync_out(g_hs), .VSync_out(g_vs), .HBlank_out(g_hb), .VBlank_out(g_vb), .RGB_out(g_rgb));
            assign r_ce = ce_pix;
            assign {r_r, r_g, r_b} = g_rgb;
            assign r_hs = g_hs; assign r_vs = g_vs; assign r_de = ~(g_hb | g_vb);
        end else begin : g_post
            assign r_ce = CE_PIXEL;
            assign {r_r, r_g, r_b} = {VGA_R, VGA_G, VGA_B};
            assign r_hs = VGA_HS; assign r_vs = VGA_VS; assign r_de = VGA_DE;
        end
    endgenerate
    assign ce_out = r_ce;
    assign de_out = r_de;
    assign vs_out = r_vs;
    assign rgb_out = {r_r, r_g, r_b};

    logic        rot_fb_en;
    logic [4:0]  rot_fb_format;
    logic [31:0] rot_fb_base;
    logic [13:0] rot_fb_stride;
    screen_rotate screen_rotate (
        .CLK_VIDEO(clk_vid), .CE_PIXEL(r_ce), .VGA_R(r_r), .VGA_G(r_g), .VGA_B(r_b),
        .VGA_HS(r_hs), .VGA_VS(r_vs), .VGA_DE(r_de),
        .rotate_ccw(rot_ccw), .no_rotate(~rot_en), .flip(1'b0), .video_rotated(),
        .FB_EN(rot_fb_en), .FB_FORMAT(rot_fb_format), .FB_WIDTH(fb_width), .FB_HEIGHT(fb_height),
        .FB_BASE(rot_fb_base), .FB_STRIDE(rot_fb_stride), .FB_VBL(fb_vbl), .FB_LL(1'b0),
        .DDRAM_CLK(), .DDRAM_BUSY(1'b0), .DDRAM_BURSTCNT(), .DDRAM_ADDR(rot_addr), .DDRAM_DIN(rot_din),
        .DDRAM_BE(rot_be), .DDRAM_WE(rot_we), .DDRAM_RD());
    assign fb_en = rot_fb_en;

    gnet_ddr3_arb arb (
        .clk(clk2x), .rst(arb_rst),
        .ddr_busy, .ddr_burstcnt, .ddr_addr, .ddr_dout, .ddr_dout_ready, .ddr_rd, .ddr_din, .ddr_be, .ddr_we,
        .rot_clk(clk_vid), .rot_we, .rot_addr, .rot_din, .rot_be,
        .z_req(1'b0), .z_line(21'd0), .z_ready(), .z_rvalid(),
        .g_rd(1'b0), .g_we(1'b0), .g_addr(29'd0), .g_burstcnt(8'd1), .g_din(64'd0), .g_be(8'd0), .g_busy(), .g_dout_ready(),
        .c_rd, .c_we, .c_addr, .c_burstcnt, .c_din, .c_be, .c_busy, .c_dout_ready,
        .rdata, .rot_ovf, .rot_hiwater, .own_ovf);
endmodule

module sync_fix (input clk, input sync_in, output sync_out);  // sys/sys_top.v:1882
    assign sync_out = sync_in ^ pol;
    reg pol;
    always @(posedge clk) begin
        reg [31:0] cnt;
        reg s1, s2;
        s1 <= sync_in;
        s2 <= s1;
        cnt <= s2 ? (cnt - 1) : (cnt + 1);
        if (~s2 & s1) begin
            cnt <= 0;
            pol <= cnt[31];
        end
    end
endmodule
