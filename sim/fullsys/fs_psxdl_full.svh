// ---------------------------------------------------------------------------
// MiSTer download path of the release PSX.sv (GNET_ZN2 + GNET_CPU50 +
// GNET_DDR3_ARB + GNET_ZOOM, revision GNET_Z1FULLR, and with
// +define+GNET_DDR3_LOAD=1 revision GNET_Z1FULLD), for the full-system
// simulation (docs/fullsys_sim.md 5.3, docs/i12_ddr3_load.md). Included by
// gen_top.py when FS_DL=1 and FS_DDR3ARB=1. Statements are copied verbatim
// from PSX.sv at branch i12-ddr3load f9d8e2d apart from: clk_1x -> clk1x
// and clk_2x -> clk2x (aliases below), the OSD/framework inputs tied to
// their defaults (buttons, status, cdDownloadReset, the pause watchdog mask,
// pll_cpu_locked), PSX.sv's cdc_handshake #(64, 32) through the wrapper
// fs_ch3_cdc (sim/fullsys/fs_ch3_cdc.vhd, synthesised by GHDL as an extra
// top), and no screen_rotate (rotation off: R port tied off, as
// fs_ddr3arb.svh). PSX.sv line numbers at f9d8e2d in brackets.
// ---------------------------------------------------------------------------
wire        clk_1x = clk1x;
wire        clk_2x = clk2x;
wire  [1:0] buttons = 2'b00;
wire [127:0] status = 128'd0;
wire        cdDownloadReset = 1'b0;
wire        zn_wd_mask = 1'b0;
wire        sdramCh3_done;

// [734-740]
reg bios_download, exe_download, cdinfo_download, code_download;
always @(posedge clk_1x) begin
	bios_download    <= ioctl_download & (ioctl_index[5:0] == 0);
	exe_download     <= ioctl_download & (ioctl_index == 1);
	cdinfo_download  <= ioctl_download & (ioctl_index == 251);
	code_download    <= ioctl_download & (ioctl_index == 255);
end

// [751-801]
reg flash_download, keys_download, meta_download, card_download, ee_download, dip_download;
always @(posedge clk_1x) begin
	flash_download <= ioctl_download & (ioctl_index == 3);
	keys_download  <= ioctl_download & (ioctl_index == 2);
	meta_download  <= ioctl_download & (ioctl_index == 4);
	card_download  <= ioctl_download & (ioctl_index == 5);
	ee_download    <= ioctl_download & (ioctl_index == 6);
	dip_download   <= ioctl_download & (ioctl_index == 254);
end
wire gnet_download;
`ifdef GNET_DDR3_LOAD
reg         flash_download_1 = 1'b0;
reg         fl_ddr3 = 1'b0;
reg  [26:0] flc_len = 27'd0;
reg         flc_start = 1'b0;
wire        flc_busy;
wire        flc_wreq;
wire        flc_wrnw;
wire [26:0] flc_waddr;
wire [31:0] flc_wdata;
wire [31:0] flc_rdata;
wire [31:0] flc_sum_copy, flc_sum_sdram, flc_sum_ddr3;
wire  [3:0] flc_flags;
always @(posedge clk_1x) begin
	flash_download_1 <= flash_download;
	flc_start        <= 1'b0;
	if (flash_download & ~flash_download_1) begin
		fl_ddr3 <= (ioctl_addr != 27'd0);
		flc_len <= ioctl_addr;
	end
	if (~flash_download & flash_download_1 & fl_ddr3) flc_start <= 1'b1;
	if (flc_start) fl_ddr3 <= 1'b0;
end
wire flc_hold = (fl_ddr3 & ~flash_download) | flc_busy;
assign gnet_download = flash_download | keys_download | meta_download | card_download | ee_download | flc_hold;
assign dbg_flc_busy = flc_busy;
assign dbg_flc_flags = flc_flags;
assign dbg_flc_sum0 = flc_sum_copy;
assign dbg_flc_sum1 = flc_sum_sdram;
assign dbg_flc_sum2 = flc_sum_ddr3;
`else
assign gnet_download = flash_download | keys_download | meta_download | card_download | ee_download;
assign dbg_flc_busy = 1'b0;
assign dbg_flc_flags = 4'd0;
assign dbg_flc_sum0 = 32'd0;
assign dbg_flc_sum1 = 32'd0;
assign dbg_flc_sum2 = 32'd0;
`endif

// [803-815], [862-883]
reg  [7:0] zn_sw0 = 8'h0F;
reg        zn_card_loaded = 0;
reg        zn_ld_wr = 0;
reg  [1:0] zn_ld_target;
reg [10:0] zn_ld_addr;
reg [15:0] zn_ld_data;
reg        zn_card_dl_wr = 0;
reg [25:0] zn_card_dl_addr;
reg [15:0] zn_card_dl_data;
reg        zn_card_wait = 0;
wire       zn_card_dl_busy;
always @(posedge clk_1x) begin
	zn_ld_wr      <= 0;
	zn_card_dl_wr <= 0;
	if (ioctl_wr) begin
		if (keys_download | meta_download | ee_download) begin
			zn_ld_wr     <= 1;
			zn_ld_target <= keys_download ? 2'd0 : meta_download ? 2'd1 : 2'd2;
			zn_ld_addr   <= ioctl_addr[10:0];
			zn_ld_data   <= ioctl_dout;
		end
		if (meta_download) zn_card_loaded <= 1;
		if (card_download) begin
			zn_card_dl_wr   <= 1;
			zn_card_dl_addr <= ioctl_addr[25:0];
			zn_card_dl_data <= ioctl_dout;
		end
		if (dip_download && ioctl_addr[24:1] == 0) zn_sw0 <= ioctl_dout[7:0];
	end
	zn_card_wait <= zn_card_dl_wr | zn_card_dl_busy;
end
// [2139-2145]
wire [3:0] zn_dsw          = {zn_sw0[3] & ~status[121], zn_sw0[2:0]};
wire       zn_jp1          = zn_sw0[4];
wire       zn_card_present = zn_card_loaded;
wire       zn_key_valid    = zn_card_loaded;

// [290-308], [1452], [1505-1510]
wire       zn_wd_reset;
reg  [7:0] zn_wd_hold = 0;
always @(posedge clk_1x) begin
	if (zn_wd_reset & ~status[100] & ~zn_wd_mask) zn_wd_hold <= 8'hFF;
	else if (zn_wd_hold) zn_wd_hold <= zn_wd_hold - 1'd1;
end
wire reset_or = RESET | buttons[1] | status[0] | bios_download | exe_download | cdDownloadReset | gnet_download | (zn_wd_hold != 0);
reg reset = 0;
always @(posedge clk_1x) begin
	reset <= 0;
	if (reset_or) reset <= 1;
end
assign dbg_reset = reset;

// [1145-1158], [1201-1243]
localparam EXE_START = 16777216;
reg [26:0] ramdownload_wraddr;
`ifdef GNET_DDR3_LOAD
wire gnet_flash_dl = flash_download | flc_busy;
reg  ramdownload_rnw = 1'b0;
`else
wire gnet_flash_dl = flash_download;
`endif
reg [31:0] ramdownload_wrdata;
reg        ramdownload_wr;
initial ioctl_wait = 0;
always @(posedge clk_1x) begin
	ramdownload_wr <= 0;
`ifdef GNET_DDR3_LOAD
	if (flc_busy) begin
		if (flc_wreq) begin
			ramdownload_wraddr <= flc_waddr;
			ramdownload_wrdata <= flc_wdata;
			ramdownload_rnw    <= flc_wrnw;
			ramdownload_wr     <= 1;
		end
		ioctl_wait <= 1;
	end else if (fl_ddr3 & ~flash_download) begin
		ioctl_wait <= 1;
	end else
`endif
	if(exe_download | bios_download | cdinfo_download | gnet_flash_dl) begin
      if (ioctl_wr) begin
         if(~ioctl_addr[1]) begin
            ramdownload_wrdata[15:0] <= ioctl_dout;
            if (gnet_flash_dl)         ramdownload_wraddr  <= 27'h1000000 + ioctl_addr[23:0];
            else if (bios_download)    ramdownload_wraddr  <= {4'd1, 2'b00, ioctl_index[7:6], ioctl_addr[18:0]};
            else if (exe_download)     ramdownload_wraddr  <= ioctl_addr[22:0] + EXE_START[26:0];
            else if (cdinfo_download)  ramdownload_wraddr  <= ioctl_addr[26:0];
         end else begin
            ramdownload_wrdata[31:16] <= ioctl_dout;
            ramdownload_wr            <= 1;
            ioctl_wait                <= 1;
            if (cdinfo_download) ioctl_wait <= 0;
         end
      end
      if(sdramCh3_done) ioctl_wait <= 0;
   end else if (card_download) begin
      ioctl_wait <= zn_card_wait;
   end else if (keys_download | meta_download | ee_download) begin
      ioctl_wait <= zn_ld_busy;
   end else begin
      ioctl_wait <= 0;
	end
end

// [2273-2352] channel 3: download handshake (clk_1x to clk_cpu) and
// zn2_ch3_arb (port a downloads, port b the flash storage port, stall from
// the mirror); sdram.sv's ch3 is driven by gen_top's sdram instance from
// ch3_* (PSX.sv's ch3c_*)
wire [26:0] ch3_addr; wire [31:0] ch3_din; wire ch3_req, ch3_rnw; wire [3:0] ch3_be; wire ch3_ready; wire [31:0] ch3_dout;
wire [26:0] ch3h_addr;
wire [31:0] ch3h_din;
wire        ch3h_rnw;
wire  [3:0] ch3h_be;
wire        ch3h_req;
wire        ch3h_ack;
wire        gnet_ch3_stall;
fs_ch3_cdc ch3_cdc
(
	.src_clk     (clk_1x),
	.src_start   ((exe_download | bios_download | gnet_flash_dl) & ramdownload_wr),
`ifdef GNET_DDR3_LOAD
	.src_req_data({ramdownload_wraddr, ramdownload_wrdata, flc_busy & ramdownload_rnw, 4'b1111}),
	.src_rsp_data(flc_rdata),
`else
	.src_req_data({ramdownload_wraddr, ramdownload_wrdata, 1'b0, 4'b1111}),
	.src_rsp_data(),
`endif
	.src_done    (sdramCh3_done),
	.dst_clk     (clk_cpu),
	.dst_valid   (ch3h_req),
	.dst_req_data({ch3h_addr, ch3h_din, ch3h_rnw, ch3h_be}),
	.dst_ack     (ch3h_ack),
	.dst_rsp_data(ch3_dout)
);
zn2_ch3_arb ch3_arb
(
	.clk      (clk_cpu),
	.stall    (gnet_ch3_stall),
	.a_req    (ch3h_req),
	.a_addr   (ch3h_addr),
	.a_din    (ch3h_din),
	.a_rnw    (ch3h_rnw),
	.a_be     (ch3h_be),
	.a_ready  (ch3h_ack),
	.b_req    (zn_fl_req),
	.b_addr   (zn_fl_addr),
	.b_din    (zn_fl_din),
	.b_rnw    (zn_fl_rnw),
	.b_be     (zn_fl_be),
	.b_ready  (zn_fl_ready),
	.c_req    (1'b0),
	.c_addr   (27'd0),
	.c_din    (32'd0),
	.c_rnw    (1'b1),
	.c_be     (4'hf),
	.c_ready  (),
	.ch3_req  (ch3_req),
	.ch3_addr (ch3_addr),
	.ch3_din  (ch3_din),
	.ch3_rnw  (ch3_rnw),
	.ch3_be   (ch3_be),
	.ch3_ready(ch3_ready)
);
assign zn_fl_dout = ch3_dout;

// [2750-2900] DDR3 arbiter block (rotation off)
wire arb_z_req, arb_z_ready, arb_z_rvalid; wire [20:0] arb_z_line; wire [63:0] arb_rdata;
gnet_ddr3_zport zport (.clk2x(clk_2x), .clk1x(clk_1x), .zrst(zoom_rst), .m_req(zoom_m_req), .m_line(zoom_m_line),
   .m_ready(zoom_m_ready), .m_rvalid(zoom_m_rvalid), .m_rdata(zoom_m_rdata),
   .z_req(arb_z_req), .z_line(arb_z_line), .z_ready(arb_z_ready), .z_rvalid(arb_z_rvalid), .z_rdata(arb_rdata));
wire mir_we, mir_busy, mir_ovf; wire [28:0] mir_addr; wire [63:0] mir_din; wire [7:0] mir_be;
gnet_ddr3_mirror mirror (.clk_src(clk_cpu), .w_req(ch3_req && !ch3_rnw), .w_addr(ch3_addr), .w_din(ch3_din), .w_be(ch3_be),
   .stall(gnet_ch3_stall), .clk2x(clk_2x), .g_we(mir_we), .g_addr(mir_addr), .g_din(mir_din), .g_be(mir_be), .g_busy(mir_busy), .ovf(mir_ovf));
assign dbg_mir_ovf = mir_ovf;
reg [2:0] arb_rst_s = 3'b111;
always @(posedge clk_2x) arb_rst_s <= {arb_rst_s[1:0], sdram_init};
`ifdef GNET_DDR3_LOAD
wire        arb_g_rd, arb_g_we, arb_g_busy, arb_g_dout_ready;
wire [28:0] arb_g_addr;
wire  [7:0] arb_g_burstcnt, arb_g_be;
wire [63:0] arb_g_din;
wire        flc_g_rd, flc_g_busy, flc_g_dout_ready;
wire [28:0] flc_g_addr;
wire  [7:0] flc_g_burstcnt;
gnet_ddr3_gmux gmux
(
	.a_we(mir_we),
	.a_addr(mir_addr),
	.a_din(mir_din),
	.a_be(mir_be),
	.a_busy(mir_busy),
	.b_rd(flc_g_rd),
	.b_we(1'b0),
	.b_addr(flc_g_addr),
	.b_burstcnt(flc_g_burstcnt),
	.b_din(64'd0),
	.b_be(8'hFF),
	.b_busy(flc_g_busy),
	.b_dout_ready(flc_g_dout_ready),
	.g_rd(arb_g_rd),
	.g_we(arb_g_we),
	.g_addr(arb_g_addr),
	.g_burstcnt(arb_g_burstcnt),
	.g_din(arb_g_din),
	.g_be(arb_g_be),
	.g_busy(arb_g_busy),
	.g_dout_ready(arb_g_dout_ready)
);
gnet_ddr3_flcopy flcopy
(
	.clk1x(clk_1x),
	.start(flc_start),
	.len(flc_len),
	.busy(flc_busy),
	.w_req(flc_wreq),
	.w_rnw(flc_wrnw),
	.w_addr(flc_waddr),
	.w_data(flc_wdata),
	.w_done(sdramCh3_done),
	.r_data(flc_rdata),
	.clk2x(clk_2x),
	.g_rd(flc_g_rd),
	.g_addr(flc_g_addr),
	.g_burstcnt(flc_g_burstcnt),
	.g_busy(flc_g_busy),
	.g_dout_ready(flc_g_dout_ready),
	.g_dout(arb_rdata),
	.sum_copy(flc_sum_copy),
	.sum_sdram(flc_sum_sdram),
	.sum_ddr3(flc_sum_ddr3),
	.flags(flc_flags),
	.tmo_info()
);
`endif
wire [28:0] arb_ddr_addr;
gnet_ddr3_arb ddr3_arb (.clk(clk_2x), .rst(arb_rst_s[2]),
   .ddr_busy(ddr3_BUSY), .ddr_burstcnt(ddr3_BURSTCNT), .ddr_addr(arb_ddr_addr), .ddr_dout(ddr3_DOUT),
   .ddr_dout_ready(ddr3_DOUT_READY), .ddr_rd(ddr3_RD), .ddr_din(ddr3_DIN), .ddr_be(ddr3_BE), .ddr_we(ddr3_WE),
   .rot_clk(clkvid), .rot_we(1'b0), .rot_addr(29'd0), .rot_din(64'd0), .rot_be(8'd0),
   .z_req(arb_z_req), .z_line(arb_z_line), .z_ready(arb_z_ready), .z_rvalid(arb_z_rvalid),
`ifdef GNET_DDR3_LOAD
   .g_rd(arb_g_rd), .g_we(arb_g_we), .g_addr(arb_g_addr), .g_burstcnt(arb_g_burstcnt), .g_din(arb_g_din), .g_be(arb_g_be),
   .g_busy(arb_g_busy), .g_dout_ready(arb_g_dout_ready),
`else
   .g_rd(1'b0), .g_we(mir_we), .g_addr(mir_addr), .g_burstcnt(8'd1), .g_din(mir_din), .g_be(mir_be), .g_busy(mir_busy), .g_dout_ready(),
`endif
   .c_rd(core_ddr3_RD), .c_we(core_ddr3_WE), .c_addr({4'b0011, core_ddr3_ADDR[27:3]}), .c_burstcnt(core_ddr3_BURSTCNT),
   .c_din(core_ddr3_DIN), .c_be(core_ddr3_BE), .c_busy(core_ddr3_BUSY), .c_dout_ready(core_ddr3_DOUT_READY),
   .rdata(arb_rdata), .rot_ovf(), .rot_hiwater(), .own_ovf(dbg_own_ovf));
assign core_ddr3_DOUT = arb_rdata;
// the model takes a byte address in its 256 MB window (word address & 0x1FFFFFF)
assign ddr3_ADDR = {arb_ddr_addr[24:0], 3'b000};
