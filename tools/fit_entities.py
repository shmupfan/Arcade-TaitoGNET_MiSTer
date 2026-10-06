#!/usr/bin/env python3
"""Per-block resources from a Quartus 17 fit report.

Reads the "Fitter Resource Utilization by Entity" table and the
"Fitter Resource Usage Summary" of a .fit.rpt and prints, for every node
whose hierarchy path matches --node, a table of its direct children
(ALMs needed, dedicated registers, block memory bits, M10K, DSP), sorted by
ALMs. Values are totals including each child's own children.

Reconciliation: for every printed parent, the children plus the parent's own
share must equal the parent's total (to rounding); a mismatch is reported.

  tools/fit_entities.py builds/<stamp>_psx/PSX.fit.rpt --node 'psx_top:ipsx_top$'
  tools/fit_entities.py <rpt> --node 'sys_top$' --node 'emu:emu$' --csv out.csv
"""
import argparse
import csv
import re
import sys

NUM = re.compile(r'^\s*([0-9.,]+)\s*(?:\(([0-9.,]+)\))?\s*$')
COLS = {
    'alms': 'ALMs needed [=A-B+C]',
    'regs': 'Dedicated Logic Registers',
    'bits': 'Block Memory Bits',
    'm10k': 'M10Ks',
    'dsp': 'DSP Blocks',
}


def num(cell):
    """'1234.5 (12.3)' -> (1234.5, 12.3); '933787' -> (933787, None)"""
    m = NUM.match(cell)
    if not m:
        return None, None
    tot = float(m.group(1).replace(',', ''))
    own = float(m.group(2).replace(',', '')) if m.group(2) else None
    return tot, own


def read_entities(path):
    lines = open(path, encoding='latin-1').read().splitlines()
    start = next(i for i, l in enumerate(lines)
                 if l.startswith('; Fitter Resource Utilization by Entity'))
    hdr_i = next(i for i in range(start, start + 10)
                 if lines[i].startswith('; Compilation Hierarchy Node'))
    header = [c.strip() for c in lines[hdr_i].split(';')]
    idx = {k: header.index(v) for k, v in COLS.items()}
    idx['path'] = header.index('Full Hierarchy Name')
    rows = []
    for l in lines[hdr_i + 2:]:
        if l.startswith('+'):
            break
        cells = l.split(';')
        r = {'path': cells[idx['path']].strip()}
        for k in COLS:
            r[k], r[k + '_own'] = num(cells[idx[k]])
        rows.append(r)
    return rows


def read_summary(path):
    text = open(path, encoding='latin-1').read()
    out = {}
    for key, pat in [
        ('alms', r'; Logic utilization \(ALMs needed / total ALMs on device\)\s*; ([0-9,]+) / ([0-9,]+)'),
        ('regs', r'; Total dedicated logic registers\s*; ([0-9,]+)'),
        ('m10k', r'; M10K blocks\s*; ([0-9,]+) / ([0-9,]+)'),
        ('dsp', r'; Total DSP Blocks\s*; ([0-9,]+) / ([0-9,]+)'),
        ('bits', r'; Total block memory bits\s*; ([0-9,]+) / ([0-9,]+)'),
    ]:
        m = re.search(pat, text)
        if m:
            out[key] = tuple(int(g.replace(',', '')) for g in m.groups())
    return out


def children(rows, parent):
    depth = parent.count('|')
    pre = parent + '|'
    return [r for r in rows if r['path'].startswith(pre)
            and r['path'].rstrip('|').count('|') == depth + 1]


def short(path):
    """last hierarchy element without the trailing bar"""
    return path.rstrip('|').split('|')[-1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('rpt')
    ap.add_argument('--node', action='append', required=True,
                    help='regex matched against the full hierarchy path of the parent')
    ap.add_argument('--csv')
    a = ap.parse_args()

    rows = read_entities(a.rpt)
    summ = read_summary(a.rpt)
    print(f'# {a.rpt}\n')
    print('| Device total | used | available | % |')
    print('|---|---|---|---|')
    for k, label in [('alms', 'ALMs needed'), ('m10k', 'M10K'), ('dsp', 'DSP blocks'),
                     ('bits', 'Block memory bits'), ('regs', 'Registers')]:
        if k in summ:
            v = summ[k]
            if len(v) == 2:
                print(f'| {label} | {v[0]:,} | {v[1]:,} | {100 * v[0] / v[1]:.1f} |')
            else:
                print(f'| {label} | {v[0]:,} | | |')
    print()

    out_rows = []
    bad = 0
    for pat in a.node:
        rx = re.compile(pat)
        parents = [r for r in rows if rx.search(r['path'].rstrip('|'))]
        if not parents:
            print(f'no node matches {pat!r}', file=sys.stderr)
            bad += 1
            continue
        for p in parents:
            path = p['path'].rstrip('|')
            kids = sorted(children(rows, path), key=lambda r: -(r['alms'] or 0))
            print(f'## {path}\n')
            print('| Child | ALMs | Registers | M10K | DSP | Block bits |')
            print('|---|---|---|---|---|---|')
            print(f"| (own logic) | {p['alms_own'] or 0:,.1f} | {p['regs_own'] or 0:,.0f} | | | |")
            for k in kids:
                print(f"| {short(k['path'])} | {k['alms']:,.1f} | {k['regs']:,.0f} | "
                      f"{k['m10k']:,.0f} | {k['dsp']:,.0f} | {k['bits']:,.0f} |")
                out_rows.append({'parent': path, 'child': short(k['path']),
                                 **{c: k[c] for c in COLS}})
            print(f"| **total** | **{p['alms']:,.1f}** | **{p['regs']:,.0f}** | "
                  f"**{p['m10k']:,.0f}** | **{p['dsp']:,.0f}** | **{p['bits']:,.0f}** |\n")
            # reconciliation
            for c in ('alms', 'regs', 'm10k', 'dsp', 'bits'):
                own = p.get(c + '_own') or 0
                s = sum(k[c] or 0 for k in kids) + own
                if abs(s - (p[c] or 0)) > max(1.0, 0.002 * (p[c] or 0)):
                    print(f'RECONCILE {path} {c}: children+own {s:,.1f} != total {p[c]:,.1f}',
                          file=sys.stderr)
                    bad += 1
    if a.csv:
        with open(a.csv, 'w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=['parent', 'child', *COLS])
            w.writeheader()
            w.writerows(out_rows)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
