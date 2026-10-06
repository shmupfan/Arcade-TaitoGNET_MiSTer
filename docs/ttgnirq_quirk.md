# ttgnirq: why MAME masks IRQs at 0x80010008 (kollon, sianniv)

Research item R27 (`docs/PLAN.md` 6, `docs/gnet_set_survey.md` 2.2). I
traced this on 2026-10-06 in MAME 0.288 under the debugger (warm boots from
post-copy NVRAM; the scripts and logs are game-derived and not committed).
Times are MAME psx cycles (100 MHz / 4 = 25 M/s); one frame is 417,878
cycles (16.715 ms, 59.826 Hz). MAME source lines refer to `taitogn.cpp` at
tag mame0288 ("gn:N" = https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#LN).

## 1. What MAME's workaround does

`ttgnirq_state::driver_start` ([gn:649 to 680](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L649-L680)) installs a read tap on
0x80010008 to 0x8001000b. When the CPU fetches the instruction at PC
0x80010008 it writes 0 to I_MASK (0x1f801074). Nothing else changes: SR
stays 0x40000401 (IEc = 1, IM2 = 1, CU2 = 1), I_STAT is untouched, and the
game rewrites I_MASK itself a few thousand instructions after its BSS clear.
The tap fires on every fetch of that address; the first hit is a BIOS-stage
program at about cycle 1.92 M with I_MASK already 0 (harmless), the second
is the game entry.

Applied to sianniv and kollon only ([gn:1365, 1366](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L1365-L1366)). kollonc ([gn:1367](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L1367)) runs as
plain `taitogn_state`.

## 2. Mechanism

0x80010008 is the game's crt0. It clears BSS with a five-instruction loop
(store word, add 4, compare, branch, delay slot) and then calls main:

| Set | BSS cleared | Delay slot of the clear loop |
|---|---|---|
| kollon V2.04JA | 0x8007f6f0 to 0x803c1820 | nop |
| sianniv V2.02J | 0x8008b360 to 0x803ac430 | nop |
| kollonc V2.04JC | 0x800833a8 to 0x803c54d8 | `mtc0 zero,SR` |
| nightrai, psyvaria(j), psyvarrv, shikigam(a), xiistag (card images) | ends at 0x8019a430 or lower | nop |

The program that jumps there is the sub-BIOS loader (flash.u30 in U30,
built by tools/build_flash.py; the game program sits at U30 0x60000 and is
copied to 0x80010000). The loader's code lives from about 0x803a0000 (lowest
PC seen 0x803a013c); its stack, gp data, callback tables and setjmp buffer
are above 0x803c7000. kollon and sianniv are the only sets whose BSS reaches
into the loader's code.

The loader leaves its interrupt system running when it jumps:

- Last calls before the jump (0x803aa5c0 to 0x803aa60c): remove a frame hook,
  sleep 1 frame (0x803a029c is a task-switch sleep), SetDispMask(0) (GP1
  0x03000001), sleep 2 frames, ResetCallback (0x803b721c through the libetc
  table; a no-op because the loader's own init flag is set), FlushCache
  (A(44h)), then `jalr` to 0x80010008.
- At the jump (cycle 124,997,288): SR 0x40000401, I_MASK 0x429 (VBLANK, DMA,
  TMR1, IRQ10), I_STAT 0, kernel custom exit hook (0x8000a5d0) = 0x803c84d0,
  a jmp_buf into the loader's dispatcher at 0x803b7418. Dispatcher table mask
  0x409: VBLANK to 0x803b79c4, DMA to 0x803b7ad8, IRQ10 to 0x803aacc4. VSync
  callback slot 4 = 0x803a3fd8 (the loader's scheduler tick, which calls
  0x803a2258).
- The jump is phase locked to VBLANK: it happens 51,819 cycles (2.07 ms)
  after a VBLANK interrupt, because of the sleeps.

Every VBLANK during the clear goes kernel handler, then the custom exit,
then loader code at 0x803b7418, 0x803b79c4, 0x803a3fd8, 0x803a2258. While
the clear pointer is below that code nothing happens (MAME logs nine clean
VBLANKs inside the loop). Once the pointer passes 0x803a2250, the tick
executes zeroed memory (zero decodes as nop), slides to the tail of another
function, pops a garbage return address and faults.

Observed in kollon with the tap neutralised (I_MASK restored at 0x8001000c):

| Event | Cycle |
|---|---|
| Sync VBLANK | 124,945,469 |
| Jump to 0x80010008 | 124,997,288 |
| Tenth VBLANK in the loop, pointer at 0x803a2a04 | 129,124,249 |
| Address error fetch, EPC = 1, Cause ExcCode 4 | 129,125,829 |
| Then BIOS A(40h) error loop, watchdog reset, same crash every boot | |

With the hack the clear ends at 129,267,752 and the game zeroes I_MASK
(its own ResetCallback, PC 0x8005c394) at 129,279,774, 12,022 cycles later.
That write, followed by a new custom exit hook, closes the window.

sianniv is the same loader (same hook buffer, same return address
0x803aa614). Its clear ends at 129,098,645, but its game runs 280,623
instructions with SR 0x40000401 before its first I_MASK write (PC 0x8002bd0c,
cycle 129,379,268). Without the hack the VBLANK at 129,124,249 lands in that
stretch and the board resets.

Vulnerable window (from the pointer passing 0x803a2250 to the game's I_MASK
write), MAME timing:

| Set | Window | Width | VBLANK inside |
|---|---|---|---|
| kollon | 9.959 to 10.372 frames after the sync VBLANK | 41% of a frame | yes, 15,791 cycles (0.63 ms) after the window opens |
| sianniv | 9.815 to 10.610 frames | 80% of a frame | yes |

kollonc is the proof that Taito knew: its crt0 has `mtc0 zero,SR` in the
delay slot, so SR is 0 for the whole clear (sampled every 512 KB: SR 0, I_STAT
1 pending, never taken). Patching that delay slot back to nop in MAME makes
kollonc hang at the same point (VBLANK at 3,423,673,068 with the pointer at
0x803a66d8, then bus and address error exceptions). So the race is in the
game, not in MAME, and the later CF build fixes it in software.

## 3. What real hardware does differently

| Candidate | Verdict |
|---|---|
| VBLANK not asserted on the board | Ruled out: the loader's sleeps right before the jump are woken by the VBLANK tick, and its dispatcher handles VBLANK. Display off (SetDispMask(0)) does not stop the PS1 VBLANK interrupt |
| Another source masked or absent | Not relevant: only VBLANK fires in the window in MAME. IRQ10 (dispatcher handler 0x803aacc4) is not wired in MAME or in the core (core IRQ10 = lightgun/SNAC only); no new ATA command is issued after the jump |
| Instruction cache keeps the old loader code | Does not save it. Of 260 cached lines on the IRQ path, 69 indices hold two or three tags. The tick's entry lines 0x803a3fd0 to 0x803a3ff0 alias kernel lines 0x3fd0 to 0x3ff0 run earlier in the same IRQ, and 0x803a4010/20 alias the clear loop itself, so they are refetched from RAM each VBLANK and come back as zeros once cleared (4 KB direct mapped, 16-byte lines). The window opens about 1,900 words later, nothing more |
| Memory contents at boot | Not relevant: the loader writes all of it |
| CPU speed relative to VBLANK | The only explanation left. The window position is a deterministic function of CPU throughput (the jump is VBLANK locked, then about 10 frames of CPU work). In MAME a 0.4% faster clear would save kollon |

So the board survives, if it does, by timing. A uniform rate model (all CPU
work scaled by r against MAME) puts both sets safe only in narrow bands
(sianniv safe at r 0.885 to 0.89, 0.965 to 0.98, 1.065 to 1.09 and higher
bands); at the PCB's measured 0.82 for loader code (docs/r1_speed_study.md)
kollon sits in a narrow safe band (0.800 to 0.825) and sianniv is not safe. Either the store loop and general code
scale differently on the board, or the T1 sianniv and kollon cards do not
boot reliably on every board. No PCB evidence either way: needs-review.

## 4. What the MiSTer core will do

- The core runs the same loader and game code with the same IRQ setup.
  Nothing in rtl/irq.vhd or rtl/gnet/ masks VBLANK or adds an IRQ here.
- rtl/cpu.vhd keeps an instruction cache with tags and per-word valid bits
  and invalidates it only on isolated-cache writes, like the R3000A, so the
  core matches the board's cache behaviour, which section 3 shows does not
  rescue the IRQ path.
- The outcome therefore depends on where the core's VBLANK falls in a
  window 40% (kollon) to 80% (sianniv) of a frame wide, after about ten
  frames of CPU work at the core's rate (50 MHz domain, calibration to the
  PCB loader still to come). I expect sianniv to fail and kollon to be a
  coin toss, and any later CPU timing change can flip either. Medium-low
  confidence; this is a prediction, not a measurement.
- Hardware, 2026-10-06: Kollon (unpatched U30, quick-start MRA) boots on my
  DE10-Nano through the BIOS bar and the CyberFront logo to its title
  screen (GNET_Z1FULLO build of 2026-10-06 21:10, RBF md5
  9dbb24050526436c111e34a4d38624db); not played further. Space
  Invaders Anniversary is not tested yet.

## 5. Recommendation

Status (2026-10-06): not implemented. The release builds U30 without this
patch; Kollon boots to its title screen on my MiSTer with the unpatched U30
(section 4). I add the patch only if Space Invaders Anniversary fails on
hardware, and then as an opt-in converter option, off by default.

No RTL change. Do not copy MAME's fetch tap: it has no hardware basis and
would need a PC match in the CPU path.

Apply Taito's own fix as data, for kollon and sianniv only: the delay slot
of the crt0 clear loop becomes `mtc0 zero,SR` (0x40806000), exactly as in
kollonc.

- Where: tools/build_flash.py, in the gameprog copied to U30 0x60000, word
  at U30 0x60028 (gameprog file offset 0x28). Guard it on the expected
  bytes (old word 0x00000000 after the loop `bnez at,-4` = 0x1420fffc and
  the `lui v0` crt0 header). Card image equivalents, if the card copy is
  ever run instead: kollon card offset 0xfe7a28, sianniv 0x15c7a28.
- Verified in MAME with the tap neutralised: a patched U30 NVRAM (MAME
  stores it byte swapped per 16-bit word) boots both sets with no reflash
  and no checksum complaint, and the snapshots are pixel identical to the
  MAME-hack runs (every 300 frames: kollon frames 300 to 2100, sianniv 300
  to 1500). The game sets SR back to 0x40000401 itself (sampled at
  10 s), so the cleared CU2 bit costs nothing. The loader does not read the
  word between copying it (cycle 72.3 M) and the jump.
- Behaviour difference from MAME's hack: none visible (MAME zeroes I_MASK,
  the patch clears SR; the game reinitialises both).

Confidence: mechanism high (traced); kollonc fix and the patch high (MAME);
hardware explanation (timing) medium-low, needs-review; core outcome
without the patch medium-low.

## 6. Tests

1. Fullsys sim boot of kollon and of sianniv from prebuilt flash, unpatched,
   at least to the game's first I_MASK write (MAME: 5.17 s for kollon, 5.18 s
   for sianniv after reset; the core's time will differ). Pass: PC reaches
   0x8005c394 (kollon) or 0x8002bd0c (sianniv) and later frames draw. Fail
   signature: an interrupt taken after the clear pointer passes 0x803a2250,
   then EPC in 0x803a or 0x803b space, EPC = 1 or a BIOS A(40h) loop and a
   watchdog reset. Log I_STAT/I_MASK, the exception vector and v0 at
   0x80010018 to see the margin.
2. The same with the patched U30. Must pass for both sets.
3. Regression: the other T1 sets must be unaffected (the patch is gated on
   set and bytes; their BSS ends at 0x8019a430 or lower anyway).

## 7. Open questions

- Do kollon and sianniv T1 cards boot every time on a real board? A PCB
  boot video or an owner report would settle whether the board is lucky or
  faster in the clear loop. needs-review
- IRQ10 on the G-NET board: the loader enables and handles it (0x803aacc4),
  so some device raises it on hardware; MAME and the core leave it
  unconnected. Not needed for this item, but worth identifying (card
  controller interrupt is my guess, needs-review).
- TMR1 is unmasked in I_MASK but its mode at the jump (0x1148) has both
  IRQ enables (bits 4 and 5) clear, so it raises nothing. Any IRQ that did
  arrive would hit the same zeroed dispatcher in kollon (its BSS also covers
  0x803b7418); the same fix covers it.
