# Taito G-NET hardware inventory

Sources: MAME 0.288 `src/mame/sony/taitogn.cpp` (PCB layouts and notes in
the header comment, machine config, memory map), `src/mame/sony/zn.cpp`,
`src/mame/sony/taito_zm.cpp`, device files named per row; XelaNotPu's
repositories read through the GitHub API on 2026-10-04. "MAME notes" means
the board description in the taitogn.cpp header (part numbers and
crystals read from real boards; the author of each measurement is not
named). Anything not confirmed is marked needs-review.

FPGA implementation method key: **MAME port** = written to match MAME's
behaviour (the author's own words where quoted); **emulator-derived** =
written from emulator knowledge and documentation and tested with test
programs; **die-level** = from decapped silicon. No die-level model was
found for any G-NET chip.

## 1. ZN-2 main board (COH-3000, sticker COH-3002T)

| Chip / block | Part (MAME notes) | Clock | Function | MAME file | Existing FPGA implementation |
|---|---|---|---|---|---|
| CPU | Sony CXD8661R (R3000A-compatible MIPS with GTE, DMA, IRQ, timers, SIO, MDEC on the PS1-style CPU die; integration of MDEC on this die is inferred from the PS1 and needs-review) | 100 MHz crystal. MAME: `CXD8661R(..., XTAL(100'000'000))`, executes clock/4 = 25 M cycles/s (ZN-1 CXD8530CQ: 67.7376 MHz / 4 = 16.93 M). Real internal clock not documented (R1) | Main CPU, geometry (GTE), FMV decode (MDEC) | `devices/cpu/psx/psx.cpp`, `gte.cpp`, `dma.cpp`, `irq.cpp`, `rcnt.cpp`, `sio.cpp`, `mdec.cpp` | PSX_MiSTer `cpu.vhd`, `gte.vhd`, `dma.vhd`, `irq.vhd`, `timer.vhd`, `sio.vhd`, `mdec.vhd` (Robert Peip / FPGAzumSpass, https://github.com/MiSTer-devel/PSX_MiSTer, GPL-2.0, emulator-derived; CPU die reverse engineering in progress at emu-russia/psxcpu, CC0, unfinished). ZN-2 variant: XelaNotPu/ZN2-Capcom_MiSTer (`cpu.vhd` modified: data cache with 128-bit line fill, size stated as 128 KB in the README and 16 KB in a ZN2.sv comment, needs-review; KSEG1 fix), CPU still at the ZN-1 rate with memory waits removed by default ("Turbo" pacing) to approximate the ZN-2 budget (ZN2.sv comment #329). Complete for the PS1 feature set; ZN-2 rate not implemented |
| GPU | Sony CXD8654Q with 2 x KM4132G271BQ-8 SGRAM (128K x 32 x 2 banks each, 2 MB VRAM) | 53.693175 MHz (MAME) | 2D/3D rasteriser, display | `devices/video/psx.cpp` (CXD8654Q = psxgpu type "SGRAM", 2 MB) | PSX_MiSTer `gpu*.vhd`; XelaNotPu ZN2-Capcom extends VRAM to 2 MB ("full PSX-type GPU with the ZN-2's 2 MB VRAM", README) and adds 480i field handling. Complete for the target per their README (Capcom titles boot and play) |
| SPU | Sony CXD2925Q with 814260-70 (256K x 16 DRAM, 512 KB sound RAM) | MAME: 67.7376 MHz / 2 (same as ZN-1), R24 | 24-voice ADPCM sound, reverb | `devices/sound/spu.cpp` | PSX_MiSTer `spu.vhd`, `spu_ram.vhd`, `spu_gauss.vhd`. Complete. ZN-2 has a MAME TODO about CPU against SPU clock (R2) |
| Main RAM | 2 x KM416V1204BT-L5 (1M x 16 EDO), two more positions unpopulated | | 4 MB (MAME default "4M"; boardconfig_r reports size) | `zn.cpp` zn_base, boardconfig_r | PSX_MiSTer has 2 MB; XelaNotPu ZN cores provide the ZN RAM size in SDRAM (exact size per core needs-review in source) |
| Boot ROM | COH3002T.353, M534002 4 Mbit mask ROM (MAME region `maincpu:rom`, `m534002c-60.ic353`) | | G-NET BIOS (English) | `taitogn.cpp` COH3002T_BIOS | XelaNotPu ZN cores load the per-manufacturer boot ROM at runtime from `coh*.zip`; G-NET BIOS not supported yet |
| Security | CAT702 labelled TT10 (main board) | SIO0 serial clock | Challenge/response latch on SIO0 | `devices/machine/cat702.cpp` (smf) | XelaNotPu `rtl/cat702.vhd` (ZN-1 and ZN-2 cores; key per game in the MRA). Complete for their supported boards. Method: re-implementation of MAME's algorithm (their README) |
| I/O MCU | NEC uPD78081G503, 5 MHz, 8 KB ROM NO_DUMP | 5 MHz | DIP switch S551, analog and trackball inputs, serial to SIO0 | `src/mame/sony/znmcu.cpp` (behavioural) | XelaNotPu `rtl/znmcu.vhd` (behavioural, as MAME). No die or ROM based model possible (R16) |
| EEPROM | Atmel AT28C16 (2K x 8) at 0x1faf0000 | | Settings, bookkeeping | `devices/machine/at28c16.cpp` | XelaNotPu ZN cores (NVRAM saved to SD, `zn1_io.vhd` and shell; exact module needs-review) |
| Glue CPLD | Altera EPM7064QC100 | | Address decode, unknown registers | none (behaviour implied by zn.cpp map) | none; implied by the ZN cores' `memorymux.vhd` |
| Video DAC | Motorola MC44200FT | | RGB out | none | MiSTer video output (not chip-level) |
| Audio DAC / amp | AKM AK4310VM DAC, LA4705 amp, S301 stereo/mono switch | | Line and speaker out | none | MiSTer audio (not chip-level) |
| Inputs | JAMMA plus CN503-506, CN651/652/654 | | Players 1-4, analog, trackball, memory card | `zn.cpp` maincpu_program_map 0x1fa00000-0x1fa20000 | XelaNotPu `zn1_io.vhd` |
| Video timing | | MAME notes: 59.8260 Hz vertical, 15.4333 kHz horizontal | | `devices/video/psx.cpp` | PSX_MiSTer `gpu_videoout*.vhd` |

## 2. FC PCB (K91X0721B M43X0337B): storage, card and Taito Zoom sound

| Chip / block | Part (MAME notes) | Clock | Function | MAME file | Existing FPGA implementation |
|---|---|---|---|---|---|
| Sound CPU | Panasonic MN1020012A (MN10200 family, QFP128). MAME notes: newer games have MN1020819DA (R9) | 12.5 MHz at OSCI pin 30 (25 MHz / 2); MAME executes clock/2 = 6.25 M cycles/s | Zoom sequencer: drives ZSG-2 and TMS57002, mailbox to main CPU | `devices/cpu/mn10200/mn10200.cpp`, `src/mame/sony/taito_zm.cpp` | XelaNotPu `rtl/mn10200.sv` in ZN1-TaitoFX1B_MiSTer (GPL-3.0-or-later). "Literal port of MAME src/devices/cpu/mn10200/mn10200.cpp, including MAME's 32-bit-wide (deliberately under-masked) D/A registers" (file header). Cycle count tracked in MAME units with a pacing accumulator (taito_zoom_top.sv). Runs Ray Storm, G-Darius, Fighters' Impact music |
| PCM synth | Zoom Corp ZSG-2 (QFP100, under the PCB) | 25 MHz pin 99; output 25 MHz / 768 = 32.552 kHz | 48-channel compressed-PCM wavetable with filter and four sends | `devices/sound/zsg2.cpp` (reverse-engineered register map and 2:1 sample format) | XelaNotPu `rtl/zsg2.sv`. "Implements MAME src/devices/sound/zsg2.cpp (0.277) behaviour", "bit-exact vs MAME" (taito_zoom_top.sv header). Sample ROM 4 MB in DDR3 for FX-1B; G-NET needs 6 MB from three flashes |
| Effects DSP | Texas Instruments TMS57002DPHA "DASP" (QFP80). MAME notes: newer games have a Zoom ZFX-2 instead, "functionally identical" (R9) | 12.5 MHz CLKIN pin 11; LRCK 32.5525 kHz; BCK 1.5625 MHz | Reverb and chorus on the ZSG-2 sends; final L/R out | `devices/cpu/tms57002/tms57002.cpp`, `tmsinstr.lst`, `tmsmake.py` | XelaNotPu `rtl/tms57002.sv` + `rtl/tms_delay_m10k.sv`. "Ground truth: MAME src/devices/cpu/tms57002/ ... and the raystorm/gdarius2/ftimpcta golden captures", "bit-exact vs MAME"; RESTRICT build option drops features no captured Taito microcode uses. Delay RAM 32768 x 16 in 64 M10K. Second independent RTL: ppriest/Arcade-KonamiGX_MiSTer `rtl/sound/gx_tms57002.sv` (GPL-3.0, 2026-09, written against MAME and checked against MAME host traffic; README declares AI-assisted development) |
| DSP delay RAM | Sanyo LC321664 (64K x 16 fast page mode DRAM with byte write per the Sanyo EN4795C sheet, not EDO; under the PCB) | | TMS57002 external data memory | `taito_zm.cpp` tms57002_map (0x00000-0x3ffff RAM, 256 KB) | XelaNotPu: 64 KB in M10K (R8) |
| Sound work RAM | Sharp LH52B256 (32K x 8 SRAM) | | MN10200 RAM | `taito_zm.cpp` map 0x400000-0x41ffff (128 KB) | XelaNotPu: 64 KB in M10K, sticky flag if a title goes beyond it (R7) |
| Mailbox | Mitsubishi M66220FP (256 x 8) | | Main CPU to MN10200 communication | `taito_zm.cpp` shared_ram, main CPU 0x1fbe0000-0x1fbe01ff (umask 0x00ff00ff) | XelaNotPu taito_zoom_top.sv mailbox (128 x 16 port A) |
| Zoom host port | | | Register select/data (global volume 0x04/0x05), sound IRQ | `taito_zm.cpp` reg_address_w/reg_data_w, sound_irq_w; main CPU 0x1fb80000-0x1fbc0001 | XelaNotPu taito_zoom_top.sv |
| Electronic volume | Fujitsu MB87078 | | 4-channel volume control | none (not emulated) | none (R12) |
| Audio out | NJM2100 op-amps x2, NEC uPD6379GR DAC (under the PCB) | | Zoom output | none | none needed beyond the MiSTer mixer |
| Supervisor / watchdog | Fujitsu MB3773 and Analog Devices ADM708AR (under the PCB) | | Reset, watchdog kicked from control bit 5 | `devices/machine/mb3773.cpp` | none found (simple counter) |
| Sub-BIOS flash | Intel TE28F160 16 Mbit (U30) | | Encrypted boot loader the BIOS decrypts; rewritten from the card when it does not match | `devices/machine/intelfsh.cpp` (INTEL_TE28F160), `taitogn.cpp` flashbank_map, region `firm` (`flash.u30`) | none |
| Zoom program flash | Intel E28F400 4 Mbit (U27) | | MN10200 program, written from the card | intelfsh.cpp (INTEL_E28F400B), region `zoomprog`; Zoom maps it at 0x080000-0x0fffff | none (FX-1B loads a ROM into DDR3 behind an 8 KB cache) |
| Wave flashes | Intel TE28F160 x3 (U56, U55, U29) | | ZSG-2 samples, 6 MB, written from the card; also visible to the main CPU in flash banks 1 and 3 | intelfsh.cpp, `taitogn.cpp` zsg2_ext_r | none |
| Bootleg EPROM socket | DIP40 AM27C800 (unpopulated on original boards) | | MOD BIOS "MB2009"/"MB2011" on the 2011 conversions (region `eprom`, bank 2) | `taitogn.cpp` | none |
| PC card controller | Ricoh RF5C296 (TQFP144, under the PCB) | | PCMCIA host: ExCA register index/data at I/O 0x3e0/0x3e1, card reset, I/O and memory windows | `devices/machine/rf5c296.cpp` ("very inaccurate at that point, it hardcodes the gnet config"); main CPU 0x1fb00000-0x1fb0ffff, memory window in flash bank 0 at 0x200000 | none |
| PC card (game media) | Type 1: TEL F1PACK TE6350B controller, ML-101, S2812A150 EEPROM, CXK58257 SRAM, ten Toshiba TC58V32FT 32 Mbit NAND (about 40 MB). Type 2 (sealed): IBM0398 controller, seven or eight TC58V32FT. Type 3: SanDisk SDCFB-64 CF in an adaptor | | ATA (CompactFlash-style) storage, password-locked | `devices/bus/pccard/ataflash.cpp` (taito_pccard1, taito_pccard2, taito_cf, ataflash), CHD hard-disk images with a 5-byte key in metadata | none for G-NET. Generic ATA references: Main_MiSTer `ide.cpp` (HPS-side ATA used by ao486 and Minimig), ao486_MiSTer |
| Security | CAT702 labelled TT16 (U17) | SIO0 | Second challenge/response chip | `cat702.cpp` | XelaNotPu `cat702.vhd` (two instances in their cores) |
| Board CPLD | Xilinx XC95108 labelled E65-01 | | FC PCB decode, control registers | `taitogn.cpp` control_r/w (0x1fb40000), control2 (0x1fb60000), control3 (0x1fa30000), gn_1fb70000 | none (R15) |
| Unpopulated | DIP24 (FM1208), *UPD6379GR etc. | | | | |
| Card slot | CD PCB daughterboard | | PCMCIA connector | | |

## 3. Optional boards (not in scope)

Communication interface PCB and Save PCB (MAME notes); RC De Go analog
controller (znmcu analog inputs); mahjong panel (ttgnmp_state).

## 4. Address map summary (main CPU, MAME 0.288)

| Range | Device |
|---|---|
| 0x1f000000-0x1f7fffff | flash bank (address_map_bank_device, 16-bit, stride 0x8000000): bank 0 = U30 sub-BIOS 0x000000-0x1fffff, RF5C296 memory 0x200000-0x2fffff, U27 0x300000-0x37ffff; banks 1 and 3 = wave U56/U55/U29; bank 2 = EPROM 0x000000-0x0fffff, U27 0x100000 (mirrored), U30 0x200000-0x3fffff |
| 0x1fa00000-0x1fa20000 | inputs, board config, CAT702 select, coin (zn.cpp) |
| 0x1fa30000 | control3 |
| 0x1fa51c00-0x1fa51dff, 0x1fa60000 | ZN-2 reads MAME ignores or toggles (R2) |
| 0x1faf0000-0x1faf07ff | AT28C16 |
| 0x1fb00000-0x1fb0ffff | RF5C296 I/O (ATA task file through the card I/O window, ExCA at 0x3e0/0x3e1) |
| 0x1fb40000 | control: bit 5 watchdog, bit 4 Zoom reset (held at power-on), bit 2 flash bank |
| 0x1fb60000 | control2 |
| 0x1fb70000 | returns 2 (R15) |
| 0x1fb80000-0x1fb80003 | Zoom register data/address |
| 0x1fba0000 / 0x1fbc0000 | Zoom IRQ write / status read |
| 0x1fbe0000-0x1fbe01ff | M66220FP mailbox |

## 5. Clock summary

| Crystal | Where | Users |
|---|---|---|
| 100 MHz | ZN-2 | CXD8661R CPU |
| 67.73 MHz | ZN-2 | SPU (MAME / 2), system |
| 53.693 MHz | ZN-2 | GPU dot clock |
| 25 MHz | FC PCB | ZSG-2; MN10200 and TMS57002 at 12.5 MHz |
| 5 MHz | ZN-2 | uPD78081 |
