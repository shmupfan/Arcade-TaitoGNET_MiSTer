#!/usr/bin/env python3
"""Rewrite to_unsigned(<expr>, <N>) as to_unsigned((<expr>) mod 2**<N>, <N>)
for simulation copies (sim/m1/build.sh). Handles nested parentheses."""
import re
import sys

src = open(sys.argv[1]).read()
out, i = [], 0
for m in re.finditer(r'to_unsigned\(', src):
    if m.start() < i:
        continue
    j, depth, comma = m.end(), 1, None
    while depth:
        c = src[j]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        elif c == ',' and depth == 1:
            comma = j
        j += 1
    expr, width = src[m.end():comma], src[comma + 1:j - 1].strip()
    out.append(src[i:m.start()])
    if re.fullmatch(r'\d+', width) and 'mod' not in expr:
        out.append(f'to_unsigned(({expr.strip()}) mod 2**{width}, {width})')
    else:
        out.append(src[m.start():j])
    i = j
out.append(src[i:])
sys.stdout.write(''.join(out))
