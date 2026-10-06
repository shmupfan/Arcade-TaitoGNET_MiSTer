// Sim-only SystemVerilog copy of rtl/gnet/zn2_ch3_arb.vhd (gnet-cpu50
// e775367): SDRAM channel 3 shared by the downloads (a) and zn2_board's
// flash storage port (b) on clk_cpu. The full-system top uses it with a
// tied off (no downloads in a non-DL build), so flash accesses see the same
// request, answer and gap cycles as PSX.sv GNET_ZN2 + GNET_CPU50.
module fs_ch3_arb (
    input  logic        clk,
    input  logic        a_req,
    input  logic [26:0] a_addr,
    input  logic [31:0] a_din,
    input  logic        a_rnw,
    input  logic [3:0]  a_be,
    output logic        a_ready = 1'b0,
    input  logic        b_req,
    input  logic [26:0] b_addr,
    input  logic [31:0] b_din,
    input  logic        b_rnw,
    input  logic [3:0]  b_be,
    output logic        b_ready = 1'b0,
    output logic        ch3_req = 1'b0,
    output logic [26:0] ch3_addr = '0,
    output logic [31:0] ch3_din = '0,
    output logic        ch3_rnw = 1'b0,
    output logic [3:0]  ch3_be = '0,
    input  logic        ch3_ready
);
    typedef enum logic [1:0] {IDLE, BUSY_A, BUSY_B, GAP} t_state;
    t_state state = IDLE;
    logic a_pend = 1'b0, b_pend = 1'b0;

    always_ff @(posedge clk) begin
        ch3_req <= 1'b0;
        a_ready <= 1'b0;
        b_ready <= 1'b0;
        if (a_req) a_pend <= 1'b1;
        if (b_req) b_pend <= 1'b1;
        case (state)
            IDLE:
                if (a_pend) begin
                    a_pend <= 1'b0;
                    ch3_addr <= a_addr; ch3_din <= a_din; ch3_rnw <= a_rnw; ch3_be <= a_be;
                    ch3_req <= 1'b1; state <= BUSY_A;
                end else if (b_pend) begin
                    b_pend <= 1'b0;
                    ch3_addr <= b_addr; ch3_din <= b_din; ch3_rnw <= b_rnw; ch3_be <= b_be;
                    ch3_req <= 1'b1; state <= BUSY_B;
                end
            BUSY_A: if (ch3_ready) begin a_ready <= 1'b1; state <= GAP; end
            BUSY_B: if (ch3_ready) begin b_ready <= 1'b1; state <= GAP; end
            GAP:    state <= IDLE;
        endcase
    end
endmodule
