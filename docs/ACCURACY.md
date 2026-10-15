# Accuracy notes: Taito G-NET core

What the core is based on, how each part was checked, and every known
difference from MAME and from the real board, with the evidence for it.
State: alpha, 2026-10-07. The detail behind each section is in the design
and findings documents cited; file paths are relative to the repository
root, and `taitogn.cpp:83` style references are to the unmodified MAME
0.288 sources listed, with links and md5s, in `docs/mame_sources.md`.

## 1. Method

Evidence is ranked as in my accuracy method for all shmupfan cores, highest
first:

| Rank | Source |
|---|---|
| 1 | Measurements on a real board (scope, logic analyser, frequency counter, direct capture) |
| 2 | Die-level models of decapped chips |
| 3 | Manufacturer documents: datasheets, manuals, schematics |
| 4 | Real boards observed: photos, PCB footage, PCB audio |
| 5 | MAME (here 0.288), the frame-by-frame and trace oracle; its TODOs mark guesses |
| 6 | Other cores and emulators, reference only |

Higher wins on conflict. With nothing above MAME, the core follows MAME,
and an open item names the evidence that would settle it. The ranking per
chip, and the datasheet library, are in `docs/evidence_sources.md`.

For G-NET the PlayStation chips (CPU, GPU, SPU) also exist in the retail
PS1, so tests run on a PS1 count for their shared behaviour, but not for
the ZN-2's clocks or its 2 MB VRAM.

What "verified" means in this document: the RTL was run against MAME 0.288
on the real BIOS and the real game data (from my own MAME files), either
access by access in lockstep, or by replaying MAME's recorded bus traffic
into the RTL and comparing every read, frame or sample. Every comparison
names its bench. Game-derived data (traces, NVRAM, card images, frames,
audio) stays in gitignored folders and is never committed.

### 1.1 Overall result

| Level | Check | Result | Where |
|---|---|---|---|
| Full system, Verilator | Whole core (PSX_MiSTer with the trims, the real sdram.sv, the ZN-2 board and G-NET glue) from power-on, BIOS to card unlock to the game's first-boot copy | Every card access, every flash write and the GPU command stream equal MAME's; the logo frame equals MAME's pixel for pixel apart from MAME's one-column offset (section 3) | `docs/fullsys_sim.md` 1, 5 |
| Full system, 50 MHz core | Ray Crisis, Psyvariar -Medium Unit-, XII Stag, Shikigami no Shiro and Night Raid, warm boot to 30 s of emulated time | The same screens as MAME in the same order, compared by frame hash (`tools/frame_hash.py`, method in `docs/gnet_frame_oracle.md`); no watchdog reset; the core is about 0.5 s behind MAME up to the loading bar and 1.5 to 5 s behind from the NOTICE screen on, depending on the game (section 2). Run logs are game-derived and not committed | `docs/gnet_frame_oracle.md`, `docs/r1_cpu_domain_design.md` (throughput sections) |
| Hardware | My MiSTer (DE10-Nano), build GNET_Z1FULL | Shikigami no Shiro through logo, loader, NOTICE and character select into play with Zoom music and effects; Psyvariar with Zoom music and effects (the effects sound too quiet against the music, section 4) | `docs/board_evidence.md` M5 |
| Full system, release configuration | Ray Crisis, Psyvariar -Medium Unit-, Night Raid, Shikigami no Shiro and XII Stag with the sources and settings of the current RBF (read overlap on), warm boot to 30 s of emulated time | No watchdog pulse; the longest gaps without a watchdog kick are Ray Crisis 2.625 s, Psyvariar -Medium Unit- under 0.2 s, Night Raid 3.625 s, Shikigami 2.783 s and XII Stag 0.721 s, all under the core's 8 s period; no content divergence from MAME 0.288 | run logs (game-derived, not committed) |
| Hardware, first alpha RBF | My MiSTer (DE10-Nano), `Arcade-TaitoGNET_20261006.rbf` (md5 e7d7995e, revision GNET_Z1FULL, replaced by `Arcade-TaitoGNET_20261007.rbf`) | On 2026-10-06 I played Psyvariar -Revision- to the end; the sound and gameplay were both good | this table |
| Hardware, test builds | My MiSTer (DE10-Nano), test builds of this core on 2026-10-06 | I played Night Raid, Ray Crisis (V2.03J) and Chaos Heat | this table |
| Fit | GNET_Z1FULLO, Quartus 17.0.2, 5CSEBA6U23I7, fitter seed 2 | 35,078 ALMs (84%), 445 of 553 RAM blocks, 93 of 112 DSP, every clock met: worst setup slack +0.168 ns (HDMI clock, slow 100C model); worst hold slack +0.064 ns on clk_1x and +0.123 ns on clk_2x over all four corners, +0.125 ns or more for every clock in the slow 100C summary (the 2026-10-07 build, released as `Arcade-TaitoGNET_20261007.rbf`) | build reports (not committed); `tools/sta/clk1x_hold.tcl` for the per-corner hold check |

## 2. CPU and memory timing

### 2.1 Sources

| Source | Rank | Used for |
|---|---|---|
| IDT R3051/R3052 Hardware User's Manual (1992), IDT R3000A/R3051 product information (1991), LSI Logic CW33000 User's Manual (CI4002A) | 3 | Pipeline, caches, bus timing; how a 100 MHz crystal can give a 50 MHz core (R3051 and R3000A halve a double-frequency input clock); stores are served before data reads (R3051 manual chapter 6, "Multiple operations") |
| psx-spx, "CPU Specifications, Load Timing" and the GTE command table (https://psx-spx.consoledev.net/ps1/cpu/gte/geometrytransformationenginegte/) | community spec of PS1 hardware | A PS1 main RAM load costs 7 CPU cycles plus refresh stalls; GTE command cycle counts |
| westtrade, "TAITO G NET Arcade Board with Ray Crisis" (YouTube zIpQM4xNWdY, 2022-01-10): a camera on the CRT of a cabinet, then a teardown showing the board | 4 | The "Prepares the start." loader takes 14.690 s on the board (880.5 frames at 59.94 fps) against 12.336 s in MAME; attract demo 1 takes 51.5 s on the board against 47.8 s in MAME, with about 7.8% of frames dropped |
| Gamers Bay, Ray Crisis and Night Raid direct captures (YouTube A_gQx5IWtVg, j13Liu8hmiY) | 4, capture method needs-review | Slowdown profile only, not paired |
| More board recordings (search 2026-10-14): K !! LmYZCiku6rU (Ray Crisis power-on, direct capture, 29.97 fps), ec3_arcade LP6Rwe3l89s (Astro City stream, 60 fps, MB-2011 BIOS: Chaos Heat boot, Ray Crisis and Night Raid card swaps, Night Raid attract), VICE IN TOKYO -CCk4pLrsbI (Psyvariar boot) | 4 | Ray Crisis prep bar on two more boards: COMPLETE 13.38 s and 13.22 s after the bar jumps (within 1%; the mark used for the 14.69 s figure still to be lined up); first-boot copy after a card swap: Ray Crisis 114.4 s, Night Raid 106.0 s (MAME takes about 133 to 155 s); Night Raid attract cycle 7,859 frames, deterministic |
| The Obsolete Geek, "Shikigami No Shiro G-NET Arcade PCB Gameplay" (YouTube V2F-Mld4ONc, 2010-01-25): "Recorded directly from the arcade PCB, NOT from MAME", 640x480 at 29.97 fps, V2.03J, warm boot to stage 2 | 4, capture device not stated | Boot phase lengths; slowdown from the in-game TIME counter (section 2.4) |
| Psyvariar Revision cabinet, phone recording (YouTube 9z-gvMGvyZY) | 4 | Fixed-length attract screens match MAME within a camera frame; the board falls behind MAME only across the two loading points, 0.31 s in all, which fits loading that runs slower than MAME's model (my reading; `docs/board_evidence.md` S11) |
| MAME 0.288 `psx.cpp`, `psx.h:181`, `zn.cpp:91` | 5 | MAME runs the CXD8661R as 25 M instructions per second with no memory wait states, 1.476 times the PS1 rate |
| MAME after 0.288, commit aab5dcadb | 5 | The ZN-2 GPU clocked from 100 MHz / 2, a hint of a 50 MHz system clock out of the CPU (`docs/board_evidence.md` S7) |

### 2.2 What the core does

- The CXD8661R side (CPU, GTE, DMA, root counters, IRQ, SIO0, memory
  control and the ZN-2 bus) runs at exactly 50.000 MHz, the GTE at
  100.000 MHz, from its own PLL. The GPU and SPU keep their PS1 clocks
  (GPU drawing at 67.7376 MHz, display timing from the 53.693175 MHz
  video crystal, SPU at 33.8688 MHz), as separate chips on separate
  crystals do on the ZN-2, with clock domain crossings between them (`docs/r1_cpu_domain_design.md`, "Plan for
  exactly 50.000 MHz" and "Steps 4 and 5").
- SDRAM runs at 100 MHz, 2:1 to the CPU.
- Root counters and SIO0 tick at 33.8688 MHz equivalents through a phase
  accumulator (add 10,584 modulo 15,625 per 50 MHz cycle), so Ray
  Crisis's counter 2 sound tick stays at 240 Hz as the PS1 sound library
  assumes (`docs/r1_cpu_domain_design.md`, Measurement 1c and "Decisions
  recorded").

### 2.3 How it was checked

- **CPU rate from PCB footage** (`docs/r1_speed_study.md`): a patched MAME
  0.288 with the ZN-2 CPU clock taken from an environment variable, swept
  from 67.7 to 100 MHz. The loader time follows 1078.1 / f_MHz + 1.540 s
  (maximum residual 0.015 s); the board's 14.69 s matches 82 MHz in MAME's
  model (81.4 to 82.6 MHz), that is 0.82 of MAME's rate. This is an
  effective rate in MAME's cost model, not a clock: a 50 MHz core with real
  memory waits can give the same figure.
- **GTE timing** (`docs/cpu_rate_probe.md`, "GTE clock ratio" and "GTE at
  100 MHz"): with the GTE at 2x the CPU clock, the CPU hold of all 22 GTE
  commands equals the psx-spx count (sum 314 cycles). GTE_NARROW_MUL = 3
  meets 10 ns with results and step counts unchanged (full-GTE
  equivalence, 4 x 25 M clocks, 0 mismatches).
- **Memory latency bench** (`docs/r1_cpu_domain_design.md`, Measurements
  2 and 3): the unmodified memorymux, memctrl and sdram.sv against an SDRAM
  chip model, cycle by cycle. An isolated main RAM read takes 5 CPU cycles
  from request to done at 3:1 (33.8688 MHz CPU) and 7 at 2:1 (50 MHz), the
  same nanoseconds (148 against 140 ns).
- **Cycle breakdown** (`docs/r1_cpu_domain_design.md`, "CPU and memory
  throughput at 50 MHz", `tools/r1/cpu_breakdown.py`): two 50 ms windows
  of the Ray Crisis loader in the full-system simulation. 60% of the cycles
  are main RAM loads (8.6 extra cycles each), 34% one cycle per
  instruction, 3% stores followed by a stall, 2% flash reads, I-cache
  misses negligible.
- **I-cache refill at 2:1** (`docs/fullsys_sim.md` 5.5): the first 50 MHz
  build halted on the BIOS POST bars. The full-system harness found the
  cause, an instruction cache line reported ready before its last word was
  written, so a taken branch executed the old line's word (a BREAK).
  Fixed in sdram.sv; MAME's trace of the same window
  (`docs/gnet_bios_security_check.md`) gave the expected registers and
  memory to compare against.

### 2.4 Known deviations and open questions

| Item | Core | MAME 0.288 | Board or document | Evidence rank and status |
|---|---|---|---|---|
| CPU clock | 50.000 MHz | 25 M instructions/s, no waits (behaves like a 50 MHz PS1-model CPU without memory penalties) | Undocumented. The R3051 and CW33000 conventions and post-0.288 MAME's GPU clock point to 50 MHz; System 16 lists "50MHz?" | Inference from rank 3 documents for other chips plus rank 4 footage; medium confidence. Settled by a frequency counter on the CXD8661R clock, or a timing test program on any CXD8661R board (R1) |
| Main RAM load | about 9.6 CPU cycles (7 for the SDRAM path at 2:1, plus about 2.6 of pipeline) | 1 cycle (no waits) | psx-spx gives 7 for a PS1 load; holding the window's mix fixed, the board's 14.69 s loader implies about 7.7 cycles per load | Rank 4 footage of one game, one window mix; the core probably spends about 2 cycles per load that the chip does not. Ray Crisis's loader: core 16.9 s, board 14.69 s, MAME 12.34 s. Where the cycles go (read of the RTL, 2026-10-14, not yet measured): every main RAM load waits one cycle in memorymux's WAITFORRAMREAD, upstream PSX_MiSTer's model of a PS1 isolated load (commit 09c5029 makes back-to-back loads one cycle faster), and that faster back-to-back path never fires at 2:1, because its window (ram_load_last = 7) has expired before the CPU issues its next load. ps1-tests `cpu/access-time` gives about 5.2 cycles for an isolated RAM read in its `psx.log` (probably a PS1 console; the model is not stated), counted as the cycles a load adds to its loop, which is a different measure from the 9.6 above; running that test on the core in simulation reconciles the two. Planned direction: the PSX_MiSTer per-load counts at 2:1 (isolated and back-to-back), then the loader time against the board. Two prototypes exist: a one-cycle earlier SDRAM ready (about 15.7 s estimated; an earlier 15.0 s figure came from a bench whose back-to-back rows request one cycle sooner than the CPU does), off in this build, and expansion bus read overlap, on in this build (`docs/r1_cpu_domain_design.md`, "Option B prototype", "Read overlap prototype"; in full-system warm boots of Ray Crisis, Psyvariar and Night Raid it matches overlap off in content, with 1 to 2% faster loading and no watchdog pulse). An SDRAM clock of 150 MHz (3:1) would restore the PS1 count but runs the SDRAM beyond its rating ("Option A on paper"): -7 grade chips such as the AS4C32M16SB-7TCN named in the MiSTer hardware documentation are rated to 143 MHz at CAS latency 3. The board's main RAM (2 x KM416V1204BT-L5, 50 ns EDO) does not limit a 7-cycle load at 50 MHz: an equivalent 50 ns part has an 85 ns random cycle |
| Flash reads on the expansion bus | about 37 CPU cycles per read in the Ray Crisis loader without read overlap; 22 to 25 with it (on in this build; bench figures at the measured latency) | no waits | the programmed delay register asks for about 15 | Core glue overhead. FC PCB bus waits are not measured (`docs/board_evidence.md` M4) |
| Night Raid NOTICE phase | 4.8 s on the 50 MHz core | 3.1 s | not measured | The phase is the game copying card data at CPU speed (RAM loads 38%, ATA data port reads 28% of the cycles), not timer paced (`docs/r1_cpu_domain_design.md`, "Night Raid NOTICE phase"). A PCB capture of a Night Raid power-on would settle it |
| BIOS ROM timing | PS1 BIOS bus timing (25 cycles per word): the ROM-resident BIOS runs about 4 times slower than in MAME in the full-system simulation | no waits | not measured | Open (`docs/zn2_layer_design.md` 17 item 8). Affects the first second after power-on only. Footage of a cold boot with no card (logo to SYSTEM ERROR) would show which is right |
| Shikigami no Shiro boot and slowdown (2026-10-14) | Full-system sim of the release RTL (alphaB warm_shikigam frames.tsv): TAITO NET logo 2.56 s, game loader 2.47 s, black screen to NOTICE 3.15 s, NOTICE 3.01 s | not compared | PCB video V2F-Mld4ONc (frame edges, plus or minus 0.033 s): logo 2.54 s, loader 2.37 to 2.40 s, black screen to NOTICE 4.11 s, NOTICE 3.04 s. The TIME counter counts game frames: steps take 1.00 s in calm play and 1.2 to 1.6 s in heavy boss and score-item scenes (about 0.65 to 0.85 of full speed), for example 125 to 131 s and 227 to 235 s of the video | Rank 4, one board. The timer-paced screens agree to 1%, which checks the frame timing. The loader is about 4% slower on the core. The board spends about 1 s longer before NOTICE, which the sim does not reproduce: the card reads complete without real card latency in the core and in MAME (R6), the likely cause, not confirmed. The TIME counter gives a direct slowdown comparison (issue #5). On my MiSTer with alpha 3 (2026-10-15, MDEC build, my own play of stage 1, screenshots every 0.54 s, counter read per frame): calm play 1.01 s per step (16 steps); the moth mid-boss fight 1.32 s per step (counter 81 to 65, 16 steps over 21 s), coin-heavy stretches 1.1 to 1.6 s. The same stage 1 boss (the moth) in the video, read the same way at 10 frames per second: the lead-in 1.00 s per step on the board against 0.98 on the core (counter 93 to 87), the fight from its entrance to the kill 1.07 s per step on the board (77 to 55, 22 steps in 23.5 s) against 1.24 on the core (81 to 64, 17 steps in 21.1 s): about 16% more slowdown on the core in that fight, while calm play matches. The counter also holds still during the boss entrance (about 2.5 s on the board, 5 s on the core) and at the start of each life, which is the game's behaviour, not slowdown. One play on each side, same character, different players. With the texture prefetch (test core of 2026-10-15, my play): the same fight 1.04 s per step (counter 79 to 74 and, after a lost life, 120 to 100: 25 steps in 26.0 s), calm play 1.00, against the board's 1.07 and 1.00 |
| Upstream timing models at 2:1 (code read, 2026-10-14, not yet measured) | PSX_MiSTer's counts are unchanged, but they run on a 2:1 SDRAM clock: the back-to-back RAM load discount (09c5029) never fires, I-cache refills cost 2 to 2.7 cycles more, DMA reads from SDRAM top out near 0.66 words per cycle, and the BIOS wait states (118bd85) are fixed for the PS1 delay register value 0x13243F where the ZN-2 BIOS writes 0x13246F | n/a | PSX_MiSTer was tuned at 3:1 against PS1 hardware tests | Needs a mem_lat bench row per item before any change; MULT/DIV, GTE, expansion delays and timers are unaffected. REPRODUCIBLEGPUTIMING is a debug setting upstream (off there too), not a hardware model |
| Store followed by a load | waits for the write to reach memory (about 7 cycles) | no wait | R3051 manual chapter 6: pending writes are served before data reads | Rank 3 supports the behaviour; its length follows the SDRAM write path |
| GTE hold on MTC2, CTC2, LWC2 | held while the GTE is busy (upstream PSX_MiSTer) | no hold | psx-spx: these do not wait | Upstream PSX_MiSTer behaviour, left unchanged (`docs/cpu_rate_probe.md`, "GTE clock ratio") |
| Root counter clock | 33.8688 MHz equivalents | reads counters at the CPU rate but schedules their IRQs at 33.8688 MHz, with a TODO | not documented | The R1 timing program (counter 2 against VBlank) settles it |
| SIO0 bit timing | MAME's rule, prescaler x baud cycles per bit | same | PSX_MiSTer's PS1 pad model ignores the prescaler | Kept as a generic (`ZN2_PS1_SIO`); affects only security and MCU transfer timing (`docs/zn2_layer_design.md` 7.2) |
| Main RAM 4 to 8 MB | separate RAM | 0.288 mirrors 4 MB; MAME after aab5dcadb raises a bus error | 4 MB fitted | No CPU access to 4 to 8 MB in any trace (`docs/zn2_layer_design.md` 3); not visible to the games |
| MDEC | present from alpha 3 (removed in alphas 1 and 2) | present | Alpha 1 removed it after six games did not use it in 900 s traces (`docs/r18_mdec_spu.md`). Space Invaders Anniversary does: it decodes a still at the coin and a zoom movie at Start, and without the MDEC it waits forever and the watchdog resets it (issue #1, the Start reset; reproduced in MAME by blocking the MDEC) | Alpha 3 puts it back on the CPU clocks. Checked on my MiSTer (2026-10-15, alpha 3 with MDEC): coin and Start play the movie and the game starts |
| Slowdown | the GPU draws with real timing on DDR3 | MAME's GPU draws instantly, so MAME drops almost no frames in Ray Crisis demo 1 at any CPU clock | the board drops about 7.8% of frames in that demo | Measured on my MiSTer with alpha 2 (2026-10-14): 220 screenshots at 0.52 s steps, each matched to a MAME frame (99 unambiguous matches over 46 s of the demo, residual standard deviation 0.24 s, `tools/r1/demo_drift.py`). The core takes 1.146 times MAME's time (demo 1 about 54.7 s), against 1.078 on the board (51.5 s): about 6% more slowdown than the board, spread evenly over both stages (1.13 to 1.16 in each 8 s stretch), as on the board. Alpha 3 with the faster CPU RAM timing (2026-10-15, same method, 94 matches over 46 s, residual sd 0.19 s): 1.126 (demo 1 about 53.8 s), about 4.4% more than the board. The CPU RAM fix took about a third of the gap; the rest fits the GPU waiting on DDR3 for texture reads (about 12 clocks per read, measured), which a texture prefetch would hide. With the texture prefetch (test core, 2026-10-15: GPU texture cache fill of 4 qwords per miss, the next texture row as well, two VRAM reads in flight; branch a3-prefetch, RBF md5 c0b698ec): 1.045 (86 matches, residual sd 0.27 s), now 3% less slowdown than the board. Without it, on the release candidate of the same day (RBF md5 4efe7da1): 1.1256, which repeats the earlier alpha 3 run to 0.0001. Shikigami no Shiro's first attract demo (stage 1 with score items, against MAME 0.288 every-frame snapshots): 1.034 without the prefetch (1.033 on an earlier build), 1.011 with it; its heaviest 5 s goes from 1.081 to 1.020. The board's GPU therefore waits on texture reads less than the core without the prefetch and more than with it. Calibration on top of the prefetch (branch a3-calib, 2026-10-15): a wait of D clk_2x cycles after each texture cache fill (`TEX_MISS_DELAY`, `docs/gpu_read_infl.md` 10). D 9: 1.061 (test core only, its fit missed hold). D 13: 1.0762 (90 matches, residual sd 0.39 s; demo 1 about 51.43 s against the board's 51.50 s, 0.2% apart). The alpha 3 release build (D 13, RBF md5 a4e2f4cd, all clocks met): 1.0748 (89 matches, residual sd 0.39 s; demo 1 about 51.36 s, 0.3% from the board). Shikigami no Shiro demo A stays at 1.011 at D 9 and D 13, so the wait only slows scenes that miss the texture cache often. Shikigami no Shiro's stage 1 boss on the release build, played by me and read from the TIME counter in screenshots every 0.54 s (2026-10-15): the board video's window, counter 77 to 55, takes 23.8 s on the core (1.082 s per step) against 23.5 s on the board (1.068), about 1.3% slower, inside the screenshot timing error of about 2%; entrance to kill (83 to 45) 1.085 s per step; calm play before the boss (115 to 90) 0.997. The fit is from one board video per game, so D is provisional until more board footage is matched |

### 2.5 Kollon and Space Invaders Anniversary: the ttgnirq race

MAME runs these two sets as `ttgnirq_state`, which zeroes I_MASK when the
CPU fetches 0x80010008 ([taitogn.cpp L649-L680](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L649-L680)). I traced
why (`docs/ttgnirq_quirk.md`).

| Item | Finding |
|---|---|
| Sources | MAME 0.288 under the debugger, warm boots of kollon, sianniv and kollonc ([taitogn.cpp L1365-L1367](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L1365-L1367)); rank 5 |
| Mechanism | The game's start-up code clears its BSS, which in these two sets runs into the code of the sub-BIOS loader that jumped to it. The loader leaves its VBLANK tick enabled, so a VBLANK after the clear passes the tick's code executes zeroed memory and faults; the game masks interrupts itself about 12,000 cycles (kollon) or 280,000 instructions (sianniv) after the clear |
| Taito's own fix | kollonc (the later CompactFlash build) has `mtc0 zero,SR` in the delay slot of the clear loop, so interrupts are off during the clear. Patching it back to a nop in MAME makes kollonc hang the same way, so the race is in the game, not in MAME |
| What the core does | Runs the same loader and game code with the same IRQ setup. I do not copy MAME's fetch tap: it has no hardware basis. Whether a set survives depends on where VBLANK falls in a window 41% (kollon) to 80% (sianniv) of a frame wide, about ten frames after the jump, so it follows the CPU's speed against VBLANK |
| How it was checked | Hardware, 2026-10-06: Kollon with an unpatched U30 boots on my DE10-Nano to its title screen (GNET_Z1FULLO build of 2026-10-06 21:10, RBF md5 9dbb2405); not played further. Full system, 2026-10-07: Space Invaders Anniversary with an unpatched U30 on the release sources, warm boot to 12 s: five VBLANKs land inside the clear and none faults; the clear ends about 5 frames after the loader's VBLANK sync (MAME about 10), so the vulnerable window falls between two VBLANKs; the game masks interrupts itself at about 5.81 s, then fades in its NOTICE screen with the CPU in game code; no exception other than interrupts and syscalls, no watchdog reset. It passes by timing, not by design |
| Known gaps | Whether the T1 Kollon and Space Invaders Anniversary cards boot every time on a real board is unknown (needs-review). A board running at MAME's pace would hit the race; the fallback for that case is Taito's kollonc fix applied to the U30 image as data, recommended in `docs/ttgnirq_quirk.md` 5 and not implemented |

## 3. GPU and VRAM

### 3.1 Sources

| Source | Rank | Used for |
|---|---|---|
| JaCzekanski/ps1-tests (MIT), gpu/transparency, triangle, uv-interpolation, quad, lines, rectangles, with their `vram.png` reference images | 1 if the images are console captures (needs-review: the suite says it is for hardware verification, but no commit states how the images were made) | Rasteriser rules shared by the PS1 GPU and the CXD8654Q |
| psx-spx, "GP1(00h) - Reset GPU" | community spec | Rendering attributes reset to 0 |
| MAME 0.288 `psxgpu.cpp` (GPU type 2, the CXD8654Q) | 5 | 2 MB VRAM (1024 x 1024), the texture page bit 11, GP1(10h) index 7 answering 2 |
| `taitogn.cpp:83` note: 59.8260 Hz and 15.4333 kHz | 5 (a measured figure, measurer not stated) | Frame rate |

### 3.2 How it was checked

- **GPU command replay** (`docs/m1_gpu_zn2.md` 2, 2b, 2c): every GP0/GP1
  word and DMA word MAME's GPU received, replayed into the PSX_MiSTer GPU
  in NVC, VRAM compared with MAME's. Boot logos: 0 of 1,048,576 pixels
  differ in 2 MB mode. Gameplay, all six games, 300 frames from MAME's
  VRAM at frames 1500 and 2700: the upper 1 MB (texture pages and CLUTs)
  is identical in every game; all differences are in drawn pixels and fall
  into the classes below.
- **PS1 hardware test images** (`docs/m1_gpu_zn2.md` 2d): the same six
  ps1-tests streams through the core GPU and through MAME. Pixels
  differing from vram.png (of 524,288): transparency 0 (MAME 0), triangle
  0 (MAME 36,769), uv-interpolation 0 (MAME 34,203), quad 0 (MAME 59,864),
  lines 64, all on segments the test draws with undefined colours (MAME
  3,352), rectangles 0 (MAME 1,188).
- **Full system** (`docs/fullsys_sim.md` 1, 5.1): from power-on with no
  card, GP1 1,857 of 1,857 words and GP0 13,310 of the core's 13,311
  commands equal MAME's; the one left is D2 below. 2 MB VRAM is needed by
  every game: all six place 141,485 to 317,797 non-zero pixels in lines
  512 to 1023 (`docs/m1_gpu_zn2.md` 2a).

### 3.3 Known deviations and open questions

| Item | Core | MAME 0.288 | Evidence and status |
|---|---|---|---|
| Space Invaders Anniversary coin (issue #1) | from alpha 2: each press gives one 100 ms coin pulse however long it is held (`rtl/gnet/gnet_coin_pulse.sv`), and the coin lockout bits mask the coin reads as in MAME (`zn2_io.vhd`) | MAME 0.288 (2026-10-14 runs from the post-copy state): a 0.1 s coin then Start plays normally, and two 0.8 s Start presses are fine, but a coin held 0.7 s shows "COIN ERROR", the game stops and the watchdog resets it | The game treats a coin input held for 30 frames (0.5 s) as a jammed coin mech (routine 0x8001102c, an endless loop, from a read of the card code). Real coin mechs give short pulses; a MiSTer button held a little long trips it, on the core as in MAME. MAME also ignores coins while the game has them locked out; the core does not. Both are in alpha 3 (an input-handling change, not a board change). Benches: `sim/shell/run_shell.sh` (a 1 s hold gives one pulse of 100 ms; a press during a pulse queues one more) and `sim/zn2/run_zn2_io.sh` (lockouts) pass (2026-10-15). On my MiSTer (2026-10-15, alpha 3 with MDEC): coin held about a second, then Start, starts the game |
| Super Puzzle Bobble character sprites (issue #6) | for 1 to 3 frames at a time, Bub and Bob are drawn as spiky sprites in pink, yellow and cyan (tester video, release build) | MAME 0.288, Player vs Computer with Bob as partner (2026-10-14 run, frames 4251 to 4305): the same moments are the game's own shock reaction, which alternates every few frames between a dark silhouette with a yellow outline and grey spiky characters | Cause: textured rectangle X/Y flip (E1 bits 12 and 13), supported by the type-2 GPU and ignored by gpu_rect.vhd; fixed in alpha 3 (RECT_FLIP). A replay of MAME's GPU stream matches MAME in 15 of 16 frames, and Lee confirmed the shock sprites look right on the MiSTer with alpha 3 (2026-10-15) |
| Dithering | dithers when E1 bit 9 is set | no dithering | ps1-tests match the core bit for bit (rank 1, provenance needs-review). In game: Psyvariar Revision frames 9477 and 11726 replayed through the core's GPU differ from MAME only in the background polygons (4bpp textured, dither bit set), where the core shows the 2x2 checker and MAME shows banding; sprites, score and the BUZZ labels match pixel for pixel (M1 GPU replay from MAME's VRAM state, 2026-10-06; the mapping was checked first with 0 differing pixels against MAME's own VRAM dumps; the images come from game data and are not in the repository) |
| Gouraud colour steps | PS1 placement | steps land later (truncated 16.16 steps) | ps1-tests triangles and G4 rows: core 0, MAME 3,740 to 18,743 pixels |
| Blend mode 0 | (B + F) / 2 | B/2 + F/2, each truncated | ps1-tests quad: all 59,002 1-LSB pixels have MAME lower |
| Texture coordinates | interpolated U | U truncated (every row red in uv-interpolation) | ps1-tests: core matches row for row |
| Edges and fill | PS1 rules | different seam and edge pixels; fill leaves column 1023 | ps1-tests quad and triangles |
| Drawing area after GP1(00h) | 0 | 1023,1023 | psx-spx: rendering attributes reset to 0. The BIOS sets the area again before it draws; no visible effect (`docs/fullsys_sim.md` 5, D2) |
| Displayed column | the display area from the GP1(05h) x | MAME's snapshot starts one column later | Settled: MAME's offset (`docs/fullsys_sim.md` 5, D3) |
| Display start change mid-frame | GP1(05h) takes effect at once, so a frame can split | latched per frame | Psyvariar, first fade step (about 11.4 s from a warm boot): the game misses a frame and moves the display start 11.2 ms into scanout, giving 2 torn frames in the core. No hardware measurement exists. Mednafen applies the write at once per scanline, and a PS1 developer tutorial says buffer swaps without waiting for vblank tear on real hardware, so the core is kept as is; MAME and DuckStation scan out whole frames at vblank, which cannot split by design. A test that writes GP1(05h) at a known scanline, filmed on a board, would settle it (needs review) |
| Line length and frame rate | 3413 clocks x 263 lines = 59.8173 Hz | 3412.5 x 263 = 59.8261 Hz | The taitogn.cpp note gives 59.8260 Hz, 147 ppm above the core; its 15.4333 kHz does not fit 263 lines at either rate. The Psyvariar Revision cabinet recording matches MAME's frame rate to about 0.3% (fixed-length screens within a camera frame, `docs/board_evidence.md` S11), too coarse to separate 147 ppm. Open: a frequency counter on the board's composite sync (`docs/m1_gpu_zn2.md` 4; owner question 7) |
| GPU clock | drawing on 67.7376 MHz (PSX_MiSTer's PS1 setting), display timing on 53.693175 MHz | 0.288: the CXD8654Q on 53.693175 MHz, drawing instantly; after 0.288 (aab5dcadb): 100 MHz / 2, with 53.693175 MHz as the video clock | Unknown on the board; only matters for drawing time, so for slowdown (`docs/board_evidence.md` S7, M1) |
| GPU drawing time on DDR3 | PSX_MiSTer's GPU with VRAM in DDR3 behind the G-NET arbiter | instant | Texture cache misses are the whole latency cost. Alpha 3 fills 4 qwords per miss, fetches the next texture row as well and keeps two VRAM reads in flight, then waits 13 clk_2x cycles after each fill so that Ray Crisis demo 1 matches the board (section 2.4, `docs/gpu_read_infl.md`). Measured on the DE10-Nano with the DDR3 latency probe (2026-10-14): an isolated read waits 12.4 clk_2x cycles on average (183 ns, median 12, 1 in 100 at 31 or more), 23.2 while writes use every free cycle. In simulation 12 extra cycles per read raise the GPU's mean time per frame in the heaviest Ray Crisis demo stretch from 14.1 to 18.6 ms (`docs/gpu_draw_time.md` 6). Whether the board's GPU is faster or slower than the core's is unknown: a PS1 draws textured quads up to 2.7 times slower than the core with ideal VRAM. The board's slowdown in Ray Crisis demo 1 is the reference (section 2.4) |

## 4. SPU

### 4.1 Sources

| Source | Rank | Used for |
|---|---|---|
| PSX_MiSTer `spu*.vhd` | base implementation (upstream) | Voices, reverb, main volume |
| MAME 0.288 `spu.cpp`, `taitogn.cpp:441-448`, `zn.cpp:170-172, 233-243` | 5 | Routing (SPU 0.3, Zoom 1.0); the ZN-2 SPU read window |
| MAME commit df9d7ef55a (2018-08-19, PR 3868, "taito_zm games: Better default Zoom/SPU balance") | 5 | Origin of the 0.3 route: set by ear, no measurement given (`docs/board_evidence.md` M5) |
| YouTube 9z-gvMGvyZY, "psyvariar revision arcade taito g-net" (2020-10-16): a phone filming a cabinet's CRT with sound (Psyvariar -Revision- exists only on G-NET) | 4 | The effects against the music on a real board, measured from the attract demo audio (`docs/board_evidence.md` S11, M5) |

### 4.2 ZN-2 specifics

- Every SPU register read in the games goes through one routine: a dummy
  read at 0x1FA51C00 plus the register offset, a poll of 0x1FA60000 until
  bit 3 is set (at most 100 tries, then the error print "SPU:T/O"), then
  the real read at 0x1F801C00 plus the offset. Writes skip it. The core
  answers as MAME (bit 3 toggling per read); the real register behind the
  EPM7064 CPLD is unknown (R2, `docs/r1_cpu_domain_design.md`
  Measurement 1a, `docs/zn2_layer_design.md` 11).
- SPU clock: 33.8688 MHz, as MAME (R24 open, no board measurement).

### 4.3 Known deviations and open questions

| Item | Core | MAME 0.288 | Evidence and status |
|---|---|---|---|
| SPU main volume (0x1F801D80/82) | applied (spu.vhd) | stored, never applied in the mix (`spu.cpp` has the register names only) | The games set it low: Ray Crisis 0x1125 (0.27 of full scale), Shikigami 0x0C99 (0.20), Psyvariar 0x2FDF (0.75). At MAME's 0.3 route the core's effects are 11.4 dB (Ray Crisis), 14.1 dB (Shikigami) and 2.5 dB (Psyvariar) below MAME's against the same music (`docs/m4_shell.md` 4) |
| SPU against Zoom balance | the SFX Level option: 0.3 (MAME, the default), 0.45, 0.6, 0.9 (MAME's pre-2018 ratio), 1.2, 1.5 | 0.3, set by ear in 2018 (0.35 in MAME 0.150, 0.45 by 0.200) | The default is MAME's until there is board evidence per game. On my MiSTer the Psyvariar effects sound too quiet against the music at 0.3, but 0.7 (the first alpha's default, from the estimate below) sounded wrong for Night Raid. Evidence only, not used for the default: the Psyvariar Revision cabinet recording, its attract demo fitted as Zoom plus k times MAME's SPU: the effects are 3.8 dB louder against the music than MAME at 1.2 to 4.8 kHz (90% range 2.2 to 6.1 dB) and 5.7 dB at 2.4 to 4.8 kHz (4.7 to 7.2 dB), k of about 0.47 to 0.58. The board applies the game's main volume (0.748), so its route is k / 0.748: 0.62 and 0.77, geometric mean 0.69, for Psyvariar (`docs/board_evidence.md` S11, M5; `docs/m4_shell.md` 4). Rank 4 from one recording: uncalibrated microphone, unknown volume dial and mono/stereo setting, the fit explaining 65 to 72% of the variance, one game. A PS2-port video under emulation is not evidence for the arcade board (S10). A line-out recording or the analog mixing resistors would settle it (owner questions 8 and 16) |
| SPU output scale against the Zoom output | both taken as 16-bit full scale, as MAME | same | needs-review against spu.vhd's scaling (`docs/zoom_board_design.md` 14.6, I7) |

## 5. ZN-2 glue and security

### 5.1 Sources

| Source | Rank | Used for |
|---|---|---|
| Atmel AT28C16 datasheet doc0540 | 3 | EEPROM byte write time (1 ms, or 200 us for the E part), DATA polling |
| NEC uPD78083 subseries user's manual U12176EJ2V0UM00 | 3 | Context only: the uPD78081 MCU ROM is not dumped |
| Taito G-NET operator manual G2500879A (archive.org arcademanual_Taito_G_Net) | 3 | DIP switch S551: "Operate No. 4 only" for test mode; 3 buttons per player |
| MAME 0.288 `zn.cpp`, `cat702.cpp`, `znmcu.cpp`, `at28c16.cpp`, `sio.cpp`, `taitogn.cpp` | 5 | CAT702 algorithm, I/O MCU model, map, inputs, coin lockouts |

### 5.2 How it was checked

- **CAT702** (`docs/zn2_layer_design.md` 16.1): every byte MAME's SIO0
  exchanged with either chip in the six 300 s cold runs, driven bit by bit
  into the RTL: 141,900 bytes, 0 mismatches. With one key bit changed,
  2,629 of 2,783 Ray Crisis bytes differ.
- **SIO0, both CAT702 and the I/O MCU together** (16.4): every SIO0 access
  and select write of all six games replayed at MAME's time; 0 mismatches
  (Shikigami: 723,704 reads, including its security traffic all through
  play and its one analog-mode MCU read).
- **zn2_io** (16.3): every access to the inputs, board configuration,
  security select, coin and the EEPROM in the MAME traces, 0 mismatches.
- **Full system**: 4,387 of 4,387 CAT702 bytes equal the reference model
  through the integrated path; the BIOS decrypts the sub-BIOS from U30
  and runs it (`docs/zn2_layer_design.md` 18.3).
- **BIOS security check in MAME** (`docs/gnet_bios_security_check.md`):
  MAME's trace of the window from the last TT16 session to the first U30
  read, with the descramble routine's registers and expected memory, used
  to locate the 50 MHz halt (section 2.3).

### 5.3 Known deviations and open questions

| Item | Core | MAME 0.288 | Evidence and status |
|---|---|---|---|
| AT28C16 write of the value already stored | written (busy for the write time) | skipped | Datasheet (rank 3) has no skip |
| AT28C16 write time | 200 us | 200 us | The part suffix (1 ms or 200 us) is not legible in any photo (`docs/board_evidence.md` P6, owner question 5) |
| I/O MCU (uPD78081) | behavioural model, as MAME | behavioural | ROM not dumped (R16) |
| Security select during Shikigami's play | any access at any time, no boot-only state | as the core | Which device answers the in-play selects on a real board is open (`docs/zn2_layer_design.md` 17 item 10) |
| BIOS POST writes to 0x1FA00000, byte writes to 0x1FB68000 | ignored | ignored | Meaning unknown (a latch or LED; `docs/board_evidence.md` C3) |
| Board configuration register | 0x69 (4 MB RAM, 2 MB VRAM, 512 KB SPU RAM) | 0x69 | Trace (`docs/zn2_layer_design.md` 3) |

### 5.4 Special controls: mahjong panel and RC wheel

| Item | Detail |
|---|---|
| Sources | MAME 0.288 `taitogn.cpp` INPUT_PORTS gobyrc, mahjngoh and usagi ([L944-L1015](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L944-L1015)) and `ttgnmp_state::mahjong_panel_r` ([L682-L713](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L682-L713)); `mahjong.cpp` `mahjong_matrix_1p` ([source](https://github.com/mamedev/mame/blob/mame0288/src/mame/shared/mahjong.cpp)); MAME's default keys, `inpttype.ipp` ([source](https://github.com/mamedev/mame/blob/mame0288/src/emu/inpttype.ipp)); the RC De Go controller description in [taitogn.cpp L145-L161](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L145-L161). Rank 5, plus that description |
| Selection | The MRA's game configuration byte, bits 3:2: 0 joysticks, 1 mahjong panel and P1 joystick (Mahjong Oh), 2 mahjong panel only (Usagi), 3 RC wheel and trigger (Go By RC, RC De Go). Controls MAME marks unused for a set read as released |
| Mahjong panel | A read of 0x1FA10100 returns the AND of the key rows that coin register bits 2, 3, 6 and 7 select, as `mahjong_panel_r`. The keys are on the keyboard with MAME's default keys: A to N, Kan LCtrl, Pon LAlt, Chi Space, Reach LShift, Ron Z, Start 1. They are also on pad 1 (issue #2): L and R are shifts over eight inputs (D-pad Left, Up, Right, Down, then the Y, X, A, B face buttons): no shift (Usagi) or L and R together give tiles A to H, R gives I to N, L gives Kan, Pon, Chi, Reach, Ron; Start is Start. Mahjong Oh keeps its P1 stick and buttons 1 to 3 on the unshifted pad. A key keeps the layer it was pressed in until released, so releasing a shift first never presses another key. This is a convenience of the core, not a control of the original cabinet |
| RC wheel and trigger | The I/O MCU's analog channels 0 and 1, 00h to FFh, centre 80h (MAME IPT_PADDLE, and IPT_PADDLE_V with PORT_REVERSE). Wheel from the analog stick's X or a paddle, trigger from the stick's Y, D-pad for full deflection |
| How it was checked | zn2_io directed tests of the panel read (each row, two rows together, no row, mahjong off); the clock-domain crossing of the keys and of the analog bytes in `sim/zn2cpu50` (40 runs, 0 errors; a deliberately per-bit analog crossing gives 513 torn values, so the check catches them); lint of the shell. Every other set's inputs are unchanged. Full system on the release sources, warm boots to 15 s: Mahjong Oh boots through its loader, notices and the TAITO logo with no watchdog reset, about 1 s behind MAME 0.288; holding Mahjong A changes the row 0 reads of 0x1FA10100 from 3Fh to 3Eh for exactly the hold time. Go By RC (Type 2 card) boots to its CALIBRATION screen and waits there, as MAME does with a fresh EEPROM; the I/O MCU packets carry the wheel value (80h at rest, 20h after the change) and the on-screen STEERING WHEEL readout follows |
| Known gaps | Not yet checked on hardware; the pad layers of the mahjong panel are not yet checked in simulation either. MiSTer-devel's Psikyo SH2 core puts mahjong keys on joystick buttons 4 to 23, which in this core would collide with the PSX base's savestate and fast-forward buttons, so the pad uses shift layers on J1 bits 4 to 14 instead. The trigger direction follows MAME's PORT_REVERSE; the real controller's direction is not documented beyond MAME |

## 6. G-NET FC PCB

### 6.1 Sources

| Source | Rank | Used for |
|---|---|---|
| System 16 FC PCB photos, top and underside, and ZN-2 photo (https://www.system16.com/hardware.php?id=672) | 4 | Part markings: TE28F160 S5100 on U30 and U29 (U56 and U55 the same layout), E28F400B5B80 on U27, LC321664AM-80, LH52B256N-10LL, MB3773PF (U43), ADM708AR (U5), RF5C296 (U50), MB87078 (U1), TMS57002DPHA (U7), XC95108 "E65-01", CAT702 "TT16"; IC053 and IC054 RAM positions empty |
| bytestorm's photo in the arcade-projects thread "Taito G-NET flash problems" (2019-05-04) | 4 | JP1 to JP4 positions; JP1 beside U30 |
| ack's continuity trace of the Save/Backup PCB connector (arcade-projects, 2023-08-02) | 4, single observer | One FC CPLD input carries a backup or power-fail status; MB3771 and ADM708 pin 1 connections |
| Tailsnic Retroworks (arcade-projects, 2024): JP1 enables erase mode on U30; LH28F160S5T-L70A works as a U30 replacement | 4/community | JP1 function |
| Intel 28F160S5/28F320S5 datasheet 290609-004, 28F160S3/28F320S3 290608-005, 28F400B5 Smart 5 Boot Block 290599-004 | 3 | Command set, IDs, status register, program and erase times, BYTE# pin |
| Ricoh RF5C296/RF5C396L Application Manual EA-028-9804 | 3 | ExCA registers at 3E0h/3E1h, identification values, card reset, windows, IRQ steering |
| CF+ and CompactFlash Specification Rev 1.4 (1999) and Rev 3.0 (2004) | 3 | ATA task file, attribute memory, CIS, configuration registers |
| Fujitsu MB3773 datasheet DS04-27401-7E | 3 | Watchdog period from the timing capacitor, CK edge, reset timing |
| Analog Devices ADM705/ADM706/ADM707/ADM708 datasheet Rev. H | 3 | The ADM708 is a supply supervisor without a watchdog (4.40 V threshold, 200 ms reset, manual reset input) |
| MAME 0.288 `taitogn.cpp`, `intelfsh.cpp`, `rf5c296.cpp`, `ataflash.cpp`, `atahle.cpp`, `mb3773.cpp` | 5 | Board decode, the Taito Type 1 card lock (documented nowhere else), behaviour without a datasheet |

### 6.2 How it was checked

- **Glue replay** (`docs/m2_glue_findings.md`): every main-CPU access to
  the flash window, the RF5C296 and task file and the control registers
  in a 300 s cold MAME run (first-boot copy, attract and a credit), for all
  six games, replayed into the RTL: 0 read mismatches; the five flash
  chips end word-identical to MAME's NVRAM, and the card sectors the games
  write equal MAME's card image. Plus 75 directed checks for behaviour no
  game reaches.
- **Flash images offline** (`docs/m0_findings.md` 3a):
  `tools/build_flash.py` rebuilds all five flash images from the card and
  the BIOS zip alone, byte-identical to MAME's post-copy NVRAM for all six
  games. The main MRAs use these images.
- **Full system** (`docs/fullsys_sim.md` 1, 5.1, 5.2): in a Ray Crisis
  cold boot, all 337 RF5C296 and ATA accesses other than data and status
  reads equal MAME's in order, all 2,512 runs of data port reads (522,375
  reads) equal MAME's, and all 657,074 byte writes to the flash window
  (commands, card attribute writes, U30 erase and program) equal MAME's.
- **First hardware test** found ERROR B930 (`docs/zn2_layer_design.md`
  18.5): the flash adapter read SDRAM with partial byte enables, which on
  the MiSTer SDRAM board become DQM and mask a read two clocks later. Every
  simulation model ignored read DQM; they now apply it.

### 6.3 Flash chips and the first-boot copy

- Parts: U30, U29, U56 and U55 are 28F160S5 (5 V VPP), U27 a 28F400B5
  bottom boot block part, matching MAME's INTEL_E28F400B
  (`docs/board_evidence.md` P1, P3).
- MAME's model programs instantly and erases a block in exactly 1.0 s, so
  121 s of MAME's 137.7 s copy is its erase constant. The 28F160S5
  typical times give about 77.5 s of flash time for the same 121 erases
  and 3,933,330 words (290609-004 p.49; `docs/m0_findings.md` 3). MAME's
  notes give 2 to 3 minutes for the whole copy on a board
  (`taitogn.cpp:21`); not measured.

| Item | Core | MAME 0.288 | Evidence and status |
|---|---|---|---|
| Program and erase timing | MAME's (preset 1); the 28F160S5 typical times are built in as preset 3 | instant program, 1.0 s erase | The release keeps MAME's timing so a first boot can be compared with MAME; preset 3 is the datasheet choice. A timed video of a board's first boot settles the total (owner question 9) |
| Word program over a programmed word | old AND new | overwrite | Datasheets (rank 3); the BIOS only programs erased words, so the result is identical |
| Status after program or erase | returns to ready in any read mode | only in read status mode | Datasheets (rank 3); the BIOS always polls in read status mode |
| U30 on the 8-bit bus | presents the addressed byte, as MAME | same | The 28F160S5 has a BYTE# pin; its level on the FC PCB needs a close-up or continuity check (`docs/board_evidence.md` P2) |
| Flash persistence | not saved; the first boot MRAs repeat the copy at every load | NVRAM | Release choice (`docs/gnet_glue_design.md` 3) |

### 6.4 PC card controller and the Taito Type 1 card

| Item | Core | MAME 0.288 | Evidence and status |
|---|---|---|---|
| ExCA register reads | 00h = 83h, 3Ah = 32h, 01h from the slot state, others read back | 0 for every register | RF5C296 manual pp.27, 47 (rank 3); no game reads them |
| Card reset | held while register 03h bit 6 = 0, the reset sequence starts on release | a reset at each write with bit 6 = 0 | Manual p.38 (rank 3); no visible effect in the traces |
| ATA commands | READ SECTORS, WRITE SECTORS, IDENTIFY; anything else aborts | many more | The six games use these three only (MAME traces of all six) |
| Card unlock and relock on a wrong key | as MAME | 5-byte key at attribute 280h to 284h, relock on a mismatch | MAME only (R5); a card on a logic analyser would settle relock |
| Attribute register 07h writes | ignored | ignored | Meaning unknown |
| Data port read before its word arrives | waits | data present at once | Keeps MAME's DRQ timing |
| Card command timing | MAME's (IDENTIFY 10 us busy, 400 ns between sectors) | same | Unknown on the board (R6); load-screen footage would set it |
| Card writes | kept in DDR3 until the core is reloaded | saved in the diff CHD | Ray Crisis writes one 128 KB block of zero-filled sectors right after the first-boot copy; the other games write a few sectors or none (`docs/m0_findings.md` 2 and 3, `docs/m2_glue_findings.md`). What the writes hold is open, and a save path is not built (R25) |
| Card IRQ | none | none | The BIOS steers the RF5C296 IRQ to "not selected" (manual register 03h, p.34; `docs/zn2_layer_design.md` 9) |

### 6.5 MB3773 watchdog

The BIOS and the games kick the watchdog with a falling edge of control
bit 5 (0x1FB40000), about every two frames.

- **Survey** (`docs/gnet_watchdog_mb3773.md` 3): MAME 0.288, every game
  warm and cold. Night Raid (2.946 s), Ray Crisis (2.558 s) and Shikigami
  (2.441 s) have a long gap without a kick, the same in all three: the
  Taito Zoom init releases the Zoom reset and runs a 2,500,000-iteration
  delay loop. The other three stay under 0.51 s. The loop counts
  instructions, so on a slower CPU the gap is longer: Shikigami 3.55 s and
  Night Raid 5.08 s on the 33.87 MHz core (full-system simulation), about
  3 s or more on the board at 0.82 of MAME's rate (estimate).
- **Datasheet**: TWD (ms) is about 100 x CT (uF), about +/-50%; the
  recommended range ends at 1000 ms (CT 10 uF). MAME's 5 s
  (`mb3773.cpp:72`, no source stated) would need about 50 uF. A period
  under 1 s would reset every Night Raid, Ray Crisis and Shikigami board at
  power-on, and they boot. So either the board's CT is far above the
  recommended range, or the MB3773's RESET does not reach the main CPU.
- **Board**: U43 MB3773PF sits next to U5 ADM708AR; the capacitor on
  pin 1 (CT) is an unmarked chip capacitor, and a 10 uF tantalum (C8)
  nearby is on an unknown net (`docs/board_evidence.md` P17, P20).

| Item | Core | MAME 0.288 | Evidence and status |
|---|---|---|---|
| Period | 8 s | 5 s | Lower bound from the games (rank 5 traces of the real game code): above about 3 s on the board. 8 s leaves 2.9 s of margin over Night Raid at 33.87 MHz. Settled by the CT value and the RESET wiring (owner questions 6, 12, 13, 14) |
| What it resets | the whole core, as MAME | the whole machine (`schedule_soft_reset`) | A driver assumption in MAME; open (`docs/board_evidence.md` P20) |
| While paused | masked, and for the period plus 0.5 s after | n/a | Shell feature (section 8) |

### 6.6 Control registers

| Item | Core | MAME 0.288 | Evidence and status |
|---|---|---|---|
| control (0x1FB40000) | bit 5 watchdog, bit 4 Zoom reset (1 at power-on), bit 2 flash bank | same | |
| control2 (0x1FB60000), control3 (0x1FA30000) | latches | latches | Meaning unknown |
| 0x1FB70000 | reads 2 | reads 2 ("so returning 2 always works, strange") | Open (R15). One FC CPLD input is a backup or power-fail status (ack's trace); whether this register reads it is unknown |
| JP1 | MRA switch, off for these six games | input port | JP1 is the 2-pin header beside U30 (bytestorm's photo); only the 2011 conversions use it |
| Bootleg EPROM in bank 2 | reads 0 | MB2011 or flasher image | Not needed for the six sets |

### 6.7 Taito Type 2 card and CompactFlash card

Five sets use the Type 2 card (spuzbobl, spuzboblj, gobyrc, zokuoten,
usagi) and two the CompactFlash card (kollonc, otenamhf)
([taitogn.cpp L389-L407](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L389-L407) and the GAME lines).

| Item | Detail |
|---|---|
| Sources | MAME 0.288 `ataflash.cpp`: `taito_pccard2_device` ([L233-L327](https://github.com/mamedev/mame/blob/mame0288/src/devices/bus/pccard/ataflash.cpp#L233-L327)) and `taito_compact_flash_device` ([L329-L392](https://github.com/mamedev/mame/blob/mame0288/src/devices/bus/pccard/ataflash.cpp#L329-L392)); MAME's note of the values each card type writes to attribute register 07h ([L116-L120](https://github.com/mamedev/mame/blob/mame0288/src/devices/bus/pccard/ataflash.cpp#L116-L120)), which the core ignores as MAME does. Rank 5: MAME is the only description of either lock |
| What the core does | The card's metadata byte (3F0h) selects the type: 02h Type 2, 03h CompactFlash. Type 2: command FEh, then FCh with a 512-byte key block (bytes 2 to 6 the key, the rest zero); a wrong block sets ERR and the card stays locked. CompactFlash: command 0Fh with the key in the task file (feature, sector count, sector number, cylinder low and high); a wrong key clears DRDY. Neither has the Type 1 attribute lock registers (attribute 201h reads FFFFh). The card size comes from IDENTIFY words 60 and 61 |
| How it was checked | Unit test `sim/gnet_ata/tb_ata_t2.sv` (core sources): 28 checks, 0 failures: 13 Type 2, 6 Type 1 regression, 9 CompactFlash, including the CompactFlash status bytes of MAME's otenamhf trace (11h for a locked read, 50h after the right key). Full system, spuzbobl warm boot at 50 MHz: the ATA register traffic equals MAME's cold trace value for value, through a wrong-key block (status 51h three times) and the right key (50h) to IDENTIFY and READ SECTORS; the unlock completes at 0.760 s in the core against 0.207 s in MAME (the core's longer BIOS security polling), game code from 1.06 s. A 25 s run matches MAME's content up to and including the TAITO logo: all 1,489 frames match except the frames at video mode switches; no watchdog pulse. spuzboblj passes the card check with the same unlock sequence. otenamhf (CompactFlash), warm boot to 30 s: the unlock matches MAME's trace register for register and the game reaches its title screen, but not its attract mode within the 30 s, because on the title loop the core's SPU voice register reads run about 2 times slower than MAME's. Type 1 regression: Ray Crisis on the build with the new card types is identical to the previous build over 592 frames |
| Known gaps | No board observation of either lock. Whether a wrong key after an unlock locks the card again is a TODO in MAME too. No Type 2 or CompactFlash set tested on hardware yet. otenamhf's attract mode not yet reached in simulation (the SPU voice register reads above) |

## 7. Taito Zoom sound board

The Zoom board: an MN10200 sound CPU running a program from flash U27, a
ZSG-2 wavetable chip playing samples from the three wave flashes, a
TMS57002 effects DSP on the ZSG-2's sends, an M66220 mailbox to the main
CPU and an MB87078 electronic volume. I wrote all three chips from their
manuals and MAME's behaviour; nothing is taken from other FPGA cores.

### 7.1 Sources

| Source | Rank | Used for |
|---|---|---|
| Panasonic MN102H60G LSI User's Manual 22360-014E and MN102L Instruction Manual 12250-030E | 3 (family manuals; nothing specific to the MN1020012A) | Instruction set with cycle counts, interrupts, timers |
| Texas Instruments TMS57002 User's Guide (1992) | 3 | Memories, host interface, serial formats, external RAM, instruction timing |
| Mitsubishi M66220SP/FP data sheet (1990 Digital ASSP data book) | 3 | The mailbox is a 256 x 8 dual-port RAM with a collision arbiter, no flags |
| Fujitsu MB87078 data sheet, Edition 2.0A | 3 | Control word layout, 0.5 dB gain law, reset to 0 dB |
| Sanyo LC321664 (EN4795C), Sharp LH52B256 | 3 | Delay RAM 64K x 16 fast page mode; work RAM 32K x 8 |
| MAME 0.288 `zsg2.cpp`, `tms57002/*`, `mn10200.cpp`, `taito_zm.cpp`; MAME commit 61c7940 (superctr, 2026-09-14) | 5 | The ZSG-2 has no datasheet: MAME is the highest source for it |
| bannister.org forum, "ZOOM ZFX-2 sound chip support" (2020 to 2021) | 6 | The ZFX-2 on later Taito boards is a TMS57070 variant; no G-NET board with one is known (R9) |

### 7.2 MN10200

- Verified in lockstep against MAME's debugger trace
  (`docs/mn10200_rtl.md` 4): PC, registers, PSW, MDR, the cycle count of
  every instruction, the interrupt request registers and every external
  access; 270.4 million instructions equal over four runs, including a
  directed test of all 159 instruction forms.
- **MULU NF**: at one `mulu` with a product of 2^31 or more, MAME leaves NF
  clear; the MN102L manual (p.79) sets it from bit 31 of the result. The
  core follows the manual. MAME's C code overflows a signed int there
  (`docs/mn10200_rtl.md` 4.3).
- Interrupt acceptance clears PSW.IE, as MAME and the MN102H manual (p.88).
- Timers: the chip family's shared prescalers by default; MAME's per-timer
  phase moves only unused timer request bits, never the program's
  behaviour (4.5). Which phase the MN1020012A has is open.
- Work RAM: 32 KB mirrored, the LH52B256 on the board, against MAME's
  128 KB map; a flag records any access above 32 KB and never fired.

### 7.3 ZSG-2

- Verified by replay (`docs/zsg2_rtl.md` 4): every ZSG-2 access at its
  sample position, all four outputs of every sample and every read: 23.4
  million samples and 1.38 million reads equal to MAME over six 120 s runs
  of four games, plus directed tests against a Python transcription of
  MAME's code (460,026 samples).
- **Register 0xB readback**: the Zoom driver reads a channel's current
  volume, shifts it right 7 bits and ORs it into a byte whose bits 6 and 7
  are flags, so it only works below 0x2000. MAME 0.288 returns 16 bits; in
  Ray Crisis 36% of the reads are 0x2000 or more, which corrupts the voice
  allocator in every game. MAME's later fix returns vol >> 3; the core
  follows it (`docs/zoom_zsg2_tms57002_design.md` 3.7). The exact 13-bit
  mapping is MAME's choice (Z1).
- MAME's guesses kept until PCB audio exists: emphasis filter constants,
  linear interpolation, the output filter, the send gain law, key-on volume
  and attack, the ramp rate, the send scaling into the DSP, immediate
  key-off (3.8, Z2 to Z7).

### 7.4 TMS57002

- Verified by replay (`docs/tms57002_rtl.md` 4): with MAME's parameter set,
  every SO1 sample of Ray Crisis, Psyvariar and Night Raid (5,850,386
  samples, 4,156,318 non-zero) and every periodic state snapshot (all
  memories and all 32,768 delay RAM words) equal MAME's.
- The games program ST0 = 0x0084AA: 64 KB of delay RAM in use, 16-bit
  serial input padded with 8 zero bits (User's Guide p.3-60, Table 3-15
  p.3-64), so the LC321664 is half used and MAME's 256 KB map is masked.

| Item | Core (User's Guide) | MAME 0.288 | Evidence |
|---|---|---|---|
| Multiplier input from AACC | bits 31 to 8 | all 32 bits | Guide p.3-22 (32 x 25 array), rank 3 |
| Coefficient update start | first CMEM read after CLOAD goes high | at the fourth host byte, even while CLOAD is low | Guide p.3-43, rank 3 |
| Serial input width | 16-bit words, low 8 bits zero | float conversion at gain 0.5, low bits set in about 40% of samples | Guide p.3-32, rank 3 |
| External RAM access time | 6 machine cycles | 2 instructions | Guide p.3-72; no audible difference (both programs leave room) |
| ZSG-2 to DSP latency | 1 sample (the documented minimum) | 0 | User's Guide 3.8.1 rules out 0 on hardware; a frame pipeline would give 2. About 31 us, not audible; a scope on SYNC (pin 80) settles it (`docs/board_evidence.md` M10, owner question 15) |
| MACC width | 52 bits | 64 bits | Guide p.3-18; no difference in these programs |

### 7.5 Board glue, mailbox and volume

| Item | Core | MAME 0.288 | Evidence and status |
|---|---|---|---|
| Volume port (0x1FB80000) | read as MB87078 programming: 0.5 dB steps, 63 = 0 dB | linear, (data & 0x3F) / 63 | The address and data writes decode as MB87078 control and gain words (data sheet pp.4, 6). Night Raid and Shikigami (gain 0x30) are 5.1 dB quieter than in MAME, XII Stag (0x36) 3.2 dB. What DSEL is wired to and what channels 0 and 1 attenuate is open (Z10, owner question 3); MAME's law is a build option |
| Coefficient update landing | at the end of the writing MN10200 instruction, between the right two DSP slots | early by up to one 60 kHz timeslice | MAME's DSP lags its MN10200 inside a scheduler timeslice, so its landing is a scheduler artefact (`docs/zoom_board_design.md` 10.5, 15.1) |
| Zoom response to the main CPU | at most 35 us behind real time in play | 16.7 us coupling quantum | The board answers a ZSG-2 read inside a pass (15.3) |
| Zoom reset | ZSG-2 and TMS57002 reset at the release of control bit 4, as MAME | same | Whether the board holds them in reset while bit 4 is set is open (Z17, owner question 11) |
| Mailbox collision arbiter | not modelled | not modelled | Matters only for a same-address access within one clock |
| Later boards with ZFX-2 / MN1020819DA | not supported | not emulated | Both photographed FC PCBs carry the MN1020012A and TMS57002; boards of the late games would tell (R9, owner question 1) |

### 7.6 Board level

- **Lockstep against MAME** (`docs/zoom_board_design.md` 10): the board
  RTL with the real firmware, driven only by the main CPU's accesses as
  MAME made them: 90.6 million (Ray Crisis) and 103.5 million (Psyvariar)
  MN10200 instructions equal, every ZSG-2, mailbox and TMS57002 access
  equal, every ZSG-2 access at MAME's sample position, 2.1 million ZSG-2
  output samples equal.
- **Through the integrated path** (15.4): MAME's main-CPU traffic replayed
  through the ZN-2 bus, the clock crossings and the memory path. The Ray
  Crisis attract music starts in the same sample as in MAME (210,908), at
  the same level (SO1 RMS 450,559.5 against 450,569.8), with an error RMS
  of 1.33% of the signal; not bit-exact, because the free-running board
  differs where the lockstep bench forces MAME's values.
- A bug found this way: the TMS57002 read its serial inputs one queue
  entry late, so the DSP heard silence (about 40 dB down). Fixed before
  this build (14.12).

### 7.7 Sets without a Zoom board

MAME's `init_nozoom` ([L416-L419](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L416-L419)) clears `m_has_zoom`:
the MN10200 is put in reset at machine reset ([L467](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L467)) and the
control register's bit 4 never releases it ([L519-L521](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L519-L521)).
Sets: otenamih, otenamhf, zokuoten, zokuotena, zooo, sianniv and the 2011
conversions.

| Item | Detail |
|---|---|
| What the core does | Bit 1 of the MRA's game configuration byte holds the Zoom MN10200 in reset regardless of control bit 4, as MAME. Existing MRAs (byte 00h or 01h) are unchanged |
| How it was checked | Full system, warm boots of otenamih and zooo to 30 s from the same post-copy NVRAM as MAME 0.288: both reach their attract mode with 0 watchdog pulses, in the same sequence as MAME. The Zoom log (zoom.log) is empty, so no mailbox access, and the Zoom audio is all zero over the 30 s. The flash images converted from their cards (`tools/build_flash.py`) are byte-equal to MAME's NVRAM. Regression with the bit at 0: a 10 s Shikigami warm boot is identical to the tree without the change in zn.log (expansion bus requests), the frames (592), gpu.log, the PC trace, zoom.log and the Zoom audio |
| Known gaps | Whether these boards were fitted without a Zoom board, or had one the games never start, is not documented outside MAME |

## 8. Video output and CRT shell

From `docs/m4_shell.md` unless noted.

- **Pixel clock**: the dot clock is the 53.693175 MHz video clock divided
  by 10, 8, 5 or 4 for the 256, 320, 512 and 640-dot modes the games use
  (every GP1(08h) write in the MAME traces is NTSC, 240 lines, not
  interlaced). Direct video shows even pixel widths. Simulated: each mode's
  active dots are exactly the divider wide, and vertical sync rises and
  falls on a horizontal sync edge (section 2).
- **480i (issue #3, found 2026-10-14 by reading the code, not yet
  fixed or measured):** the traced six games are 240p, but Flip Maze,
  Kollon and Otenami Haiken Final draw 480i, and Zooo, Zoku Otenamihaiken
  and Mahjong Oh switch modes after their init screen (MAME 0.288 GP1(08h)
  logs, 2026-10-14: Zooo and Mahjong Oh 08000027h, 640 x 480 interlaced,
  from about 5.3 s; Zoku Otenamihaiken 08000023h, 640 x 240 with the
  interlace bit, on its boot screen). In 480i the GPU video
  output (unchanged from PSX_MiSTer) starts one field's vertical sync half
  a line later, so the fields interleave on a CRT. The G-NET shell sends
  video through the framework's arcade_video, which updates vertical sync
  only on a horizontal sync edge (sys/arcade_video.v line 71), so the half
  line is lost on direct video and the analog output, and the CRT
  position logic rebuilds vertical sync on line edges too. Scaled HDMI uses
  the field flag instead and is not affected. Fix: keep the half-line
  vertical sync when not scandoubling, in a local copy of arcade_video and
  in the CRT position logic, and offer the Deinterlacing option for HDMI.
  This is also the likely cause of the 480i CRT known issue.
- **Aspect**: HDMI "Original" is 4:3 of the area the game draws (its own
  hblank, 256 to 640 dots), as MAME's default and as a monitor adjusted to
  fill the tube shows it; PSX_MiSTer's fixed padded window is not used.
- **No 216p crop**: the games draw 240 lines.
- **Flip Screen** is the GPU video output's 180-degree turn (lines bottom
  to top, dots right to left). The ZN-2 GPU has no flip register; this is a
  display convenience for rotated monitors, not a board feature.
- **Rotation** for HDMI through the framework's screen_rotate, with its
  writes into DDR3 through the G-NET arbiter's FIFO, fed before the
  scandoubler (`docs/ddr3_arbiter.md`).
- **CRT position** moves only the regenerated sync pulses; the picture,
  the blanking and the game's timing are unchanged (bench: every setting
  shifts sync by exactly the expected clocks).
- **Black picture with running sync** while the core is in reset or
  loading, so a CRT keeps lock.
- **Pause** holds the CPU, GPU, SPU and the Zoom board; the audio is
  muted, and the watchdog is masked while paused and for 8.5 s after.
- **EEPROM save**: a copy of the AT28C16 is uploaded as NVRAM when the OSD
  opens after a write. Needs confirmation across a power cycle on hardware.
- **Debug overlay**: live board state and a snapshot at the last watchdog
  expiry that survives the reset (`docs/hw_debug_overlay.md`).

## 9. Open questions, by the evidence that would settle them

| Evidence | Settles | Section |
|---|---|---|
| Frequency counter on the CXD8661R clock, or a timing test program on any CXD8661R board | CPU clock, cache, RAM and flash wait states, root counter clock, SIO0 timing, GPU and SPU register latency | 2 |
| 60 fps direct capture of Ray Crisis attract demo 1 and of heavy scenes (Shikigami no Shiro's included, issue #5) | slowdown, GPU drawing time on the core | 2, 3 |
| ps1-tests `cpu/access-time` and `gpu/bandwidth` run on a ZN-2 or G-NET board | RAM load cost and GPU drawing rates of the CXD8661R and CXD8654Q themselves | 2, 3 |
| Which console produced the ps1-tests `psx.log` and `vram.png` references | the rank of every ps1-tests comparison in this document | 2, 3 |
| Timed video of a normal power-on (Night Raid, Ray Crisis, Shikigami) to the NOTICE screen | CPU speed in the card-copy and Zoom-init phases; the watchdog does not fire there | 2, 6.5 |
| Timed video of a first boot after a card swap | first-boot copy length, card timing | 6.3, 6.4 |
| Frequency counter on composite sync | frame and line rate | 3 |
| Line-out recording of a board (stereo, volume noted), or the analog mixing resistors | SPU against Zoom balance, MB87078 law, ZSG-2 guesses | 4, 7 |
| Value of the MB3773 timing capacitor and where RESET goes | watchdog period and reach | 6.5 |
| Close-ups or continuity checks on the FC PCB (TMS57002 pins 10 and 80, MB87078 DSEL, U30 BYTE#, Zoom reset line, AT28C16 marking) | DSP clock mode and latency, volume wiring, flash bus width, reset reach, EEPROM write time | 5, 6, 7 |
| A board boot video or owner report of Kollon and Space Invaders Anniversary T1 cards | whether the ttgnirq race also hits real boards | 2.5 |
| A Go By RC or RC De Go controller (or its manual) | trigger direction and wheel range | 5.4 |
| G card manuals | button names, per-game DIP use, Night Raid's monitor orientation | README |

The questions for board owners, in plain language, are in
`docs/TESTING_GUIDE.md`; the full list with sources is in
`docs/board_evidence.md` section 4. "Owner question N" in this document
refers to that list's numbering.

## 10. Reproducing the checks

| What | Tool or bench |
|---|---|
| MAME traces (bus, glue, GPU stream, SIO0, Zoom, frames) | `tools/mame/*.lua` with their runner scripts; MAME 0.288 and your own files |
| Flash images from a card | `tools/build_flash.py <card.img> coh3002t.zip <outdir> [--check <MAME nvram dir>]` |
| GPU replay and ps1-tests | `sim/m1/`, `tools/gpu_stream.py`, `tools/vram_compare.py`, `tools/ps1test_stream.py`, `tools/ps1test_compare.py` |
| ZN-2 layer | `sim/zn2/` (CAT702, SIO0, zn2_io, memorymux, system bench) |
| G-NET glue | `sim/gnet/` (replay and directed tests) |
| Zoom chips and board | `sim/mn10200/`, `sim/zsg2/`, `sim/tms57002/`, `sim/zoomboard/`, `sim/zoomlink/`, `sim/zoomddr3/` |
| CPU timing | `tools/r1/` (footage analysis, memory latency bench, cycle breakdown) |
| Shell | `sim/shell/`, `sim/dbg/`, `sim/rotfx/` |
| PC card types | `sim/gnet_ata/tb_ata_t2.sv` (Verilator) |
| Frame comparison | `tools/frame_hash.py` |
