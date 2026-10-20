# Issue #12: faster loading through the MRA DDR3 load path

Branch i12-ddr3load (from de4d29b, the alpha 3 release source, revision
GNET_Z1FULLR). New revision GNET_Z1FULLD = GNET_Z1FULLR + macro
GNET_DDR3_LOAD, pc_build target z1fulld. GNET_Z1FULLR is unchanged.

## 1. Summary

- Card image (index 5, 41 MB, 23 s today): `address="0x34000000"` on the
  MRA's `<rom>` makes Main_MiSTer copy it straight into DDR3 where
  zn2_cardmem already keeps it. No core change; the same MRA works with the
  alpha 3 RBF and with the new one (section 7, run R2).
- Flash area (index 3, 10 MB, 6.5 s today): `address="0x31000000"` puts it
  in DDR3 at the flash mirror's place; the new RBF copies it to SDRAM
  0x1000000 after the download (gnet_ddr3_flcopy), holding the core in
  reset and Main waiting. Needs the new RBF.
- Expected load for Ray Crisis: about 7 s with the new RBF and `--ddr3 all` MRAs, about 12 s with `--ddr3 card` MRAs on any RBF, against 35 s today; both include a memcpy time I could not measure (section 8).

## 2. Current flow (alpha 3, PSX.sv line numbers at f9d8e2d)

1. hps_io (PSX.sv:640, WIDE=1, clk_sys = clk_1x 33.8688 MHz) turns each
   16-bit word Main sends into ioctl_wr with ioctl_addr (stepping by 2) and
   ioctl_dout (low byte = even file byte). Main waits for the core's
   acknowledge of every word; sys_top freezes the acknowledge while
   ioctl_wait is high (sys/sys_top.v:258-263).
2. Index decode on clk_1x: bios_download (index 0) PSX.sv:734-740; G-NET
   indices 2 (keys), 3 (flash), 4 (meta), 5 (card), 6 (EEPROM), 254 (DIPs)
   PSX.sv:751-758; index 7 (configuration byte, GNET_SHELL) PSX.sv:886-893.
3. Every G-NET download holds the core in reset: gnet_download
   (PSX.sv:800) is part of reset_or (PSX.sv:308), registered into reset
   (PSX.sv:1563-1567). Between two downloads reset is released for Main's
   gap (fullsys_sim.md 5.3).
4. Keys, meta, EEPROM: words into psx_top's loader (zn_ld_*, PSX.sv:862-874),
   ioctl_wait = zn_ld_busy (PSX.sv:1237).
5. Card (index 5): each word to zn_card_dl_* (PSX.sv:875-879) into
   zn2_cardmem (rtl/gnet/zn2_cardmem.vhd, instance rtl/psx_top.vhd:3343
   with CPU_CLK_SPLIT), which collects four words into one 64-bit write at
   DDR3 BASE + card offset (zn2_cardmem.vhd:33, BASE = 0x4000000, line 142)
   through psx_top's own DDR3 arbiter. ioctl_wait = zn_card_wait
   (PSX.sv:882, 1235). Byte order: word k in bits 16k+15:16k of the qword,
   so DDR3 byte (BASE + i) = card byte i.
6. Flash (index 3): two words make one 32-bit ramdownload write to SDRAM
   0x1000000 + offset (PSX.sv:1215-1232); with GNET_CPU50 it crosses to
   clk_cpu in cdc_handshake ch3_cdc (PSX.sv:2299) and goes through
   zn2_ch3_arb port a (PSX.sv:2317) to sdram.sv channel 3; ioctl_wait is
   held until sdramCh3_done. gnet_ddr3_mirror (PSX.sv:2772) copies every
   channel 3 write in 0x1000000-0x19FFFFF to DDR3 byte 0x31000000 + offset
   for the Taito Zoom (docs/ddr3_arbiter.md 4).
7. The core's DDR3 window: psx_mister.vhd:375-376 drives DDRAM_ADDR =
   0011 & ddr3_ADDR(27:3), a qword address, so core byte b is HPS physical
   0x30000000 + b. sys_top passes DDRAM_ADDR unchanged to sysmem's
   f2h_sdram1 port (sys/sys_top.v:616, 1692, 1824; sys/sysmem.sv:74, 204).
   The card at core byte 0x4000000 is therefore physical 0x34000000 and the
   flash mirror at core byte 0x1000000 is physical 0x31000000 (the memory
   note's 0x34000000 is confirmed).
8. Other DDR3 users, none inside 0x31000000-0x319FFFFF or
   0x34000000-0x37FFFFFF: screen_rotate at 0x24000000, 3 x 8 MB
   (sys/arcade_video.v:204, 210); VRAM, SPU RAM and memory cards at core
   bytes below 0x400000 (psx_top.vhd:1130-1170, 2336); the savestate
   header the reset sequencer reads at core byte 0xE000000 (dword address
   58720256, psx_top.vhd:2447, savestates.vhd:558).

Hardware measurement (Lee, 2026-10-16, Ray Crisis, alpha 3): about 35 s:
RBF 0.3 s, zip reads about 4 s, flash 10.5 MB (10,485,760 bytes) in 6.5 s,
card 41 MB (40,960,000 bytes) in 23 s, so 1.6 to 1.8 MB/s through the word
handshake.

## 3. What Main_MiSTer does with address= (source: MiSTer-devel/Main_MiSTer master, 63186a3, fetched 2026-10-20)

- support/arcade/mra_loader.cpp:541-543 reads `address` on a `<rom>`
  (strtoul, base 0, so "0x34000000" works). The ROM is assembled in RAM as
  usual (rom_data, lines 229-282: parts, zip reads, interleave, md5).
- rom_finish (lines 327-371): `user_io_set_index(romindex)`, then
  `user_io_set_download(1, address ? len : 0)`, then for an address ROM
  `shmem_put(fpga_mem(address), len, data)` instead of the word loop, then
  `user_io_set_download(0)`.
- shmem.h:12: `fpga_mem(x) = 0x20000000 | (x & 0x1FFFFFFF)`, so
  0x34000000 stays 0x34000000 (physical). shmem.cpp: shmem_put mmaps
  /dev/mem (O_RDWR | O_SYNC) at that address and memcpys.
- user_io.cpp:2154-2165: user_io_set_download sends FIO_FILE_TX (0x53),
  0xFF, and when the length is nonzero two more words, len[15:0] and
  len[31:16].
- What the core sees (sys/hps_io.sv:668-684): FIO_FILE_INDEX sets
  ioctl_index = 5 (or 3); FIO_FILE_TX word 0 sets ioctl_addr = 0, words 1
  and 2 set ioctl_addr[15:0] and [26:16] = the length; ioctl_download rises
  when the command ends (fio_block, fp_enable low), so at its rising edge
  ioctl_addr = length (27 bits, up to 128 MB). No ioctl_wr at all. Main
  then memcpys the data into DDR3 while ioctl_download is high, and
  FIO_FILE_TX 0 drops ioctl_download (ioctl_addr becomes length + 2). The
  data is complete in DDR3 when ioctl_download falls; at the rising edge
  nothing is there yet. A normal download starts with ioctl_addr = 0 and
  its first word does not step the address (skip_add), so ioctl_addr != 0
  at the start identifies a DDR3 load.
- The length word exists since Main_MiSTer 1844709a (2021-03-01, "mra_loader:
  send DDR3 ROM size to core"); an older Main sends 0 and the core would
  take the load for an empty normal download.
- Every Main command word waits for the core's acknowledge, which sys_top
  holds while ioctl_wait is high (sys_top.v:258-263; Main's fpga_spi has no
  timeout, fpga_io.cpp:688-705). Holding ioctl_wait therefore stops Main
  before its next ROM.

Not verified: the memcpy rate of Main's shmem_put into the uncached
/dev/mem mapping (section 8 uses a range; Lee's hardware test gives it).

## 4. Design

### 4.1 MRA layout

| index | today | new (card only, any RBF) | new (all, GNET_DDR3_LOAD RBF) |
|---|---|---|---|
| 0 BIOS | words | words | words |
| 2 keys | words | words | words |
| 3 flash | words to SDRAM | words to SDRAM | `address="0x31000000"` |
| 4 meta | words | words | words |
| 5 card | words to DDR3 | `address="0x34000000"` | `address="0x34000000"` |
| 7 config, 254 DIPs, nvram 6 | words | words | words |

The zips from both converters are unchanged: the address is an MRA
attribute only.

### 4.2 Card (index 5)

Main's memcpy puts card byte i at physical 0x34000000 + i, which is where
zn2_cardmem reads it (section 2, items 5 and 7), in the same byte order.
card_download still holds reset for the whole download (no ioctl_wr, so
zn_card_wait stays 0 and ioctl_wait 0). zn2_cardmem's one-line read buffer
is cleared by reset (zn2_cardmem.vhd:128-132; its reset is psx_top's reset_intern_p, psx_top.vhd:3347), so no line of an earlier
card survives. The card's IDENTIFY, CIS, key and type come from the meta
(index 4) as before. Nothing in the core changes, so the alpha 3 RBF works
with these MRAs.

### 4.3 Flash (index 3) with GNET_DDR3_LOAD

PSX.sv:763-801 (loader section):
- At the rise of flash_download, `fl_ddr3 <= (ioctl_addr != 0)` and
  `flc_len <= ioctl_addr`.
- At its fall with fl_ddr3, `flc_start` pulses; gnet_ddr3_flcopy takes it
  and raises busy at the same edge that clears fl_ddr3, so
  `flc_hold = (fl_ddr3 & ~flash_download) | flc_busy` has no gap and goes
  into gnet_download: reset stays held from the start of the download to
  the last SDRAM write (savestates.vhd as reset sequencer is unchanged and
  runs after the release, as before).
- PSX.sv:1203-1215: while flc_hold, ioctl_wait = 1 (Main waits before its
  next ROM) and the copier's writes take the ramdownload registers;
  gnet_flash_dl = flash_download | flc_busy (PSX.sv:1149-1151) so they go
  through the same ch3_cdc, zn2_ch3_arb port a and sdram.sv channel 3 as a
  normal flash download. The flash mirror sees them and writes the same
  bytes back into DDR3 (harmless, and the Zoom copy stays right).
- rtl/gnet/gnet_ddr3_flcopy.sv: clk2x side reads 64-qword bursts from
  qword 0x6200000 (byte 0x31000000) on the DDR3 arbiter's glue port
  through gnet_ddr3_gmux (from branch ddr3-card, mirror first) into a
  256-qword M10K buffer, only while the buffer has room; clk1x side turns
  each qword into two 32-bit writes (low half at the lower address),
  waiting for sdramCh3_done after each. Length clamped to 0xA00000, rounded
  up to 32-bit words. clk1x and clk2x are one PLL with aligned edges
  (PSX.sv:147-149), so the two sides read each other's counters directly
  (no synchroniser); both only grow during a copy, so a late sample is safe.
- Old MRAs on the new RBF: ioctl_addr = 0 at the start, fl_ddr3 = 0, every
  added path idle; the gmux passes the mirror through combinationally.

### 4.4 Rejected alternatives

- Serving the CPU's flash reads from DDR3 (no copy): changes the main CPU's
  flash timing and the ch3 path; far more risk than a one-off copy.
- Letting the copy overlap Main's card memcpy (no ioctl_wait during the
  copy): saves at most the shorter of the two, and needs every other
  download path guarded against the copier owning ramdownload. Not done.

## 5. Implementation

Commits on i12-ddr3load (local, not pushed):

| commit | content |
|---|---|
| f9d8e2d | RTL: PSX.sv (GNET_DDR3_LOAD sections), rtl/gnet/gnet_ddr3_flcopy.sv (new), rtl/gnet/gnet_ddr3_gmux.sv (from ddr3-card 126e964, unchanged), GNET_Z1FULLD.qsf, tools/pc_build.sh target z1fulld |
| 61d5128 | sim/fullsys and docs/fullsys_sim.md from fullsys-sim b41842d, unchanged |
| 9ead848 | copier bench and mutants, full-system download-path harness, MRA generator patch |
| (this doc) | docs/i12_ddr3_load.md, compare_ab.py reporting |

- GNET_Z1FULLR: PSX.sv preprocessed with the revision's 26 macros
  (verilator -E -P) is identical to de4d29b's; its qsf and file list are
  unchanged. So the release revision builds the same netlist.
- GNET_Z1FULLD.qsf = GNET_Z1FULLR.qsf + GNET_DDR3_LOAD + gnet_ddr3_gmux.sv +
  gnet_ddr3_flcopy.sv; seed 8 and PLLOUTPUTCOUNTER_X0_Y5_N1 kept.
- tools/lint_psx.py: no warnings or errors in PSX.sv for GNET_Z1FULLR and
  GNET_Z1FULLD. verilator --lint-only -Wall on gnet_ddr3_flcopy.sv: clean
  apart from PROCASSINIT (power-up values on registers, as gnet_ddr3_mirror).
- Not fitted. Expected size: one 256 x 64 buffer (2 M10K), about 150 to 250
  ALMs of counters and muxes (estimate, not measured). Timing risk: the
  clk1x/clk2x counter compares (21 bits) are same-PLL paths with half a
  clk1x period (14.76 ns).

## 6. Simulation method

### 6.1 Copier bench (sim/ddr3arb, `run.sh flcopy`)

tb_flcopy_top.sv wires gnet_ddr3_flcopy, gnet_ddr3_gmux, gnet_ddr3_mirror
and gnet_ddr3_arb as PSX.sv does; tb_flcopy.cpp models the DDRAM port
(pipelined reads, latency base + jitter, gaps between beats, random BUSY
plus a 200-cycle BUSY run every 5,000 cycles), Main's memcpy, the channel 3
handshake (done after 3 to 20 clk1x, 2% after 200 to 600) feeding the
mirror on a 50 MHz clk_cpu, and random core reads. Checks per copy: write
count, order, address and data of every write, nothing outside a copy,
DDR3 flash area intact at the end, no FIFO overflow, every core read right.

### 6.2 Full system (sim/fullsys, `zn2fulldl.sh`)

The fullsys-sim harness (b41842d) brought onto this branch and extended:
- fs_psxdl_full.svh: PSX.sv's download path of the release tree copied
  verbatim (index decode, loader, reset_or with the watchdog hold, the
  ramdownload block, ch3_cdc as fs_ch3_cdc.vhd around the real
  cdc_handshake, zn2_ch3_arb, mirror, gmux, copier, DDR3 arbiter), with
  the GNET_DDR3_LOAD sections under the same macro. gen_top.py includes it
  for FS_DL=1 with FS_DDR3ARB=1.
- One GHDL netlist of psx_top from f9d8e2d with GNET_Z1FULLR's generics
  (zn2fulldl.sh), two Verilator builds: obj_dir (no macro = GNET_Z1FULLR)
  and obj_ddr3 (+define+GNET_DDR3_LOAD=1 = GNET_Z1FULLD), both
  profile-guided (pgo_dl.sh).
- tb_fullsys.cpp: a `-dl` line `<index>@<address>` is a DDR3 load: the HPS
  model starts the download with ioctl_addr = length, copies the bytes into
  the DDR3 model at (address - 0x30000000) at -hps_mbs MB/s (100 here, a
  model value) while the download is open, then ends it. Every command of
  the HPS model now waits while ioctl_wait is high, as sys_top makes Main
  wait. After the downloads it checks SDRAM and DDR3 against the files
  (and for a DDR3 flash load both Main's DDR3 copy and the core's SDRAM
  copy). progress.log records the copier's busy edges and any mirror or
  arbiter owner FIFO overflow.
- compare_ab.py compares two runs from their final reset release on.
- Settings: -cpu_mhz 50, -dqm 1 (SDRAM read DQM modelled), pseudo-random
  power-up memory, -pre_ms 100. Ray Crisis (raycris) files: BIOS
  m534002c-60.ic353, keys from coh3002t.zip; raycris.flash from
  build_flash (gnet-games tools/build_flash.py, identical to the file the
  earlier fullsys runs used); raycris.meta built as gnet_tester_zips.py
  does (type 01); card sim/cards/raycris.img (md5 2e4c9dd8...).

## 7. Simulation results

### 7.1 Copier bench (sim/ddr3arb, 2026-10-20)

| run (seed, BUSY %, latency base + jitter, lengths) | result |
|---|---|
| 1, 20%, 14+8, default lengths (196,608, 74,565, 8, 5, 3, 262,145 bytes) | pass: 133,336 writes, 424,433 core beats checked |
| 2, 0%, 4+0 | pass |
| 3, 40%, 40+40 | pass |
| 4, 60%, 20+30 | pass |
| 6, 25%, 14+8, one copy of 0xA00000 bytes | pass: 2,621,440 writes, 8,295,457 core beats |

Negative controls (`flcopy_mutants.py`, seed 3, 40%, 40+40), each a copy of
the copier with one fault; all four caught:

| mutant | caught by |
|---|---|
| no room check (buffer may be overrun) | 4 copies with wrong data |
| high half written from the low half | wrong data in every copy |
| a command dropped when the arbiter is busy | copies time out (3,072 of 133,336 writes) |
| odd tail: always a second write | write counts one too many |

Skipping the ACK state passes, as it must (with aligned clocks it is
redundant; it is kept as a margin), so it is not listed as a mutant.

### 7.2 Full system, Ray Crisis (sim/fullsys/work/i12, 2026-10-20)

Netlist from f9d8e2d (zn2fulldl.sh), profile-guided builds, -cpu_mhz 50,
-dqm 1, -pre_ms 100, -hps_mbs 100. R1 and R3 use -hps_w 1 -hps_r 1 to
shorten the word downloads (emulated time only; the handshake is the same).

| run | build | MRA (dl list) | downloads done / final reset release | after the downloads |
|---|---|---|---|---|
| R1 | GNET_Z1FULLR | today's, all words (dl_old) | 9.639 s / 9.637 s | BIOS, flash, card identical to the files |
| R2 | GNET_Z1FULLR | card at 0x34000000 (dl_card) | 3.118 s / 3.116 s | identical |
| R3 | GNET_Z1FULLD | today's (dl_old) | run to 3 s only | every download start and end and every reset edge at the same time as R1, to the nanosecond (20 events) |
| R4 | GNET_Z1FULLD | flash at 0x31000000, card at 0x34000000 (dl_full) | 1.792 s / 1.790 s | BIOS, flash in SDRAM, flash in DDR3 (Main's copy after the mirror's write-back), card: all identical |
| R5 | GNET_Z1FULLD | first boot: flash.u30 + 8 MB FFh at 0x31000000, card (dl_cold) | 1.792 s | all identical; copier 1.0486 s, as R4 |

In R4 the copier ran from 330.785 ms (end of the flash download) to
1379.361 ms; ioctl_wait was high and reset held over exactly that span
(progress.log: "ioctl_wait 1 (no download open)" at 330.785 ms, "psx reset
0" and "ioctl_wait 0" at 1379.361 ms), and Main's next ROM (index 4) only
started after it. No mirror or arbiter owner FIFO overflow in any run.

Boot after the final reset release (compare_ab.py, 6.863 s after release,
the length of R1's boot; outputs in work/i12/compare_R1.txt):

| | R1 against R2 | R1 against R4 |
|---|---|---|
| card window accesses (RF5C296 / ATA, status reads left out, runs folded) | 253 = 253, identical | 253 = 253, identical |
| ATA data port read runs (count, first, last, sum) | 549 = 549, identical | 549 = 549, identical |
| flash bank window accesses with the data read | identical as far as the shorter goes (255,257 of 255,539) | identical as far as the shorter goes (254,569 of 255,257) |
| whole pictures (239/240 lines), folded | 49 of 50 equal in place | 49 of 50 equal in place |
| last picture | 40b1c743 at 6.818 s in both (R2 6.811 s) | 40b1c743, R4 6.837 s |

R2 against R4 over 7.884 s: card 253, ATA 549 identical, flash identical
as a prefix, 52 of 53 pictures equal, last picture equal.

The differences, all timing:
- Picture #5 is the last 256-wide frame before the switch to 320 x 240,
  nearly black (luma 0.15 to 0.25 of 255) and different in each run: the
  mode change falls at a different point of the frame.
- The full ZN-2 bus stream first differs at 0x1FA10300 (the CAT702 / SIO0
  select the BIOS bit-bangs), where one run writes 84h and another 88h in
  a retry loop. Without that register, R2 and R4 match as a prefix to the
  end; against R1 they match for the first 119,240 to 119,965 accesses
  (3.4 s), then interleave input reads and flash reads differently by a
  few accesses (the order of an interrupt against the main loop); the
  flash stream on its own stays identical.
- The run's offset relative to the video phase differs (the final release
  falls at a different point of the frame), so the first picture after
  release and the GPU stream's timing differ from the start.

Gate: Ray Crisis boots to the same point after the DDR3 paths (R2, R4) as
after today's path (R1): the same card accesses and sector data, the same
flash contents as the CPU reads them, the same sequence of pictures to the
same picture 6.8 s after release. PASS.

## 8. Expected load time

| stage | today (Lee, measured) | `--ddr3 card`, any RBF | `--ddr3 all`, GNET_Z1FULLD |
|---|---|---|---|
| RBF | 0.3 s | 0.3 s | 0.3 s |
| zip reads and assembly in RAM (Main) | about 4 s | about 4 s | about 4 s |
| flash 10,485,760 bytes | 6.5 s (word handshake) | 6.5 s | Main memcpy t3 + copier 1.05 s (sim) |
| card 40,960,000 bytes | 23 s (word handshake) | Main memcpy t5 | Main memcpy t5 |
| the rest (BIOS 512 KB, keys, meta, config, Main) | about 1.2 s (35 s minus the above) | same | same |
| total | about 35 s | 12.0 s + t5 | 6.55 s + t3 + t5 |

- Copier time: 1.0486 s in R4 and R5 (busy from 330.785 to 1379.361 ms):
  2,621,440 writes, 400 ns (13.5 clk1x) each, the round trip of one
  channel 3 write through ch3_cdc (clk_1x to clk_cpu and back), zn2_ch3_arb
  and sdram.sv. Independent of the data (R5 with the first boot flash took
  the same time to the nanosecond).
- t3 and t5 are Main's memcpy of 10.5 MB and 41 MB into the uncached
  /dev/mem mapping. Not measured and not sourced. At 100 MB/s they would be
  0.10 s and 0.41 s (totals about 7.1 s and 12.4 s); at 30 MB/s 0.35 s and
  1.37 s (about 8.3 s and 13.4 s). Lee's hardware test (section 11) gives
  the real figure.
- The zip reads (about 4 s) become the largest part; they are Main's and
  unchanged by this work.
- The first boot MRAs still need the BIOS's 2.5 minute flash copy after
  loading.

## 9. MRA and converter changes, compatibility

- gnet_tester_zips.py (gnet-games) and the web converter
  (gnet-release/web/converter) write only the zips (.img, .meta, .flash).
  Nothing in the zips changes, so neither needs a change and zips made by
  any version work with every MRA.
- The MRAs come from tools/gnet/make_release_mras.py in gnet-release.
  docs/patches/i12_make_release_mras_ddr3.patch (applies to gnet-release
  4f21d12) adds `--ddr3 none|card|all` (default card): `card` puts
  `address="0x34000000"` on index 5, `all` also `address="0x31000000"` on
  index 3 (quick start and first boot MRAs). `--ddr3 none` writes the same
  58 files as the unpatched script (checked); all 58 `all` MRAs parse as
  XML.
- Compatibility:

  | MRA | alpha 1 to 3 RBF | GNET_DDR3_LOAD RBF |
  |---|---|---|
  | today's (no address) | works | works (run R3) |
  | `--ddr3 card` | works (run R2) | works |
  | `--ddr3 all` | flash not loaded: does not start | works (run R4) |

  So `--ddr3 card` MRAs can ship now, with any RBF. `--ddr3 all` MRAs must
  ship together with the new RBF, and the release notes must say that
  these MRAs need it (an older RBF shows a flash error).
- Both need Main_MiSTer from 2021-03-01 or later (section 3).
- Found on the way, not changed: gnet-release's make_release_mras.py lags
  its committed MRAs for Chaos Heat (Dash button, configuration 10h),
  Mahjong Oh and Usagi (8 files differ). Regenerating releases/ from the
  script as it is would undo those; either bring the script up to date
  first or add the address attributes to the committed MRAs directly.
- The gnet-games copy of make_release_mras.py is the older six-set version
  (releases/gnet, --boot); it is not what the release uses and I left it.

## 10. Build request (for the main session)

- Branch i12-ddr3load, commit f9d8e2d (the RTL; any later commit on the branch has the same RTL), revision GNET_Z1FULLD,
  `tools/pc_build.sh z1fulld` (own build dir gn_z1fulld). Seed 8 as
  GNET_Z1FULLR; if timing misses, it is a seed question first (the macro
  adds a small block). The pc_build HDMI counter check applies.

## 11. Hardware test steps for Lee

Use test names, as the deploy rules say (for example
`_Arcade/cores/TaitoGNET_i12_<date>.rbf` and MRAs with `<rbf>TaitoGNET_i12</rbf>`),
and keep the alpha 3 RBF in place.

1. MRAs for Ray Crisis (V2.03O), made with the patched generator into a
   scratch folder (`--ddr3 none`, `card`, `all`), `<rbf>` pointed at the
   test RBF; a second copy of the `card` MRA pointed at the alpha 3 RBF.
2. Time each load, three times, from pressing A on the MRA to the first
   G-NET picture (a phone video at 60 fps is enough), and note the order of
   the OSD progress messages. Expected: none about 35 s, card about 12 s,
   all about 7 s. The difference between "card" and "none" gives t5, the
   memcpy of 41 MB; please write it down (section 8 needs it).
3. With each MRA: the game reaches attract, Zoom music plays (the flash
   mirror is right), coin and start, play to the first boss. Test mode
   (DIP Test Mode On) shows no flash or ROM error.
4. Debug overlay DR row (docs/hw_debug_overlay.md 2): mirror and owner
   overflow flags stay 0 after an `all` load.
5. Load Ray Crisis (`all`), then Shikigami no Shiro (`all`) without a power
   cycle, then Ray Crisis with the old MRA: each must boot (no stale card
   line or flash from the previous game).
6. First boot MRA with `--ddr3 all` (Ray Crisis first boot): the BIOS does
   its 2.5 minute copy and the game starts.
7. Kollon (V2.04JC), CompactFlash card, quick start `all`: boots (the v2
   sub-BIOS in U30 comes through the copier).
8. The `card` MRA on the alpha 3 RBF: boots and plays as step 3.
9. HDMI video_info check as for every build (pll_hdmi counter X0_Y5_N1).

## 12. Open questions

1. Main's memcpy rate into DDR3 (t3, t5): only Lee's test can give it.
2. GNET_Z1FULLD has not been fitted. The addition is small, but alpha 3
   closed timing on 1 seed of several; a seed sweep may be needed.
3. Rollout: `--ddr3 card` MRAs need no RBF change and save about 23 s;
   they could ship before the new RBF. Lee to decide.
4. The copier spends 1.05 s on 2.6 M single 32-bit channel 3 writes, each a
   full clk_1x to clk_cpu handshake. A copier on clk_cpu writing channel 3
   directly could be several times faster; not worth the risk unless the
   hardware total disappoints.
5. Main_MiSTer older than 2021-03-01 sends no length; with `all` MRAs the
   flash would stay unloaded. Worth a line in the release notes.
6. The R3 run (new RBF, old MRA) covers the download timeline only (to
   3 s, identical to R1 to the nanosecond); the boot after it rests on the
   argument that every GNET_DDR3_LOAD path is idle with an old MRA.
7. gnet-release's make_release_mras.py is behind its committed MRAs for
   Chaos Heat, Mahjong Oh and Usagi (section 9).
