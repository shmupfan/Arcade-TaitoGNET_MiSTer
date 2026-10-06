// Taito Zoom board: MN10200 bus decoder (docs/zoom_board_design.md 2 and 4).
//
// Map (taito_zm.cpp:114-125, MAME 0.288):
//   0x080000-0x0FFFFF  program flash U27, read only (program cache)
//   0x400000-0x41FFFF  work RAM (32 KB on the PCB, mirrored; zoom_wram)
//   0x800000-0x8007FF  ZSG-2, 16-bit (zsg2)
//   0xC00000           TMS57002 data port, 8-bit, lane 0 (writes only in
//                      the firmware, design study 2.3)
//   0xE00000-0xE000FF  M66220FP mailbox, byte addressed (zoom_mbox)
//   anything else      reads 0, writes ignored (MAME unmapped)
//
// The core holds bus_rd / bus_wr until bus_ack. Program cache hits and the
// work RAM answer in the next clock with a combinational ack (their RAMs
// read on clk2x); everything else answers through a registered ack.
// Before a ZSG-2 access the decoder asks the time base to tick any sample
// boundary that MAME would place before the access (zoom_tbase look_*),
// then waits a clock so the ZSG-2 has counted the tick.
module zoom_bus #(
    parameter int WRAM_AW = 14
) (
    input  logic        clk,
    input  logic        rst,
    // MN10200
    input  logic [23:0] bus_addr,
    input  logic        bus_rd,
    input  logic        bus_wr,
    input  logic [1:0]  bus_be,
    input  logic [15:0] bus_wdata,
    output logic [15:0] bus_rdata,
    output logic        bus_ack,
    input  logic [4:0]  acc_cyc,
    // program cache
    output logic        pc_rd,
    input  logic        pc_hit,
    input  logic [15:0] pc_q,
    // work RAM
    output logic        wr_we,
    input  logic [15:0] wr_q,
    input  logic        wr_cur,
    // ZSG-2
    output logic        z_rd,
    output logic        z_wr,
    input  logic [15:0] z_rdata,
    input  logic        z_ack,
    // time base lookahead
    output logic        look_req,
    output logic [4:0]  look_cyc,
    input  logic        look_ack,
    input  logic        t_idle,         // the sample tick has reached the ZSG-2's clock domain
    input  logic        s_en,           // this clock ends on a ZSG-2 clock edge (1 when one clock)
    // TMS57002 data port
    output logic        tms_wr,
    // mailbox (port B; address and data come from the bus)
    output logic        mb_we,
    input  logic [15:0] mb_q,
    // debug
    output logic        dbg_wram_hi,    // sticky: work RAM access above the RAM size
    output logic        dbg_unmapped,   // sticky: access to an unmapped address
    output logic        dbg_tms_rd      // sticky: TMS57002 data port read
);
    wire req   = bus_rd || bus_wr;
    wire r_prg = bus_addr[23:19] == 5'b00001;
    wire r_ram = bus_addr[23:17] == 7'b0100000;
    wire r_zsg = bus_addr[23:11] == 13'h1000;
    wire r_tms = bus_addr[23:1]  == 23'h600000;
    wire r_mb  = bus_addr[23:8]  == 16'hE000;

    assign pc_rd = bus_rd && r_prg;
    assign wr_we = bus_wr && r_ram;
    wire   fast  = (bus_rd && r_prg && pc_hit) || (bus_rd && r_ram && wr_cur) || (bus_wr && r_ram);

    typedef enum logic [2:0] { B_IDLE, B_ZLOOK, B_ZWAIT, B_ZACC, B_MBRD } bst_t;
    bst_t        st;
    logic        ack_r;
    logic [15:0] rd_r;

    assign look_req = (st == B_ZLOOK);
    assign look_cyc = acc_cyc;
    assign mb_we    = (st == B_IDLE) && bus_wr && r_mb && !ack_r;
    assign tms_wr   = (st == B_IDLE) && bus_wr && r_tms && bus_be[0] && !ack_r;
    assign bus_ack  = ack_r || fast;
    assign bus_rdata = ack_r ? rd_r : (r_ram ? wr_q : pc_q);

    always_ff @(posedge clk) begin
        ack_r <= 1'b0;
        if (rst) begin
            st   <= B_IDLE;
            z_rd <= 1'b0;
            z_wr <= 1'b0;
            dbg_wram_hi  <= 1'b0;
            dbg_unmapped <= 1'b0;
            dbg_tms_rd   <= 1'b0;
        end else begin
            if (req && r_ram && bus_addr[16:WRAM_AW+1] != '0) dbg_wram_hi <= 1'b1;
            case (st)
                B_IDLE: if (req && !ack_r && !fast) begin
                    if (r_zsg) st <= B_ZLOOK;
                    else if (r_mb) begin
                        if (bus_wr) ack_r <= 1'b1;
                        else st <= B_MBRD;
                    end else if (r_tms) begin
                        if (bus_rd) dbg_tms_rd <= 1'b1;
                        rd_r  <= 16'h0000;
                        ack_r <= 1'b1;
                    end else if (r_prg) begin
                        if (bus_wr) begin               // the flash is read-only to the MN10200
                            rd_r  <= 16'h0000;
                            ack_r <= 1'b1;
                        end                             // read miss: the cache fills, then hits
                    end else if (!r_ram) begin
                        dbg_unmapped <= 1'b1;
                        rd_r  <= 16'h0000;
                        ack_r <= 1'b1;
                    end
                end
                B_ZLOOK: if (look_ack) st <= B_ZWAIT;
                B_ZWAIT: if (t_idle) begin
                    z_rd <= bus_rd;
                    z_wr <= bus_wr;
                    st   <= B_ZACC;
                end
                // the ZSG-2's acknowledge lasts one of its clocks: take it once
                B_ZACC: if (z_ack && s_en) begin
                    z_rd  <= 1'b0;
                    z_wr  <= 1'b0;
                    rd_r  <= z_rdata;
                    ack_r <= 1'b1;
                    st    <= B_IDLE;
                end
                B_MBRD: begin
                    rd_r  <= mb_q;
                    ack_r <= 1'b1;
                    st    <= B_IDLE;
                end
                default: st <= B_IDLE;
            endcase
        end
    end
endmodule
