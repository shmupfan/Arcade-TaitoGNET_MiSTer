// Taito Zoom board time base (docs/zoom_board_design.md 6).
//
// One virtual clock for the whole Zoom board: the MN10200 machine cycle
// (6.25 MHz, OSCI 12.5 MHz / 2). While the CPU runs, cycles come from its
// cycle stepper (mn10200 mc_step), so every sample boundary falls at a fixed
// CPU cycle count as on the PCB, where one 25 MHz crystal clocks all three
// chips (25 MHz / 768 = 192 machine cycles per sample). While the CPU is held
// in reset the cycles come from a real-time accumulator (the ZSG-2 keeps
// rendering in MAME while the MN10200 is held, taitogn.cpp:519-533).
//
// Outputs:
//   sample_tick  ZSG-2 sample tick. An external access of the MN10200 lands
//                at the end of its instruction in machine time (mn10200.cpp
//                charges every cycle before the access), so before a ZSG-2
//                access the bus asks look_req with the instruction's cycles;
//                a boundary inside that window is ticked at once (pre) and
//                not again when the stepped time reaches it.
//   bound        the boundary in stepped time (TMS57002 SYNC point).
//   cyc_cnt, bnd_tog, bnd_cnt   for the TMS57002 slot feeder (zoom_tmsfeed,
//                in the sound chips' clock domain): machine cycles stepped
//                (mod 65,536; the feeder uses bits 7:0, the board's host
//                event times all 16), a toggle per boundary, and cyc_cnt
//                (bits 7:0) after the cycle that reached the last boundary.
//
// Sample period: P_INT + REM_ADD / REM_MOD machine cycles. Board: 192 + 0.
// MAME 0.288 computes the ZSG-2 stream rate as 25 MHz / 768 in integers,
// 32,552 Hz (zsg2.cpp:137), which is 6,250,000 / 32,552 = 192 + 16 / 32,552
// cycles; the testbench uses that and loads the phase at each Zoom reset.
module zoom_tbase #(
    parameter int P_INT    = 192,
    parameter int REM_ADD  = 0,
    parameter int REM_MOD  = 1,
    parameter int RT_ADD   = 15625,     // real-time machine cycles: 6,250,000 / 33,868,800
    parameter int RT_SUB   = 84672
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        cpu_run,        // MN10200 out of reset
    input  logic        mc_step,        // one machine cycle stepped by the MN10200
    input  logic        look_req,       // hold until look_ack
    input  logic [4:0]  look_cyc,
    output logic        look_ack,
    output logic        sample_tick,
    output logic        bound,
    output logic [15:0] cyc_cnt,
    output logic        bnd_tog,
    output logic [7:0]  bnd_cnt,
    // testbench: load the phase (cycles to the next boundary, remainder)
    input  logic        ld,
    input  logic [8:0]  ld_left,
    input  logic [15:0] ld_rem
);
    localparam logic [17:0] K_RT_ADD  = RT_ADD;
    localparam logic [17:0] K_RT_SUB  = RT_SUB;
    localparam logic [16:0] K_REM_ADD = REM_ADD;
    localparam logic [16:0] K_REM_MOD = REM_MOD;
    localparam logic [8:0]  K_P_INT   = P_INT;

    // real-time cycle source while the CPU is held
    logic [17:0] rt_acc;
    logic        rt_cyc;
    always_ff @(posedge clk) begin
        if (rst) begin
            rt_acc <= '0;
            rt_cyc <= 1'b0;
        end else if (rt_acc + K_RT_ADD >= K_RT_SUB) begin
            rt_acc <= rt_acc + K_RT_ADD - K_RT_SUB;
            rt_cyc <= 1'b1;
        end else begin
            rt_acc <= rt_acc + K_RT_ADD;
            rt_cyc <= 1'b0;
        end
    end
    wire cyc = cpu_run ? mc_step : rt_cyc;

    // boundary counter
    logic [8:0]  left;                  // cycle events to the next boundary (>= 1)
    logic [15:0] rem;
    logic        pre;                   // next boundary already ticked by a lookahead
    wire  [16:0] rem_n  = {1'b0, rem} + K_REM_ADD;
    wire         rem_c  = rem_n >= K_REM_MOD;
    wire  [16:0] rem_w  = rem_n - K_REM_MOD;

    always_ff @(posedge clk) begin
        sample_tick <= 1'b0;
        bound       <= 1'b0;
        look_ack    <= 1'b0;
        if (rst) begin
            left <= K_P_INT;
            rem  <= '0;
            pre  <= 1'b0;
        end else if (ld) begin
            left <= ld_left;
            rem  <= ld_rem;
            pre  <= 1'b0;
        end else if (cyc) begin
            if (left == 9'd1) begin
                bound <= 1'b1;
                if (!pre) sample_tick <= 1'b1;
                pre  <= 1'b0;
                left <= K_P_INT + {8'd0, rem_c};
                rem  <= rem_c ? rem_w[15:0] : rem_n[15:0];
            end else
                left <= left - 9'd1;
        end else if (look_req && !look_ack) begin
            // cycles are never stepped during an access (the MN10200 starts an
            // instruction only when the previous one's cycles are stepped)
            if (!pre && {4'd0, look_cyc} >= left) begin
                sample_tick <= 1'b1;
                pre <= 1'b1;
            end
            look_ack <= 1'b1;
        end
    end

    // cycle and boundary counters for the TMS57002 slot feeder
    always_ff @(posedge clk) begin
        if (rst) begin
            cyc_cnt <= '0; bnd_tog <= 1'b0; bnd_cnt <= '0;
        end else if (cyc) begin
            cyc_cnt <= cyc_cnt + 16'd1;
            if (left == 9'd1 && !ld) begin
                bnd_tog <= ~bnd_tog;
                bnd_cnt <= cyc_cnt[7:0] + 8'd1;
            end
        end
    end
endmodule
