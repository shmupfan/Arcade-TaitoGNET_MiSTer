# GPU VRAM read latency on DDR3: where it costs and what hides it

This study's GPU changes and its testbench (`sim/gpuinfl/`) are on a
development branch and are not in this repository or in the release RBF,
which uses the upstream GPU read path. The document is kept as the record
of the measurements cited in docs/ACCURACY.md.

docs/ddr3_bandwidth.md (branch ddr3-bandwidth, 4.3) showed the PSX_MiSTer
GPU is bound by DDR3 read latency: it keeps one VRAM read in flight
(rtl/gpu.vhd READVRAM waits for the last beat) and its drawing waits for
every texture cache miss. This document measures which reads cost the time
and tries three changes, all behind generics whose defaults keep the
upstream GPU unchanged. Branch gpu-read-infl (from ddr3-arb-int 277f5de).

## 1. Method

- M1 replay testbench `sim/gpuinfl/tb_gpu_infl.vhd` (from sim/m1 and
  sim/arbgpu): the Ray Crisis attract-demo gameplay chunk
  (sim/m1/gtime/streams/demo_5700.txt with
  sim/oracle/gtime_raycris_demo1/vram_5700.bin, game-derived, not
  committed), first 57 GPU frames, 2 MB VRAM.
- Memory model rewritten as a pipelined port: a read is answered in order
  from a copy of its words taken when it is accepted, its first beat L + 1
  edges later (the old model's timing, L = -gVRAM_RD_LAT); writes apply when
  accepted, also while reads are outstanding. Several reads in flight.
- Each read is tagged with its requester (texture miss, CLUT, video,
  poly/rect/line destination, copy) from the GPU's request lines and the
  pipeline's texture state (`texReqActive`, a simulation-only signal in
  gpu_pixelpipeline). Per-class latency generics remove the latency of one
  class at a time.
- Work measure: destination-read commands per run against the ideal-memory
  run (one per drawn span line; the CLUT-load count agrees within a few
  points). The GPU takes the stream with MAME's frame pacing, so a slower
  GPU finishes less of it in the same frames. Write beats are not used:
  they move with the pixel-merge timeouts (L = 12 gives 106% of the ideal
  write beats). Read commands are not used: the fills change their count.
- Correctness gate: VRAM after frame 30 at L = 0 compared pixel by pixel
  with upstream (`-gDUMPS=30`).

## 2. Where the latency is paid (L = 24)

Reads in the 57 frames at L = 0: texture misses 78.6%, destination reads
17.2%, CLUT loads 3.2%, video 1.0%, copies 0.1%.

| Latency removed from (L = 24 for the rest) | Work done (of ideal) |
|---|---|
| none | 73.7% |
| texture misses | 100.0% |
| destination reads | 80.0% |
| CLUT loads | 74.4% |
| video and copies | 74.3% |

Texture misses are the whole problem: with their latency removed the GPU
keeps up at L = 24.

## 3. Changes tried

| Generic (default = upstream) | What it does |
|---|---|
| gpu GPU_READ_INFL (1) | >= 2: pixel writes leave the output FIFO while a single-burst read waits for its data. The read was accepted first and the port answers in order, so it returns the same data as upstream. Also the number of texture-row reads allowed in flight (below). |
| gpu / gpu_pixelpipeline TEX_FETCH_QW (1) | 4: a texture miss (unfiltered texturing) fills the aligned group of four qwords holding the missed one, one 4-beat burst. In the cache layout (rtl/gpu_pixelpipeline.vhd tag_addr) the group is the four entries of one index row, same tag, in both the 4/8-bit and the 15-bit layout. Filtered pixels keep one qword: a group fill could evict another texel of the same pixel. |
| gpu / gpu_pixelpipeline TEX_FETCH_ROWS (1) | 2 or 4, with TEX_FETCH_QW = 4 and GPU_READ_INFL >= TEX_FETCH_ROWS: the same group of the next 1 or 3 texture rows too, each a 4-beat burst issued right after the previous one is accepted, so the latencies overlap. Rows that would carry into the next cache block (different tag) are not fetched; that miss fills one row. |

## 4. Results (work done, of ideal, 57 frames)

| Configuration | L = 12 | L = 24 | L = 36 |
|---|---|---|---|
| upstream | 95.9% | 73.7% | 60.4% |
| GPU_READ_INFL = 2 (posted writes only) | | 73.8% | |
| TEX_FETCH_QW = 4 | 100.1% | 84.0% | 70.6% |
| + TEX_FETCH_ROWS = 2, GPU_READ_INFL = 2 | 100.1% | 89.9% | 76.4% |
| + TEX_FETCH_ROWS = 4, GPU_READ_INFL = 4 | 100.1% | 90.1% | 78.8% |

Texture read commands at L = 24: 861,254 (upstream), 635,715 (4 qwords),
493,408 (2 rows), 397,993 (4 rows).

- Posted writes alone gain nothing: the pixel pipeline waits for the
  texel, not for the write FIFO.
- The 4-qword fill removes the loss at L = 12 and a third of it at L = 24.
- Two rows with two reads in flight bring L = 24 to 90%; four rows add
  little more (90.1% at L = 24, +2.4 points at L = 36). What remains is
  misses that follow each other (each still waits L) and the destination
  reads (section 2: 6.3 points at L = 24).
- VRAM at frame 30 (L = 0) is identical to upstream for the 4-qword, the
  2-row and the 4-row configuration (0 of 1,048,576 pixels differ), the
  2-row and 4-row runs with posted writes on.

## 5. Accuracy notes

- psx-spx (Texture Caching) gives the cache geometry the upstream GPU
  already uses: 2 KB, 256 entries of 8 bytes, a block of 64 x 64 texels in
  4-bit mode, 32 x 64 in 8-bit, 32 x 32 in 15-bit. It does not say how much
  the real GPU loads on a miss. Whether the CXD8654Q fills one entry or
  more per miss is open (needs-review); a timing test on a PS1 or ZN-2
  (texture fetch cost per miss against a stride pattern) would settle it.
- The fills put neighbouring entries into the cache earlier than upstream
  would. The contents are VRAM's at fill time, as upstream's are at its
  fill time; a difference can only appear when a primitive draws into its
  own texture area between the fill and the use. The upstream comment at
  REQUESTTEXTURE already treats that case as unknown on real hardware. Not
  seen in the frame-30 checks.
- Every change is a generic with the upstream value as default; with the
  defaults the GPU elaborates to the upstream logic (the new branches are
  under `if GENERIC = ...` on constants). Checked: at L = 0 the defaults on
  the new RTL and the pipelined memory model give the same port traffic in
  every one of 31 frames (commands, beats, busy cycles, longest run, window
  maxima) as the original GPU on the old blocking model.

## 6. Cost (estimate, not fitted)

About 100 ALMs and no M10K for all three: fill base, beat and row counters
and the entry address adders in gpu_pixelpipeline (about 40), the extra-row
read address and counter in gpu.vhd (about 40), the posted-write condition
(about 15). The DDR3 arbiter's owner FIFO (16 entries) already allows 4 GPU
reads in flight.

## 7. Recommendation

The probe's measured L decides (docs/ddr3_latency_probe.md, branch
ddr3-latency-probe):

- L <= 12 clk_2x: TEX_FETCH_QW = 4 is enough (100%), or nothing (96%).
- L about 24: TEX_FETCH_QW = 4, TEX_FETCH_ROWS = 2, GPU_READ_INFL = 2 (90%).
- L 36 and above: the rows help less (79% at 4 rows); the next step would
  be a texture prefetcher that looks ahead along the span and keeps
  several independent misses in flight (a queue between rasterizer and
  pipeline, a few hundred to about 1,500 ALMs), plus overlapping the next
  line's destination read. docs/gpu_tex_prefetch.md: design study (ideal
  bound 100% at L = 36 and 48) and the RTL prototype TEX_PREFETCH (default
  off; 100% at L = 24 and 36, 99.1% at L = 48; VRAM identical to upstream
  at L = 0 on Ray Crisis, Psyvariar and Shikigami).

## 8. Reproduce

`sim/gpuinfl/build.sh`, then
`sim/gpuinfl/run.sh <name> <stream> <vram image> 60 -gVRAM_RD_LAT=<L>
[-gTEX_QW=4] [-gTEX_ROWS=2|4] [-gREAD_INFL=2|4] [-gLAT_TEX=0 ...]
[-gDUMPS=30]`. ddr3_frames.txt columns: as sim/arbgpu, then reads per class
(texture, CLUT, video, destination, copy) and the cycles a read waited with
pixel writes queued.

## 9. Build macros

The three generics reach the GPU through psx_top and psx_mister (defaults
1, upstream). In a revision's qsf:

```
set_global_assignment -name VERILOG_MACRO "GNET_TEX_FETCH_QW=4"
set_global_assignment -name VERILOG_MACRO "GNET_TEX_FETCH_ROWS=2"
set_global_assignment -name VERILOG_MACRO "GNET_GPU_READ_INFL=2"
```

TEX_FETCH_ROWS needs TEX_FETCH_QW = 4 and GPU_READ_INFL >= TEX_FETCH_ROWS
(otherwise the extra rows are not read). Unset macros keep upstream.
`tools/lint_psx.py <revision> +define+GNET_...` is clean with and without
them; psx_top and psx_mister analyse in NVC (sim/zn2/system/build.sh).
