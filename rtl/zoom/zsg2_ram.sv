// Simple dual-port RAM (one write port, one registered read port, one
// clock) for the ZSG-2 (docs/zsg2_rtl.md). Plain write enable: Quartus 17
// infers M10K from this template (a byte-enable loop variant was not
// inferred and became flip-flops, docs/zsg2_rtl.md 6). Read during write
// of the same address returns the old data.
module zsg2_ram #(
    parameter AW = 8,
    parameter DW = 16
) (
    input  logic          clk,
    input  logic          we,
    input  logic [AW-1:0] waddr,
    input  logic [DW-1:0] wdata,
    input  logic [AW-1:0] raddr,
    output logic [DW-1:0] q
);
    logic [DW-1:0] mem [0:(1<<AW)-1];

`ifdef VERILATOR
    initial for (int i = 0; i < (1<<AW); i++) mem[i] = '0;
`endif

    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        q <= mem[raddr];
    end
endmodule
