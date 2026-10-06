// Taito Zoom board: M66220FP mailbox (docs/zoom_board_design.md 3.2).
//
// The M66220FP is a 256 x 8 RAM with two independent asynchronous ports and
// an address-collision arbiter that drives Not Ready on the later port
// (Mitsubishi M66220SP/FP data sheet pp.3-3 to 3-8). It has no flags or
// interrupts. MAME models it as a plain 256-byte shared RAM
// (taito_zm.cpp:88-96, 124; taitogn.cpp:487), and so does this block: a
// true dual-port RAM, one port per side. The collision arbiter is not
// modelled (Not Ready never reaches either CPU in MAME).
//
// Byte b of the mailbox is word b >> 1, lane b & 1:
//   - MN10200 side (0xE00000-0xE000FF, byte addressed): word = address
//     bits 7:1, byte enables as on its bus;
//   - main CPU side (0x1FBE0000-0x1FBE01FF, umask32 0x00FF00FF): byte lane
//     0 of 32-bit word k is byte 2k, lane 2 is byte 2k + 1, so word k with
//     the lo byte from lane 0 and the hi byte from lane 2 (as zn2_io's stub
//     on branch zn2-layer).
// Two clocks: hclk for the main-CPU side, clk for the Zoom side.
module zoom_mbox (
    input  logic        hclk,
    input  logic        h_we,
    input  logic [6:0]  h_a,
    input  logic [1:0]  h_be,           // {lane 2, lane 0}
    input  logic [15:0] h_wd,
    output logic [15:0] h_q,
    input  logic        clk,
    input  logic        z_we,
    input  logic [6:0]  z_a,
    input  logic [1:0]  z_be,
    input  logic [15:0] z_wd,
    output logic [15:0] z_q
);
    reg [7:0] lo [0:127];
    reg [7:0] hi [0:127];

`ifdef VERILATOR
    initial for (int i = 0; i < 128; i++) begin lo[i] = '0; hi[i] = '0; end
`endif

    // Quartus 17 true dual-port template (Quartus Handbook HDL templates,
    // "True Dual-Port RAM with dual clocks"): plain always blocks, one per
    // port and clock, one RAM per byte lane, write-through on the writing
    // port (the outputs are only used on read cycles, so the read-during-
    // write mode does not matter here)
    logic [7:0] h_ql, h_qh, z_ql, z_qh;
    always @(posedge hclk) begin
        if (h_we && h_be[0]) begin lo[h_a] <= h_wd[7:0]; h_ql <= h_wd[7:0]; end
        else h_ql <= lo[h_a];
    end
    always @(posedge hclk) begin
        if (h_we && h_be[1]) begin hi[h_a] <= h_wd[15:8]; h_qh <= h_wd[15:8]; end
        else h_qh <= hi[h_a];
    end
    always @(posedge clk) begin
        if (z_we && z_be[0]) begin lo[z_a] <= z_wd[7:0]; z_ql <= z_wd[7:0]; end
        else z_ql <= lo[z_a];
    end
    always @(posedge clk) begin
        if (z_we && z_be[1]) begin hi[z_a] <= z_wd[15:8]; z_qh <= z_wd[15:8]; end
        else z_qh <= hi[z_a];
    end
    assign h_q = {h_qh, h_ql};
    assign z_q = {z_qh, z_ql};
endmodule
