#!/usr/bin/env python3
"""Negative controls for the gnet_ddr3_flcopy bench (docs/i12_ddr3_load.md
6.1): each mutant is a copy of rtl/gnet/gnet_ddr3_flcopy.sv with one fault,
built and run with run.sh flcopy; every one must FAIL.
Not a mutant: skipping the ACK state (job_ack == job) passes, as it must:
with aligned clocks the clk2x edge in the middle of the start clk1x cycle
clears rcv before the first CHECK. The state is kept as a margin.

  sim/ddr3arb/flcopy_mutants.py [seed busy lat jit]
"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'rtl', 'gnet', 'gnet_ddr3_flcopy.sv')
MUTANTS = {
    'no_room_check': ('room   = (req - cons + bc) <= 21\'(DEPTH);', 'room   = 1\'b1;'),
    'high_half_from_low': ('w_data   <= q[63:32];', 'w_data   <= q[31:0];'),
    'drop_cmd_on_busy': ('if (g_rd && g_busy) begin', 'if (1\'b0) begin'),
    'odd_tail_extra_word': ('if (hi_ok) st <= W1;', 'if (1\'b1) st <= W1;'),
    'readback_ignores_data': ('sum_sdram <= sum_sdram + r_data;', 'sum_sdram <= sum_sdram + w_data;'),
    'ddr3_reread_skips_high': ("sum_ddr3 <= sum_ddr3 + q[31:0] + (hi_ok ? q[63:32] : 32'd0);", "sum_ddr3 <= sum_ddr3 + q[31:0];"),
}
args = sys.argv[1:] or ['3', '40', '40', '40']
src = open(SRC).read()
bad = 0
for name, (a, b) in MUTANTS.items():
    assert src.count(a) == 1, name
    d = os.path.join(HERE, 'obj_mut_' + name)
    os.makedirs(d, exist_ok=True)
    f = os.path.join(d, 'gnet_ddr3_flcopy.sv')
    open(f, 'w').write(src.replace(a, b))
    env = dict(os.environ, FLC_SRC=f, FLC_OBJ='obj_mut_' + name + '/obj')
    r = subprocess.run(['perl', '-e', 'alarm 900; exec @ARGV', os.path.join(HERE, 'run.sh'), 'flcopy'] + args,
                       env=env, capture_output=True, text=True)
    last = [l for l in r.stdout.splitlines() if l.startswith('seed')] or ['(no summary: killed or hung, rc %d)' % r.returncode]
    errs = [l for l in r.stdout.splitlines() if l.startswith('ERROR')][:2]
    caught = r.returncode != 0
    bad += not caught
    print(f'{name}: {"caught" if caught else "NOT CAUGHT"}: {last[-1]}')
    for e in errs:
        print('   ', e)
sys.exit(1 if bad else 0)
