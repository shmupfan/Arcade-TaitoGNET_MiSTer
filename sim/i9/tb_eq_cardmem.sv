// zn2_cardmem with CARD_JOURNAL = false against the alpha4 zn2_cardmem
// (both through ghdl --synth): 20 million clocks of random inputs, every
// output compared every clock. UL_REQ = 1 is the negative control (the
// journal client active must make the outputs differ).
`timescale 1ns/1ps
module tb_eq_cardmem;
`ifdef UL_ON
  localparam logic UL_REQ = 1'b1;
`else
  localparam logic UL_REQ = 1'b0;
`endif
  logic clk = 0; always #5 clk = ~clk;
  logic reset, dl_wr, cm_req, cm_we, mem_ack, mem_DOUT_READY;
  logic [25:0] dl_addr; logic [15:0] dl_data, cm_wdata; logic [24:0] cm_addr; logic [63:0] mem_DOUT;
  wire a_dl_busy, b_dl_busy, a_cm_ack, b_cm_ack, a_req, b_req, a_we, b_we, a_rd, b_rd;
  wire [15:0] a_cm_rdata, b_cm_rdata; wire [7:0] a_bc, b_bc, a_be, b_be; wire [27:0] a_ad, b_ad; wire [63:0] a_din, b_din;
  gold a(.clk2x(clk), .reset, .dl_wr, .dl_addr, .dl_data, .dl_busy(a_dl_busy), .cm_req, .cm_we, .cm_addr, .cm_wdata,
    .cm_ack(a_cm_ack), .cm_rdata(a_cm_rdata), .mem_request(a_req), .mem_BURSTCNT(a_bc), .mem_ADDR(a_ad), .mem_DIN(a_din),
    .mem_BE(a_be), .mem_WE(a_we), .mem_RD(a_rd), .mem_ack, .mem_DOUT, .mem_DOUT_READY);
  gate b(.clk2x(clk), .reset, .dl_wr, .dl_addr, .dl_data, .dl_busy(b_dl_busy), .cm_req, .cm_we, .cm_addr, .cm_wdata,
    .cm_ack(b_cm_ack), .cm_rdata(b_cm_rdata), .ul_req(UL_REQ), .ul_line(23'd0), .ul_ack(), .ul_data(),
    .mem_request(b_req), .mem_BURSTCNT(b_bc), .mem_ADDR(b_ad), .mem_DIN(b_din),
    .mem_BE(b_be), .mem_WE(b_we), .mem_RD(b_rd), .mem_ack, .mem_DOUT, .mem_DOUT_READY);
  wire [255:0] oa = {a_dl_busy, a_cm_ack, a_cm_rdata, a_req, a_bc, a_ad, a_din, a_be, a_we, a_rd};
  wire [255:0] ob = {b_dl_busy, b_cm_ack, b_cm_rdata, b_req, b_bc, b_ad, b_din, b_be, b_we, b_rd};
  longint n = 0, bad = 0, busy = 0;
  initial begin
    repeat (20000000) begin
      @(negedge clk);
      reset = ($urandom_range(0, 9999) == 0); dl_wr = $urandom_range(0, 3) == 0; cm_req = $urandom_range(0, 2) == 0;
      cm_we = $urandom; mem_ack = $urandom_range(0, 3) == 0; mem_DOUT_READY = $urandom_range(0, 3) == 0;
      dl_addr = {$urandom, $urandom}; dl_data = $urandom; cm_wdata = $urandom; cm_addr = $urandom & 25'h3f; mem_DOUT = {$urandom, $urandom};
      @(posedge clk); #1;
      n++; if (a_req) busy++;
      if (oa !== ob) begin bad++; if (bad < 5) $display("diff at cycle %0d", n); end
    end
    $display("EQ cycles %0d, mem_request cycles %0d, differing %0d", n, busy, bad);
    $finish;
  end
endmodule
