#!/usr/bin/env python3
"""Negative controls for the issue #9 bench: copies of gnet_card_journal.sv
with one fault each. sim/i9/run.sh builds each one and expects tb_cj to FAIL.

  sim/i9/mutants.py <gnet_card_journal.sv> <outdir>
"""
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text()
out = Path(sys.argv[2])

MUTANTS = {
    # upload words not stalled: Main reads before the DDR3 line is there
    'nostall': [('assign ul_wait   = u_act & ~(q_valid & (q_addr == ioctl_addr));',
                 'assign ul_wait   = 1\'b0;')],
    # no EEPROM mirror at the end of the file
    'nomirror': [('wire        u_inee   = (a1 < 27\'d2048) || ((a1 >= 27\'(A_MIR)) && (a1 < 27\'(A_END)));',
                  'wire        u_inee   = (a1 < 27\'d2048);')],
    # a card write during an upload does not ask again
    'norearm': [('            dirty       <= 1\'b1;\n        end else if (req_take) begin',
                 '            if (!u_act) dirty <= 1\'b1;\n        end else if (req_take) begin')],
    # crossing: hunk captured on the edge that first samples the toggle
    'earlyhold': [('    wire         ev_seen = cdc_rx_s2 ^ ev_q;',
                   '    wire         ev_seen = cdc_rx_s2 ^ ev_q;\n    logic [13:0] h_early = \'0;\n'
                   '    always_ff @(posedge clk) if (ev_tog != cdc_rx_s1) h_early <= ev_hunk;'),
                  ('            cdc_rx_hold <= ev_hunk;', '            cdc_rx_hold <= h_early;')],
    # the journal is not replayed into the card at load
    'noreplay': [('    assign slot_wr   = ioctl_wr & dl6 & d_inslot & ({1\'b0, d_slot} < cnt);',
                  '    assign slot_wr   = 1\'b0;')],
    # directory entries accepted without the GNCJ and complement check
    'nodircheck': [("                2'd3: if (dw0 == 16'h4E47 && dw1 == 16'h4A43 && dw2[15:14] == 2'b00 &&\n"
                    "                          ioctl_dout == ~dw2 && {1'b0, d_entry} == cnt && cnt < 7'(SLOTS)) begin",
                    "                2'd3: if ({1'b0, d_entry} == cnt && cnt < 7'(SLOTS)) begin")],
    # a new card image (index 5) does not empty the list
    'noclear5': [('        if ((dl5 && !dl5_q) || (dl6 && !dl6_q)) begin',
                  '        if (dl6 && !dl6_q) begin')],
    # every write appends, rewritten hunks are listed twice
    'nodedupe': [('            end else if (list[s_i[5:0]] == s_h) begin',
                  '            end else if (1\'b0) begin')],
}

for name, edits in MUTANTS.items():
    t = src
    for a, b in edits:
        if t.count(a) != 1:
            sys.exit(f'mutants: {name}: pattern found {t.count(a)} times: {a[:60]}')
        t = t.replace(a, b)
    d = out / name
    d.mkdir(parents=True, exist_ok=True)
    (d / 'gnet_card_journal.sv').write_text(t)
print('mutants: ' + ' '.join(MUTANTS))
