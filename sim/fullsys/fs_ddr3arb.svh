// Included by gen_top.py for gnet-full trees (FS_DDR3ARB=1): PSX.sv
// GNET_DDR3_ARB as of gnet-full 3c993c0. psx_mister's DDRAM side (here
// psx_top's ddr3_* through core_ddr3_*, with psx_mister.vhd's address
// mapping 0011 & ddr3_ADDR(27:3)) is the core client of gnet_ddr3_arb; the
// Zoom line port goes through gnet_ddr3_zport; channel 3 writes are mirrored
// into DDR3 by gnet_ddr3_mirror (which stalls zn2_ch3_arb). Rotation is off:
// no screen_rotate in the harness. The harness DDR3 model sits on the
// arbiter's DDRAM port (fs_top ddr3_*).
wire [26:0] ch3_addr; wire [31:0] ch3_din; wire ch3_req, ch3_rnw; wire [3:0] ch3_be; wire ch3_ready; wire [31:0] ch3_dout;
wire gnet_ch3_stall;
zn2_ch3_arb ich3arb (.clk(clk_cpu), .stall(gnet_ch3_stall), .a_req(1'b0), .a_addr(27'd0), .a_din(32'd0), .a_rnw(1'b0), .a_be(4'd0), .a_ready(),
   .b_req(zn_fl_req), .b_addr(zn_fl_addr), .b_din(zn_fl_din), .b_rnw(zn_fl_rnw), .b_be(zn_fl_be), .b_ready(zn_fl_ready),
   .c_req(1'b0), .c_addr(27'd0), .c_din(32'd0), .c_rnw(1'b1), .c_be(4'hf), .c_ready(),
   .ch3_req(ch3_req), .ch3_addr(ch3_addr), .ch3_din(ch3_din), .ch3_rnw(ch3_rnw), .ch3_be(ch3_be), .ch3_ready(ch3_ready));
assign zn_fl_dout = ch3_dout;
wire arb_z_req, arb_z_ready, arb_z_rvalid; wire [20:0] arb_z_line; wire [63:0] arb_rdata;
gnet_ddr3_zport zport (.clk2x(clk2x), .clk1x(clk1x), .zrst(zoom_rst), .m_req(zoom_m_req), .m_line(zoom_m_line),
   .m_ready(zoom_m_ready), .m_rvalid(zoom_m_rvalid), .m_rdata(zoom_m_rdata),
   .z_req(arb_z_req), .z_line(arb_z_line), .z_ready(arb_z_ready), .z_rvalid(arb_z_rvalid), .z_rdata(arb_rdata));
wire mir_we, mir_busy, mir_ovf; wire [28:0] mir_addr; wire [63:0] mir_din; wire [7:0] mir_be;
gnet_ddr3_mirror mirror (.clk_src(clk_cpu), .w_req(ch3_req && !ch3_rnw), .w_addr(ch3_addr), .w_din(ch3_din), .w_be(ch3_be),
   .stall(gnet_ch3_stall), .clk2x(clk2x), .g_we(mir_we), .g_addr(mir_addr), .g_din(mir_din), .g_be(mir_be), .g_busy(mir_busy), .ovf(mir_ovf));
reg [2:0] arb_rst_s = 3'b111;
always @(posedge clk2x) arb_rst_s <= {arb_rst_s[1:0], sdram_init};
wire [28:0] arb_ddr_addr;
gnet_ddr3_arb ddr3_arb (.clk(clk2x), .rst(arb_rst_s[2]),
   .ddr_busy(ddr3_BUSY), .ddr_burstcnt(ddr3_BURSTCNT), .ddr_addr(arb_ddr_addr), .ddr_dout(ddr3_DOUT),
   .ddr_dout_ready(ddr3_DOUT_READY), .ddr_rd(ddr3_RD), .ddr_din(ddr3_DIN), .ddr_be(ddr3_BE), .ddr_we(ddr3_WE),
   .rot_clk(clkvid), .rot_we(1'b0), .rot_addr(29'd0), .rot_din(64'd0), .rot_be(8'd0),
   .z_req(arb_z_req), .z_line(arb_z_line), .z_ready(arb_z_ready), .z_rvalid(arb_z_rvalid),
   .g_rd(1'b0), .g_we(mir_we), .g_addr(mir_addr), .g_burstcnt(8'd1), .g_din(mir_din), .g_be(mir_be), .g_busy(mir_busy), .g_dout_ready(),
   .c_rd(core_ddr3_RD), .c_we(core_ddr3_WE), .c_addr({4'b0011, core_ddr3_ADDR[27:3]}), .c_burstcnt(core_ddr3_BURSTCNT),
   .c_din(core_ddr3_DIN), .c_be(core_ddr3_BE), .c_busy(core_ddr3_BUSY), .c_dout_ready(core_ddr3_DOUT_READY),
   .rdata(arb_rdata), .rot_ovf(), .rot_hiwater(), .own_ovf());
assign core_ddr3_DOUT = arb_rdata;
// the model takes a byte address in its 256 MB window (word address & 0x1FFFFFF)
assign ddr3_ADDR = {arb_ddr_addr[24:0], 3'b000};
