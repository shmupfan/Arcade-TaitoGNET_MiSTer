#!/usr/bin/env python3
"""Render a VRAM dump of tb_zn2_system (2 MB, 1024 x 1024 16-bit pixels,
the DDR3 layout of gpu.vhd with VRAM_Y_BITS = 10) as a PNG of the whole
VRAM, to look at what the BIOS has drawn.

    vram_png.py <vram_N.bin> <out.png>
"""
import sys

import numpy as np
from PIL import Image


def main(src, out):
    v = np.fromfile(src, dtype="<u2")[:1024 * 1024].reshape(1024, 1024)
    r = (v & 31) << 3
    g = ((v >> 5) & 31) << 3
    b = ((v >> 10) & 31) << 3
    Image.fromarray(np.dstack([r, g, b]).astype(np.uint8)).save(out)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
