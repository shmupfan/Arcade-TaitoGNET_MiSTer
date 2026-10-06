# Timing constraints for the crossings built from rtl/gnet/cdc (helper for
# step 5 of docs/r1_cpu_domain_design.md; not yet run through Quartus, see
# "CDC building blocks" in that file).
#
# Use: source this file from the revision's SDC after derive_pll_clocks:
#   source rtl/gnet/cdc/cdc.sdc
# Do not put the CPU group and the PS1 group into one
# set_clock_groups -asynchronous: clock groups override every constraint
# below and would hide a crossing that lacks a synchroniser.
#
# Naming convention (cdc_pkg.vhd): every crossing path starts at a register
# named cdc_tx_* (source domain) and ends at a register named cdc_rx_s1
# (first synchroniser stage) or cdc_rx_hold (handshake data capture).
#   1. cdc_tx_* to cdc_rx_s1 (synchroniser first stages): max delay
#      CDC_MAX_DELAY, hold relaxed. This path is asynchronous to the
#      capturing clock, so its length does not change the settling time
#      between cdc_rx_s1 and the next stage (a full destination period,
#      which is what the MTBF depends on); it only decides on which
#      destination edge a change is first seen. Every cdc_sync carries
#      either independent bits (levels, toggles, single-bit requests: each
#      bit may arrive one destination cycle before or after the others,
#      cdc_sync.vhd) or a Gray bus, whose skew item 2 bounds separately.
#      So the bound only has to stay below the shortest destination period
#      of a crossing (clk2x, 14.76 ns) to keep the latency counts of
#      cdc_handshake and cdc_fifo. GNET_Z1_CPU50 fit 1 failed the earlier
#      8 ns bound by up to 1.221 ns on such paths (cpu_split u_p2c
#      cdc_tx_p_lvl to cdc_rx_s1, cpu_spu_bridge cdc_tx_dreq, cdc_tx_fillreq)
#      with no functional consequence.
#   1b. cdc_tx_* to cdc_rx_hold (held handshake data): max delay
#      CDC_HOLD_DELAY, hold relaxed. The data is written on the same source
#      edge as its toggle and captured on the destination edge after the
#      toggle has passed STAGES synchroniser stages, so at least STAGES
#      destination periods after the toggle's first sample (2 x 14.76 ns
#      into clk2x, the fastest destination of a handshake). Bounding it at
#      8 ns like a synchroniser input failed GNET_CPU50_B1 fit 3 (-0.807 ns
#      on cpu_gpu_bridge u_rsp cdc_tx_req to cdc_rx_hold) with no
#      functional need; 14 ns stays below one clk2x period, and a toggle
#      that arrives at its cdc_rx_s1 at time t has its data at cdc_rx_hold
#      by t + 14 ns, before the capture STAGES edges later.
#   2. Gray pointers and event counters (cdc_tx_wptr, cdc_tx_rptr,
#      cdc_tx_cnt): max skew CDC_GRAY_SKEW and net delay within one bus,
#      per instance. The skew must stay below the source clock period
#      (10 ns at 100 MHz) so that one sample never mixes two increments.
#   3. Any other path from a CPU-group register to a PS1-group register
#      (or back) is a design error; tools/sta/xclk_query.tcl lists them.

set CDC_MAX_DELAY 14.0
set CDC_HOLD_DELAY 14.0
set CDC_GRAY_SKEW 5.0

set cdc_tx [get_registers -nowarn {*cdc_tx_*}]
set cdc_s1 [get_registers -nowarn {*cdc_rx_s1*}]
set cdc_hd [get_registers -nowarn {*cdc_rx_hold*}]
if {[get_collection_size $cdc_tx] > 0 && [get_collection_size $cdc_s1] > 0} {
   set_max_delay -from $cdc_tx -to $cdc_s1 $CDC_MAX_DELAY
   set_min_delay -from $cdc_tx -to $cdc_s1 -100.0
}
if {[get_collection_size $cdc_tx] > 0 && [get_collection_size $cdc_hd] > 0} {
   set_max_delay -from $cdc_tx -to $cdc_hd $CDC_HOLD_DELAY
   set_min_delay -from $cdc_tx -to $cdc_hd -100.0
}

# Gray buses, one set_max_skew per instance (skew between unrelated
# instances is meaningless). Source register name -> synchroniser instance:
#   cdc_fifo  cdc_tx_wptr -> cdc_sync:u_wsync, cdc_tx_rptr -> cdc_sync:u_rsync
#   cdc_pulse cdc_tx_cnt  -> cdc_sync:u_sync
foreach {tx sync} {cdc_tx_wptr u_wsync cdc_tx_rptr u_rsync cdc_tx_cnt u_sync} {
   set seen [list]
   foreach_in_collection r [get_registers -nowarn "*|${tx}\[*\]"] {
      set name [get_node_info -name $r]
      set inst [string range $name 0 [expr {[string last "|${tx}\[" $name] - 1}]]
      if {[lsearch -exact $seen $inst] >= 0} {
         continue
      }
      lappend seen $inst
      set from [get_keepers "${inst}|${tx}\[*\]"]
      set to   [get_keepers "${inst}|cdc_sync:${sync}|cdc_rx_s1\[*\]"]
      if {[get_collection_size $to] > 0} {
         set_max_skew -from $from -to $to $CDC_GRAY_SKEW
         set_net_delay -from $from -to $to -max $CDC_GRAY_SKEW
      }
   }
}
