//============================================================================
//  G-NET core: high score save (MAME hiscore.dat) through the index 6 NVRAM
//  Copyright (C) 2026 Lee Foot
//  SPDX-License-Identifier: GPL-2.0-or-later
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// Origin: written for this core around rtl/gnet/hiscore.v (JimmyStones and
//         alanswx, Hiscores_MiSTer, GPL-3.0-or-later; vendored with a clock
//         enable added). No other code copied.
// Evidence: MAME 0.288 plugins/hiscore/hiscore.dat 14697-14698 (spuzbobl,
//           the only G-NET set in it); MAME runs in docs/hiscore.md 1 (the
//           game keeps its table in main RAM only, not in the EEPROM or on
//           the card, and clears it about 12 s after a reset).
// Design: docs/hiscore.md. Bench: sim/hiscore/run.sh.
//
// What it adds to the core, all on clk_1x (the hps_io clock):
//
// 1. Byte bridge. hps_io runs 16 bits wide (WIDE=1) and hiscore.v takes
//    bytes. A config download (CFG_INDEX, the MRA's hiscore.dat block) and
//    the dump part of the NVRAM download are passed on one byte per clock,
//    low byte first; uploads of the dump part are read from hiscore.v one
//    byte at a time and handed to hps_io as words (io_wait holds Main until
//    the word is there).
//
// 2. One NVRAM file. Main_MiSTer keeps one <nvram> per MRA, already the
//    EEPROM on index 6, so the dump shares that file:
//      0x000-0x7FF  EEPROM (PSX.sv's loader and zn2_io's copy, as before)
//      0x800-0x9FF  zero (the card journal's directory, issue #9 branch)
//      0xA00-0xA03  "GNHS" when the dump holds a table, else zero
//      0xA04-0xC03  hiscore dump (up to 512 bytes, hiscore.dat order)
//      0xC04-0xFFF  zero
//      0x1000-...   EEPROM again (older RBFs load the file wrapped on 2 KB)
//    A load takes the dump only after the marker: a 2 KB file from an older
//    release arrives zero padded and leaves hiscore.v's dump as it was. The
//    marker comes first so that the dump bytes can be dropped before they
//    reach hiscore.v. It is written when the dump holds a table: one loaded
//    with a marker, or a snapshot (taken only from a fresh table, 4 below).
//    ee_sel gives PSX.sv's EEPROM loader the first 2 KB only.
//
// 3. Game RAM port. Main RAM is in SDRAM; reads and writes go out on channel
//    3 of the SDRAM controller (m_* into PSX.sv's ch3 crossing), one 32-bit
//    word at a time, and hiscore.v is held (ce low) until the word is back.
//    A one-word cache serves the bytes of a word while hiscore.v keeps
//    reading (cleared whenever it stops). Writes are single bytes with a
//    byte enable. Writes, and reads while the OSD is open (the save
//    snapshot), wait for the core to be paused (psx_top isPaused); pause_req
//    asks for it. The start and end checks hiscore.v polls every CHECK_WAIT
//    read with the core running: they read two bytes, and pausing every
//    2 ms through the game's boot would cost CPU time for nothing.
//
// 4. Fresh table after a reset. The core's reset zero fill covers the
//    first 2 MB of main RAM only (cpu_reset_fill), so after an OSD reset or
//    a reload the SDRAM still holds the previous table at 0x28BF08 with
//    valid start and end bytes; spuzbobl clears it about 12 s after a reset
//    and writes its defaults 2.6 s later (MAME watchpoints). A restore into
//    the old table would be overwritten by the defaults, and a snapshot of
//    RAM before the game's own table is there would save junk. So after
//    each reset the table counts as fresh only once entry 0's start byte
//    has been seen not matching (cleared) and then start and end matching
//    again. Until it has been seen cleared, entry 0's start byte reads as a
//    mismatch to hiscore.v's restore checks; until it is fresh, hiscore.v
//    does not see the OSD open (no snapshot, no save). The wrapper polls the
//    two bytes every 65,536 clocks (1.9 ms) until the table is fresh; a
//    restore also makes it fresh (its checks passed the same way). A game
//    that never clears its table is never restored and never saved, and its
//    file is never overwritten.
//
// 5. Save request. hiscore.v asks for a save after its snapshot when the
//    table changed (autosave on); upload_req passes that on as one clock,
//    PSX.sv ORs it into the EEPROM's request. An upload that reaches the
//    marker or the dump while a snapshot is still running is held (io_wait)
//    until it ends; a request from that snapshot is then not passed on (the
//    upload in progress carries it).
//    Main_MiSTer checks for a request once as its menu opens; a request that
//    comes later is kept by hps_io and saved at the next menu open.
//
// Format limits of the wrapper: config entries with a 2-byte length
// (CFG_LENGTHWIDTH 2, as the MRA block in docs/hiscore.md), at most 4
// entries, a dump of at most 512 bytes, game RAM below 8 MB.

module gnet_hiscore #(
	parameter [7:0]  CFG_INDEX = 8'd8,      // MRA <rom index="8">: hiscore.dat config
	parameter [7:0]  NV_INDEX  = 8'd6,      // MRA <nvram index="6">
	parameter integer RAM_AW   = 23,        // game RAM byte address width (SDRAM byte address = RAM address)
	parameter integer POLL_W   = 16         // fresh-table poll every 2**POLL_W clocks
)
(
	input             clk,                  // clk_1x
	input             reset,                // core reset (PSX.sv reset)
	input             user_paused,          // PSX.sv paused (OSD or pause button): hiscore.v's timers stop
	input             core_paused,          // psx_top isPaused, synchronised to clk
	input             OSD_STATUS,
	input             ch3_free,             // no download or flash copy uses channel 3

	input             ioctl_download,
	input             ioctl_upload,
	input             ioctl_wr,
	input       [7:0] ioctl_index,
	input      [26:0] ioctl_addr,
	input      [15:0] ioctl_dout,
	output            ul_sel,               // upload word ul_din replaces the EEPROM copy's
	output reg [15:0] ul_din = 16'd0,
	output            io_wait,              // ORed into hps_io ioctl_wait
	output            ee_sel,               // index 6 word below 2 KB: the EEPROM's
	output reg        upload_req = 1'b0,    // one clock: ask Main to save index 6
	output            pause_req,            // ORed into psx_top pause
	output            configured,           // a config was loaded (the MRA has the block)

	output reg        m_req = 1'b0,         // channel 3 request, one clock
	output reg        m_rnw = 1'b1,
	output reg [26:0] m_addr = 27'd0,
	output reg [31:0] m_wdata = 32'd0,
	output reg  [3:0] m_be = 4'd0,
	input             m_done,               // one clock, m_rdata valid (reads)
	input      [31:0] m_rdata
);

localparam [26:0] MRK_OFS  = 27'h0A00;      // marker
localparam [26:0] DUMP_OFS = 27'h0A04;
localparam [26:0] AREA_LO  = 27'h0800;
localparam [26:0] AREA_HI  = 27'h1000;
localparam [15:0] MRK_W0   = 16'h4E47;      // "GN" (low byte first)
localparam [15:0] MRK_W1   = 16'h5348;      // "HS"
localparam integer DUMP_W  = 9;             // dump up to 512 bytes (0xA04 to 0xC03)

// ---------------------------------------------------------------- hiscore.v
reg         h_dl = 1'b0, h_ul = 1'b0, h_wr = 1'b0;
reg   [7:0] h_idx = 8'hFF;
reg   [8:0] h_addr = 9'd0;              // byte address: config (up to 512 bytes) or dump
reg   [7:0] h_dout = 8'd0;
wire  [7:0] h_din;
wire        h_req, h_pause;
wire        ce;
wire [RAM_AW-1:0] r_addr;
wire  [7:0] r_wd, r_rdata;
wire        r_wr, r_rd, r_iw;
reg         h_reset_x = 1'b0;
reg   [3:0] rst_stretch = 4'd0;
reg         fresh = 1'b0;             // the game's own table is in RAM (4 in the header)
wire        h_osd = OSD_STATUS & fresh;

hiscore #(
	.HS_ADDRESSWIDTH(RAM_AW),
	.HS_SCOREWIDTH(DUMP_W),
	.HS_CONFIGINDEX(CFG_INDEX),
	.HS_DUMPINDEX(NV_INDEX),
	.CFG_ADDRESSWIDTH(2),
	.CFG_LENGTHWIDTH(2),
	.HS_MASKBITS(8)
) hs (
	.clk(clk),
	.ce(ce),
	.paused(user_paused),
	.reset(reset | h_reset_x),
	.autosave(1'b1),
	.ioctl_upload(h_ul),
	.ioctl_upload_req(h_req),
	.ioctl_download(h_dl),
	.ioctl_wr(h_wr),
	.ioctl_addr({16'd0, h_addr}),
	.ioctl_index(h_idx),
	.OSD_STATUS(h_osd),
	.data_from_hps(h_dout),
	.data_from_ram(r_rdata),
	.ram_address(r_addr),
	.data_to_hps(h_din),
	.data_to_ram(r_wd),
	.ram_write(r_wr),
	.ram_intent_read(r_rd),
	.ram_intent_write(r_iw),
	.pause_cpu(h_pause),
	.configured(configured)
);

// ---------------------------------------------------------------- entry 0 of the config
// Header 16 bytes (byte 15 = change mask length), then the mask, then 8-byte
// entries: address (4), length (2), start, end.
reg   [7:0] cfg_cm = 8'd0;
reg  [23:0] e0_addr = 24'd0;
reg  [15:0] e0_len = 16'd0;
reg   [7:0] e0_start = 8'd0, e0_end = 8'd0;
wire  [8:0] e0_base = 9'd16 + {1'b0, cfg_cm};
wire        e0_ok = (e0_len != 16'd0) && (e0_len <= (16'd1 << DUMP_W));
wire [23:0] e0_eaddr = e0_addr + {8'd0, e0_len} - 24'd1;   // entry 0's end byte

// ---------------------------------------------------------------- byte bridge
wire dl_cfg = ioctl_download & (ioctl_index == CFG_INDEX);
wire dl_nv  = ioctl_download & (ioctl_index == NV_INDEX);
wire ul_nv  = ioctl_upload & (ioctl_index == NV_INDEX);
wire [11:0] dump_rel = ioctl_addr[11:0] - DUMP_OFS[11:0];
wire in_dump = (ioctl_addr[26:12] == 15'd0) && (dump_rel < 12'd512);   // 0xA04 to 0xC03
wire in_mrk  = (ioctl_addr[26:2] == MRK_OFS[26:2]);                   // 0xA00 to 0xA03
wire  [8:0] dump_off = dump_rel[8:0];

assign ee_sel = (ioctl_addr < AREA_LO);
assign ul_sel = ul_nv & (ioctl_addr >= AREA_LO) & (ioctl_addr < AREA_HI);

// download: a word becomes two byte writes on the next two clocks
reg         b_pend = 1'b0, b_hi = 1'b0;
reg  [15:0] b_word = 16'd0;
reg   [8:0] b_addr = 9'd0;
reg   [7:0] b_idx = 8'hFF;
wire  [8:0] b_at = {b_addr[8:1], b_hi};
wire  [8:0] b_rel = b_at - e0_base;      // byte within entry 0 of the config (below it: 241 or more)
wire  [7:0] b_byte = b_hi ? b_word[15:8] : b_word[7:0];
reg         t0_ok = 1'b0, t1_ok = 1'b0; // index 6 load: marker words
wire        nv_ok = t0_ok & t1_ok & configured & e0_ok;
reg         dump_loaded = 1'b0;       // the last index 6 load held a dump (marker)
reg         dump_valid = 1'b0;        // hiscore.v's dump holds a table: write the marker
// upload
typedef enum logic [1:0] {U_IDLE, U_LO, U_HI} ustate_t;
ustate_t    us = U_IDLE;
reg   [1:0] ucnt = 2'd0;
reg   [7:0] u_lo = 8'd0;
reg  [11:1] ul_tag = 11'd0;             // word in ul_din (ul_sel limits the address to 0x800 to 0xFFF)
reg         ul_ok = 1'b0;
reg         ex_busy = 1'b0;           // a snapshot may be running (OSD opened on a fresh table)
reg  [10:0] ex_quiet = 11'd0;
reg         ul_past = 1'b0;           // this upload has gone past the dump
reg         osd_q = 1'b0, h_req_q = 1'b0, dl_q = 1'b0;

wire ul_hit = ul_ok & (ul_tag == ioctl_addr[11:1]);
assign io_wait = b_pend | (ul_sel & ~ul_hit);

always @(posedge clk) begin
	h_wr       <= 1'b0;
	upload_req <= 1'b0;
	osd_q      <= h_osd;
	h_req_q    <= h_req;
	dl_q       <= dl_nv;
	h_dl       <= ioctl_download;

	// hiscore.v's save request (autosave), one clock on its rising edge;
	// it comes only after a snapshot, and snapshots are taken only from a
	// fresh table, so its dump then holds a table. An upload that has not
	// yet passed the dump carries it (it waits for the snapshot window).
	if (h_req & ~h_req_q) begin
		if (~ul_nv | ul_past) upload_req <= 1'b1;
		dump_valid <= 1'b1;
	end
	ul_past <= ul_nv & (ul_past | (ioctl_addr >= DUMP_OFS + 27'd512));

	// snapshot window: from the OSD opening (as hiscore.v sees it) until
	// hiscore.v has kept its pause low for 1,024 clocks (its snapshot copies
	// at most 512 bytes after the pause ends, then asks for the save)
	if (h_osd & ~osd_q) begin
		ex_busy  <= 1'b1;
		ex_quiet <= 11'd0;
	end else if (ex_busy & ce) begin
		if (h_pause) ex_quiet <= 11'd0;
		else if (ex_quiet == 11'd1024) ex_busy <= 1'b0;
		else ex_quiet <= ex_quiet + 1'd1;
	end

	// hold hiscore.v's reset a few clocks past the end of an index 6 load,
	// so it sees the reset end after it has taken the dump
	if (rst_stretch != 4'd0) rst_stretch <= rst_stretch - 1'd1;
	h_reset_x <= (rst_stretch != 4'd0);

	// ------------------------------------------------------------ downloads
	// the dump's words only after the marker checked out
	if (ioctl_download & ioctl_wr & (dl_cfg | (dl_nv & in_dump & nv_ok))) begin
		b_pend <= 1'b1;
		b_hi   <= 1'b0;
		b_word <= ioctl_dout;
		b_addr <= dl_cfg ? ioctl_addr[8:0] : dump_off;
		b_idx  <= ioctl_index;
	end else if (b_pend) begin
		h_idx  <= b_idx;
		h_addr <= b_at;
		h_dout <= b_byte;
		h_wr   <= 1'b1;
		b_hi   <= 1'b1;
		if (b_hi) b_pend <= 1'b0;
		// entry 0 of the config, from the byte stream
		if (b_idx == CFG_INDEX) begin
			if (b_at == 9'd15) cfg_cm <= b_byte;
			if (b_rel == 9'd1) e0_addr[23:16] <= b_byte;
			if (b_rel == 9'd2) e0_addr[15:8]  <= b_byte;
			if (b_rel == 9'd3) e0_addr[7:0]   <= b_byte;
			if (b_rel == 9'd4) e0_len[15:8]   <= b_byte;
			if (b_rel == 9'd5) e0_len[7:0]    <= b_byte;
			if (b_rel == 9'd6) e0_start       <= b_byte;
			if (b_rel == 9'd7) e0_end         <= b_byte;
		end
	end else if (us == U_IDLE) begin
		// between bytes: the config keeps its index (hiscore.v takes the
		// config at the end of the download); the dump index is shown only
		// once the marker has checked out, so the end of the download marks
		// a dump as loaded only then (meanwhile hiscore.v rewrites the last
		// byte pair it was given; every dump byte follows and overwrites)
		h_idx <= dl_cfg ? CFG_INDEX : (dl_nv & nv_ok) ? NV_INDEX : 8'hFF;
	end
	if (dl_nv & ioctl_wr) begin
		if (ioctl_addr == MRK_OFS)         t0_ok <= (ioctl_dout == MRK_W0);
		if (ioctl_addr == MRK_OFS + 27'd2) t1_ok <= (ioctl_dout == MRK_W1);
	end
	if (dl_nv & ~dl_q) begin
		t0_ok <= 1'b0;
		t1_ok <= 1'b0;
	end
	if (~dl_nv & dl_q) begin
		dump_loaded <= nv_ok;
		dump_valid  <= nv_ok;
		rst_stretch <= 4'd15;
	end

	// ------------------------------------------------------------ uploads
	if (~ul_nv) ul_ok <= 1'b0;
	case (us)
		U_IDLE:
			if (ul_sel & ~ul_hit & ~b_pend) begin
				if (in_dump) begin
					// read two bytes of hiscore.v's dump (data_to_hps is two
					// clocks behind the address); not during a snapshot or
					// while hiscore.v is held for a RAM access
					if (~ex_busy & ce) begin
						h_ul   <= 1'b1;
						h_idx  <= NV_INDEX;
						h_addr <= dump_off;
						ucnt   <= 2'd3;
						us     <= U_LO;
					end
				end else if (in_mrk) begin
					// the marker also waits for the snapshot (dump_valid)
					if (~ex_busy) begin
						ul_din <= (dump_valid & configured) ? (ioctl_addr[1] ? MRK_W1 : MRK_W0) : 16'd0;
						ul_tag <= ioctl_addr[11:1];
						ul_ok  <= 1'b1;
					end
				end else begin
					ul_din <= 16'd0;
					ul_tag <= ioctl_addr[11:1];
					ul_ok  <= 1'b1;
				end
			end
		U_LO:
			if (ucnt != 2'd0) ucnt <= ucnt - 1'd1;
			else begin
				u_lo   <= h_din;
				h_addr <= h_addr + 1'd1;
				ucnt   <= 2'd3;
				us     <= U_HI;
			end
		U_HI:
			if (ucnt != 2'd0) ucnt <= ucnt - 1'd1;
			else begin
				ul_din <= {h_din, u_lo};
				ul_tag <= ioctl_addr[11:1];
				ul_ok  <= 1'b1;
				h_ul   <= 1'b0;
				h_idx  <= 8'hFF;
				us     <= U_IDLE;
			end
		default: us <= U_IDLE;
	endcase
end

// ---------------------------------------------------------------- game RAM port
reg               c_valid = 1'b0;
reg  [RAM_AW-1:2] c_tag = '0;
reg        [31:0] c_data = 32'd0;
reg               w_done = 1'b0;
reg               m_busy = 1'b0;
reg               m_poll = 1'b0;         // the request in flight is the wrapper's own poll
reg               seen_clear = 1'b0;     // entry 0's start byte seen not matching since the reset
reg               restored = 1'b0;       // hiscore.v wrote the dump since the reset
reg  [POLL_W-1:0] poll_t = '0;
reg         [1:0] poll_step = 2'd0;      // 0 wait, 1 read the start byte, 2 read the end byte

wire c_hit   = c_valid & (c_tag == r_addr[RAM_AW-1:2]);
wire need_rd = r_rd & ~c_hit;
wire need_wr = r_wr & ~w_done;
// never hold hiscore.v during a download: it takes the config and the dump then
assign ce = ~(need_rd | need_wr) | ioctl_download;

wire acc_pause = r_iw | OSD_STATUS;
wire acc_ok    = ch3_free & ~ioctl_download & (~acc_pause | core_paused);
assign pause_req = h_pause & acc_pause;

wire [7:0] r_byte  = c_data[8*r_addr[1:0] +: 8];
wire       e0_here = (r_addr == e0_addr[RAM_AW-1:0]);
wire       falsify = dump_loaded & ~restored & ~seen_clear & e0_here;
assign r_rdata = falsify ? ~e0_start : r_byte;

wire       poll_on = configured & e0_ok & ~fresh & ~reset;
wire [RAM_AW-1:0] p_addr = (poll_step == 2'd2) ? e0_eaddr[RAM_AW-1:0] : e0_addr[RAM_AW-1:0];
wire [7:0] p_byte = m_rdata[8*p_addr[1:0] +: 8];

always @(posedge clk) begin
	m_req <= 1'b0;
	if (~(r_rd | r_wr | r_iw)) c_valid <= 1'b0;
	if (~r_wr) w_done <= 1'b0;

	// hiscore.v's own checks see the start byte too
	if (r_rd & c_hit & e0_here & (r_byte != e0_start)) seen_clear <= 1'b1;

	// poll timer
	if (poll_on & (poll_step == 2'd0)) begin
		poll_t <= poll_t + 1'd1;
		if (&poll_t) poll_step <= 2'd1;
	end

	if (~m_busy) begin
		if ((need_rd | need_wr) & acc_ok) begin
			m_req   <= 1'b1;
			m_busy  <= 1'b1;
			m_poll  <= 1'b0;
			m_rnw   <= ~need_wr;
			m_addr  <= {{(27-RAM_AW){1'b0}}, r_addr[RAM_AW-1:2], 2'b00};
			m_wdata <= {4{r_wd}};
			m_be    <= need_wr ? (4'b0001 << r_addr[1:0]) : 4'b1111;
		end else if (poll_on & (poll_step != 2'd0) & ~(r_rd | r_wr | r_iw) & ch3_free & ~ioctl_download) begin
			m_req   <= 1'b1;
			m_busy  <= 1'b1;
			m_poll  <= 1'b1;
			m_rnw   <= 1'b1;
			m_addr  <= {{(27-RAM_AW){1'b0}}, p_addr[RAM_AW-1:2], 2'b00};
			m_be    <= 4'b1111;
		end
	end else if (m_done) begin
		m_busy <= 1'b0;
		if (m_poll) begin
			// start byte: a mismatch is the clear; a match after the clear
			// goes on to the end byte; an end byte match makes it fresh
			if (poll_step == 2'd1) begin
				if (p_byte != e0_start) begin
					seen_clear <= 1'b1;
					poll_step  <= 2'd0;
				end else
					poll_step  <= seen_clear ? 2'd2 : 2'd0;
			end else if (poll_step == 2'd2) begin
				if (p_byte == e0_end) fresh <= 1'b1;
				poll_step <= 2'd0;
			end
		end else if (m_rnw) begin
			c_valid <= 1'b1;
			c_tag   <= m_addr[RAM_AW-1:2];
			c_data  <= m_rdata;
		end else begin
			// a restore write: hiscore.v's checks passed on the game's fresh
			// table (its start byte may differ from hiscore.dat's once the
			// restored scores are in, so the poll could not tell)
			w_done   <= 1'b1;
			restored <= 1'b1;
			fresh    <= 1'b1;
			if (c_valid & (c_tag == m_addr[RAM_AW-1:2]))
				for (int i = 0; i < 4; i++) if (m_be[i]) c_data[8*i +: 8] <= m_wdata[8*i +: 8];
		end
	end

	if (reset) begin
		seen_clear <= 1'b0;
		restored   <= 1'b0;
		fresh      <= 1'b0;
		poll_step  <= 2'd0;
		poll_t     <= '0;
	end
end

endmodule
