// ---------------------------------------------------------------------------
// MiSTer download path of PSX.sv (zn2-layer 4ae0210, `ifdef GNET_ZN2),
// copied for the full-system simulation (docs/fullsys_sim.md 7). Statements
// are verbatim apart from clk_1x -> clk1x and the OSD/framework inputs tied
// to their defaults (buttons, status, cdDownloadReset). PSX.sv line numbers
// at 4ae0210 in brackets.
// ---------------------------------------------------------------------------
wire        clk_1x = clk1x;
wire  [1:0] buttons = 2'b00;
wire [127:0] status = 128'd0;
wire        cdDownloadReset = 1'b0;
wire        sdramCh3_done;

// [531-536]
reg bios_download, exe_download, cdinfo_download, code_download;
always @(posedge clk_1x) begin
	bios_download    <= ioctl_download & (ioctl_index[5:0] == 0);
	exe_download     <= ioctl_download & (ioctl_index == 1);
	cdinfo_download  <= ioctl_download & (ioctl_index == 251);
	code_download    <= ioctl_download & (ioctl_index == 255);
end

// [547-604]
reg flash_download, keys_download, meta_download, card_download, ee_download, dip_download;
always @(posedge clk_1x) begin
	flash_download <= ioctl_download & (ioctl_index == 3);
	keys_download  <= ioctl_download & (ioctl_index == 2);
	meta_download  <= ioctl_download & (ioctl_index == 4);
	card_download  <= ioctl_download & (ioctl_index == 5);
	ee_download    <= ioctl_download & (ioctl_index == 6);
	dip_download   <= ioctl_download & (ioctl_index == 254);
end
wire gnet_download = flash_download | keys_download | meta_download | card_download | ee_download;

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
wire zn_card_present = zn_card_loaded;
wire zn_key_valid    = zn_card_loaded;
wire [3:0] zn_dsw    = zn_sw0[3:0];
wire zn_jp1          = zn_sw0[4];

// [204-214], [1001-1006]
wire       zn_wd_reset;
reg  [7:0] zn_wd_hold = 0;
always @(posedge clk_1x) begin
	if (zn_wd_reset & ~status[100]) zn_wd_hold <= 8'hFF;
	else if (zn_wd_hold) zn_wd_hold <= zn_wd_hold - 1'd1;
end
wire reset_or = RESET | buttons[1] | status[0] | bios_download | exe_download | cdDownloadReset | gnet_download | (zn_wd_hold != 0);
reg reset = 0;
always @(posedge clk_1x) begin
	reset <= 0;
	if (reset_or) reset <= 1;
end
assign dbg_reset = reset;

// [613-621], [658-684]
reg [26:0] ramdownload_wraddr;
wire gnet_flash_dl = flash_download;
reg [31:0] ramdownload_wrdata;
reg        ramdownload_wr;
localparam EXE_START = 16777216;
initial ioctl_wait = 0;
always @(posedge clk_1x) begin
	ramdownload_wr <= 0;
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
   end else begin
      ioctl_wait <= 0;
	end
end

// [1489-1495], sdram ch3
wire        dl_sel   = exe_download | bios_download | gnet_flash_dl;
wire [26:0] ch3_addr = dl_sel ? ramdownload_wraddr : zn_fl_addr;
wire [31:0] ch3_din  = dl_sel ? ramdownload_wrdata : zn_fl_din;
wire        ch3_req  = dl_sel ? ramdownload_wr     : zn_fl_req;
wire        ch3_rnw  = dl_sel ? 1'b0               : zn_fl_rnw;
wire  [3:0] ch3_be   = dl_sel ? 4'b1111            : zn_fl_be;
wire        ch3_ready;
wire [31:0] ch3_dout;
assign sdramCh3_done = ch3_ready;
assign zn_fl_ready = ch3_ready;
assign zn_fl_dout  = ch3_dout;
