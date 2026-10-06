// MN10200 register file D0-D3 (0-3), A0-A3 (4-7), 24 bits
// (docs/mn10200_design.md 5.4). One write port, four asynchronous read
// ports. MLAB = 1: four MLAB copies written together (the design study's
// layout); MLAB = 0: flip-flops with read multiplexers. No reset: the core
// clears the file through the write port after reset.
module mn10200_rf #(
    parameter MLAB = 1
) (
    input  logic        clk,
    input  logic        we,
    input  logic [2:0]  wa,
    input  logic [23:0] wd,
    input  logic [2:0]  ra0, ra1, ra2, ra3,
    output logic [23:0] rd0, rd1, rd2, rd3,
    output logic [191:0] dbg            // {A3..A0, D3..D0}; 0 in MLAB synthesis builds
);
    generate
        if (MLAB) begin : g_mlab
            (* ramstyle = "MLAB, no_rw_check" *) logic [23:0] m0 [0:7];
            (* ramstyle = "MLAB, no_rw_check" *) logic [23:0] m1 [0:7];
            (* ramstyle = "MLAB, no_rw_check" *) logic [23:0] m2 [0:7];
            (* ramstyle = "MLAB, no_rw_check" *) logic [23:0] m3 [0:7];
            always_ff @(posedge clk) begin
                if (we) begin
                    m0[wa] <= wd;
                    m1[wa] <= wd;
                    m2[wa] <= wd;
                    m3[wa] <= wd;
                end
            end
            assign rd0 = m0[ra0];
            assign rd1 = m1[ra1];
            assign rd2 = m2[ra2];
            assign rd3 = m3[ra3];
`ifdef VERILATOR
            assign dbg = {m0[7], m0[6], m0[5], m0[4], m0[3], m0[2], m0[1], m0[0]};
`else
            assign dbg = 192'h0;
`endif
        end else begin : g_ff
            logic [23:0] r [0:7];
            always_ff @(posedge clk) if (we) r[wa] <= wd;
            assign rd0 = r[ra0];
            assign rd1 = r[ra1];
            assign rd2 = r[ra2];
            assign rd3 = r[ra3];
            assign dbg = {r[7], r[6], r[5], r[4], r[3], r[2], r[1], r[0]};
        end
    endgenerate
endmodule
