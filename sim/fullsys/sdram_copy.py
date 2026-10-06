#!/usr/bin/env python3
"""Verilator copy of rtl/sdram.sv for the full-system simulation
(docs/fullsys_sim.md W7). Controller logic unchanged; mechanical edits:

1. inout SDRAM_DQ splits into SDRAM_DQ (output) and SDRAM_DQ_IN (input);
   the one read (dq_reg <= SDRAM_DQ) uses SDRAM_DQ_IN. The SDRAM chip is a
   C++ model in the harness.
2. the altddio_out clock buffer becomes assign SDRAM_CLK = ~clk.
3. 'Z fills become 0 (only reached with SDRAM_EN = 0, never in the core).

    sdram_copy.py <rtl/sdram.sv> <out.sv>
"""
import re, sys

src, dst = sys.argv[1], sys.argv[2]
t = open(src).read()
n = 0
t, k = re.subn(r"inout\s+reg\s+\[15:0\]\s+SDRAM_DQ,",
               "output reg [15:0]  SDRAM_DQ,\n\tinput      [15:0]  SDRAM_DQ_IN,", t); n += k
t, k = re.subn(r"dq_reg <= SDRAM_DQ;", "dq_reg <= SDRAM_DQ_IN;", t); n += k
t, k = re.subn(r"altddio_out\s*#\(.*?\);\s*\n", "assign SDRAM_CLK = ~clk; // altddio_out (datain_h 0, datain_l 1)\n", t, flags=re.S); n += k
t = t.replace("16'bZ", "16'b0").replace("<= 'Z;", "<= '0;")
if n != 3:
    sys.exit(f"sdram_copy: {n} of 3 edits applied, sdram.sv changed?")
open(dst, "w").write(t)
