#!/usr/bin/env python3
"""Reader and summary for glue traces (tools/mame/glue_trace.lua).

  glue_trace.py summary <glue.zst> [--max N]
  glue_trace.py dump <glue.zst> [--t0 S] [--t1 S] [--lo ADDR] [--hi ADDR] [--max N]
"""
import argparse
import collections
import struct
import subprocess

REC = struct.Struct("<BdIIIId")
KIND = "RWXE"


def records(path):
    p = subprocess.Popen(["zstd", "-dc", path], stdout=subprocess.PIPE, bufsize=1 << 20)
    hdr = p.stdout.read(4 + 4 + 16 + 1)
    assert hdr[:4] == b"GNGT", hdr[:4]
    setname = hdr[8:24].rstrip(b"\0").decode()
    jp1 = hdr[24]
    yield ("hdr", setname, jp1)
    n = REC.size
    while True:
        b = p.stdout.read(n * 4096)
        if not b:
            break
        for i in range(0, len(b) - n + 1, n):
            yield REC.unpack_from(b, i)


def region(a):
    if 0x1f000000 <= a < 0x1f800000:
        return "flash"
    if 0x1fb00000 <= a < 0x1fb10000:
        o = a - 0x1fb00000
        return "exca" if o >= 0x3e0 else "ata"
    return {0x1fa30000: "ctrl3", 0x1fb40000: "ctrl", 0x1fb60000: "ctrl2", 0x1fb70000: "gn1fb7"}.get(a & ~3, "?")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd"); ap.add_argument("path")
    ap.add_argument("--t0", type=float, default=0); ap.add_argument("--t1", type=float, default=1e9)
    ap.add_argument("--lo", type=lambda s: int(s, 0), default=0); ap.add_argument("--hi", type=lambda s: int(s, 0), default=0xffffffff)
    ap.add_argument("--max", type=int, default=10 ** 12)
    a = ap.parse_args()
    it = records(a.path)
    print("header", next(it))
    if a.cmd == "dump":
        n = 0
        for k, t, ad, v, mk, c, tl in it:
            if t < a.t0 or ad < a.lo or ad > a.hi:
                continue
            if t > a.t1 or n >= a.max:
                break
            print(f"{t:.9f} {KIND[k]} {ad:08x} {v:08x} {mk:08x} x{c} {tl:.9f} {region(ad)}")
            n += 1
        return
    cnt = collections.Counter(); acc = collections.Counter(); masks = collections.Counter()
    for r in it:
        k, t, ad, v, mk, c, tl = r
        if k >= 2:
            print("event", KIND[k], t, c)
            continue
        rg = region(ad)
        cnt[(rg, KIND[k])] += 1
        acc[(rg, KIND[k])] += c
        masks[(rg, KIND[k], mk)] += c
    for key in sorted(cnt):
        print(key, "records", cnt[key], "accesses", acc[key])
    for key, n in sorted(masks.items()):
        print("mask", key[0], key[1], f"{key[2]:08x}", n)


if __name__ == "__main__":
    main()
