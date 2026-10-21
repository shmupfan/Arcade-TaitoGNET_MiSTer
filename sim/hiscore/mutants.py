#!/usr/bin/env python3
"""Negative controls for the high score bench: copies of gnet_hiscore.sv with
one safeguard removed each. Every mutant must make tb_hs.sv FAIL.

  sim/hiscore/mutants.py <gnet_hiscore.sv> <outdir>
writes <outdir>/<name>/gnet_hiscore.sv and <outdir>/<name>/args (plusargs).
"""
import sys
from pathlib import Path

MUTANTS = {
    # restore checks see entry 0's real start byte at once: a restore lands
    # in the old table left in SDRAM and the game's defaults overwrite it
    'no_gate': ("wire       falsify = dump_loaded & ~restored & ~seen_clear & e0_here;",
                "wire       falsify = 1'b0;", ''),
    # snapshots before the game's own table is in RAM
    'no_fresh': ("wire        h_osd = OSD_STATUS & fresh;",
                 "wire        h_osd = OSD_STATUS;", ''),
    # game RAM writes without waiting for the paused core
    'no_pause_wait': ("wire acc_ok    = ch3_free & ~ioctl_download & (~acc_pause | core_paused);",
                      "wire acc_ok    = ch3_free & ~ioctl_download;", ''),
    # a load takes the dump without the marker
    'no_marker': ("wire        nv_ok = t0_ok & t1_ok & configured & e0_ok;",
                  "wire        nv_ok = configured & e0_ok;", '+old'),
    # the snapshot's own request goes out although the upload carries it
    'no_req_suppress': ("\t\tif (~ul_nv | ul_past) upload_req <= 1'b1;", "\t\tupload_req <= 1'b1;", ''),
    # byte writes with all four byte enables
    'all_byte_enables': ("m_be    <= need_wr ? (4'b0001 << r_addr[1:0]) : 4'b1111;",
                         "m_be    <= 4'b1111;", ''),
}

src = Path(sys.argv[1]).read_text()
out = Path(sys.argv[2])
# an upload reads the marker and the dump while a snapshot is still running:
# both holds removed (either one alone covers the other, as the upload
# reaches the marker first)
HOLDS = [("\t\t\t\t\tif (~ex_busy & ce) begin", "\t\t\t\t\tif (ce) begin", ''),
         ("\t\t\t\t\tif (~ex_busy) begin", "\t\t\t\t\tif (1'b1) begin", '')]
MUTANTS['no_area_hold'] = None
for name, m in MUTANTS.items():
    edits = HOLDS if m is None else [m]
    text = src
    for old, new, args in edits:
        if text.count(old) != 1:
            sys.exit(f'mutants: {name}: pattern found {text.count(old)} times')
        text = text.replace(old, new)
    d = out / name
    d.mkdir(parents=True, exist_ok=True)
    (d / 'gnet_hiscore.sv').write_text(text)
    (d / 'args').write_text(edits[0][2] + '\n')
print('mutants: ' + ', '.join(MUTANTS))
