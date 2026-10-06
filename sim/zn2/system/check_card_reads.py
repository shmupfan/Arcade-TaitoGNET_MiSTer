#!/usr/bin/env python3
"""Check every ATA data port read of a system simulation (zn.log) against
the card image: task file writes give the LBA (LBA mode) and the sector
count, READ SECTORS (20h) starts a transfer, and each read of the data
port at 0x1FB00000 must return the next byte (byte read, the 8-bit mode the
BIOS uses for its first sectors) or the next little-endian word (16-bit
read) of the image. This checks the card path end to end (memorymux, zn2_board, gnet_fc
in Verilator, zn2_cardmem, the DDR3 arbiter and the model).

    check_card_reads.py <zn.log> <card.img>
"""
import sys


def main(log, img):
    data = open(img, "rb").read()
    regs = {}
    pos = None      # byte offset of the next byte
    left = 0        # bytes left in the transfer
    ok = bad = cmds = 0
    for line in open(log):
        p = line.split()
        if len(p) < 7:
            continue
        we = p[1] == "'1'"
        a, be, wd, rd = int(p[2], 16), int(p[3], 16), int(p[4], 16), int(p[6], 16)
        if not (0x1FB00000 <= a <= 0x1FB00007):
            continue
        if we:
            for b in range(4):
                if (be >> b) & 1:
                    off = (a & 7) + b
                    v = (wd >> (8 * b)) & 0xFF
                    regs[off] = v
                    if off == 7 and v == 0x20:
                        lba = regs.get(3, 0) | regs.get(4, 0) << 8 | regs.get(5, 0) << 16 | (regs.get(6, 0) & 15) << 24
                        n = regs.get(2, 0) or 256
                        pos, left = lba * 512, n * 512
                        cmds += 1
        elif a == 0x1FB00000 and be in (0x1, 0x3) and left > 0:
            if be == 0x3:
                exp, got, n = data[pos] | data[pos + 1] << 8, rd & 0xFFFF, 2
            else:
                exp, got, n = data[pos], rd & 0xFF, 1
            if got == exp:
                ok += 1
            else:
                bad += 1
                if bad <= 5:
                    print(f"{p[0]} us: card byte {pos:#x} core {got:x} image {exp:x}")
            pos += n
            left -= n
    print(f"READ SECTORS commands {cmds}, data reads checked {ok + bad}: match {ok}, mismatch {bad}")
    return bad == 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(0 if main(*sys.argv[1:]) else 1)
