// Taito Type 1 and Type 2 ATA PC cards and the Taito CompactFlash card (G-NET
// game cards): attribute memory, card lock, ATA task file and the commands
// the games use.
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
// Evidence: CF+ and CompactFlash specification Rev 1.4 (task file, status,
// attribute memory); MAME 0.288 ataflash.cpp, atahle.cpp, atastorage.cpp for
// the Taito lock and every behaviour the specification leaves open.
//
// Per-game data comes in through the meta load port (byte address):
//   000h-1FFh IDENTIFY block (CHD metadata IDNT, returned verbatim as MAME)
//   200h-2FFh CIS (CHD metadata CIS, padded with FFh)
//   300h-304h unlock key (CHD metadata KEY); key_valid = a key was loaded
//   3F0h      card type: 02h = Taito Type 2 (MAME taito_pccard2), 03h = Taito
//             CompactFlash (MAME taito_cf), anything else = Type 1 (00h in
//             meta files made before the type byte)
// The card size is IDENTIFY words 60-61 (total LBA sectors, bytes 078h-07Bh);
// if those are zero, NUM_LBA.
//
// Attribute memory (16-bit word offsets, MAME read_reg/write_reg):
//   000h-0FFh CIS byte; 100h configuration option; 101h configuration and
//   status; 102h pin replacement (reset 002Eh); Type 1 only (not Type 2 or
//   CompactFlash): 201h lock status
//   (1 while locked), and writes to 280h-288h compare the low byte with key
//   byte n (bytes 5 to 8 compare with 0): a match clears lock bit n, a
//   mismatch sets it (MAME; whether a wrong key relocks a real card is open,
//   R5); write 07h ignored; other offsets (201h and 280h-288h on Type 2 and
//   CompactFlash) read FFFFh, writes ignored (MAME device_pccard_interface).
//
// Task file (byte offsets 0-7 command block, 8-15 control block; offsets
// above 15 read FFFFh). Access width follows each access (MAME's
// m_8bit_data_transfers hack: byte accesses move one byte of the sector
// buffer, 16-bit accesses two). While BSY every command block read except
// the data port returns status (MAME). Commands: 20h READ SECTORS, 30h WRITE
// SECTORS, ECh IDENTIFY DEVICE; any other command ends with ERR and ABRT
// (MAME also implements 90h, EFh, E7h and the multiple/DMA forms; the games
// never issue them). While locked every command ends with ERR, error 00h and
// DRDY clear (all three card types, MAME).
//
// Type 2 unlock (MAME 0.288 taito_pccard2_device): locked at power-on when a
// key is loaded. FEh (unlock 1): sector count 1, DRDY, at once and whether
// locked or not. FCh (unlock 2): DRQ for one 512-byte PIO data-out block;
// when the block is complete, DRQ clears and the card unlocks if bytes 2-6
// equal the key and every other byte is 0, else ERR (error 00h) and the card
// stays locked. The bytes are checked as they arrive (t2_bad). MAME also
// raises IRQ for FEh and FCh; this card has no IRQ output (the G-NET BIOS
// polls status), as for the other commands.
//
// CompactFlash unlock (MAME 0.288 taito_compact_flash_device): locked at
// power-on when a key is loaded. 0Fh, at once and whether locked or not:
// unlock if feature, sector count, sector number, cylinder low and cylinder
// high equal key bytes 0-4 (sector count as MAME holds it: 00h written is
// 100h), else DRDY clears and the card stays locked; no data phase, no ERR.
// MAME's IRQ for 0Fh is left out as for the other commands.
//
// Timing (MAME 0.288 values as defaults, all parameters): reset detect 2 ms
// then diagnostic 2 ms; IDENTIFY 10 us busy; first sector of a read 0 (CF
// seek time); between sectors 400 ns; each written sector 100 us. Status bit
// IDX is always 0 (CF 1.4); MAME's hard disk model has an index pulse in
// calculate_status, but it never appears in the oracle traces, so MAME and
// the specification agree.
//
// Storage: word port into the card image (word address = LBA * 256 + n,
// little-endian 16-bit words of the image bytes). A read fills the sector
// buffer in the background; data port reads stall (op_ack) until their word
// has arrived, so DRQ timing stays as MAME's. A written sector goes to
// storage during its busy time and sets its 4 KB hunk in the dirty map.

module gnet_ata #(
    parameter int unsigned CLK_HZ      = 33_868_800,
    parameter int unsigned NUM_LBA     = 80_000,
    parameter int unsigned NUM_HEADS   = 16,     // CHS translation (unused by the games: LBA)
    parameter int unsigned NUM_SECTORS = 50,
    parameter int unsigned T_DETECT_NS = 2_000_000,
    parameter int unsigned T_DIAG_NS   = 2_000_000,
    parameter int unsigned T_CMD_NS    = 10_000,
    parameter int unsigned T_FIRST_NS  = 0,
    parameter int unsigned T_NEXT_NS   = 400,
    parameter int unsigned T_WRITE_NS  = 100_000
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        card_reset,     // from the RF5C296 (03h bit 6 = 0)

    // attribute memory (word offset)
    input  logic        attr_req,
    input  logic        attr_we,
    input  logic [19:0] attr_waddr,
    input  logic [15:0] attr_wdata,
    output logic        attr_ack,
    output logic [15:0] attr_rdata,

    // task file (16-bit lane at even byte offset)
    input  logic        tf_req,
    input  logic        tf_we,
    input  logic [15:0] tf_off,
    input  logic [1:0]  tf_bmask,
    input  logic [15:0] tf_wdata,
    output logic        tf_ack,
    output logic [15:0] tf_rdata,

    // per-game data
    input  logic        meta_we,
    input  logic [9:0]  meta_addr,
    input  logic [7:0]  meta_wdata,
    input  logic        key_valid,

    // card image
    output logic        st_req,
    output logic        st_we,
    output logic [24:0] st_addr,
    output logic [15:0] st_wdata,
    input  logic        st_ack,
    input  logic [15:0] st_rdata,

    // dirty 4 KB hunks (8 sectors)
    output logic        dirty_set,
    output logic [13:0] dirty_hunk,
    input  logic [13:0] dirty_raddr,
    output logic        dirty_rdata,
    input  logic        dirty_clear,

    // debug tap (docs/hw_debug_overlay.md): pulse when a READ SECTORS (20h)
    // or WRITE SECTORS (30h) command is written and taken by the task file
    output logic        dbg_sec_cmd
);
    function automatic logic [31:0] ns2cyc(input int unsigned ns);
        return 32'((64'(CLK_HZ) * 64'(ns) + 64'd999_999_999) / 64'd1_000_000_000);
    endfunction
    localparam logic [31:0] T_DETECT = ns2cyc(T_DETECT_NS);
    localparam logic [31:0] T_DIAG   = ns2cyc(T_DIAG_NS);
    localparam logic [31:0] T_CMD    = ns2cyc(T_CMD_NS);
    localparam logic [31:0] T_FIRST  = ns2cyc(T_FIRST_NS);
    localparam logic [31:0] T_NEXT   = ns2cyc(T_NEXT_NS);
    localparam logic [31:0] T_WRITE  = ns2cyc(T_WRITE_NS);

    localparam logic [7:0] ST_BSY = 8'h80, ST_DRDY = 8'h40, ST_DSC = 8'h10, ST_DRQ = 8'h08, ST_ERR = 8'h01;

    // ---------------------------------------------------------------- memories
    logic [7:0]  idnt_lo [256], idnt_hi [256];
    logic [7:0]  cis     [256];
    logic [7:0]  key     [5];
    logic [7:0]  buf_lo  [256], buf_hi [256];
    logic        dmap    [16384];
    logic [7:0]  card_type;
    logic [7:0]  lba_b   [4];        // IDENTIFY words 60-61, little-endian

    always_ff @(posedge clk) begin
        if (meta_we) begin
            if (meta_addr == 10'h3f0) card_type <= meta_wdata;
            if (meta_addr[9:2] == 8'h1e) lba_b[meta_addr[1:0]] <= meta_wdata;
            case (meta_addr[9:8])
                2'b00, 2'b01: if (meta_addr[0]) idnt_hi[meta_addr[8:1]] <= meta_wdata;
                              else             idnt_lo[meta_addr[8:1]] <= meta_wdata;
                2'b10:        cis[meta_addr[7:0]] <= meta_wdata;
                default:      if (meta_addr[7:0] < 8'd5) key[meta_addr[2:0]] <= meta_wdata;
            endcase
        end
    end

    // dirty map (one write port, one read port)
    logic        dm_we;
    logic [13:0] dm_waddr;
    logic [13:0] clr_addr;
    logic        clr_act;
    always_ff @(posedge clk) begin
        if (dm_we)       dmap[dm_waddr] <= 1'b1;
        else if (clr_act) dmap[clr_addr] <= 1'b0;
        dirty_rdata <= dmap[dirty_raddr];
    end
    always_ff @(posedge clk) begin
        if (rst || dirty_clear) begin clr_act <= 1'b1; clr_addr <= 14'd0; end
        else if (clr_act && !dm_we) begin
            if (clr_addr == 14'h3fff) clr_act <= 1'b0;
            clr_addr <= clr_addr + 14'd1;
        end
    end
    assign dirty_set  = dm_we;
    assign dirty_hunk = dm_waddr;

    // ---------------------------------------------------------------- state
    logic [7:0]  status, error, feature, secnum, cyllo, cylhi, devhead, command, devctl;
    logic [8:0]  seccnt;
    logic        resetting;
    logic [8:0]  locked;
    logic [7:0]  cfg_opt, cfg_stat;
    logic [9:0]  boff;            // byte offset in the buffer (0-512)
    logic        bit8;            // last command block access was a byte access
    logic        src_idnt;        // data comes from the IDENTIFY block
    logic [31:0] bcnt;            // busy countdown
    typedef enum logic [2:0] {B_NONE, B_DETECT, B_DIAG, B_CMD, B_READ, B_WRITE, B_RESET} bp_t;
    bp_t         bparam;

    // sector engine
    logic        se_act, se_we;
    logic [16:0] se_lba;
    logic [8:0]  se_idx;          // words transferred
    logic [8:0]  fill;            // words in the buffer for a read
    logic [1:0]  se_rd_pend;      // write: buffer word read in flight (2-cycle RAM read)

    wire selected = (devhead[4] == 1'b0);
    wire ready_ok = (locked == 9'd0);
    wire t2       = (card_type == 8'h02);
    wire cf       = (card_type == 8'h03);
    wire t1       = !t2 && !cf;
    logic        t2_bad;          // Type 2 unlock block: a byte so far is wrong

    // card size in sectors: IDENTIFY words 60-61, else the parameter
    logic [31:0] num_lba;
    always_ff @(posedge clk)
        num_lba <= ({lba_b[3], lba_b[2], lba_b[1], lba_b[0]} != 32'd0)
                   ? {lba_b[3], lba_b[2], lba_b[1], lba_b[0]} : 32'(NUM_LBA);

    function automatic logic [31:0] lba_of(input logic [7:0] dh, input logic [7:0] ch,
                                            input logic [7:0] cl, input logic [7:0] sn);
        if (dh[6]) lba_of = {4'h0, dh[3:0], ch, cl, sn};
        else       lba_of = (({16'h0, ch, cl} * NUM_HEADS + {28'h0, dh[3:0]}) * NUM_SECTORS) + {24'h0, sn} - 32'd1;
    endfunction
    wire [31:0] cur_lba = lba_of(devhead, cylhi, cyllo, secnum);

    // ---------------------------------------------------------------- ops
    typedef enum logic [2:0] {O_IDLE, O_DRD, O_DRD1, O_DRD2, O_ARD} os_t;
    os_t         os;
    logic        o_hi;            // byte at the odd offset (high lane)
    logic [7:0]  o_reg;
    logic        rd_word_hi;
    logic [15:0] ram_q;
    logic        ram_from_idnt;
    logic [7:0]  cis_q;

    // buffer read port
    logic [7:0] ram_raddr;
    always_ff @(posedge clk) begin
        ram_q <= ram_from_idnt ? {idnt_hi[ram_raddr], idnt_lo[ram_raddr]}
                               : {buf_hi[ram_raddr],  buf_lo[ram_raddr]};
        cis_q <= cis[attr_waddr[7:0]];
    end

    // buffer write port (CPU data writes or sector fill)
    logic       bw_lo, bw_hi;
    logic [7:0] bw_addr;
    logic [15:0] bw_data;
    always_ff @(posedge clk) begin
        if (bw_lo) buf_lo[bw_addr] <= bw_data[7:0];
        if (bw_hi) buf_hi[bw_addr] <= bw_data[15:8];
    end

    // registers the reset sequence leaves (device_reset in MAME)
    task automatic card_power_on();
        status    <= ST_BSY;          // status = 0, then busy (detect)
        devctl    <= 8'h00;
        resetting <= 1'b1;
        bparam    <= B_DETECT;
        bcnt      <= T_DETECT;
        boff      <= 10'd0;
        cfg_opt   <= 8'h00;
        cfg_stat  <= 8'h00;
        locked    <= key_valid ? (t1 ? 9'h1ff : 9'h001) : 9'h000;
        se_act    <= 1'b0;
        src_idnt  <= 1'b0;
        t2_bad    <= 1'b0;
    endtask

    always_ff @(posedge clk) begin
        tf_ack   <= 1'b0;
        attr_ack <= 1'b0;
        bw_lo    <= 1'b0;
        bw_hi    <= 1'b0;
        dm_we    <= 1'b0;
        dbg_sec_cmd <= 1'b0;

        if (rst || card_reset) begin
            card_power_on();
            os       <= O_IDLE;
            st_req   <= 1'b0;
            if (rst) begin
                error    <= 8'h00; feature <= 8'h00; seccnt <= 9'd0; secnum <= 8'h00;
                cyllo    <= 8'h00; cylhi   <= 8'h00; devhead <= 8'h00; command <= 8'h00;
                bit8     <= 1'b0;
            end
        end else begin
            // ------------------------------------------------ busy timer
            if (status[7] && bparam != B_RESET && bparam != B_NONE) begin
                if (bcnt != 32'd0) begin
                    bcnt <= bcnt - 32'd1;
                end else if (!(bparam == B_WRITE && se_act)) begin
                    status <= status & ~ST_BSY;
                    bparam <= B_NONE;
                    case (bparam)
                        B_DETECT: begin               // soft_reset
                            boff   <= 10'd0;
                            status <= (ready_ok ? ST_DRDY : 8'h00) | ST_DSC | ST_BSY;
                            bparam <= B_DIAG;
                            bcnt   <= T_DIAG;
                        end
                        B_DIAG: begin                 // finished diagnostic, signature
                            error     <= 8'h01;
                            resetting <= 1'b0;
                            seccnt    <= 9'd1;
                            secnum    <= 8'h01;
                            cyllo     <= 8'h00;
                            cylhi     <= 8'h00;
                            devhead   <= 8'h00;
                        end
                        B_CMD: begin                  // IDENTIFY finished
                            src_idnt <= 1'b1;
                            boff     <= 10'd0;
                            status   <= (status & ~ST_BSY) | ST_DRQ;
                        end
                        B_READ: begin                 // finished_read
                            if (cur_lba >= num_lba) begin
                                status <= (status & ~ST_BSY) | ST_ERR;
                                error  <= 8'h80;
                            end else begin
                                se_act   <= 1'b1;
                                se_we    <= 1'b0;
                                se_lba   <= cur_lba[16:0];
                                se_idx   <= 9'd0;
                                fill     <= 9'd0;
                                src_idnt <= 1'b0;
                                boff     <= 10'd0;
                                status   <= (status & ~ST_BSY) | ST_DRQ;
                                if (seccnt != 9'd1) next_sector();
                            end
                        end
                        B_WRITE: begin                // finished_write (sector stored)
                            dm_we    <= 1'b1;
                            dm_waddr <= se_lba[16:3];
                            if (seccnt != 9'd1) next_sector();
                            if (seccnt != 9'd0) begin
                                seccnt <= seccnt - 9'd1;
                                if (seccnt != 9'd1) status <= (status & ~ST_BSY) | ST_DRQ;
                            end
                        end
                        default: ;
                    endcase
                end
            end

            // ------------------------------------------------ sector engine
            if (se_act) begin
                if (!se_we) begin                     // card -> buffer
                    if (!st_req && se_idx != 9'd256) begin
                        st_req  <= 1'b1;
                        st_we   <= 1'b0;
                        st_addr <= {se_lba, se_idx[7:0]};
                    end else if (st_req && st_ack) begin
                        st_req  <= 1'b0;
                        bw_lo   <= 1'b1; bw_hi <= 1'b1;
                        bw_addr <= se_idx[7:0];
                        bw_data <= st_rdata;
                        se_idx  <= se_idx + 9'd1;
                        fill    <= se_idx + 9'd1;
                        if (se_idx == 9'd255) se_act <= 1'b0;
                    end
                end else begin                        // buffer -> card
                    if (!st_req && se_rd_pend == 2'd0 && os == O_IDLE && !tf_req) begin
                        ram_from_idnt <= 1'b0;
                        ram_raddr     <= se_idx[7:0];
                        se_rd_pend    <= 2'd1;
                    end else if (se_rd_pend == 2'd1) begin
                        se_rd_pend    <= 2'd2;
                    end else if (se_rd_pend == 2'd2 && !st_req) begin
                        st_req   <= 1'b1;
                        st_we    <= 1'b1;
                        st_addr  <= {se_lba, se_idx[7:0]};
                        st_wdata <= ram_q;
                    end else if (st_req && st_ack) begin
                        st_req     <= 1'b0;
                        se_rd_pend <= 2'd0;
                        se_idx     <= se_idx + 9'd1;
                        if (se_idx == 9'd255) se_act <= 1'b0;
                    end
                end
            end

            // ------------------------------------------------ attribute memory
            if (attr_req) begin
                if (attr_we) begin
                    attr_ack <= 1'b1;
                    if (t1 && attr_waddr >= 20'h280 && attr_waddr <= 20'h288) begin
                        logic [3:0] p;
                        p = 4'(attr_waddr - 20'h280);
                        if (attr_wdata[7:0] == ((p < 4'd5) ? key[p[2:0]] : 8'h00)) locked[p] <= 1'b0;
                        else                                                       locked[p] <= 1'b1;
                    end else if (attr_waddr == 20'h100) cfg_opt  <= attr_wdata[7:0];
                    else if (attr_waddr == 20'h101)     cfg_stat <= attr_wdata[7:0];
                end else begin
                    os <= O_ARD;                      // CIS read needs the RAM cycle
                end
            end
            if (os == O_ARD) begin
                os       <= O_IDLE;
                attr_ack <= 1'b1;
                if (attr_waddr < 20'h100)       attr_rdata <= {8'h00, cis_q};
                else if (attr_waddr == 20'h100) attr_rdata <= {8'h00, cfg_opt};
                else if (attr_waddr == 20'h101) attr_rdata <= {8'h00, cfg_stat};
                else if (attr_waddr == 20'h102) attr_rdata <= 16'h002e;
                else if (attr_waddr == 20'h201 && t1) attr_rdata <= {15'h0, locked != 9'd0};
                else                            attr_rdata <= 16'hffff;
            end

            // ------------------------------------------------ task file
            if (tf_req && os == O_IDLE) begin
                logic        w16;
                logic [15:0] r;
                logic [7:0]  wd;
                w16   = (tf_bmask == 2'b11);
                o_hi  <= (tf_bmask == 2'b10);
                r     = {8'h00, (tf_bmask == 2'b10) ? 8'(tf_off + 16'd1) : tf_off[7:0]};
                wd    = (tf_bmask == 2'b10) ? tf_wdata[15:8] : tf_wdata[7:0];
                if (tf_off > 16'd15) begin
                    tf_ack   <= 1'b1;
                    tf_rdata <= 16'hffff;
                end else if (r[7:0] <= 8'd7) begin
                    // command block
                    bit8 <= !w16;
                    if (!tf_we) begin
                        if (!status[6] && ready_ok) status <= status | ST_DRDY;
                        if (status[7] && r[7:0] != 8'd0) begin
                            tf_ack   <= 1'b1;
                            tf_rdata <= put(selected ? stat_rd() : 8'h00);
                        end else case (r[2:0])
                            3'd0: begin
                                if (!selected || status[7] || !status[3]) begin
                                    tf_ack   <= 1'b1;
                                    tf_rdata <= 16'hffff;
                                end else begin
                                    os <= O_DRD;
                                end
                            end
                            3'd1: begin tf_ack <= 1'b1; tf_rdata <= put(error);   end
                            3'd2: begin tf_ack <= 1'b1; tf_rdata <= o_put16(seccnt); end
                            3'd3: begin tf_ack <= 1'b1; tf_rdata <= put(secnum);  end
                            3'd4: begin tf_ack <= 1'b1; tf_rdata <= put(cyllo);   end
                            3'd5: begin tf_ack <= 1'b1; tf_rdata <= put(cylhi);   end
                            3'd6: begin tf_ack <= 1'b1; tf_rdata <= put(devhead); end
                            default: begin
                                tf_ack   <= 1'b1;
                                tf_rdata <= put(selected ? stat_rd() : 8'h00);
                            end
                        endcase
                    end else begin
                        tf_ack <= 1'b1;
                        if (status[3] && r[2:0] != 3'd0 && (r[2:0] != 3'd6 || wd != devhead)) begin
                            status <= (status & ~(ST_BSY | ST_DRQ)) | ST_ERR;   // abort
                            bparam <= B_NONE;
                            error  <= 8'h04;
                        end
                        if (!status[7] || (status[3] && r[2:0] != 3'd0 && (r[2:0] != 3'd6 || wd != devhead))) begin
                            case (r[2:0])
                                3'd0: if (selected && status[3]) data_write(w16);
                                3'd1: feature <= wd;
                                3'd2: seccnt  <= (wd != 8'h00) ? {1'b0, wd} : 9'h100;
                                3'd3: secnum  <= wd;
                                3'd4: cyllo   <= wd;
                                3'd5: cylhi   <= wd;
                                3'd6: devhead <= wd;
                                default: if (selected || command == 8'h90) begin
                                    command <= wd;
                                    boff    <= 10'd0;
                                    error   <= 8'h00;
                                    dbg_sec_cmd <= (wd == 8'h20) || (wd == 8'h30);
                                    process_command(wd, status & ~ST_ERR);
                                end
                            endcase
                        end
                    end
                end else begin
                    // control block
                    tf_ack <= 1'b1;
                    if (!tf_we) begin
                        if (!status[6] && ready_ok) status <= status | ST_DRDY;
                        case (r[2:0])
                            3'd6: tf_rdata <= put(selected ? stat_rd() : 8'h00);
                            3'd7: tf_rdata <= put({7'h0, selected});
                            default: tf_rdata <= 16'hffff;
                        endcase
                    end else if (r[2:0] == 3'd6) begin
                        devctl <= wd;
                        if ((devctl[2] ^ wd[2])) begin
                            if (wd[2]) begin
                                if (!resetting) begin
                                    status <= status | ST_BSY;
                                    bparam <= B_RESET;
                                end
                            end else if (bparam == B_RESET) begin
                                boff   <= 10'd0;     // soft_reset
                                status <= (ready_ok ? ST_DRDY : 8'h00) | ST_DSC | ST_BSY;
                                bparam <= B_DIAG;
                                bcnt   <= T_DIAG;
                            end
                        end
                    end
                end
            end

            // data port read: wait for the word, then the RAM cycle
            if (os == O_DRD) begin
                if (src_idnt || fill > {1'b0, boff[8:1]}) begin
                    ram_from_idnt <= src_idnt;
                    ram_raddr     <= boff[8:1];
                    rd_word_hi    <= boff[0];
                    os            <= O_DRD1;
                end
            end else if (os == O_DRD1) begin
                os <= O_DRD2;                         // RAM output registered
            end else if (os == O_DRD2) begin
                os     <= O_IDLE;
                tf_ack <= 1'b1;
                if (bit8) tf_rdata <= o_hi ? {(rd_word_hi ? ram_q[15:8] : ram_q[7:0]), 8'h00}
                                           : {8'h00, (rd_word_hi ? ram_q[15:8] : ram_q[7:0])};
                else      tf_rdata <= ram_q;
                if (boff + (bit8 ? 10'd1 : 10'd2) >= 10'd512) read_buffer_empty();
                else boff <= boff + (bit8 ? 10'd1 : 10'd2);
            end
        end
    end

    // ---------------------------------------------------------------- helpers
    function automatic logic [15:0] put(input logic [7:0] v);
        put = o_hi_now() ? {v, 8'h00} : {8'h00, v};
    endfunction
    function automatic logic o_hi_now();
        o_hi_now = (tf_bmask == 2'b10);
    endfunction
    function automatic logic [15:0] o_put16(input logic [8:0] v);
        o_put16 = (tf_bmask == 2'b11) ? {7'h0, v} : put(v[7:0]);
    endfunction
    // status as a read sees it: DRDY is set lazily on every register read
    // once the card is ready (MAME command_r/control_r)
    function automatic logic [7:0] stat_rd();
        stat_rd = status | (ready_ok ? ST_DRDY : 8'h00);
    endfunction

    task automatic next_sector();
        if (devhead[6]) begin
            secnum <= secnum + 8'd1;
            if (secnum == 8'hff) begin
                cyllo <= cyllo + 8'd1;
                if (cyllo == 8'hff) begin
                    cylhi <= cylhi + 8'd1;
                    if (cylhi == 8'hff) devhead <= {devhead[7:4], devhead[3:0] + 4'd1};
                end
            end
        end else begin
            if (secnum >= 8'(NUM_SECTORS)) begin
                secnum <= 8'd1;
                if ({1'b0, devhead[3:0]} + 5'd1 >= 5'(NUM_HEADS)) begin
                    devhead <= {devhead[7:4], 4'd0};
                    cyllo   <= cyllo + 8'd1;
                    if (cyllo == 8'hff) cylhi <= cylhi + 8'd1;
                end else begin
                    devhead <= {devhead[7:4], devhead[3:0] + 4'd1};
                end
            end else begin
                secnum <= secnum + 8'd1;
            end
        end
    endtask

    // s0: status with ERR already cleared by the command write
    task automatic process_command(input logic [7:0] c, input logic [7:0] s0);
        if (t2 && c == 8'hfe) begin                  // Type 2 unlock 1
            seccnt <= 9'd1;
            status <= s0 | ST_DRDY;
        end else if (t2 && c == 8'hfc) begin         // Type 2 unlock 2: key block
            status <= s0 | ST_DRQ;
            t2_bad <= 1'b0;
        end else if (cf && c == 8'h0f) begin         // CompactFlash unlock: key in the task file
            if (feature == key[0] && seccnt == {1'b0, key[1]} && secnum == key[2] &&
                cyllo == key[3] && cylhi == key[4]) begin
                status <= s0;
                locked <= 9'h000;
            end else
                status <= s0 & ~ST_DRDY;
        end else if (!ready_ok) begin                // locked (all three types)
            status <= (s0 & ~ST_DRDY) | ST_ERR;
            error  <= 8'h00;
        end else case (c)
            8'h20: begin
                status <= s0 | ST_BSY;
                bparam <= B_READ;
                bcnt   <= T_FIRST;
            end
            8'h30: status <= s0 | ST_DRQ;
            8'hec: begin
                status <= s0 | ST_BSY;
                bparam <= B_CMD;
                bcnt   <= T_CMD;
            end
            default: begin
                status <= s0 | ST_ERR;
                error  <= 8'h04;
            end
        endcase
    endtask

    task automatic read_buffer_empty();
        boff   <= 10'd0;
        status <= status & ~ST_DRQ;
        if (!src_idnt) begin
            logic [8:0] n;
            n = (seccnt != 9'd0) ? seccnt - 9'd1 : 9'd0;
            seccnt <= n;
            if (n != 9'd0) begin
                status <= (status & ~ST_DRQ) | ST_BSY;
                bparam <= B_READ;
                bcnt   <= T_NEXT;
            end
        end
    endtask

    // Type 2 unlock block: byte o of the block is wrong
    function automatic logic key_bad(input logic [9:0] o, input logic [7:0] v);
        if (o < 10'd2 || o >= 10'd7) key_bad = (v != 8'h00);
        else                         key_bad = (v != key[3'(o - 10'd2)]);
    endfunction

    task automatic data_write(input logic w16);
        logic nb;
        nb = w16 ? (key_bad(boff, tf_wdata[7:0]) | key_bad(boff + 10'd1, tf_wdata[15:8]))
                 :  key_bad(boff, tf_wdata[7:0]);
        bw_addr <= boff[8:1];
        if (w16) begin
            bw_lo   <= 1'b1; bw_hi <= 1'b1;
            bw_data <= tf_wdata;
        end else begin
            bw_lo   <= !boff[0];
            bw_hi   <=  boff[0];
            bw_data <= {tf_wdata[7:0], tf_wdata[7:0]};
        end
        if (t2 && command == 8'hfc) begin            // Type 2 unlock block
            if (boff + (w16 ? 10'd2 : 10'd1) >= 10'd512) begin   // process_buffer
                boff <= 10'd0;
                if (t2_bad | nb) begin
                    status <= (status & ~ST_DRQ) | ST_ERR;
                    error  <= 8'h00;
                end else begin
                    status <= status & ~ST_DRQ;
                    locked <= 9'h000;
                end
            end else begin
                boff   <= boff + (w16 ? 10'd2 : 10'd1);
                t2_bad <= t2_bad | nb;
            end
        end else if (boff + (w16 ? 10'd2 : 10'd1) >= 10'd512) begin   // write_buffer_full
            boff   <= 10'd0;
            status <= (status & ~ST_DRQ) | ST_BSY;
            bparam <= B_WRITE;
            bcnt   <= T_WRITE;
            se_act <= 1'b1;
            se_we  <= 1'b1;
            se_lba <= cur_lba[16:0];
            se_idx <= 9'd0;
            se_rd_pend <= 2'd0;
        end else begin
            boff <= boff + (w16 ? 10'd2 : 10'd1);
        end
    endtask
endmodule
