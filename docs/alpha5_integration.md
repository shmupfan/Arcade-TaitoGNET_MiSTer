# Alpha 5 integration

Branch `alpha5`, from alpha4b 8d71028, written 2026-10-20. Alpha 5 is the
alpha 4 fixes plus the refactor (comments, licence headers, markers,
archived experiments) plus the public-export folds, on one line. No Quartus
fit, compile PC, MiSTer or push was used for this work.

## 1. Inputs

| Side | Branch, commit | What it brings |
|---|---|---|
| alpha 4 | alpha4b 8d71028 (alpha4-f1 6638e03 + area 0d9310a) | alpha 3 + issue #11 gnet_sd_blank, issue #10 gpu_poly watchdog, issue #12 DDR3 load (GNET_DDR3_LOAD on in GNET_Z1FULLR), F1 GNET_HDMI_FITOC.sdc, area switches GNET_NO_DBG, GNET_NO_DCACHE, zn2_io ZOOM_STUB |
| refactor | refactor-docs 383c88d | comments, SPDX headers, G-NET: markers, PROVENANCE.md, 43 experiment revisions archived (tag experiments-archive), mdec/spu generics, docs/ARCHITECTURE.md |
| public export | public-export 28649a2 | tools/export_public.py, tools/public_manifest.txt, the public repository's hand edits folded into dev, cited tools published |
| build script | a3-calib 5313896 | pc_build.sh push record per SLOT (requested during the merge) |

All three main inputs branch from 24235eb (alpha 3 release RTL);
public-export also contains alpha4 59d57d1.

## 2. Commits on alpha5

| Commit | What |
|---|---|
| 63e732d | Merge refactor-docs (conflicts below) |
| 2776f96 | Merge public-export (no conflicts) |
| ad454c4 | Merge a3-calib 5313896: `builds/pushed_${TARGET}${SLOT:+_$SLOT}.txt` in push and fetch |
| 41be50b | GNET_HDMI_FITOC.sdc in tools/public_manifest.txt; docs/hdmi_timing.md takes the public rewording (gnet-release 972cb88) plus one "our PC" it missed |
| 737020a | Alpha 4 code to the refactor standard; GNET_Z1FULLD archived |
| 20e8915 | docs/ARCHITECTURE.md for the alpha 5 tree |
| bbf2f24 | sim/fullsys: shellcheck SC2046 (tier 0, section 4.6) |

## 3. Conflict resolutions

Every conflict was resolved by keeping the alpha 4 logic and the refactor's
comments, markers and headers.

| File | Conflict | Resolution |
|---|---|---|
| PSX.sv, gnet_flash_dl | alpha 4 added a GNET_DDR3_LOAD branch (`flash_download \| flc_busy`); the refactor added a G-NET: comment above `ifdef GNET_ZN2 | Refactor comment first, then the alpha 4 `ifdef GNET_DDR3_LOAD / `elsif GNET_ZN2 chain unchanged |
| PSX.sv, download write path | alpha 4 put the copier's write path and ioctl_wait ahead of upstream's `if(exe_download ...)`; the refactor added a G-NET: comment on that `if` | alpha 4 block, then the refactor comment directly above the `if` |
| PSX.sv, macro table | alpha 4 added the area localparams after the GNET_NO_MDEC `endif`; the refactor removed GNET_NO_MDEC (MDEC always built) | Area block kept, the stray `endif dropped, comment marked "G-NET: area switches" |
| rtl/psx_top.vhd, gzndbg | alpha 4: `ZN2_BOARD = 1 and ZN2_DBG = 1`; refactor: comment that the block is built in every ZN2_BOARD build | alpha 4 condition; comment merges both (built with ZN2_DBG = 1, the release sets 0) |
| rtl/gnet/zn2_io.vhd, mailbox | alpha 4 moved the mailbox declarations into the ZOOM_STUB generate; the refactor added a comment to the old declarations | Declarations stay in the generate; the refactor comment moved with them, reworded; the header no longer says the stub is still built with ZOOM = 1 |
| tools/pc_build.sh, header and targets | alpha 4 added target z1fulld; the refactor cut the list to z1fullr, z1fullo, psx, psxsw | Reduced list; SLOT, AFFINITY (default 0000FFFF), BUILD_DATE and the NUL-separated push (alpha 4, auto-merged) kept; z1fullr's description names the alpha 4 additions; usage print range 2-51 for the longer header |
| GNET_Z1FULL.qsf, GNET_Z1FULLB.qsf, GNET_Z1SHELL.qsf | deleted by the refactor, alpha 4 added the gnet_sd_blank.sv line | Stay deleted (archived experiment revisions) |

Also archived, not a git conflict: GNET_Z1FULLD.qsf (issue #12 test
revision = GNET_Z1FULLR + GNET_DDR3_LOAD). GNET_Z1FULLR sets the macro
itself since alpha 4 and the reduced target list has no z1fulld. The copy
in alpha4b also lacks gnet_sd_blank.sv. docs/experiment_revisions.md says
how to restore it (`git show alpha4b:GNET_Z1FULLD.qsf`; branch
i12-ddr3load keeps it).

Auto-merged files both sides changed (cpu.vhd, gpu_poly.vhd, psx_mister.vhd,
zn2_board.vhd, GNET_Z1FULLR.qsf, and the PSX.sv and psx_top hunks without
conflict) were checked at token level (section 4.2). public-export and the
alpha 5 line overlap only in docs/r1_cpu_domain_design.md,
docs/zoom_board_design.md and tools/lint_psx.py, with disjoint hunks.

## 4. Refactor standard applied to the alpha 4 code (737020a)

- New own files: rtl/gnet/gnet_sd_blank.sv, gnet_ddr3_flcopy.sv,
  gnet_ddr3_gmux.sv and GNET_HDMI_FITOC.sdc have the SPDX line and Origin
  and Evidence lines with their benches. gnet_ddr3_gmux.sv names its b
  master in this tree (gnet_ddr3_flcopy; gnet_card_sector is on branch
  ddr3-card only).
- Upstream files: every alpha 4 hunk carries "G-NET:" (PSX.sv DDR3 load,
  copier write path, glue port, area switches, GNET_NO_DBG RGB, issue #11;
  cpu.vhd and psx_top.vhd HAS_DCACHE and ZN2_DBG; gpu_poly.vhd issue #10).
  The notices of PSX.sv, psx_top.vhd, psx_mister.vhd, cpu.vhd and
  gpu_poly.vhd name the changes and commits.
- Stale refactor comments corrected: PSX.sv's debug overlay was "built
  into the release", zn2_io's stub was "still built" with ZOOM = 1.
- PROVENANCE.md: a "Changes since alpha 3" table, the note that
  gpu_poly.vhd's watchdog change applies to every build (revision PSX
  included; a generic is a planned step), and the alpha 4 commits in the
  appendix.
- docs/ARCHITECTURE.md (20e8915): every PSX.sv, psx_top, psx_mister and
  GNET_Z1FULLR.qsf line citation moved to the merged files (mapped by line
  alignment, then spot-checked); DDR3 load (4.4, 5.1), F1 and area (3.3),
  three macros and the FITOC SDC (6.1), generics HAS_DCACHE and ZN2_DBG
  (6.2), debug overlay out and scandoubler blanking (6.3), open items
  (C094, gpu_poly, mailbox stub gone).

## 5. Gates

All run on alpha5 bbf2f24 unless stated.

### 5.1 Upstream markers

`python3 tools/upstream_marks.py --all`: exit 0, TOTAL marked 294, closing
17, mechanical 118, renamed 49, wrapped 9, whitespace 0, **unmarked 0**.
Before the marker pass it reported 3 unmarked hunks (cpu.vhd 2, gpu_poly.vhd
1).

### 5.2 Comment-only against alpha4b

`tools/comment_only_check.py --base alpha4b --head bbf2f24 --qsf
GNET_Z1FULLR.qsf --allow-new .md,.py,.tsv,.txt,.sh --ignore 'docs/*'`:
OK 110, DELETED 75 (the archived revisions and fits), ADDED 7 (MAME Lua
scripts from public-export), UNCHECKED 20 (scripts, .gitignore, .tpl),
CHANGED 6. Every CHANGED file is a logic change that alpha4b does not have
and that comes from one of the merged lines:

| File | Logic difference against alpha4b | From |
|---|---|---|
| PSX.sv | GNET_ZOOM_SDRAM, GNET_RAM_B2B_WINDOW, GNET_NO_MDEC branches removed | refactor 6bd6952 (experiment-only macros; GNET_Z1FULLR sets none of them) |
| rtl/mdec.vhd, rtl/spu.vhd, rtl/psx_top.vhd | generics IDCT_REG_STAGE, MLAB_WR_NEGEDGE (0 = upstream) and their maps from psx_top | refactor 55d6e91 |
| sim/mdec/tb_mdec_equiv.vhd | STAGE generic for the bench | refactor 55d6e91 |
| sim/gnet_ata/tb_ata_t2.sv | test key 12 34 56 78 9A instead of a game's card key | public-export (the public repository's key, kept by refactor 383c88d's citation check) |

Token-level three-way check (a scratch script over the same comment
stripping, run on 20e8915; bbf2f24 changes only shell scripts): for each
of the 99 HDL, .qsf and .sdc files that differ between alpha4b and alpha5, every logic hunk against alpha4b must be a
hunk of refactor-docs against 24235eb, and every logic hunk against
refactor-docs must be a hunk of alpha4b against 24235eb. 98 pass; the one
exception is tb_ata_t2.sv's key above (from public-export). So the merge
took the refactor's comments everywhere and changed no alpha 4 logic.

The marker and standard commit 737020a alone, against its parent: OK on
every HDL, .qsf and .sdc file it touches (PSX.sv 21,027 tokens, 17,637
preprocessed); the only non-comment change is the GNET_Z1FULLD.qsf
deletion.

### 5.3 PSX.sv preprocessed

PSX.sv run through `verilator -E -P` (tools/comment_only_check.py's
preprocess, sys/ on the include path; sys/ is identical in both trees) with
the GNET_Z1FULLR.qsf macros, which are identical on both sides (29), then
comments stripped and tokenised: alpha4b 17,637 tokens, alpha5 17,637,
**identical**. The same holds with PSX.qsf's macros (12,206 tokens,
upstream build) and GNET_Z1FULLO.qsf's (17,292).

### 5.4 Lint

`~/.claude/hooks/lint_on_edit.py` on every file changed by the merges and
the later commits (14 files in the standard pass, 6 shell scripts): 0
errors. Advice only, unchanged from before: PSX.sv's build_id.v stub and
cpu.vhd's missing altera_mf library on this machine. A Python count of em
and en dashes over all 173 changed text files: none added against alpha4b.

### 5.5 Public export

`tools/export_public.py bbf2f24 --public-repo <gnet-release> --public-ref
main --out <scratch> --compare main`: exit 0, 709 files (619 from dev, 90
public-owned), **scrub: 0 hits**, 0 cited paths missing.
GNET_HDMI_FITOC.sdc is in the export and every file line of the exported
GNET_Z1FULLR.qsf names a file in the export. Against public main 4f21d12:
533 identical, 124 changed, 52 added, 4 removed (the archived CDC fit top
and CPU-rate STA scripts). Two changed dev files drop public-only lines,
both decided earlier: docs/m4_shell.md (tools/public_doc_sides.tsv: dev
wins, the dropped lines are the alpha 1 text) and tools/lint_psx.py (the
usage example names GNET_Z1FULLR instead of GNET_Z1FULLO, as on
public-export).

### 5.6 Regression net, tier 0

`tools/regress/regress.sh tier0 --tree <alpha5 worktree> --jobs 2` from the
regress-a3 worktree:

| Part | alpha4b 8d71028 | alpha5 before bbf2f24 | alpha5 bbf2f24 |
|---|---|---|---|
| files | WARN, 94 rtl files without SPDX or licence line | WARN, 37 | WARN, 37 (upstream PSX_MiSTer files, which get no header by policy; every rtl/gnet and rtl/zoom file has SPDX) |
| vhdl, verilog, ports, python | PASS | PASS | PASS |
| shell | FAIL, 6 new | FAIL, 6 new | **PASS**, 0 new |
| verdict | FAIL | FAIL | **PASS** in 10 s |

The 6 shell findings were alpha 4's: sim/fullsys/*.sh (from branch
fullsys-sim) left `$(git rev-parse $REF)` unquoted (SC2046); bbf2f24 quotes
it. Tier 1 and tier 2 were not run (tier 2's overnight run is in progress).

## 6. Open items carried into alpha 5

- Full DDR3 load (flash and card addresses) gives ERROR C094 on hardware
  with the alpha 4 RBF; investigated on branch i12-ddr3load, not touched
  here. Old MRAs boot.
- gpu_poly.vhd's issue #10 change is unconditional (PROVENANCE.md).
- Revision PSX has not been re-checked against unmodified PSX_MiSTer since
  2026-10-04.

## 7. Build request

- Branch `alpha5`, commit bbf2f24 or later (later commits on alpha5 touch
  docs only), worktree ../gnet-mister-alpha5 (builds/ is the shared
  gnet-mister-a3cal builds folder).
- Revision GNET_Z1FULLR, target z1fullr, as committed (Aggressive
  Performance, GNET_HDMI_FITOC.sdc read by the fitter only).
- Four-seed sweep: seeds 1, 2, 3 and 4, one SLOT per seed
  (`SLOT=s1 SEED=1 tools/pc_build.sh z1fullr push`, then `task`, `run`,
  `fetch` with the same SLOT and SEED; the push record is per SLOT since
  5313896), so the fits compare seed by seed with the 20261020_1848 alpha 4
  sweep and the area sweep.
- Gates per build: every clock meets setup at Slow 1100mV 100C and hold at
  every corner (clk1x_hold.tcl hold1x and hold2x included); fit report has
  pll_hdmi counter[0] at PLLOUTPUTCOUNTER_X0_Y5_N1 (issue #8);
  compile.log has the GNET_HDMI_FITOC message once, from quartus_fit, and
  not from quartus_sta.
- Area per build (tools/fit_entities.py, as docs/area.md 7): no
  zn_dbg_overlay, zn_dbg_regs or cpu datacache; zn2_io 4 M10K; M10K total
  about 397; ALMs about 330 to 400 below the alpha 4 fit of the same seed.
- Report per seed: ALMs, M10K, worst setup slack on the HDMI clock,
  clk_cpu and clk_cpu2x, against the alpha 4 and area sweeps.
- Since the RTL equals alpha4b's for GNET_Z1FULLR (section 5.3), the
  netlist should match an alpha4b build of the same seed apart from the
  build date; a different result points at the flow, not the merge.
