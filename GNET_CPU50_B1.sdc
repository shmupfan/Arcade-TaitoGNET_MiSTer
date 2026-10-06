# GNET_CPU50_B1 only (R1 steps 4 and 5, docs/r1_cpu_domain_design.md): the
# CPU group runs from rtl/gnet/pll_cpu.v at 50.000 MHz (clk_cpu) and
# 100.000 MHz (clk_cpu2x). derive_pll_clocks (sys_top.sdc, PSX.sdc) creates
# both; STA times clk_cpu to clk_cpu2x as synchronous (one VCO, phase 0).
# GNET_LEAN.sdc stays in the revision for clk_vid against the emu PLL.
#
# Clock names follow the pll_vid_fixed pattern of GNET_LEAN.sdc (altera_pll
# instantiated directly, instance pll_cpu in emu); needs-review on the first
# fit: the TimeQuest clock list must show these two names.
set cpu   {emu|pll_cpu|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
set cpu2x {emu|pll_cpu|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}
set vid   {emu|pll2|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}

# 1. Crossings between the CPU group and the PS1 group (clk_1x, clk_2x) are
#    built only from rtl/gnet/cdc entities. No set_clock_groups between them:
#    it would override the bounds below and hide a crossing without a
#    synchroniser (rtl/gnet/cdc/cdc.sdc). cdc.sdc bounds every cdc_tx_* to
#    cdc_rx_* path (max 14 ns, hold relaxed) and the skew of the Gray buses.
source rtl/gnet/cdc/cdc.sdc

# 2. clk_vid. The dot clock, hblank and vblank reach the timers through
#    gpu.vhd's clk_1x copies and rtl/gnet/cpu_split, so the only paths
#    between clk_vid and the CPU group are the G-NET debug overlay's
#    (docs/hw_debug_overlay.md): one cdc_handshake in PSX.sv's instance
#    dbg_ovl (rtl/gnet/zn_dbg_overlay.vhd), source clk_vid, destination
#    clk_cpu, from cdc_tx_* to cdc_rx_* registers in both directions.
#    No false path between clk_vid and the CPU clocks: Quartus gives
#    set_false_path priority over set_max_delay, so one would remove the
#    bound below. Any other path between clk_vid and {clk_cpu, clk_cpu2x}
#    is a design error and shows as a failing transfer. cdc.sdc's wildcard
#    bound (section 1) covers the same registers; the full names here make
#    the overlay's crossing explicit.
set dbg_hs {emu:emu|zn_dbg_overlay:dbg_ovl|cdc_handshake:u_hs}
set dbg_tx [get_registers -nowarn "${dbg_hs}|cdc_tx_*"]
set dbg_rx [get_registers -nowarn "${dbg_hs}|*|cdc_rx_*"]
if {[get_collection_size $dbg_tx] > 0 && [get_collection_size $dbg_rx] > 0} {
  set_max_delay -from $dbg_tx -to $dbg_rx 8.0
  set_min_delay -from $dbg_tx -to $dbg_rx -100.0
}
# The overlay's DR row (GNET_DDR3_ARB builds, docs/hw_debug_overlay.md):
# a second cdc_handshake u_hs_dr in the same instance, source clk_vid,
# destination clk_2x (the DDR3 arbiter status). GNET_LEAN.sdc false-paths
# clk_vid against both emu PLL outputs, and a false path takes priority over
# this bound, so it is named here for the fit report only; the handshake
# does not rely on it (its data is held for at least two destination clocks
# before capture). The collections are empty in builds without the row.
# (Quartus names the VHDL generate as cdc_handshake:\g_dr:u_hs_dr; the
# wildcard avoids escaping the backslash; needs-review on the first fit)
set dr_hs {emu:emu|zn_dbg_overlay:dbg_ovl|*u_hs_dr}
set dr_tx [get_registers -nowarn "${dr_hs}|cdc_tx_*"]
set dr_rx [get_registers -nowarn "${dr_hs}|*|cdc_rx_*"]
if {[get_collection_size $dr_tx] > 0 && [get_collection_size $dr_rx] > 0} {
  set_max_delay -from $dr_tx -to $dr_rx 8.0
  set_min_delay -from $dr_tx -to $dr_rx -100.0
}
set_clock_groups -asynchronous \
   -group [get_clocks [list $cpu $cpu2x]] \
   -group [get_clocks -nowarn {pll_hdmi|pll_hdmi_inst|altera_pll_i|*[0].*|divclk}] \
   -group [get_clocks -nowarn {pll_audio|pll_audio_inst|altera_pll_i|*[0].*|divclk}] \
   -group [get_clocks -nowarn {spi_sck hdmi_sck *|h2f_user0_clk FPGA_CLK1_50 FPGA_CLK2_50 FPGA_CLK3_50}]

# 3. Quasi-static configuration from PSX.sv into the CPU group (crossing C20):
#    OSD status bits (hps_io), the EXE header registers, BIOS region, hasCD
#    and the TURBO flags. clk_1x registers at the emu level that change only
#    from the OSD or a download, with the core in reset. Listed by name: the
#    first fit used "every emu-level register except psx_mister, sdram and the
#    channel 3 handshake", but Quartus names registers emu:emu|... in these
#    collections, so the exclusions matched nothing and the false path cut
#    every path into the CPU clocks (they were missing from the setup and
#    hold summaries of fit 2).
set static_src [get_registers -nowarn {*|hps_io:hps_io|status[*] emu:emu|exe_initial_pc[*] emu:emu|exe_initial_gp[*] emu:emu|exe_load_address[*] emu:emu|exe_file_size[*] emu:emu|exe_stackpointer[*] emu:emu|biosregion[*] emu:emu|hasCD emu:emu|TURBO_MEM emu:emu|TURBO_COMP emu:emu|TURBO_CACHE emu:emu|TURBO_CACHE50}]
if {[get_collection_size $static_src] > 0} {
  set_false_path -from $static_src -to [get_clocks [list $cpu $cpu2x]]
}

# 4. Not constrained here (needs-review on the first fit, with
#    tools/sta/xclk_query.tcl extended to the CPU clocks): any other path
#    between {clk_cpu, clk_cpu2x} and {clk_1x, clk_2x, clk_3x} is a design
#    error and shows as a failing path with a small setup relationship. The
#    command FIFOs of rtl/gnet/cpu_split are written for M10K; if Quartus
#    builds them in MLAB or registers, their write-to-read path through the
#    memory needs the same 14 ns bound as cdc_tx_* paths.
