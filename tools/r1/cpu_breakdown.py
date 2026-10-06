#!/usr/bin/env python3
"""Cycle breakdown of a CPU window from a full-system run (sim/fullsys
harness: pc.log from -pctrace_from/-pctrace_to, io.log from -iolog_all 1
over the same window, ram_<T>.bin from -ramdump_us; the BIOS image).

    cpu_breakdown.py <run dir> <bios.bin> [cpu_mhz=50] [ram image]

ram image: main RAM (byte address 0 up) for the opcodes; default the run's
ram_<T>.bin (the harness dumps only the first 64 KB). The harness
checkpoint holds all of SDRAM: extract it as in docs/r1_cpu_domain_design.md.

pc.log has every new fetch-stage PC with its time, so the time a PC stays
is the cycles the whole pipeline spent while that instruction was being
fetched: 1 cycle when nothing stalls, more when the fetch missed or any
later stage held the pipeline. Each extra cycle is attributed to one
cause, in this order:
  data     a CPU data access (io.log) was requested within the stall or in
           the 3 cycles before it (load or store, by region: RAM,
           scratchpad, I/O, expansion bus, BIOS)
  ifetch   the fetch of this PC missed a model of the 4 KB direct-mapped
           I-cache (16-byte lines, refill from the missed word to the end
           of the line, KUSEG/KSEG0 only), or the PC is uncached
           (KSEG1, BIOS)
  muldiv   the opcode is MFHI/MFLO, or MULT/DIV in flight (needs the
           opcode: RAM dump or BIOS)
  gte      the opcode is a COP2 instruction or a GTE register move
  other    none of the above (branch/exception/unknown)
Output: totals in cycles and as a share of the window, per class and
region, plus per-class counts and mean stall per event.
"""
import struct
import sys
from collections import Counter, defaultdict


IO_NAMES = [
    (0x1F801070, 0x1F801078, "I/O I_STAT/I_MASK"),
    (0x1F801080, 0x1F801100, "I/O DMA"),
    (0x1F801100, 0x1F801130, "I/O timers"),
    (0x1F801040, 0x1F801050, "I/O SIO0"),
    (0x1F801810, 0x1F801818, "I/O GPU"),
    (0x1F801C00, 0x1F802000, "I/O SPU"),
]
EXP_NAMES = [
    (0x1F000000, 0x1F800000, "expansion flash window"),
    (0x1FB00000, 0x1FB10000, "expansion RF5C296/ATA"),
    (0x1FA51C00, 0x1FA51E00, "expansion 1FA51Cxx"),
    (0x1FA60000, 0x1FA60004, "expansion 1FA60000 SPU status"),
    (0x1FA00000, 0x1FA00400, "expansion inputs"),
    (0x1FB80000, 0x1FC00000, "expansion Zoom/mailbox"),
]


def region(a):
    a &= 0x1FFFFFFF
    if a < 0x00800000:
        return "RAM"
    if 0x1F800000 <= a < 0x1F800400:
        return "scratchpad"
    if 0x1F801000 <= a < 0x1F803000:
        for lo, hi, n in IO_NAMES:
            if lo <= a < hi:
                return n
        return "I/O other"
    if 0x1FC00000 <= a < 0x1FC80000:
        return "BIOS"
    if 0x1F000000 <= a < 0x1F800000 or 0x1FA00000 <= a < 0x1FC00000:
        for lo, hi, n in EXP_NAMES:
            if lo <= a < hi:
                return n
        return "expansion other"
    return "other"


def main(run, biosf, mhz=50.0, ramf=None):
    cyc = 1.0 / mhz          # one CPU cycle in us (pc.log and io.log times are in us)
    bios = open(biosf, "rb").read()
    import glob
    rd = glob.glob(run + "/ram_*.bin")
    ram = open(ramf, "rb").read() if ramf else (open(rd[0], "rb").read() if rd else b"")

    def opcode(pc):
        a = pc & 0x1FFFFFFF
        if a < len(ram):
            return struct.unpack_from("<I", ram, a & ~3)[0]
        if 0x1FC00000 <= a < 0x1FC80000:
            return struct.unpack_from("<I", bios, (a - 0x1FC00000) & ~3)[0]
        return None

    pcs = []
    for l in open(run + "/pc.log"):
        p = l.split()
        if len(p) == 2:
            pcs.append((float(p[0]), int(p[1], 16)))
    acc = []
    for l in open(run + "/io.log"):
        p = l.split()
        if len(p) >= 7:
            acc.append((float(p[0]), p[1], int(p[2], 16), int(p[6], 16)))
    acc.sort()

    # I-cache model
    tags = [None] * 256
    valid = [[False] * 4 for _ in range(256)]

    def fetch_miss(pc):
        seg = pc >> 29
        if seg in (5, 6, 7) or region(pc) == "BIOS":   # KSEG1 / ROM: uncached
            return "uncached"
        a = pc & 0x1FFFFFFF
        line = (a >> 4) & 0xFF
        tag = a >> 12
        w = (a >> 2) & 3
        if tags[line] == tag and valid[line][w]:
            return None
        if tags[line] != tag:
            tags[line] = tag
            valid[line] = [False] * 4
        for k in range(w, 4):
            valid[line][k] = True
        return "miss"

    pc_cycles = Counter()
    stall = Counter()
    events = Counter()
    hist_stall = defaultdict(Counter)
    total = 0
    ninst = 0
    ai = 0
    muldiv_until = -1.0
    for i in range(len(pcs) - 1):
        t, pc = pcs[i]
        dt = pcs[i + 1][0] - t
        n = max(1, round(dt / cyc))
        total += n
        ninst += 1
        pc_cycles[pc] += n
        fm = fetch_miss(pc)
        op = opcode(pc)
        if op is not None:
            o = op >> 26
            if o == 0 and (op & 0x3F) in (0x18, 0x19, 0x1A, 0x1B):
                muldiv_until = t
        extra = n - 1
        if extra <= 0:
            continue
        # data access requested in [t - 3 cycles, t + dt)
        while ai < len(acc) and acc[ai][0] < t - 3 * cyc:
            ai += 1
        cause = None
        j = ai
        while j < len(acc) and acc[j][0] < t + dt:
            if acc[j][0] >= t - 3 * cyc:
                cause = ("load " if acc[j][1] == "R" else "store ") + region(acc[j][2])
                break
            j += 1
        if cause is None:
            # a store in the last 4 instructions (stores are posted: no done
            # pulse, so io.log does not list them)
            for k in range(max(0, i - 4), i + 1):
                ok = opcode(pcs[k][1])
                if ok is not None and (ok >> 26) in (0x28, 0x29, 0x2A, 0x2B, 0x2E, 0x3A):
                    cause = "store (opcode) " + ("GTE" if (ok >> 26) == 0x3A else "")
                    break
        if cause is None and fm is not None:
            cause = "ifetch " + ("uncached " + region(pc) if fm == "uncached" else "I-cache miss")
        if cause is None and op is not None:
            o = op >> 26
            if o == 0 and (op & 0x3F) in (0x10, 0x12):
                cause = "muldiv (MFHI/MFLO)"
            elif o == 0x12 or o in (0x32, 0x3A):
                cause = "gte"
        if cause is None:
            cause = "other" if op is not None else "other (no opcode)"
        stall[cause] += extra
        events[cause] += 1
        hist_stall[cause][extra] += 1
    span_us = pcs[-1][0] - pcs[0][0]
    print(f"window {pcs[0][0]:.1f} to {pcs[-1][0]:.1f} us = {span_us:.1f} us = {span_us * mhz:.0f} cycles at {mhz} MHz")
    print(f"instructions (fetch-stage PC changes) {ninst}, cycles counted {total}, CPI {total / ninst:.3f}")
    print(f"base (1 cycle per instruction) {ninst} = {100.0 * ninst / total:.1f}%")
    for c, v in stall.most_common():
        top = ", ".join(f"{k}:{n}" for k, n in sorted(hist_stall[c].items(), key=lambda x: -x[1])[:4])
        print(f"{c:32s} {v:9d} cycles {100.0 * v / total:5.1f}%  events {events[c]:8d}  mean {v / events[c]:5.2f}  (stall:count {top})")
    reg = Counter(region(a[2]) + " " + a[1] for a in acc)
    print("data accesses in the window:", ", ".join(f"{k} {v}" for k, v in reg.most_common()))
    # where the time goes: 16-byte code blocks by cycles, with the data
    # regions their instructions access
    blk = Counter()
    for pc, c in pc_cycles.items():
        blk[pc & ~0xF] += c
    acc_by_blk = defaultdict(Counter)
    for a in acc:
        acc_by_blk[a[3] & ~0xF][region(a[2])] += 1
    print("top code blocks by cycles (block, share, data accesses by region):")
    for b, c in blk.most_common(12):
        ra = ", ".join(f"{k} {v}" for k, v in acc_by_blk[b].most_common(3))
        print(f"  {b:08X} {100.0 * c / total:5.1f}%  {ra}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 50.0,
         sys.argv[4] if len(sys.argv) > 4 else None)
