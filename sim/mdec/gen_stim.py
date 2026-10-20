#!/usr/bin/env python3
"""MDEC stimulus for sim/mdec/run.sh (tb_mdec_equiv.vhd).

Writes <out>.stim and prints the number of 32-bit result words the MDEC must
return. Stimulus lines: "W <hex>" is a word for the MDEC data port (DMA0),
"S <n>" makes the writer wait until the reader (DMA1) has <n> result words,
as software waits for DecDCTout before it sends the next command.

  gen_stim.py random SEED NMB OUT   random command stream: standard and
                                     random scale tables, random quant
                                     tables, NMB decode commands in all four
                                     depths (4, 8, 15, 24 bit) with random
                                     run-level data, some of it saturating
  gen_stim.py dc OUT                 one mono 8-bit block, DC only (hand
                                     result: every pixel 0x8C)
  gen_stim.py mono SEED NBLK OUT     NBLK mono 8-bit blocks; also writes
                                     OUT.expect from the model below

The model in idct_mono() restates the rtl/mdec.vhd arithmetic (RL decode,
dequantise, zigzag, two-pass IDCT with the 30-bit temp table and
idct_sum(48 downto 32), clip, +128) for the mono 8-bit path only.
"""
import random
import sys

SCALE_STD = [
    0x5A82, 0x5A82, 0x5A82, 0x5A82, 0x5A82, 0x5A82, 0x5A82, 0x5A82,
    0x7D8A, 0x6A6D, 0x471C, 0x18F8, 0xE707, 0xB8E3, 0x9592, 0x8275,
    0x7641, 0x30FB, 0xCF04, 0x89BE, 0x89BE, 0xCF04, 0x30FB, 0x7641,
    0x6A6D, 0xE707, 0x8275, 0xB8E3, 0x471C, 0x7D8A, 0x18F8, 0x9592,
    0x5A82, 0xA57D, 0xA57D, 0x5A82, 0x5A82, 0xA57D, 0xA57D, 0x5A82,
    0x471C, 0x8275, 0x18F8, 0x6A6D, 0x9592, 0xE707, 0x7D8A, 0xB8E3,
    0x30FB, 0x89BE, 0x7641, 0xCF04, 0xCF04, 0x7641, 0x89BE, 0x30FB,
    0x18F8, 0xB8E3, 0x6A6D, 0x8275, 0x7D8A, 0x9592, 0x471C, 0xE707,
]

ZIGZAG = [
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
]


def s16(v):
    return v - 0x10000 if v & 0x8000 else v


def s10(v):
    return v - 0x400 if v & 0x200 else v


def resize_signed(v, n):
    # numeric_std resize to a narrower signed: sign bit kept, low n-1 bits kept
    low = v & ((1 << (n - 1)) - 1)
    return low - (1 << (n - 1)) if v < 0 else low


def trunc_div(a, b):
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def scale_cmd(table):
    words = [0x60000000]
    for i in range(0, 64, 2):
        words.append((table[i] & 0xFFFF) | ((table[i + 1] & 0xFFFF) << 16))
    return words


def quant_cmd(lum, chrom):
    words = [0x40000001]
    data = list(lum) + list(chrom)
    for i in range(0, 128, 4):
        words.append(data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24))
    return words


def rand_block(rng, big=False):
    """Halfwords of one block: (qscale, dc) header, (run, level) pairs, EOB."""
    q = rng.randrange(64)
    lim = 512 if big else rng.choice([16, 64, 512])
    hw = [(q << 10) | (rng.randrange(-lim, lim) & 0x3FF)]
    coeff = 0
    for _ in range(rng.randrange(0 if not big else 10, 30)):
        run = rng.choice([0, 0, 0, 1, 2, rng.randrange(8)])
        if coeff + run + 1 >= 63:
            break
        coeff += run + 1
        hw.append((run << 10) | (rng.randrange(-lim, lim) & 0x3FF))
    hw.append(0xFE00)
    return hw


def decode_cmd(depth, blocks_hw, signed=0, bit15=0):
    hw = [h for b in blocks_hw for h in b]
    if len(hw) % 2:
        hw.append(0xFE00)
    data = [hw[i] | (hw[i + 1] << 16) for i in range(0, len(hw), 2)]
    head = 0x20000000 | (depth << 27) | (signed << 26) | (bit15 << 25) | len(data)
    return [head] + data


def out_words(depth, nblocks):
    if depth & 2:
        mb = nblocks // 6
        return mb * (192 if depth == 2 else 128)
    return nblocks * (8 if depth == 0 else 16)


def idct_mono(block_hw, quant, scale):
    """rtl/mdec.vhd arithmetic, one mono block -> 64 pixel bytes."""
    inp = [0] * 64
    head = block_hw[0]
    qscale = head >> 10
    entries = [(0, s10(head & 0x3FF))]
    coeff = 0
    for h in block_hw[1:]:
        coeff = coeff + (h >> 10) + 1
        if coeff >= 63:
            break
        entries.append((coeff, s10(h & 0x3FF)))
    for c, d in entries:
        if qscale == 0:
            v = d * 2
            idx = c
        else:
            v = d * quant[c]
            if c > 0:
                v = trunc_div(v * qscale + 4, 8)
            idx = ZIGZAG[c]
        inp[idx] = max(-1024, min(1023, v))
    sc = [s16(v) for v in scale]
    temp = [0] * 64
    for x in range(8):
        for y in range(8):
            s = sum(inp[u * 8 + x] * sc[u * 8 + y] for u in range(8))
            temp[x + y * 8] = resize_signed(s, 30)
    out = [0] * 64
    for x in range(8):
        for y in range(8):
            s = sum(temp[u + y * 8] * sc[u * 8 + x] for u in range(8))
            out[x + y * 8] = max(-128, min(127, s >> 32)) + 128
    return out


def write(path, words):
    with open(path, "w") as f:
        for w in words:
            if isinstance(w, tuple):
                f.write("S %d\n" % w[1])
            else:
                f.write("W %08X\n" % (w & 0xFFFFFFFF))


def write_expect(path, words):
    with open(path, "w") as f:
        for w in words:
            f.write("%08X\n" % w)


def main():
    mode = sys.argv[1]
    words = [x for x in scale_cmd(SCALE_STD)]
    if mode == "dc":
        out = sys.argv[2]
        words += quant_cmd([2] * 64, [2] * 64)
        words += decode_cmd(1, [[(1 << 10) | 50, 0xFE00]])
        write(out + ".stim", words)
        write_expect(out + ".expect", [0x8C8C8C8C] * 16)
        print(16)
    elif mode == "mono":
        seed, nblk, out = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
        rng = random.Random(seed)
        quant = [rng.randrange(1, 64) for _ in range(64)]
        words += quant_cmd(quant, quant)
        blocks = [rand_block(rng) for _ in range(nblk)]
        words += decode_cmd(1, blocks)
        exp = []
        for b in blocks:
            px = idct_mono(b, quant, SCALE_STD)
            exp += [px[i] | (px[i + 1] << 8) | (px[i + 2] << 16) | (px[i + 3] << 24) for i in range(0, 64, 4)]
        write(out + ".stim", words)
        write_expect(out + ".expect", exp)
        print(len(exp))
    elif mode == "random":
        seed, nmb, out = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
        rng = random.Random(seed)
        nout = 0
        for i in range(nmb):
            if i % 4 == 0:
                if rng.random() < 0.3:
                    words += scale_cmd([rng.randrange(0x10000) for _ in range(64)])
                elif rng.random() < 0.5:
                    words += scale_cmd(SCALE_STD)
                words += quant_cmd([rng.randrange(256) for _ in range(64)],
                                   [rng.randrange(256) for _ in range(64)])
            depth = rng.randrange(4)
            big = rng.random() < 0.2
            nb = (6 * rng.randrange(1, 3)) if depth & 2 else rng.randrange(1, 5)
            words += decode_cmd(depth, [rand_block(rng, big) for _ in range(nb)],
                                rng.randrange(2), rng.randrange(2))
            nout += out_words(depth, nb)
            words.append(("S", nout))
        write(out + ".stim", words)
        print(nout)
    else:
        sys.exit("mode: random | dc | mono")


if __name__ == "__main__":
    main()
