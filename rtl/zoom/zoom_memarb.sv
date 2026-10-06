// Taito Zoom board: wave and program memory arbiter (docs/zoom_board_design.md 5).
//
// Two clients share one 64-bit line port into the flash area (SDRAM in the
// test build, DDR3 later): the MN10200 program cache (client P) and the
// ZSG-2 prefetcher (client Z). Protocol on every side: req and line held
// until ready; responses (rvalid with 64-bit data) come back in request
// order, any latency, several outstanding. The arbiter grants P first: a
// cache miss stalls the CPU at once, while a ZSG-2 prefetch has a sample
// period of slack (docs/zsg2_rtl.md 5). A small FIFO remembers the owner of
// each outstanding request to route the responses.
//
// The line port has no byte enables: every request reads a whole 64-bit
// line. Whatever carries it to SDRAM must issue full-width reads (byte
// enables 1111, see zoom_line32.sv); partial read masks blank data on real
// SDRAM.
module zoom_memarb #(
    parameter int OW = 3                // up to 2^OW requests outstanding downstream
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        p_req,
    input  logic [20:0] p_line,
    output logic        p_ready,
    output logic        p_rvalid,
    input  logic        z_req,
    input  logic [20:0] z_line,
    output logic        z_ready,
    output logic        z_rvalid,
    output logic        m_req,
    output logic [20:0] m_line,
    input  logic        m_ready,
    input  logic        m_rvalid,
    output logic        dbg_ovf
);
    logic [(1<<OW)-1:0] own;            // owner bit per slot: 1 = P
    logic [OW:0]        wp, rp;
    localparam logic [OW:0] K_FULL = 1 << OW;
    wire  [OW:0]        occ  = wp - rp;
    wire                full = occ == K_FULL;

    wire sel_p = p_req;
    assign m_req   = (p_req || z_req) && !full;
    assign m_line  = sel_p ? p_line : z_line;
    assign p_ready = m_ready && !full && sel_p;
    assign z_ready = m_ready && !full && !sel_p && z_req;

    wire head_p = own[rp[OW-1:0]];
    assign p_rvalid = m_rvalid && head_p;
    assign z_rvalid = m_rvalid && !head_p;

    always_ff @(posedge clk) begin
        if (rst) begin
            wp <= '0; rp <= '0; dbg_ovf <= 1'b0;
        end else begin
            if (m_req && m_ready) begin
                own[wp[OW-1:0]] <= sel_p;
                wp <= wp + 1'd1;
            end
            if (m_rvalid) begin
                if (wp == rp) dbg_ovf <= 1'b1;
                rp <= rp + 1'd1;
            end
        end
    end
endmodule
