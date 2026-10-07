# Taito G-NET core plan (Ray Crisis, Psyvariar, XII Stag, Shikigami no Shiro, Night Raid)

Status (2026-10-07): alpha release, revision GNET_Z1FULLO (README.md,
docs/ACCURACY.md); the first alpha (2026-10-06) was revision GNET_Z1FULL.
The plan below is kept as written at the start, with later results added
to the research items.

Earlier status: F0 PASSED (2026-10-04): projected 82.4 to 87.5% ALM (docs/f0_budget.md 5).
M0 in progress. No G-NET RTL yet.
M4 shell (2026-10-05, branch gnet-shell, docs/m4_shell.md): revision
GNET_Z1SHELL (target z1shell, not fitted). DV1 pixel clock is integer in
every G-NET mode (no PLL change); Flip Screen, pause, volume, MAME keys,
black picture with running sync, CRT H/V position, scandoubler Fx,
EEPROM NVRAM save, README done; rotation waits for the DDR3 arbiter
branch. Minimum-standard gaps still open: button names for four games
(game manuals), audio level match after the Zoom mix, high score and
card-write saving; 216p crop left out on purpose (240-line output).

Next target of the shmup programme after the glue cores, and the first
that is not a glue core: Taito G-NET is a Sony ZN-2 (PlayStation-derived) board plus
Taito's FC PCB (Taito Zoom sound board, five flash chips, a PCMCIA card
slot). Every major chip already has FPGA RTL in public, GPL code written by
other people (docs/hardware_inventory.md), so the work is integration,
G-NET glue, verification and fitting.

My standing rule: accuracy first, document everything. MAME 0.288
(`src/mame/sony/taitogn.cpp`) is the oracle for verification; where MAME is
known or suspected to be less accurate than the hardware, the core follows
the hardware's most plausible behaviour, every divergence from MAME is
classified with its cause, and an open research item names the evidence
that would settle it. Evidence ranking: shmupfan ACCURACY.md
(docs/evidence_sources.md).

Companion documents:

- docs/hardware_inventory.md: every chip and block, clock, MAME file,
  existing FPGA implementation.
- docs/evidence_sources.md: ranked evidence per chip, datasheet library.
- docs/f0_budget.md: DE10-Nano budget.

## 1. Coverage check (2026-10-04)

- No public G-NET core or G-NET work found on GitHub (search for taitogn,
  G-NET MiSTer, Ray Crisis MiSTer, Psyvariar MiSTer); Discord and forum
  work cannot be searched and stays needs-review.
- XelaNotPu's PSX_MiSTer-derived cores (GitHub XelaNotPu, GPL-3.0-or-later)
  cover ZN-1 (four publisher variants, including Taito FX-1B with the full
  Taito Zoom board) and ZN-2 Capcom (coh3002c). Their ZN-2 README says no
  ZN-2 board other than the Capcom variant is covered.
- The four G-NET "VER x.xxG" 2011 bootleg conversions are of games that
  already run on XelaNotPu's ZN-1 cores in their original form (Ray Storm
  and G-Darius on FX-1B with Zoom music; Aero Fighters Special (Visco
  coh1002v, playable) and Brave Blade (Raizing coh1002e, playable, sound
  effects only, no music) on XelaNotPu/ZN1_MiSTer, README checked
  2026-10-04).
- Second TMS57002 RTL exists (ppriest, Konami GX core, GPL-3.0), useful
  as a cross-check of XelaNotPu's.
- Rechecked 2026-10-04 (GitHub API): last pushes ZN2-Capcom_MiSTer
  2026-08-29 and ZN1-TaitoFX1B_MiSTer 2026-08-14; newest repository
  SYSTEMFL_MiSTer-Supporter (2026-09-24). The "pushed 2026-10-01" noted
  earlier was the repositories' `updated_at` metadata, not a push
  (correction). No G-NET mention in their repositories or code search; no
  public repository found for taitogn, G-NET MiSTer, Ray Crisis MiSTer,
  Psyvariar MiSTer or coh3002t. Recheck before M0.

## 2. Sets (MAME 0.288, taitogn.cpp)

All target sets share one machine: `coh3002t` BIOS (ZN-2, CXD8661R at a
100 MHz crystal, CXD8654Q GPU with 2 MB VRAM), FC PCB with Taito Zoom, and
a Taito Type 1 PC card (`coh3002t_t1`, ATA flash card with a 5-byte unlock
key) or, for the bootlegs, a plain ATA flash card (`coh3002t_bl`) with the
MB2011 modified BIOS EPROM. Game data is a CHD hard-disk image in MAME.

| Priority | Set(s) | Game | Card | Zoom | Rotation | Driver state class | Reason for order |
|---|---|---|---|---|---|---|---|
| 1 | raycris, raycrisj | Ray Crisis (V2.03O / V2.03J 1998-11-15) | Type 1 | yes | ROT0 | taitogn_state | Taito's own flagship G-NET shooter; same developer and sound driver family as Ray Storm, whose Zoom path is already bit-exact in XelaNotPu's FX-1B core |
| 2 | psyvarrv; psyvaria, psyvarij | Psyvariar -Revision- (V2.04J 2000-08-11); -Medium Unit- (V2.02O / V2.04J) | Type 1 | yes | ROT270 | ttgncl4_state (coin lockout 2/3) | Rated 4 in the 2026-10-04 ranking; two games from one engine |
| 3 | xiistag | XII Stag (V2.01J 2002-06-26) | Type 1 | yes | ROT270 | taitogn_state | Rated 4 |
| 4 | shikigam, shikigama | Shikigami no Shiro (V2.03J; internal build V1.02J) | Type 1 | yes | ROT270 | taitogn_state | Rated 3 |
| 5 | nightrai | Night Raid (V2.03J 2001-02-26) | Type 1 | yes | ROT0 | ttgncl4_state | Rated 3; MAME notes a second card type (sealed "Type 2" PCB) exists for this game, dump is Type 1 |
| 6 | gdariusg, raystormg | G-Darius (VER 2.70G), Ray Storm (VER 2.60G), 2011 bootleg | plain ATA flash | yes | ROT0 | taitogn_state | Originals already on MiSTer (FX-1B); useful as an A/B check of the Zoom against the FX-1B core |
| 7 | aerofgtsg, brvbladeg | Aero Fighters Special (VER 1.00G), Brave Blade (VER 1.40G), 2011 bootleg | plain ATA flash | no (init_nozoom) | ROT270 | ttgncl0_state / taitogn_state | Originals covered elsewhere; no Zoom, so these exercise only the ZN-2 + card path |

Hardware simplicity does not separate priorities 1 to 5: they are one
machine configuration. The order follows game quality and the value of
verifying Ray Crisis first against the Ray Storm Zoom evidence.

Out of scope: the non-shooter G-NET sets (puzzle, mahjong, RC De Go, Chaos
Heat), Kollon and Space Invaders Anniversary (ttgnirq_state, an IRQ hack in
MAME), the CompactFlash sets (Taito CF lock), and coh1002t / Mawasunda
(G-NET FC PCB on a ZN-1). They reuse the same core and can be added later.

## 3. Architecture (proposal, decided at M0/M4 after G0)

### 3.1 Base

**Chosen (2026-10-04): my own implementation on the official PSX core.**
Start from MiSTer-devel/PSX_MiSTer (Robert Peip): CPU, GTE, GPU, SPU, DMA,
MDEC, timers and IRQs. Trim what G-NET does not have (CD-ROM subsystem,
memory cards, console controllers, savestates, cheats, PAL and console
options), keeping each trim a clean switch so upstream fixes can still be
merged. Write the ZN-2 board layer (boot ROM, CAT702, znmcu model, EEPROM,
2 MB VRAM), the G-NET blocks below and the Taito Zoom sound board
(MN10200, ZSG-2, TMS57002) myself, from datasheets, MAME and board
evidence per the accuracy framework, with the true ZN-2 CPU rate from the
start (R1). XelaNotPu's ZN-2 and FX-1B cores are reference only (evidence
rank 6), credited in the README for anything learned from them; no code
copied without keeping their headers and saying so. An earlier option,
building on XelaNotPu's code, was set aside.

### 3.2 New G-NET blocks (none exist in any FPGA project found)

| Block | MAME | Function | Notes |
|---|---|---|---|
| Flash bank (0x1f000000-0x1f7fffff, bank select from control bit 2 and JP1) | taitogn.cpp flashbank_map | Maps sub-BIOS flash U30 (2 MB), Zoom program flash U27 (512 KB), RF5C296 memory window, wave flashes U56/U55/U29 (3 x 2 MB), bootleg EPROM (1 MB) | Five Intel flash parts with the Intel command set (read array, program, block erase, status). Storage in SDRAM or DDR3 |
| Flash persistence | intelfsh.cpp (MAME saves them as NVRAM) | The BIOS copies part of the card into the flashes on first boot (2 to 3 minutes on the PCB per MAME notes) and boots directly when they match | R3: copy every cold boot (fast or real program timing), save 8.5 MB to SD, or pre-build offline |
| Control registers | control_w/r (0x1fb40000), control2 (0x1fb60000), control3 (0x1fa30000), gn_1fb70000 | Watchdog kick, Zoom reset, flash bank | MAME returns 2 from 0x1fb70000 "strange" (R15) |
| RF5C296 | machine/rf5c296.cpp ("very inaccurate, hardcodes the gnet config") | PCMCIA controller: ExCA index/data at I/O 0x3e0/0x3e1, card reset, I/O and memory windows | R4 |
| PC card | bus/pccard/ataflash.cpp taito_pccard1 | ATA (CompactFlash style) task file, CIS, attribute registers, Type 1 unlock at attribute 0x280-0x288 with the 5-byte key, lock status at 0x201 | Card image: about 40 MB raw (Type 1: ten 32 Mbit NAND, MAME notes). R5, R6, R25 |
| Card storage | n/a | Sector reads for the ATA card | Load the raw image into DDR3 from the MRA, or mount it from the OSD and stream with sd_lba, or use Main_MiSTer's ide.cpp (needs a Main_MiSTer change). Decide at M0 (R25) |
| MB3773 watchdog | machine/mb3773.cpp | Resets the board if not kicked (control bit 5) | R17 |
| Zoom glue changes | taito_zm.cpp, taitogn.cpp zsg2_ext_r | Zoom program from flash U27 instead of ROM; ZSG-2 samples from three 2 MB wave flashes (6 MB, FX-1B core expects 4 MB); Zoom held in reset until the main CPU releases it | |

### 3.3 Memory (first estimate, M0 measures)

| Item | Size | Placement candidate |
|---|---|---|
| Main RAM (2 x KM416V1204BT, MAME default "4M") | 4 MB | SDRAM (as ZN2-Capcom) |
| VRAM (2 x KM4132G271BQ SGRAM) | 2 MB | as ZN2-Capcom |
| SPU RAM (814260) | 512 KB | as PSX_MiSTer |
| BIOS COH3002T (M534002) | 512 KB | SDRAM |
| Flashes U30, U27, U56, U55, U29 | 8.5 MB | SDRAM or DDR3, writable |
| Bootleg EPROM (sets 6-7 only) | 1 MB | same |
| PC card image | ~40 MB | DDR3 (or streamed from SD) |
| MN10200 work RAM | 128 KB (MAME) / 32 KB (LH52B256 on the PCB, R7) | M10K (FX-1B uses 64 KB) |
| TMS57002 delay RAM | 64 KB (FX-1B) / 128 KB (LC321664) / 256 KB (MAME map), R8 | M10K (64 blocks in FX-1B) |
| M66220FP mailbox | 256 B | M10K |

### 3.4 Clocks

ZN-2 crystals per MAME notes: 100 MHz (CPU), 67.73 MHz (SPU and system),
53.693 MHz (GPU dot clock). FC PCB: 25 MHz (ZSG-2; MN10200 and TMS57002 at
12.5 MHz). MAME runs the CXD8661R at clock/4 = 25 M cycles/s against the
ZN-1's 16.93 M (x1.476). XelaNotPu's ZN-2 core runs the CPU at the ZN-1 rate
with memory waits removed as an approximation. A true
ZN-2 CPU rate is the single biggest accuracy question for shooters, where
slowdown is part of the game (R1, R24).

## 4. Milestones

| M | Content | Gate |
|---|---|---|
| G0 | Heads-up to XelaNotPu (and optionally Robert Peip): starting G-NET on PSX_MiSTer, findings shared. Avoids duplicate work; not a gate | Message sent |
| F0 | Trial fit and trim budget: build unmodified PSX_MiSTer in Quartus 17, resource report per module (ALMs, M10K, DSP); confirm from MAME which PSX blocks the G-NET games use (SPU, MDEC: R18); remove unused blocks behind switches, refit, and compare the freed space with estimates for the ZN-2 layer, G-NET blocks and Zoom board | A budget showing the whole system fits the 5CSEBA6, or a documented reason it cannot (stop or rescope) |
| M0 | BIOS and CHD checks (`mame -verifyroms`, `chdman info`, card logical size and key metadata), raw card image extraction, region builder for BIOS, sub-BIOS flash, Zoom flash, wave flashes; MAME 0.288 Lua oracle: frame captures plus write logs for GPU (GP0/GP1 and DMA), SPU, Zoom mailbox and register port, flash commands, RF5C296 and ATA task-file traffic, card unlock, control registers, from power-on through the first-boot flash copy to attract and gameplay; datasheet library (evidence_sources.md); docs/m0_findings.md settling which R items MAME alone answers | 7 priority groups verified; every MAME device access during boot classified; regions byte-identical to MAME's NVRAM after first boot |
| M1 | Video: the PSX_MiSTer GPU (as built in the chosen base) replayed in Verilator against the M0 GPU command streams; frames against MAME. Differences classified against PS1 hardware test results (evidence_sources.md) before MAME is assumed right. Display timing against the MAME note (59.8260 Hz, 15.4333 kHz) | Every captured frame matches MAME or has a classified, evidenced cause |
| M2 | Full system in Verilator: BIOS boot, sub-BIOS decrypt from U30, card detect and unlock, flash compare/copy, game boot, CAT702, znmcu, EEPROM, inputs, watchdog | Boot from power-on matches MAME's I/O streams, images and RAM at checkpoints; divergences root-caused (CPU rate differences expected and measured) |
| M3 | Sound: Zoom block ported with G-NET glue (flash program, 6 MB wave, reset sequencing), SPU, mix | MN10200 bus, ZSG-2 register and TMS57002 streams equal MAME's; WAV level and balance against MAME, then PCB recordings (R13) |
| M4 | MiSTer: shell from the chosen base, SDRAM/DDR3 layout, card image loading, flash persistence, MRAs (sets in section 2, DIP S551, JP1 for bootlegs, rotation), Quartus fit and timing on the compile PC | Board simulation equals M2; fit with timing met on every clock; first RBF |
| M5 | Hardware test on my MiSTer; long play; slowdown and load times against PCB footage; release | All priority sets play; known differences documented |

## 5. Decisions

| Date | Decision | Basis |
|---|---|---|
| 2026-10-04 | Own implementation on the official PSX_MiSTer, trimmed; ZN-2 layer, G-NET blocks and Zoom sound written in-house; XelaNotPu's cores as reference only; a heads-up message, not a permission request | GPL permits the base; own layers avoid forking an active developer's unreleased work; framework favours datasheet-based sound over a MAME port |
| 2026-10-04 | F0 (trial fit and trim budget) first, before any other RTL | Fit is the largest risk (docs/f0_budget.md) |
| 2026-10-04 | R18 MAME trace deferred to M0 (no coh3002t or CHDs yet); F0 fits MDEC off as a measurement only, switch default on | ROMs not available this session |
| 2026-10-04 | Zoom and ZN-2 layer area for the F0 budget measured from unmodified fits of XelaNotPu's FX-1B and ZN2-Capcom cores (measurement only, no code taken) | Better than paper estimates for chips that already exist in RTL |
| 2026-10-04 | PSX_MiSTer merged into this repository with its history (remote `upstream`, main cd17b5a); trims are integer generics on psx_top (default 1 = upstream) set from PSX.sv macros, without re-indenting upstream code | Keeps `git merge upstream/main` clean |
| 2026-10-04 | savestates.vhd stays in every build: in PSX_MiSTer it is also the reset sequencer (reset is a load of reset values through the SS ports). The F0 switch removes only the save/load/rewind request path (statemanager) | rtl/savestates.vhd lines 300-330 |
| 2026-10-04 | New files carry GPL-2.0-or-later headers; the combined core is GPL-3.0-or-later because the MiSTer framework files already are (docs/licensing.md) | docs/licensing.md |

## 6. Research items

| # | Question | Evidence needed |
|---|---|---|
| R1 | CXD8661R execution rate: 100 MHz crystal; MAME uses the same divider as the ZN-1 (25 M vs 16.93 M cycles/s, x1.476). Datasheet reading 2026-10-04: MAME psx.cpp says the PS1 CPU is the LSI CoreWare CW33300 core; the CW33000 manual (CI4002A, datasheets/r3000/) has the core run directly from its system clock PCLKP, and the IDT R3000A/R3051 parts use a double-frequency input clock (Clk2xSys / Clk2xIn) halved on chip. The PS1 halves its 67.7376 MHz crystal to 33.8688 MHz; the same convention gives 50 MHz from 100 MHz, consistent with MAME's ratio, but the Sony divider is undocumented, so this is inference. MAME states no evidence for the ZN-2 rate; its psx.cpp limitations note approximate load/store timing and unknown memory-control registers (com_delay, BIU), and zn.cpp has a TODO 'work around for mismatched CPU & SPU clock?' (a toggling read at 0x1fa60000). Cache and wait states: unknown PCB footage result 2026-10-04 (docs/r1_speed_study.md, rank 4): the westtrade Ray Crisis board (MB2011 BIOS) runs the CPU-bound boot loader in 14.69 s against MAME's 12.34 s; a patched-MAME clock sweep matches it at 82 MHz, i.e. about 0.82 of MAME's ZN-2 model (20.5 M MAME cycles/s against 25.0 M; the ZN-1 rate gives 17.47 s, far too slow). This is an effective rate in MAME's cost model, not a clock: a 50 MHz core with memory wait states could give the same figure. Timing probe (docs/cpu_rate_probe.md): a fit constrained to 50 MHz closes every CPU-side path (+1.96 ns, +76 ALMs). CPU-domain design study 2026-10-05: docs/r1_cpu_domain_design.md (recommended: CXD8661R blocks in their own CPU + 2x domain, GPU and SPU on PS1 clocks). | Rank 1: frequency counter on the CXD8661R clock output, or a timing test program on any CXD8661R board (ZN-2, Namco System 12, G-NET via the MB2011 BIOS and a plain ATA card): loop vs VBlank (53.693 MHz GPU crystal) for the clock, growing loop footprints for cache size, timed loads per region for wait states. Rank 4: frame-counted CPU-bound events in PCB footage (boot phases, slowdown) matched against MAME at swept CPU clocks gives effective throughput only Decision 2026-10-05: target exactly 50.000 MHz (medium confidence; calibrate against the PCB loader once booting). 2026-10-05 recommendations accepted (r1_cpu_domain_design.md, Decisions recorded). |
| R2 | ZN-2 SPU against CPU clock: MAME's zn2_maincpu_program_map has a TODO "work around for mismatched CPU & SPU clock?" (nopr at 0x1fa51c00, a toggling read at 0x1fa60000) | Trace what the BIOS polls there; board logic (EPM7064 CPLD) |
| R3 | First-boot flash copy: what the BIOS writes to U27/U29/U30/U55/U56, in what order, how long it takes with real Intel program/erase times, and what the core should do (copy every boot, persist, pre-build) | MAME trace at M0 (software behaviour); Intel 28F160/28F400 datasheets for timing; PCB footage of a first boot (MAME notes: 2 to 3 minutes) |
| R4 | RF5C296 register behaviour beyond MAME's hardcoded config | RF5C296 / Intel 82365SL (ExCA) documentation; the M0 register trace |
| R5 | Taito Type 1 card lock: attribute register 0x07 writes (0x0e, 0x0a), lock bitmap at 0x201, re-lock on a wrong key | MAME TODOs; a real card on a logic analyser |
| R6 | Card access timing (BSY/DRQ, sector read latency); MAME completes commands without real NAND timing; affects load times | PCB footage of load screens (60 fps); card measurement |
| R7 | MN10200 work RAM: MAME maps 128 KB at 0x400000; MAME's FC PCB layout shows one LH52B256 (32 KB) SRAM | PCB photos or schematic; MN1020012A manual (internal RAM) |
| R8 | TMS57002 external data memory: MAME maps 256 KB; FC PCB carries an LC321664 (64K x 16 = 128 KB); FX-1B core uses 64 KB measured | TMS57002 datasheet (external memory address width); board Answered 2026-10-05 (docs/zoom_zsg2_tms57002_design.md): all six games set ST0 = 0x0084AA, 64K address space, so 64 KB (32K x 16) is used; 64 M10K. |
| R9 | Later boards: MAME notes a Panasonic MN1020819DA and a Zoom ZFX-2 in place of the MN1020012A and TMS57002 on "newer games" (functionally identical per MAME). Which target games shipped with which | PCB photos of each game's FC PCB |
| R10 | ZSG-2 filter and ramping (MAME TODO), clicks and pops noted in gdarius and raystorm | PCB audio recordings (no datasheet, no decap known) |
| R11 | TMS57002 input sample scaling (MAME TODO: sample range "really low", should the DSP left-shift 16-bit samples?) | TMS57002 datasheet serial input format Closed 2026-10-05: SIM = 1, 16-bit input padded with 8 zero LSBs (TMS57002 guide p.3-60), as MAME does; the "really low" TODO concerns ZSG-2 levels. |
| R12 | Output volume: Zoom global volume registers 0x04/0x05 (6 bits) and the MB87078 electronic volume on the FC PCB, which MAME does not emulate | MB87078 datasheet; register trace; PCB audio 2026-10-05: the 0x04/0x05 writes decode as MB87078 programming (channel 0/1, 6-bit gain, 0.5 dB steps); MAME linear law differs by up to 5.1 dB (needs-review, PCB audio). |
| R13 | Balance SPU against Zoom (MAME routes SPU at 0.3 and Zoom at 1.0, unexplained) | PCB line-out recordings, scene matched |
| R14 | Video timing: MAME notes give 59.8260 Hz and 15.4333 kHz; confirm the GPU mode each game sets and the line count | Frame-rate measurement on a PCB; M0 GPU GP1 log |
| R15 | gn_1fb70000_r returns 2 ("so returning 2 always works, strange"); control2/control3 meaning | FC PCB XC95108 CPLD (E65-01) behaviour; board trace |
| R16 | znmcu: the uPD78081 MCU is NO_DUMP; MAME and XelaNotPu use a behavioural model | An MCU dump |
| R17 | Watchdog MB3773 period and reset effect | MB3773 datasheet |
| R18 | MDEC and SPU use. **Answered 2026-10-04 (docs/r18_mdec_spu.md): MDEC unused by all six games** (no MDEC access or MDEC DMA in 900 s traces covering first boot, attract and play; no MDEC register address in RAM-resident code); SPU used by all six. Open gap: later-stage overlays | Later-stage trace if wanted |
| R19 | Night Raid orientation and screen use: MAME ROT0, the 2026-10-02 gap list classed it as a vertical shooter | Operator manual or PCB footage |
| R20 | Bootleg sets: JP1 jumper flow ("Disable JP1 BIOS Flash after blue/red progress bar has disappeared") and how to present it on the OSD | MAME input port; footage of a converted board |
| R21 | Mixed main RAM: ZN-2 board has two unpopulated KM416V1204 positions; boardconfig_r reports RAM size; target games expect 4 MB | M0 boardconfig read log |
| R22 | DE10-Nano fit of ZN-2 + Zoom + G-NET glue (docs/f0_budget.md) | Quartus fit report of a trial integration |
| R23 | Slowdown behaviour against the true CPU rate in Ray Crisis, Psyvariar (buzz scoring depends on it) and XII Stag Footage result 2026-10-04 (docs/r1_speed_study.md): in Ray Crisis attract demo 1 the PCB takes 51.5 s with about 7.8% dropped frames; MAME takes 47.8 to 48.1 s at any CPU clock from 67.7 to 100 MHz with almost no drops, because its GPU draws instantly. Slowdown therefore depends on GPU drawing time or bus contention, which MAME does not model; demo 1 (223 extra frames on the PCB) is a ready-made test for the core's GPU timing. | 60 fps PCB footage of known heavy scenes, frame-counted |
| R24 | SPU clock on ZN-2 (MAME 67.7376 MHz / 2, as ZN-1) | Board measurement |
| R26 | MAME 0.288 ZSG-2 volume readback is 16 bits; commit 61c7940 (2026-09-14, after 0.289) narrows it to 13 bits and fixes Shikigami no Shiro stealing voices in its intro. Which is the chip | Shikigami PCB audio of the intro; compare core against a MAME build with 61c7940 2026-10-05: firmware voice poll needs at most 13 bits, and 36% of raycris reads exceed that under 0.288, so all games are affected; the core follows 61c7940. |
| R27 | The ttgnirq IRQ hack in MAME (sianniv, kollon): its root cause; kollonc runs without it (docs/gnet_set_survey.md) | MAME history and a trace of kollon against kollonc |
| R28 | What the real board does for the 11 sets MAME runs with the Zoom switched off (no-Zoom flag, docs/gnet_set_survey.md) | PCB evidence; MAME history |
| R29 | The v2/MB2011 flasher's U30 output (needed to pre-build U30 for the CF sets and 2011 bootlegs instead of running the flasher with JP1 closed) | MAME flasher run plus a decode like tools/build_flash.py |
| R25 | Card image format for MiSTer and card writes. **2026-10-04: games write to the card in MAME.** Card logical size 40,960,000 bytes (10,000 hunks of 4 KB, all six). Hunks written across the R18 runs (MAME diff CHDs, `diff/`, accumulated over all runs): raycris 32 (one 128 KB block from LBA 41056), psyvaria 4, psyvarrv 4, xiistag 3, shikigam 3 (one hunk near LBA 40 to 72 plus a few near the end), nightrai 0. So the ATA engine needs WRITE SECTOR(S) and the core needs a save path for dirty sectors (small: 128 KB at most so far). Open: what the writes hold (settings, rankings, bookkeeping) and when they happen | ATA command trace in MAME (which command, when); compare written sectors before/after a credit |
