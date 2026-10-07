//============================================================================
//  PSX
//  Copyright (C) 2019 Robert Peip
//
//  Port to MiSTer
//  Copyright (C) 2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

assign HDMI_FREEZE = 1'b0;
assign HDMI_BOB_DEINT = status[41];

assign ADC_BUS  = 'Z;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;

assign AUDIO_S   = 1;
assign AUDIO_MIX = status[8:7];

assign LED_USER  = exe_download | bk_pending;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

wire [ 3:0] frameindex;
wire [11:0] DisplayWidth;
wire [11:0] DisplayHeight;
wire [ 9:0] DisplayOffsetX;
wire [ 8:0] DisplayOffsetY;

`ifdef GNET_DDR3_ARB
// core client of gnet_ddr3_arb (psx_mister's DDRAM side)
wire        core_ddr_busy, core_ddr_dout_ready, core_ddr_rd, core_ddr_we;
wire  [7:0] core_ddr_burstcnt, core_ddr_be;
wire [28:0] core_ddr_addr;
wire [63:0] core_ddr_din, arb_rdata;
// flash mirror stall to zn2_ch3_arb
wire        gnet_ch3_stall;
`endif

`ifdef GNET_SHELL
// Rotation option wires of the release shell, declared here, before their
// first use in the FB_* mux below; driven in the shell's status block
// (Orientation and Rotate Direction OSD items, docs/m4_shell.md).
wire        gnet_rot_en, gnet_rot_ccw;
`endif

`ifdef GNET_DDR3_ARB
// G-NET rotation (docs/ddr3_arbiter.md 4): with gnet_rot_en the frame buffer
// is screen_rotate's (DDR3 0x24000000), shown by the scaler; otherwise the
// core's own FB mode as below. gnet_rot_en and gnet_rot_ccw come from the
// release shell (GNET_SHELL: declared above, driven in its status block);
// without the shell they are declared here and tied off in the DDR3 block.
`ifndef GNET_SHELL
wire        gnet_rot_en, gnet_rot_ccw;
`endif
// screen_rotate active (to hps_io, as the MiSTer template)
wire        video_rotated;
wire        rot_fb_en;
wire  [4:0] rot_fb_format;
wire [11:0] rot_fb_width, rot_fb_height;
wire [31:0] rot_fb_base;
wire [13:0] rot_fb_stride;
assign FB_BASE    = gnet_rot_en ? rot_fb_base   : status[11] ? 32'h30000000 : {8'h30, frameindex, DisplayOffsetY, DisplayOffsetX, 1'b0};
assign FB_EN      = gnet_rot_en ? rot_fb_en     : (status[14] || video_fbmode);
assign FB_FORMAT  = gnet_rot_en ? rot_fb_format : (status[10] || video_fb24) ? 5'b00101 : 5'b01100;
assign FB_WIDTH   = gnet_rot_en ? rot_fb_width  : status[11] ? 12'd1024 : DisplayWidth;
assign FB_HEIGHT  = gnet_rot_en ? rot_fb_height : status[11] ? 12'd512  : DisplayHeight;
assign FB_STRIDE  = gnet_rot_en ? rot_fb_stride : 14'd2048;
`else
assign FB_BASE    = status[11] ? 32'h30000000 : {8'h30, frameindex, DisplayOffsetY, DisplayOffsetX, 1'b0};
assign FB_EN      = (status[14] || video_fbmode);
assign FB_FORMAT  = (status[10] || video_fb24) ? 5'b00101 : 5'b01100;
assign FB_WIDTH   = status[11] ? 12'd1024 : DisplayWidth;
assign FB_HEIGHT  = status[11] ? 12'd512  : DisplayHeight;
assign FB_STRIDE  = 14'd2048;
`endif
assign FB_FORCE_BLANK = 0;


///////////////////////  CLOCK/RESET  ///////////////////////////////////

wire pll_locked;
wire clk_1x;
wire clk_2x;
wire clk_3x;
wire clk_vid;

`ifdef GNET_CPU50
// R1 (docs/r1_cpu_domain_design.md): CPU group at exactly 50.000 MHz with its
// 2x clock at 100.000 MHz from a second PLL (rtl/gnet/pll_cpu.v); clk_1x and
// clk_2x keep the emu PLL for the GPU, SPU, DDR3 and framework blocks.
wire clk_cpu;
wire clk_cpu2x;
wire pll_cpu_locked;

// The reference goes over the global clock network, not the pin's dedicated
// path: FPGA_CLK2_50 (PIN_Y13) reaches only the three fractional PLLs at the
// bottom of the die, and pll_hdmi, the emu PLL and pll_vid_fixed occupy them
// (first GNET_CPU50_B1 fit, Error 175001/11238). From the global network the
// fitter can place pll_cpu in a free fractional PLL elsewhere. Still exactly
// the 50 MHz crystal, so 50.000 / 100.000 MHz stay exact.
wire clk_50m_gclk;

cyclonev_clkena #(.clock_type("Global Clock"), .ena_register_mode("always enabled")) pll_cpu_refclk
(
	.inclk(CLK_50M),
	.ena(1'b1),
	.enaout(),
	.outclk(clk_50m_gclk)
);

pll_cpu pll_cpu
(
	.refclk(clk_50m_gclk),
	.rst(0),
	.outclk_0(clk_cpu),
	.outclk_1(clk_cpu2x),
	.locked(pll_cpu_locked)
);
`endif

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_1x),
	.outclk_1(clk_2x),
	.outclk_2(clk_3x),
	.locked(pll_locked)
);

`ifdef GNET_LEAN
// G-NET: fixed 53.693175 MHz video clock, no runtime PLL reconfiguration
// (rtl/gnet/pll_vid_fixed.v). FFrequest is kept so the code below compiles.
pll_vid_fixed pll2
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid),
	.locked()
);

wire FFrequest = joy[17] && ~FB_LL && ~DIRECT_VIDEO;
wire syncVideoOut = 0;
`else
pll2 pll2
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid),
   .reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);


wire FFrequest = joy[17] && ~FB_LL && ~DIRECT_VIDEO;
wire syncVideoOut = 0; //status[57] && ~FB_LL && ~DIRECT_VIDEO;
wire syncVideoClock = 0; //status[56] && ~FB_LL && ~DIRECT_VIDEO;

always @(posedge CLK_50M) begin : cfg_block
	reg pald = 0, pald2 = 0;
	reg pdbg = 0, pdbg2 = 0;
	reg pffw = 0, pffw2 = 0;
	reg [3:0] state = 0;

	pald  <= isPal;
	pald2 <= pald;

	pdbg  <= syncVideoClock;
	pdbg2 <= pdbg;

	pffw  <= fast_forward;
	pffw2 <= pffw;

	cfg_write <= 0;
	if(pald2 != pald || pdbg2 != pdbg || pffw2 != pffw) state <= 1;

	if(!cfg_waitrequest) begin
		if(state) state<=state+1'd1;
		case(state)
			1: begin
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
         3: begin
					cfg_address <= 5;
					cfg_data <= pffw2 ? 131842 : pdbg2 ? 771 : 1028;
					cfg_write <= 1;
				end
			5: begin
					cfg_address <= 7;
					cfg_data <= pffw2 ? 2147483648 : pdbg2 ? 551954751 : pald2 ? 2201376898 : 2537930535;
					cfg_write <= 1;
				end
			7: begin
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end

`endif

reg fast_forward;
reg ff_latch;

always @(posedge clk_1x) begin : ffwd
	reg last_ffw;
	reg ff_was_held;
	longint ff_count;

	last_ffw <= FFrequest;

	if (FFrequest)
		ff_count <= ff_count + 1;

	if (~last_ffw & FFrequest) begin
		ff_latch <= 0;
		ff_count <= 0;
	end

	if ((last_ffw & ~FFrequest)) begin
		ff_was_held <= 0;

		if (ff_count < 10000000 && ~ff_was_held) begin
			ff_was_held <= 1;
			ff_latch <= 1;
		end
	end

	fast_forward <= (FFrequest | ff_latch);
end

`ifdef GNET_CPU50
reg [1:0] pll_cpu_locked_s = 0;
always @(posedge clk_1x) pll_cpu_locked_s <= {pll_cpu_locked_s[0], pll_cpu_locked};
`endif
// MB3773 watchdog period in seconds (gnet_ctrl.sv WD_TIMEOUT_S), passed
// to zn2_board through psx_mister and psx_top; the pause grace below
// follows it
localparam GNET_WD_TIMEOUT_S = 8;
`ifdef GNET_ZN2
// G-NET: the MB3773 watchdog (gnet_ctrl, GNET_WD_TIMEOUT_S) resets the
// board unless disabled in the OSD; every G-NET download also holds reset
wire       zn_wd_reset;
wire       gnet_download;
reg  [7:0] zn_wd_hold = 0;
`ifdef GNET_SHELL
// The MB3773 model (gnet_ctrl) counts on the raw clock, so a pause longer
// than its period would let it expire. Its reset is ignored while paused
// and for the period plus 0.5 s after (8.5 s): the game kicks it within a
// frame once running, and a hung game still resets one period later
// (docs/m4_shell.md).
wire       zn_wd_mask;
`else
wire       zn_wd_mask = 1'b0;
`endif
always @(posedge clk_1x) begin
	if (zn_wd_reset & ~status[100] & ~zn_wd_mask) zn_wd_hold <= 8'hFF;
	else if (zn_wd_hold) zn_wd_hold <= zn_wd_hold - 1'd1;
end
`ifdef GNET_CPU50
wire reset_or = RESET | buttons[1] | status[0] | bios_download | exe_download | cdDownloadReset | gnet_download | (zn_wd_hold != 0) | ~pll_cpu_locked_s[1];
`else
wire reset_or = RESET | buttons[1] | status[0] | bios_download | exe_download | cdDownloadReset | gnet_download | (zn_wd_hold != 0);
`endif
`elsif GNET_CPU50
wire reset_or = RESET | buttons[1] | status[0] | bios_download | exe_download | cdDownloadReset | ~pll_cpu_locked_s[1];
`else
wire reset_or = RESET | buttons[1] | status[0] | bios_download | exe_download | cdDownloadReset;
`endif

////////////////////////////  HPS I/O  //////////////////////////////////

// Status Bit Map: (0..31 => "O", 32..63 => "o")
// 0         1         2         3          4         5         6          7         8         9
// 01234567890123456789012345678901 23456789012345678901234567890123 45678901234567890123456789012345
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
//  XXXX XXXXXX XXXXXX XXXXX  XX XX XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX XXXXXXXXXXXXXXXXXXXXXXXXXXXXX

`include "build_id.v"
`ifdef GNET_ZN2
// G-NET (docs/zn2_layer_design.md 13.5, 13.6): arcade menu; DIP switches
// S551 and JP1 come from the MRA (ioctl index 254). Video option bits keep
// their PSX numbers.
`ifdef GNET_SHELL
// Release shell (docs/m4_shell.md, minimum standard). New bits: 102
// Orientation, 103 Rotate direction, 104 Flip, 106:105 Volume, 110:107 CRT H
// position, 113:111 CRT V position, 116:114 Scandoubler Fx, 119:117 SFX
// level (GNET_ZOOM: SPU gain in zoom_mix); 64 keeps its
// PSX meaning (Pause when OSD open). Also: 100 Watchdog, 101 debug overlay
// (docs/hw_debug_overlay.md). Menu mask: H0 direct_video, H1
// horizontal set, H2 no rotation available, H3 H2 or Orientation Horizontal.
parameter CONF_STR = {
	"GNET;;",
	"-;",
	"H0O[33:32],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H0O[35:34],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"H2O[102],Orientation,Vertical,Horizontal;",
	"H3O[103],Rotate Direction,CCW,CW;",
	"H1O[104],Flip Screen,Off,On;",
	"O[116:114],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O[110:107],CRT H Position,0,+2,+4,+6,+8,+10,+12,+14,-16,-14,-12,-10,-8,-6,-4,-2;",
	"O[113:111],CRT V Position,0,+1,+2,+3,-4,-3,-2,-1;",
	"-;",
	"O[64],Pause when OSD is open,On,Off;",
	"O[106:105],Volume,Normal,+6 dB,-6 dB,-12 dB;",
`ifdef GNET_ZOOM
	"O[119:117],SFX Level,0.3 (MAME),0.45,0.6,0.9,1.2,1.5;",
`endif
	"-;",
	"DIP;",
	"-;",
	"O[100],Watchdog,On,Off;",
	"O[101],Debug overlay,Off,On;",
	"R0,Reset;",
	"J1,Button 1,Button 2,Button 3,Start,Coin,Service,Test,Pause;",
	"jn,A,B,X,Start,Select,L,R;",
	"V,v",`BUILD_DATE
};
`else
parameter CONF_STR = {
	"GNET;;",
	"-;",
	"DIP;",
	"-;",
	"O[100],Watchdog,On,Off;",
	"O[101],Debug overlay,Off,On;",
	"O[33:32],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[35:34],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"O[41],Deinterlacing,Weave,Bob;",
	"-;",
	"R0,Reset;",
	"J1,Button 1,Button 2,Button 3,Start,Coin,Service,Test;",
	"jn,A,B,X,Start,Select,L,R;",
	"V,v",`BUILD_DATE
};
`endif
`else
parameter CONF_STR = {
	"PSX;SS3E000000:400000;",
	"H7S1,CUECHD,Load CD;",
	"h7-,Reload core for CD;",
	"F1,EXE,Load Exe;",
	"-;",
	"d6C,Cheats;",
	"h6O[6],Cheats Enabled,Yes,No;",
	"-;",
	"hA-,Memcard Status: not saved;",
	"HB-,Memcard Status: saved;",
	"hC-,Memcard Status: saving...;",
	"RD,Save Memory Cards;",
	"O[71],Save to SDCard,On Open OSD,Manual;",
	"SC2,SAVMCD,Mount Memory Card 1;",
	"SC3,SAVMCD,Mount Memory Card 2;",
	"O[63],Automount Memory Card 1,Yes,No;",
	"-;",
	"O[36],Savestates to SDCard,On,Off;",
	"O[68],Autoincrement Slot,Off,On;",
	"O[38:37],Savestate Slot,1,2,3,4;",
	"RH,Save state (Alt-F1);",
	"RI,Restore state (F1);",
	"-;",
	"O[40:39],System Type,Auto,NTSC-U,NTSC-J,PAL;",
	"-;",
	"D8O[48:45],Pad1,Dualshock,Off,Digital,Analog,GunCon,NeGcon,Wheel-NegCon,Wheel-Analog,Mouse,Justifier,SNAC-port1,Analog Joystick,Pop'n;",
	"D8O[52:49],Pad2,Dualshock,Off,Digital,Analog,GunCon,NeGcon,Wheel-NegCon,Wheel-Analog,Mouse,Justifier,SNAC-port2,Analog Joystick,Pop'n;",
	"D8h0O[66],SNAC MemCard,Virtual,Real;",
	"D8hFO[91],NeGcon Rumble,Off,On;",
	"D8h2O[9],Show Crosshair,Off,On;",
	"D8h4O[31],DS Mode,L3+R3+Up/Dn | Click,L1+L2+R1+R2+Up/Dn;",
	"O[57:56],Multitap,Off,Port1: 4 x Digital,Port1: 4 x Analog;",
	"-;",

	"P1,Video & Audio;",
	"P1-;",
	"P1O[33:32],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[35:34],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1-;",
	"DEP1O[62],Fixed HBlank,On,Off;",
	"DEP1O[55],Fixed VBlank,Off,On;",
	"d5P1O[4:3],Vertical Crop,Off,On(224/270),On(216/256);",
	"P1O[67],Horizontal Crop,Off,On;",
	"P1O[61],Black Transitions,On,Off;",
	"P1O[41],Deinterlacing,Weave,Bob;",
	"P1O[60],Sync 480i for HDMI,Off,On;",
	"P1O[24],Rotate,Off,On;",
	"P1-;",
	"P1O[22],Dithering,On,Off;",
	"DEP1O[84],Render 24 Bit,Off,On;",
	"P1O[73],Dither 24 Bit for VGA,Off,On;",
	"P1-;",
	"P1O[89],480i to 480p Hack,Off,On;",
	"P1O[54:53],Widescreen Hack,Off,3:2,5:3,16:9;",
	"P1O[82:81],Texture Filter,Off,All Polygon,Dithered,Dith+Shaded;",
	"hDP1O[87:86],Filter Strength,25%,50%,75%,100%;",
	"hDP1O[83],Filter 2D Detect,Off,On;",
	"P1-;",
	"d1P1O[44],SPU RAM select,DDR3,SDRAM2;",
	"P1O[8:7],Stereo Mix,None,25%,50%,100%;",

	"P2,Miscellaneous;",
	"P2-;",
	"P2O[16],Fastboot,Off,On;",
	"P2O[42],CD Lid,Closed,Open;",
	"P2O[64],Pause when OSD open,On,Off;",
	"P2-;",
	"P2-,(U) = unsafe -> can crash;",
	"P2O[80:79],Turbo(Cheats Off),Off,Low(U),Medium(U),High(U);",
	"P2O[72],Pause when CD slow,On,Off(U);",
	"P2O[15],PAL 60Hz Hack,Off,On(U);",
	"P2O[21],CD Fast Seek,Off,On(U);",
	"P2O[77:75],CD Speed,Original,Forced 1X(U),Forced 2X(U),Hack 4X(U),Hack 6X(U),Hack 8X(U);",
	"P2O[78],Limit Max CD Speed,Off,On(U);",
	"P2O[85],RAM(Homebrew),2 MByte,8 MByte(U);",
	"P2O[90],GPU Slowdown,Off,On(U);",
	"P2O[92],Old GPU(CXD8514Q),Off,On;",
	"P2-;",
	"P2O[28],FPS Overlay,Off,On;",
	"P2O[74],Error Overlay,Off,On;",
	"P2O[59],CD Slow Overlay,Off,On;",
	"h9P2O[70],CD Overlay,Read,Read+Seek;",

	"h3-;",
	"h3P3,Debug;",
	"h3P3-;",
	"h3P3O[14],DDR3 Framebuffer,Off,On;",
	"h3P3O[10],DDR3 FB Color,16,24;",
	"h3P3O[11],VRAMViewer,Off,On;",
	"h3P3O[30],Sound,On,Off;",
	"h3P3O[43],RepTimingSPUDMA,Off,On;",
	"h3P3O[27],Textures,On,Off;",
	"h3P3O[69],LBA Overlay,Off,On;",
	"h3P3O[88],Fast CD DMA Timing,Off,On;",
	"h3P3T1,Advance Pause;",
	"h3P3T2,Sound IRQ Trigger;",

	"-   ;",
	"R0,Reset;",
	"J1,Triangle(NeGcon B),O(Gun Fire|NeGcon A),X(Gun B|NeGcon I),[](NeGcon II),Select,Start(Gun A),L1,R1,L2,R2,L3,R3,Savestates,Fastforward,Pause(Core),Toggle Dualshock;",
	"jn,X,A,B,Y,Select,Start,L,R;",
	"I,",
	"Load=DPAD Up|Save=Down|Slot=L+R,",
	"Active Slot 1,",
	"Active Slot 2,",
	"Active Slot 3,",
	"Active Slot 4,",
	"Save to state 1,",
	"Restore state 1,",
	"Save to state 2,",
	"Restore state 2,",
	"Save to state 3,",
	"Restore state 3,",
	"Save to state 4,",
	"Restore state 4,",
	"Rewinding...,",
	"Slot 1 Analog,",
	"Slot 1 Digital,",
	"Slot 2 Analog,",
	"Slot 2 Digital,",
	"Region Unknown->US,",
	"Region JP,",
	"Region US,",
	"Region EU,",
	"Saving Memcard,",
	"Unsafe option used!;",
	"V,v",`BUILD_DATE
};
`endif

reg dbg_enabled = 0;
wire  [1:0] buttons;
wire [127:0] status;
`ifdef GNET_SHELL
// Game configuration from the MRA (ioctl index 7, one byte): bit 0 = the set
// is vertical (ROT270 in MAME taitogn.cpp: psyvaria, psyvarij, psyvarrv,
// xiistag, shikigam, shikigama). Default horizontal.
// Bit 1 = the set has no Taito Zoom board (MAME init_nozoom, taitogn.cpp
// 416-419: otenamih, otenamhf, zokuoten, zokuotena, zooo, sianniv and the 2011
// conversions): the Zoom's MN10200 stays in reset whatever the game writes to
// the control register's bit 4 (taitogn.cpp 519-535). Default: Zoom present.
// Bits 3:2 = the controls (gnet_inmode, see the keyboard block below):
// 0 joysticks, 1 mahjong panel and P1 joystick (Mahjong Oh), 2 mahjong panel
// only (Usagi), 3 RC wheel and trigger (Go By RC, RC De Go).
reg  gnet_vertical = 1'b0;
reg  gnet_nozoom   = 1'b0;
reg  [1:0] gnet_inmode = 2'd0;
wire DIRECT_VIDEO;
// EEPROM NVRAM save (MRA <nvram index="6" size="2048"/>), see the loader
wire        ioctl_upload;
reg         nv_upload_req = 1'b0;
wire [15:0] nv_din;
// Rotation interface to the DDR3 arbiter branch (ddr3-arb-int,
// docs/ddr3_arbiter.md): that branch owns screen_rotate, its FB_* and
// video_rotated outputs and the DDRAM FIFO, and takes exactly these two
// wires. gnet_rot_en: rotate the picture (vertical set, Orientation
// Vertical, HDMI only); gnet_rot_ccw: direction (ROT270 sets stand upright
// with CCW). Flip Screen is not part of it: it turns the picture 180
// degrees in the GPU's video out (rotate180) before any rotation, so it
// applies on CRT and HDMI alike.
// (declared near the top of the module, before the FB_* mux uses them)
assign gnet_rot_en  = gnet_vertical & ~status[102] & ~DIRECT_VIDEO;
assign gnet_rot_ccw = ~status[103];
// The Orientation and Rotate Direction items stay hidden until rotation is
// built in: the arbiter branch defines GNET_ROT_DDR where it connects
// screen_rotate.
`ifdef GNET_ROT_DDR
localparam GNET_ROT_READY = 1'b1;
`else
localparam GNET_ROT_READY = 1'b0;
`endif
wire gnet_rot_hide = DIRECT_VIDEO | ~gnet_vertical | ~GNET_ROT_READY;
wire [15:0] status_menumask = {12'd0, (gnet_rot_hide | status[102]), gnet_rot_hide, ~gnet_vertical, DIRECT_VIDEO};
`else
wire [15:0] status_menumask = {(PadPortNeGcon1 | PadPortNeGcon2), hack_480p, filter_on, saving_memcard, (bk_pending | saving_memcard), bk_pending, status[59], multitap, biosMod, ~TURBO_MEM, (status[55] && ~hack_480p), (PadPortDS1 | PadPortDS2), dbg_enabled, (PadPortGunCon1 | PadPortGunCon2 | PadPortJustif1 | PadPortJustif2), SDRAM2_EN, (snacPort1 | snacPort2)};
`endif
wire        forced_scandoubler;
reg  [31:0] sd_lba0 = 0;
reg  [31:0] sd_lba1;
reg  [ 6:0] sd_lba2;
reg  [ 6:0] sd_lba3;
reg   [3:0] sd_rd;
reg   [3:0] sd_wr;
wire  [3:0] sd_ack;
wire  [8:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din2;
wire [15:0] sd_buff_din3;
wire        sd_buff_wr;
wire  [3:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire        ioctl_download;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_wr;
wire  [7:0] ioctl_index;
reg         ioctl_wait = 0;

wire [19:0] joy;
wire [19:0] joy_unmod;
wire [19:0] joy2;
wire [19:0] joy3;
wire [19:0] joy4;

wire [10:0] ps2_key;

wire [21:0] gamma_bus;
wire [15:0] sdram_sz;

wire [15:0] joystick_analog_l0;
wire [15:0] joystick_analog_r0;
wire [15:0] joystick_analog_l1;
wire [15:0] joystick_analog_r1;
wire [15:0] joystick_analog_l2;
wire [15:0] joystick_analog_r2;
wire [15:0] joystick_analog_l3;
wire [15:0] joystick_analog_r3;

wire [7:0] paddle_0;

wire [24:0] mouse;

wire [15:0] joystick1_rumble;
wire [15:0] joystick2_rumble;
wire [15:0] joystick3_rumble;
wire [15:0] joystick4_rumble;
wire [32:0] RTC_time;

wire filter_on = (status[82:81] == 2'b00) ? 1'b0 : 1'b1;

assign HDMI_BLACKOUT = ~status[61];

wire [127:0] status_in = {status[127:39],ss_slot,status[36:19], 2'b00, status[16:0]};

wire bk_pending;
`ifndef GNET_SHELL
wire DIRECT_VIDEO;
`endif

hps_io #(.CONF_STR(CONF_STR), .WIDE(1), .VDNUM(4), .BLKSZ(3)) hps_io
(
	.clk_sys(clk_1x),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(EXT_BUS),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),

	.joystick_0(joy_unmod),
	.joystick_1(joy2),
	.joystick_2(joy3),
	.joystick_3(joy4),
	.ps2_key(ps2_key),

	.status(status),
	.status_in(status_in),
	.status_set(statusUpdate),
	.status_menumask(status_menumask),
	.info_req(psx_info_req),
	.info(psx_info),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr(ioctl_wr),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait),
`ifdef GNET_SHELL
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(nv_upload_req),
	.ioctl_upload_index(8'd6),
	.ioctl_din(nv_din),
`endif

	.sd_lba('{sd_lba0, sd_lba1, sd_lba2, sd_lba3}),
	.sd_blk_cnt('{0,0, 0, 0}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din('{0, 0, sd_buff_din2, sd_buff_din3}),
	.sd_buff_wr(sd_buff_wr),

	.TIMESTAMP(RTC_time),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.sdram_sz(sdram_sz),
	.gamma_bus(gamma_bus),
`ifdef GNET_DDR3_ARB
	.video_rotated(video_rotated),
`endif

   .joystick_l_analog_0(joystick_analog_l0),
   .joystick_r_analog_0(joystick_analog_r0),
   .joystick_l_analog_1(joystick_analog_l1),
   .joystick_r_analog_1(joystick_analog_r1),
   .joystick_l_analog_2(joystick_analog_l2),
   .joystick_r_analog_2(joystick_analog_r2),
   .joystick_l_analog_3(joystick_analog_l3),
   .joystick_r_analog_3(joystick_analog_r3),
   .ps2_mouse(mouse),
   .joystick_0_rumble(paused ? 16'h0000 : joystick1_rumble),
   .joystick_1_rumble(paused ? 16'h0000 : joystick2_rumble),

   .paddle_0(paddle_0),

   .direct_video(DIRECT_VIDEO)
);

assign joy = joy_unmod[16] ? 20'b0 : joy_unmod;

assign sd_rd[0] = 0;
assign sd_wr[0] = 0;

assign sd_wr[1] = 0;

wire [35:0] EXT_BUS;
wire        heartbeat;

hps_ext hps_ext
(
	.clk_sys(clk_1x),
	.EXT_BUS(EXT_BUS),
	.heartbeat(heartbeat)
);


//////////////////////////  ROM DETECT  /////////////////////////////////

reg bios_download, exe_download, cdinfo_download, code_download;
always @(posedge clk_1x) begin
	bios_download    <= ioctl_download & (ioctl_index[5:0] == 0);
	exe_download     <= ioctl_download & (ioctl_index == 1);
	cdinfo_download  <= ioctl_download & (ioctl_index == 251);
	code_download    <= ioctl_download & (ioctl_index == 255);
end

`ifdef GNET_ZN2
// G-NET loader (docs/zn2_layer_design.md 13.5). ioctl is 16 bits wide.
//   2   CAT702 keys, tt10.ic652 then tt16.u17 (16 bytes)
//   3   flash images as SDRAM 0x1000000-0x19FFFFF: U30 at 0, U27 at 0x200000,
//       U56 0x400000, U55 0x600000, U29 0x800000 (little-endian 16-bit words)
//   4   card metadata: IDNT 000h, CIS 200h, KEY 300h (1 KB)
//   5   card image (40,960,000 bytes) to DDR3
//   6   EEPROM (2 KB)
//   254 DIP switches: byte 0 bits 3-0 S551 (1 = off), bit 4 JP1
reg flash_download, keys_download, meta_download, card_download, ee_download, dip_download;
always @(posedge clk_1x) begin
	flash_download <= ioctl_download & (ioctl_index == 3);
	keys_download  <= ioctl_download & (ioctl_index == 2);
	meta_download  <= ioctl_download & (ioctl_index == 4);
	card_download  <= ioctl_download & (ioctl_index == 5);
	ee_download    <= ioctl_download & (ioctl_index == 6);
	dip_download   <= ioctl_download & (ioctl_index == 254);
end
assign gnet_download = flash_download | keys_download | meta_download | card_download | ee_download;

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
wire       zn_ld_busy;      // loader FIFO nearly full (GNET_CPU50: zn2_board on clk_cpu); 0 otherwise
wire        zn_fl_req, zn_fl_rnw;
wire [26:0] zn_fl_addr;
wire [31:0] zn_fl_din, zn_fl_dout;
wire  [3:0] zn_fl_be;
`ifdef GNET_CPU50
wire        zn_fl_ready_c;   // flash port ready on clk_cpu (zn2_ch3_arb)
`endif
// debug overlay (docs/hw_debug_overlay.md): word index and word on the CPU
// group clock (clk_cpu with GNET_CPU50, else clk_1x)
wire  [3:0] zn_dbg_idx;
wire [31:0] zn_dbg_word;
`ifdef GNET_ZOOM
// Taito Zoom sound board (docs/zoom_board_design.md 14; needs GNET_ZN2 and
// GNET_CPU50, psx_top asserts it). zoom_m_*: zoom_board's flash area line
// port exactly as zoom_memarb drives it, on clk_1x (m_req and m_line held
// until an edge with m_ready, m_line = flash area byte offset / 8, one
// m_rvalid per line in order with m_rdata, flash byte 8L in bits 7:0, up to
// 8 lines open). Memory behind it:
//   GNET_DDR3_ARB    the DDR3 arbiter (branch ddr3-arb-int), flash area
//                    mirrored at DDR3 0x31000000; ZSG-2 INFL 8
//   GNET_ZOOM_SDRAM  temporary path for the first test build: the SDRAM
//                    flash area (0x1000000) through rtl/gnet/zoom_sdram_link
//                    and zn2_ch3_arb port c, one line at a time
// The two are exclusive: with GNET_DDR3_ARB the arbiter drives zoom_m_ready,
// zoom_m_rvalid and zoom_m_rdata and GNET_ZOOM_SDRAM is ignored. With neither
// nothing answers the line port and the Zoom stays silent.
// Audio on clk_1x, mixed with the SPU below.
`ifdef GNET_ZOOM_SDRAM
`ifndef GNET_DDR3_ARB
`define GNET_ZOOM_SDRAM_PATH 1
`endif
`endif
wire        zoom_m_req;
wire [20:0] zoom_m_line;
wire        zoom_m_ready;
wire        zoom_m_rvalid;
wire [63:0] zoom_m_rdata;
wire        zoom_rst;        // zoom_board's reset (psx_top reset_intern_p): drop answers to lines from before it
`ifdef GNET_ZOOM_SDRAM_PATH
wire        zoom_fl_req;
wire [26:0] zoom_fl_addr;
wire        zoom_fl_ready;
`endif
wire [15:0] zoom_aud_l, zoom_aud_r;
wire  [7:0] zoom_flags;      // zoom_board dbg_flags (clk_1x), for a debug overlay
wire [15:0] spu_aud_l, spu_aud_r;
`endif
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
	// hold ioctl while the card word is collected and its DDR3 line written
	// (zn2_cardmem dl_busy rises within this clock after the fourth word)
	zn_card_wait <= zn_card_dl_wr | zn_card_dl_busy;
end

`ifdef GNET_SHELL
// game configuration byte (ioctl index 7), see gnet_vertical
always @(posedge clk_1x)
	if (ioctl_download & ioctl_wr & (ioctl_index == 7) & (ioctl_addr == 0)) begin
		gnet_vertical <= ioctl_dout[0];
		gnet_nozoom   <= ioctl_dout[1];
		gnet_inmode   <= ioctl_dout[3:2];
	end

// Keyboard, MAME default keys (ps2_key: [10] toggles per event, [9] pressed,
// [8] extended, [7:0] set-2 scancode)
//   P1: arrows, LCtrl = B1, LAlt = B2, Space = B3, 1 = Start, 5 = Coin
//   P2: R/F/D/G, A = B1, S = B2, Q = B3, 2 = Start, 6 = Coin
//   9 = Service, F2 = Test, P = Pause
reg k_up = 0, k_dn = 0, k_lt = 0, k_rt = 0, k_b1 = 0, k_b2 = 0, k_b3 = 0;
reg k_st1 = 0, k_co1 = 0, k_svc = 0, k_test = 0, k_p = 0;
reg k2_up = 0, k2_dn = 0, k2_lt = 0, k2_rt = 0, k2_b1 = 0, k2_b2 = 0, k2_b3 = 0;
reg k_st2 = 0, k_co2 = 0;
reg ps2_last = 1'b0;
always @(posedge clk_1x) begin
	ps2_last <= ps2_key[10];
	if (ps2_key[10] != ps2_last) begin
		case ({ps2_key[8], ps2_key[7:0]})
			9'h175: k_up   <= ps2_key[9];
			9'h172: k_dn   <= ps2_key[9];
			9'h16B: k_lt   <= ps2_key[9];
			9'h174: k_rt   <= ps2_key[9];
			9'h014: k_b1   <= ps2_key[9];   // left ctrl
			9'h011: k_b2   <= ps2_key[9];   // left alt
			9'h029: k_b3   <= ps2_key[9];   // space
			9'h016: k_st1  <= ps2_key[9];   // 1
			9'h01E: k_st2  <= ps2_key[9];   // 2
			9'h02E: k_co1  <= ps2_key[9];   // 5
			9'h036: k_co2  <= ps2_key[9];   // 6
			9'h046: k_svc  <= ps2_key[9];   // 9
			9'h006: k_test <= ps2_key[9];   // F2
			9'h04D: k_p    <= ps2_key[9];   // P
			9'h02D: k2_up  <= ps2_key[9];   // R
			9'h02B: k2_dn  <= ps2_key[9];   // F
			9'h023: k2_lt  <= ps2_key[9];   // D
			9'h034: k2_rt  <= ps2_key[9];   // G
			9'h01C: k2_b1  <= ps2_key[9];   // A
			9'h01B: k2_b2  <= ps2_key[9];   // S
			9'h015: k2_b3  <= ps2_key[9];   // Q
			default: ;
		endcase
	end
end
// joystick bits: 0 R, 1 L, 2 D, 3 U, then the J1 list: 4 B1, 5 B2, 6 B3,
// 7 Start, 8 Coin, 9 Service, 10 Test, 11 Pause
wire [19:0] zj1 = joy  | {9'd0, k_test, k_svc, k_co1, k_st1, k_b3,  k_b2,  k_b1,  k_up,  k_dn,  k_lt,  k_rt};
wire [19:0] zj2 = joy2 | {9'd0, 1'b0,   1'b0,  k_co2, k_st2, k2_b3, k2_b2, k2_b1, k2_up, k2_dn, k2_lt, k2_rt};
wire        pause_btn = zj1[11] | zj2[11] | k_p;

// Special controls (gnet_inmode, MAME 0.288 taitogn.cpp INPUT_PORTS
// mahjngoh, usagi and gobyrc). Bits MAME marks unused read as released.
wire gnet_mj  = (gnet_inmode == 2'd1) | (gnet_inmode == 2'd2);
wire gnet_rc  = (gnet_inmode == 2'd3);
wire [7:0] zm_p1  = (gnet_inmode >= 2'd2) ? 8'h7F : 8'h00;      // usagi, gobyrc: P1 0x7f unused
wire [7:0] zm_p2  = (gnet_inmode != 2'd0) ? 8'h7F : 8'h00;      // mahjngoh, usagi, gobyrc: P2 0x7f unused
wire [7:0] zm_sys = (gnet_inmode == 2'd2) ? 8'h03 :              // usagi: START1/START2 unused
                    (gnet_inmode == 2'd3) ? 8'h02 : 8'h00;      // gobyrc: START2 unused

// Mahjong panel (taitogn.cpp ttgnmp_state, rows KEY0-KEY3 of mame
// shared/mahjong.cpp mahjong_matrix_1p) on the keyboard, MAME's default
// keys (emu/inpttype.ipp): A to N, Kan = LCtrl, Pon = LAlt, Chi = Space,
// Reach = LShift, Ron = Z; Start 1 is also KEY0 bit 5. LCtrl, LAlt and
// Space also stay P1 buttons 1-3, as MAME binds both by default.
reg [13:0] k_mj = 14'd0;                 // A to N
reg k_kan = 0, k_pon = 0, k_chi = 0, k_reach = 0, k_ron = 0;
reg ps2_last_mj = 1'b0;
always @(posedge clk_1x) begin
	ps2_last_mj <= ps2_key[10];
	if (ps2_key[10] != ps2_last_mj) begin
		case ({ps2_key[8], ps2_key[7:0]})
			9'h01C: k_mj[0]  <= ps2_key[9];   // A
			9'h032: k_mj[1]  <= ps2_key[9];   // B
			9'h021: k_mj[2]  <= ps2_key[9];   // C
			9'h023: k_mj[3]  <= ps2_key[9];   // D
			9'h024: k_mj[4]  <= ps2_key[9];   // E
			9'h02B: k_mj[5]  <= ps2_key[9];   // F
			9'h034: k_mj[6]  <= ps2_key[9];   // G
			9'h033: k_mj[7]  <= ps2_key[9];   // H
			9'h043: k_mj[8]  <= ps2_key[9];   // I
			9'h03B: k_mj[9]  <= ps2_key[9];   // J
			9'h042: k_mj[10] <= ps2_key[9];   // K
			9'h04B: k_mj[11] <= ps2_key[9];   // L
			9'h03A: k_mj[12] <= ps2_key[9];   // M
			9'h031: k_mj[13] <= ps2_key[9];   // N
			9'h014: k_kan    <= ps2_key[9];   // left ctrl
			9'h011: k_pon    <= ps2_key[9];   // left alt
			9'h029: k_chi    <= ps2_key[9];   // space
			9'h012: k_reach  <= ps2_key[9];   // left shift
			9'h01A: k_ron    <= ps2_key[9];   // Z
			default: ;
		endcase
	end
end
// rows 3 downto 0, 6 bits each, pressed = 1 (zn2_io A10100, active low)
wire [5:0] mj_r0 = {zj1[7], k_kan,   k_mj[12], k_mj[8],  k_mj[4], k_mj[0]};   // Start1 Kan M I E A
wire [5:0] mj_r1 = {1'b0,   k_reach, k_mj[13], k_mj[9],  k_mj[5], k_mj[1]};   // -      Reach N J F B
wire [5:0] mj_r2 = {1'b0,   k_ron,   k_chi,    k_mj[10], k_mj[6], k_mj[2]};   // -      Ron Chi K G C
wire [5:0] mj_r3 = {2'b00,           k_pon,    k_mj[11], k_mj[7], k_mj[3]};   // -  -   Pon L H D
wire [23:0] zn_mj = ~{mj_r3, mj_r2, mj_r1, mj_r0};

// RC wheel and trigger (gobyrc ANALOG1 IPT_PADDLE, ANALOG2 IPT_PADDLE_V
// PORT_REVERSE, 00h-FFh, centre 80h; znmcu analog channels 0 and 1).
// Wheel: the analog stick's X, or the paddle once it moves (the source
// that moved last is used); trigger: the stick's Y reversed as MAME's
// PORT_REVERSE (stick up = FFh). The D-pad or keyboard arrows give full
// deflection.
reg       rc_paddle = 1'b0;
reg [7:0] paddle_q  = 8'd0;
always @(posedge clk_1x) begin
	paddle_q <= paddle_0;
	if ((paddle_0 > paddle_q + 8'd2) | (paddle_q > paddle_0 + 8'd2)) rc_paddle <= 1'b1;
	else if ((joystick_analog_l0[7:0] > 8'd16) & (joystick_analog_l0[7:0] < 8'd240)) rc_paddle <= 1'b0;
end
wire [7:0] rc_wheel_a = rc_paddle ? paddle_0 : (joystick_analog_l0[7:0] ^ 8'h80);
wire [7:0] rc_trig_a  = ~(joystick_analog_l0[15:8] ^ 8'h80);
wire [7:0] zn_an0 = ~gnet_rc ? 8'hFF : zj1[1] ? 8'h00 : zj1[0] ? 8'hFF : rc_wheel_a;   // left, right
wire [7:0] zn_an1 = ~gnet_rc ? 8'hFF : zj1[3] ? 8'hFF : zj1[2] ? 8'h00 : rc_trig_a;    // up, down

// EEPROM NVRAM save (docs/m4_shell.md 4). Main_MiSTer loads the MRA's
// <nvram index="6" size="2048"/> file on index 6 (the loader above) and
// saves it by an upload of index 6: hps_io steps ioctl_addr by 2 and takes
// ioctl_din, the 16-bit word at that address (low byte = even address), from
// zn2_io's EEPROM copy, read on clk_1x. A CPU write to the EEPROM toggles
// zn_nv_wtog (clk_cpu); it is synchronised here and marks the copy dirty.
// When the OSD opens with the copy dirty, ioctl_upload_req asks Main to save
// it (the core pauses on OSD open by default, so the EEPROM is still).
wire       zn_nv_wtog;
wire [0:0] zn_nv_wtog_s;
cdc_sync #(.WIDTH(1)) nv_tog_sync (.clk(clk_1x), .rst(1'b0), .d(zn_nv_wtog), .q(zn_nv_wtog_s));
reg nv_tog_q = 1'b0, nv_dirty = 1'b0, nv_osd_q = 1'b0;
always @(posedge clk_1x) begin
	nv_tog_q      <= zn_nv_wtog_s[0];
	nv_osd_q      <= OSD_STATUS;
	nv_upload_req <= 1'b0;
	if (zn_nv_wtog_s[0] != nv_tog_q) nv_dirty <= 1'b1;
	if (OSD_STATUS & ~nv_osd_q & nv_dirty) begin
		nv_upload_req <= 1'b1;
		nv_dirty      <= 1'b0;
	end
end
`else
wire [19:0] zj1 = joy;
wire [19:0] zj2 = joy2;
wire        pause_btn = joy[18];
wire        gnet_mj = 1'b0;
wire [7:0]  zm_p1 = 8'h00, zm_p2 = 8'h00, zm_sys = 8'h00;
wire [23:0] zn_mj  = 24'hFFFFFF;
wire [7:0]  zn_an0 = 8'hFF, zn_an1 = 8'hFF;
`endif
`else
wire gnet_download = 0;
wire        pause_btn = joy[18];
`endif

reg cart_loaded = 0;
always @(posedge clk_1x) begin
	if (exe_download || img_mounted[1]) begin
		cart_loaded <= 1;
	end
end

localparam EXE_START = 16777216;
localparam BIOS_START = 8388608;

reg [26:0] ramdownload_wraddr;
`ifdef GNET_ZN2
wire gnet_flash_dl = flash_download;
`else
wire gnet_flash_dl = 0;
`endif
reg [31:0] ramdownload_wrdata;
reg        ramdownload_wr;

reg        hasCD = 0;

reg exe_download_1 = 0;
reg cdinfo_download_1 = 0;
reg loadExe = 0;

reg sd_mounted2 = 0;
reg sd_mounted3 = 0;

reg memcard1_load = 0;
reg memcard2_load = 0;
reg memcard_save = 0;

wire saving_memcard;

reg memcard1_inserted = 0;
reg memcard2_inserted = 0;
reg [25:0] memcard1_cnt = 0;
reg [25:0] memcard2_cnt = 0;

wire bk_save     = status[13];
wire bk_autosave = ~status[71];

reg old_save = 0;
reg old_save_a = 0;

wire bk_save_a = OSD_STATUS & bk_autosave;

reg cdbios = 0;
reg  [1:0] region;
reg  [1:0] biosregion;
wire [1:0] region_out;
reg        isPal;
reg biosMod = 0;

reg [31:0] exe_initial_pc;
reg [31:0] exe_initial_gp;
reg [31:0] exe_load_address;
reg [31:0] exe_file_size;
reg [31:0] exe_stackpointer;

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
`ifdef GNET_ZN2
   end else if (card_download) begin
      ioctl_wait <= zn_card_wait;
   end else if (keys_download | meta_download | ee_download) begin
      ioctl_wait <= zn_ld_busy;
`endif
   end else begin
      ioctl_wait <= 0;
	end
   exe_download_1  <= exe_download;
   loadExe         <= exe_download_1 & ~exe_download;

   if (exe_download & ramdownload_wr) begin
      if (ramdownload_wraddr[22:0] == 'h10) exe_initial_pc     <= ramdownload_wrdata;
      if (ramdownload_wraddr[22:0] == 'h14) exe_initial_gp     <= ramdownload_wrdata;
      if (ramdownload_wraddr[22:0] == 'h18) exe_load_address   <= ramdownload_wrdata;
      if (ramdownload_wraddr[22:0] == 'h1C) exe_file_size      <= ramdownload_wrdata;
      if (ramdownload_wraddr[22:0] == 'h30) exe_stackpointer   <= ramdownload_wrdata;
      if (ramdownload_wraddr[22:0] == 'h34) exe_stackpointer   <= exe_stackpointer + ramdownload_wrdata;
   end

   if (loadExe) biosMod <= 1'b1;

   if (img_mounted[1]) begin
      if (img_size > 0) begin
         hasCD     <= 1;
      end else begin
         hasCD     <= 0;
      end
   end

   case(status[40:39])
      0: begin
            case(region_out)
               0: begin region = 2'b00; isPal <= 0; end   // unknown => default to NTSC
               1: begin region = 2'b01; isPal <= 0; end   // JP
               2: begin region = 2'b00; isPal <= 0; end   // US
               3: begin region = 2'b10; isPal <= 1; end   // EU
            endcase
         end
      1: begin region = 2'b00; isPal <= 0; end
      2: begin region = 2'b01; isPal <= 0; end
      3: begin region = 2'b10; isPal <= 1; end
	endcase

   if (bios_download && ioctl_index[7:6] == 2'b11) cdbios <= 1'b1;

   if (cdbios)
      biosregion <= 2'b11;
   else
      biosregion <= region;

   memcard1_load <= 0;
   memcard2_load <= 0;
   memcard_save <= 0;

   // memcard 1
   if (img_mounted[2]) begin
      memcard1_inserted <= 0;
      memcard1_cnt      <= 26'd0;
      if (img_size > 0) begin
         sd_mounted2       <= 1;
         memcard1_load     <= 1;
      end else begin
         sd_mounted2       <= 0;
      end
   end

   if (sd_mounted2) begin // delay memcard inserted for ~2 seconds on card change
      if (memcard1_cnt[25]) begin
         memcard1_inserted <= 1;
      end else begin
         memcard1_cnt <= memcard1_cnt + 1'd1;
      end
   end

   // memcard 2
   if (img_mounted[3]) begin
      memcard2_inserted <= 0;
      memcard2_cnt      <= 26'd0;
      if (img_size > 0) begin
         sd_mounted3   <= 1;
         memcard2_load <= 1;
      end else begin
         sd_mounted3 <= 0;
      end
   end

   if (sd_mounted3) begin
      if (memcard2_cnt[25]) begin
         memcard2_inserted <= 1;
      end else begin
         memcard2_cnt <= memcard2_cnt + 1'd1;
      end
   end

	old_save   <= bk_save;
	old_save_a <= bk_save_a;

   if ((~old_save & bk_save) | (~old_save_a & bk_save_a)) memcard_save <= 1;

end

///////////////////////////  SAVESTATE  /////////////////////////////////

wire [1:0] ss_slot;
wire [7:0] ss_info;
wire [3:0] validSStates;
wire ss_save, ss_load, ss_info_req;
wire statusUpdate;

savestate_ui savestate_ui
(
	.clk            (clk_1x        ),
	.ps2_key        (ps2_key[10:0] ),
	.allow_ss       (cart_loaded   ),
	.joySS          (joy_unmod[16] ),
	.joyRight       (joy_unmod[0]  ),
	.joyLeft        (joy_unmod[1]  ),
	.joyDown        (joy_unmod[2]  ),
	.joyUp          (joy_unmod[3]  ),
	.joyRewind      (0             ),
	.rewindEnable   (0             ),
	.status_slot    (status[38:37] ),
	.autoincslot    (status[68]    ),
	.OSD_saveload   (status[18:17] ),
   .validSStates   (validSStates  ),
	.ss_save        (ss_save       ),
	.ss_load        (ss_load       ),
	.ss_info_req    (ss_info_req   ),
	.ss_info        (ss_info       ),
	.statusUpdate   (statusUpdate  ),
	.selected_slot  (ss_slot       )
);
defparam savestate_ui.INFO_TIMEOUT_BITS = 25;

////////////////////////////  PAD  ///////////////////////////////////

// 0000 -> DualShock
// 0001 -> off
// 0010 -> digital
// 0011 -> analog
// 0100 -> Namco GunCon lightgun
// 0101 -> Namco NeGcon
// 0110 -> Wheel Negcon
// 0111 -> Wheel Analog
// 1000 -> mouse
// 1001 -> Konami Justifier lightgun
// 1010 -> SNAC
// 1011 -> Analog Joystick
// 1100..1111 -> reserved

wire PadPortDS1      = (status[48:45] == 4'b0000);
wire PadPortEnable1  = (status[48:45] != 4'b0001);
wire PadPortDigital1 = (status[48:45] == 4'b0010) || (status[52:49] == 4'b1100);
wire PadPortAnalog1  = (status[48:45] == 4'b0011) || (status[48:45] == 4'b0111);
wire PadPortGunCon1  = (status[48:45] == 4'b0100);
wire PadPortNeGcon1  = (status[48:45] == 4'b0101) || (status[48:45] == 4'b0110);
wire PadPortWheel1   = (status[48:45] == 4'b0110) || (status[48:45] == 4'b0111);
wire PadPortMouse1   = (status[48:45] == 4'b1000);
wire PadPortJustif1  = (status[48:45] == 4'b1001);
wire snacPort1       = (status[48:45] == 4'b1010) && ~multitap;
wire PadPortStick1   = (status[48:45] == 4'b1011);
wire PadPortPopn1    = (status[48:45] == 4'b1100);

wire PadPortDS2      = (status[52:49] == 4'b0000);
wire PadPortEnable2  = (status[52:49] != 4'b0001) && ~multitap;
wire PadPortDigital2 = (status[52:49] == 4'b0010) || (status[52:49] == 4'b1100);
wire PadPortAnalog2  = (status[52:49] == 4'b0011) || (status[52:49] == 4'b0111);
wire PadPortGunCon2  = (status[52:49] == 4'b0100);
wire PadPortNeGcon2  = (status[52:49] == 4'b0101) || (status[52:49] == 4'b0110);
wire PadPortWheel2   = (status[52:49] == 4'b0110) || (status[52:49] == 4'b0111);
wire PadPortMouse2   = (status[52:49] == 4'b1000);
wire PadPortJustif2  = (status[52:49] == 4'b1001);
wire snacPort2       = (status[52:49] == 4'b1010) && ~multitap;
wire PadPortStick2   = (status[52:49] == 4'b1011);
wire PadPortPopn2    = (status[52:49] == 4'b1100);

reg paddleMode = 0;
reg paddleMin = 0;
reg paddleMax = 0;
wire [7:0] joy0_xmuxed = (paddleMode) ? (paddle_0 - 8'd128) : joystick_analog_l0[7:0];

// to activate paddleMode negcon mode must be active and paddle must best moved
always @(posedge clk_1x) begin
   if (PadPortNeGcon1) begin
      if (paddle_0 < 112) paddleMin <= 1'b1;
      if (paddle_0 > 144) paddleMax <= 1'b1;
      if (paddleMin && paddleMax) paddleMode <= 1'b1;
   end else begin
      paddleMode <= 0;
      paddleMin <= 0;
      paddleMax <= 0;
   end
end

// 00 -> multitap off
// 01 -> port1, 4 x digital
// 10 -> port1, 4 x analog
wire multitap        = (status[57:56] != 2'b00);
wire multitapDigital = (status[57:56] == 2'b01);
wire multitapAnalog  = (status[57:56] == 2'b10);

wire [1:0] padMode;
reg  [1:0] padMode_1;

reg [7:0] psx_info;
reg psx_info_req;

wire resetFromCD;
reg  cdDownloadReset = 0;

reg [3:0] ToggleDS = 0;
reg [3:0] joy19_1 = 0;

always @(posedge clk_1x) begin

   psx_info_req <= 0;
   padMode_1    <= padMode;

   cdinfo_download_1 <= cdinfo_download;

   if (ss_info_req) begin
      psx_info_req <= 1;
      psx_info     <= ss_info;
   end else if (saving_memcard) begin
      psx_info_req <= 1;
      psx_info     <= 8'd23;
   end else if (padMode_1[0] != padMode[0] && ~multitap) begin
      psx_info_req <= 1;
      if (padMode[0])  psx_info <= 8'd15;
      if (!padMode[0]) psx_info <= 8'd16;
   end else if (padMode_1[1] != padMode[1] && ~multitap) begin
      psx_info_req <= 1;
      if (padMode[1])  psx_info <= 8'd17;
      if (!padMode[1]) psx_info <= 8'd18;
   end else if (cdinfo_download_1 && ~cdinfo_download) begin
      // warning for every unsafe option
      if (status[89] || status[80:79] > 0 || status[72] || status[15] || status[21] || status[77:75] > 0 || status[78] || status[85]) begin
         psx_info_req <= 1;
         psx_info     <= 8'd24;
      end else if (status[40:39] == 2'b00) begin
         psx_info_req <= 1;
         case(region_out)
            0: begin psx_info <= 8'd19; end   // unknown => default to NTSC
            1: begin psx_info <= 8'd20; end   // JP
            2: begin psx_info <= 8'd21; end   // US
            3: begin psx_info <= 8'd22; end   // EU
         endcase
      end
   end

   cdDownloadReset <= 0;
   if (cdinfo_download_1 && ~cdinfo_download && resetFromCD) begin
      cdDownloadReset <= 1;
   end

   if (joy[14] && joy[15] && joy[8]) dbg_enabled <= 1;  // L3+R3+Select

   // DS toggle
   joy19_1 <= {joy4[19] ,joy3[19] ,joy2[19] ,joy[19] };
   ToggleDS[0] <=  joy[19] & ~joy19_1[0];
   ToggleDS[1] <= joy2[19] & ~joy19_1[1];
   ToggleDS[2] <= joy3[19] & ~joy19_1[2];
   ToggleDS[3] <= joy4[19] & ~joy19_1[3];

end

////////////////////////////  PAUSE and RESET  ///////////////////////////
reg paused = 0;
reg [9:0] unpause = 0;
reg status1_1;
wire isPaused;

reg [20:0] aliveCnt = 0;
reg heartbeat_1 = 0;
reg hps_busy = 0;

reg reset = 0;

reg buttonpause_1 = 0;
reg button_paused = 0;

reg TURBO_MEM;
reg TURBO_COMP;
reg TURBO_CACHE;
reg TURBO_CACHE50;

always @(posedge clk_1x) begin

   paused <= 0;

   // pause from OSD open
   if (~status[64] & OSD_STATUS & (unpause == 0)) begin
      paused <= 1;
   end

   // pause from button
   buttonpause_1 <= pause_btn;
   if (pause_btn & ~buttonpause_1) begin
      button_paused <= ~button_paused;
   end
   if (button_paused) begin
      paused <= 1;
   end

   // Advance Pause OSD trigger
   status1_1 <= status[1];
   if (status[1] & ~status1_1) begin
      unpause <= 1023;
   end else if (unpause > 0) begin
      unpause <= unpause - 1'd1;
   end

   // pause from heartbeat -> only used for savestate
   hps_busy    <= 0;
   heartbeat_1 <= heartbeat;
   if (heartbeat == heartbeat_1) begin
      if (aliveCnt[20] == 0) begin
         aliveCnt <= aliveCnt + 1'b1;
      end else begin
         hps_busy <= 1;
      end
   end else begin
      aliveCnt <= 0;
   end

   // reset
   reset <= 0;
   if (reset_or) begin
      reset    <= 1;
      aliveCnt <= 0;
   end

   // 1 => low    -> only MEM
   // 2 => medium -> MEM + 50% cache
   // 3 => high   -> everything
   TURBO_MEM      <= status[80:79] > 0;
   TURBO_COMP     <= status[80:79] == 2'b11;
   TURBO_CACHE    <= status[80];
   TURBO_CACHE50  <= status[80:79] == 2'b10;

end

`ifdef GNET_SHELL
// watchdog mask: while paused and GNET_WD_TIMEOUT_S + 0.5 s after, in
// clk_1x cycles (33,868,800 Hz): (2 x period + 1) x 16,934,400, 287,884,800
// for 8 s
localparam [29:0] GNET_WD_GRACE = (2 * GNET_WD_TIMEOUT_S + 1) * 16934400;
reg [29:0] zn_wd_grace = 0;
always @(posedge clk_1x) begin
   if (paused)
      zn_wd_grace <= GNET_WD_GRACE;
   else if (zn_wd_grace != 0)
      zn_wd_grace <= zn_wd_grace - 1'd1;
end
assign zn_wd_mask = paused | (zn_wd_grace != 0);
`endif

////////////////////////////  SYSTEM  ///////////////////////////////////

// GNET_LEAN: console-only OSD options fixed to constants so their logic is
// removed (docs/f0_budget.md). Without the macro every option stays live.
`ifdef GNET_LEAN
`define GNET_OPT(live, fixed) (fixed)
`else
`define GNET_OPT(live, fixed) (live)
`endif

// G-NET trim switches (docs/f0_budget.md); upstream builds define none of
// these macros, so every block stays in.
`ifdef GNET_NO_CD
localparam GNET_HAS_CD = 0;
`else
localparam GNET_HAS_CD = 1;
`endif
`ifdef GNET_NO_PADS
localparam GNET_HAS_PADS = 0;
`else
localparam GNET_HAS_PADS = 1;
`endif
`ifdef GNET_NO_SAVESTATES
localparam GNET_HAS_SAVESTATES = 0;
`else
localparam GNET_HAS_SAVESTATES = 1;
`endif
`ifdef GNET_NO_CHEATS
localparam GNET_HAS_CHEATS = 0;
`else
localparam GNET_HAS_CHEATS = 1;
`endif
`ifdef GNET_NO_MDEC
localparam GNET_HAS_MDEC = 0;
`else
localparam GNET_HAS_MDEC = 1;
`endif
`ifdef GNET_VRAM_2MB
localparam GNET_VRAM_Y_BITS = 10;   // ZN-2 CXD8654Q, 1024 x 1024 VRAM
`else
localparam GNET_VRAM_Y_BITS = 9;
`endif
`ifdef GNET_GTE_NARROW_MUL
localparam GNET_GTE_NARROW_MUL = `GNET_GTE_NARROW_MUL;   // 1, 2 or 3, see rtl/gte_mac123.vhd and rtl/gte.vhd
`else
localparam GNET_GTE_NARROW_MUL = 0;
`endif
`ifdef GNET_ZOOM
localparam GNET_ZOOM_BOARD = 1;  // Taito Zoom sound board (rtl/zoom, rtl/gnet/zoom_cdc.vhd)
`else
localparam GNET_ZOOM_BOARD = 0;
`endif
`ifdef GNET_DDR3_ARB
localparam GNET_ZOOM_INFL = 8;   // ZSG-2 reads outstanding behind the DDR3 arbiter (ddr3_bandwidth.md 4.4)
`else
localparam GNET_ZOOM_INFL = 4;
`endif
`ifdef GNET_ZN2
localparam GNET_ZN2_BOARD = 1;   // ZN-2 board and G-NET FC PCB (rtl/gnet/zn2_board.vhd)
`else
localparam GNET_ZN2_BOARD = 0;
`endif
// Fast clock (clk_3x) edges per CPU clock cycle for the request strobes in
// sdram.sv and psx_top.vhd (docs/r1_cpu_domain_design.md). Selects logic
// only: the PLL still makes 3:1, so a GNET_CLK_RATIO2 build checks synthesis
// and area, it does not run correctly until the CPU clock changes.
`ifdef GNET_CLK_RATIO2
localparam GNET_CLK_FAST_RATIO = 2;
`else
localparam GNET_CLK_FAST_RATIO = 3;
`endif
// R1 option B: main SDRAM plain reads ready one fast edge earlier at 2:1
// (sdram.sv EARLY_READY; docs/r1_cpu_domain_design.md, throughput section)
`ifdef GNET_EARLY_READY
localparam GNET_EARLY_READY_P = 1;
`else
localparam GNET_EARLY_READY_P = 0;
`endif
// R1 read overlap: a ZN-2 expansion read step issues its request when its
// read delay starts (memorymux ZN2_READ_OVERLAP; docs/r1_cpu_domain_design.md)
`ifdef GNET_READ_OVERLAP
localparam GNET_READ_OVERLAP_P = 1;
`else
localparam GNET_READ_OVERLAP_P = 0;
`endif
// R1: CPU group on clk_cpu/clk_cpu2x (needs GNET_CLK_RATIO2 and the LEAN trims)
`ifdef GNET_CPU50
localparam GNET_CPU_CLK_SPLIT = 1;
`else
localparam GNET_CPU_CLK_SPLIT = 0;
`endif

`ifdef GNET_SHELL
// core video before gnet_sync_keeper, core sound before gnet_volume
wire        hs_c, vs_c, hbl_c, vbl_c, ce_pix_c;
wire  [7:0] r_c, g_c, b_c;
wire  [2:0] video_hResMode_c;
wire [15:0] snd_l, snd_r;
wire        hs_k, vs_k;   // gnet_sync_keeper to gnet_crt_pos
`endif

psx_mister
#(
   .HAS_CD(GNET_HAS_CD),
   .HAS_PADS(GNET_HAS_PADS),
   .HAS_SAVESTATES(GNET_HAS_SAVESTATES),
   .HAS_CHEATS(GNET_HAS_CHEATS),
   .HAS_MDEC(GNET_HAS_MDEC),
   .VRAM_Y_BITS(GNET_VRAM_Y_BITS),
   .GTE_NARROW_MUL(GNET_GTE_NARROW_MUL),
   .CLK_FAST_RATIO(GNET_CLK_FAST_RATIO),
   .CPU_CLK_SPLIT(GNET_CPU_CLK_SPLIT),
   .ZN2_BOARD(GNET_ZN2_BOARD),
   .ZN2_WD_TIMEOUT_S(GNET_WD_TIMEOUT_S),
   .ZOOM_BOARD(GNET_ZOOM_BOARD),
   .ZOOM_INFL(GNET_ZOOM_INFL),
   .ZN2_READ_OVERLAP(GNET_READ_OVERLAP_P)
)
psx
(
   .clk1x(clk_1x),
   .clk2x(clk_2x),
   .clk3x(clk_3x),
   .clkvid(clk_vid),
`ifdef GNET_CPU50
   .clk_cpu(clk_cpu),
   .clk_cpu2x(clk_cpu2x),
   .clk_cpu3x(clk_cpu2x),
`else
   .clk_cpu(clk_1x),
   .clk_cpu2x(clk_2x),
   .clk_cpu3x(clk_3x),
`endif
   .reset(reset),
   .isPaused(isPaused),
   // commands
   .pause(paused),
   .hps_busy(hps_busy),
   .loadExe(loadExe),
   .exe_initial_pc(exe_initial_pc),
   .exe_initial_gp(exe_initial_gp),
   .exe_load_address(exe_load_address),
   .exe_file_size(exe_file_size),
   .exe_stackpointer(exe_stackpointer),
`ifdef GNET_ZN2
   .fastboot(1'b0),
   .ram8mb(1'b1),                // ZN-2: 4 MB main RAM (docs/zn2_layer_design.md 3)
`else
   .fastboot(status[16] && hasCD),
   .ram8mb(status[85]),
`endif
   .TURBO_MEM(`GNET_OPT(TURBO_MEM, 1'b0)),
   .TURBO_COMP(`GNET_OPT(TURBO_COMP, 1'b0)),
   .TURBO_CACHE(`GNET_OPT(TURBO_CACHE, 1'b0)),
   .TURBO_CACHE50(`GNET_OPT(TURBO_CACHE50, 1'b0)),
   .REPRODUCIBLEGPUTIMING(0),
   .INSTANTSEEK(`GNET_OPT(status[21], 1'b0)),
   .FORCECDSPEED(`GNET_OPT(status[77:75], 3'b000)),
   .LIMITREADSPEED(`GNET_OPT(status[78], 1'b0)),
   .IGNORECDDMATIMING(`GNET_OPT(status[88], 1'b0)),
   .ditherOff(`GNET_OPT(status[22], 1'b0)),
   .interlaced480pHack(`GNET_OPT(status[89], 1'b0)),
   .showGunCrosshairs(`GNET_OPT(status[9], 1'b0)),
   .enableNeGconRumble(`GNET_OPT(status[91], 1'b0)),
   .fpscountOn(`GNET_OPT(status[28], 1'b0)),
   .cdslowOn(`GNET_OPT(status[59], 1'b0)),
   .testSeek(`GNET_OPT(status[70], 1'b0)),
   .pauseOnCDSlow(`GNET_OPT(~status[72], 1'b0)),
   .errorOn(`GNET_OPT(status[74], 1'b0)),
   .LBAOn(`GNET_OPT(status[69], 1'b0)),
   .PATCHSERIAL(0), //.PATCHSERIAL(status[54]),
   .noTexture(`GNET_OPT(status[27], 1'b0)),
   .textureFilter(`GNET_OPT(status[82:81], 2'b00)),
   .textureFilterStrength(`GNET_OPT(status[87:86], 2'b00)),
   .textureFilter2DOff(`GNET_OPT(status[83], 1'b0)),
   .dither24(`GNET_OPT(status[73], 1'b0)),
   .render24(`GNET_OPT(status[84] && ~hack_480p, 1'b0)),
   .drawSlow(`GNET_OPT(status[90], 1'b0)),
   .syncVideoOut(syncVideoOut),
   .syncInterlace(status[60]),
`ifdef GNET_SHELL
   .rotate180(status[104] & gnet_vertical),   // OSD Flip Screen, vertical sets only (renderer 180, all outputs)
`else
   .rotate180(`GNET_OPT(status[24], 1'b0)),
`endif
   .fixedVBlank(`GNET_OPT(status[55] && ~hack_480p, 1'b0)),
   .vCrop(hack_480p ? 2'b00 : status[4:3]),
   .hCrop(status[67]),
   .SPUon(`GNET_OPT(~status[30], 1'b1)),
   .SPUIRQTrigger(status[2]),
   .SPUSDRAM(`GNET_OPT(status[44] & SDRAM2_EN, 1'b0)),
   .REVERBOFF(0),
   .REPRODUCIBLESPUDMA(`GNET_OPT(status[43], 1'b0)),
   .WIDESCREEN(`GNET_OPT(status[54:53], 2'b00)),
   .oldGPU(`GNET_OPT(status[92], 1'b0)),   
   // RAM/BIOS interface
`ifdef GNET_ZN2
   .biosregion(2'b00),
`else
   .biosregion(biosregion),
`endif
   .ram_refresh(sdr_refresh),
   .ram_dataWrite(sdr_sdram_din),
   .ram_dataRead32(sdr_sdram_dout32),
   .ram_Adr(sdram_addr),
   .ram_cntDMA(sdram_cntDMA),
   .ram_be(sdram_be),
   .ram_rnw(sdram_rnw),
   .ram_ena(sdram_req),
   .ram_dma(sdram_dma),
   .ram_cache(sdram_cache),
   .ram_done(sdram_ack),
   .ram_dmafifo_adr  (sdram_dmafifo_adr),
   .ram_dmafifo_data (sdram_dmafifo_data),
   .ram_dmafifo_empty(sdram_dmafifo_empty),
   .ram_dmafifo_read (sdram_dmafifo_read),
   .cache_wr(cache_wr),
   .cache_data(cache_data),
   .cache_addr(cache_addr),
   .dma_wr(dma_wr),
   .dma_reqprocessed(dma_reqprocessed),
   .dma_data(dma_data),
   // vram/ddr3
`ifdef GNET_DDR3_ARB
   // through gnet_ddr3_arb as its core client (DDR3 block below)
   .DDRAM_BUSY      (core_ddr_busy   ),
   .DDRAM_BURSTCNT  (core_ddr_burstcnt),
   .DDRAM_ADDR      (core_ddr_addr   ),
   .DDRAM_DOUT      (arb_rdata       ),
   .DDRAM_DOUT_READY(core_ddr_dout_ready),
   .DDRAM_RD        (core_ddr_rd     ),
   .DDRAM_DIN       (core_ddr_din    ),
   .DDRAM_BE        (core_ddr_be     ),
   .DDRAM_WE        (core_ddr_we     ),
`else
   .DDRAM_BUSY      (DDRAM_BUSY      ),
   .DDRAM_BURSTCNT  (DDRAM_BURSTCNT  ),
   .DDRAM_ADDR      (DDRAM_ADDR      ),
   .DDRAM_DOUT      (DDRAM_DOUT      ),
   .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
   .DDRAM_RD        (DDRAM_RD        ),
   .DDRAM_DIN       (DDRAM_DIN       ),
   .DDRAM_BE        (DDRAM_BE        ),
   .DDRAM_WE        (DDRAM_WE        ),
`endif
   // cd
   .region          (region),
   .region_out      (region_out),
   .hasCD           (hasCD),
   .LIDopen         (status[42]),
   .fastCD          (0),
   .trackinfo_data  (ramdownload_wrdata),
   .trackinfo_addr  (ramdownload_wraddr[10:2]),
   .trackinfo_write (ramdownload_wr && cdinfo_download),
   .resetFromCD     (resetFromCD),
   .cd_hps_req      (sd_rd[1]),
   .cd_hps_lba      (sd_lba1),
   .cd_hps_ack      (sd_ack[1]),
   .cd_hps_write    (sd_buff_wr),
   .cd_hps_data     (sd_buff_dout),
   // spuram
   .spuram_dataWrite(spuram_dataWrite),
   .spuram_Adr      (spuram_Adr      ),
   .spuram_be       (spuram_be       ),
   .spuram_rnw      (spuram_rnw      ),
   .spuram_ena      (spuram_ena      ),
   .spuram_dataRead (spuram_dataRead ),
   .spuram_done     (spuram_done     ),
   // memcard
   .memcard_changed (bk_pending),
   .saving_memcard  (saving_memcard),
   .memcard1_load   (memcard1_load),
   .memcard2_load   (memcard2_load),
   .memcard_save    (memcard_save),
   .memcard1_mounted   (sd_mounted2),
   .memcard1_available (memcard1_inserted),
   .memcard1_rd     (sd_rd[2]),
   .memcard1_wr     (sd_wr[2]),
   .memcard1_lba    (sd_lba2),
   .memcard1_ack    (sd_ack[2]),
   .memcard1_write  (sd_buff_wr),
   .memcard1_addr   (sd_buff_addr[8:0]),
   .memcard1_dataIn (sd_buff_dout),
   .memcard1_dataOut(sd_buff_din2),
   .memcard2_mounted   (sd_mounted3),
   .memcard2_available (memcard2_inserted),
   .memcard2_rd     (sd_rd[3]),
   .memcard2_wr     (sd_wr[3]),
   .memcard2_lba    (sd_lba3),
   .memcard2_ack    (sd_ack[3]),
   .memcard2_write  (sd_buff_wr),
   .memcard2_addr   (sd_buff_addr[8:0]),
   .memcard2_dataIn (sd_buff_dout),
   .memcard2_dataOut(sd_buff_din3),
   // video
   .videoout_on     (~status[14]),
   .isPal           (`GNET_OPT(isPal, 1'b0)),
   .pal60           (`GNET_OPT(status[15], 1'b0)),
`ifdef GNET_SHELL
   // through gnet_sync_keeper (VIDEO section)
   .hsync           (hs_c),
   .vsync           (vs_c),
   .hblank          (hbl_c),
   .vblank          (vbl_c),
`else
   .hsync           (hs),
   .vsync           (vs),
   .hblank          (hbl),
   .vblank          (vbl),
`endif
   .DisplayWidth    (DisplayWidth),
   .DisplayHeight   (DisplayHeight),
   .DisplayOffsetX  (DisplayOffsetX),
   .DisplayOffsetY  (DisplayOffsetY),
`ifdef GNET_SHELL
   .video_ce        (ce_pix_c),
   .video_interlace (video_interlace),
   .video_r         (r_c),
   .video_g         (g_c),
   .video_b         (b_c),
`else
   .video_ce        (ce_pix),
   .video_interlace (video_interlace),
   .video_r         (r),
   .video_g         (g),
   .video_b         (b),
`endif
   .video_isPal     (video_isPal),
   .video_fbmode    (video_fbmode),
   .video_fb24      (video_fb24),
`ifdef GNET_SHELL
   .video_hResMode  (video_hResMode_c),
`else
   .video_hResMode  (video_hResMode),
`endif
   .video_frameindex(frameindex),
   //Keys
   .DSAltSwitchMode(`GNET_OPT(status[31], 1'b0)),
   .PadPortEnable1 (PadPortEnable1),
   .PadPortDigital1(PadPortDigital1),
   .PadPortAnalog1 (PadPortAnalog1),
   .PadPortMouse1  (PadPortMouse1 ),
   .PadPortGunCon1 (PadPortGunCon1),
   .PadPortNeGcon1 (PadPortNeGcon1),
   .PadPortWheel1  (PadPortWheel1),
   .PadPortDS1     (PadPortDS1),
   .PadPortJustif1 (PadPortJustif1),
   .PadPortStick1  (PadPortStick1),
   .PadPortPopn1   (PadPortPopn1),
   .PadPortEnable2 (PadPortEnable2),
   .PadPortDigital2(PadPortDigital2),
   .PadPortAnalog2 (PadPortAnalog2),
   .PadPortMouse2  (PadPortMouse2 ),
   .PadPortGunCon2 (PadPortGunCon2),
   .PadPortNeGcon2 (PadPortNeGcon2),
   .PadPortWheel2  (PadPortWheel2),
   .PadPortDS2     (PadPortDS2),
   .PadPortJustif2 (PadPortJustif2),
   .PadPortStick2  (PadPortStick2),
   .PadPortPopn2   (PadPortPopn2),
   .KeyTriangle({joy4[4], joy3[4], joy2[4], joy[4] }),
   .KeyCircle  ({joy4[5] ,joy3[5] ,joy2[5] ,joy[5] }),
   .KeyCross   ({joy4[6] ,joy3[6] ,joy2[6] ,joy[6] }),
   .KeySquare  ({joy4[7] ,joy3[7] ,joy2[7] ,joy[7] }),
   .KeySelect  ({joy4[8] ,joy3[8] ,joy2[8] ,joy[8] }),
   .KeyStart   ({joy4[9] ,joy3[9] ,joy2[9] ,joy[9] }),
   .KeyRight   ({joy4[0] ,joy3[0] ,joy2[0] ,joy[0] }),
   .KeyLeft    ({joy4[1] ,joy3[1] ,joy2[1] ,joy[1] }),
   .KeyUp      ({joy4[3] ,joy3[3] ,joy2[3] ,joy[3] }),
   .KeyDown    ({joy4[2] ,joy3[2] ,joy2[2] ,joy[2] }),
   .KeyR1      ({joy4[11],joy3[11],joy2[11],joy[11]}),
   .KeyR2      ({joy4[13],joy3[13],joy2[13],joy[13]}),
   .KeyR3      ({joy4[15],joy3[15],joy2[15],joy[15]}),
   .KeyL1      ({joy4[10],joy3[10],joy2[10],joy[10]}),
   .KeyL2      ({joy4[12],joy3[12],joy2[12],joy[12]}),
   .KeyL3      ({joy4[14],joy3[14],joy2[14],joy[14]}),
   .ToggleDS   (ToggleDS),
   .Analog1XP1(joy0_xmuxed),
   .Analog1YP1(joystick_analog_l0[15:8]),
   .Analog2XP1(joystick_analog_r0[7:0]),
   .Analog2YP1(joystick_analog_r0[15:8]),
   .Analog1XP2(joystick_analog_l1[7:0]),
   .Analog1YP2(joystick_analog_l1[15:8]),
   .Analog2XP2(joystick_analog_r1[7:0]),
   .Analog2YP2(joystick_analog_r1[15:8]),
   .Analog1XP3(joystick_analog_l2[7:0]),
   .Analog1YP3(joystick_analog_l2[15:8]),
   .Analog2XP3(joystick_analog_r2[7:0]),
   .Analog2YP3(joystick_analog_r2[15:8]),
   .Analog1XP4(joystick_analog_l3[7:0]),
   .Analog1YP4(joystick_analog_l3[15:8]),
   .Analog2XP4(joystick_analog_r3[7:0]),
   .Analog2YP4(joystick_analog_r3[15:8]),
   .RumbleDataP1(joystick1_rumble),
   .RumbleDataP2(joystick2_rumble),
   .RumbleDataP3(joystick3_rumble),
   .RumbleDataP4(joystick4_rumble),
   .padMode(padMode),
   .MouseEvent(`GNET_OPT(mouse[24], 1'b0)),
   .MouseLeft(mouse[0]),
   .MouseRight(mouse[1]),
   .MouseX({mouse[4],mouse[15:8]}),
   .MouseY({mouse[5],mouse[23:16]}),
   .multitap(`GNET_OPT(multitap, 1'b0)),
   .multitapDigital(`GNET_OPT(multitapDigital, 1'b0)),
   .multitapAnalog(`GNET_OPT(multitapAnalog, 1'b0)),
   //snac
   .snacPort1(`GNET_OPT(snacPort1, 1'b0)),
   .snacPort2(`GNET_OPT(snacPort2, 1'b0)),
   .selectedPort1Snac(selectedPort1Snac),
   .selectedPort2Snac(selectedPort2Snac),
   .irq10Snac(irq10Snac),
   .transmitValueSnac(transmitValueSnac),
   .clk9Snac(clk9Snac),
   .receiveBufferSnac(receiveBufferSnac),
   .beginTransferSnac(beginTransferSnac),
   .actionNextSnac(actionNextSnac),
   .receiveValidSnac(receiveValidSnac),
   .ackSnac(~ack),//using real ack not the 1 cycle ack
   .snacMC(status[66]),

   //sound
`ifdef GNET_ZOOM
	.sound_out_left(spu_aud_l),    // to zoom_mix (after this instance)
	.sound_out_right(spu_aud_r),
`elsif GNET_SHELL
	.sound_out_left(snd_l),    // to gnet_volume (VIDEO section end)
	.sound_out_right(snd_r),
`else
	.sound_out_left(AUDIO_L),
	.sound_out_right(AUDIO_R),
`endif
   //savestates
   .increaseSSHeaderCount (!status[36]),
   .save_state            (ss_save),
   .load_state            (ss_load),
   .savestate_number      (ss_slot),
   .state_loaded          (),
   .validSStates          (validSStates),
   .rewind_on             (0), //(status[27]),
   .rewind_active         (0), //(status[27] & joy[15]),
   //cheats
   .cheat_clear(gg_reset),
   .cheats_enabled(~status[6] && ~TURBO_MEM && ~ioctl_download),
   .cheat_on(gg_valid),
   .cheat_in(gg_code),
   .cheats_active(gg_active),

   .Cheats_BusAddr(cheats_addr),
   .Cheats_BusRnW(cheats_rnw),
   .Cheats_BusByteEnable(cheats_be),
   .Cheats_BusWriteData(cheats_dout),
   .Cheats_Bus_ena(cheats_ena),
   .Cheats_BusReadData(cheats_din),
   .Cheats_BusDone(sdramCh3_done)
`ifdef GNET_ZN2
   ,
   // G-NET: inputs active low (MAME zn/taitogn input ports, docs/zn2_layer_design.md 7.1)
   // zj1/zj2: joysticks, with the MAME keyboard keys in GNET_SHELL builds
   .zn_in_p1       (~{1'b0, zj1[6], zj1[5], zj1[4], zj1[0], zj1[1], zj1[2], zj1[3]} | zm_p1),
   .zn_in_p2       (~{1'b0, zj2[6], zj2[5], zj2[4], zj2[0], zj2[1], zj2[2], zj2[3]} | zm_p2),
   .zn_in_service  (~{6'b000000, zj1[9], zj1[10]}),
   .zn_in_system   (~{2'b00, zj2[8], zj1[8], 2'b00, zj2[7], zj1[7]} | zm_sys),
   .zn_in_mj       (zn_mj),
   .zn_in_mj_en    (gnet_mj),
   .zn_in_an0      (zn_an0),
   .zn_in_an1      (zn_an1),
   .zn_dsw         (zn_sw0[3:0]),
   .zn_jp1         (zn_sw0[4]),
`ifdef GNET_SHELL
   .zn_nozoom      (gnet_nozoom),
`endif
   .zn_card_present(zn_card_loaded),
   .zn_key_valid   (zn_card_loaded),
   .zn_coin        (),
   .zn_wd_reset    (zn_wd_reset),
   .zn_ld_wr       (zn_ld_wr),
   .zn_ld_target   (zn_ld_target),
   .zn_ld_addr     (zn_ld_addr),
   .zn_ld_data     (zn_ld_data),
   .zn_card_dl_wr  (zn_card_dl_wr),
   .zn_card_dl_addr(zn_card_dl_addr),
   .zn_card_dl_data(zn_card_dl_data),
   .zn_card_dl_busy(zn_card_dl_busy),
   .zn_ld_busy     (zn_ld_busy),
   .zn_fl_req      (zn_fl_req),
   .zn_fl_rnw      (zn_fl_rnw),
   .zn_fl_addr     (zn_fl_addr),
   .zn_fl_din      (zn_fl_din),
   .zn_fl_be       (zn_fl_be),
`ifdef GNET_CPU50
   .zn_fl_ready    (zn_fl_ready_c),   // clk_cpu: zn2_board is in the CPU group
`else
   .zn_fl_ready    (sdramCh3_done),
`endif
   .zn_fl_dout     (zn_fl_dout),
   .zn_dbg_idx     (zn_dbg_idx),
   .zn_dbg_word    (zn_dbg_word)
`ifdef GNET_SHELL
   ,
   .zn_nv_clk      (clk_1x),
   .zn_nv_addr     (ioctl_addr[10:1]),
   .zn_nv_q        (nv_din),
   .zn_nv_wtog     (zn_nv_wtog)
`endif
`ifdef GNET_ZOOM
   ,
   .zoom_m_req     (zoom_m_req),
   .zoom_m_line    (zoom_m_line),
   .zoom_m_ready   (zoom_m_ready),
   .zoom_m_rvalid  (zoom_m_rvalid),
   .zoom_m_rdata   (zoom_m_rdata),
   .zoom_rst       (zoom_rst),
   .zoom_aud_l     (zoom_aud_l),
   .zoom_aud_r     (zoom_aud_r),
   .zoom_flags     (zoom_flags),
   .zoom_hold      (paused)          // MN10200 held at an instruction boundary while the core is paused
`endif
`endif
);

`ifdef GNET_ZOOM
// MAME taitogn.cpp 441-448: SPU to the speakers at 0.3, Zoom at 1.0, both
// 16-bit full scale (rtl/zoom/zoom_mix.sv; the PCB balance is open, R13).
// The SPU gain is the OSD SFX Level in shell builds (0.3 default): MAME's
// spu.cpp ignores the SPU main volume the games set (Ray Crisis 0x1125,
// about 0.27), spu.vhd applies it, so the effects come out quieter than in
// MAME at the same route.
// Both inputs are clk_1x registers (spu.vhd, zoom_out.sv). With the
// release shell the mix goes to snd_l/snd_r, ahead of the OSD volume stage
// (gnet_volume); otherwise straight to AUDIO_L/R.
// Silent pause: while the core is paused the SPU (ce held) and the Zoom
// output stage (zoom_hold, docs/zoom_board_design.md 14.12) each repeat
// their last sample; both inputs are forced to 0 instead, so the pause is
// silent rather than a held DC level.
zoom_mix zoom_mix
(
	.clk   (clk_1x),
`ifdef GNET_SHELL
	.spu_lvl(status[119:117]),   // OSD SFX Level: 0.3 (MAME, default) ... 1.5
`else
	.spu_lvl(3'd0),              // 0.3, MAME's route
`endif
	.spu_l (paused ? 16'sd0 : spu_aud_l),
	.spu_r (paused ? 16'sd0 : spu_aud_r),
	.zoom_l(paused ? 16'sd0 : zoom_aud_l),
	.zoom_r(paused ? 16'sd0 : zoom_aud_r),
`ifdef GNET_SHELL
	.out_l (snd_l),
	.out_r (snd_r)
`else
	.out_l (AUDIO_L),
	.out_r (AUDIO_R)
`endif
);
`endif

////////////////////////////  MEMORY  ///////////////////////////////////

localparam ROM_START = (65536+131072)*4;

wire         sdr_refresh;
wire  [31:0] sdr_sdram_din;
wire  [31:0] sdr_sdram_dout32;
wire  [15:0] sdr_bram_din;
wire         sdr_sdram_ack;
wire         sdr_bram_ack;
wire  [24:0] sdram_addr;
wire   [1:0] sdram_cntDMA;
wire   [3:0] sdram_be;
wire         sdram_req;
wire         sdram_ack;
wire         sdram_readack;
wire         sdram_readack2;
wire         sdram_writeack;
wire         sdram_writeack2;
wire         sdram_rnw;
wire         sdram_dma;
wire         sdram_cache;
wire [ 3:0]  cache_wr;
wire [31:0]  cache_data;
wire [ 7:0]  cache_addr;
wire         dma_wr;
wire         dma_reqprocessed;
wire [31:0]  dma_data;

wire  [22:0] sdram_dmafifo_adr;
wire  [31:0] sdram_dmafifo_data;
wire         sdram_dmafifo_empty;
wire         sdram_dmafifo_read;


wire [20:0] cheats_addr;
wire cheats_rnw;
wire [3:0] cheats_be;
wire [31:0] cheats_dout;
wire cheats_ena;
wire [31:0] cheats_din;
wire sdramCh3_done;

assign sdram_ack = sdram_readack | sdram_writeack;

`ifdef GNET_CPU50
// R1: the SDRAM controller runs with the CPU group (clk_base clk_cpu, clk
// clk_cpu2x). Channel 3 is driven from clk_1x (HPS downloads, cheats), so its
// requests cross in a cdc_handshake (rtl/gnet/cdc): address, data, rnw and
// byte enables held, ch3_dout and the done pulse back.
wire [26:0] ch3c_addr;
wire [31:0] ch3c_din;
wire        ch3c_rnw;
wire  [3:0] ch3c_be;
wire        ch3c_req;
wire [31:0] ch3c_dout;
wire        ch3c_ready;

`ifdef GNET_ZN2
// G-NET with the CPU group: zn2_board (and its flash storage port) runs on
// clk_cpu next to the SDRAM controller, so only the downloads (BIOS, flash
// images) cross from clk_1x. rtl/gnet/zn2_ch3_arb.vhd shares channel 3
// between the download handshake and the flash port, one request at a time.
wire [26:0] ch3h_addr;
wire [31:0] ch3h_din;
wire        ch3h_rnw;
wire  [3:0] ch3h_be;
wire        ch3h_req;
wire        ch3h_ack;

cdc_handshake #(.REQ_W(64), .RSP_W(32)) ch3_cdc
(
	.src_clk     (clk_1x),
	.src_rst     (1'b0),
	.src_start   ((exe_download | bios_download | gnet_flash_dl) & ramdownload_wr),
	.src_req_data({ramdownload_wraddr, ramdownload_wrdata, 1'b0, 4'b1111}),
	.src_busy    (),
	.src_done    (sdramCh3_done),
	.src_rsp_data(),
	.dst_clk     (clk_cpu),
	.dst_rst     (1'b0),
	.dst_valid   (ch3h_req),
	.dst_req_data({ch3h_addr, ch3h_din, ch3h_rnw, ch3h_be}),
	.dst_pending (),
	.dst_ack     (ch3h_ack),
	.dst_rsp_data(ch3c_dout)
);

zn2_ch3_arb ch3_arb
(
	.clk      (clk_cpu),
`ifdef GNET_DDR3_ARB
	.stall    (gnet_ch3_stall),
`endif
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
	.b_ready  (zn_fl_ready_c),
`ifdef GNET_ZOOM_SDRAM_PATH
	// Taito Zoom flash area reads (rtl/gnet/zoom_sdram_link.vhd): 32-bit
	// reads, byte enables 1111 (read DQM, 13b6e1d)
	.c_req    (zoom_fl_req),
	.c_addr   (zoom_fl_addr),
	.c_din    (32'd0),
	.c_rnw    (1'b1),
	.c_be     (4'b1111),
	.c_ready  (zoom_fl_ready),
`endif
	.ch3_req  (ch3c_req),
	.ch3_addr (ch3c_addr),
	.ch3_din  (ch3c_din),
	.ch3_rnw  (ch3c_rnw),
	.ch3_be   (ch3c_be),
	.ch3_ready(ch3c_ready)
);
assign zn_fl_dout = ch3c_dout;
`ifdef GNET_ZOOM_SDRAM_PATH
// temporary SDRAM path of the Zoom flash area (see the zoom_m_* wires)
zoom_sdram_link zoom_sdram_link
(
	.clk_cpu    (clk_cpu),
	.clk1x      (clk_1x),
	.p_board_rst(zoom_rst),
	.p_m_req    (zoom_m_req),
	.p_m_line   (zoom_m_line),
	.p_m_ready  (zoom_m_ready),
	.p_m_rvalid (zoom_m_rvalid),
	.p_m_rdata  (zoom_m_rdata),
	.c_fl_req   (zoom_fl_req),
	.c_fl_addr  (zoom_fl_addr),
	.c_fl_ready (zoom_fl_ready),
	.c_fl_dout  (ch3c_dout)
);
`endif
`else
cdc_handshake #(.REQ_W(64), .RSP_W(32)) ch3_cdc
(
	.src_clk     (clk_1x),
	.src_rst     (1'b0),
	.src_start   ((exe_download | bios_download) ? ramdownload_wr : cheats_ena),
	.src_req_data({((exe_download | bios_download) ? ramdownload_wraddr : cheats_addr),
	               ((exe_download | bios_download) ? ramdownload_wrdata : cheats_dout),
	               ((exe_download | bios_download) ? 1'b0 : cheats_rnw),
	               ((exe_download | bios_download) ? 4'b1111 : cheats_be)}),
	.src_busy    (),
	.src_done    (sdramCh3_done),
	.src_rsp_data(cheats_din),
	.dst_clk     (clk_cpu),
	.dst_rst     (1'b0),
	.dst_valid   (ch3c_req),
	.dst_req_data({ch3c_addr, ch3c_din, ch3c_rnw, ch3c_be}),
	.dst_pending (),
	.dst_ack     (ch3c_ready),
	.dst_rsp_data(ch3c_dout)
);
`endif
`endif

sdram #(.CLK_FAST_RATIO(GNET_CLK_FAST_RATIO), .EARLY_READY(GNET_EARLY_READY_P)) sdram
(
   .SDRAM_DQ   (SDRAM_DQ),
   .SDRAM_A    (SDRAM_A),
   .SDRAM_DQML (SDRAM_DQML),
   .SDRAM_DQMH (SDRAM_DQMH),
   .SDRAM_BA   (SDRAM_BA),
   .SDRAM_nCS  (SDRAM_nCS),
   .SDRAM_nWE  (SDRAM_nWE),
   .SDRAM_nRAS (SDRAM_nRAS),
   .SDRAM_nCAS (SDRAM_nCAS),
   .SDRAM_CKE  (SDRAM_CKE),
   .SDRAM_CLK  (SDRAM_CLK),

   .SDRAM_EN(1),
`ifdef GNET_CPU50
	.init(~pll_cpu_locked),
	.clk(clk_cpu2x),
	.clk_base(clk_cpu),
`else
	.init(~pll_locked),
	.clk(clk_3x),
	.clk_base(clk_1x),
`endif

	.refreshForce(sdr_refresh),

	.ch1_addr(sdram_addr),
	.ch1_din(),
	.ch1_dout(),
	.ch1_dout32(sdr_sdram_dout32),
	.ch1_req(sdram_req & sdram_rnw),
	.ch1_rnw(1'b1),
	.ch1_dma(sdram_dma),
	.ch1_cntDMA(sdram_cntDMA),
	.ch1_cache(sdram_cache),
	.ch1_ready(sdram_readack),
	.cache_wr(cache_wr),
	.cache_data(cache_data),
	.cache_addr(cache_addr),
	.dma_wr(dma_wr),
	.dma_reqprocessed(dma_reqprocessed),
	.dma_data(dma_data),

	.ch2_addr (sdram_addr),
	.ch2_din  (sdr_sdram_din),
	.ch2_dout (),
	.ch2_req  (sdram_req & ~sdram_rnw),
	.ch2_rnw  (1'b0),
	.ch2_be   (sdram_be),
	.ch2_ready(sdram_writeack),

`ifdef GNET_CPU50
	.ch3_addr (ch3c_addr),
	.ch3_din  (ch3c_din),
	.ch3_dout (ch3c_dout),
	.ch3_req  (ch3c_req),
	.ch3_rnw  (ch3c_rnw),
	.ch3_be   (ch3c_be),
	.ch3_ready(ch3c_ready),
`elsif GNET_ZN2
	// G-NET: downloads, then the flash storage port of zn2_board
	.ch3_addr ((exe_download | bios_download | gnet_flash_dl) ? ramdownload_wraddr : zn_fl_addr),
	.ch3_din  ((exe_download | bios_download | gnet_flash_dl) ? ramdownload_wrdata : zn_fl_din),
	.ch3_dout (zn_fl_dout),
	.ch3_req  ((exe_download | bios_download | gnet_flash_dl) ? ramdownload_wr     : zn_fl_req),
	.ch3_rnw  ((exe_download | bios_download | gnet_flash_dl) ? 1'b0               : zn_fl_rnw),
	.ch3_be   ((exe_download | bios_download | gnet_flash_dl) ? 4'b1111            : zn_fl_be),
	.ch3_ready(sdramCh3_done),
`else
	.ch3_addr ((exe_download | bios_download) ? ramdownload_wraddr : cheats_addr),
	.ch3_din  ((exe_download | bios_download) ? ramdownload_wrdata : cheats_dout),
	.ch3_dout (cheats_din),
	.ch3_req  ((exe_download | bios_download) ? ramdownload_wr     : cheats_ena),
	.ch3_rnw  (cheats_rnw),
	.ch3_be   ((exe_download | bios_download) ? 4'b1111            : cheats_be),
	.ch3_ready(sdramCh3_done),
`endif

	.dmafifo_adr  (sdram_dmafifo_adr),
	.dmafifo_data (sdram_dmafifo_data),
	.dmafifo_empty(sdram_dmafifo_empty),
	.dmafifo_read (sdram_dmafifo_read)
);

wire [31:0] spuram_dataWrite;
wire [18:0] spuram_Adr;
wire  [3:0] spuram_be;
wire        spuram_rnw;
wire        spuram_ena;
wire [31:0] spuram_dataRead;
wire        spuram_done;

assign spuram_done     = sdram_readack2 | sdram_writeack2;

`ifdef MISTER_DUAL_SDRAM

sdram sdram2
(
	.SDRAM_DQ   (SDRAM2_DQ),
   .SDRAM_A    (SDRAM2_A),
   .SDRAM_DQML (),
   .SDRAM_DQMH (),
   .SDRAM_BA   (SDRAM2_BA),
   .SDRAM_nCS  (SDRAM2_nCS),
   .SDRAM_nWE  (SDRAM2_nWE),
   .SDRAM_nRAS (SDRAM2_nRAS),
   .SDRAM_nCAS (SDRAM2_nCAS),
   .SDRAM_CKE  (),
   .SDRAM_CLK  (SDRAM2_CLK),
   .SDRAM_EN   (SDRAM2_EN),

	.init(~pll_locked),
	.clk(clk_3x),
	.clk_base(clk_1x),

	.refreshForce(1'b0),
	.ram_idle(),

	.ch1_addr(spuram_Adr),
	.ch1_din(),
	.ch1_dout(),
	.ch1_dout32(spuram_dataRead),
	.ch1_req(spuram_ena & spuram_rnw),
	.ch1_rnw(1'b1),
	.ch1_dma(1'b0),
   .ch1_cntDMA(2'b00),
	.ch1_cache(1'b0),
	.ch1_ready(sdram_readack2),

	.ch2_addr (spuram_Adr),
	.ch2_din  (spuram_dataWrite),
	.ch2_dout (),
	.ch2_req  (spuram_ena & ~spuram_rnw),
	.ch2_rnw  (1'b0),
   .ch2_be   (spuram_be),
	.ch2_ready(sdram_writeack2),

	.ch3_addr(0),
	.ch3_din(),
	.ch3_dout(),
	.ch3_req(1'b0),
	.ch3_rnw(1'b1),
	.ch3_ready(),

	.dmafifo_adr  (0),
	.dmafifo_data (0),
	.dmafifo_empty(1'b1),
	.dmafifo_read ()
);

`else

wire SDRAM2_EN = 0;

assign spuram_dataRead = '0;
assign sdram_readack2 = '0;
assign sdram_writeack2 = '0;

`endif


assign DDRAM_CLK = clk_2x;


////////////////////////////  VIDEO  ////////////////////////////////////

assign CLK_VIDEO = clk_vid;

wire hs, vs, hbl, vbl, video_interlace, video_isPal, video_fbmode, video_fb24;

wire [2:0] video_hResMode;

wire ce_pix;
wire [7:0] r,g,b;

wire hack_480p = status[89];

`ifdef GNET_SHELL
// Black picture with running sync while the core's video timing is held in
// reset (downloads, reset sequencer): rtl/gnet/gnet_sync_keeper.sv
gnet_sync_keeper sync_keeper
(
	.clk     (clk_vid),
	.c_ce    (ce_pix_c),
	.c_hs    (hs_c),
	.c_vs    (vs_c),
	.c_hbl   (hbl_c),
	.c_vbl   (vbl_c),
	.c_r     (r_c),
	.c_g     (g_c),
	.c_b     (b_c),
	.c_hres  (video_hResMode_c),
	.o_ce    (ce_pix),
	.o_hs    (hs_k),
	.o_vs    (vs_k),
	.o_hbl   (hbl),
	.o_vbl   (vbl),
	.o_r     (r),
	.o_g     (g),
	.o_b     (b),
	.o_hres  (video_hResMode),
	.o_substitute()
);

// OSD CRT H/V position: moves hsync and vsync only (rtl/gnet/gnet_crt_pos.sv)
gnet_crt_pos crt_pos
(
	.clk  (clk_vid),
	.hs   (hs_k),
	.vs   (vs_k),
	.hres (video_hResMode),
	.crt_h(status[110:107]),
	.crt_v(status[113:111]),
	.hs_o (hs),
	.vs_o (vs)
);

// OSD volume at the final mix (rtl/gnet/gnet_volume.sv): snd_l/snd_r is the
// SPU alone, or with GNET_ZOOM the SPU and Taito Zoom mix (zoom_mix).
gnet_volume volume
(
	.clk  (clk_1x),
	.vol  (status[106:105]),
	.in_l (snd_l),
	.in_r (snd_r),
	.out_l(AUDIO_L),
	.out_r(AUDIO_R)
);

// G-NET draws exactly 256/320/512/640 dots in every mode it uses (GP1(06h)
// X1..X2 = 2560 clocks), so the game's own hblank is the active area and the
// HDMI aspect is 4:3 for it (3:4 rotated), as an arcade monitor adjusted to
// fill the tube shows it (docs/m4_shell.md).
localparam GNET_GAME_HBLANK = 1'b1;
`else
localparam GNET_GAME_HBLANK = 1'b0;
`endif

typedef struct {
	logic [7:0] red;
	logic [7:0] green;
	logic [7:0] blue;
	logic       hs;
	logic       vs;
	logic       hb;
	logic       vb;
	logic       interlace;
} vid_info;

vid_info video_aspect;
vid_info video_gamma;

`ifndef GNET_SHELL
assign CE_PIXEL = ce_pix;
assign VGA_R    = video_gamma.red;
assign VGA_G    = video_gamma.green;
assign VGA_B    = video_gamma.blue;
assign VGA_VS   = video_gamma.vs;
assign VGA_HS   = video_gamma.hs;
assign VGA_DE   = ~(video_gamma.vb | video_gamma.hb);
assign VGA_SL = 0;
`endif
// GNET_SHELL: CE_PIXEL, VGA_R/G/B/HS/VS/DE and VGA_SL come from arcade_video
assign VGA_F1   =  status[14] ? 1'b0 : video_aspect.interlace;

`ifdef GNET_DDR3_ARB
////////////////////////////  DDR3 ARBITER  /////////////////////////////
// docs/ddr3_arbiter.md: rotation, Taito Zoom, glue and the core share the
// emu DDRAM port through rtl/gnet/gnet_ddr3_arb.sv, all on clk_2x. Needs
// GNET_ZN2 and GNET_CPU50 (the flash mirror taps the CPU-group channel 3).

// Without the release shell rotation is off; with it (GNET_SHELL) the
// shell drives gnet_rot_en and gnet_rot_ccw from the Orientation and Rotate
// Direction OSD items.
`ifndef GNET_SHELL
assign gnet_rot_en  = 1'b0;
assign gnet_rot_ccw = 1'b0;
`endif
// Zoom line port: with GNET_ZOOM, psx_top's zoom_board drives zoom_m_req,
// zoom_m_line and zoom_rst (clk_1x, declared with the loader wires) and the
// arbiter answers on zoom_m_ready/rvalid/rdata from the flash mirror at DDR3
// 0x31000000 (GNET_ZOOM_SDRAM is ignored, ZSG-2 INFL 8). Without the Zoom
// board: no requests.
`ifndef GNET_ZOOM
wire        zoom_m_req   = 1'b0;
wire [20:0] zoom_m_line  = 21'd0;
wire        zoom_rst     = 1'b0;   // Zoom-side reset (clk_1x)
wire        zoom_m_ready, zoom_m_rvalid;
wire [63:0] zoom_m_rdata;
`endif

// screen_rotate (sys/arcade_video.v) on the core's video; its DDRAM writes
// go to the arbiter's rotation FIFO, never straight to the port. It takes
// the gamma-corrected video before any scandoubler, with the core's dot
// enable, on clk_vid: in GNET_SHELL builds from a second gamma_corr on the
// overlay output (rot_gamma, VIDEO section), otherwise from video_gamma.
// Taking arcade_video's outputs instead (the MiSTer template's way) would
// feed it the scandoubler Fx: scanlines double and HQ2x quadruples the
// writes (one per clk_vid at 640 dots), which overflows the rotation FIFO
// once DDR3 BUSY reaches about 40% or holds for 20 us (sim/rotfx). The Fx
// still apply to the unrotated output; the rotated picture is the scaler's.
`ifdef GNET_SHELL
wire        rotv_hs, rotv_vs, rotv_hb, rotv_vb;
wire [23:0] rotv_rgb;
`endif
wire        rot_we;
wire [28:0] rot_addr;
wire [63:0] rot_din;
wire  [7:0] rot_be;
screen_rotate screen_rotate
(
	.CLK_VIDEO(clk_vid),
`ifdef GNET_SHELL
	.CE_PIXEL(ce_pix),
	.VGA_R(rotv_rgb[23:16]),
	.VGA_G(rotv_rgb[15:8]),
	.VGA_B(rotv_rgb[7:0]),
	.VGA_HS(rotv_hs),
	.VGA_VS(rotv_vs),
	.VGA_DE(~(rotv_vb | rotv_hb)),
`else
	.CE_PIXEL(ce_pix),
	.VGA_R(video_gamma.red),
	.VGA_G(video_gamma.green),
	.VGA_B(video_gamma.blue),
	.VGA_HS(video_gamma.hs),
	.VGA_VS(video_gamma.vs),
	.VGA_DE(~(video_gamma.vb | video_gamma.hb)),
`endif
	.rotate_ccw(gnet_rot_ccw),
	.no_rotate(~gnet_rot_en),
	.flip(1'b0),
	.video_rotated(video_rotated),
	.FB_EN(rot_fb_en),
	.FB_FORMAT(rot_fb_format),
	.FB_WIDTH(rot_fb_width),
	.FB_HEIGHT(rot_fb_height),
	.FB_BASE(rot_fb_base),
	.FB_STRIDE(rot_fb_stride),
	.FB_VBL(FB_VBL),
	.FB_LL(FB_LL),
	.DDRAM_CLK(),
	.DDRAM_BUSY(1'b0),
	.DDRAM_BURSTCNT(),
	.DDRAM_ADDR(rot_addr),
	.DDRAM_DIN(rot_din),
	.DDRAM_BE(rot_be),
	.DDRAM_WE(rot_we),
	.DDRAM_RD()
);

// Zoom line port, clk_1x to clk_2x
wire        arb_z_req, arb_z_ready, arb_z_rvalid;
wire [20:0] arb_z_line;
gnet_ddr3_zport zport
(
	.clk2x(clk_2x),
	.clk1x(clk_1x),
	.zrst(zoom_rst),
	.m_req(zoom_m_req),
	.m_line(zoom_m_line),
	.m_ready(zoom_m_ready),
	.m_rvalid(zoom_m_rvalid),
	.m_rdata(zoom_m_rdata),
	.z_req(arb_z_req),
	.z_line(arb_z_line),
	.z_ready(arb_z_ready),
	.z_rvalid(arb_z_rvalid),
	.z_rdata(arb_rdata)
);

// flash area writes on channel 3 (clk_cpu) mirrored into DDR3 for the Zoom
wire        mir_we, mir_busy, mir_ovf;
wire [28:0] mir_addr;
wire [63:0] mir_din;
wire  [7:0] mir_be;
gnet_ddr3_mirror mirror
(
	.clk_src(clk_cpu),
	.w_req(ch3c_req && !ch3c_rnw),
	.w_addr(ch3c_addr),
	.w_din(ch3c_din),
	.w_be(ch3c_be),
	.stall(gnet_ch3_stall),
	.clk2x(clk_2x),
	.g_we(mir_we),
	.g_addr(mir_addr),
	.g_din(mir_din),
	.g_be(mir_be),
	.g_busy(mir_busy),
	.ovf(mir_ovf)
);

// reset only at power-up: the core keeps reads in flight across its own
// resets, and the owner FIFO must keep matching them
reg [2:0] arb_rst_s = 3'b111;
always @(posedge clk_2x) arb_rst_s <= {arb_rst_s[1:0], ~pll_locked};

// status for a debug page (all clk_2x): rotation FIFO overflowed (sticky),
// its highest fill level (of 512), owner FIFO overflow (protocol error,
// sticky), flash mirror FIFO overflow (sticky; the stall prevents it)
wire        gnet_ddr3_rot_ovf, gnet_ddr3_own_ovf, gnet_ddr3_mirror_ovf;
wire  [9:0] gnet_ddr3_rot_hiwater;
assign gnet_ddr3_mirror_ovf = mir_ovf;
gnet_ddr3_arb ddr3_arb
(
	.clk(clk_2x),
	.rst(arb_rst_s[2]),
	.ddr_busy(DDRAM_BUSY),
	.ddr_burstcnt(DDRAM_BURSTCNT),
	.ddr_addr(DDRAM_ADDR),
	.ddr_dout(DDRAM_DOUT),
	.ddr_dout_ready(DDRAM_DOUT_READY),
	.ddr_rd(DDRAM_RD),
	.ddr_din(DDRAM_DIN),
	.ddr_be(DDRAM_BE),
	.ddr_we(DDRAM_WE),
	.rot_clk(clk_vid),
	.rot_we(rot_we),
	.rot_addr(rot_addr),
	.rot_din(rot_din),
	.rot_be(rot_be),
	.z_req(arb_z_req),
	.z_line(arb_z_line),
	.z_ready(arb_z_ready),
	.z_rvalid(arb_z_rvalid),
	.g_rd(1'b0),
	.g_we(mir_we),
	.g_addr(mir_addr),
	.g_burstcnt(8'd1),
	.g_din(mir_din),
	.g_be(mir_be),
	.g_busy(mir_busy),
	.g_dout_ready(),
	.c_rd(core_ddr_rd),
	.c_we(core_ddr_we),
	.c_addr(core_ddr_addr),
	.c_burstcnt(core_ddr_burstcnt),
	.c_din(core_ddr_din),
	.c_be(core_ddr_be),
	.c_busy(core_ddr_busy),
	.c_dout_ready(core_ddr_dout_ready),
	.rdata(arb_rdata),
	.rot_ovf(gnet_ddr3_rot_ovf),
	.rot_hiwater(gnet_ddr3_rot_hiwater),
	.own_ovf(gnet_ddr3_own_ovf)
);
`endif
logic [11:0] aspect_x, aspect_y;

wire [1:0] ar = status[33:32];
video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),

`ifdef GNET_SHELL
	.ARX((!ar) ? (gnet_rot_en ? 12'd3 : 12'd4) : {10'd0, ar - 2'd1}),
	.ARY((!ar) ? (gnet_rot_en ? 12'd4 : 12'd3) : 12'd0),
`else
	.ARX((!ar) ? ((status[54:53] == 1) ? 3 : (status[54:53] == 2) ? 5 : (status[54:53] == 3) ? 16 : status[11] ? 12'd2 : aspect_x) : (ar - 1'd1)),
	.ARY((!ar) ? ((status[54:53] == 1) ? 2 : (status[54:53] == 2) ? 3 : (status[54:53] == 3) ?  9 : status[11] ? 12'd1 : aspect_y) : 12'd0),
`endif
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(status[35:34])
);

// Res  Div Padding
// 256  10  +25
// 320  8   +32
// 368  7   +37
// 512  5   +51
// 640  4   +64

localparam reg [23:0] aspect_ratio_lut_ntsc[128] = '{
    24'h37015B, 24'h2B4113, 24'h1A10A7, 24'hEB45EF, 24'hA00411, 24'hF8365B, 24'hA31435, 24'h6A42C3,
    24'h85D381, 24'hF8F691, 24'h581257, 24'h1860A7, 24'hFD56D4, 24'h6EF303, 24'h497202, 24'hDA1601,
    24'hF8D6E6, 24'h8513B7, 24'hB014F3, 24'h3C51B5, 24'h3971A3, 24'hC02583, 24'hD09606, 24'h4E1245,
    24'hFEF776, 24'hC555D0, 24'hBD559D, 24'hE686E1, 24'hF7C771, 24'hC4F5F4, 24'h655315, 24'hB5158B,
    24'h2C015B, 24'h1750B9, 24'hC74637, 24'hF857CB, 24'h89B459, 24'h800411, 24'hC87668, 24'hA21536,
    24'hFB3820, 24'h443238, 24'hE17761, 24'hFD3856, 24'h207113, 24'h204113, 24'h3941EB, 24'hE6F7C8,
    24'h28015B, 24'hD55745, 24'hD21733, 24'hE9F810, 24'hC0A6AD, 24'h99955A, 24'hA0359D, 24'h7FF482,
    24'hD5B792, 24'hE5C82F, 24'hF558C9, 24'h35D1F0, 24'h6EF404, 24'h93155A, 24'h5BF35D, 24'h9F75DD,
    24'h6E0411, 24'h2DF1B5, 24'h44D292, 24'h1160A7, 24'hB4F6D4, 24'hD49810, 24'hD057F1, 24'h91B595,
    24'hB006C7, 24'hF959A6, 24'hE338D6, 24'hC1378D, 24'hC557C0, 24'hF579B0, 24'h7E1500, 24'hABD6D9,
    24'hFE3A2E, 24'hD3D886, 24'h54736A, 24'hFF3A5E, 24'hE19935, 24'hF42A03, 24'h356233, 24'hFEBA8B,
    24'h957637, 24'hEFAA03, 24'h43F2DA, 24'hA6F70A, 24'h20015B, 24'h24D191, 24'h72E4E9, 24'hC1E853,
    24'hDC097D, 24'hD09909, 24'hFE8B13, 24'hD5E959, 24'hFEFB31, 24'h2B81EB, 24'h8A5620, 24'h2B91F0,
    24'h2AF1EB, 24'hD3F982, 24'hED9AB4, 24'h163101, 24'h724531, 24'hDCBA12, 24'hC50907, 24'hFB7B92,
    24'h580411, 24'hFDDBC7, 24'hAA77F1, 24'hD259D7, 24'h2ED233, 24'h2431B5, 24'hC1992B, 24'h20F191,
    24'h7665A7, 24'h42D334, 24'hD09A0A, 24'hF17BAB, 24'hFFFC6B, 24'h6B653B, 24'h5153FA, 24'hFD9C73
};

localparam reg [23:0] aspect_ratio_lut_pal[160] = '{
    24'hE8F4D9, 24'h41015D, 24'h40815D, 24'h8EB30A, 24'hF8D557, 24'h1C009B, 24'h1CB0A0, 24'h473190,
    24'h711280, 24'hCEF49C, 24'hD734D4, 24'hCAC495, 24'h4791A1, 24'hF695A7, 24'hC7549A, 24'hC31489,
    24'hAEB417, 24'hB8C45B, 24'hA2C3DD, 24'hBCF484, 24'hD2E513, 24'hC2A4B7, 24'hEFF5DA, 24'h85D349,
    24'h18809B, 24'h0C9050, 24'hF59626, 24'hE595C9, 24'h35C15D, 24'hF81655, 24'h0EC061, 24'hEA160D,
    24'h68D2BA, 24'hD735A2, 24'h4731E0, 24'hE9A631, 24'hDC35DF, 24'h6D12ED, 24'h96D412, 24'hB87502,
    24'hCFF5AE, 24'h73732C, 24'hF1D6AF, 24'h7CA377, 24'h30C15D, 24'hA7A4B7, 24'h5C629D, 24'h3941A1,
    24'h4A221F, 24'hF5B712, 24'hD5F631, 24'h8ED428, 24'h8BC417, 24'hE236A8, 24'hA854FB, 24'hEAE6FD,
    24'hD73670, 24'hD5666B, 24'hFD97AB, 24'hA8751F, 24'hCDA649, 24'hCE1655, 24'h5C92DC, 24'h3BC1DB,
    24'hAEB574, 24'hB5A5B3, 24'hFE8807, 24'h2B015D, 24'h13009B, 24'hB6F5DC, 24'hA5E557, 24'hC7D677,
    24'hD1A6D1, 24'h099050, 24'hEF37DB, 24'hB8C619, 24'h25B140, 24'h4FD2A9, 24'hE1978E, 24'hD7373E,
    24'h28515D, 24'hE437C1, 24'hD35737, 24'hF4D866, 24'hF97899, 24'h42724D, 24'h5572F9, 24'h27015D,
    24'hCF0745, 24'h6D83DD, 24'hFFB910, 24'hE35818, 24'hEB2869, 24'hB1565F, 24'hF3F8CE, 24'hE05822,
    24'h10A09B, 24'hEFF8C7, 24'h9E35D0, 24'h87B502, 24'hBAF6EE, 24'hD7D809, 24'hD7380C, 24'hF59939,
    24'h2E31BE, 24'hE0B883, 24'h6B8417, 24'h93F5A7, 24'h09E061, 24'hE3B8C6, 24'hBCE74F, 24'h2FC1DB,
    24'h22F15D, 24'h818513, 24'h5ED3BB, 24'hFF3A15, 24'h5AB399, 24'hB52737, 24'hF0199A, 24'hEE5992,
    24'hBDB7A6, 24'hC74811, 24'h3FD298, 24'h77F4E5, 24'h4552D7, 24'h1390CE, 24'hE4D973, 24'h25B190,
    24'h91960F, 24'hBBD7D9, 24'h20815D, 24'h788513, 24'h20415D, 24'h9BF69E, 24'h8EB614, 24'h8435A7,
    24'hF8DAAE, 24'h9B26AF, 24'h0E009B, 24'h8EA631, 24'h1CB140, 24'h1B112F, 24'hD05925, 24'hD1F940,
    24'h89060F, 24'hD7098B, 24'h88060F, 24'h4172ED, 24'hD739A8, 24'hDBE9E7, 24'h656495, 24'hFF8B97,
    24'hD1A98B, 24'hA6D79F, 24'hB4E84B, 24'hEC7AE1, 24'hFF1BC7, 24'h5C944A, 24'hC31912, 24'hEE8B21
};

logic [11:0] h_pos, v_pos, vb_pos, v_total;
logic [11:0] hb_start_lut[8];
logic [11:0] hb_end_lut[8];
logic [11:0] hb_start, hb_end;

// FIXME: this should be adjusted if hsync changes size to maintain center
assign hb_start_lut = '{12'd63,  12'd50,  12'd36,  12'd31,  12'd24,  12'd0, 12'd0, 12'd0};
assign hb_end_lut =   '{12'd767, 12'd613, 12'd441, 12'd383, 12'd305, 12'd0, 12'd0, 12'd0};

always_comb begin
	hb_start = hb_start_lut[video_hResMode];
	hb_end = hb_end_lut[video_hResMode];
end

// steps on the core's dot enable ce_pix (equal to CE_PIXEL except in
// GNET_SHELL builds, where CE_PIXEL comes from arcade_video's mixer)
always_ff @(posedge CLK_VIDEO) if (ce_pix) begin
	logic old_vb;
	old_vb <= vbl;
	video_aspect.hs <= hs;
	video_aspect.vs <= vs;
	video_aspect.vb <= vbl;
	video_aspect.interlace <= video_interlace;
	video_aspect.red <= (vbl || hbl) ? 8'd0 : r;
	video_aspect.green <= (vbl || hbl) ? 8'd0 : g;
	video_aspect.blue <= (vbl || hbl) ? 8'd0 : b;
	{aspect_x, aspect_y} <= video_isPal ? aspect_ratio_lut_pal[v_total] : aspect_ratio_lut_ntsc[v_total];

	VGA_DISABLE <= fast_forward;

	h_pos <= h_pos + 1'd1;
	if (~old_vb && vbl)
		vb_pos <= 0;

	if (video_aspect.hs && ~hs) begin
		h_pos <= 0;
		if (~vbl)
			v_pos <= v_pos + 1'd1;
		else
			vb_pos <= vb_pos + 1'd1;
	end

	if (~video_aspect.vs && vs) begin
		v_pos <= 0;

		if (v_pos < 128)
			v_total <= 6'd0;
		else if (video_isPal && v_pos > 287)
			v_total <= 8'd159;
		else if (~video_isPal && v_pos > 255)
			v_total <= 7'd127;
		else
			v_total <= v_pos - 8'd128;
	end

	if (vb_pos > (video_isPal ? 161 : 135))
		video_aspect.vb <= 0;

	if (h_pos == hb_start)
		video_aspect.hb <= 0;
	if (h_pos == hb_end)
		video_aspect.hb <= 1;
	if (status[62] || hack_480p || (status[54:53] > 0) || GNET_GAME_HBLANK)
		video_aspect.hb <= hbl;

end

`ifdef GNET_ZN2
// G-NET debug overlay (docs/hw_debug_overlay.md, OSD status[101]): hex text
// mixed into the RGB between video_aspect and gamma_corr, stepped by
// CE_PIXEL. With the option off rgb_dbg is video_aspect's RGB unchanged.
wire [23:0] rgb_dbg;

// DR row (GNET_DDR3_ARB builds only): the DDR3 arbiter status, all clk_2x,
// fetched by the overlay over its own cdc_handshake into clk_2x. Digits:
// rotation FIFO overflow | owner FIFO overflow | flash mirror overflow | 0,
// then the rotation FIFO high-water mark (of 512). Without the arbiter the
// row is not built (DR_ROW 0) and the word is tied to 0.
`ifdef GNET_DDR3_ARB
localparam GNET_DBG_DR_ROW = 1;
wire [31:0] gnet_dbg_dr_word = {3'd0, gnet_ddr3_rot_ovf, 3'd0, gnet_ddr3_own_ovf,
                                3'd0, gnet_ddr3_mirror_ovf, 4'd0, 6'd0, gnet_ddr3_rot_hiwater};
`else
localparam GNET_DBG_DR_ROW = 0;
wire [31:0] gnet_dbg_dr_word = 32'd0;
`endif

zn_dbg_overlay #(.DR_ROW(GNET_DBG_DR_ROW)) dbg_ovl
(
	.clk_cfg (clk_1x),
	.cfg_en  (status[101]),
`ifdef GNET_CPU50
	.clk_src (clk_cpu),
`else
	.clk_src (clk_1x),
`endif
	.src_idx (zn_dbg_idx),
	.src_word(zn_dbg_word),
	.clk_dr  (clk_2x),
	.dr_word (gnet_dbg_dr_word),
	.clk_vid (CLK_VIDEO),
	.ce_pix  (ce_pix),
	.hres_dbl(video_hResMode[2:1] == 2'b00),   // 640 or 512 dots per line
	.hb      (video_aspect.hb),
	.vb      (video_aspect.vb),
	.rgb_in  ({video_aspect.red,video_aspect.green,video_aspect.blue}),
	.rgb_out (rgb_dbg)
);
`endif

`ifdef GNET_SHELL
// Scandoubler Fx and gamma through the framework's arcade_video (as my
// other cores): HQ2x or CRT scanlines when Fx is set or the scandoubler is
// forced (31 kHz VGA). With Fx None and no forced scandoubler CE_PIXEL is the
// core's dot enable, one dot every 10/8/5/4 clocks (DV1, docs/m4_shell.md 2).
arcade_video #(.WIDTH(640), .DW(24)) arcade_video
(
	.clk_video(CLK_VIDEO),
	.ce_pix   (ce_pix),
	.RGB_in   (rgb_dbg),
	.HBlank   (video_aspect.hb),
	.VBlank   (video_aspect.vb),
	.HSync    (video_aspect.hs),
	.VSync    (video_aspect.vs),
	.CLK_VIDEO(),
	.CE_PIXEL (CE_PIXEL),
	.VGA_R    (VGA_R),
	.VGA_G    (VGA_G),
	.VGA_B    (VGA_B),
	.VGA_HS   (VGA_HS),
	.VGA_VS   (VGA_VS),
	.VGA_DE   (VGA_DE),
	.VGA_SL   (VGA_SL),
	.fx       (status[116:114]),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);
`ifdef GNET_DDR3_ARB
// The rotation feed (see screen_rotate): the same gamma table as
// arcade_video's (gamma_bus is only read here; video_mixer drives bit 21),
// on the pre-scandoubler video.
gamma_corr rot_gamma
(
	.clk_sys(gamma_bus[20]),
	.clk_vid(CLK_VIDEO),
	.ce_pix(ce_pix),
	.gamma_en(gamma_bus[19]),
	.gamma_wr(gamma_bus[18]),
	.gamma_wr_addr(gamma_bus[17:8]),
	.gamma_value(gamma_bus[7:0]),
	.HSync(video_aspect.hs),
	.VSync(video_aspect.vs),
	.HBlank(video_aspect.hb),
	.VBlank(video_aspect.vb),
	.RGB_in(rgb_dbg),
	.HSync_out(rotv_hs),
	.VSync_out(rotv_vs),
	.HBlank_out(rotv_hb),
	.VBlank_out(rotv_vb),
	.RGB_out(rotv_rgb)
);
`endif
`else
assign gamma_bus[21] = 1;
gamma_corr gamma(
	.clk_sys(gamma_bus[20]),
	.clk_vid(CLK_VIDEO),
	.ce_pix(CE_PIXEL),

	.gamma_en(gamma_bus[19]),
	.gamma_wr(gamma_bus[18]),
	.gamma_wr_addr(gamma_bus[17:8]),
	.gamma_value(gamma_bus[7:0]),

	.HSync(video_aspect.hs),
	.VSync(video_aspect.vs),
	.HBlank(video_aspect.hb),
	.VBlank(video_aspect.vb),
`ifdef GNET_ZN2
	.RGB_in(rgb_dbg),
`else
	.RGB_in({video_aspect.red,video_aspect.green,video_aspect.blue}),
`endif

	.HSync_out(video_gamma.hs),
	.VSync_out(video_gamma.vs),
	.HBlank_out(video_gamma.hb),
	.VBlank_out(video_gamma.vb),
	.RGB_out({video_gamma.red,video_gamma.green,video_gamma.blue})
);
`endif



////////////////////////////  CODES  ///////////////////////////////////

// Code layout:
// {code flags,     32'b address, 32'b compare, 32'b replace}
//  127:96          95:64         63:32         31:0
// Integer values are in BIG endian byte order, so it up to the loader
// or generator of the code to re-arrange them correctly.
reg [127:0] gg_code;
reg gg_valid;
reg gg_reset;
reg code_download_1;
wire gg_active;
always_ff @(posedge clk_1x) begin

   gg_reset <= 0;
   code_download_1 <= code_download;
	if (code_download && ~code_download_1) begin
      gg_reset <= 1;
   end

   gg_valid <= 0;
	if (code_download & ioctl_wr) begin
		case (ioctl_addr[3:0])
			0:  gg_code[111:96]  <= ioctl_dout; // Flags Bottom Word
			2:  gg_code[127:112] <= ioctl_dout; // Flags Top Word
			4:  gg_code[79:64]   <= ioctl_dout; // Address Bottom Word
			6:  gg_code[95:80]   <= ioctl_dout; // Address Top Word
			8:  gg_code[47:32]   <= ioctl_dout; // Compare Bottom Word
			10: gg_code[63:48]   <= ioctl_dout; // Compare top Word
			12: gg_code[15:0]    <= ioctl_dout; // Replace Bottom Word
			14: begin
				gg_code[31:16]    <= ioctl_dout; // Replace Top Word
				gg_valid          <= 1;          // Clock it in
			end
		endcase
	end
end

wire clk8Snac;
wire clk9Snac;
wire oldClk8;
wire oldClk9;
wire selectedPort1Snac;
wire selectedPort2Snac;
wire oldselectedPort1;
wire oldselectedPort2;
wire [7:0]transmitValueSnac;
wire [7:0]receiveBufferSnac;
wire receiveValidSnac;
wire beginTransferSnac;
wire actionNextSnac;
wire actionNextPadSnac;
reg [7:0]Send;
reg [7:0]Receive;
wire Cmd;
wire Dat;
wire ack;
wire oldAck;
//wire ackSnac;
wire [15:0]ackTimer;
wire ackNone;
wire oneTime;
wire [3:0]bitCnt;
wire [8:0]byteCnt;
wire [8:0]bytesLeft;
wire [7:0]pad1ID;
wire [7:0]pad2ID;
wire [7:0]targetID;
wire irq10Snac;
wire csync;
wire MCtransfer;
wire PStransfer;
wire [7:0]PSdatalength;

reg USER_IN3_1;
reg USER_IN4_1;
reg USER_IN6_1;

reg USER_IN3_2;
reg USER_IN4_2;
reg USER_IN6_2;

reg USER_IN3_3;
reg USER_IN3_4;
reg ackglitch;

assign clk8Snac = bitCnt < 8 ? clk9Snac : 1'b1;

always @(posedge clk_1x)
begin

   USER_IN3_1 <= USER_IN[3];
   USER_IN4_1 <= USER_IN[4];
   USER_IN6_1 <= USER_IN[6];

   USER_IN3_2 <= USER_IN3_1;
   USER_IN4_2 <= USER_IN4_1;
   USER_IN6_2 <= USER_IN6_1;

   USER_IN3_3 <= USER_IN3_2;//glitch filter for ack
   USER_IN3_4 <= USER_IN3_3;
   ackglitch  <= ~USER_IN3_1 && ~USER_IN3_2 && ~USER_IN3_3 && ~USER_IN3_4 ? 1'b0 : 1'b1;

	if (snacPort1 || snacPort2) begin
		USER_OUT[0] <= ~selectedPort2Snac;
		USER_OUT[1] <= ~selectedPort1Snac;
		USER_OUT[2] <= Cmd;
		USER_OUT[3] <= 1'b1; //ACK
		USER_OUT[4] <= 1'b1; //DAT
		USER_OUT[5] <= oldClk8;
		ack         <= ~ackglitch ? USER_IN3_2 : 1'b1;
		Dat         <= USER_IN4_2;

		if ((pad1ID == 8'h63 || pad2ID == 8'h63) && (pad1ID != 8'h31 || pad2ID != 8'h31)) begin //quirk for guncon, irq is N/C in guncon. so using irq line and outputting csync on snac for g-con. only if justifier isn't connected
			USER_OUT[6] <= ~csync;
			irq10Snac   <= 1'b0;
			csync       <= VGA_HS ^ VGA_VS;//real csync shifts HSync during VSync, should be close enough to work	with guncon
		end
		else begin
			USER_OUT[6] <= 1'b1;
			irq10Snac   <= ~USER_IN6_2;
		end
	end
	else begin
		USER_OUT  <= '1;
		irq10Snac <= 1'b0;
		ack       <= 1'b1;
		Dat       <= 1'b1;
	end

	oldselectedPort1 <= selectedPort1Snac;
	oldselectedPort2 <= selectedPort2Snac;

	if ((~oldselectedPort1 && selectedPort1Snac) || (~oldselectedPort2 && selectedPort2Snac)) begin
		byteCnt    <= 9'd0;
		bytesLeft  <= 9'd0;
		MCtransfer <= 1'b0;
	end

	if (beginTransferSnac) begin
		bitCnt  <= 4'd0;
		byteCnt <= byteCnt + 9'd1 ;
	end

	oldClk8 <= clk8Snac;
	oldClk9 <= clk9Snac;

	if (oldClk9 && ~clk9Snac) begin	//send on falling edge
		if (bitCnt < 8) begin
			if (bitCnt==0) begin
				Cmd  <= transmitValueSnac[0];
				Send <= {1'b1, transmitValueSnac[7:1]};
			end
			else begin
				Cmd  <= Send[0];
				Send <= {1'b1, Send[7:1]};
			end
		end
		else begin
			Cmd  <= 1'b1;
			Send <= Send;
		end
	end

	if(~oldClk8 && clk8Snac) begin //receive on rising edge
		Receive <= { Dat, Receive[7:1]};
		bitCnt <= bitCnt + 1'b1;
		if(bitCnt == 4'd7) begin//check for ack
			oneTime <= 1'b1;
			if (MCtransfer) ackTimer <= 16'd60000;//very late ack after 7th byte. around 56000 cycles (1.7ms) with a sony MC. 3rd party MCs don't seem to do this
			else begin
				if (byteCnt == bytesLeft + 3) ackTimer <= 16'd400;//only wait around 150 on last byte
				else ackTimer <= 16'd1800;//1st byte of multitap(1375) cycles to ack,digital(460),analog(350-400),ds2(250-400),mouse(120),guncon(270)
			end
		end
	end

	if (ackTimer > 0) begin
		ackTimer <= ackTimer - 16'd1;
	end

	oldAck <= ack;
	if(oldAck && ~ack) begin //ack received
		actionNextPadSnac <= 1'b1;
		ackTimer <= 16'd173;//16'd255;//a delay between ack and next action. too small might cause a hang. was using acktimer 1-255
	end
	else if(ackTimer == 1) begin //wait over
		actionNextPadSnac <= 1'b1;
		oneTime <= 1'b0;
	end
	else if (ackTimer == 16'd258) begin //no ack
		ackNone <= 1'b1;
		actionNextPadSnac <= 1'b1;
	end
	else if (ackTimer == 16'd256) begin //reset if no ack
		oneTime <= 1'b0;
		ackTimer <= 16'd0;
	end
	else begin
		actionNextPadSnac <= 1'b0;
		ackNone <= 1'b0;
	end

	if (actionNextPadSnac && ((snacPort1 && selectedPort1Snac) || (snacPort2 && selectedPort2Snac))) begin //logic for joypad.vhd
		if (oneTime) begin
			if (ackNone) begin
				if (byteCnt < (bytesLeft + 4)) begin // no ack on last byte of transfer
					receiveBufferSnac <= Receive;
					receiveValidSnac <= 1'b1;
					actionNextSnac <= 1'b1;
				end
				else
					actionNextSnac <= 1'b1;
				end
			else begin
				if (byteCnt < (bytesLeft + 4)) begin
					receiveBufferSnac <= Receive;
					receiveValidSnac <= 1'b1;
					//ackSnac <= 1'b1;
				end
				actionNextSnac <= 1'b1;
			end
		end
		else begin
			actionNextSnac <= 1'b1;
		end
	end
	else begin
		receiveBufferSnac <= 8'd0;
		receiveValidSnac <= 1'b0;
		actionNextSnac <= 1'b0;
		//ackSnac <= 1'b0;
	end

	if (receiveValidSnac) begin
		if (byteCnt == 1) begin
			targetID <= transmitValueSnac;
		end
		if (byteCnt == 2) begin
			if (targetID == 8'h81 || targetID == 8'h82 || targetID == 8'h83 || targetID == 8'h84) begin 	//memcard quirks
				MCtransfer <= 1'b1;
				if (transmitValueSnac == 8'h52) bytesLeft <= 9'd137;//read
				if (transmitValueSnac == 8'h57) bytesLeft <= 9'd135;//write
				if (transmitValueSnac == 8'h53) bytesLeft <= 9'd7;//ID Cmd
				//pocketstation
				if (transmitValueSnac == 8'h50) bytesLeft <= 9'd0;//Change a FUNC 03h related value
				if (transmitValueSnac == 8'h58) bytesLeft <= 9'd2;//Get an ID or Version value
				if (transmitValueSnac == 8'h59) bytesLeft <= 9'd6;//Prepare File Execution with Dir_index, and Parameter
				if (transmitValueSnac == 8'h5A) bytesLeft <= 9'd18;//Get Dir_index, ComFlags, F_SN, Date, and Time
				if (transmitValueSnac == 8'h5D) bytesLeft <= 9'd3;//Execute Custom Download Notification
				if (transmitValueSnac == 8'h5E) bytesLeft <= 9'd3;//Get-and-Send ComFlags.bit1,3,2
				if (transmitValueSnac == 8'h5F) bytesLeft <= 9'd1;//Get-and-Send ComFlags.bit0
				if (transmitValueSnac == 8'h5B) begin//Execute Function and transfer data from Pocketstation to PSX--variable length
					bytesLeft <= 9'd3;
					PStransfer <= 1'b1;
				end
				if (transmitValueSnac == 8'h5C) begin//Execute Function and transfer data from PSX to Pocketstation--variable length
					bytesLeft <= 9'd3;
					PStransfer <= 1'b1;
				end
			end
			else begin //joypad quirks
				MCtransfer <= 1'b0;
				if (selectedPort1Snac) pad1ID <= Receive;
				if (selectedPort2Snac) pad2ID <= Receive;

				if (Receive == 8'h80) bytesLeft <= 9'd32; //for multitap
				else bytesLeft <= {5'd0, (Receive[3:0] + Receive[3:0])};
			end
		end
		if (byteCnt == 4 && PStransfer == 1) begin //for pocketstation
			bytesLeft <= bytesLeft + Receive;
			PSdatalength <=  Receive;
		end
		if ((byteCnt == PSdatalength + 5) && PStransfer == 1) begin
			bytesLeft <= bytesLeft + Receive;
			PStransfer <= 1'b0;
		end
	end
end

endmodule
