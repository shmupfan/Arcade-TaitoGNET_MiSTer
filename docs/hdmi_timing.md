# HDMI setup timing in GNET_Z1FULLR (post-RMA plan, step 3)

Branch `hdmi-timing` from 24235eb. Written 2026-10-20 from the fetched reports only; no Quartus run was made for this note. Every slack below is quoted from a `.sta.summary`, `.sta.rpt` or a Tcl report in a `builds/` folder, path given.

## Summary

- **Failing logic.** The HDMI clock (`pll_hdmi|...|counter[0].output_counter|divclk`, 6.732 ns, 148.5 MHz in the SDC) fails setup only on paths that start and end in that clock: the Setup Transfers table of seed 4 lists `pll_hdmi ... -> pll_hdmi ...  138746` RR paths, and every transfer from another clock into it is `false path`. No crossing and no shell (PSX.sv, rtl/gnet) logic is involved.
- **Path family.** The only path-level report I have for a failing HDMI fit (2026-10-07 z1fullos, seed 2) names three families, all inside the framework scaler `sys/ascal.vhd` (output side, `o_clk`): the horizontal accumulator `o_hacc_next -> o_hacc_next`, the horizontal phase divider `o_div[2] -> o_hfrac[1]`, and `o_vacpt -> o_vpixq_pre`. The 2026-10-20 seed 1, 3 and 4 reports carry summaries only, so whether the same families fail there is not yet measured; `tools/sta/hdmi_paths.tcl` gets it from the kept databases.
- **Cause.** Placement in an 87 % full device. `sys/` is byte-identical (md5) to the five glue cores and unchanged since upstream commit 480094b; G-NET builds a smaller scaler than upstream PSX (adaptive and YC disabled). The same scaler meets with +0.135 to +0.729 ns in all 30 glue-core STA summaries (33 to 72 % ALMs where the fit summary was kept), while unmodified upstream PSX_MiSTer at 97 % on my build PC failed at -0.332, GNET_Z1FULLR at 84 to 87 % ranges from -0.408 to +0.344 over seeds and nearby commits, and five seeds of one commit (1f6d3dc) span -0.227 to +0.260.
- **Not a false path or multicycle.** All three families are single-cycle by construction (details below). The quasi-static sources (`o_hsize`, `o_ihsize`, ...) are already false paths in `sys_top.sdc`.
- **Fixes, smallest first.** F1 fitter-only over-constraint of the HDMI clock (constraint only, committed here as `GNET_HDMI_FITOC.sdc`); F2 a placement region for ascal (only if F1 fails); F3 a behaviour-identical rewrite of the `o_hacc_next` recurrence in ascal.vhd (documented, not applied: framework RTL); F4 the other two families (documented only).

## 1. Seed results

Release revision GNET_Z1FULLR, all at 84 to 87 % ALMs. Slack and TNS from `GNET_Z1FULLR.sta.summary` (Setup, HDMI clock; plus any other failing clock), seed from the fit report line `Fitter Initial Placement Seed`.

| Build folder | Source | Seed | ALMs | HDMI setup slack / TNS | Other failure |
|---|---|---|---|---|---|
| gnet-mister-a3cal/builds/20261020_1742_z1fullr_seed1 | 1f6d3dc | 1 | 36,459 (87 %) | -0.010 / -0.035 | none |
| .../20261020_1743_z1fullr_seed2 | 1f6d3dc | 2 | 36,448 (87 %) | 0.131 / 0.000 | none (only clean fit of the five) |
| .../20261020_1743_z1fullr_seed3 | 1f6d3dc | 3 | 36,494 (87 %) | -0.186 / -0.791 | none |
| .../20261020_1743_z1fullr_seed4 | 1f6d3dc | 4 | 36,482 (87 %) | -0.227 / -0.629 | none |
| .../20261020_1706_z1fullr_seed8 | 1f6d3dc | 8 | 36,418 (87 %) | 0.260 / 0.000 | clk_cpu2x (pll_cpu general[1]) setup -0.311 |
| .../20261015_1654_z1fullr | a3-calib | 5 | 36,411 (87 %) | 0.122 / 0.000 | Hold emu pll general[1] -0.420 |
| .../20261015_1803_z1fullr | a3-calib | 6 | 36,413 (87 %) | -0.054 / -0.502 | none |
| .../20261015_1957_z1fullr | a3-calib | 7 | 36,401 (87 %) | 0.237 / 0.000 | clk_cpu (pll_cpu general[0]) setup -0.260 |
| .../20261015_2100_z1fullr | a3-calib c853da8 | 8 | 36,441 (87 %) | 0.017 / 0.000 | none (alpha 3 release) |
| gnet-mister-alpha3/builds/20261015_1112_z1fullr_seed4 | alpha3 | 4 | 36,329 (87 %) | -0.408 / -9.819 | |
| gnet-mister-alpha3/builds/20261015_1010_z1fullr | alpha3 | 3 | 36,266 (87 %) | 0.050 / 0.000 | |
| gnet-mister-alpha3/builds/20261015_0909_z1fullr_seed3 | alpha3 | 3 | 36,258 (87 %) | 0.263 / 0.000 | |
| gnet-mister-alpha3/builds/20261015_0803_z1fullr | alpha3 | 2 | 36,278 (87 %) | 0.290 / 0.000 | |
| gnet-mister-alpha3/builds/20261014_2309_z1fullr | alpha3 | 2 | 36,269 (87 %) | 0.093 / 0.000 | |
| gnet-mister-a3sta/builds/20261015_1213_z1fullr | a3-sta | 3 | 36,429 (87 %) | 0.344 / 0.000 | |
| gnet-mister-a3pf/builds/20261015_1316_z1fullr | a3-prefetch | 3 | 36,589 (87 %) | 0.214 / 0.000 | |
| gnet-mister-a3nm/builds/20261015_0013_z1fullr | a3-nm | 2 | 35,329 (84 %) | 0.085 / 0.000 | |

Of these 17 fits, HDMI setup failed on 5 and was below +0.1 ns on 4 more. On the current tree (1f6d3dc) 1 of 5 seeds met every clock. The 20261020_1640_z1fullr_seed8 folder is the bit-identical P-core rebuild of the 2100 release and is not counted twice.

Corrections to the brief, from the reports:
- The a3-calib seeds are 5 to 8 (folders 20261015_1654 to 2100). Seed 6 missed HDMI by 0.054 (commit ac79ada says the same); seed 7 met HDMI (+0.237) and failed clk_cpu (-0.260). The "seed 4" HDMI failure of alpha 3 week is gnet-mister-alpha3/builds/20261015_1112_z1fullr_seed4 (-0.408, TNS -9.819), an earlier tree. 20261015_1551_z1fullr (seed 4 of a3-calib) has no STA report (commit 2a171d1: seed 3 did not route; the 1551 folder has no `.sta.rpt`).
- GNET_Z1FULLR is not built in Balanced mode. GNET_Z1FULLR.qsf line 32 has `OPTIMIZATION_MODE "AGGRESSIVE PERFORMANCE"` (inherited from upstream PSX.qsf), the fit report says `Info (16303): Aggressive Performance optimization mode selected` (fit.rpt line 15460, seed 4) and the map report `Timing-Driven Synthesis ; On` (map.rpt line 1046), with `Placement Effort Multiplier 1.0` (mode default 4.0). quartus_compile_pc.md already records this exception; it is unchanged here.
- The release QSF has `TIMEQUEST_MULTICORNER_ANALYSIS OFF` (as upstream and the glue cores), so the flow's STA and the gate see only `Slow 1100mV 100C Model`. On the one failing build with a Tcl report for both slow corners (z1fullos below) the -40C corner was worse: -0.307 against -0.233.

## 2. Path detail

### 2.1 What the 2026-10-20 reports contain

`GNET_Z1FULLR.sta.rpt` (seed 3 and 4) has the summary panels only: Setup Summary, Fmax, Setup/Hold Transfers, Unconstrained Paths, Messages. No path list. What it does settle:

- Setup Transfers (seed 4): `pll_hdmi|...|divclk ; pll_hdmi|...|divclk ; 138746` RR paths. Every row into the HDMI clock from another clock reads `false path` (from emu pll2, emu pll general[0], sysmem h2f_user0_clk). There is no pll_cpu row into HDMI at all. So the failing paths are HDMI to HDMI.
- The emu side has no HDMI-clocked logic: PSX.sv drives only `HDMI_FREEZE`, `HDMI_BOB_DEINT`, `HDMI_BLACKOUT` (static OSD bits) and `CLK_VIDEO`; `emu` has no HDMI clock input.
- HDMI-domain logic in sys_top (fit.rpt, Fitter Resource Utilization by Entity, seed 4, ALMs needed): `ascal:ascal` 1923.1, `osd:hdmi_osd` 544.2, `pll_hdmi_adj` 542.1 (clocked by FPGA_CLK1_50, not HDMI), `shadowmask:HDMI_shadowmask` 136.6, `vga_out:vga_scaler_out` 155.1, `csync:csync_hdmi` 24.5. ascal is most of it.
- TNS against worst slack: seed 3 -0.791 over a worst of -0.186 and seed 4 -0.629 over -0.227 mean several failing endpoints each (TimeQuest TNS sums the worst slack per failing endpoint); alpha3 seed 4's -9.819 over -0.408 means dozens.

### 2.2 The one HDMI path report I have: 2026-10-07 z1fullos, seed 2

`gnet-mister-spu/builds/20261007_0604_z1fullos/` (GNET_Z1FULLO, 35,098 ALMs, 84 %, setup HDMI -0.233 in its sta.summary) has `hdmi_setup_7_slow_1100mv_100c.rpt` and `hdmi_setup_7_slow_1100mv_n40c.rpt` (20 worst paths each, summary). Lines quoted as Slack ; From ; To ; Relationship ; Clock Skew ; Data Delay:

Slow 1100mV 100C:
```
-0.233 ; ascal:ascal|o_hacc_next[3] ; ascal:ascal|o_hacc_next[13]     ; 6.732 ; -0.109 ; 6.656
-0.219 ; ascal:ascal|o_hacc_next[1] ; ascal:ascal|o_hacc_next[13]     ; 6.732 ; -0.109 ; 6.642
-0.156 ; ascal:ascal|o_hacc_next[2] ; ascal:ascal|o_hacc_next[13]     ; 6.732 ; -0.114 ; 6.574
-0.121 ; ascal:ascal|o_vacpt[5]     ; ascal:ascal|o_vpixq_pre[3].r[0] ; 6.732 ; -0.564 ; 6.089
-0.118 ; ascal:ascal|o_hacc_next[3] ; ascal:ascal|o_hacc_next[11]     ; 6.732 ; -0.109 ; 6.541
```
19 of the 20 paths are `o_hacc_next[1..7] -> o_hacc_next[9|11|13]`, one is `o_vacpt -> o_vpixq_pre`.

Slow 1100mV -40C:
```
-0.307 ; ascal:ascal|o_div[2][20]   ; ascal:ascal|o_hfrac[1][4]       ; 6.732 ; -0.637 ; 6.202
-0.272 ; ascal:ascal|o_hacc_next[3] ; ascal:ascal|o_hacc_next[13]     ; 6.732 ; -0.097 ; 6.707
-0.130 ; ascal:ascal|o_div[2][7]    ; ascal:ascal|o_hfrac[1][4]       ; 6.732 ; -0.637 ; 6.025
```
Here the paths are `o_hacc_next -> o_hacc_next` and `o_div[2] -> o_hfrac[1][4]`.

All three are the same clock to itself, relationship 6.732 ns, inside one entity (`ascal`, framework code). The `o_div` and `o_vacpt` paths carry -0.564 to -0.637 ns of clock skew, which points at the two ends being placed far apart; the `o_hacc_next` paths have ordinary skew (-0.1 ns) and 6.5 to 6.7 ns of data delay for a loop of about two adders, which points at routing detours.

### 2.3 The logic behind each family (sys/ascal.vhd)

- **`o_hacc_next` (Scalaire process, state `sCOPY`, lines 2232 to 2244).** Per copied pixel: `dif_v := (o_hacc_next - 2*o_hsize + 8*OHRESH) MOD (8*OHRESH)`; if `dif_v >= 4*OHRESH` then `o_hacc_next <= o_hacc_next + 2*o_ihsize`, else `o_hacc_next <= (dif_v + 2*o_ihsize + 4*OHRESH) MOD (4*OHRESH)`. OHRESH is 4096 here (OHRES default 2304), so this is a 15-bit subtract, its sign, a 14-bit add on the subtract's result and a 2:1 mux, all in one cycle, feeding back into itself. `hcarry_v` (the same sign) also drives `o_hacpt`, `o_last`, `o_sh`, `o_acpt` and `o_ad`.
- **`o_div` to `o_hfrac` (HSCAL process, lines 2527 to 2610).** A non-restoring 8-bit divider of `o_hacc*256` by `o_hsize`, two conditional add/subtract steps of 21 bits per cycle; the last stage writes `o_hfrac(1)`.
- **`o_vacpt` to `o_vpixq_pre` (vertical pipeline, lines 2896 to 2916).** `o_vacpt > o_ivsize` and `= o_ivsize` (12-bit compares) select which of the line-buffer pixels form `o_vpixq_pre` (4 pixels x 24 bits), under `o_ce`.

### 2.4 False path or multicycle?

- `o_hacc_next`: no. The Scalaire process has no clock enable (`IF rising_edge(o_clk)`), and in `sCOPY` with `o_dshi=0` the register is rewritten every `o_clk`; it is the per-pixel step of the horizontal resampler. A multicycle would be wrong.
- `o_div` to `o_hfrac`: no. HSCAL runs every `o_clk` without an enable; each stage takes the previous stage's register every cycle.
- `o_vacpt` to `o_vpixq_pre`: not provable from the RTL. `o_vacpt` changes once per output line, but the capture at `o_vpixq_pre` happens on every `o_ce` cycle, and nothing in the code guarantees that the cycles right after an `o_vacpt` update are blanked. Upstream does not constrain it either. Not called false or multicycle.
- The sources that really are quasi-static are already handled upstream: `sys_top.sdc` has `set_false_path -from {ascal|o_ihsize*}`, `-from {ascal|o_hsize* ascal|o_vsize*}`, `-from {ascal|o_hmin* ...}` and so on, and the seed 4 STA messages show no "Ignored filter" warning for those lines (only lines 6, 13, 17 and 63 of sys_top.sdc are reported as ignored), so they match. The failing paths therefore start at registers that change every cycle.
- Relaxing the HDMI clock itself is not legitimate: 6.732 ns is 1080p60 (148.5 MHz), a mode MiSTer users run.

## 3. Comparison with upstream and other cores

- **Framework source.** `md5` of `sys/ascal.vhd`, `sys/sys_top.v` and `sys/sys_top.sdc` is identical in gnet-mister-hdmitiming, hyperduel-mister, dooyong-mister, tecmo16-mister, dec8-mister and 1945kiii-mister (1b17376e..., f22545a2..., d7face00...). `git log -- sys/` ends at 480094b (TheJesusFish, 2026-08-07, "Sys update and hotfix"); no G-NET commit touches `sys/`.
- **Scaler configuration.** ascal parameters come from QSF macros. Upstream PSX.qsf (357766b): `MISTER_FB`, `MISTER_DOWNSCALE_NN`, `MISTER_DISABLE_ALSA`; adaptive and YC enabled. GNET_Z1FULLR adds `MISTER_DISABLE_ADAPTIVE` and `MISTER_DISABLE_YC`, so its HDMI domain is a subset of upstream's. Hyper Duel uses none of the macros (adaptive on, no FB) and Dooyong only `MISTER_FB`: their scalers are at least as large as G-NET's.
- **Same scaler, emptier devices.** HDMI setup slack in every glue-core `sta.summary` under `*/builds/`: 1945k III +0.266 to +0.729 (41 %), DEC8 +0.277 to +0.478 (40 to 41 %), Dooyong +0.135 to +0.574 (55 % where recorded), Hyper Duel +0.174 to +0.441 (72 % where recorded), Tecmo 16 +0.257 to +0.452 (33 to 34 %). 30 summaries (1945k III `c3` repeats the 0516 figures), none negative.
- **Upstream PSX_MiSTer on my build PC.** gnet-mister/builds/20261004_1426_psx (SOURCE_PUSHED: "357766b Merge MiSTer-devel/PSX_MiSTer main (cd17b5a) as the base; RTL unmodified upstream"), seed 1, 40,456 ALMs (97 %): HDMI setup -0.332, TNS -0.579. The framework scaler does not meet 148.5 MHz in a near-full PSX build without seed luck, before any G-NET change.
- **G-NET history.** Failing HDMI fits also appear at lower fill: GNET_F0_LEAN 76 % -0.209, GNET_F0_CPU50E5 64 % -0.085, GNET_Z1 70 % -0.252 (TNS -6.048), GNET_Z1_ZOOM 79 % -0.149 (TNS -3.576), each next to passing fits of the same revision family. So the PSX-based design places the scaler worse than the glue cores do at similar fill; a reasonable reading (not measured) is that the PSX GPU, SDRAM and DDR3 logic compete for the same region near the HPS memory interface and the HDMI pins.
- **The G-NET video changes.** The 480i output fix, `gnet_arcade_video` (786.2 ALMs in seed 4), crop and rotate (`GNET_ROT_DDR`) all run on `clk_vid` or `clk_sys` inside `emu`, plus the framebuffer read that upstream PSX also has (`MISTER_FB`). None adds a register in the HDMI domain; they add to the total fill.
- **Physical fill.** Seed 4: "ALMs needed" 36,482 (87 %) but `[A] ALMs used in final placement` 38,652.9, which is 92 % of 41,910 before dense packing recovery.

## 4. Fixes, smallest first

### F1. Fitter-only over-constraint on HDMI (committed on this branch)

Change: new `GNET_HDMI_FITOC.sdc`, added last to `GNET_Z1FULLR.qsf` (`set_global_assignment -name SDC_FILE GNET_HDMI_FITOC.sdc`):
```tcl
set gnet_hdmi_clk {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set gnet_fit_oc 0.25
if {[info exists ::TimeQuestInfo(nameofexecutable)] && \
    $::TimeQuestInfo(nameofexecutable) eq "quartus_fit"} {
  set_clock_uncertainty -setup -add \
    -from [get_clocks $gnet_hdmi_clk] -to [get_clocks $gnet_hdmi_clk] $gnet_fit_oc
  catch { post_message -type info "GNET_HDMI_FITOC: fitter over-constraint +$gnet_fit_oc ns setup on HDMI to HDMI" }
}
```
Why it is correct: it changes nothing in the design and nothing in sign-off. Only quartus_fit sees 0.25 ns of extra setup uncertainty on HDMI to HDMI paths, so placement and routing keep that much margin there; quartus_sta (flow STA, the gate, `tools/sta/*.tcl`) skips the block and times the real 6.732 ns with the derived uncertainty. This is Intel's documented fitter over-constraint pattern (`$::TimeQuestInfo(nameofexecutable)`). The evidence in section 3 says the HDMI failures are placement-limited (one commit, 1f6d3dc, spans -0.227 to +0.260 over five seeds), which is what fitter priority changes. 0.25 ns covers every failure on the current tree (-0.010 to -0.227) with a small margin; -0.408 (alpha3 seed 4) would still need luck.

Risk: the fitter's effort moves. clk_cpu2x (+0.085 to +0.349 on the passing seeds of 1f6d3dc, -0.311 on seed 8) and clk_cpu (-0.260 on a3-calib seed 7) are also marginal, so F1 can shift failures to them instead of removing them. It cannot hide a real failure (STA is unchanged). The `-add` and the `TimeQuestInfo` check have not been exercised on this PC yet; the first fit must confirm both (below).

Verify the mechanism on the first F1 fit: `compile.log` contains `GNET_HDMI_FITOC: fitter over-constraint` from the quartus_fit step and not from the quartus_sta step (if `post_message` is not available inside SDC evaluation the line is silently absent; then check instead that the fit and STA HDMI slacks differ from the same seed without F1). The `.sta.rpt` Clocks panel and the 6.732 relationship must be unchanged.

### F2. Placement region for the scaler (only if F1 is not enough)

Change: a Logic Lock region for `ascal:ascal` (and `osd:hdmi_osd`, `shadowmask:HDMI_shadowmask`, `csync:csync_hdmi`, `vga_out:vga_scaler_out`) in the QSF, sized from where the passing seeds place it. Why: it would make the scaler's placement the same on every seed, which is the variable that decides HDMI slack. Risk: high. A region in the wrong place, or too small for its 1,923 ALMs plus M10K line buffers, makes every seed worse; it constrains the fitter in an already 92 % placed device; Logic Lock support and syntax in 17.0 Lite needs-review. Needs Chip Planner on a passing (seed 2) and a failing (seed 4) database to choose the region. Not drafted.

### F3. One-adder `o_hacc_next` recurrence in ascal.vhd (documented, not applied)

Only worth doing if `hdmi_paths.tcl` shows `o_hacc_next -> o_hacc_next` still dominates on seeds 3 and 4. It changes framework RTL, so it is not "constraint-only or a clearly correct pipeline stage" and is not committed.

Idea: carry `D = o_hacc_next - 2*o_hsize` (mod 2^15) as its own register, so the branch decision is a register bit and every next value is one add from registers:

```vhdl
-- declarations (Scalaire)
SIGNAL o_hacc_dif, o_hacc_dif_ini, o_hinc2, o_hincd : unsigned(14 DOWNTO 0);
VARIABLE sum_v, dif2_v : unsigned(14 DOWNTO 0);   -- in PROCESS Scalaire

-- next to o_hacc_ini (line 2052, every clock, quasi-static operands)
o_hacc_dif_ini <= to_unsigned((3*o_ihsize - o_hsize + 32768) MOD 32768, 15); -- = o_hacc_ini + 2*o_ihsize - 2*o_hsize
o_hinc2        <= to_unsigned(2*o_ihsize, 15);
o_hincd        <= to_unsigned((2*o_ihsize - 2*o_hsize + 32768) MOD 32768, 15);

-- sWAIT, inside IF o_primv(0)='1' (next to o_hacc_next<=o_hacc_ini + 2*o_ihsize)
o_hacc_dif <= o_hacc_dif_ini;

-- sCOPY, replaces the dif_v block under IF o_dshi=0
IF o_hacc_dif(14)='1' THEN                 -- o_hacc_next < 2*o_hsize
  sum_v  := to_unsigned(o_hacc_next, 15) + o_hinc2;
  dif2_v := o_hacc_dif + o_hinc2;
  o_hacc      <= o_hacc_next;
  o_hacc_next <= to_integer(sum_v(13 DOWNTO 0));
  o_hacc_dif  <= (dif2_v(14) XOR sum_v(14)) & dif2_v(13 DOWNTO 0);
  hcarry_v := false;
ELSE
  sum_v  := o_hacc_dif + o_hinc2;
  dif2_v := o_hacc_dif + o_hincd;
  o_hacc      <= to_integer(o_hacc_dif(13 DOWNTO 0));
  o_hacc_next <= to_integer(sum_v(13 DOWNTO 0));
  o_hacc_dif  <= (dif2_v(14) XOR sum_v(14)) & dif2_v(13 DOWNTO 0);
  hcarry_v := true;
END IF;
o_dcpt_inc <= '1';
```
The XOR on bit 14 reproduces the original's 14-bit wrap of `o_hacc_next` in the carried difference (adding 2^14 mod 2^15 flips bit 14). Why it is correct: a Python model of both recurrences (OHRESH 4096, the original's MOD widths, 600 steps per line) gave identical `(o_hacc, o_hacc_next)` sequences for 60,000 `(o_hsize, o_ihsize)` pairs, all pairs 1 to 63 plus common widths and random pairs up to 4095: "cases 60000, mismatches 0". Equivalence assumes `o_hsize` and `o_ihsize` hold for two clocks before a line starts, the same assumption `sys_top.sdc` already makes by false-pathing from them. Gain: the loop goes from subtract, sign, add, mux to add, mux (and `hcarry_v` becomes a register bit for `o_hacpt`, `o_last`, `o_ad`). Cost: about 75 registers and three 15-bit adders.

Risk: medium. It is a local change to a framework file that every `sys/` update overwrites (keep it as a patch with a check in `pc_build.sh`), and the model covers the recurrence, not the whole scaler. Before any hardware build: an NVC bench of ascal (stock against patched) on a few scaling ratios, comparing every `o_r/o_g/o_b/o_de/o_hs/o_vs` sample bit for bit; then a hardware check at 1080p, 720p, 1280x1024 and with a downscaled mode.

### F4. `o_div -> o_hfrac` and `o_vacpt -> o_vpixq_pre` (documented only)

- `o_div`: splitting the last divider stage adds a cycle to `o_hfrac(1)`, so every C-numbered stage of the horizontal filter (`o_hfrac(2 TO 9)`, `o_hpixq`, `o_copyv`, `o_dcptv_*`) must move by one. Not a clearly correct single register; only if the Tcl run shows this family on the current seeds.
- `o_vacpt`: register the two compare results (`o_vacpt > o_ivsize`, `= o_ivsize`) when `o_vacpt` is updated, so CYCLE 8 selects on flags. Correct only if no displayed pixel uses the flags in the cycle after an `o_vacpt` update; needs the same NVC bench as F3.

## 5. Tcl path report (seed 3 and seed 4 databases)

Script: `tools/sta/hdmi_paths.tcl` on this branch. It opens the project, then for each slow corner (100C and -40C) and each of the HDMI clock, clk_cpu2x and clk_cpu writes: the 200 worst endpoints (summary), the 50 worst with `-detail full_path`, the endpoints under +0.1 ns grouped into from-family to to-family (bus indices folded, count, worst slack, data delay), the worst path from each launch clock, and one corners file with worst slack, TNS and failing endpoint count. Output goes to `output_files/setup_*.rpt`.

Run it with Quartus 17.0 in the folder of a fitted GNET_Z1FULLR project
(after a full compile, so the fitted database is there):
```
quartus_sta -t tools/sta/hdmi_paths.tcl PSX GNET_Z1FULLR setup > sta_hdmi.log 2>&1
```
The reports land in `output_files/setup_*.rpt`. If the QSF's SEED was changed after the fit, quartus_sta prints `Assignment SEED changed value` and still reports the fitted result: the timing netlist comes from the fitted database, so the message can be ignored. Sanity check on the 2026-10-20 seed 3 and seed 4 fits: `setup_corners.rpt` gives hdmi at Slow 100C as -0.186 (seed 3) and -0.227 (seed 4), the values in the flow's sta.summary; if not, the netlist is not the one fitted.

What to read: `setup_hdmi_*_families.rpt` first. If `ascal:ascal|o_hacc_next[*] -> ascal:ascal|o_hacc_next[*]` leads on both seeds, F3 is the structural fix; if the families differ between seeds and spread over ascal, F1 or F2 is the right lever. `setup_cpu2x_*` and `setup_cpu_*` give the same for the CPU clocks on the same placements.

## 6. Verification plan

Every arm is fitted with the same source (current tree, 1f6d3dc or its successor), Balanced/Aggressive setting unchanged, 4 seeds at once (about 30 min a batch), seeds 1 to 8. A seed passes when every clock in the Setup Summary is >= 0 and the hold1x/hold2x corner reports have no failing endpoint.

1. Tcl run on s3 and s4 (section 5). No fit needed.
2. Baseline: seeds 1 to 4 and 8 exist (all-clock pass 1 of 5, HDMI pass 2 of 5); fit seeds 5 to 7 of the same source to complete 8.
3. F1: cherry-pick `GNET_HDMI_FITOC.sdc` and the QSF line, fit seeds 1 to 8. Record per seed the HDMI, clk_cpu2x and clk_cpu setup slack and the hold corners, plus the compile.log check for the over-constraint message.
4. Decide: F1 is kept if the HDMI pass rate rises (target 8 of 8) and the all-clock pass rate rises over the baseline without new clk_cpu/clk_cpu2x failures. Eight seeds per arm is a small sample: a change from 2 of 5 to 8 of 8 is a clear signal, a change of one or two seeds is not. If clk_cpu2x or clk_cpu regress, try `gnet_fit_oc` 0.15 before dropping F1.
5. If HDMI still fails and step 1 named `o_hacc_next`: F3 behind the NVC bench, then seeds 1 to 8 without F1, then with F1, so each effect is measured on its own.
6. Hardware for any kept build: video_info at 1440x1080 and 1920x1080 (the #8 checks), and the HDMI output counter still on PLLOUTPUTCOUNTER_X0_Y5_N1 (`pc_build.sh fetch` check; F1 does not touch that pin).

Release gate unchanged: never deploy a build with negative slack on any clock.
