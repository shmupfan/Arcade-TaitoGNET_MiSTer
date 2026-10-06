// Taito Zoom board: MN10200 work RAM (docs/zoom_board_design.md 4.2).
//
// The FC PCB carries one LH52B256 (32 KB, PLAN.md R7); MAME maps 128 KB at
// 0x400000-0x41FFFF (taito_zm.cpp:121). 2^AW words of 16 bits, mirrored
// across the window; AW = 14 is the PCB's 32 KB. The firmware stays below
// 0x408000 (docs/mn10200_design.md 3.4); the bus decoder flags any access
// above the RAM size.
//
// Read on clk2x (see zoom_pcache.sv): data for the address the core put on
// the bus at a clk edge is valid before the next clk edge. Writes also land
// on clk2x edges; a write held for one clk cycle is written twice with the
// same data, which is harmless.
module zoom_wram #(
    parameter int AW = 14
) (
    input  logic          clk2x,
    input  logic [AW-1:0] a,            // word address
    input  logic          we,
    input  logic [1:0]    be,
    input  logic [15:0]   wd,
    output logic [15:0]   q,
    output logic          cur           // q belongs to address a
);
    logic [1:0][7:0] mem [0:(1<<AW)-1];
    logic [AW-1:0]   qa;

`ifdef VERILATOR
    initial for (int i = 0; i < (1<<AW); i++) mem[i] = '0;
`endif

    always_ff @(posedge clk2x) begin
        if (we) begin
            if (be[0]) mem[a][0] <= wd[7:0];
            if (be[1]) mem[a][1] <= wd[15:8];
        end
        q  <= mem[a];
        qa <= a;
    end
    assign cur = (qa == a);
endmodule
