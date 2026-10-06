# M2 part 1: G-NET glue RTL, verified against MAME 0.288

Status: DONE for part 1 (2026-10-04). Standalone blocks in `rtl/gnet/`, not
yet integrated into psx_top/memorymux (that comes later, coordinated with
M1). Plan: docs/PLAN.md 3.2 and 4 (M2). Design study:
docs/gnet_glue_design.md.

## Result

I replayed every main-CPU access to the glue that MAME 0.288 makes during a
300 s cold first boot (the card-to-flash copy, then attract and a credit of
play) into the RTL, for all six priority games. Every read matches MAME. The
five flash chips end word-identical to MAME's NVRAM, and the card sectors
the games write are identical to MAME's card image.

| Set | MAME accesses (records) | Replayed accesses | Read mismatches | Flash words differing (5 chips) | Card sectors written / differing |
|---|---|---|---|---|---|
| raycris | 391,971,443 (33,632,479) | 38,520,640 | 0 | 0 | 32 / 0 |
| psyvarrv | 312,633,470 (31,810,248) | 36,901,475 | 0 | 0 | 7 / 0 |
| xiistag | 309,711,087 (15,166,779) | 17,830,186 | 0 | 0 | 4 / 0 |
| shikigam | 339,247,146 (33,465,624) | 38,127,301 | 0 | 0 | 0 / 0 |
| nightrai | 327,057,775 (33,007,314) | 38,400,026 | 0 | 0 | 0 / 0 |
| psyvaria | 359,595,552 (30,659,026) | 36,280,712 | 0 | 0 | 6 / 0 |

"Replayed" is less than "MAME accesses" because the trace folds identical
consecutive accesses. The testbench replays every ATA data port access and
every write, but only the first and last read of a folded run of identical
reads, which have no side effects (status polling, mostly).

Directed tests (sim/gnet/tb_directed.cpp) cover the behaviour no game
reaches. 62 checks pass with flash preset 1 and with preset 2.

## 1. Method

1. **Trace:** `tools/mame/glue_trace.lua` (run by
   `tools/mame/glue_trace_run.sh`) logs every main-CPU access to:
   - 0x1f000000-0x1f7fffff, the flash bank window;
   - 0x1fa30000;
   - 0x1fb00000-0x1fb0ffff, the RF5C296 and task file;
   - 0x1fb40000, 0x1fb60000 and 0x1fb70000.

   Each access is logged with direction, address, data, byte mask and
   emulated time, without loss. Identical consecutive accesses are folded
   into one record with a count and the last time, and the stream goes
   through zstd. One 300 s cold run is 145 to 333 MB per game. The existing
   M0 oracle logs could not drive a replay: they fold program data and ATA
   data reads into sums.
2. **Runs:** cold (empty NVRAM: U30 starts from flash.u30 of the BIOS zip,
   the other four chips erased), 300 s, coin at 180 s, all six sets. MAME's
   NVRAM at exit and its diff CHD (card writes) are kept beside each trace
   in `sim/gnet/work/` (gitignored).
3. **Replay:** `sim/gnet/tb_gnet_fc.cpp` (Verilator 5.050):
   - It drives each access into `gnet_fc` at cycle = t x CLK_HZ and
     compares every read under its byte mask.
   - At the end it compares the flash storage with MAME's NVRAM, and the
     card image with MAME's (the diff CHD extracted with
     `chdman extractraw -ip`).
   - Storage behind both memory ports has a 2-cycle latency.
4. **Clock:** I verify at 67.7376 MHz (the PSX core's clk2x). At 33.8688 MHz
   the glue needs about 10 cycles per access, and during the sub-BIOS's
   flash loops the BIOS issues one every 0.28 to 0.3 us. The replay then
   fell behind MAME by up to 191,750 cycles (5.7 ms at 33.8688 MHz), which
   shifted the 1 s erase timers. At 67.7376 MHz the worst lag in all six
   runs is 13 cycles. All timers are parameters derived from CLK_HZ, so the
   logic is the same at either clock (integration note in 5).

## 2. Blocks

### 2.1 Control registers and MB3773 watchdog (`gnet_ctrl.sv`)

- **Registers:**
  - control at 0x1fb40000: 8-bit, reset 0x10. Bit 5 is the watchdog CK,
    bit 4 holds the Zoom in reset, bit 2 selects the flash bank.
  - control2 at 0x1fb60000: 16-bit, write only.
  - control3 at 0x1fa30000: 8-bit, read back.
  - 0x1fb70000 reads 0x0002 (MAME, R15).
  - Unmapped bytes read 0, as MAME does (control reads with a 16-bit mask
    return 0x00c8 in the trace).
- **Watchdog:** a falling edge on CK restarts it. Timeout is a parameter,
  default MAME's 5 s, because the FC PCB capacitor is unknown (R17).
- **Outputs:**
  - zoom_reset (control bit 4);
  - a zoom_release pulse when bit 4 falls (MAME puts U27 and the wave chips
    into read array mode at that point);
  - bank_sel;
  - wd_reset.
- **Verification:** replay (all six); directed tests for readback,
  0x1fb70000 and the 5 s expiry.
- **Traces:** no watchdog reset happens in any trace.

### 2.2 Intel flash command machine (`gnet_flash.sv`)

- **Structure:** one engine shared by the five chips (U30, U27, U56, U55,
  U29), with per-chip mode, busy flag and timer.
- **Commands:**
  - FFh/F0h read array; 90h read identifier; 70h read status.
  - 50h clear status (enters read status, as MAME).
  - 40h/10h word program; 20h then D0h block erase.
  - 60h lock setup (the next write is consumed).
- **Identifier:**
  - TE28F160: B0h/D0h (28F160S3 290608-005 Table 12, p24).
  - E28F400B: 89h/4471h.
  - Word 2 = 0, word 3 = 0, other addresses 0.
- **Status:** 80h ready, 00h busy.
- **Erase blocks:**
  - TE28F160: 64 KB.
  - E28F400B, bottom boot: 16 KB, 8 KB, 8 KB, 96 KB, then 128 KB blocks.
  - The erase engine writes FFFFh over the block in the background during
    the busy time.
- **Timing:**

  | Preset | TE28F160 program | TE28F160 erase | E28F400B program | E28F400B erase |
  |---|---|---|---|---|
  | 1 (MAME) | 0 | 1.0 s | 0 | 0.3 s boot/parameter, 0.6 s main |
  | 2 (datasheet) | 20.0 us | 0.56 s | 0 | 0.3 s / 0.6 s |

  Preset 2 uses the 28F160S3 typical values at 2.7 V VPP (290608-005 p50).
  The 28F400B5 datasheet in the library gives maxima only (100 us, 7 s,
  14 s), so U27 keeps MAME's values in both presets.
- **Timing rule:** a program or erase counts from the cycle its confirming
  write is accepted. A status read at or after write time + T sees ready.
  That is exactly MAME's behaviour: in the raycris trace the first poll at
  confirm + 1.000000000 s already reads 80h.
- **Memory port:** one word-wide port: chip, word address, request held
  until ack.

### 2.3 RF5C296 register file (`gnet_rf5c296.sv`)

- **Access:** ExCA index at 3E0h, data at 3E1h. The 16-bit lane at 3E0h
  carries both bytes.
- **Register file:** 64 x 8 for socket A, written as the datasheet says,
  defaults 0.
- **Reads, per the RF5C296/RF5C396L datasheet:**
  - 00h = 83h (p27).
  - 3Ah = 32h (p47).
  - 01h Interface Status (p27): GPI 0, power active from 02h bit 4, IREQ#
    level 1, WP 0, card detect 11, BVD 11.
  - Other registers read back the written value.
- **Card reset:** 03h bit 6 = 0 holds the card in reset (p38).
- **Window check:** the two windows decode at the fixed G-NET addresses. A
  debug output flags programmed windows that differ from that mapping.
- **Seen in the traces:**
  - The BIOS never reads an ExCA register.
  - It writes a 20-write setup sequence at 0.125 s. The game writes a
    similar 23-write sequence at about 155 s (after the copy), with an
    extra card reset.
  - It touches attribute memory only between 06h = 21h (memory window 0
    enabled) and 06h = 60h (window disabled again). That fits a real
    controller, where accesses outside an enabled window would not reach
    the card.

### 2.4 ATA card, Taito Type 1 (`gnet_ata.sv`)

- **Attribute memory (word offsets):**
  - CIS bytes at 000h-0FFh.
  - Configuration option, configuration and status, pin replacement at
    100h-102h (reset 0, 0, 002Eh).
  - Lock status at 201h.
  - Writes to 07h are ignored.
  - Unlock writes at 280h-288h: key bytes for positions 0-4, zero for 5-8,
    a mismatch relocks (MAME).
  - Everything else reads FFFFh.
- **Task file and access width:**
  - Command block at offsets 0-7, control block at 8-15; above 15 reads
    FFFFh.
  - Each access's width sets the data transfer width, as MAME's
    m_8bit_data_transfers hack does. The BIOS reads the IDENTIFY block one
    byte at a time and sectors 16 bits at a time.
- **Commands:**
  - 20h READ SECTORS, 30h WRITE SECTORS, ECh IDENTIFY DEVICE (the IDNT block
    verbatim).
  - Anything else gives ERR and ABRT.
  - While locked: ERR, error 00h, DRDY clear.
  - DRDY is set lazily on register reads once the card is unlocked.
  - While BSY, every command block read except data returns status.
  - A non-data register write during DRQ aborts the command.
- **Addressing:** LBA, with CHS translation as a parameter.
- **SRST:** handled as MAME.
- **Timing (parameters, MAME's values):**
  - Reset: detect 2 ms then diagnostic 2 ms (signature and error 01h after
    it).
  - IDENTIFY: 10 us busy.
  - First sector: 0 (MAME's CF seek time). Between sectors: 400 ns.
  - Each written sector: 100 us busy.
  - IDENTIFY's 10 us BSY is visible in the trace (status D0h for 10.2 us,
    then 58h) and the replay matches it.
- **Storage:** word port into the card image. A read fills the 512-byte
  sector buffer in the background; data port reads wait for their word, so
  DRQ timing stays MAME's.
- **Dirty map:** a written sector goes to storage during its busy time and
  sets its 4 KB hunk in a 10,000-hunk dirty map. The map has a read port and
  a clear input for the save path.
- **Per-game data:** IDNT, CIS and KEY load through a byte port, from the
  files `tools/extract_card.sh` writes.

### 2.5 Top (`gnet_fc.sv`)

- **Decode:** the main-CPU offsets of docs/hardware_inventory.md 4. cpu_hit
  is provided for the memorymux integration.
- **Flash bank window:** bank = control bit 2 | JP1 << 1, mapped as MAME's
  flashbank_map.
  - Bank 0: U30, card attribute memory, U27.
  - Banks 1 and 3: U56, U55, U29.
  - Bank 2: EPROM (not modelled, reads 0), U27 mirror, U30.
- **Lane splitting:** 32-bit accesses become 16-bit lane operations, low
  lane first, with byte enables. That is how MAME presents 16-bit devices
  on the 32-bit bus.

## 3. Differences from MAME 0.288

| # | Behaviour | RTL | MAME | Basis (evidence rank) | Visible in the six traces |
|---|---|---|---|---|---|
| 1 | ExCA register reads | 00h = 83h, 3Ah = 32h, 01h from slot state, others read back | 00h for every register | RF5C296 datasheet p27, p47 (3) | No: never read |
| 2 | Card reset | Held while 03h bit 6 = 0; the 4 ms reset sequence starts on release | Card reset at each write with bit 6 = 0 | Datasheet p38 (3) | No: no status read falls in the shifted windows (0.135 s and 155.06 to 155.08 s) |
| 3 | Word program | Stored word = old AND new | Overwrites | 28F160S3 and 28F400B5 datasheets (3) | No: the BIOS programs erased words only; final contents identical |
| 4 | Completion of program or erase | Status returns to 80h whatever the read mode | Only in read status mode (otherwise 00h until the next 50h) | Datasheets: the WSM completes the operation (3) | No: the BIOS always polls in read status mode |
| 5 | Status bit IDX | Always 0 | Index pulse code in ide_hdd calculate_status | CF 1.4 status register ("always set to 0") (3) | No: MAME's pulse never fires in any trace, so both read 0 |
| 6 | ATA commands other than 20h, 30h, ECh | ABRT | Implemented (90h, EFh, E7h, READ/WRITE MULTIPLE, DMA, and more) | ATA: unsupported commands abort; the games use three (oracle, all six) | No |
| 7 | EPROM in bank 2 (JP1 sets) | Reads 0 | MB2011 or flasher EPROM image | Not needed for the six priority sets (JP1 = 0) | No |
| 8 | Data port read before its word arrives | Waits (ack delayed) | Data present at once | Implementation choice: keeps MAME's DRQ timing | No (the replay waits); matters for the CPU timing at integration |

Behaviours kept from MAME without better evidence:
- the Taito lock and relock (R5);
- U27 and the wave chips put into read array mode when the Zoom is
  released;
- the 0x1fb70000 value (R15);
- the 5 s watchdog (R17);
- ATA busy times (R6);
- clear status entering read status mode (the datasheets do not say which
  read mode follows 50h).

## 4. ALM estimate per block

These are paper estimates; I have not run Quartus. Each figure is flip-flop
count plus logic. One ALM holds two 6-input LUTs and up to four registers.

| Block | ALMs (estimate) | M10K | Main cost |
|---|---|---|---|
| gnet_ctrl | 60 to 90 | 0 | 32-bit watchdog counter, three registers |
| gnet_flash | 350 to 500 | 0 | five 32-bit busy timers with decrement (about 200), sequencer, erase engine, block geometry, identifier mux |
| gnet_rf5c296 | 200 to 320 | 0 | 64 x 8 registers in flip-flops with reset and a 64:1 read mux; 40 to 80 if moved to an MLAB (needs a power-on clear instead of reset) |
| gnet_ata | 450 to 700 | 5 | task file, busy counter, sector engine, LBA/CHS arithmetic; RAMs: sector buffer 512 B, IDNT 512 B, CIS 256 B, dirty map 16 Kbit (2) |
| gnet_fc | 120 to 180 | 0 | lane sequencer (latched 32-bit request), decode |
| **Total** | **1,180 to 1,790** | **5** | |

The F0 budget (docs/f0_budget.md 4.1) has 1,660 to 2,920 ALMs for the G-NET
glue including the loader (200 to 400) and the memory bridges, which are
not built yet. Cheap savings if needed:
- RF5C296 registers in an MLAB;
- 26-bit flash timers (1 s fits);
- a 24-bit watchdog counter with a prescaler.

### 4.1 Synthesis (2026-10-05)

Quartus 17.0.2 Analysis & Synthesis of `gnet_fc` alone (project
GNET_GLUE_SYN, defaults CLK_HZ 33868800 and FLASH_PRESET 1, 5CSEBA6U23I7),
main at 4a35ce6 plus later commits; reports in
`builds/20261005_1041_gluesyn/` (gitignored). 0 errors, 15 warnings.
Synthesis reports ALUTs and registers, not ALMs (an ALM holds two ALUTs and
up to four registers). Stand-alone fit with virtual pins (GNET_GLUE_FIT,
`builds/20261005_1054_gluefit/`): **1,346 ALMs**, 1,583 registers, 7 RAM
blocks, 1 DSP. The timing result does not count: VIRTUAL_PIN ON -to * also
made the clock a virtual pin (the OFF assignment on clk is listed as
ignored), the same issue found in GNET_CDC_FIT. That is inside the paper
estimate of 1,180 to 1,790 ALMs; RAM is 7 blocks against the estimated 5
(see below).

| Entity | Combinational ALUTs | Registers | Block memory bits | DSP |
|---|---|---|---|---|
| gnet_fc (own logic) | 130 | 196 | 0 | 0 |
| u_ctrl (gnet_ctrl) | 80 | 59 | 0 | 0 |
| u_flash (gnet_flash) | 540 | 317 | 0 | 0 |
| u_exca (gnet_rf5c296) | 308 | 537 | 0 | 0 |
| u_ata (gnet_ata) | 840 | 474 | 26,624 | 1 |
| **Total** | **1,898** | **1,583** | **26,624** | **1** |

RAM inference (Analysis & Synthesis RAM Summary): all six RAMs became
altsyncram blocks (type AUTO, so M10K or MLAB is decided by the fitter):
sector buffer as buf_lo and buf_hi (256 x 8 each), IDENTIFY as idnt_lo and
idnt_hi (256 x 8 each), CIS (256 x 8) and the dirty map (16,384 x 1). As
M10K that is 7 blocks (one per 256 x 8 RAM, two for the dirty map), not 5:
the 16-bit sector buffer and IDENTIFY were split into byte lanes. Warning
276020 on buf_hi, buf_lo, idnt_hi and idnt_lo: pass-through logic added to
keep read-during-write behaviour (a few registers and muxes each; removable
if the design never reads and writes the same address in one cycle).

Other findings:
- u_ata uses one DSP block (Independent 27 x 27, one unsigned multiplier),
  probably the CHS to LBA arithmetic.
- u_exca keeps the 64 x 8 register file in flip-flops (537 registers); the
  MLAB option in the table above would save most of them.
- Warning 10776, gnet_flash.sv:119: variable b in the static function
  erase_block may infer a latch (needs-review).
- Warnings 10036: assigned but never read: feature (gnet_ata.sv:159),
  control2 (gnet_ctrl.sv:52), o_we (gnet_flash.sv:100), f and l
  (gnet_flash.sv:209), t (gnet_flash.sv:270).
- Warning 15610: cpu_addr[1:0] drive nothing (gnet_fc.sv:45), expected for
  a 32-bit bus with byte enables.

## 5. Open questions and integration notes

1. **CPU stalls at integration.** At clk1x (33.8688 MHz) the glue takes
   about 10 cycles per access, slower than the BIOS's access rate in its
   flash loops. On hardware the CPU then waits on the bus, so boot timing
   depends on how memorymux stalls the CPU and on the SDRAM/DDR3 latency
   behind the two memory ports. Running the glue on clk2x halves this. The
   flash and card storage ports are the next step (SDRAM for U30/U27, DDR3
   for the waves and the card), with read ports for the MN10200 (U27) and
   the ZSG-2 (waves) beside the CPU path.
2. **R6:** real card BSY/DRQ timing. All times are parameters; PCB load-time
   footage could set them.
3. **R5:** does a wrong key relock a real Type 1 card (MAME assumes yes)?
4. **Attribute register 07h:** MAME notes that Type 1 cards are written
   0Eh then 0Ah there. The meaning is unknown; ignored, as MAME does.
5. **R3:** flash persistence across power cycles. tools/build_flash.py can
   build the images offline (docs/m0_findings.md 3a), so the loader can
   start warm.
6. **R25:** the dirty map is ready for a save path (at most 32 sectors in
   300 s here). The format and the HPS side are decided at M4.
7. **R15 and R17:** 0x1fb70000 and the watchdog period stay MAME's.
8. **Bootleg sets (JP1):** need the EPROM in bank 2.

## 6. Files

- RTL (GPL-2.0-or-later headers): `rtl/gnet/gnet_fc.sv`, `gnet_ctrl.sv`,
  `gnet_flash.sv`, `gnet_rf5c296.sv`, `gnet_ata.sv`.
- Trace tools:
  - `tools/mame/glue_trace.lua` and `tools/mame/glue_trace_run.sh`
    (MAME 0.288, nice -n 15, refuses to start with 3 MAME processes
    running);
  - `tools/gnet/glue_trace.py` (summary and dump).
- Testbenches:
  - `sim/gnet/tb_gnet_fc.cpp`, `build.sh` and `run_replay.sh` (replay);
  - `sim/gnet/tb_directed.cpp` and `build_directed.sh` (directed).
- Work data (gitignored, game-derived): `sim/gnet/work/`, holding the
  traces, MAME NVRAM and diff CHDs, flash.u30 and the replay logs.
