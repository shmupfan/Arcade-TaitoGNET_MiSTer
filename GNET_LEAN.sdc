# GNET_F0_LEAN only: the fixed video PLL (rtl/gnet/pll_vid_fixed.v) replaces
# pll2, so its clock has a General-PLL name. Same false paths as PSX.sdc
# applies to pll2 (clk_vid is asynchronous to every other clock).
set vid {emu|pll2|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
foreach other {
  {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
  {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}
  {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
  {FPGA_CLK1_50}
  {FPGA_CLK2_50}
} {
  set_false_path -from [get_clocks $other] -to [get_clocks $vid]
  set_false_path -from [get_clocks $vid] -to [get_clocks $other]
}
set_false_path -from [get_clocks $vid] -to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]
