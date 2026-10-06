// Taito Zoom board: MN10200 program cache for flash U27 (512 KB at
// 0x080000-0x0FFFFF, taito_zm.cpp:116-117), docs/zoom_board_design.md 4.
//
// Direct mapped, 2^IDX_W lines of 2^LN_W 64-bit beats. The tag and data RAMs
// are read on clk2x, so a hit is answered in the clock after the MN10200
// puts the address on its bus (the next-clock bus the core needs to keep
// real time, docs/mn10200_rtl.md 7 item 2):
//   - clk2x is clk x 2, phase aligned (the PSX core's scratchpad scheme,
//     docs/r1_cpu_domain_design.md table 2.1). At the clk2x edge in the
//     middle of a clk cycle the RAMs sample the address the core registered
//     at the clk edge; data and tag are valid before the next clk edge.
//   - Each RAM output carries the index it was read at; hit requires that
//     index to equal the current address, so a stale output never hits.
// A miss fills the whole line from the memory port (in-order 64-bit beats)
// and writes the tag last; the held bus request then hits.
//
// Invalidation: inval starts a sweep that clears every tag (one per clock);
// hit stays low meanwhile. The board sweeps while the Zoom is held in reset,
// which is the only time the main CPU writes U27 (MAME traces, all six
// games, docs/zoom_board_design.md 3.3).
module zoom_pcache #(
    parameter int IDX_W = 9,                    // 2^IDX_W lines
    parameter int LN_W  = 1,                    // 2^LN_W beats of 8 bytes per line
    parameter logic [23:0] BASE = 24'h200000    // U27 in the flash area (byte address)
) (
    input  logic        clk,
    input  logic        clk2x,
    input  logic        rst,
    input  logic        inval,
    output logic        busy,
    input  logic [18:1] a,              // word address in U27
    input  logic        rd,             // read request to the U27 window
    output logic        hit,
    output logic [15:0] q,
    output logic        miss,           // pulse: a fill starts
    // memory: 64-bit beats, req/line held until ready, rvalid in order
    output logic        mem_req,
    output logic [20:0] mem_line,       // byte address bits 23:3
    input  logic        mem_ready,
    input  logic        mem_rvalid,
    input  logic        men,            // this clock ends on a memory-port clock edge (1 when one clock)
    input  logic [63:0] mem_rdata
);
    localparam int OFF_W = LN_W + 3;            // byte offset in a line
    localparam int TAG_W = 19 - OFF_W - IDX_W;
    localparam int NB    = 1 << LN_W;

    localparam logic [LN_W:0] K_NB   = NB;
    localparam logic [LN_W:0] K_LAST = NB - 1;
    wire [IDX_W-1:0] idx  = a[OFF_W+IDX_W-1:OFF_W];
    wire [TAG_W-1:0] tag  = a[18:OFF_W+IDX_W];
    wire [IDX_W+LN_W-1:0] didx = a[OFF_W+IDX_W-1:3];

    // ------------------------------------------------------------------ RAMs (clk2x)
    logic             t_we;
    logic [IDX_W-1:0] t_wa;
    logic [TAG_W:0]   t_wd;                     // {valid, tag}
    logic             d_we;
    logic [IDX_W+LN_W-1:0] d_wa;
    logic [63:0]      d_wd;

    logic [TAG_W:0]   tag_mem [0:(1<<IDX_W)-1];
    logic [63:0]      dat_mem [0:(1<<(IDX_W+LN_W))-1];
    logic [TAG_W:0]   t_q;
    logic [IDX_W-1:0] t_qi;
    logic [63:0]      d_q;
    logic [IDX_W+LN_W-1:0] d_qi;

`ifdef VERILATOR
    initial begin
        for (int i = 0; i < (1<<IDX_W); i++) tag_mem[i] = '0;
        for (int i = 0; i < (1<<(IDX_W+LN_W)); i++) dat_mem[i] = '0;
    end
`endif

    always_ff @(posedge clk2x) begin
        if (t_we) tag_mem[t_wa] <= t_wd;
        t_q  <= tag_mem[idx];
        t_qi <= idx;
    end
    always_ff @(posedge clk2x) begin
        if (d_we) dat_mem[d_wa] <= d_wd;
        d_q  <= dat_mem[didx];
        d_qi <= didx;
    end

    wire cur   = (t_qi == idx) && (d_qi == didx);  // outputs belong to this address
    wire match = t_q[TAG_W] && (t_q[TAG_W-1:0] == tag);
    assign hit = !busy && cur && match;
    assign q   = d_q[{a[2:1], 4'd0} +: 16];

    // ------------------------------------------------------------------ fill and sweep (clk)
    typedef enum logic [1:0] { F_IDLE, F_FILL, F_WAIT, F_SWEEP } fst_t;
    fst_t fst;
    logic [IDX_W-1:0] f_idx;
    logic [TAG_W-1:0] f_tag;
    logic [LN_W:0]    f_rq, f_rs;               // beats requested, received
    logic [1:0]       f_w;
    logic             inv_p;                    // invalidation requested during a fill

    assign busy     = (fst == F_SWEEP);
    assign mem_req  = (fst == F_FILL) && (f_rq != K_NB);
    // {tag, index, beat} is the 16-bit line number within U27 (bits 18:3)
    assign mem_line = BASE[23:3] + {5'd0, f_tag, f_idx, f_rq[LN_W-1:0]};

    always_ff @(posedge clk) begin
        miss <= 1'b0;
        t_we <= 1'b0;
        d_we <= 1'b0;
        if (rst) begin
            fst  <= F_SWEEP;                    // power-up: clear the tags
            f_idx <= '0;
            inv_p <= 1'b0;
        end else begin
            if (inval) inv_p <= 1'b1;
            case (fst)
                F_IDLE: begin
                    if (inval || inv_p) begin
                        fst <= F_SWEEP;
                        f_idx <= '0;
                        inv_p <= 1'b0;
                    end else if (rd && cur && !match) begin
                        f_idx <= idx;
                        f_tag <= tag;
                        f_rq  <= '0;
                        f_rs  <= '0;
                        miss  <= 1'b1;
                        fst   <= F_FILL;
                    end
                end
                F_FILL: begin
                    if (mem_req && mem_ready && men) f_rq <= f_rq + 1'd1;
                    if (mem_rvalid && men) begin
                        d_we <= 1'b1;
                        d_wa <= {f_idx, f_rs[LN_W-1:0]};
                        d_wd <= mem_rdata;
                        f_rs <= f_rs + 1'd1;
                        if (f_rs == K_LAST) begin
                            t_we <= 1'b1;
                            t_wa <= f_idx;
                            t_wd <= {1'b1, f_tag};
                            f_w  <= 2'd2;
                            fst  <= F_WAIT;
                        end
                    end
                end
                F_WAIT: begin
                    // the tag write and the re-read of the held address
                    f_w <= f_w - 2'd1;
                    if (f_w == 2'd0) fst <= F_IDLE;
                end
                F_SWEEP: begin
                    t_we <= 1'b1;
                    t_wa <= f_idx;
                    t_wd <= '0;
                    f_idx <= f_idx + 1'd1;
                    if (f_idx == '1) begin
                        f_w <= 2'd2;
                        fst <= F_WAIT;
                    end
                end
            endcase
        end
    end
endmodule
