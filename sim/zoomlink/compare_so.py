#!/usr/bin/env python3
"""Compare the TMS57002 SO1 stream of the integration bench (so.bin from
tb_zoomlink, one pair per SYNC after the release) with MAME's (S lines of
tools/zoom/zoom_hostlog.sh run with ZOOM_HOSTLOG_SO=1).

    compare_so.py <so.bin> <hostlog> <t_release_s> [block] [search]

MAME's sample k is floor(t x 32,552); the board's sample n counts SYNCs from
the release, so the nominal alignment is n = k - floor(t_release x 32,552).
The bench runs free (its MN10200 takes the main CPU's commands some
microseconds later than MAME, and its TMS57002 drives EMPTY itself), so the
streams are compared block by block (default 4,096 samples of MAME's): for
each block the offset within +-search board samples (default 2,000) with the
most equal pairs is taken. Values are 24-bit signed. Reports per block the
best offset and the equal pairs, then totals; blocks silent on both sides
are counted apart.
"""
import struct
import sys

import numpy as np


def s24(v):
    v = v & 0xFFFFFF
    return np.where(v & 0x800000, v - 0x1000000, v)


def main():
    sob, hl, trel = sys.argv[1], sys.argv[2], float(sys.argv[3])
    blk = int(sys.argv[4]) if len(sys.argv) > 4 else 4096
    srch = int(sys.argv[5]) if len(sys.argv) > 5 else 2000
    b = np.frombuffer(open(sob, "rb").read(), dtype="<i4").reshape(-1, 2).astype(np.int64)
    board = s24(b[:, 0]) * (1 << 24) + s24(b[:, 1])
    k0 = int(trel * 32552)
    ks, ls, rs = [], [], []
    for ln in open(hl):
        if ln.startswith("S "):
            f = ln.split()
            ks.append(int(f[1]) - k0); ls.append(int(f[2])); rs.append(int(f[3]))
    ks = np.array(ks); ls = s24(np.array(ls, dtype=np.int64)); rs = s24(np.array(rs, dtype=np.int64))
    sel = ks >= 0
    ks, ls, rs = ks[sel], ls[sel], rs[sel]
    mame = np.zeros(ks.max() + 1, dtype=np.int64)
    have = np.zeros(ks.max() + 1, dtype=bool)
    mame[ks] = ls * (1 << 24) + rs
    have[ks] = True
    nzb = np.nonzero(board)[0]
    nzm = np.nonzero(mame)[0]
    print(f"board: {len(board)} samples, first non-zero at {nzb[0] if len(nzb) else None}; "
          f"MAME: {have.sum()} samples logged, first non-zero at {nzm[0] if len(nzm) else None}")
    end = min(len(mame), len(board))
    tot = eq_tot = silent = exact = 0
    offs = {}
    for b0 in range(0, end - blk, blk):
        idx = np.nonzero(have[b0:b0 + blk])[0] + b0
        if len(idx) == 0:
            continue
        mv = mame[idx]
        lo_o = max(-srch, -int(idx.min()))
        hi_o = min(srch, len(board) - 1 - int(idx.max()))
        if not mv.any() and not board[idx].any():
            silent += 1
            continue
        best = (-1, 0)
        for o in range(lo_o, hi_o + 1):
            e = int(np.count_nonzero(board[idx + o] == mv))
            if e > best[0]:
                best = (e, o)
        tot += len(idx)
        eq_tot += best[0]
        offs[best[1]] = offs.get(best[1], 0) + 1
        if best[0] == len(idx):
            exact += 1
        print(f"block {b0:8d}: offset {best[1]:+5d}, equal {best[0]} of {len(idx)}")
    # level and waveform: one global offset (least error) over the part
    # where MAME is not silent, left and right as 24-bit values
    if len(nzm) and len(nzb):
        w0, w1 = int(nzm[0]), min(len(mame), len(board) + srch) - srch
        idx = np.nonzero(have[w0:w1])[0] + w0
        mr = ((mame[idx] & 0xFFFFFF) ^ 0x800000) - 0x800000
        ml = (mame[idx] - mr) >> 24
        bestw = None
        for o in range(-srch, srch + 1):
            j = idx + o
            if j.min() < 0 or j.max() >= len(board):
                continue
            br = ((board[j] & 0xFFFFFF) ^ 0x800000) - 0x800000
            bl = (board[j] - br) >> 24
            e = float(np.mean((bl - ml) ** 2 + (br - mr) ** 2))
            if bestw is None or e < bestw[0]:
                bestw = (e, o, bl, br)
        if bestw:
            e, o, bl, br = bestw
            rms_m = float(np.sqrt(np.mean(ml.astype(float) ** 2 + mr.astype(float) ** 2) / 2))
            rms_b = float(np.sqrt(np.mean(bl.astype(float) ** 2 + br.astype(float) ** 2) / 2))
            err = float(np.sqrt(e / 2))
            mx = int(max(np.abs(bl - ml).max(), np.abs(br - mr).max()))
            print(f"waveform over {len(idx)} samples from MAME's first non-zero: best offset {o:+d}; "
                  f"RMS board {rms_b:.1f}, MAME {rms_m:.1f}; error RMS {err:.1f} ({100.0 * err / rms_m:.2f}% of MAME's); "
                  f"max abs error {mx} (24-bit units; 16-bit: divide by 256); samples equal {int(np.count_nonzero((bl == ml) & (br == mr)))}")
    pct = f" ({100.0 * eq_tot / tot:.2f}%)" if tot else ""
    print(f"non-silent blocks: {sum(offs.values())}, exact {exact}; equal pairs {eq_tot} of {tot}{pct}; "
          f"silent blocks {silent}; offsets {dict(sorted(offs.items()))}")


if __name__ == "__main__":
    main()
