// Taito Zoom board output stage (docs/zoom_board_design.md 7).
//
// The TMS57002's SO1 pair arrives once per sample at the SYNC point of the
// board's virtual time (zoom_tbase). It goes through a small FIFO and is
// read at a real-time 25 MHz / 768 = 32,552.083 Hz tick: 15,625 /
// 16,257,024 per clk_1x clock, 1,040.45 clocks per sample, no drift. The
// FIFO absorbs the MN10200 pacer's lead or lag against real time. Reading
// starts with LEAD samples queued; an empty FIFO repeats the last sample
// and sets a sticky flag.
//
// Gain: unsigned Q1.15 per channel from zoom_host (MB87078 law or MAME's
// linear law), applied as (s x g) >> 15, which cannot overflow 16 bits for
// g <= 32768.
module zoom_out #(
    parameter int OUT_ADD = 15625,
    parameter int OUT_MOD = 16257024,
    parameter int LEAD    = 2,
    parameter int AW      = 3           // FIFO 2^AW entries
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        push,
    input  logic [15:0] in_l,
    input  logic [15:0] in_r,
    input  logic [15:0] gain_l,
    input  logic [15:0] gain_r,
    output logic        tick,           // one clock per output sample
    output logic signed [15:0] out_l,
    output logic signed [15:0] out_r,
    output logic        dbg_under,
    output logic        dbg_over,
    output logic [AW:0] dbg_level
);
    localparam logic [24:0] K_ADD  = OUT_ADD;
    localparam logic [24:0] K_MOD  = OUT_MOD;
    localparam logic [AW:0] K_FULL = 1 << AW;
    localparam logic [AW:0] K_LEAD = LEAD;
    logic [31:0] fifo [0:(1<<AW)-1];
    logic [AW:0] wp, rp;
    wire  [AW:0] level = wp - rp;
    assign dbg_level = level;
    logic        started;

    // real-time tick
    logic [24:0] acc;
    always_ff @(posedge clk) begin
        tick <= 1'b0;
        if (rst) acc <= '0;
        else if (acc + K_ADD >= K_MOD) begin
            acc  <= acc + K_ADD - K_MOD;
            tick <= 1'b1;
        end else acc <= acc + K_ADD;
    end

    // FIFO
    always_ff @(posedge clk)
        if (push) fifo[wp[AW-1:0]] <= {in_r, in_l};

    logic [31:0] cur;
    logic        mul_go;
    logic        mul_ch;
    always_ff @(posedge clk) begin
        mul_go <= 1'b0;
        if (rst) begin
            wp <= '0; rp <= '0; started <= 1'b0;
            cur <= '0;
            dbg_under <= 1'b0; dbg_over <= 1'b0;
        end else begin
            if (push) begin
                if (level == K_FULL) begin
                    rp <= rp + 1'd1;            // full: drop the oldest
                    dbg_over <= 1'b1;
                end
                wp <= wp + 1'd1;
            end
            if (!started && level >= K_LEAD) started <= 1'b1;
            if (tick) begin
                mul_go <= 1'b1;
                if (started && level != '0 && !(push && level == K_FULL)) begin
                    cur <= fifo[rp[AW-1:0]];
                    rp  <= rp + 1'd1;
                end else if (started) dbg_under <= 1'b1;
            end
        end
    end

    // gain: one multiplier, left then right
    wire signed [15:0] m_s = mul_ch ? $signed(cur[31:16]) : $signed(cur[15:0]);
    wire        [16:0] m_g = mul_ch ? {1'b0, gain_r} : {1'b0, gain_l};
    wire signed [33:0] m_p = m_s * $signed({1'b0, m_g});
    always_ff @(posedge clk) begin
        if (rst) begin
            out_l <= '0; out_r <= '0; mul_ch <= 1'b0;
        end else if (mul_go) begin
            out_l  <= m_p[30:15];
            mul_ch <= 1'b1;
        end else if (mul_ch) begin
            out_r  <= m_p[30:15];
            mul_ch <= 1'b0;
        end
    end
endmodule
