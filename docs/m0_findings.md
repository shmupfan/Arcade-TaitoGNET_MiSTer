# M0 findings

Started 2026-10-04 (alongside F0). MAME 0.288 unless stated. Game-derived
data (NVRAM, card images, RAM dumps, snapshots) lives under `sim/` and
`roms/`, gitignored.

## 1. ROM and CHD verification

`mame -rompath roms -verifyroms <set>` (0.288): coh3002t, raycris,
raycrisj, psyvarrv, psyvaria, psyvarij, xiistag, shikigam, shikigama,
nightrai all OK ("best available" only because the uPD78081 MCU ROM is
NO_DUMP). coh3002t.zip holds the eight files with the CRCs in
taitogn.cpp COH3002T_BIOS (m534002c-60.ic353, tt10.ic652, tt16.u17,
flash.u30, four f35-01 EPROM variants).

## 2. PC card images (R25)

`tools/extract_card.sh <set>` writes the raw image and the CHD metadata to
`sim/cards/`. chdman 0.289 (Homebrew rom-tools).

All six priority cards: 40,960,000 bytes (80,000 sectors of 512 bytes),
CHD hunk 4,096 bytes. Metadata per card:

| Set | KEY (Type 1 unlock) | CIS bytes | IDENTIFY model | Firmware | Serial prefix | IDENTIFY C/H/S |
|---|---|---|---|---|---|---|
| raycris | (from the CHD metadata) | 122 | TAITO AT-40M-TE(S1) | Ver.6.3 | LT980618 | 625/8/16 |
| psyvarrv | (from the CHD metadata) | 123 | TAITO AT-40M-TE(S2) | Ver.6.3 | LT990420 | 625/8/16 |
| psyvaria | (from the CHD metadata) | 122 | TAITO AT-40M-TE(S1) | Ver.6.3 | LT980916 | 625/8/16 |
| xiistag | (from the CHD metadata) | 123 | TAITO AT-40M-TE(S1) | Ver.6.3 | LT980925 | 625/8/16 |
| shikigam | (from the CHD metadata) | 123 | TAITO AT-40M-TE(S2) | Ver.6.3 | LT010531 | 625/8/16 |
| nightrai | (from the CHD metadata) | 123 | TAITO AT-40M-TE(S2) | Ver.6.3 | LT990514 | 625/8/16 |

Notes:
- The CHD geometry tag GDDD says 100/16/50, the IDENTIFY block says
  625/8/16; both give 80,000 sectors. The core should answer IDENTIFY
  with the stored IDNT block verbatim (MAME does), so the MRA or loader
  must carry the 512-byte IDNT, the 5-byte KEY and the CIS per game.
- Three later cards (xiistag, shikigam, nightrai) share one key.
- The serial prefix looks like a date (LT980618 = 1998-06-18 for Ray
  Crisis, earlier than the V2.03 1998-11-15 build); interpretation
  needs-review.

Card writes (MAME diff CHDs from the R18 runs, accumulated over all runs):
raycris 32 hunks (one 128 KB block from LBA 41056), psyvaria 4,
psyvarrv 4, xiistag 3, shikigam 3, nightrai 0. The core needs ATA writes
and a save path for dirty sectors. What the writes hold is open (R25).

## 3. First boot (R3)

Oracle canary (`tools/mame/oracle.lua`, raycris cold, 200 s; summary in
`sim/oracle/raycris_cold200/summary.txt`):

| Chip | Erases (0x20/0xD0) | Words programmed (0x40) | Window (emulated s) |
|---|---|---|---|
| firm (U30) | 18 | 525,458 | 2.86 to 22.3, header block rewritten at 139.6 to 140.6 |
| zoomprog (U27) | 7 | 262,144 (whole chip) | 24.30 to 28.77 |
| wave0 (U56) | 32 | 1,048,576 (whole chip) | 29.02 to 65.72 |
| wave1 (U55) | 32 | 1,048,576 | 65.96 to 102.66 |
| wave2 (U29) | 32 | 1,048,576 | 102.91 to 139.60 |

Copy: first command 2.863 s, last 140.611 s (137.7 s); game sound starts at
155.45 s. NVRAM after the run is byte-identical to the R18 snapshot. The
BIOS programs word by word with the sequence 0x50, 0x70, 0x50, 0x40, data
and polls the status register (about 3M reads per second while waiting),
so real program and erase times change the copy length.

MAME's flash model takes exactly 1.0 s per block erase and programs
instantly, so 121 of the 137.7 s are MAME's erase constant. Real times from
the Intel datasheets (typ, 28F160S3 290608-005 p50; 28F160S5 290609-004
p49), 121 erases and 3,933,330 words:

| Part, VPP | Erase total | Program total | Copy (flash only) |
|---|---|---|---|
| 28F160S3, 2.7 V | 67.8 s | 78.7 s | 146.4 s |
| 28F160S3, 3.3 V | 42.3 s | 74.7 s | 117.1 s |
| 28F160S3, 5 V | 36.3 s | 47.2 s | 83.5 s |
| 28F160S5 | 41.1 s | 36.3 s | 77.5 s |

MAME's notes give 2 to 3 minutes on the PCB, which fits the S3 at low VPP
best (inference, needs-review: board photos or the board's VPP settle S3
against S5). Both report device ID D0h, so software cannot tell them apart.

The BIOS also unlocks the card at every boot: repeated 9-byte groups to
attribute offsets 0x500 to 0x510 (byte addresses of MAME's 16-bit registers
0x280 to 0x288), 3,356 writes cold or warm, then configuration register
(byte 0x200) = 0x41.

Card traffic, all six games cold (Ray Crisis 200 s; the others 300 s with
a coin at 180 s; `sim/oracle/<set>_cold300/`):

| Set | READ SECTORS 0x20 | WRITE SECTORS 0x30 | IDENTIFY 0xEC | Other | Flash copy (first to last command) |
|---|---|---|---|---|---|
| raycris | 508 | 32 | 3 | none | 2.86 to 140.61 s |
| psyvarrv | 6,453 | 14 | 3 | none | 2.86 to 130.20 s |
| xiistag | 6,636 | 0 | 3 | none | 2.86 to 125.91 s |
| shikigam | 194 | 0 | 3 | none | 2.86 to 142.06 s |
| nightrai | 5,853 | 0 | 3 | none | 2.86 to 136.09 s |
| psyvaria | 2,852 | 14 | 3 | none | 2.86 to 127.25 s |

The Ray Crisis writes are zero-filled sectors right after the copy
(155.44 s). The RF5C296 setup (ExCA writes, values in
docs/gnet_glue_design.md 4) is identical in all six, and no game or the
BIOS reads an ExCA register.

## 3a. Card filesystem and where the flash contents come from

The card is a plain PC disk: MBR with one FAT16 partition (type 06h) at LBA
16, 79,872 sectors, 4 sectors per cluster, every file contiguous
(`tools/card_ls.py sim/cards/raycris.img` lists it). Ray Crisis holds 160
files: game code and data (PRG*.BIN, SCR*.BIN, BOSS*.BIN, E*/ENE*.BIN, TIM/,
CLUT/, VAB/ PlayStation sound banks), the flash payloads and an empty
SAVEDATA/ directory (probably where the card writes of R25 go).

Comparison of the post-copy flash NVRAM with the card files (Ray Crisis):

| Flash | Content | Evidence |
|---|---|---|
| wave0, wave1, wave2 (U56, U55, U29) | WAVE0.BIN, WAVE1.BIN, WAVE2.BIN (2 MB each), 16-bit byte-swapped | 4,041 of 4,096 sectors at one fixed offset for wave0; wave1/wave2 checked at 8 points each |
| firm (U30) 0x000000-0x05ffff | flash.u30 from coh3002t.zip (the sub-BIOS), 16-bit byte-swapped | 762 of 768 sectors equal; the 6 others are the header block rewritten at the end of the copy |
| firm (U30) from 0x060000 | RAY.SDH (1,000,458 bytes), byte-swapped | contiguous match from card offset 0xF9EA00 |
| zoomprog (U27) | from ZOOM.SDH (176,365 bytes), transformed | no verbatim or swapped match; ZOOM.SDH starts with the same record-table layout as RAY.SDH (01 01 xx 01 02 01 ...), so the BIOS probably unpacks records into the flash |

Decoded 2026-10-04 and checked: `tools/build_flash.py <card.img>
coh3002t.zip <outdir> --check <MAME nvram dir>` rebuilds all five flash
images from the card and the BIOS zip alone. Result: byte-identical to
MAME 0.288's post-first-boot NVRAM for every flash of all six priority
games (raycris, psyvarrv, xiistag, shikigam, nightrai, psyvaria; XII Stag
has one wave flash). This meets the M0 gate "regions byte-identical to
MAME's NVRAM after first boot" for the flash regions.

What the BIOS install does (reconstructed, all six games agree):
- SYSTEM.INF names gameprog, zoomprog, wave files (tabs or spaces; one
  title lacks its closing quote).
- wave flashes: the wave files, 16-bit byte-swapped.
- zoomprog: the zoomprog file (PROG.BIN raw, or ZOOM.SDH decoded),
  byte-swapped. SDH = 255-node Huffman tree (16-bit LE pairs, root 0x100,
  values below 0x100 are bytes), 0xFFFFFFFF, u32 decoded length, MSB-first
  bit stream; the decoded stream is u32 output length then LZSS (flag bits
  LSB first, 1 = literal, reference = 12-bit offset from the low byte and
  the high nibble, length = low nibble + 3, 4,096-byte ring from 4,078,
  zero filled). RAY.SDH is stored in U30 still compressed (the sub-BIOS
  decodes it at boot).
- firm (U30): flash.u30 (sub-BIOS) with an install header at 0x50000
  (u32 lot number in decimal from SYSTEM.INF, u32 gameprog size, 16-byte
  upper-case title, gameprog extension and area letter, version major and
  minor, a mask of installed wave flashes, then FF FF 00 00 00),
  SYSTEM.TIM at 0x54000 with three VRAM position bytes set (13 = 03h,
  14 = FEh, 57 = 03h) and zero-padded to 256 bytes, and the gameprog file at
  0x60000 zero-padded to the end of its 64 KB erase block.

Consequence for the loader (docs/gnet_glue_design.md 3): a release can
build every flash image from the CHD and the BIOS zip with no first-boot
run and no MAME-made data; the first-boot copy stays available as an
accuracy option.

## 3b. GPU command stream for M1

`ORACLE_GPU_STREAM=1 tools/mame/oracle_run.sh ...` writes gpu_stream.bin:
every CPU write to GP0/GP1, and at each DMA channel 2 start the words the
GPU receives (block mode read from RAM; linked lists walked node by node,
headers removed, one record per node). `tools/gpu_stream.py` parses it into
GP0 commands. Main RAM is 4 MB on the ZN-2, so DMA addresses are masked
with 0x3FFFFC (a first version used the PS1's 2 MB mask, walked garbage and
wrote 5 GB in 28 s; fixed, with loop and size guards).

Ray Crisis warm, 40 s with a credit (`sim/oracle/gs_canary`): 7.9 MB, 2,206
frames, 4,408 DMA lists (up to 4,268 nodes each), 1.19 M words by linked
list, 0.24 M by block DMA, 16.5 k by CPU. GP0 commands: 142,164 rectangles,
72,856 environment, 54,009 polygons, 2,199 VRAM copies, 1,480 poly-lines,
1,307 fills, 307 CPU-to-VRAM uploads.

## 4. PSX block use (R18)

MDEC unused, SPU used: docs/r18_mdec_spu.md.
