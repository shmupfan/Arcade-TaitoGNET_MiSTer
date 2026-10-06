// G-NET FC PCB flash command machine for the five Intel-command-set chips.
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
// Chips (docs/gnet_glue_design.md 3): 0 = U30 TE28F160 (2 MB, sub-BIOS and
// game program), 1 = U27 E28F400B (512 KB, Zoom program), 2..4 = U56, U55,
// U29 TE28F160 (wave data). 16-bit chips; addresses here are word addresses.
//
// Commands (Intel 28F160S3 290608-005 and 28F400B5; MAME intelfsh.cpp for the
// mode transitions the datasheets leave open):
//   FFh/F0h read array, 90h read identifier, 70h read status register,
//   50h clear status register (enters read status, as MAME), 40h/10h word
//   program (next write is the data), 20h block erase then D0h confirm,
//   60h lock-bit setup (the next write is consumed, locks not modelled).
// Identifier (read identifier mode, word address bits 7:0): 0 maker, 1 device,
// 2 block lock 0, 3 master lock 0, others 0. TE28F160: B0h/D0h; E28F400B:
// 89h/4471h (values as MAME; 28F160S3 datasheet Table 12 p24 gives B0h/D0h).
// Status: 80h ready, 00h while a program or erase runs (SR.7 = 0).
//
// Program: the stored word becomes old AND new (PROGRAM_AND = 1, datasheet:
// programming only clears bits) or new (PROGRAM_AND = 0, MAME overwrites).
// Erase blocks: TE28F160 64 KB; E28F400B bottom boot 16 KB, 8 KB, 8 KB,
// 96 KB, then 128 KB (28F400B5 datasheet; same as MAME).
// Timing (cycles of clk), PRESET 1 = MAME 0.288 (program instant; erase 1.0 s,
// E28F400B 0.3 s boot/parameter and 0.6 s main), PRESET 2 = 28F160S3 typical
// at 2.7 V VPP (290608-005 p50: 20.0 us per word, 0.56 s per block), PRESET 3
// = 28F160S5 typical at 5 V VPP (290609-004 p49: 9.24 us per word, 0.34 s per
// block; the part on the FC PCB, TE28F160 S5100, docs/board_evidence.md P1)
// for the TE28F160 chips; the E28F400B keeps the MAME values in all presets (the
// 28F400B5 datasheet in the library gives maxima only: 100 us, 7 s, 14 s).
// When a program or erase completes, status returns to 80h whatever the read
// mode (datasheet: the WSM finishes); MAME only does this in read status mode.
// zoom_release puts U27 and the wave chips into read array mode (MAME
// taitogn.cpp control_w: "assume that this also readies the sound flash
// chips"; no board evidence).
//
// Storage sits behind one word-wide memory port (mem_req held until mem_ack).
// The erase engine writes FFFFh over the block in the background while the
// chip reports busy; CPU operations have priority on the port.

module gnet_flash #(
    parameter int unsigned CLK_HZ      = 33_868_800,
    parameter int unsigned PRESET      = 1,
    parameter bit          PROGRAM_AND = 1'b1
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        op_req,
    input  logic        op_we,
    input  logic [2:0]  op_chip,
    input  logic [20:0] op_waddr,
    input  logic [15:0] op_wdata,
    output logic        op_ack,
    output logic [15:0] op_rdata,

    input  logic        zoom_release,

    output logic        mem_req,
    output logic        mem_we,
    output logic [2:0]  mem_chip,
    output logic [20:0] mem_addr,
    output logic [15:0] mem_wdata,
    input  logic        mem_ack,
    input  logic [15:0] mem_rdata,

    output logic [4:0]  busy          // per chip: program/erase in progress
);
    // --- timing --------------------------------------------------------------
    function automatic logic [31:0] cyc_us(input int unsigned us);
        return 32'((64'(CLK_HZ) * 64'(us)) / 64'd1_000_000);
    endfunction
    function automatic logic [31:0] cyc_ns(input int unsigned ns);
        return 32'((64'(CLK_HZ) * 64'(ns)) / 64'd1_000_000_000);
    endfunction
    localparam logic [31:0] T_PROG_S   = (PRESET == 2) ? cyc_us(20)      :
                                         (PRESET == 3) ? cyc_ns(9_240)   : 32'd0;
    localparam logic [31:0] T_ERASE_S  = (PRESET == 2) ? cyc_us(560_000) :
                                         (PRESET == 3) ? cyc_us(340_000) : cyc_us(1_000_000);
    localparam logic [31:0] T_PROG_B   = 32'd0;
    localparam logic [31:0] T_ERASE_BP = cyc_us(300_000);
    localparam logic [31:0] T_ERASE_BM = cyc_us(600_000);

    // --- per-chip state ------------------------------------------------------
    typedef enum logic [2:0] {M_NORMAL, M_STATUS, M_ID, M_PROG, M_ERASE1, M_MASTER} mode_t;
    mode_t       mode   [5];
    logic [31:0] timer  [5];
    logic [4:0]  tbusy;            // timer running

    // erase engine
    logic        er_act;
    logic [2:0]  er_chip;
    logic [20:0] er_addr, er_last;
    logic        er_mem;           // engine owns the memory port this access

    // operation sequencer
    typedef enum logic [2:0] {S_IDLE, S_READ, S_RMW_RD, S_PROG_WR, S_WAIT_ER} st_t;
    st_t         st;
    logic        o_we;
    logic [2:0]  o_chip;
    logic [20:0] o_addr;
    logic [15:0] o_wdata;
    logic        mem_busy;         // a memory access is outstanding


    function automatic logic [15:0] ident(input logic [2:0] chip, input logic [7:0] a);
        case (a)
            8'h00:   ident = (chip == 3'd1) ? 16'h0089 : 16'h00b0;
            8'h01:   ident = (chip == 3'd1) ? 16'h4471 : 16'h00d0;
            default: ident = 16'h0000;
        endcase
    endfunction

    // erase block of word address a: first word and last word
    task automatic erase_block(input logic [2:0] chip, input logic [20:0] a,
                               output logic [20:0] first, output logic [20:0] last,
                               output logic [31:0] t);
        logic [19:0] b;   // byte address within a 512 KB E28F400B
        if (chip != 3'd1) begin
            first = {a[20:15], 15'h0000};
            last  = {a[20:15], 15'h7fff};
            t     = T_ERASE_S;
        end else begin
            b = {1'b0, a[17:0], 1'b0};
            if (b < 20'h04000) begin
                first = 21'h00000; last = 21'h01fff; t = T_ERASE_BP;
            end else if (b < 20'h08000) begin
                first = 21'(b[14:13]) << 12; last = first + 21'h00fff; t = T_ERASE_BP;
            end else if (b < 20'h20000) begin
                first = 21'h04000; last = 21'h0ffff; t = T_ERASE_BM;
            end else begin
                first = {3'b000, b[18:17], 16'h0000}; last = first + 21'h0ffff; t = T_ERASE_BM;
            end
        end
    endtask

    // A program or erase that started at the write of cycle W is complete
    // for a status read at cycle R when R - W >= T: the timer then holds 1
    // (MAME: ready when the read happens at or after the write time + T).
    logic [4:0] tdone;
    always_comb for (int i = 0; i < 5; i++) tdone[i] = !tbusy[i] || timer[i] <= 32'd1;
    assign busy = ~tdone | ({5{er_act}} & (5'b00001 << er_chip));

    always_ff @(posedge clk) begin
        op_ack <= 1'b0;
        if (rst) begin
            for (int i = 0; i < 5; i++) begin
                mode[i]  <= M_NORMAL;
                timer[i] <= 32'd0;
            end
            tbusy    <= 5'b0;
            st       <= S_IDLE;
            er_act   <= 1'b0;
            mem_req  <= 1'b0;
            mem_busy <= 1'b0;
            er_mem   <= 1'b0;
        end else begin
            // timers
            for (int i = 0; i < 5; i++) begin
                if (tbusy[i]) begin
                    if (timer[i] <= 32'd1) tbusy[i] <= 1'b0;
                    else timer[i] <= timer[i] - 32'd1;
                end
            end
            if (zoom_release) begin
                for (int i = 1; i < 5; i++) mode[i] <= M_NORMAL;
            end

            // memory port completion
            if (mem_busy && mem_ack) begin
                mem_req  <= 1'b0;
                mem_busy <= 1'b0;
                if (er_mem) begin
                    er_mem <= 1'b0;
                    if (er_addr == er_last) er_act <= 1'b0;
                    else er_addr <= er_addr + 21'd1;
                end
            end

            case (st)
                S_IDLE: if (op_req) begin
                    o_we    <= op_we;
                    o_chip  <= op_chip;
                    o_addr  <= op_waddr;
                    o_wdata <= op_wdata;
                    if (!op_we) begin
                        case (mode[op_chip])
                            M_STATUS: begin
                                op_rdata <= {8'h00, (busy[op_chip] ? 8'h00 : 8'h80)};
                                op_ack   <= 1'b1;
                            end
                            M_ID: begin
                                op_rdata <= ident(op_chip, op_waddr[7:0]);
                                op_ack   <= 1'b1;
                            end
                            default: st <= S_READ;
                        endcase
                    end else begin
                        case (mode[op_chip])
                            M_PROG: begin
                                mode[op_chip]  <= M_STATUS;
                                tbusy[op_chip] <= ((op_chip == 3'd1) ? T_PROG_B : T_PROG_S) != 32'd0;
                                timer[op_chip] <= (op_chip == 3'd1) ? T_PROG_B : T_PROG_S;
                                st <= PROGRAM_AND ? S_RMW_RD : S_PROG_WR;
                            end
                            M_ERASE1: begin
                                if (op_wdata[7:0] == 8'hd0) begin
                                    logic [20:0] f, l;
                                    logic [31:0] t;
                                    erase_block(op_chip, op_waddr, f, l, t);
                                    mode[op_chip]  <= M_STATUS;
                                    tbusy[op_chip] <= (t != 32'd0);   // timing starts at the confirm
                                    timer[op_chip] <= t;
                                    st <= S_WAIT_ER;
                                end else begin
                                    op_ack <= 1'b1;
                                end
                            end
                            M_MASTER: begin
                                mode[op_chip] <= M_STATUS;
                                op_ack <= 1'b1;
                            end
                            default: begin
                                case (op_wdata[7:0])
                                    8'hff, 8'hf0: mode[op_chip] <= M_NORMAL;
                                    8'h90:        mode[op_chip] <= M_ID;
                                    8'h40, 8'h10: mode[op_chip] <= M_PROG;
                                    8'h50:        mode[op_chip] <= M_STATUS;
                                    8'h70:        mode[op_chip] <= M_STATUS;
                                    8'h20:        mode[op_chip] <= M_ERASE1;
                                    8'h60:        mode[op_chip] <= M_MASTER;
                                    default: ;
                                endcase
                                op_ack <= 1'b1;
                            end
                        endcase
                    end
                end

                S_READ, S_RMW_RD, S_PROG_WR: begin
                    if (!mem_busy && !er_mem) begin
                        mem_req   <= 1'b1;
                        mem_busy  <= 1'b1;
                        mem_we    <= (st == S_PROG_WR);
                        mem_chip  <= o_chip;
                        mem_addr  <= o_addr;
                        mem_wdata <= o_wdata;
                    end else if (mem_busy && mem_ack && !er_mem) begin
                        case (st)
                            S_READ: begin
                                op_rdata <= mem_rdata;
                                op_ack   <= 1'b1;
                                st       <= S_IDLE;
                            end
                            S_RMW_RD: begin
                                o_wdata <= o_wdata & mem_rdata;
                                st      <= S_PROG_WR;
                            end
                            default: begin   // S_PROG_WR done
                                op_ack <= 1'b1;
                                st     <= S_IDLE;
                            end
                        endcase
                    end
                end

                S_WAIT_ER: if (!er_act && !mem_busy) begin
                    logic [20:0] f, l;
                    logic [31:0] t;
                    erase_block(o_chip, o_addr, f, l, t);
                    er_act        <= 1'b1;
                    er_chip       <= o_chip;
                    er_addr       <= f;
                    er_last       <= l;
                    op_ack        <= 1'b1;
                    st            <= S_IDLE;
                end

                default: st <= S_IDLE;
            endcase

            // erase engine uses the port when the sequencer does not need it
            if (er_act && !mem_busy && !er_mem && st != S_READ && st != S_RMW_RD && st != S_PROG_WR
                && !(st == S_IDLE && op_req)) begin
                mem_req   <= 1'b1;
                mem_busy  <= 1'b1;
                er_mem    <= 1'b1;
                mem_we    <= 1'b1;
                mem_chip  <= er_chip;
                mem_addr  <= er_addr;
                mem_wdata <= 16'hffff;
            end
        end
    end
endmodule
