#!/usr/bin/env python3
"""Post-process the GHDL Verilog netlist for Verilator (docs/fullsys_sim.md W8).

GHDL writes a VHDL signal that has an initial value and a concurrent
assignment as
    always @*
      x = y; // (isignal)
    initial
      x = <init>;
In Verilog an "always @*" waits for a change of y, so when y is constant
(a trimmed port, a constant output of a sub-block) x keeps <init> forever.
VHDL runs every concurrent assignment once at time 0, so x = y from the
start. Example: savestates drives ddr3_BURSTCNT with x"01"; psx_top's copy
(ss_ram_BURSTCNT, init 0) stayed 0 and the reset sequencer waited for a
DDR3 read that never returned. Every "always @*" becomes "always_comb"
(evaluated at time 0) and the initial of an isignal is dropped.

    fix_netlist.py <netlist.v>     (in place)
"""
import re, sys

fn = sys.argv[1]
t = open(fn).read()
t, n1 = re.subn(r'  always @\*\n    (\S+) = ([^;]+); // \(isignal\)\n  initial\n    \1 = [^;]+;\n',
                r'  always_comb\n    \1 = \2; // (isignal)\n', t)
t, n2 = re.subn(r'always @\*', 'always_comb', t)
open(fn, 'w').write(t)
print(f'fix_netlist: {n1} isignal initials dropped, {n1 + n2} always_comb')
