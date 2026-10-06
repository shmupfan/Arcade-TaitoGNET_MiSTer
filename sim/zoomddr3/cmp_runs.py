#!/usr/bin/env python3
"""Compare two Zoom bench runs: insn.bin (32-byte records: pc, psw, mdr,
D0-D3/A0-A3 as six 32-bit words) and mbx.log (MN10200 mailbox accesses and
host acks in order). Prints the record counts, the first difference and,
for the instruction logs, the differing stretches with the PCs involved
(as docs/zoom_board_design.md 14.8 compares tb_zoomlink with tb_zoomref).

  cmp_runs.py <run A dir> <run B dir>
"""
import struct, sys, collections

def recs(d):
    b = open(d + '/insn.bin', 'rb').read()
    return [b[i:i + 32] for i in range(0, len(b), 32)]

def main():
    a, b = sys.argv[1], sys.argv[2]
    ra, rb = recs(a), recs(b)
    print(f'instructions: A {len(ra)}, B {len(rb)}')
    if ra == rb:
        print('instruction logs: identical')
    else:
        # greedy resync: on a mismatch, find the smallest (da, db), da + db
        # <= W, after which K records match again
        W, K = 256, 16
        i = j = 0
        diffs = []
        na, nb = len(ra), len(rb)
        while i < na and j < nb:
            if ra[i] == rb[j]:
                i += 1; j += 1
                continue
            found = None
            for s_ in range(1, W + 1):
                for da in range(s_ + 1):
                    db = s_ - da
                    if i + da + K <= na and j + db + K <= nb and ra[i + da:i + da + K] == rb[j + db:j + db + K]:
                        found = (da, db); break
                if found: break
            if not found:
                print(f'instruction logs: no resync within {W} records after A {i}, B {j}')
                diffs.append(('x', i, na, j, nb)); i, j = na, nb
                break
            # extend over records that differ in place (same count)
            diffs.append(('d', i, i + found[0], j, j + found[1])) if found != (0, 0) else None
            i += found[0]; j += found[1]
        # same-length in-place differences: records at i == j positions that differ were handled as (k, k) shifts
        if i < na or j < nb:
            diffs.append(('t', i, na, j, nb))
        n_a = sum(op[2] - op[1] for op in diffs); n_b = sum(op[4] - op[3] for op in diffs)
        pcs = collections.Counter()
        for op in diffs:
            for r in ra[op[1]:op[2]] + rb[op[3]:op[4]]:
                pcs[struct.unpack('<I', r[:4])[0]] += 1
        print(f'instruction logs: {len(diffs)} differing stretches, {n_a} records in A and {n_b} in B' + (f'; first at A record {diffs[0][1]}' if diffs else ''))
        if diffs:
            print('  PCs in the differing records: ' + ', '.join(f'{pc:06x} x{n}' for pc, n in pcs.most_common(8)))
            lens = [max(op[2] - op[1], op[4] - op[3]) for op in diffs]
            print(f'  stretch length max {max(lens)}; last stretch ends at A record {diffs[-1][2]} of {na}')
    ma = open(a + '/mbx.log').read().split('\n')
    mb = open(b + '/mbx.log').read().split('\n')
    if ma == mb:
        n = collections.Counter(l[0] for l in ma if l)
        print(f'mailbox/ack logs: identical ({n["M"]} MN10200 mailbox accesses, {n["A"]} host acks)')
    else:
        for i, (x, y) in enumerate(zip(ma, mb)):
            if x != y:
                print(f'mailbox/ack logs differ at line {i}: A {x!r}, B {y!r}')
                break
        else:
            print(f'mailbox/ack logs: lengths {len(ma)} and {len(mb)}')

main()
