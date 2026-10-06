# MB3773 watchdog: kick gaps in MAME and the real period

Status: 2026-10-05. Question: the core's watchdog is a flat 5 s (MAME's
mb3773.cpp guess). The Shikigami warm boot has a 2.44 s gap without a kick
in MAME and 3.55 s in the 33.87 MHz core. Which games come close to the
period, and what is the real period?

## 1. Answer

- **Three games have a long no-kick gap, all from the same Taito Zoom
  init routine.** It releases the Zoom reset and then runs a fixed
  2,500,000-iteration delay loop without kicking. The gaps in MAME are
  Night Raid 2.946 s, Ray Crisis 2.558 s and Shikigami 2.441 s, the same
  on warm and cold boots.
- **The other three stay under 0.51 s.** Psyvariar Medium Unit, Psyvariar
  Revision and XII Stag never come near either limit.
- **The gap is CPU-bound, not frame-paced.** The loop counts instructions,
  so a slower CPU makes it longer. In the full-system simulation at
  33.87 MHz (2026-10-06) Shikigami's gap is 3.55 s and Night
  Raid's is 5.081 s (6.411 to 11.492 s). Night Raid scales by 1.72 times
  its MAME gap, not by Shikigami's 1.45; my earlier scaled estimate of
  4.3 s was too low. A 5 s watchdog resets Night Raid at 33.87 MHz (it
  fired at 11.411 s, 81 ms before the game's next kick, and again on the
  second boot); 8 s leaves 2.9 s of margin, and a 30 s run of the
  01:14 gnet_z1 build (8 s) had no watchdog pulse in Night Raid or
  Shikigami. At 50 MHz Night Raid
  passed the gap with no reset under 8 s (my run, 98f4c77).
- **The datasheet does not fit a period under 1 s.** The recommended
  range for the MB3773 tops out at tWD = 1000 ms (CT 10 uF). Any period
  that short would reset every real board during this loop. MAME's
  logging and the kick wiring are not the explanation (section 4).
  Either the board uses a much larger CT than the datasheet recommends,
  or the MB3773 RESET does not reset the main CPU. The photo does not
  settle which (section 5).
- **Recommendation for the core:** keep the watchdog, but make the period
  comfortably longer than the slowest-CPU Night Raid gap. 8 s or more
  would cover it; the exact figure is a choice to make.

## 2. MAME's CPU rate

zn.cpp:91 clocks the ZN-2 CXD8661R at XTAL(100'000'000). psx.h:181
(`execute_clocks_to_cycles`, clocks / 4) and psx.cpp:3347 (`m_icount--`
once per instruction) mean MAME executes 25,000,000 instructions per
emulated second. It applies no memory wait states. That is 1.476 times
the PS1 model (67.7376 MHz / 4 = 16.93 M), so in PS1 terms it behaves like
a 50 MHz CPU. docs/r1_speed_study.md measures the PCB at about 0.82 of
MAME's rate.

## 3. Survey

Method: `tools/mame/wdt_survey.sh` runs `tools/mame/wdt_survey.lua`, one
MAME at a time under nice -n 15. A kick is a falling edge of bit 5 written
to 1FB40000 (taitogn.cpp:516; mb3773.cpp re-arms its timer on ck 1 to 0;
the datasheet also says the negative CK edge).

- Warm runs: the post-copy flash images, no EEPROM file and an unmodified
  card, as a warm-boot MRA gives the core; 120 s, coin at 40 s.
- Cold runs: empty NVRAM; 300 s, coin at 180 s.
- Inputs as in the earlier oracle runs.
- Summary: `tools/mame/wdt_report.py sim/oracle/wdt`.

No run had a watchdog reset. In normal running the games kick about every
2 frames (bit 5 alternates d8/f8 once per frame).

Columns:
- "Gap" is in emulated seconds.
- "Cycles" is MAME instructions (25 M/s), plus the same interval in clocks
  at 33.8688 MHz and at 50 MHz.
- "From/to PC" are the kicks that open and close the gap.
- "vs 1 s / vs 5 s" is the gap as a fraction of each period.

| Game | Boot | Longest gap | Where (t, phase) | From / to PC | MAME instr | clk 33.87 | clk 50 | vs 1 s | vs 5 s |
|---|---|---|---|---|---|---|---|---|---|
| Night Raid | warm | 2.9456 s | 5.128 to 8.073 s: Zoom init after the prepare bar, black/white screens before NOTICE | 8008C6D4 / 8008C6D4 | 73.6 M | 99.8 M | 147.3 M | 2.95 | 0.59 |
| Night Raid | cold | 2.9456 s | 140.32 to 143.27 s: the same, right after the flash copy | 8008C6D4 / 8008C6D4 | 73.6 M | 99.8 M | 147.3 M | 2.95 | 0.59 |
| Ray Crisis | warm | 2.5576 s | 15.70 to 18.25 s: Zoom init, black screen between COMPLETE and NOTICE | 801300A0 / 801300A0 | 63.9 M | 86.6 M | 127.9 M | 2.56 | 0.51 |
| Ray Crisis | cold | 2.5575 s | 155.43 to 157.99 s: the same after the copy | 801300A0 / 801300A0 | 63.9 M | 86.6 M | 127.9 M | 2.56 | 0.51 |
| Shikigami | warm | 2.4412 s | 5.342 to 7.783 s: Zoom init, black screen before NOTICE | 800614F4 / 800614F4 | 61.0 M | 82.7 M | 122.1 M | 2.44 | 0.49 |
| Shikigami | cold | 2.4004 s | 146.47 to 148.87 s: the same after the copy | 800614F4 / 800614F4 | 60.0 M | 81.3 M | 120.0 M | 2.40 | 0.48 |
| Shikigami | warm, 2nd | 0.6080 s | 116.24 to 116.85 s, in play (coin at 40 s) | 800614F4 / 800614F4 | 15.2 M | 20.6 M | 30.4 M | 0.61 | 0.12 |
| XII Stag | warm | 0.4944 s | 5.222 to 5.717 s: black screen after the prepare bar | 8008AE80 / 8008AE80 | 12.4 M | 16.7 M | 24.7 M | 0.49 | 0.10 |
| XII Stag | cold | 0.5070 s | 130.21 to 130.71 s: after the copy | 8008AE80 / 8008AE80 | 12.7 M | 17.2 M | 25.4 M | 0.51 | 0.10 |
| Psyvariar Medium Unit | warm | 0.1454 s | 16.18 to 16.33 s, Prologue attract | 8004EF08 / 8004EF08 | 3.6 M | 4.9 M | 7.3 M | 0.15 | 0.03 |
| Psyvariar Medium Unit | cold | 0.1454 s | 142.55 to 142.69 s | 8004EF08 / 8004EF08 | 3.6 M | 4.9 M | 7.3 M | 0.15 | 0.03 |
| Psyvariar Revision | warm | 0.1206 s | 4.948 to 5.068 s, after the prepare bar (no screen capture for this set; Medium Unit is black from 5 s) | 803AD398 / 8004EACC | 3.0 M | 4.1 M | 6.0 M | 0.12 | 0.02 |
| Psyvariar Revision | cold | 0.1206 s | 134.26 to 134.38 s | 803AD398 / 8004EACC | 3.0 M | 4.1 M | 6.0 M | 0.12 | 0.02 |

803AD398 is the BIOS-stage kick (the prepare-bar loop); the other PCs are
each game's own kick routine. Shikigami's 2.4412 s matches the earlier
trace `sim/oracle/shikigam_warm20` exactly (kick at 7.7833 s).

## 4. The long gap

Night Raid (RAM 8008B300), Ray Crisis (8013E114) and Shikigami (8006F830)
contain the same routine. It clears bit 3
of the control register at 1FB40000, sets it again, then clears bit 4, which
releases the Zoom board's MN10200 from reset. It then runs a delay loop of
10 `nop`s with the counter on the stack, while i <= 2,499,999 (0x26259F), with
no watchdog kick inside it.

The loop is 19 instructions per iteration, so 2,500,000 iterations are 47.5 M instructions or
1.90 s at 25 MIPS. Measured from the bit-4 write to the next kick it is
1.998 s for Shikigami, 2.085 s for Ray Crisis and 2.587 s for Night Raid;
the rest is interrupt time. Bit 5 stays 0 from the kick before the routine
until well after the loop, so there is no falling edge.

The peer session's four possibilities:

- **(a) Something else restarts the MB3773: ruled out within what can be
  observed.**
  - Writes to 1FB40000 in the Shikigami gap: d8 at 5.391 s; then d0, d8
    and c8 at 5.7156 s (the routine above); then e8 at 7.7131 s. Bit 5
    only rises again at the end.
  - Bit 3 falls once, inside the routine. Bit 5 is the bit that
    alternates once per frame in normal running, which is the usual
    kick pattern, so CK on bit 3 would leave every normal frame unkicked.
  - Nothing else in the gap looks like a strobe. The only other control
    registers touched are 1FB70000 (0/1 bursts at 5.37 to 5.40 s and
    from 7.6 s; taitogn.cpp:572 does not know its use) and one read of
    1FA10200. Between the bit-4 write and the next bit-5 write there are
    about 50 GPU, 301 SPU and 12 Zoom accesses. 115 of the 120 per-frame
    PC samples are inside the loop; the other 5 are in game code at
    80063940 to 800728F8. My reading is that these accesses are interrupt
    handlers.
- **(b) RESET does not reach the main CPU: possible, not established.**
  - MAME's mb3773 calls schedule_soft_reset (the whole machine). That is
    the driver's assumption, not a board trace.
  - The FC PCB also carries an ADM708AR (U5), a supervisor without a
    watchdog. Where the MB3773 RESET goes is not in docs/board_evidence.md.
- **(c) The gap is shorter on hardware: no.**
  - The loop counts instructions, and the PCB measures 0.82 of MAME's
    rate, so on the board it is longer: roughly 3.0 s for Shikigami and
    3.6 s for Night Raid at 0.82 (an estimate from the measured rate,
    not a measurement of this loop).
  - The R3000's lack of a data cache makes the stack load and store
    slower than MAME's flat 1 cycle, so it is longer still.
  - MAME's Lua has no CPU clock-scale setter (`cpu.clockscale` cannot be
    assigned in 0.288), so I could not rerun with a slower CPU. The
    disassembly settles it.
- **(d) MAME misses kicks: no.**
  - Two independent logs agree on the 2.441 s Shikigami gap and the kick
    times: the write tap of this survey, and the full access log of
    oracle.lua (sim/oracle/shikigam_warm20/ctrl.log).
  - The tap sees every CPU write to 1FB40000, whatever the value.

So on a real board this gap is about 3 s or more. A watchdog anywhere
near the datasheet's recommended maximum of 1 s would reset every Night
Raid, Ray Crisis and Shikigami board at the first boot after power-on,
and they boot. So one of these holds:

- CT is far above the recommended 10 uF: about 47 uF or more for a typical
  TWD of 4.7 s, and with the ±50% tolerance at 0.1 uF, more like 100 uF
  for a safe margin;
- the RESET output is not connected to the main CPU's reset;
- both.

Taito's own code assumes a gap of at least about 3 s is safe.

## 5. Datasheet and board

Fujitsu DS04-27401-7E (local copy:
mister-arcade-survey/datasheets/misc_gnet/MB3773_Fujitsu_DS04-27401-7E.pdf):

- **Formulas:**
  - TWD (ms) ≈ 100 × CT (uF): watchdog monitoring time.
  - TWR (ms) ≈ 20 × CT (uF): reset pulse length on a timeout.
  - TPR (ms) ≈ 1000 × CT (uF): power-on reset hold.
- **Tolerance:** at CT = 0.1 uF the electrical table gives TWD 5 / 10 /
  15 ms (min / typ / max), TWR 1 / 2 / 3 ms and TPR 50 / 100 / 150 ms. TWD
  is about ±50%.
- **Timing from the last kick:** CK triggers on the falling edge, while CT
  discharges; reset comes TWD to TWD + TWR after the last kick (operation
  sequence item 6).
- **Recommended limits:** tWD 0.1 to 1000 ms; CT 0.001 to 10 uF; CK input
  pulse width 3.0 us minimum.
- **CT pin:** pin 1 (pinout: 1 CT, 2 RESET-bar, 3 CK, 4 GND, 5 VCC,
  6 VREF, 7 VS, 8 RESET).
- **What 5 s means:** MAME's 5 s corresponds to CT ≈ 50 uF typical.

FC PCB underside photo (System 16, `boards/gnet_1st_under.jpg`, 2048 x
1536; viewed in the browser through the System 16 page, not saved):

- U43 reads "MB3773PF". The package's second marking line is not legible.
- Next to it: R35 (resistor, value not legible) and C101 (a small chip
  capacitor; chip ceramics carry no value marking). Below them is a
  resistor whose label is not legible.
- C8, a tantalum marked "10 16V" (10 uF, 16 V), sits between U4
  (uPD6379GR, the DAC) and U43. From the photo I can't tell which net it
  is on. If it were CT, TWD would be about 1 s typical, which section 4
  rules out unless RESET does not reach the CPU.
- Pin 1 of U43 runs to a via near R35 and C101. I can't follow it further
  in the photo.
- Still needed (board_evidence.md P17 and request item 6): the CT value
  (a measurement, or a photo of the component on pin 1's net) and where
  RESET (pin 8) and RESET-bar (pin 2) go.

## 6. For the core

- **Period:** the core's period has to exceed the longest gap at the
  slowest CPU rate the core runs. On the 33.87 MHz build that is Night
  Raid, measured at 5.081 s in the full-system simulation, so 5 s resets
  it. 8 s (now in the builds) leaves 2.9 s; 10 s would give more room for
  slower memory paths while still catching a real hang. The fix for the
  extra cycles per main-RAM load (9.6 against about 7, being prototyped)
  should shorten the gap.
- **What to measure:** running Night Raid in the fullsys harness or on
  hardware with a kick logger would give the real core figure.
- **Re-measuring:** `tools/mame/wdt_survey.sh` repeats the MAME numbers
  for any set list. `tools/mame/wdt_gap_probe.lua` logs every
  control-register write and the per-frame PC.
