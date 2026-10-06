// Empty stand-ins for the PLLs and Intel primitives PSX.sv and sdram.sv
// instantiate, so sim/dbg/lint_psx.sh elaborates the whole of PSX.sv
// (width checks included). Lint only.
/* verilator lint_off UNUSED */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off DECLFILENAME */
/* verilator lint_off MULTITOP */
module pll (input wire refclk, input wire rst, output wire outclk_0, output wire outclk_1, output wire outclk_2, output wire locked);
endmodule
module pll_cpu (input wire refclk, input wire rst, output wire outclk_0, output wire outclk_1, output wire locked);
endmodule
module pll_vid_fixed (input wire refclk, input wire rst, output wire outclk_0, output wire locked);
endmodule
module cyclonev_clkena #(parameter clock_type = "", parameter ena_register_mode = "")
   (input wire inclk, input wire ena, output wire enaout, output wire outclk);
endmodule
module altddio_out #(parameter extend_oe_disable = "", parameter intended_device_family = "", parameter invert_output = "",
                     parameter lpm_hint = "", parameter lpm_type = "", parameter oe_reg = "", parameter power_up_high = "",
                     parameter width = 1)
   (input wire [width-1:0] datain_h, input wire [width-1:0] datain_l, input wire outclock, output wire [width-1:0] dataout,
    input wire aclr, input wire aset, input wire oe, input wire outclocken, input wire sclr, input wire sset);
endmodule
