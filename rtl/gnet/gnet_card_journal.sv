// PC card hunk journal for the G-NET NVRAM save (issue #9,
// docs/i9_nvram.md section 6). Built only with GNET_CARD_JOURNAL.
//
// Copyright (C) 2026 Lee Foot
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation; either version 2 of the License, or (at your option)
// any later version. This program is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
// Public License for more details.
//
// Games such as Psyvariar keep their settings on the PC card (ATA WRITE
// SECTORS), which the core holds in DDR3 and reloads from the zip on every
// load. This module keeps a list of the 4 KB card hunks the game has
// written (up to SLOTS) and carries them in the MRA's index 6 NVRAM file
// after the EEPROM:
//
//   byte 0       2,048    EEPROM (as without the journal)
//   byte 2048    512      directory: SLOTS entries of 8 bytes, 47h 4Eh 43h
//                         4Ah ("GNCJ"), hunk (16-bit LE), hunk XOR FFFFh;
//                         entries 0 to count-1 are used, the rest are 0
//   byte 2560    1,536    0
//   byte 4096    SLOTS x 4,096  slot k = card bytes hunk(k) x 4096 onwards
//   byte 266240  2,048    EEPROM again (mirror, for RBFs without this module,
//                         which load index 6 with ioctl_addr[10:0])
//   total 268,288 bytes (MRA <nvram index="6" size="268288"/>)
//
// Load (index 6 download, core held in reset by gnet_download): words below
// 2048 go to the EEPROM loader (ee_sel); directory entries are checked in
// order and the leading valid ones become the list; slot words of listed
// hunks go to the card loader path (slot_wr, the index 5 path into
// zn2_cardmem). Everything else is ignored. An index 5 download (a new card
// image) empties the list.
//
// Save (index 6 upload): ioctl_din is a registered copy of the word at
// ioctl_addr; ul_wait (to hps_io's ioctl_wait, combinational) is high while
// that copy is not for the current ioctl_addr, so Main's next word waits
// (sys_top holds the acknowledge while io_wait is high). Slot data is read
// from DDR3 one 64-bit line at a time through zn2_cardmem's journal read
// client (crd_*). The list length and overflow flag are taken at the start
// of the upload; the list only grows, so the file stays consistent if the
// game writes during the upload. With more than SLOTS hunks written the
// directory is saved empty (the card image goes back to the zip's on the
// next load, which is consistent; a partial set would not be).
//
// Dirty events: zn2_board (on its clock, clk_cpu in CPU_CLK_SPLIT builds)
// toggles cdc_tx_cjtog and holds cdc_tx_cjhunk for every written sector. Here the
// toggle passes two synchroniser stages (cdc_rx_s1, cdc_rx_s2) and the hunk
// is captured into cdc_rx_hold one clock later (rtl/gnet/cdc/cdc.sdc rules 1
// and 1b). gnet_ata writes at most one sector per 100 us (T_WRITE), so the
// hunk is stable long before the capture and an event is handled (list
// search, at most SLOTS + 1 clocks) long before the next one. Every event
// sets card_dirty; req_take (the PSX.sv upload request) clears it, and an
// event in the same clock wins, so a write during an upload asks again at
// the next OSD open.

module gnet_card_journal #(
    parameter int SLOTS = 64          // fixed by the file layout above
) (
    input  logic        clk,          // clk_1x, hps_io's clk_sys

    // hps_io file transfer
    input  logic        ioctl_download,
    input  logic        ioctl_upload,
    input  logic  [7:0] ioctl_index,
    input  logic [26:0] ioctl_addr,
    input  logic [15:0] ioctl_dout,
    input  logic        ioctl_wr,
    output logic [15:0] ioctl_din,
    output logic        ul_wait,

    // EEPROM copy (zn2_io nv_q: registered read of ioctl_addr[10:1])
    input  logic [15:0] nv_din,

    // index 6 download routing (combinational, valid with ioctl_wr)
    output logic        ee_sel,       // word for the EEPROM loader
    output logic        slot_wr,      // word for the card loader path
    output logic [25:0] slot_addr,    // card byte address

    // zn2_cardmem journal read client (request held until ack)
    output logic        crd_req,
    output logic [22:0] crd_line,    // card byte address 25:3
    input  logic        crd_ack,
    input  logic [63:0] crd_data,

    // dirty events from zn2_board (its clock)
    input  logic        ev_tog,
    input  logic [13:0] ev_hunk,

    input  logic        req_take,     // pulse: the upload request was raised
    output logic        card_dirty,
    output logic  [6:0] count,
    output logic        overflow
);
    // registers behind the outputs, with their power-up values
    logic        rd_req = 1'b0;
    logic [22:0] rd_line = '0;
    logic        dirty = 1'b0;
    logic  [6:0] cnt = '0;
    logic        ovf = 1'b0;
    assign crd_req    = rd_req;
    assign crd_line   = rd_line;
    assign card_dirty = dirty;
    assign count      = cnt;
    assign overflow   = ovf;

    localparam int A_DIR   = 2048;
    localparam int A_PAD   = A_DIR + 8 * SLOTS;          // 2560
    localparam int A_SLOT  = 4096;
    localparam int A_MIR   = A_SLOT + 4096 * SLOTS;      // 266240
    localparam int A_END   = A_MIR + 2048;               // 268288

    logic [13:0] list [SLOTS];

    // ------------------------------------------------------------ download
    wire dl5 = ioctl_download & (ioctl_index == 8'd5);
    wire dl6 = ioctl_download & (ioctl_index == 8'd6);
    logic dl5_q = 1'b0, dl6_q = 1'b0;

    // slot of an address: ioctl_addr[26:12] = slot + 1 for slots 0 to SLOTS-1
    wire [14:0] d_page  = ioctl_addr[26:12];
    wire        d_inslot = (d_page >= 15'd1) && (d_page <= 15'(SLOTS));
    wire  [5:0] d_slot  = 6'(d_page - 15'd1);
    wire        d_indir = (ioctl_addr >= 27'(A_DIR)) && (ioctl_addr < 27'(A_PAD));
    wire  [5:0] d_entry = ioctl_addr[8:3];

    assign ee_sel    = (ioctl_addr < 27'd2048);
    assign slot_wr   = ioctl_wr & dl6 & d_inslot & ({1'b0, d_slot} < cnt);
    assign slot_addr = {list[d_slot], ioctl_addr[11:0]};

    logic [15:0] dw0, dw1, dw2;          // directory entry words 0 to 2

    // ------------------------------------------------------------ events
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic cdc_rx_s1 = 1'b0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic cdc_rx_s2 = 1'b0;
    logic        ev_q = 1'b0;
    logic [13:0] cdc_rx_hold = '0;
    logic        ev_pend = 1'b0;         // event captured, search not started
    logic        s_busy = 1'b0;
    logic  [6:0] s_i = '0;
    logic [13:0] s_h = '0;               // hunk being searched
    wire         ev_seen = cdc_rx_s2 ^ ev_q;

    // ------------------------------------------------------------ upload
    wire        u_act = ioctl_upload & (ioctl_index == 8'd6);
    logic       u_act_q = 1'b0;
    logic [6:0] u_count = '0;
    logic       u_over = 1'b0;
    logic [26:0] a1 = '0;                // ioctl_addr one clock ago (nv_din's address)
    logic [26:0] q_addr = '0;
    logic        q_valid = 1'b0;
    logic [15:0] q = '0;
    logic [63:0] line = '0;
    logic [22:0] line_tag = '0;
    logic        line_ok = 1'b0;

    wire [14:0] u_page   = a1[26:12];
    wire        u_inslot = (u_page >= 15'd1) && (u_page <= 15'(SLOTS));
    wire  [5:0] u_slot   = 6'(u_page - 15'd1);
    wire        u_indir  = (a1 >= 27'(A_DIR)) && (a1 < 27'(A_PAD));
    wire  [5:0] u_entry  = a1[8:3];
    wire        u_inee   = (a1 < 27'd2048) || ((a1 >= 27'(A_MIR)) && (a1 < 27'(A_END)));
    wire [13:0] u_dhunk  = list[u_entry];
    wire [13:0] u_shunk  = list[u_slot];
    wire        u_dvalid = !u_over && ({1'b0, u_entry} < u_count);
    wire        u_svalid = !u_over && ({1'b0, u_slot} < u_count);
    wire [22:0] u_need   = {u_shunk, a1[11:3]};

    logic [15:0] src_data;
    logic        src_ready;
    always_comb begin
        src_data  = 16'h0000;
        src_ready = 1'b1;
        if (u_inee) src_data = nv_din;
        else if (u_indir) begin
            if (u_dvalid)
                case (a1[2:1])
                    2'd0: src_data = 16'h4E47;
                    2'd1: src_data = 16'h4A43;
                    2'd2: src_data = {2'b00, u_dhunk};
                    2'd3: src_data = ~{2'b00, u_dhunk};
                endcase
        end else if (u_inslot && u_svalid) begin
            src_ready = line_ok && (line_tag == u_need);
            case (a1[2:1])
                2'd0: src_data = line[15:0];
                2'd1: src_data = line[31:16];
                2'd2: src_data = line[47:32];
                2'd3: src_data = line[63:48];
            endcase
        end
    end

    assign ioctl_din = q;
    assign ul_wait   = u_act & ~(q_valid & (q_addr == ioctl_addr));

    // ------------------------------------------------------------ state
    always_ff @(posedge clk) begin
        dl5_q   <= dl5;
        dl6_q   <= dl6;
        u_act_q <= u_act;
        a1      <= ioctl_addr;

        // event capture: toggle through two stages, hunk one clock later
        cdc_rx_s1 <= ev_tog;
        cdc_rx_s2 <= cdc_rx_s1;
        ev_q      <= cdc_rx_s2;
        if (ev_seen) begin
            cdc_rx_hold <= ev_hunk;
            ev_pend     <= 1'b1;
            dirty       <= 1'b1;
        end else if (req_take) begin
            dirty       <= 1'b0;
        end

        // list search: one entry per clock; append if absent
        if (s_busy) begin
            if (s_i == cnt) begin
                if (cnt < 7'(SLOTS)) begin
                    list[cnt[5:0]] <= s_h;
                    cnt <= cnt + 7'd1;
                end else begin
                    ovf <= 1'b1;
                end
                s_busy <= 1'b0;
            end else if (list[s_i[5:0]] == s_h) begin
                s_busy <= 1'b0;
            end else begin
                s_i <= s_i + 7'd1;
            end
        end else if (ev_pend && !dl6 && !ev_seen) begin
            ev_pend <= 1'b0;
            s_busy  <= 1'b1;
            s_i     <= 7'd0;
            s_h     <= cdc_rx_hold;
        end

        // index 6 download: directory entries in order
        if (ioctl_wr && dl6 && d_indir) begin
            case (ioctl_addr[2:1])
                2'd0: dw0 <= ioctl_dout;
                2'd1: dw1 <= ioctl_dout;
                2'd2: dw2 <= ioctl_dout;
                2'd3: if (dw0 == 16'h4E47 && dw1 == 16'h4A43 && dw2[15:14] == 2'b00 &&
                          ioctl_dout == ~dw2 && {1'b0, d_entry} == cnt && cnt < 7'(SLOTS)) begin
                          list[d_entry] <= dw2[13:0];
                          cnt <= cnt + 7'd1;
                      end
            endcase
        end

        // a new card image or a new NVRAM file empties the list
        if ((dl5 && !dl5_q) || (dl6 && !dl6_q)) begin
            cnt    <= 7'd0;
            ovf <= 1'b0;
            s_busy   <= 1'b0;
            ev_pend  <= 1'b0;
            if (dl5) dirty <= 1'b0;
        end

        // upload: snapshot, registered word for the current address
        if (u_act && !u_act_q) begin
            u_count <= cnt;
            u_over  <= ovf;
            line_ok <= 1'b0;
        end
        if (u_act && u_act_q && src_ready) begin
            q       <= src_data;
            q_addr  <= a1;
            q_valid <= 1'b1;
        end else if (!u_act) begin
            q_valid <= 1'b0;
        end

        // DDR3 line read for the slot word at a1
        if (rd_req) begin
            if (crd_ack) begin
                rd_req  <= 1'b0;
                line     <= crd_data;
                line_tag <= rd_line;
                line_ok  <= 1'b1;
            end
        end else if (u_act && u_act_q && u_inslot && u_svalid && !(line_ok && line_tag == u_need)) begin
            rd_req  <= 1'b1;
            rd_line <= u_need;
        end
    end

endmodule
