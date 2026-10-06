// Full-system simulation RAM models for Verilator (sim only,
// docs/fullsys_sim.md W4). Instantiated from the GHDL netlist through the
// shims in fs_mem.vhd. Behaviour follows the PSX_MiSTer primitives:
// dpram/dpram_dif as altsyncram NEW_DATA_NO_NBE_READ on the same port,
// RamMLAB asynchronous read, SyncRam write-first, the others read-first.
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */
module fs_dpram #(parameter AW = 8, parameter DW = 8) (
  input clock_a, input clken_a, input wren_a, input [AW-1:0] address_a,
  input [DW-1:0] data_a, output reg [DW-1:0] q_a,
  input clock_b, input clken_b, input wren_b, input [AW-1:0] address_b,
  input [DW-1:0] data_b, output reg [DW-1:0] q_b);
  reg [DW-1:0] m [0:(1<<AW)-1];
  integer i; initial begin for (i = 0; i < (1<<AW); i = i + 1) m[i] = 0; q_a = 0; q_b = 0; end
  always @(posedge clock_a) if (clken_a) begin
    if (wren_a) begin m[address_a] <= data_a; q_a <= data_a; end else q_a <= m[address_a];
  end
  always @(posedge clock_b) if (clken_b) begin
    if (wren_b) begin m[address_b] <= data_b; q_b <= data_b; end else q_b <= m[address_b];
  end
endmodule

// Mixed widths: storage in words of the narrower port; the wide port
// covers R consecutive narrow words, lowest word in the low bits.
module fs_dpram_dif #(parameter AWA = 8, parameter DWA = 8, parameter AWB = 8, parameter DWB = 8) (
  input clock_a, input clken_a, input wren_a, input [AWA-1:0] address_a,
  input [DWA-1:0] data_a, output reg [DWA-1:0] q_a,
  input clock_b, input clken_b, input wren_b, input [AWB-1:0] address_b,
  input [DWB-1:0] data_b, output reg [DWB-1:0] q_b);
  localparam NW = (DWA < DWB) ? DWA : DWB;
  localparam NA = (DWA < DWB) ? AWA : AWB;
  localparam RA = DWA / NW;
  localparam RB = DWB / NW;
  reg [NW-1:0] m [0:(1<<NA)-1];
  integer i; initial begin for (i = 0; i < (1<<NA); i = i + 1) m[i] = 0; q_a = 0; q_b = 0; end
  integer j, k;
  always @(posedge clock_a) if (clken_a) begin
    for (j = 0; j < RA; j = j + 1) begin
      if (wren_a) begin m[address_a * RA + j] <= data_a[j*NW +: NW]; q_a[j*NW +: NW] <= data_a[j*NW +: NW]; end
      else q_a[j*NW +: NW] <= m[address_a * RA + j];
    end
  end
  always @(posedge clock_b) if (clken_b) begin
    for (k = 0; k < RB; k = k + 1) begin
      if (wren_b) begin m[address_b * RB + k] <= data_b[k*NW +: NW]; q_b[k*NW +: NW] <= data_b[k*NW +: NW]; end
      else q_b[k*NW +: NW] <= m[address_b * RB + k];
    end
  end
endmodule

module fs_rammlab #(parameter DW = 8, parameter AW = 4) (
  input clk, input we, input [DW-1:0] d, input [AW-1:0] wa, input [AW-1:0] ra, output [DW-1:0] q);
  reg [DW-1:0] m [0:(1<<AW)-1];
  integer i; initial for (i = 0; i < (1<<AW); i = i + 1) m[i] = 0;
  always @(posedge clk) if (we) m[wa] <= d;
  assign q = m[ra];
endmodule

module fs_ramdualbe #(parameter BW = 8, parameter AW = 6, parameter NB = 4) (
  input clk,
  input [AW-1:0] addr_a, input [4*BW-1:0] din_a, output reg [NB*BW-1:0] dout_a, input we_a, input [NB-1:0] be_a,
  input [AW-1:0] addr_b, input [4*BW-1:0] din_b, output reg [NB*BW-1:0] dout_b, input we_b, input [NB-1:0] be_b);
  reg [NB*BW-1:0] m [0:(1<<AW)-1];
  integer i; initial begin for (i = 0; i < (1<<AW); i = i + 1) m[i] = 0; dout_a = 0; dout_b = 0; end
  integer j;
  always @(posedge clk) begin
    for (j = 0; j < NB; j = j + 1) begin
      if (we_a && be_a[j]) m[addr_a][j*BW +: BW] <= din_a[j*BW +: BW];
      if (we_b && be_b[j]) m[addr_b][j*BW +: BW] <= din_b[j*BW +: BW];
    end
    dout_a <= m[addr_a];
    dout_b <= m[addr_b];
  end
endmodule

module fs_syncram #(parameter DW = 8, parameter AW = 6) (
  input clk, input [AW-1:0] addr, input [DW-1:0] din, output reg [DW-1:0] dout, input we);
  reg [DW-1:0] m [0:(1<<AW)-1];
  integer i; initial begin for (i = 0; i < (1<<AW); i = i + 1) m[i] = 0; dout = 0; end
  always @(posedge clk) begin
    if (we) begin m[addr] <= din; dout <= din; end else dout <= m[addr];
  end
endmodule

module fs_syncramdual #(parameter DW = 8, parameter AW = 6, parameter N = 64) (
  input clk,
  input [AW-1:0] addr_a, input [DW-1:0] din_a, output reg [DW-1:0] dout_a, input we_a, input re_a,
  input [AW-1:0] addr_b, input [DW-1:0] din_b, output reg [DW-1:0] dout_b, input we_b, input re_b);
  reg [DW-1:0] m [0:N-1];
  integer i; initial begin for (i = 0; i < N; i = i + 1) m[i] = 0; dout_a = 0; dout_b = 0; end
  always @(posedge clk) begin
    if (we_a) m[addr_a] <= din_a;
    if (re_a) dout_a <= m[addr_a];
    if (we_b) m[addr_b] <= din_b;
    if (re_b) dout_b <= m[addr_b];
  end
endmodule
/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on WIDTHTRUNC */
