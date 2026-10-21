# Hold exception for the savestate engine's SPU RAM read capture, for
# revisions built with GNET_NO_SAVESTATES (HAS_SAVESTATES = 0). Read by
# GNET_Z1FULLR.qsf only (docs/area_timing.md section 2).
#
# The path: rtl/savestates.vhd SPURAM_dataRead1x (clk1x, line 274) ->
# SPURAM_dataRead2x (clk2x, line 307), same emu PLL, hold relationship 0 with
# about 0.79 to 0.89 ns of clock skew (CLKCTRL of clk_1x against clk_2x).
# It failed hold on 2 of 28 GNET_Z1FULLR fits: a3-calib seed 5 -0.420 and
# 8d71028 seed 4 -0.202 (Slow 100C), both with skew 0.889 ns.
#
# Why it is safe here: SPURAM_dataRead2x is read only in state
# SAVEMEMORY_WAIT_SPURAM (savestates.vhd line 485), reached only through
# savemode = '1', which is set only by save = '1'. With HAS_SAVESTATES = 0
# psx_top ties savestate_savestate (the save input) to '0' (gnostatemanager),
# so the captured value never reaches a register that matters. Reset mode
# (SPU RAM zero fill) writes SPU RAM and does not use this capture.
# Setup on the path stays timed; only hold is removed.
#
# Guard: applied only when the netlist has no statemanager (HAS_SAVESTATES =
# 0); with savestates built the exception would be wrong and is skipped.
set gnet_ss_sm [get_registers -nowarn {*istatemanager*}]
set gnet_ss_from [get_registers -nowarn {*|savestates:isavestates|SPURAM_dataRead1x[*]}]
set gnet_ss_to   [get_registers -nowarn {*|savestates:isavestates|SPURAM_dataRead2x[*]}]
if {[get_collection_size $gnet_ss_sm] == 0 && \
    [get_collection_size $gnet_ss_from] > 0 && [get_collection_size $gnet_ss_to] > 0} {
  set_false_path -hold -from $gnet_ss_from -to $gnet_ss_to
  catch { post_message -type info "GNET_SPURAM_HOLD: hold false path SPURAM_dataRead1x -> SPURAM_dataRead2x ([get_collection_size $gnet_ss_to] registers)" }
} else {
  catch { post_message -type warning "GNET_SPURAM_HOLD: not applied (statemanager present or registers not found)" }
}
