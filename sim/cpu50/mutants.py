#!/usr/bin/env python3
"""Negative controls for tb_cpu_split: write a mutated copy of one
rtl/gnet/cpu_split file; the bench must report errors with it.

    mutants.py <name> <rtl/gnet/cpu_split dir> <out dir>

Names:
  gpu_nostall   GPU proxy takes read data in the cycle after the read even
                while gpu.vhd's bus_stall is high
  spu_nostall   SPU read: no stall to memorymux (data taken before it crossed)
  gpu_noquiet   gpu_dmaRequest not held low after traffic (quiet window 0)
  rst_noorder   reset pulse not held back behind a same-cycle SS_reset (not
                in run.sh neg: with SS_reset and reset one clk1x cycle apart,
                29.5 ns, the two pulses cannot reach clk_cpu in one cycle, so
                the hold-back is defensive and no valid stimulus exercises it)
  fill_noce     zero fill writes RAM without waiting for ram_done
"""
import shutil
import sys

MUT = {
    'gpu_nostall': ('cpu_gpu_bridge.vhd',
                    "               if p_bus_stall = '0' then\n",
                    "               if true then\n"),
    'spu_nostall': ('cpu_spu_bridge.vhd',
                    "   c_bus_stall     <= c_bus_read and not rd_ready;\n",
                    "   c_bus_stall     <= '0';\n"),
    'gpu_noquiet': ('cpu_gpu_bridge.vhd',
                    "                     '1'        when (dreq_sync(0) = '1' and quiet_cnt = 0) else\n",
                    "                     '1'        when (dreq_sync(0) = '1') else\n"),
    'rst_noorder': ('cpu_reset_fill.vhd',
                    "            if ss_pulse = '1' then\n",
                    "            if false then\n"),
    'fill_noce': ('cpu_reset_fill.vhd',
                  "               if ram_done = '1' then\n",
                  "               if true then\n"),
}


def main():
    name, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
    f, old, new = MUT[name]
    for g in ('cpu_gpu_bridge.vhd', 'cpu_spu_bridge.vhd', 'cpu_reset_fill.vhd', 'cpu_split.vhd'):
        shutil.copy(f'{src}/{g}', f'{dst}/{g}')
    t = open(f'{src}/{f}').read()
    assert t.count(old) == 1, (name, old)
    open(f'{dst}/{f}', 'w').write(t.replace(old, new))


if __name__ == '__main__':
    main()
