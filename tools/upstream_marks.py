#!/usr/bin/env python3
"""List the edits in upstream PSX_MiSTer files that carry no G-NET: marker.

Compares each file in the working tree with the upstream base (default
cd17b5a, the PSX_MiSTer commit merged as this core's base) using
`git diff -U0` and checks every hunk:

  marked      one of its added lines contains 'G-NET:', or the nearest
              non-blank line above it in the current file does
  mechanical  (only with --mech NAME) every changed line is the upstream line
              with numeric widths replaced by an expression in NAME, line for
              line, e.g. 'unsigned(8 downto 0)' to
              'unsigned(VRAM_Y_BITS - 1 downto 0)'; the file's header notice
              covers these instead of one marker per line
  renamed     (only with --rename OLD=NEW) every changed line is the upstream
              line with the listed identifier renames applied
  wrapped     (only with --wrap MACRO) every changed line is the upstream line
              with some expressions X wrapped as `MACRO(X, constant)
  whitespace  the hunk changes blank space only (listed, not counted as
              unmarked; reverting those is a separate step)
  closing     (Verilog) the hunk only adds `else / `endif lines that close a
              conditional opened on a GNET_ macro, whose opening is marked
  unmarked    anything else (printed)

Usage:
  tools/upstream_marks.py rtl/gpu_line.vhd --mech VRAM_Y_BITS
  tools/upstream_marks.py --all     # every modified file, with the per-file
                                    # options in DEFAULTS (as the notices say)
Exit status 0 when nothing is unmarked.
"""
import argparse
import functools
import re
import subprocess
import sys

NUM = re.compile(r"\b\d+\b|\b16#[0-9A-Fa-f_]+#")
DIRECTIVE = re.compile(r"^\s*`(ifdef|ifndef|elsif|else|endif)\b\s*(\w*)")


def opener_of(lines, idx):
    """Index of the `ifdef/`ifndef that the `else/`endif at lines[idx] belongs to."""
    depth = 0
    for i in range(idx - 1, -1, -1):
        m = DIRECTIVE.match(lines[i])
        if not m:
            continue
        if m.group(1) == "endif":
            depth += 1
        elif m.group(1) in ("ifdef", "ifndef"):
            if depth == 0:
                return i
            depth -= 1
    return None


def closes_gnet(lines, h):
    """True if the hunk adds only `else/`endif lines closing GNET_ conditionals."""
    code = [x for x in h["add"] if x.strip() and not x.strip().startswith("//")]
    if not code or h["rem"]:
        return False
    k = h["new"] - 1
    for off, x in enumerate(h["add"]):
        if not x.strip() or x.strip().startswith("//"):
            continue
        m = DIRECTIVE.match(x)
        if not m or m.group(1) not in ("else", "endif"):
            return False
        o = opener_of(lines, k + off)
        if o is None or not DIRECTIVE.match(lines[o]).group(2).startswith("GNET_"):
            return False
    return True


def norm_mech(line, names):
    s = line
    for n in names:
        # NAME, NAME - 1, NAME + 15, 2**NAME, (NAME + 1) * 2 ...
        s = re.sub(r"(?:\d+\s*\*\*\s*)?\b%s\b(?:\s*[-+*]\s*\d+)*" % re.escape(n), "N", s)
    s = NUM.sub("N", s)
    return " ".join(s.split())


def unwrap(line, macro):
    """Replace `MACRO(a, b) by a (paren-aware)."""
    key = "`%s(" % macro
    out, i = [], 0
    while True:
        j = line.find(key, i)
        if j < 0:
            out.append(line[i:])
            return "".join(out)
        out.append(line[i:j])
        k, depth, comma = j + len(key), 1, None
        while k < len(line) and depth:
            c = line[k]
            if c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
            elif c == "," and depth == 1 and comma is None:
                comma = k
            k += 1
        if comma is None:
            out.append(line[j:k])
        else:
            out.append(line[j + len(key):comma].strip())
        i = k


def norm_rename(line, pairs):
    s = line
    for old, new in pairs:
        s = re.sub(r"\b%s\b" % re.escape(new), old, s)
    return " ".join(s.split())


def hunks_of(base, path):
    d = subprocess.run(["git", "diff", "-U0", base, "--", path], capture_output=True, text=True, check=True).stdout
    hunks, cur = [], None
    for line in d.splitlines():
        m = re.match(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
        if m:
            cur = {"new": int(m.group(3)), "nlen": int(m.group(4) or 1), "add": [], "rem": []}
            hunks.append(cur)
        elif cur is not None and line.startswith("+") and not line.startswith("+++"):
            cur["add"].append(line[1:])
        elif cur is not None and line.startswith("-") and not line.startswith("---"):
            cur["rem"].append(line[1:])
    return hunks


# Per-file options that --all applies (what each file's notice says it covers)
PSX_TOP_RENAMES = (
    "DMA_GPU_read=DMA_GPU_read_p", "DMA_GPU_readEna=DMA_GPU_readEna_p",
    "DMA_GPU_waiting=DMA_GPU_waiting_p", "DMA_GPU_write=DMA_GPU_write_p",
    "DMA_GPU_writeEna=DMA_GPU_writeEna_p", "DMA_SPU_read=DMA_SPU_read_p",
    "DMA_SPU_readEna=DMA_SPU_readEna_p", "DMA_SPU_write=DMA_SPU_write_p",
    "DMA_SPU_writeEna=DMA_SPU_writeEna_p", "SS_Adr=SS_Adr_p", "SS_DataWrite=SS_DataWrite_p",
    "SS_Idle_gpu=SS_Idle_gpu_p", "SS_idle=SS_idle_p", "SS_idle_spu=SS_idle_spu_p",
    "SS_reset=SS_reset_p", "SS_wren=SS_wren_p", "allowunpause=allowunpause_p",
    "bus_gpu_addr=bus_gpu_addr_p", "bus_gpu_dataRead=bus_gpu_dataRead_p",
    "bus_gpu_dataWrite=bus_gpu_dataWrite_p", "bus_gpu_read=bus_gpu_read_p",
    "bus_gpu_stall=bus_gpu_stall_p", "bus_gpu_write=bus_gpu_write_p",
    "bus_spu_addr=bus_spu_addr_p", "bus_spu_dataRead=bus_spu_dataRead_p",
    "bus_spu_dataWrite=bus_spu_dataWrite_p", "bus_spu_read=bus_spu_read_p",
    "bus_spu_write=bus_spu_write_p", "ce=ce_p", "cpuPaused=cpuPaused_p",
    "debugmodeOn=debugmodeOn_p", "dmaOn=dmaOn_p", "dotclock=dotclock_p",
    "errorCode=errorCode_p", "errorEna=errorEna_p", "errorGPU=errorGPU_p",
    "errorGPUFIFO=errorGPUFIFO_p", "errorLINE=errorLINE_p", "errorMASK=errorMASK_p",
    "errorPOLY=errorPOLY_p", "errorRECT=errorRECT_p", "errorSPUTIME=errorSPUTIME_p",
    "gpu_dmaRequest=gpu_dmaRequest_p", "hblank_tmr=hblank_tmr_p", "irq_GPU=irq_GPU_p",
    "irq_SPU=irq_SPU_p", "irq_VBLANK=irq_VBLANK_p", "loading_savestate=loading_savestate_p",
    "pausing=pausing_p", "pausingSS=pausingSS_p", "ram_cpu_done=ram_cpu_done_p",
    "ram_dataRead32=ram_dataRead32_p", "ram_done=ram_done_p", "reset_exe=reset_exe_p",
    "reset_intern=reset_intern_p", "savestate_pause=savestate_pause_p",
    "spu_dmaRequest=spu_dmaRequest_p", "vblank_tmr=vblank_tmr_p", "clk1x=clk_cpu",
    "clk2x=clk_cpu2x", "clk3x=clk_cpu3x", "clk2xIndex=clk2xIndex_c", "clk3xIndex=clk3xIndex_c",
    "loadExe=loadExe_c", "pause=pause_c", "reset=reset_c", "reset_in=reset_in_c",
)
DEFAULTS = {
    "PSX.sv": {"wrap": ["GNET_OPT"]},
    "rtl/psx_top.vhd": {"rename": list(PSX_TOP_RENAMES)},
}
for _f in ("gpu", "gpu_cpu2vram", "gpu_fillVram", "gpu_line", "gpu_pixelpipeline", "gpu_poly",
           "gpu_rect", "gpu_videoout", "gpu_vram2cpu", "gpu_vram2vram", "pGPU"):
    DEFAULTS["rtl/%s.vhd" % _f] = {"mech": ["VRAM_Y_BITS"]}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default="cd17b5a")
    ap.add_argument("--all", action="store_true", help="every HDL file modified since --base (PSX.sv, rtl/, sim/system)")
    ap.add_argument("--mech", action="append", default=[], help="generic name whose width substitutions count as mechanical")
    ap.add_argument("--rename", action="append", default=[], help="OLD=NEW identifier rename that counts as mechanical")
    ap.add_argument("--wrap", action="append", default=[], help="Verilog macro MACRO(live, fixed) whose wrapping counts as mechanical")
    ap.add_argument("-q", action="store_true", help="print only the per-file summary")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
    files = a.files
    if a.all:
        out = subprocess.run(["git", "diff", "--name-only", "--diff-filter=M", a.base, "--", "PSX.sv", "rtl", "sim/system"],
                             capture_output=True, text=True, check=True, cwd=top).stdout
        files = [f for f in out.split() if re.search(r"\.(vhd|sv|v)$", f)]
    pairs0 = [tuple(r.split("=", 1)) for r in a.rename]
    tot = {"marked": 0, "closing": 0, "mechanical": 0, "renamed": 0, "wrapped": 0, "whitespace": 0, "unmarked": 0}
    for f in files:
        with open("%s/%s" % (top, f), encoding="utf-8", errors="replace") as fh:
            new = fh.read().splitlines()
        d = DEFAULTS.get(f, {}) if a.all else {}
        mech = a.mech + d.get("mech", [])
        wrap = a.wrap + d.get("wrap", [])
        pairs = pairs0 + [tuple(r.split("=", 1)) for r in d.get("rename", [])]
        per = {"marked": 0, "closing": 0, "mechanical": 0, "renamed": 0, "wrapped": 0, "whitespace": 0, "unmarked": 0}
        for h in hunks_of(a.base, "%s/%s" % (top, f)):
            kind = "unmarked"
            if any("G-NET:" in x for x in h["add"]):
                kind = "marked"
            else:
                i = h["new"] - 2 if h["nlen"] > 0 else h["new"] - 1
                while i >= 0 and not new[i].strip():
                    i -= 1
                if i >= 0 and "G-NET:" in new[i]:
                    kind = "marked"
            if kind == "unmarked" and [x.split() for x in h["add"] if x.strip()] == [y.split() for y in h["rem"] if y.strip()]:
                kind = "whitespace"
            if kind == "unmarked" and closes_gnet(new, h):
                kind = "closing"
            if kind == "unmarked" and h["add"] and len(h["add"]) == len(h["rem"]):
                if mech and all(norm_mech(x, mech) == norm_mech(y, mech) and any(n in x for n in mech)
                                  for x, y in zip(h["add"], h["rem"])):
                    kind = "mechanical"
                elif wrap and all(" ".join(functools.reduce(unwrap, wrap, x).split()) == " ".join(y.split())
                                    for x, y in zip(h["add"], h["rem"])):
                    kind = "wrapped"
                elif pairs and all(norm_rename(x, pairs) == " ".join(y.split()) for x, y in zip(h["add"], h["rem"])):
                    kind = "renamed"
            per[kind] += 1
            if kind in ("unmarked", "whitespace") and not a.q:
                print("%s:%d  %s +%d/-%d  %s" % (f, h["new"], kind, len(h["add"]), len(h["rem"]),
                                             (h["add"] or h["rem"])[0].strip()[:90]))
        for k in tot:
            tot[k] += per[k]
        print("## %s: %s" % (f, ", ".join("%s %d" % kv for kv in per.items())))
    print("TOTAL " + ", ".join("%s %d" % kv for kv in tot.items()))
    return 1 if tot["unmarked"] else 0


if __name__ == "__main__":
    sys.exit(main())
