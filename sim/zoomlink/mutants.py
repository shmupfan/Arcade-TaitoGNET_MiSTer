#!/usr/bin/env python3
"""Negative controls for sim/zoomlink (docs/zoom_board_design.md 14): write
mutated copies of rtl/gnet/zoom_cdc.vhd and rtl/gnet/zoom_sdram_link.vhd into
an output directory. Each mutant must make tb_zoom_cdc report errors.

    mutants.py list
    mutants.py <mutant> <rtl/gnet dir> <out dir>

  word_swap    zoom_sdram_link returns the two 32-bit words of a line swapped
  no_hit_gate  zoom_cdc passes requests for addresses zoom_board does not
               decode to the board (zoom_host would never answer them)
  zrst_init0   zoom_cdc's reset synchroniser starts at 0: the Zoom would run
               for a few cycles after configuration
  stale_line   zoom_sdram_link delivers the answer to a line requested before
               a zoom_board reset (zoom_memarb gets an rvalid it did not ask for)
  stale_host   zoom_cdc acknowledges an answer that belongs to a request from
               before a zn2_board reset (memorymux gets an ack it did not ask for)
  start_in_reset  zoom_cdc starts a pending host request while zn2_board's
               reset is high (found by tb_zoom_cdc seed 3 with resets: the
               answer to a request the bus had dropped was acknowledged)
"""
import sys

MUT = {
    "word_swap": ("zoom_sdram_link.vhd", "f_rsp <= c_fl_dout & f_lo;", "f_rsp <= f_lo & c_fl_dout;"),
    "no_hit_gate": ("zoom_cdc.vhd", "p_h_req   <= p_valid and (not p_board_rst) and p_h_hit;",
                    "p_h_req   <= p_valid and (not p_board_rst);"),
    "zrst_init0": ("zoom_cdc.vhd", "generic map (WIDTH => 1, INIT => '1',", "generic map (WIDTH => 1, INIT => '0',"),
    "stale_line": ("zoom_sdram_link.vhd", "p_m_rvalid <= l_done and (not l_stale);", "p_m_rvalid <= l_done;"),
    "start_in_reset": ("zoom_cdc.vhd", "c_busy = '0' and c_board_rst = '0') else '0';", "c_busy = '0') else '0';"),
    "stale_host": ("zoom_cdc.vhd", "if (c_stale = '0' and c_board_rst = '0') then", "if (true) then"),
}


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "list":
        print(" ".join(MUT))
        return
    if len(sys.argv) != 4 or sys.argv[1] not in MUT:
        sys.exit(__doc__)
    name, src, out = sys.argv[1:]
    mf, old, new = MUT[name]
    for f in ("zoom_cdc.vhd", "zoom_sdram_link.vhd"):
        s = open(f"{src}/{f}").read()
        if f == mf:
            assert s.count(old) == 1, name
            s = s.replace(old, new)
        open(f"{out}/{f}", "w").write(s)


if __name__ == "__main__":
    main()
