// Taito Zoom board: TMS57002 slot feeder (docs/zoom_board_design.md 6.3, 15).
//
// Runs in the sound chips' clock domain (clk_1x). The time base
// (zoom_tbase, in the MN10200's domain, clk_1x or clk_2x phase aligned)
// publishes the machine cycles stepped (cyc_cnt, mod 256), a toggle per
// sample boundary (bnd_tog) and cyc_cnt after the cycle that reached it
// (bnd_cnt). Each clock this block takes the new cycles, two instruction
// slots each, and the boundary between them, and delivers slots and SYNC in
// order, at most one pulse per STEP_GAP clocks (the TMS57002 core executes
// a slot in two clocks, docs/tms57002_rtl.md 1). Slots of the cycle that
// reaches a boundary come before its SYNC (slot j of sample k is at
// B_k + j / 2 cycles). Boundaries are at least 192 cycles apart, so at most
// one arrives per clock; the inputs are registers of a synchronous,
// phase-aligned clock and need no synchroniser.
//
// Host events (I5, docs/zoom_board_design.md 15): a TMS57002 host byte or a
// PLOAD/CLOAD change carries its time in slots (ev_slot = 2 x the machine
// cycle count at the end of the writing instruction, where MAME places the
// access). The feeder counts the slots it has delivered (del, the same
// origin: every stepped cycle gives two slots) and delivers the event, as
// ev_fire, once del has reached ev_slot, before any later slot and after a
// SYNC at the same point (a boundary at or before the access comes first,
// as for the ZSG-2 lookahead, zoom_tbase.sv), and only when the TMS57002
// has executed every slot given so far (tms_busy low), so the byte or pin
// change lands between exactly the two slots the PCB's one crystal puts it
// between. ev_fire is combinational from registers; the board applies the
// event on that edge.
module zoom_tmsfeed #(
    parameter int STEP_GAP = 2
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  cyc_cnt,
    input  logic        bnd_tog,
    input  logic [7:0]  bnd_cnt,
    input  logic        tms_ready,
    input  logic        tms_busy,       // TMS57002: slots given but not executed, or a host request open
    input  logic        ev_valid,       // head of the host event queue
    input  logic [16:0] ev_slot,
    output logic        ev_fire,
    output logic        tms_step,
    output logic        tms_sync,
    output logic        sync_pend,      // a SYNC waits behind undelivered slots
    output logic        dbg_sync_ovf    // sticky: a second SYNC queued behind a pending one
);
    localparam logic [1:0] K_GAP = STEP_GAP - 1;
    logic [7:0]  s_cyc;
    logic        s_bnd;
    logic [10:0] sa, sb;                // slots before the pending SYNC, after it
    logic        sp;                    // SYNC pending
    logic [1:0]  gap;
    logic [16:0] del;                   // slots delivered (mod 2^17)
    wire  [7:0]  d_all = cyc_cnt - s_cyc;
    wire  [7:0]  d_pre = bnd_cnt - s_cyc;
    wire  [7:0]  d_post = cyc_cnt - bnd_cnt;
    assign sync_pend = sp;

    // the event is due once the delivered slots reach its time (signed
    // distance, so a time already passed never waits for the counter to wrap)
    wire  [16:0] ev_dist = ev_slot - del;
    wire         ev_due  = ev_valid && (ev_dist == 17'd0 || ev_dist[16]);
    wire         do_sync = sp && sa == 11'd0;
    assign ev_fire = gap == 2'd0 && tms_ready && !do_sync && ev_due && !tms_busy;
    // a due event holds back every later slot until it is delivered
    wire         do_step = gap == 2'd0 && tms_ready && !do_sync && !ev_due && sa != 11'd0;

    always_ff @(posedge clk) begin
        tms_step <= 1'b0;
        tms_sync <= 1'b0;
        if (rst) begin
            s_cyc <= '0; s_bnd <= 1'b0;
            sa <= '0; sb <= '0; sp <= 1'b0; gap <= '0; del <= '0;
            dbg_sync_ovf <= 1'b0;
        end else begin : feed
            logic [10:0] na, nb;
            logic        np;
            na = sa; nb = sb; np = sp;
            // delivery
            if (gap != 2'd0) gap <= gap - 2'd1;
            else if (tms_ready && do_sync) begin
                tms_sync <= 1'b1;
                na = nb; nb = '0; np = 1'b0;
                gap <= K_GAP;
            end else if (ev_fire) begin
                gap <= K_GAP;
            end else if (do_step) begin
                tms_step <= 1'b1;
                na = na - 11'd1;
                del <= del + 17'd1;
                gap <= K_GAP;
            end
            // arrival
            if (bnd_tog != s_bnd) begin
                // a second SYNC while one is pending: merge (flagged)
                if (np) begin na = na + nb + {2'b0, d_pre, 1'b0}; nb = '0; dbg_sync_ovf <= 1'b1; end
                else    na = na + {2'b0, d_pre, 1'b0};
                np = 1'b1;
                nb = nb + {2'b0, d_post, 1'b0};
            end else if (np) nb = nb + {2'b0, d_all, 1'b0};
            else             na = na + {2'b0, d_all, 1'b0};
            s_cyc <= cyc_cnt;
            s_bnd <= bnd_tog;
            sa <= na; sb <= nb; sp <= np;
        end
    end
endmodule
