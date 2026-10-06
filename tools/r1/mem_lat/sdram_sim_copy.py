#!/usr/bin/env python3
"""Make a simulation copy of rtl/sdram.sv that NVC can elaborate inside a VHDL
testbench. The controller logic is not changed; the edits are mechanical:

1. module-level localparam/wire/reg declarations move above their first use
   (NVC's Verilog front end needs declaration before use);
2. the altddio_out SDRAM clock buffer becomes `assign SDRAM_CLK = ~clk`
   (datain_h 0, datain_l 1: the inverted clock it produces);
3. `'Z` fill literals become `{16{1'bz}}` (SDRAM_EN = 1 in the core, so that
   branch never runs);
4. the inout SDRAM_DQ splits into SDRAM_DQ (output) and SDRAM_DQ_IN (input),
   because NVC only supports in and out ports across the language boundary;
   the one read (`dq_reg <= SDRAM_DQ`) uses SDRAM_DQ_IN;
5. a new output idx_o shows clk3xIndex to the testbench;
6. registers without an initial value start at 0, as the FPGA powers them up
   (Verilog simulation would start them at X: data_ready_delay1, ch1_rq and
   the output registers, for example).

The index generator is not touched: the copy keeps the CLK_FAST_RATIO
parameter of sdram.sv (3 = upstream two-stage compare, 2 = one-stage compare
for a 2:1 clock ratio), which the testbench sets through its generic map.
(Measurement 3 used a --fix21 option here that patched the generator in the
copy; sdram.sv now selects it by parameter, so the option is gone.)

    sdram_sim_copy.py <rtl/sdram.sv> <out.sv>
"""
import re
import sys


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    lines = open(src).read().split("\n")
    hdr_end = next(i for i, l in enumerate(lines) if l.startswith(");"))
    lp, wr, rg, rest = [], [], [], []
    for l in lines[hdr_end + 1:]:
        if l.startswith("localparam"):
            lp.append(l)
        elif l.startswith("wire"):
            wr.append(l)
        elif l.startswith("reg"):
            rg.append(l)
        else:
            rest.append(l)
    hdr = "\n".join(lines[: hdr_end + 1])
    n = 0
    hdr, k = re.subn(r"inout\s+reg\s+\[15:0\]\s+SDRAM_DQ,",
                     "output reg [15:0]  SDRAM_DQ,\n\tinput      [15:0]  SDRAM_DQ_IN,\n\toutput             idx_o,", hdr)
    n += k
    def init0(l):
        if "=" in l:
            return l
        m = re.match(r"(reg\s*(\[[^\]]*\])?\s*)(.*);(.*)$", l)
        names = [x.strip() for x in m.group(3).split(",")]
        return m.group(1) + ", ".join(x + " = 0" for x in names) + ";" + m.group(4)
    rg = [init0(l) for l in rg]
    outs = re.findall(r"output\s+reg\s*(?:\[[^\]]*\])?\s*(\w+)", hdr)
    init_blk = "initial begin\n" + "".join(f"   {o} = 0;\n" for o in outs if o != "SDRAM_DQ") + "end\n"
    body = "\n".join(lp + wr + rg + [init_blk] + rest)
    body, k = re.subn(r"altddio_out\s*#\(.*?\);\s*\n", "", body, flags=re.S)
    n += k
    body, k = re.subn(r"dq_reg <= SDRAM_DQ;", "dq_reg <= SDRAM_DQ_IN;", body)
    n += k
    body = body.replace("<= 'Z;", "<= {16{1'bz}};")
    body = body.replace("endmodule",
                        "assign SDRAM_CLK = ~clk; // altddio_out (datain_h 0, datain_l 1)\n"
                        "assign idx_o = clk3xIndex;\nendmodule")
    if "parameter CLK_FAST_RATIO" not in hdr:
        sys.exit("sdram_sim_copy: no CLK_FAST_RATIO parameter in sdram.sv")
    expected = 3
    if n != expected:
        sys.exit(f"sdram_sim_copy: {n} of {expected} edits applied, sdram.sv changed?")
    open(dst, "w").write(hdr + "\n" + body)


if __name__ == "__main__":
    main()
