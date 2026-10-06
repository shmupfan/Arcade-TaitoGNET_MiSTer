#!/usr/bin/env python3
"""Verilator lint of PSX.sv (module emu) for one Quartus revision.

Takes the revision's VERILOG_MACRO lines, lints PSX.sv with the Verilog and
SystemVerilog sources it instantiates, and stands in empty modules for what
Verilator cannot read: VHDL entities (ports taken from the entity
declaration, rtl/**/*.vhd), Altera primitives and PLL IP (stub port lists
below). Only PSX.sv-level problems are of interest: widths are not checked
(-Wno-WIDTH; VHDL record and integer ports become wide vectors).

  tools/lint_psx.py GNET_Z1FULL [extra verilator args]
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = Path('/tmp') if False else ROOT / 'sim' / 'lint_psx'

SV_FILES = ['sys/hps_io.sv', 'sys/arcade_video.v', 'sys/math.sv', 'rtl/sdram.sv',
            'rtl/savestate_ui.sv', 'rtl/hps_ext.v', 'rtl/ddram.sv',
            'sys/hq2x.sv']   # module Hq2x (arcade_video's scandoubler, GNET_SHELL)
SV_GLOBS = ['rtl/gnet/*.sv', 'rtl/zoom/*.sv']   # rtl/zoom: zoom_mix (GNET_ZOOM)
# PLL wrappers: stubbed from their own module headers (the IP inside is not
# readable by Verilator)
PLL_FILES = ['rtl/pll/pll_0002.v', 'rtl/pll2/pll2_0002.v', 'rtl/gnet/pll_cpu.v', 'rtl/gnet/pll_vid_fixed.v']

# modules Verilator cannot read: hand-written port lists
HAND = {
    # defined in sys/sys_top.v (the top level, not linted)
    'sync_fix': 'module sync_fix(input clk, input sync_in, output sync_out); endmodule',
    'altddio_out': 'module altddio_out #(parameter extend_oe_disable="", intended_device_family="", '
                   'invert_output="", lpm_hint="", lpm_type="", oe_reg="", power_up_high="", width=1)'
                   '(input [width-1:0] datain_h, input [width-1:0] datain_l, input outclock, '
                   'input outclocken, input aclr, input aset, input oe, input sclr, input sset, '
                   'output [width-1:0] dataout, output oe_out); endmodule',
    'cyclonev_clkena': 'module cyclonev_clkena #(parameter clock_type="", ena_register_mode="")'
                       '(input inclk, input ena, output enaout, output outclk); endmodule',
    'pll_cfg': 'module pll_cfg(input mgmt_clk, input mgmt_reset, output mgmt_waitrequest, '
               'input mgmt_read, input mgmt_write, output [31:0] mgmt_readdata, input [5:0] mgmt_address, '
               'input [31:0] mgmt_writedata, output [63:0] reconfig_to_pll, input [63:0] reconfig_from_pll); endmodule',
}


def vhdl_entities():
    ents = {}
    for f in ROOT.glob('rtl/**/*.vhd'):
        t = f.read_text(errors='replace')
        t = re.sub(r'--[^\n]*', '', t)
        for m in re.finditer(r'\bentity\s+(\w+)\s+is\b(.*?)\bend\b', t, re.S | re.I):
            ents[m.group(1).lower()] = m.group(2)
    return ents


CASE = {}


def ports_of(body):
    m = re.search(r'\bport\s*\((.*)\)\s*;', body, re.S | re.I)
    if not m:
        return []
    out = []
    for decl in m.group(1).split(';'):
        if ':' not in decl:
            continue
        names, rest = decl.split(':', 1)
        rest = rest.strip()
        d = re.match(r'(in|out|inout|buffer)\b\s*(.*)', rest, re.S | re.I)
        if not d:
            continue
        dirn = {'in': 'input', 'out': 'output', 'inout': 'inout', 'buffer': 'output'}[d.group(1).lower()]
        typ = d.group(2).split(':=')[0].strip().lower()
        if re.match(r'std_logic\s*$', typ) or typ.startswith('std_ulogic') and '(' not in typ:
            w = ''
        else:
            w = '[255:0] '
        for n in names.split(','):
            n = n.strip()
            if n:
                out.append(f'{dirn} {w}{CASE.get(n.lower(), n)}')
    return out


def verilog_header(name):
    for f in PLL_FILES:
        t = (ROOT / f).read_text(errors='replace')
        m = re.search(r'\bmodule\s+' + name + r'\b.*?\);', t, re.S)
        if m:
            return m.group(0) + ' endmodule'
    return None


def stub(name, ents):
    if name in HAND:
        return HAND[name]
    h = verilog_header(name)
    if h:
        return h
    body = ents.get(name.lower())
    if body is None:
        return f'module {name}(); endmodule'
    gens = re.search(r'\bgeneric\s*\((.*?)\)\s*;\s*port\b', body, re.S | re.I)
    params = []
    if gens:
        for decl in gens.group(1).split(';'):
            if ':' in decl:
                for n in decl.split(':', 1)[0].split(','):
                    params.append(f'parameter {n.strip()} = 0')
    p = f' #({", ".join(params)})' if params else ''
    return f'module {name}{p}({", ".join(ports_of(body))}); endmodule'


def main():
    rev = sys.argv[1]
    extra = sys.argv[2:]
    qsf = (ROOT / f'{rev}.qsf').read_text()
    macros = sorted(set(re.findall(r'VERILOG_MACRO\s+"([^"]+)"', qsf)))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'build_id.v').write_text('`define BUILD_DATE "000000"\n')
    files = [str(ROOT / f) for f in SV_FILES]
    for g in SV_GLOBS:
        files += [str(p) for p in sorted(ROOT.glob(g))]
    ents = vhdl_entities()
    for n in re.findall(r'\.(\w+)\s*\(', (ROOT / 'PSX.sv').read_text(errors='replace')):
        CASE.setdefault(n.lower(), n)
    stubs = OUT / 'stubs.sv'
    have = set()
    for it in range(8):
        stubs.write_text('\n'.join(stub(n, ents) for n in sorted(have)) + '\n')
        cmd = ['verilator', '--lint-only', '-Wno-fatal', '-Wno-WIDTH', '-Wno-PINMISSING',
               '-Wno-DECLFILENAME', '-Wno-UNUSED', '-Wno-PINCONNECTEMPTY', '-Wno-PROCASSWIRE', '-Wno-TIMESCALEMOD',
               f'-I{ROOT}', f'-I{ROOT}/sys', f'-I{ROOT}/rtl', f'-I{OUT}', '--top-module', 'emu'] + \
              [f'-D{m}' for m in macros] + extra + [str(ROOT / 'PSX.sv')] + files + [str(stubs)]
        r = subprocess.run(cmd, capture_output=True, text=True)
        miss = set(re.findall(r"Cannot find file containing module: '(\w+)'", r.stderr))
        if not miss - have:
            break
        have |= miss
    lines = [l for l in r.stderr.splitlines() if l.startswith('%')]
    psx = [l for l in lines if 'PSX.sv' in l or 'Error' in l]
    print(f'{rev}: {len(macros)} macros, {len(have)} stubbed modules ({", ".join(sorted(have))})')
    print('\n'.join(psx) if psx else 'no warnings or errors in PSX.sv')
    sys.exit(1 if any('%Error' in l for l in lines) else 0)


if __name__ == '__main__':
    main()
