#!/usr/bin/env python3
"""Apply exact-substring edits to an RTL file, asserting each match count.
Usage: imported; edits(path, [(old, new, count), ...])."""
def edits(path, rules):
    t = open(path, encoding='latin-1').read()
    for old, new, n in rules:
        c = t.count(old)
        assert c == n, f'{path}: expected {n} of {old!r}, found {c}'
        t = t.replace(old, new)
    open(path, 'w', encoding='latin-1').write(t)
    print(f'{path}: {len(rules)} edits')
