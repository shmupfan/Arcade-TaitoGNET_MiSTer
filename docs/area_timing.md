# Why the area merge made GNET_Z1FULLR timing worse (alpha4b, 8d71028)

Branch `area-timing` from alpha4b 8d71028. Written 2026-10-20 on the Mac from the fetched reports only; no Quartus run was made for this note. Every figure is quoted from a `.sta.summary`, `.sta.rpt`, `.fit.rpt`, `.map.rpt` or `hold2x_*` report under `gnet-mister-a3cal/builds/`.

## Summary

- **The clock.** `emu|pll|pll_inst|altera_pll_i|general[1]` is `clk_2x`: PSX.sv instance `pll` drives `.outclk_1(clk_2x)`, and the Clocks panel gives it 14.762 ns (67.74 MHz, general[0] = clk_1x at 29.524 ns). In the release (GNET_CPU50) the CPU and its data cache are not on it: psx_top maps the CPU's clk1x/clk2x to `clk_cpu`/`clk_cpu2x` (the separate `pll_cpu`, 50/100 MHz). clk_2x carries the GPU, SPU, savestate engine, DDR3 arbiter and #12 flash copy.
- **Seed 4 hold (-0.202).** The known savestate SPU RAM capture `savestates|SPURAM_dataRead1x[6]` (clk_1x) to `SPURAM_dataRead2x[6]` (clk_2x), 1 endpoint, all four corners. Same path, same 0.889 ns clock skew as the a3-calib seed 5 failure (-0.420) before any area change. The data cache removal did not expose it. It is unreachable in the release (savestates are compiled out), so a hold-only false path is exact: `GNET_SPURAM_HOLD.sdc`, read by GNET_Z1FULLR.qsf since the section 9 commit.
- **clk_2x setup (named by step 0, section 9).** Every failing endpoint is `gpu|reqVRAMwrap[*]` (8 bits), reached from the DDR3 arbiter's owner FIFO pointers (`of_wp`, `of_rp`) or the HPS f2sdram waitrequest through the arbiter's combinational core BUSY (`sel_c`), the GPU's request gating and the wrap arithmetic: 10 to 12 levels, 13.8 to 14.5 ns of data delay in a 14.762 ns period. The RTL of this path is unchanged since alpha 3; the area merge made the fitter place it worse on every seed (the clk_2x path count also rose 30 %, 133.5 M to 174.3 M), so 3 of 4 seeds missed by up to 0.044 ns. At Slow -40C, which the flow does not sign off, it misses on all 4 seeds by 0.55 to 0.79 ns. Fix (section 9, committed): the wrap value is computed one cycle later from registered operands; behaviour is unchanged (NVC A/B bench) and the next endpoints of the cone have +0.74 ns or more on the same placements.
- **HDMI setup.** Area fits: -0.226, +0.039, -0.018, -0.410. That is within the pre-F1 spread of the current tree (4 of 9 fits met HDMI), and alpha4-f1's 3 of 3 is itself weak evidence (3 seeds, seed 4 never fitted with F1). HDMI here is still the ascal placement lottery of docs/hdmi_timing.md; the area merge did not help it and the data does not show it hurt it.
- **Release position.** Do not ship 8d71028. alpha4-f1 (6638e03) seeds 1 to 3 each pass every clock and every hold corner; seed 2 has the widest margins (HDMI +0.279, clk_2x +0.774, worst hold2x +0.105, RBF md5 4c6cc257669ae5bc35f02669e818341b).
- **Next.** One 4-seed fit batch of `area-timing` (fix plus hold SDC), section 9. Steps 1 and 2 (sections 6 and 7) and the arm branches are no longer needed for the release; they would only explain why the area merge moved this path.

## 1. Which clock

- `PSX.sv` line 143: `pll pll (.refclk(CLK_50M), .outclk_0(clk_1x), .outclk_1(clk_2x), .outclk_2(clk_3x), ...)`. In the STA, outclk_1 is `general[1]`.
- `GNET_Z1FULLR.sta.rpt` (2011 seed 4) Clocks panel: general[0] 29.524 ns, 33.87 MHz; general[1] 14.762 ns, 67.74 MHz; `pll_cpu` general[0] 20.000 ns, general[1] 10.000 ns.
- `rtl/psx_top.vhd` port map of `icpu`: `clk1x => clk_cpu, clk2x => clk_cpu2x, clk3x => clk_cpu3x`; `datacache` takes the CPU's clk1x/clk2x. So the 64 M10K of the data cache sat on pll_cpu, not on clk_2x. `zn_dbg_regs` and `zn2_io` are in the CPU group too (clk_cpu).
- What the area commit removed on emu PLL clocks: the debug overlay (`zn_dbg_overlay`: clk_cfg = clk_1x, clk_dr = clk_2x for the DDR3 status row, clk_vid) and, through it, 15 now-unused status registers in `gnet_ddr3_arb` (map report: ddr3_arb -47 ALUTs, -15 registers).

## 2. Seed 4 hold: the known SPU RAM capture

`20261020_2011_z1fullr_seed4/hold2x_corners.rpt`:

| Corner | Worst | Failing endpoints |
|---|---|---|
| Slow 100C | -0.202 | 1 |
| Slow -40C | -0.050 | 1 |
| Fast 100C | -0.160 | 1 |
| Fast -40C | -0.148 | 1 |

Path #1 of every `hold2x_*_full.rpt`: from `savestates:isavestates|SPURAM_dataRead1x[6]` (launch general[0]) to `SPURAM_dataRead2x[6]` (latch general[1]), hold relationship 0.000. Slow 100C: clock skew 0.889, data delay 0.747. Both registers sit in one LAB (FF_X57_Y36_N32 and _N1); clk_1x comes through CLKCTRL_G2 and arrives at 6.693 ns, clk_2x through CLKCTRL_G0 at 8.053 ns (PLL output counter 1.747 against 1.468, global route 2.377 against 1.917). The fitter added only a feeder LUT (0.442 ns), not enough.

The same path failed on `20261015_1654_z1fullr` (a3-calib seed 5, before the area work): bit [3], -0.420 at Slow 100C, skew 0.889, data delay 0.529, at FF_X31_Y44. So it is a recurring, placement-dependent hold problem of this transfer: 2 of 28 GNET_Z1FULLR fits. Nothing in the data cache removal touches it (different PLL, different entity, savestates.vhd unchanged).

Why a hold false path is exact here: `SPURAM_dataRead2x` is read only in state `SAVEMEMORY_WAIT_SPURAM` (savestates.vhd line 485), reached only with `savemode = '1'`, set only by `save = '1'`. With `HAS_SAVESTATES = 0` (GNET_NO_SAVESTATES) psx_top ties `savestate_savestate`, the save input, to '0' (`gnostatemanager`). Reset mode (SPU RAM zero fill) writes SPU RAM and does not use the capture.

Fix: `GNET_SPURAM_HOLD.sdc` (`set_false_path -hold` from `SPURAM_dataRead1x[*]` to `SPURAM_dataRead2x[*]`, applied only when no statemanager register exists). GNET_Z1FULLR.qsf reads it (`set_global_assignment -name SDC_FILE GNET_SPURAM_HOLD.sdc`, added with the section 9 fix, once step 0 had settled the setup question). Check after its first fit: compile.log has `GNET_SPURAM_HOLD: hold false path ...` with a non-zero register count and hold2x no longer lists the path.

## 3. clk_2x setup: what the reports show

### 3.1 Slack per fit

clk_2x setup slack (Slow 100C, flow STA) for every GNET_Z1FULLR fit with an STA report (bit-identical rebuilds of the 2100 release counted once):

| Source | Fits | clk_2x setup | HDMI setup | All clocks met |
|---|---|---|---|---|
| alpha3, a3-nm, a3-sta, a3-prefetch, a3-calib (Oct 14 to 15) | 12 | +0.154 to +1.387 | -0.408 to +0.344 | |
| 1f6d3dc (#11) seeds 1 to 4, 8 | 5 | +0.493 to +1.292 | -0.227 to +0.260 | 1 of 5 |
| 9f482ae (#10, #11) seeds 1 to 4 | 4 | +0.201 to +1.037 | -0.288 to +0.325 | 2 of 4 |
| 6638e03 alpha4-f1 (#12 + F1) seeds 1 to 3 | 3 | +0.716, +0.774, +0.092 | +0.041, +0.279, +0.181 | 3 of 3 |
| 8d71028 alpha4b (area) seeds 1 to 4 | 4 | -0.011, -0.028, +0.141, -0.044 | -0.226, +0.039, -0.018, -0.410 | 0 of 4 |

18 of the 21 pre-F1 fits had clk_2x at +0.30 or more; none was below +0.154. All 4 area fits are at +0.141 or less. With F1 alone, 1 of 3 (seed 3, +0.092) was already low.

Area seed 1 clk_2x TNS -0.064, seed 2 -0.200, seed 4 -0.328 (worst -0.044): several failing endpoints, a bus or a family, not one register.

### 3.2 The netlist changed in the clk_2x domain

Setup Transfers panel, RR paths (seed spread within one commit is small):

| Source | clk_2x to clk_2x | clk_1x to clk_2x |
|---|---|---|
| alpha3 era (8 fits) | 116.7 to 118.3 M | 0.72 M |
| a3-calib to 9f482ae (13 fits) | 134.5 to 137.9 M | 0.72 M |
| 6638e03 alpha4-f1 (3) | 133.4 to 133.6 M | 6.09 M (#12 flash copy) |
| 8d71028 area (4) | 174.1 to 174.4 M | 6.46 M |

The area commit added about 40.8 million clk_2x paths while removing clk_2x logic. The map report (synthesis, identical between seeds of one commit: seed 1 and seed 2 of 6638e03 have no per-entity difference) shows the area commit changed synthesis outside the removed blocks: GPU -59 ALUTs, SPU +32, memorymux +51, DMA -40, GTE +20, Zoom board -82, ascal +25, hdmi_osd +24, sdram +17 registers, ddr3_arb -15 registers. Total block memory fell by exactly the 67 M10K expected (524,288 + 2,048 + 512 bits), so no RAM changed implementation.

Reading: Quartus synthesis (Aggressive Performance, timing-driven synthesis on) re-optimised the whole design after the change, and some clk_2x structure came out with many more and, by the slack data, longer paths. Which family that is, the fetched reports cannot say.

### 3.3 Fitter-level figures (no difference that explains it)

ALMs needed 36,477 to 36,544 (alpha4-f1) against 36,099 to 36,146 (area); M10K 464 against 397; router peak interconnect and hold delay added (2.3 to 3.5 % of routing delay) overlap between the two sets. compile.log has the F1 message 8 or 9 times on all 7 F1 fits (from quartus_fit only, checked in the seed 4 log), so F1 acted the same way in both sets.

## 4. Hypotheses against the evidence

| Hypothesis | Evidence | Verdict |
|---|---|---|
| Hold failure exposed by the data cache removal | Path is clk_1x to clk_2x inside savestates; data cache was on pll_cpu; identical skew failure on a3-calib seed 5 before the area work | Rejected: known SPU RAM capture, 2 of 28 fits |
| clk_2x failure is placement churn (seed luck) | 4 of 4 area fits at or below +0.141, against 0 of 21 earlier fits below +0.154; path count up 30 % with under 0.3 % seed spread | Rejected as the main cause: systematic, netlist level |
| Data cache removal lengthened clk_2x paths directly | No data cache logic on clk_2x | Not directly. Indirectly possible (synthesis re-optimisation); step 1 tests it |
| Debug overlay removal changed clk_2x | The overlay is the only removed logic with a clk_2x side (DDR3 status handshake, 15 ddr3_arb registers) | Plausible; step 1 tests it |
| F1 over-constraint plus freed area pushed the fitter off clk_2x | F1 alone: 1 of 3 low (+0.092); F1 cannot change synthesis, and the path count change is in synthesis-level structure | Secondary at most; the alpha4-f1 g4 to g7 batch (pushed 20:18 from 8aff312) measures F1 alone on 4 more seeds |
| Area change made HDMI worse | Area HDMI 1 of 4 met; pre-F1 tree 4 of 9; F1 3 of 3 on 3 seeds | Not shown either way; HDMI remains the ascal lottery |

## 5. Step 0: path families from the kept area databases (no fit)

`tools/sta/clk_paths.tcl` (this branch) generalises `hdmi_paths.tcl`: setup into any of `2x 1x cpu cpu2x vid hdmi`, both slow corners, with per-family worst slack, count, data delay, clock skew, logic levels and launch clock, plus the worst path per launch clock. The kept databases C:\gn_z1fullr_b1 to b4 were pushed from 8d71028 and do not have the script, so copy it first (from this worktree):

```
for s in b1 b2 b3 b4; do ssh $PC_HOST "powershell -NoProfile -Command \"\$input | Set-Content -Encoding ASCII C:\gn_z1fullr_$s\tools\sta\clk_paths.tcl\"" < tools/sta/clk_paths.tcl; done
```

Task file `C:\gn_sta_paths.cmd` (CRLF; send it with the same `powershell ... Set-Content -Encoding ASCII C:\gn_sta_paths.cmd` pattern), sequential so four timing netlists are not in memory at once:

```
cd /d C:\gn_z1fullr_b1
start /B /WAIT /AFFINITY 0000FFFF C:\intelFPGA_lite\17.0\quartus\bin64\quartus_sta.exe -t tools/sta/clk_paths.tcl PSX GNET_Z1FULLR paths 2x hdmi cpu cpu2x >> sta_paths.log 2>&1
cd /d C:\gn_z1fullr_b2
start /B /WAIT /AFFINITY 0000FFFF C:\intelFPGA_lite\17.0\quartus\bin64\quartus_sta.exe -t tools/sta/clk_paths.tcl PSX GNET_Z1FULLR paths 2x hdmi cpu cpu2x >> sta_paths.log 2>&1
cd /d C:\gn_z1fullr_b3
start /B /WAIT /AFFINITY 0000FFFF C:\intelFPGA_lite\17.0\quartus\bin64\quartus_sta.exe -t tools/sta/clk_paths.tcl PSX GNET_Z1FULLR paths 2x hdmi cpu cpu2x >> sta_paths.log 2>&1
cd /d C:\gn_z1fullr_b4
start /B /WAIT /AFFINITY 0000FFFF C:\intelFPGA_lite\17.0\quartus\bin64\quartus_sta.exe -t tools/sta/clk_paths.tcl PSX GNET_Z1FULLR paths 2x hdmi cpu cpu2x >> sta_paths.log 2>&1
echo ===== sta paths end %DATE% %TIME% ===== >> C:\gn_z1fullr_b4\sta_paths.log
```

```
ssh $PC_HOST "schtasks /create /f /tn gnstapaths /tr C:\gn_sta_paths.cmd /sc once /st 23:59 /sd 01/01/2030"
ssh $PC_HOST "schtasks /run /tn gnstapaths"
```

Fetch `output_files/paths_*.rpt` and `sta_paths.log` of each slot into the build folder of its seed. Which slot holds which seed is settled by `paths_corners.rpt`, Slow 100C, against the flow's sta.summary: seed 1 clk_2x -0.011 / HDMI -0.226; seed 2 -0.028 / +0.039; seed 3 +0.141 / -0.018; seed 4 -0.044 / -0.410. A slot that matches none was refitted since; drop it.

What to read: `paths_2x_Slow_1100mV_100C_Model_families.rpt` on all four seeds. One family failing on 3 or 4 seeds is the target of step 1 (its entity says which area change can reach it). A family with a launch clock other than clk_2x is a crossing (check its cdc.sdc bound). High data delay with few levels is routing; many levels is synthesis depth, which step 1 sees without a fit.

If `-clock_skew` or `-num_logic_levels` are not accepted by this Quartus, the columns print `?` and the rest of the report is unaffected.

## 6. Step 1: post-synthesis batch, 4 netlists, no fit

Superseded by section 9 (step 0 named the path). Kept as a method for a later netlist comparison.

Synthesis is deterministic and takes about 3 minutes (map 00:03:12 in the seed 4 log), so four netlists can be compared without seed noise. `pc_build.sh POSTMAP=1` runs quartus_map, then `tools/sta/postmap_paths.tcl` on the synthesis netlist: `postmap_transfers.rpt` (path count per clock pair), `postmap_worst.rpt` and `postmap_<clk>_families.rpt` (2000 worst endpoints, logic levels).

| Slot | Worktree | Commit | Netlist |
|---|---|---|---|
| m0 | gnet-mister-areatiming-ref | e702a56 (8aff312 + tools) | alpha4-f1, no area change |
| m1 | gnet-mister-areatiming | 6a388bd (8d71028 + tools) | full area change |
| m2 | gnet-mister-areatiming-dc | 98f613f | area, data cache kept |
| m3 | gnet-mister-areatiming-dbg | ac2ecc9 | area, debug overlay kept |

Per slot, from its worktree (e.g. m2):
```
cd ../gnet-mister-areatiming-dc
SLOT=m2 POSTMAP=1 tools/pc_build.sh z1fullr push
SLOT=m2 POSTMAP=1 tools/pc_build.sh z1fullr task
SLOT=m2 POSTMAP=1 tools/pc_build.sh z1fullr run
SLOT=m2 POSTMAP=1 tools/pc_build.sh z1fullr fetch
```

Decision:
- Calibration first: m0 against m1 must show the clk_2x to clk_2x count jump (or a new deep family in `postmap_2x_families.rpt`). If m0 and m1 are alike post-map, the change appears only after the fitter's physical synthesis; skip to the fallback fit batch below.
- m2 like m0 and m3 like m1: the data cache removal set it off. Keep the cache (GNET_NO_DCACHE off); fit batch = `area-timing-dc`.
- m3 like m0 and m2 like m1: the overlay removal set it off. Fit batch = `area-timing-dbg`.
- Both like m1: neither change alone (the zn2_io stub, or the pair). Fallback fit batch.

## 7. Step 2: the 4-seed fit batch

Superseded by section 9.

Chosen arm, seeds 1 to 4, slots b1 to b4, F1 at 0.25 (default). The push clears the slot, so run step 0 on b1 to b4 first. For example:
```
cd ../gnet-mister-areatiming-dc
for s in 1 2 3 4; do SLOT=b$s tools/pc_build.sh z1fullr push && SLOT=b$s SEED=$s tools/pc_build.sh z1fullr task && SLOT=b$s tools/pc_build.sh z1fullr run; done
# when done: for s in 1 2 3 4; do SLOT=b$s SEED=$s tools/pc_build.sh z1fullr fetch; done
```
Every fit now also writes `paths_*` (clk_paths.tcl after the hold reports), so the families are on hand for every seed.

Fallback batch (step 1 inconclusive): `area-timing` seeds 1 and 2 with `FIT_OC=0` (F1 off; same netlist as the failing area fits, so it isolates the fitter interaction) and `area-timing-dc` seeds 1 and 2.

What decides it, per arm: clk_2x at +0.30 or more on its seeds means the culprit is gone (18 of 21 pre-F1 fits); +0.15 or less means it is still there (4 of 4 area fits). HDMI is judged only on pass counts over many seeds, never on one batch. An arm becomes a release candidate when 3 of 4 seeds meet every clock and every hold corner; then add GNET_SPURAM_HOLD.sdc and fit once more to confirm.

F1 at 0.15 is not in this batch: the alpha4-f1 g4 to g7 fits (pushed 20:18) answer whether F1 alone costs clk_2x. If those show clk_2x at +0.15 or less, add `FIT_OC=0.15` arms on the release candidate.

## 8. Files on this branch

- `docs/area_timing.md` this note.
- `tools/sta/clk_paths.tcl` setup families for any core clock.
- `tools/sta/postmap_paths.tcl` post-synthesis transfers and families.
- `tools/pc_build.sh` POSTMAP=1, FIT_OC=<ns>, clk_paths.tcl after every full PSX fit, push record per SLOT (cherry-picked 5313896).
- `GNET_HDMI_FITOC.sdc` reads `GNET_FIT_OC` (unset: 0.25 as before; 0: off).
- `GNET_SPURAM_HOLD.sdc` hold exception, not in any QSF.

Not checked on the PC: `create_timing_netlist -post_map`, `report_clock_transfers -file`, `get_path_info -clock_skew` / `-num_logic_levels` and the `::env` read inside SDC are standard Quartus Tcl but have not been run on this install; the first step 0 and step 1 runs confirm them (compile.log shows `GNET_HDMI_FITOC: off for this fit` when FIT_OC=0).

## 9. Step 0 result and the fix

### 9.1 What step 0 found

`tools/sta/clk_paths.tcl` on the kept 8d71028 databases (slots b1 to b4 = seeds 1 to 4, matched on the flow's Slow 100C figures). clk_2x, worst slack and families under +0.1 ns:

| Seed | Slow 100C | Slow -40C | Family (100C) | Data delay | Levels |
|---|---|---|---|---|---|
| 1 | -0.011 (8 endpoints) | -0.550 | sysmem f2sdram~FF_3780 -> gpu reqVRAMwrap[*] | 13.815 | 10 |
| 2 | -0.028 (8) | -0.788 | gnet_ddr3_arb of_wp[*] -> gpu reqVRAMwrap[*] | 14.451 | 11 |
| 3 | +0.141 | -0.583 | (none under 0.1; worst of_wp[0] -> reqVRAMwrap) | | |
| 4 | -0.044 (8) | -0.651 | gnet_ddr3_arb of_wp[*] -> gpu reqVRAMwrap[*] | 14.441 | 12 |

At -40C the family is the same on all four (of_rp on seed 1). The next endpoints in the 100C summaries are the same cone's `reqVRAMremain[*]` and `vram_BURSTCNT[*]` at +0.744 (seed 1), +1.083 (2), +1.240 (3), +1.040 (4).

Seed 4 full path (Slow 100C): of_wp[1] (FF_X46_Y65) -> Add4 (of_wp - of_rp) -> req_g~0 / rd_room -> sel_c~1 (fanout 12) -> gpu_rect requestVRAMSize[4]~0 -> gpu reqVRAMSize[4] -> Add15 -> LessThan16 -> reqVRAMSizeRounded~2 -> LessThan17 (fanout 45) -> Add22 (carry chain) -> LessThan19 -> reqVRAMwrap[1]~2 -> reqVRAMwrap[6] sclr (FF_X40_Y64); data delay 14.441, of which 6.033 ns routing.

### 9.2 The path in the RTL

- `rtl/gnet/gnet_ddr3_arb.sv`: `rd_room` compares `of_wp - of_rp` (owner FIFO level); `req_g`/`req_c` use it; `sel_c = load && !req_r && !req_z && !req_g && req_c` with `load = !rst && (!k_valid || accept)` and `accept = k_valid && !ddr_busy` (ddr_busy = HPS f2sdram waitrequest, the seed 1 start point); `assign c_busy = !sel_c`, combinational.
- PSX.sv: `.c_busy(core_ddr_busy)`, into psx_mister `DDRAM_BUSY`, psx_top `ddr3_BUSY`, gpu `vram_BUSY`.
- `rtl/gpu.vhd`: `VRAMIdle` needs `vram_WE = '0' or vram_BUSY = '0'`; `reqVRAMIdle` feeds every requester, and gpu_rect (like the others) zeroes `requestVRAMSize` unless `requestVRAMIdle = '1'`; the OR of the requesters is `reqVRAMSize`; in state IDLE the process rounds it, clamps it to 1024 and, for VRAM-to-VRAM and VRAM-to-CPU reads, sets `reqVRAMwrap` from `reqVRAMXPos + reqVRAMSizeRounded > 1024`. That last add, compare and divide is the step that only the wrap endpoints pay.
- Changed by #12 or the area work? No. `git log` of gnet_ddr3_arb.sv ends at c6aab13 (GNET_DDR3_ARB) and of gpu.vhd at 771b9fe (TEX_MISS_DELAY), both before alpha 3 (c853da8); #12's gnet_ddr3_gmux sits on the arbiter's G port (`g_rd`/`g_we`), which enters `req_g` but is not the start point of any listed path. The logic is the same; its placement got worse. The area merge rewrote synthesis around it (section 3.2) and, if this was also alpha4-f1's worst clk_2x family (not measured, 9.3), the fitter put the cone about 0.7 ns worse than on alpha4-f1 seeds 1 and 2.

### 9.3 Why alpha4-f1 had +0.774

No alpha4-f1 path report exists (the fetched folders have summaries only and the b slots now hold the area fits). The path is in the alpha4-f1 netlist unchanged, so the likely reading is that it was the same family with more margin from placement, and that alpha4-f1 seed 3 (+0.092) was this family close to failing. The run that settles it: `clk_paths.tcl ... paths 2x` on any kept alpha4-f1 database (the g4 to g7 slots pushed at 20:18 from 8aff312, if still on the PC), with the same task file as section 5 and `cd /d C:\gn_z1fullr_g4` etc.

### 9.4 The fix (commit a43ec84)

`rtl/gpu.vhd`: in IDLE, instead of computing `reqVRAMwrap` from the live request, the process stores `reqVRAMwrapX <= reqVRAMXPos`, `reqVRAMwrapSize <= reqVRAMSizeRounded` and `reqVRAMwrapPend <= vram2vram_reqVRAMEnable or vram2cpu_reqVRAMEnable` (and still clears `reqVRAMwrap`). One clk2x later, `reqVRAMwrapPend = '1'` applies the original expression to the registered operands. Reset clears the pending bit.

Why the one cycle cannot be seen: `reqVRAMwrap` is read in two places only. `postWrite` needs `vram_RD = '0'`, and the request just set `vram_RD <= '1'`, so postWrite is 0 in the first READVRAM cycle. The wrap burst in READVRAM needs `vram_DOUT_READY = '1'` with `reqVRAMremain = 0`, the request's last beat, which comes after the read was accepted (at the earliest the cycle after the request) and returned. The wrap requesters never take the render24 READSECOND branch. From the second READVRAM cycle on, `reqVRAMwrap` holds the same value as before.

Timing effect: the wrap endpoints leave the BUSY cone. The new endpoints there are `reqVRAMwrapSize` (captures after the 1024 clamp, earlier than `reqVRAMnext` and `vram_BURSTCNT`, which had +0.74 ns or more) and `reqVRAMwrapX` (shallower). The one-cycle computation is register to register inside the GPU. Cost: 22 registers.

Bench (sim/gpuinfl, NVC): `sim/gpuinfl/wrap_stream.py` fills and uploads data on both sides of the x = 1023 / 0 seam and runs 7 VRAM-to-VRAM copies, 5 of which wrap (one 600 wide, also using reqVRAMnext; one with a wrapping destination). Old gpu.vhd, new gpu.vhd and a mutant (wrap never set), each with the direct VRAM model (read latency 0, data one cycle after the request, the tightest case) and with `-gARB=true` (the arbiter core path model):

| Build | VRAM dump (vram_3.bin) md5 | ddr3_frames.txt |
|---|---|---|
| old, direct | a10fc38615db29272a45948fafa7b6bf | 8e1f19ac... |
| new, direct | a10fc38615db29272a45948fafa7b6bf | 8e1f19ac... (same) |
| old, ARB | a10fc38615db29272a45948fafa7b6bf | 1cf0d92e... |
| new, ARB | a10fc38615db29272a45948fafa7b6bf | 1cf0d92e... (same) |
| mutant | a0d1c3e961ba4246a0c1e28b3a8fd4ad | differs |

The mutant differs from old in 710 pixels, all in the wrapped parts of the 5 wrapping copies, so the stream exercises the wrap; old and new match in VRAM and in the per-vblank DDR3 cycle counts (same timing, not only same result). Re-run: build each GPU with `sim/gpuinfl/build.sh` (old: `M1_BUILD=pre` with the old gpu.vhd in rtl/ while building), then `run.sh` as in the script header.

### 9.5 Next PC batch

`area-timing` (8d71028 + fix + GNET_SPURAM_HOLD.sdc + tools), seeds 1 to 4 in slots b1 to b4, F1 at 0.25:
```
cd ../gnet-mister-areatiming     # the area-timing worktree
for s in 1 2 3 4; do SLOT=b$s tools/pc_build.sh z1fullr push && SLOT=b$s SEED=$s tools/pc_build.sh z1fullr task && SLOT=b$s tools/pc_build.sh z1fullr run; done
# when done: for s in 1 2 3 4; do SLOT=b$s SEED=$s tools/pc_build.sh z1fullr fetch; done
```
Each fit also writes `paths_*` (clk_paths.tcl) and the hold reports. Checks per seed: compile.log has `GNET_SPURAM_HOLD: hold false path` and `GNET_HDMI_FITOC: fitter over-constraint +0.25`; `paths_2x_*_families.rpt` has no `reqVRAMwrap` family; clk_2x Slow 100C at +0.3 ns or more (the cone's next endpoints were +0.74 to +1.24 on the failing placements); hold1x/hold2x no failing endpoint. A seed passing every clock is a release candidate; HDMI is still the ascal lottery (docs/hdmi_timing.md), so expect some seeds to miss on HDMI only. The arm branches area-timing-ref/-dc/-dbg are not needed.

