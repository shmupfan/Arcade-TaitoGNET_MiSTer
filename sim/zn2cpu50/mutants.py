#!/usr/bin/env python3
"""Negative controls for sim/zn2cpu50 (docs/r1_cpu_domain_design.md, "ZN-2
layer in the CPU group"): write mutated copies of rtl/gnet/zn2_cdc.vhd and
rtl/gnet/zn2_ch3_arb.vhd into an output directory. Each mutant must make its
bench report errors.

    mutants.py <mutant> <rtl/gnet dir> <out dir>

  stale_ack       zn2_cdc acknowledges an answer that belongs to a request from
                  before a zn2_board reset (gnet_ata gets an ack it did not ask for)
  ld_every_cycle  zn2_cdc pops a loader word every cycle (zn2_board's byte
                  split needs one free cycle after each word)
  no_hold         zn2_cdc goes back to idle right after the ack, without
                  waiting for gnet_ata to drop its request (the request still
                  high in the next cycle is sent a second time)
  no_gap          zn2_ch3_arb starts the next request in the cycle after a
                  ready (a ready that lasts two cycles then completes it)
  ready_swap      zn2_ch3_arb answers a download with the flash port's ready
  ld_ignore_busy  no RTL change; run.sh runs the bench with LD_STRESS=2, a
                  loader that ignores p_ld_busy (ioctl_wait), which must
                  overflow the FIFO
"""
import sys

MUT = {
    "stale_ack": ("zn2_cdc.vhd",
                  "if (c_stale = '0' and c_board_rst = '0') then",
                  "if (true) then"),
    "ld_every_cycle": ("zn2_cdc.vhd",
                       "ld_pop <= '1' when (ld_empty = '0' and ld_wr_r = '0') else '0';",
                       "ld_pop <= '1' when (ld_empty = '0') else '0';"),
    "no_hold": ("zn2_cdc.vhd",
                "                     cs        <= C_HOLD;",
                "                     cs        <= C_IDLE;"),
    "no_gap": ("zn2_ch3_arb.vhd",
               "            when GAP =>\n               state <= IDLE;",
               "            when GAP =>\n               state <= IDLE;"),
    "ld_ignore_busy": ("none", "", ""),
    "ready_swap": ("zn2_ch3_arb.vhd",
                   "                  a_ready <= '1';",
                   "                  b_ready <= '1';"),
}


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in MUT:
        sys.exit(__doc__)
    name, src, out = sys.argv[1:]
    for f in ("zn2_cdc.vhd", "zn2_ch3_arb.vhd"):
        s = open(f"{src}/{f}").read()
        mf, old, new = MUT[name]
        if f == mf:
            if name == "no_gap":
                # every answer goes straight back to IDLE
                old2 = "                  state   <= GAP;"
                assert s.count(old2) == 3, name
                s = s.replace(old2, "                  state   <= IDLE;")
            else:
                assert s.count(old) == 1, name
                s = s.replace(old, new)
        open(f"{out}/{f}", "w").write(s)


if __name__ == "__main__":
    main()
