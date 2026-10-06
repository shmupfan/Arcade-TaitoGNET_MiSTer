// ZSG-2 sample memory port (docs/zsg2_rtl.md 3.3): per-channel prefetch
// request queue, ROM readback (0x638-0x63E) and the line buffer fill.
//
// Memory interface: one 64-bit line per request (line L = bytes 8L..8L+7 of
// the three wave flashes stored contiguously as little-endian 16-bit words,
// so block 2L is rdata[31:0] and block 2L+1 is rdata[63:32]). mem_req and
// mem_addr hold until mem_ready; responses (mem_rvalid) return in request
// order, any latency, up to INFL requests outstanding.
module zsg2_fetch #(
    parameter logic [23:0] MEM_BLOCKS = 24'h180000,  // 32-bit blocks present (MAME m_mem_blocks)
    parameter RQ_AW = 6,                             // request queue depth 2^RQ_AW
    parameter INFL  = 4                              // requests outstanding at most (1 to 8)
) (
    input  logic        clk,
    input  logic        rst,
    // prefetch requests from the sequencer (one per clock at most)
    input  logic        enq,
    input  logic [5:0]  enq_ch,
    input  logic [22:0] enq_line,
    output logic        enq_full,
    // readback (control registers 0x1c-0x1f)
    input  logic        rb_req,        // the read address changed: fetch it
    input  logic [29:0] rb_addr,       // 32-bit block address
    output logic [31:0] rb_data,
    output logic        rb_valid,
    // line buffer write port: {line, data}
    output logic        lb_we,
    output logic [5:0]  lb_waddr,
    output logic [86:0] lb_wdata,
    // memory
    output logic        mem_req,
    output logic [22:0] mem_addr,
    input  logic        mem_ready,
    input  logic        mem_rvalid,
    input  logic [63:0] mem_rdata
);
    // request queue (MLAB)
    (* ramstyle = "MLAB, no_rw_check" *) logic [28:0] rq [0:(1<<RQ_AW)-1];
    logic [RQ_AW:0]   rq_wp, rq_rp;
    wire              rq_empty = (rq_wp == rq_rp);
    assign enq_full = (rq_wp[RQ_AW-1:0] == rq_rp[RQ_AW-1:0]) && (rq_wp[RQ_AW] != rq_rp[RQ_AW]);
    wire  [28:0]      rq_head = rq[rq_rp[RQ_AW-1:0]];

    always_ff @(posedge clk)
        if (enq && !enq_full) rq[rq_wp[RQ_AW-1:0]] <= {enq_ch, enq_line};

    // readback state
    logic [29:0] rb_a;
    logic        rb_pend, rb_zero;
    logic [4:0]  rb_cnt;
    logic [31:0] rb_d;
    wire         rb_oor = (rb_addr >= {6'd0, MEM_BLOCKS});
    assign rb_valid = !rb_pend && (rb_cnt == 5'd0);
    assign rb_data  = rb_zero ? 32'd0 : rb_d;

    // outstanding requests, in order: {rb, half, ch, line}
    localparam IW = (INFL > 1) ? $clog2(INFL) : 1;
    logic [30:0] infl [0:INFL-1];
    logic [4:0]  infl_n;
    wire  [30:0] infl_head = infl[0];

    // responses still owed for requests issued before a reset: dropped
    logic [4:0] drop;
    wire rv = mem_rvalid && (drop == 5'd0);
    wire issue = mem_req && mem_ready;
    wire can_load = !mem_req || issue;
    wire take_rb = can_load && rb_pend && (infl_n + (issue ? 5'd1 : 5'd0) - (rv ? 5'd1 : 5'd0) < INFL[4:0]);
    wire take_rq = can_load && !rb_pend && !rq_empty && (infl_n + (issue ? 5'd1 : 5'd0) - (rv ? 5'd1 : 5'd0) < INFL[4:0]);

    logic [30:0] req_tag;   // what the held request is: {rb, half, ch, line}

    always_ff @(posedge clk) begin
        lb_we <= 1'b0;
        if (mem_rvalid && drop != 5'd0) drop <= drop - 5'd1;
        if (rst) begin
            drop    <= drop + infl_n + (issue ? 5'd1 : 5'd0) - ((mem_rvalid && (drop != 5'd0 || infl_n != 5'd0)) ? 5'd1 : 5'd0);
            rq_wp   <= '0;
            rq_rp   <= '0;
            mem_req <= 1'b0;
            infl_n  <= '0;
            rb_pend <= 1'b0;
            rb_zero <= 1'b0;
            rb_cnt  <= '0;
            rb_d    <= '0;
            rb_a    <= '0;
        end else begin
            if (enq && !enq_full) rq_wp <= rq_wp + 1'd1;

            // readback request: the newest address wins
            if (rb_req) begin
                rb_a    <= rb_addr;
                rb_zero <= rb_oor;
                rb_pend <= !rb_oor;
            end

            // load the request register
            if (issue && !take_rb && !take_rq) mem_req <= 1'b0;
            if (take_rb && !rb_req) begin
                mem_req  <= 1'b1;
                mem_addr <= rb_a[23:1];
                req_tag  <= {1'b1, rb_a[0], 6'd0, rb_a[23:1]};
                rb_pend  <= 1'b0;
            end else if (take_rq) begin
                mem_req  <= 1'b1;
                mem_addr <= rq_head[22:0];
                req_tag  <= {1'b0, 1'b0, rq_head[28:23], rq_head[22:0]};
                rq_rp    <= rq_rp + 1'd1;
            end else if (take_rb) begin
                // rb_req in the same clock: wait one clock for the new address
                if (issue) mem_req <= 1'b0;
            end

            // outstanding list: push on issue, pop on response
            if (rv) begin
                for (int i = 0; i < INFL-1; i++) infl[i] <= infl[i+1];
                if (issue) infl[IW'(infl_n - 5'd1)] <= req_tag;
            end else if (issue) begin
                infl[IW'(infl_n)] <= req_tag;
            end
            infl_n <= infl_n + (issue ? 5'd1 : 5'd0) - (rv ? 5'd1 : 5'd0);
            // readback fetches loaded and not yet answered
            rb_cnt <= rb_cnt + ((take_rb && !rb_req) ? 5'd1 : 5'd0) - ((rv && infl_head[30]) ? 5'd1 : 5'd0);

            if (rv) begin
                if (infl_head[30]) begin
                    rb_d <= infl_head[29] ? mem_rdata[63:32] : mem_rdata[31:0];
                end else begin
                    lb_we    <= 1'b1;
                    lb_waddr <= infl_head[28:23];
                    lb_wdata <= {infl_head[22:0], mem_rdata};
                end
            end
        end
    end
endmodule
