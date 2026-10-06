# R18: PSX blocks used by the G-NET games (MDEC, SPU)

Measured 2026-10-04 in MAME 0.288 with `tools/mame/r18_trace.lua` (runner
`sim/r18/run_all.sh`) and `tools/mame/r18_scan.py`. ROMs verified with
`mame -verifyroms` (BIOS and all nine priority CHDs OK).

## Method

1. Dynamic: main-CPU write/read taps on MDEC0/MDEC1 (0x1f801820-27), DMA
   channel 0/1 CHCR start bit (0x1f801088, 0x1f801098), SPU key-on
   (0x1f801d88-8b) and SPU control (0x1f801daa); GPU GP0/GP1 writes as a
   control. Each game from a cold first boot (empty NVRAM, so the BIOS
   copies the card into the flashes) for 900 emulated seconds: first boot,
   attract, a coin at 240 s (0.1 s pulse), start, fire held with left/right
   movement. Snapshots every 120 s from coin+10 s confirm play.
2. Static: main RAM (4 MB) dumped after 120 s from the post-copy NVRAM
   with a game in progress; count of 32-bit words equal to each register
   address (KUSEG/KSEG0/KSEG1 forms). GPU and SPU addresses are the
   positive control.

Method note: a first static attempt matched `lui 0x1f80` plus offset
instruction pairs; the GPU control was zero, so these games do not address
hardware that way and the method was dropped. A first dynamic run held the
coin for a whole second (Lua `machine.time.seconds` is the integer part),
which made every game reset 5 s later and lost the earlier counts; fixed
with `as_double` and 0.1 s pulses, then rerun.

## Results

| Game | Emulated s | GPU writes | MDEC access | DMA0/1 starts | SPU key-ons (first at) | Play seen in snapshots |
|---|---|---|---|---|---|---|
| raycris | 900 | 1,823,883 | 0 | 0 / 0 | 4,674 (155.5 s) | yes |
| psyvarrv | 900 | 2,711,574 | 0 | 0 / 0 | 6,180 (136.8 s) | yes (area 1) |
| xiistag | 900 | 5,041,830 | 0 | 0 / 0 | 4,075 (132.9 s) | yes (name entry after play) |
| shikigam | 900 | 3,399,308 | 0 | 0 / 0 | 2,286 (146.3 s) | yes (game result) |
| nightrai | 900 | 2,798,557 | 0 | 0 / 0 | 9,958 (143.1 s) | yes (tutorial) |
| psyvaria | 532.8 | 245,556 | 0 | 0 / 0 | 1,482 (133.8 s) | yes (gameplay at 250 s) |

psyvaria: MAME exited cleanly at 532.8 s with no error and no reset logged
(cause needs-review); its counts cover first boot, attract and one credit.

Static constants in RAM during play:

| Game | GPU GP0/GP1 | SPU | MDEC0/1 | DMA0 regs | DMA1 regs |
|---|---|---|---|---|---|
| raycris | 6 | 8 | 0 | 2 | 0 |
| psyvarrv | 6 | 8 | 0 | 2 | 0 |
| xiistag | 3 | 9 | 0 | 1 | 0 |
| shikigam | 6 | 9 | 0 | 2 | 0 |
| nightrai | 6 | 8 | 0 | 2 | 0 |
| psyvaria | 6 | 10 | 0 | 2 | 0 |

The DMA0 hits are its base address 0x1f801080, which is also the DMA
register block base used by generic DMA code, so they do not indicate MDEC
use.

## Conclusion

- **MDEC: unused** by all six games in boot, the first-boot flash copy,
  attract and early play, and no MDEC register address exists in the code
  resident in RAM during play. Evidence rank 5 (MAME behaviour of the real
  game code). Remaining gap: code loaded only for later stages (overlays)
  is not covered; a later-stage trace (MAME save states or longer scripted
  play) would close it. Decision proposed: MDEC off in the G-NET build
  (switch HAS_MDEC=0), saving 713 ALMs, 19 M10K, 9 DSP (V0).
- **SPU: used** by all six (key-ons from the first game frame after the
  flash copy). Keep.
- First-boot flash copy, by first SPU activity: 133 to 155 emulated
  seconds from power-on (R3 data point; MAME notes say 2 to 3 minutes on the
  PCB).
