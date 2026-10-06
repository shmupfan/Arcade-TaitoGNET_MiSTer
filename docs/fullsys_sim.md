# Full-system simulation in Verilator

Status: WORKING 2026-10-05 (branch fullsys-sim). The whole core (PSX_MiSTer
VHDL with the LEAN trims, the real sdram.sv, and the ZN-2 board with the
G-NET glue from branch zn2-layer) runs in Verilator, about 8 to 14 times
faster than the NVC system simulation. From power-on with the Ray Crisis
card, the G-NET BIOS shows the Taito G-NET logo, reads the card, shows the
game's "Loading now." screen and starts the first-boot copy into the flash
chips. Within 8 s of emulated time, every card access and every flash
write I compared equals MAME 0.288's.

## 1. Result

Runs: T1 = BIOS, flash.u30 and CAT702 keys, no card (6 s emulated);
T2 = plus the Ray Crisis card image and metadata, cold flashes (8 s).
MAME references: `oracle_run.sh coh3002t 6 --cold` with
ORACLE_GPU_STREAM=1, and `oracle_run.sh raycris 8 --cold` with
ORACLE_FLASH_RAW=1 (both under `sim/fullsys/work/`).

| Check | Result |
|---|---|
| Boot sequence T1 | Reset sequencer (90 ms), BIOS from ROM, sub-BIOS decrypted from U30 to RAM (0x8001xxxx, then 0x803Bxxxx), Taito G-NET logo, then "SYSTEM ERROR" (no card). MAME shows the same screens (logo, then SYSTEM ERROR by frame 180) |
| GPU stream T1 against MAME (`compare_gpu.py`, CPU and DMA words) | GP1: 1,857 of 1,857 words equal. GP0 aligned by command: 13,310 of the core's 13,312 commands equal MAME's first 13,311. Two differences, both root-caused (section 5, D1 and D2) |
| Frames | The logo frame equals MAME's snapshot apart from a one-pixel horizontal offset (with a 1 px shift only the wrapped edge column differs: 176 pixels). The "Loading now." screen differs only in the phase of the blinking text and one pixel |
| Boot sequence T2 | Logo, card setup at 0.97 s (RF5C296, CIS, unlock, IDENTIFY, 34 READ SECTORS), logo fade at 3.6 s (frame 210), RAYCRISIS "Loading now." from 5.4 s (frame 315; MAME frame 180), U30 programming from 6.18 s (MAME 4.99 s), block erase of 0x1F080000 at 7.72 s (MAME 6.29 s) |
| Card bus T2 (`compare_card.py`) | All 337 RF5C296 / ATA accesses other than data and status reads equal MAME's in order; all 2,512 runs of data port reads (522,375 reads) equal MAME's run by run (count, first and last value, sum) |
| Flash writes T2 (`compare_flash.py`) | All 657,074 byte writes to the flash bank window (command sequences, card attribute writes, U30 erase and program) equal MAME's raw flash log in order |
| Watchdog | No watchdog reset in any run; the BIOS writes the control register with bit 5 alternating (C8h/E8h, D8h/F8h) |
| Same RTL in NVC (zn2-layer bench, run_t1long) | With the NVC bench's clocks and reset time (`-h_ps 2461 -vid_half_ps 9312 -reset_us 10`, GTE_NARROW_MUL=1): 170 of the first 171 GPU writes identical to the microsecond, one 1 us later, all in the same order with the same data. With the default bench timing all 498 writes of the first 1.5 s keep order and data. The GHDL to Verilog conversion behaves like the VHDL |

How far the BIOS gets: into the first-boot flash copy. MAME needs about
133 to 155 emulated seconds for the copy (M0 notes); at the speeds in
section 4 that is 5 to 9 hours of simulation, which I did not run.

Timing against MAME: the ROM-resident BIOS runs about 4 times slower than
in MAME (IDENTIFY at 1.03 s against 0.238 s), the RAM-resident code close
to MAME's rate (U30 programming 6.18 to 7.72 s in the core against 4.99 to
6.29 s in MAME, 1.18 times). This is the known ROM wait-state difference
(PSX_MiSTer's BIOS ROM timing against MAME's none; zn2_layer_design.md 18.3,
R1).

## 2. Method

1. **VHDL to Verilog** (`sim/fullsys/convert.sh`): GHDL synthesis of
   psx_top straight to Verilog (`ghdl --synth --out=verilog`), generics
   HAS_CD=0, HAS_PADS=0, HAS_SAVESTATES=0, HAS_CHEATS=0, HAS_MDEC=0,
   VRAM_Y_BITS=10, GTE_NARROW_MUL=0 (GNET_B1.qsf and the zn2 NVC bench use
   1; `GTE_NARROW_MUL=1` selects it). Files as in rtl/psx.qip. Upstream RTL
   is never edited: simulation-only copies go to `work/<tag>/patched`
   (`patch_vhdl.py`). The result is one netlist (7.7 MB, 75 modules) that
   keeps the hierarchy and the signal names (lower case).
2. **Netlist post-process** (`fix_netlist.py`, W8 in section 3).
3. **RAM primitives** (`fs_mem.vhd`, `fs_mem.v`): the PSX_MiSTer RAM
   entities (dpram, dpram_dif, RamMLAB, SyncRam, SyncRamDual,
   SyncRamDualNotPow2, SyncRamDualByteEnable) are replaced by shims with the
   same entity and ports that instantiate an unbound component. GHDL writes
   an unbound component as a parameterised Verilog instance, and
   `fs_mem.v` implements it as a plain Verilog memory with the
   read-during-write behaviour of the original. The FIFOs stay VHDL.
4. **Top** (`gen_top.py`, generated from the netlist's port list): psx_top
   wired to a Verilator copy of rtl/sdram.sv as PSX.sv does (ch1 reads
   with DMA and cache fill, ch2 writes, DMA FIFO); every other psx_top port
   goes to the top under its own name. With the ZN-2 board the gnet_fc
   flash port is sdram ch3 (PSX.sv GNET_ZN2). Debug probes (`probes.txt`)
   read internal nets by hierarchical name.
5. **ZN-2 board** (`zn2.sh`): the committed rtl/ of branch zn2-layer is
   exported read only into `work/zn2/src` (COMMIT records the hash; these
   results: ad57ab1) and built with ZN2_BOARD = 1. gnet_fc and its blocks
   are SystemVerilog and go to Verilator directly (zn2_board instantiates
   gnet_fc as a component, so GHDL leaves it unbound).
6. **Harness** (`tb_fullsys.cpp`):
   - SDRAM chip model in C++ (32 MB, CAS 2, burst 2, commands on the
     falling controller clock, as the R1 and zn2 benches): BIOS
     m534002c-60.ic353 at byte 0x800000 (PSX.sv BIOS slot 0), flash.u30 at
     0x1000000, the other flash chips erased (FFh).
   - DDR3 model (Avalon, reads after 15 clk2x, as the zn2 bench): VRAM,
     SPU RAM, the card image at 64 MB.
   - ZN-2 loader as the zn2 bench: CAT702 keys (tt10, tt16) and the card
     metadata (IDNT, CIS, key) through zn_ld_*, then card_present and
     key_valid, then reset.
   - Clocks: clk1x 33.8688 MHz, clk2x and clk3x with rising edges aligned,
     clkvid 53.693175 MHz. No logic in the core uses a falling edge, so
     falling clocks are folded into the next evaluation: 6 evaluations per
     clk1x period plus about 1.6 for clkvid.
   - Outputs: `progress.log` (every 100 us: frame, CPU PC, counters,
     probes), `gpu.log` (CPU writes to GP0/GP1, DMA words to the GPU, CPU
     reads of GPUREAD), `zn.log` (every ZN-2 expansion bus access, as the
     zn2 bench), `frames/fNNNNN.ppm` from the video output (hblank,
     vblank, video_ce), `vram_<ms>.bin` (2 MB) at the first vsync after
     each interval.
7. **Comparison tools**: `compare_gpu.py` (GP0 and GP1 word streams and an
   alignment by command against gpu_stream.bin; tools/gpu_stream.py splits
   the commands), `compare_card.py` (RF5C296 / ATA accesses and data port
   runs against ata.log), `compare_flash.py` (flash window writes against
   flash.log).

## 3. Workarounds

Every construct that failed, and what the simulation copy does instead.
None changes behaviour.

| # | Where | Failure | Workaround |
|---|---|---|---|
| T1 | OSS CAD Suite 2026-10-05, libexec/ghdl | dyld on this macOS refuses the binary: "duplicate LC_RPATH '@executable_path/../lib/'" | Removed the duplicate rpaths (`install_name_tool -delete_rpath`) and re-signed ad hoc (`codesign -f -s -`), local tool copy only |
| T2 | Yosys ghdl plugin (`yosys -m ghdl`) | Asserts (ADA.ASSERTIONS.ASSERTION_ERROR, netlists.adb:978) even on a one-register design | Standalone `ghdl --synth --out=verilog`; Yosys is not needed |
| W1 | gpu_crosshair, justifier_sensor, gpu_overlay | "bounds or direction of actual don't match": a natural actual (to_integer of an unsigned) on an `integer range 0 to 1023` input | Those y inputs declared natural (values stay below 1024) |
| W2 | export.vhd | "signals in packages are not supported": package pexport declares a signal nothing reads | Signal dropped |
| W3 | gpu_poly | "unhandled dyn operation: IIR_PREDEFINED_INTEGER_ABSOLUTE" (abs on integer) | fs_util.fs_iabs |
| W4 | sim/system/src/mem/dpram.vhd and the other RAMs | "multiple assignments for ram": two processes write one shared variable (true dual port) | RAM shims to Verilog models (2.3) |
| W5 | gpu_line, gpu_poly, gpu | TYPES.INTERNAL_ERROR (netlists-utils.adb:166) on the inout divider record ports (the GPU unit drives start/dividend/divisor, gpu.vhd the results) | Each divN port split into divN (out) and divN_i (in); gpu.vhd wires the outputs to the OR mux and the divider results to the inputs |
| W6 | gpu_poly | TYPES.INTERNAL_ERROR (netlists-utils.adb:166) on `(signed13 & x"00000000") + x"100000000" - 2048` (3 places) | The 36-bit literal (+2^32) written as `(to_signed(1, 13) & x"00000000")`, the same 45-bit value |
| W7 | sdram.sv | inout SDRAM_DQ and the altddio_out clock buffer | `sdram_copy.py`: DQ split into DQ (out) and DQ_IN (in), SDRAM_CLK = ~clk, 'Z fills 0 (only used with SDRAM_EN = 0) |
| W8 | GHDL Verilog output | A VHDL signal with an initial value and a concurrent assignment becomes `always @* x = y;` plus `initial x = init;`. With a constant y the always block never runs in Verilog, so x keeps its initial value. Seen as a hang: psx_top's ss_ram_BURSTCNT stayed 0 (savestates drives x"01"), so the reset sequencer's DDR3 read never returned and the CPU never left reset | `fix_netlist.py`: every `always @*` becomes `always_comb` (runs at time 0, as VHDL runs every concurrent assignment once at the start) and the initial of these signals is dropped (896 signals) |
| W9 | gnet/zn2_io (zn2-layer) | "actual must be a static name" and "cannot extract same variable part for dynamic slice": `p_wdata(8 * lane_byte(p_be) + 7 downto 8 * lane_byte(p_be))` as a port actual | Lane selected by a case function fs_lane |
| W10 | gnet/zn2_cardmem (zn2-layer) | TYPES.INTERNAL_ERROR (elab-vhdl_expr.adb:1114) on `be(2 * c_lane + 1 downto 2 * c_lane) := "11"` (variable) | The two bits set one by one |

W5, W6 and W10 are GHDL bugs (internal errors) with one-statement
triggers; worth a report upstream.

## 4. Speed

Measured on the Mac with every run under `nice -n 15`, load average 13 to
19 from other work, one or two simulations at a time. "Frames per minute"
are emulated video frames per wall-clock minute (emulated time per minute
divided by the 16.715 ms frame).

| Simulation | Emulated time per wall second | Frames per minute |
|---|---|---|
| NVC system simulation (zn2-layer bench, zn2_layer_design.md 18.3), one run | 0.6 ms | 2.2 |
| Verilator, plain build (-O2), T2 8 s, two runs at a time | 4.73 ms | 17.0 |
| Verilator, profile-guided build (`pgo.sh`), T2 8 s, one run | 8.31 ms | 29.8 |

The profile-guided run of T2 produced the same zn.log and the same 31
frames, byte for byte, as the plain build, and the same GPU stream. Per
evaluation the model takes 0.47 us profile-guided, 0.82 us plain (2.06
billion evaluations for 8 s). Measured variants on the same 300 ms window
(A/B/A, one other simulation running):

| Variant | Wall time | Note |
|---|---|---|
| plain (-O2) | 60.5 to 62.9 s | baseline |
| -O3 -mcpu=native | 63.2 s | no gain |
| profile-guided (training: 1 s of T1) | 36.4 to 36.6 s | 1.66 times faster, identical gpu.log |
| Verilator --threads 2 | 3.0 times slower (400 ms window) | thread hand-off per evaluation; single thread kept |

A sample of a running simulation shows the time spread over the clocked
logic of the whole design (no single hot block), so the remaining gains
would come from evaluating less often, not from a faster block.

## 5. Divergences from MAME

| # | Divergence | Root cause | Status |
|---|---|---|---|
| D1 | GP0: the core sent one extra E1001000 (draw mode) at 0.83 s that MAME does not | The BIOS runs the nocash GPU version check (as ps1-tests gpu/version-detect): GP1(10h) index 4, then index 7, read GPUREAD, and if the answer is not 2, write E1001000 and read GPUSTAT. MAME's CXD8654Q (psxgpu.cpp, gputype 2) answers 2; PSX_MiSTer's gpu.vhd ignored index 7 and left GPUREAD stale | RESOLVED on main cfdf23f (gpu.vhd answers 2 when VRAM_Y_BITS = 10). Checked in 5.1 |
| D2 | GP0: E4000000 (drawing area bottom right) where MAME sends E40FFFFF | After GP1(00h) reset, gpu.vhd clears the drawing area to 0; MAME sets the bottom right to 1023,1023 (psxgpu.cpp gpu_reset, for every GPU type). The BIOS reads it back with GP1(10h) index 4 (core: 00000000, in gpu.log as GR0) and writes it out | SETTLED: the core follows the PS1 documentation. psx-spx (nocash), "GP1(00h) - Reset GPU": "GP0(E1h..E6h) ;rendering attributes (0)" (https://psx-spx.consoledev.net/ps1/gpu/display-control-commands-gp1/). MAME's value has no stated source. No visible effect: the BIOS sets the drawing area again (E4111C00 at 0.84 s) before it draws. Open only if a ZN-2 hardware test shows the CXD8654Q differs from the PS1 GPU |
| D3 | Captured frames one pixel to the right of MAME's snapshots | Not the core and not the harness. The core's captured frame equals VRAM exactly from the display address of GP1(05h) (x = 0): 0 mismatches at offset 0 against vram_1250.bin, 1,241 at offset 1. MAME's snapshot equals VRAM from x = 1 (0 mismatches at offset +1): MAME drops VRAM column 0 and shows black in its last column | SETTLED: the core shows the display area as GP1(05h) defines it; the offset is MAME's. On a MiSTer the visible window is set by PSX.sv's own blanking counters (hb_start/hb_end per hResMode; the core's hblank is used only with status[62], the 480p hack or widescreen), so the on-screen crop is a separate question |
| D4 | Shikigami warm boot: SIO0 never sends the byte after the CAT702 select; the watchdog resets the board (the hardware loop) | zn_sio0.vhd answered lhu 0x1F80104A (JOY_CTRL) with JOY_MODE, so the game's read-modify-write cleared TXEN | RESOLVED on zn2-layer f8cf759. Checked in 5.4 |

### 5.1 Rebuild with D1 fixed (2026-10-05)

`TAG=zn2b OVERLAY="cfdf23f:rtl/gpu.vhd" sim/fullsys/zn2.sh`: zn2-layer 6d8e332
(includes 4ae0210, de7217d and 935647c; FLASH_PRESET default still 1 = MAME)
with main's gpu.vhd from cfdf23f on top, profile-guided.

| Check | Result |
|---|---|
| T1 (no card, 6 s) against MAME | GP1 1,857 of 1,857 equal; GP0 13,310 of the core's 13,311 commands equal MAME's first 13,311. Only D2 is left |
| T1 against the previous build | GPU stream identical apart from the removed E1 (52,797 words), times within 0 to 3 us; the 11 frames both runs saved are byte-identical |
| T2 (Ray Crisis, 8 s) against MAME | Card bus 337 of 337, ATA data runs 2,512 of 2,512 (522,375 reads), flash writes 657,074 of 657,074 equal |
| T2 against the previous build | The same 4,696,145 expansion bus accesses with the same data (times shifted by a few us), GPU stream identical apart from the removed E1, all 31 frames byte-identical |
| Speed | 8.1 to 8.2 ms emulated per second with two runs at a time |

### 5.2 MiSTer ERROR B930 (first hardware test of GNET_Z1)

On my MiSTer, GNET_Z1 (zn2-layer 4ae0210) ended every G-NET boot on
"CanNotFindProgramRom / ERROR B930". No simulation had shown it, because
the SDRAM chip models (this harness, the R1 and zn2 benches) ignored DQM
on reads.

- **Cause** (found by the zn2-layer work, confirmed here): zn2_board.vhd
  reads the flash storage port with byte enables "1100" (odd 16-bit word) or
  "0011". sdram.sv puts ~be[1:0] on A12:A11 at a ch3 READ (line 476); on
  MiSTer these are DQMH:DQML (line 88). With the SDRAM's read DQM latency
  of 2, A12:A11 = 11 at READ and READ+1 masks both words of the burst, so
  an odd word reads whatever floats on the bus. ch1 (CPU) reads force
  A12:A11 = 00 (line 442) and are not affected; writes use DQM with latency
  0 and are correct.
- **Model:** the SDRAM chip model applies read DQM with latency 2 (`-dqm 1`;
  masked bytes read `-dqm_float`, default 5A5Ah).
- **Reproduced:** in a Ray Crisis cold boot the BIOS reads the U30 licence
  header at 0x1F000004 at 647,647 us. Bytes 4-5 read "Li" (694Ch) as before;
  bytes 6-7 read 5A5Ah instead of "ce" (6563h). The BIOS retries, then
  writes POST code 0Fh. The video output shows "CanNotFindProgramRom /
  ERROR B930" by frame 120, the screen seen on the MiSTer.
- **Fix** (`FS_EXP_FLREAD_BE=1`, for zn2-layer): read with all byte
  enables: `if (fmem_we = '0') then fl_be <= "1111"; elsif ...`. With DQM
  modelled, all 130,338 ZN-2 bus accesses through 1.13 s are the same in
  content as the earlier run that matches MAME. To 7 s, the fixed boot
  reaches the RAYCRISIS "Loading now." screen and the U30 erase and
  program, as before. Against MAME, the card bus (337 of 337), the ATA data
  runs (2,512 of 2,512) and the flash writes (329,384 of 329,384) all
  match. All 27 frames both runs saved are byte-identical to the run
  without DQM.

### 5.3 MiSTer download path

`FS_DL=1` builds the top with PSX.sv's download path copied verbatim from
zn2-layer 4ae0210 (fs_psxdl.svh):

- the ioctl index decode;
- the G-NET loader (keys, metadata, EEPROM, card words to zn2_cardmem with
  ioctl_wait);
- reset_or with the watchdog hold;
- ramdownload to SDRAM ch3;
- the ch3 multiplexer.

The harness models sys_top's HPS strobe/ack handshake (io_ack frozen while
io_wait) and hps_io's fio_block. It sends the files of a `-dl` list in MRA
order. Before the first download, the core runs on pseudo-random SDRAM and
DDR3 contents for `-pre_ms`, as after a core load on a MiSTer.

After the downloads, the harness compares the BIOS, flash and card areas
with the source files.

Result for the cold Shikigami MRA on the 4ae0210 tree, before the B930 fix:
- **Timing:** downloads ran from 0.5 s to 10.93 s emulated, about 13 clk1x
  per word with `-hps_w 2 -hps_r 2`.
- **Memory:** after the downloads, the BIOS at SDRAM 0x800000 (524,288
  bytes), the flash area at SDRAM 0x1000000 (10,485,760 bytes) and the card
  at DDR3 0x4000000 (40,960,000 bytes) all equal the source files.
- **Reset:** the core is held in reset during every G-NET download and
  released between them.

So the download path, ioctl_wait and the zn2_cardmem line writes are
correct, and B930 comes from the flash read DQM alone (5.2).

### 5.4 Shikigami warm-boot stall (zn_sio0 halfword reads)

With the B930 fix, Shikigami on the MiSTer showed the logo, then the
loader, then a watchdog reset loop. The warm boot here (zn2-layer 13b6e1d
with cfdf23f's gpu.vhd, `-dqm 1`) did the same.

- **Not the SPU.** The game starts a large SPU DMA4 at 10.16 s (MADR
  80185A3C, BCR 1D640010). It completes at about 10.389 s (DICR
  acknowledged).
- **Where it stops.** At 10.3896 s the game selects the CAT702 at
  1FA10300, as MAME does at 7.6929 s. It then sets up SIO0, writes one TX
  byte and polls JOY_STAT at PC 800607B0 forever (io.log, `-iolog_from`).
- **MAME at the same point** (sio0_trace.lua): the game writes ctrl 0050,
  baud 0002, mode 000E, ctrl 0000 and ctrl 1013. It then reads JOY_CTRL with
  lhu at 0x1F80104A (1003), writes it back with bit 4 set (1013) and sends
  the byte. JOY_STAT goes 80, 85, 05, 07 and the game reads RX.
- **Cause.** In the core the same lhu returned 000E, the mode, so the game
  wrote ctrl 001E. TXEN (bit 0) is clear, the byte never starts, and
  TX ready and TX empty stay 0. memorymux applies only rotate16 to pad reads,
  a byte shift within the halfword, so the device must answer halfword reads
  at 2, 6, A and E in bits 15:0. joypad.vhd and sio.vhd do this. zn_sio0.vhd
  decoded only bus_addr(3 downto 2) and answered 0xA with ctrl & mode.
- **Fix** (`FS_EXP_SIO0RD=1` here, zn2-layer f8cf759): decode
  bus_addr(3 downto 1). Offsets A and E return `x"0000" & ctrl` and
  `x"0000" & baud`; offsets 2 and 6 return 0 (the upper halves, as MAME
  reads them).
- **Result.** The fixed warm boot leaves the poll loop with no reset. To
  30 s it shows NOTICE (from frame 630), the Taito logo and "Alfa System
  presents" (frame about 1200; MAME 1080), the same sequence as MAME. No
  MB3773 request.
- **Watchdog margin.** Kicks are bit 5 falling edges in 1FB40000, about 30
  per second. The longest gap is 3.552 s (6.859 to 10.411 s); MAME's is
  2.441 s. Most of it is the Zoom reset sequence at 8006F794: a delay of
  425,000 iterations, clear 1FBE0000, release the Zoom, then a delay of
  2,500,000 iterations (no I/O; the VBlank IRQ runs but does not kick). The
  core takes about 39 clk1x per iteration, MAME about 26. With MAME's 5 s
  MB3773 period (a guess in mb3773.cpp) the core uses 71% of it.
- **Later boots.** The warm boot only sends flash commands (0x90 ID, 0xFF
  read array; no program or erase) and never touches the AT28C16, so a
  boot after a watchdog reset starts from the same state.

io.log samples the CPU bus at mem_request and mem_done, so a line can mix
two back-to-back accesses (here the mode write was logged as a read). The
MAME tap is the reference for the order of accesses.

### 5.5 GNET_Z1_CPU50: BIOS halt on POST bars (I-cache refill race)

The first 50 MHz build (gnet-cpu50 e775367, ZN-2 board in the CPU group,
CLK_FAST_RATIO = 2) stopped on three or four BIOS POST bars, on my
MiSTer and in this harness (`zn2cpu50.sh`, `-cpu_mhz 50`).

- **Where.** The BIOS ran the CAT702/znmcu sessions; their TX and RX bytes
  were identical to the 33.87 MHz run, session for session. Right after
  the last TT16 session, the RAM-resident check at 0x312C took an
  exception: Cause 0x24 (ExcCode 9, BREAK), EPC 0x316C. The vector at
  0x80000080 led to A(40h) SystemErrorUnresolvedException, a loop at
  BFC0B530. DCIC was 0.
- **Cause.** The CPU executed 0x0007000D (BREAK) at 0x316C, where RAM holds
  0x00E02021 (move a0, a3). The I-cache is direct mapped, 256 lines of 16
  bytes. 0x216C, in the same slot (index 0x16, word 3), holds 0x0007000D.
  After the miss on 0x3160, word 0 of the new line was correct but word 3
  was still the old line's. A taken branch reached 0x316C two instructions
  later, inside the refill window. At ratio 2, sdram.sv signalled the fill
  ready before its last word was written.
- **Fix** (gnet-cpu50 6cb9b78, sdram.sv): at CLK_FAST_RATIO = 2, ch1_ready
  for a cache fill rises with the write of the last refill word. Ratio 3
  is unchanged. With it, the warm boot reaches NOTICE (about 8.5 s; 10.5 s
  at 33.87 MHz) with no MB3773 pulse. The longest no-kick gap is 2.750 s,
  against 3.552 s at 33.87 MHz.
- **Tools.** `-pctrace_from/-pctrace_to`, `-ramdump_us`, `-iolog_all`,
  `-ps1_phase_ns`, plus the COP0 and pipeline probes in probes.txt
  (c0cause, c0epc, op0 to op2, pcold0, pcold1).

### 5.6 Ruled out for the 33.87 MHz hardware loop

GNET_Z1 (f8cf759) loops on hardware: logo, loader COMPLETE, reset, about
every 25 s. These sims do not reproduce it. All boot through to NOTICE
with no MB3773 pulse:
- 13b6e1d with the zn_sio0 fix, and pure f8cf759 (without cfdf23f), with
  `-wd_apply 1`;
- hardware-like DDR3 timing (`-ddr_lat 30 -ddr_jit 40 -ddr_gap 20
  -ddr_busy 20`).
The harness's card, flash and metadata inputs are byte-equal to the MRA
zip. The warm boot sends no flash program or erase commands and never
touches the AT28C16, so later boots match the first.

### 5.7 Tree checks (2026-10-06)

Warm boots with `-wd_apply 1`. The MB3773 is applied: on a pulse the
harness holds reset for 255 clk1x, as PSX.sv's zn_wd_hold does.

| Tree | Clock | Games | Result |
|---|---|---|---|
| zn2-layer 13b6e1d + cfdf23f + zn_sio0 fix (5 s MB3773) | 33.87 | all five | four pass; Night Raid loops: a 5.081 s no-kick gap in its Zoom-reset delay (6.411 to 11.492 s) against the 5 s watchdog |
| hw-debug-overlay a5a556e (z1, 8 s MB3773) | 33.87 | all five | pass, 0 to 30 s; GPU write counts equal the run above |
| gnet-cpu50 6cb9b78 | 50 | Shikigami | NOTICE about 8.5 s, longest gap 2.750 s |
| zoom-into-z1 d15f51d (`zn2zoom.sh`) | 50 | Shikigami | as 6cb9b78; the Zoom is released at 6.768 s; MN10200 dbg_flags 00; 1,872 host mailbox writes equal MAME's |
| gnet-full 3c993c0 (`zn2full.sh`) | 50 | Shikigami | NOTICE about 8 s; Zoom over the DDR3 arbiter; 1,880 mailbox writes equal MAME's |
| gnet-full 2c8476d | 50 | Ray Crisis | no divergence (a6); Zoom music sample-aligned with MAME at onset, RMS error 17 against 1,773 (about -40 dB) over 1.3 s |

The core lags MAME. Ray Crisis's prepare bar takes 20.7 s at 33.87 MHz,
16.9 s at 50 MHz and 12.3 s in MAME. A 1.48x clock gives only a 1.22x
faster bar, so the bar is memory or bus bound.

Ray Crisis's music command (1FBE0110 to 0124) comes 0.25 s later relative
to the picture than in MAME. That is host sequencing; the Zoom adds 21 ms.

## 6. How to run

Tools: Verilator 5.050 (Homebrew) and GHDL from the YosysHQ OSS CAD Suite
macOS arm64 build 2026-10-05 (T1 fix applied; `OSS_CAD` gives its
path).

```
sim/fullsys/zn2.sh                 # export zn2-layer (read only), convert, build: work/zn2/
TAG=zn2 sim/fullsys/pgo.sh         # optional: profile-guided rebuild, about 5 minutes
sim/fullsys/run.sh t1 1500         # BIOS, U30, keys, no card, 1.5 s emulated
sim/fullsys/run.sh t2 8000 raycris # with the Ray Crisis card (sim/cards/raycris.*)
python3 sim/fullsys/compare_gpu.py sim/fullsys/work/zn2/run_t1/gpu.log <MAME run>/gpu_stream.bin
python3 sim/fullsys/compare_card.py sim/fullsys/work/zn2/run_t2/zn.log <MAME run>/ata.log
python3 sim/fullsys/compare_flash.py sim/fullsys/work/zn2/run_t2/zn.log <MAME run>/flash.log
```

MAME references (one MAME at a time, at most three on the machine):
`ORACLE_GPU_STREAM=1 tools/mame/oracle_run.sh coh3002t 6 sim/fullsys/work/mame_coh3002t --cold`
and `ORACLE_FLASH_RAW=1 tools/mame/oracle_run.sh raycris 8 sim/fullsys/work/mame_raycris_raw --cold`
(the script reads roms/ of the checkout it runs from).

Other options: `TAG=main` builds plain PSX_MiSTer from this branch's rtl/
(`convert.sh`, then `build.sh`; without the ZN-2 board I only ran it to
200 ms, where the BIOS still runs from ROM); `TAG=zn2n1 GTE_NARROW_MUL=1 sim/fullsys/zn2.sh` for the B1
setting; harness flags `-h_ps`, `-vid_half_ps` and `-reset_us` set the
bench timing (the NVC bench: 2461, 9312, 10); `FS_EXP_GPUVER=2` with a
separate TAG builds the D1 experiment; `OVERLAY="<ref>:<path> ..."` takes files
from another commit on top of the zn2-layer export.

`TAG=zn2hw FS_DL=1 sim/fullsys/zn2.sh <ref>` builds the download-path
top; run it with `-dl <list>` (one line per MRA index: `<index> <file> ...`,
`fill:<count>:<hexbyte>`, `hex:<bytes>`), `-pre_ms`, `-hps_w`, `-hps_r`,
`-dl_gap_ms`, `-garbage 0|1`. `-dqm 1` turns on SDRAM read DQM in any build.

Checkpoints for long runs: build with `VFLAGS=--savable` (with pgo.sh too),
run with `-ckpt_ms N` (every N emulated ms: ckpt_<ms>.model and
ckpt_<ms>.harness, about 300 MB, the last two kept), continue with
`-restore <out>/ckpt_<ms>` and the same other arguments. A run restored at
150 ms gave the same gpu.log, progress.log and frames as the uninterrupted
run. A checkpoint belongs to the build that wrote it: any RTL change
renumbers GHDL's nets and changes the saved state layout, so after a change
the run starts again from 0.

Game data (BIOS, keys, card files, frames, VRAM dumps, logs, MAME runs)
stays in `sim/fullsys/work/` (gitignored). Every build and run goes under
`nice -n 15`; builds use 4 compile jobs.
