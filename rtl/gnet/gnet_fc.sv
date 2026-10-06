// G-NET FC PCB glue top: main-CPU address decode for the flash bank window,
// the RF5C296 / ATA card, the control registers and the watchdog.
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
// CPU side: offsets from 0x1f000000 (docs/hardware_inventory.md 4).
//   000000-7fffff flash bank window (16-bit devices), bank = control bit 2
//                 | JP1 << 1 (MAME 0.288 taitogn.cpp flashbank_map):
//                   bank 0: U30 000000-1fffff, card attribute memory
//                           200000-2fffff (RF5C296 memory window), U27
//                           300000-37ffff
//                   bank 1, 3: U56 000000, U55 200000, U29 400000 (2 MB each)
//                   bank 2: EPROM 000000-0fffff (not modelled here, reads 0),
//                           U27 100000-1fffff (mirrored), U30 200000-3fffff
//                 unmapped space reads 0
//   a30000        control3
//   b00000-b0ffff RF5C296 I/O: 16-bit lane at 3E0h = ExCA index/data, the
//                 rest goes to the card task file (MAME's fixed I/O window)
//   b40000        control, b60000 control2, b70000 the 0x1fb70000 register
// A 32-bit access is split into 16-bit lane operations, low lane first, each
// carrying its byte enables (MAME's 16-bit devices on the 32-bit bus).
// cpu_hit says whether an address belongs to this block (for the integration
// with memorymux); cpu_ack follows every request, data valid with it.
// card_present = 0 (empty slot): the RF5C296 reports no card and card
// attribute memory and task file read FFFFh, writes ignored, as MAME's
// empty pccard slot (pccard.cpp read_memory/read_reg return 0xffff).

module gnet_fc #(
    parameter int unsigned CLK_HZ       = 33_868_800,
    parameter int unsigned FLASH_PRESET = 1,
    parameter bit          PROGRAM_AND  = 1'b1,
    parameter int unsigned WD_TIMEOUT_S = 8
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        jp1,
    input  logic        card_present,

    input  logic        cpu_req,
    input  logic        cpu_we,
    input  logic [23:0] cpu_addr,
    input  logic [3:0]  cpu_be,
    input  logic [31:0] cpu_wdata,
    output logic        cpu_ack,
    output logic [31:0] cpu_rdata,
    output logic        cpu_hit,

    output logic        zoom_reset,
    output logic        wd_reset,

    // flash storage (word port, chip 0 U30, 1 U27, 2-4 U56/U55/U29)
    output logic        fmem_req,
    output logic        fmem_we,
    output logic [2:0]  fmem_chip,
    output logic [20:0] fmem_addr,
    output logic [15:0] fmem_wdata,
    input  logic        fmem_ack,
    input  logic [15:0] fmem_rdata,
    output logic [4:0]  flash_busy,

    // card image storage
    output logic        cmem_req,
    output logic        cmem_we,
    output logic [24:0] cmem_addr,
    output logic [15:0] cmem_wdata,
    input  logic        cmem_ack,
    input  logic [15:0] cmem_rdata,

    // per-game card data and dirty map
    input  logic        meta_we,
    input  logic [9:0]  meta_addr,
    input  logic [7:0]  meta_wdata,
    input  logic        key_valid,
    output logic        dirty_set,
    output logic [13:0] dirty_hunk,
    input  logic [13:0] dirty_raddr,
    output logic        dirty_rdata,
    input  logic        dirty_clear,

    output logic        card_reset,
    output logic        win_mismatch,

    // debug taps (docs/hw_debug_overlay.md)
    output logic        dbg_wd_kick,   // pulse: watchdog CK falling edge (gnet_ctrl)
    output logic [7:0]  dbg_ctrl,      // control register 0x1fb40000
    output logic        dbg_sec_cmd    // pulse: ATA READ/WRITE SECTORS taken (gnet_ata)
);
    // ------------------------------------------------------------ decode
    typedef enum logic [2:0] {T_NONE, T_FLASH, T_ATTR, T_CTRL, T_EXCA, T_TF, T_EMPTY} tgt_t;

    function automatic logic glue_addr(input logic [23:0] a);
        glue_addr = (a < 24'h800000) || (a[23:2] == 22'(24'ha30000 >> 2)) ||
                    (a[23:16] == 8'hb0) || (a[23:2] == 22'(24'hb40000 >> 2)) ||
                    (a[23:2] == 22'(24'hb60000 >> 2)) || (a[23:2] == 22'(24'hb70000 >> 2));
    endfunction
    assign cpu_hit = glue_addr(cpu_addr);

    logic       bank_sel;
    wire  [1:0] bank = {jp1, bank_sel};

    // ------------------------------------------------------------ sequencer
    logic        busy, l_we, lane;
    logic [23:0] l_addr;
    logic [3:0]  l_be;
    logic [31:0] l_wdata, l_rdata;
    logic        op_pending;
    tgt_t        tgt;

    // lane decode (combinational from the latched request)
    logic [23:0] ba;            // byte address of the lane
    logic [1:0]  bm;
    logic [15:0] wd;
    tgt_t        dt;
    logic [2:0]  chip;
    logic [20:0] waddr;
    logic [1:0]  creg;
    always_comb begin
        ba    = {l_addr[23:2], lane, 1'b0};
        bm    = lane ? l_be[3:2] : l_be[1:0];
        wd    = lane ? l_wdata[31:16] : l_wdata[15:0];
        dt    = T_NONE;
        chip  = 3'd0;
        waddr = 21'd0;
        creg  = 2'd0;
        if (ba < 24'h800000) begin
            case (bank)
                2'd0: begin
                    if (ba < 24'h200000)      begin dt = T_FLASH; chip = 3'd0; waddr = 21'(ba[20:1]); end
                    else if (ba < 24'h300000) begin dt = T_ATTR;  waddr = 21'(ba[19:1]); end
                    else if (ba < 24'h380000) begin dt = T_FLASH; chip = 3'd1; waddr = 21'(ba[18:1]); end
                end
                2'd2: begin
                    if (ba >= 24'h100000 && ba < 24'h200000) begin dt = T_FLASH; chip = 3'd1; waddr = 21'(ba[18:1]); end
                    else if (ba >= 24'h200000 && ba < 24'h400000) begin dt = T_FLASH; chip = 3'd0; waddr = 21'(ba[20:1]); end
                end
                default: begin   // banks 1 and 3: waves
                    if (ba < 24'h600000) begin dt = T_FLASH; chip = 3'd2 + 3'(ba[22:21]); waddr = 21'(ba[20:1]); end
                end
            endcase
        end else if (ba[23:16] == 8'hb0) begin
            dt = (ba[15:0] == 16'h03e0) ? T_EXCA : T_TF;
        end else if (ba[23:2] == 22'(24'hb40000 >> 2)) begin dt = T_CTRL; creg = 2'd0; end
        else if (ba[23:2] == 22'(24'hb60000 >> 2))     begin dt = T_CTRL; creg = 2'd1; end
        else if (ba[23:2] == 22'(24'ha30000 >> 2))     begin dt = T_CTRL; creg = 2'd2; end
        else if (ba[23:2] == 22'(24'hb70000 >> 2))     begin dt = T_CTRL; creg = 2'd3; end
    end

    // sub-block request strobes and latched operands
    logic        f_req, a_req, c_req, e_req, t_req;
    logic [2:0]  q_chip;
    logic [20:0] q_waddr;
    logic [1:0]  q_creg, q_bm;
    logic [15:0] q_wd;
    logic [15:0] q_off;
    logic        q_hi;
    logic        f_ack, a_ack, c_ack, e_ack, t_ack;
    logic [15:0] f_rd, a_rd, c_rd, e_rd, t_rd;

    always_ff @(posedge clk) begin
        cpu_ack <= 1'b0;
        f_req <= 1'b0; a_req <= 1'b0; c_req <= 1'b0; e_req <= 1'b0; t_req <= 1'b0;
        if (rst) begin
            busy       <= 1'b0;
            op_pending <= 1'b0;
        end else if (!busy) begin
            if (cpu_req) begin
                busy    <= 1'b1;
                l_we    <= cpu_we;
                l_addr  <= cpu_addr;
                l_be    <= cpu_be;
                l_wdata <= cpu_wdata;
                l_rdata <= 32'h0;
                lane    <= (cpu_be[1:0] == 2'b00);
                op_pending <= 1'b0;
            end
        end else if (!op_pending) begin
            // issue the current lane
            q_chip  <= chip;
            q_waddr <= waddr;
            q_creg  <= creg;
            q_bm    <= bm;
            q_wd    <= wd;
            q_off   <= ba[15:0];
            q_hi    <= lane;
            tgt     <= (!card_present && (dt == T_ATTR || dt == T_TF)) ? T_EMPTY : dt;
            op_pending <= 1'b1;
            case (dt)
                T_FLASH: f_req <= 1'b1;
                T_ATTR:  a_req <= card_present;
                T_CTRL:  c_req <= 1'b1;
                T_EXCA:  e_req <= 1'b1;
                T_TF:    t_req <= card_present;
                default: ;   // unmapped: completes below with 0
            endcase
        end else begin
            logic        done;
            logic [15:0] r;
            done = 1'b0; r = 16'h0000;
            case (tgt)
                T_FLASH: begin done = f_ack; r = f_rd; end
                T_ATTR:  begin done = a_ack; r = a_rd; end
                T_CTRL:  begin done = c_ack; r = c_rd; end
                T_EXCA:  begin done = e_ack; r = e_rd; end
                T_TF:    begin done = t_ack; r = t_rd; end
                T_EMPTY: begin done = 1'b1;  r = 16'hffff; end
                default: done = 1'b1;
            endcase
            if (done) begin
                op_pending <= 1'b0;
                if (lane) l_rdata[31:16] <= r; else l_rdata[15:0] <= r;
                if (!lane && l_be[3:2] != 2'b00) begin
                    lane <= 1'b1;
                end else begin
                    busy      <= 1'b0;
                    cpu_ack   <= 1'b1;
                    cpu_rdata <= lane ? {r, l_rdata[15:0]} : {l_rdata[31:16], r};
                end
            end
        end
    end

    // ------------------------------------------------------------ blocks
    logic zoom_release;

    gnet_ctrl #(.CLK_HZ(CLK_HZ), .WD_TIMEOUT_S(WD_TIMEOUT_S)) u_ctrl (
        .clk, .rst,
        .op_req(c_req), .op_we(l_we), .op_reg(q_creg), .op_hi(q_hi), .op_bmask(q_bm),
        .op_wdata(q_wd), .op_ack(c_ack), .op_rdata(c_rd),
        .zoom_reset, .zoom_release, .bank_sel, .wd_reset,
        .wd_kick(dbg_wd_kick), .ctrl_q(dbg_ctrl));

    gnet_flash #(.CLK_HZ(CLK_HZ), .PRESET(FLASH_PRESET), .PROGRAM_AND(PROGRAM_AND)) u_flash (
        .clk, .rst,
        .op_req(f_req), .op_we(l_we), .op_chip(q_chip), .op_waddr(q_waddr), .op_wdata(q_wd),
        .op_ack(f_ack), .op_rdata(f_rd), .zoom_release,
        .mem_req(fmem_req), .mem_we(fmem_we), .mem_chip(fmem_chip), .mem_addr(fmem_addr),
        .mem_wdata(fmem_wdata), .mem_ack(fmem_ack), .mem_rdata(fmem_rdata), .busy(flash_busy));

    gnet_rf5c296 u_exca (
        .clk, .rst,
        .op_req(e_req), .op_we(l_we), .op_bmask(q_bm), .op_wdata(q_wd),
        .op_ack(e_ack), .op_rdata(e_rd),
        .card_present, .card_reset, .win_mismatch);

    gnet_ata #(.CLK_HZ(CLK_HZ)) u_ata (
        .clk, .rst, .card_reset,
        .attr_req(a_req), .attr_we(l_we), .attr_waddr(q_waddr[19:0]), .attr_wdata(q_wd),
        .attr_ack(a_ack), .attr_rdata(a_rd),
        .tf_req(t_req), .tf_we(l_we), .tf_off(q_off), .tf_bmask(q_bm), .tf_wdata(q_wd),
        .tf_ack(t_ack), .tf_rdata(t_rd),
        .meta_we, .meta_addr, .meta_wdata, .key_valid,
        .st_req(cmem_req), .st_we(cmem_we), .st_addr(cmem_addr), .st_wdata(cmem_wdata),
        .st_ack(cmem_ack), .st_rdata(cmem_rdata),
        .dirty_set, .dirty_hunk, .dirty_raddr, .dirty_rdata, .dirty_clear,
        .dbg_sec_cmd);
endmodule
