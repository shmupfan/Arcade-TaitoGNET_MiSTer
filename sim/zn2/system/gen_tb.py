#!/usr/bin/env python3
"""Generate sim/zn2/system/tb_zn2_system.vhd: psx_top with ZN2_BOARD = 1, the
real sdram.sv (R1 simulation copy) with a chip model preloaded from files,
a DDR3 model, and the G-NET loader ports (preloaded, or with LOAD_MODE = 1
through a model of PSX.sv's ioctl download logic and of hps_io). Ports are taken from
rtl/psx_top.vhd so the testbench follows the entity.

    gen_tb.py <rtl/psx_top.vhd> <out.vhd> [split]

split 0 (default): psx_top's clk_cpu ports on clk1x/clk2x/clk3x, the zn2-layer
configuration. split 1: CPU_CLK_SPLIT = 1 (CLK_FAST_RATIO 2, GTE_NARROW_MUL
3) with the CPU clocks f_clk/f_clk2 and the flash port through zn2_ch3_arb
(docs/r1_cpu_domain_design.md, "ZN-2 layer in the CPU group").
"""
import os
import re
import sys

# inputs the testbench drives itself; every other input gets a constant
TB_IN = {
    "clk1x": "clk1x", "clk2x": "clk2x", "clk3x": "clk3x", "clkvid": "clkvid", "reset": "reset",
    "ram_dataRead32": "ch1_dout32", "ram_done": "ram_done", "ram_dmafifo_read": "dmafifo_read",
    "cache_wr": "cache_wr", "cache_data": "cache_data", "cache_addr": "cache_addr",
    "dma_wr": "dma_wr", "dma_reqprocessed": "dma_reqprocessed", "dma_data": "dma_data",
    "ddr3_BUSY": "ddr3_BUSY", "ddr3_DOUT": "ddr3_DOUT", "ddr3_DOUT_READY": "ddr3_DOUT_READY",
    "zn_card_present": "card_present_m", "zn_key_valid": "card_present_m",
    "zn_ld_wr": "ld_wr_m", "zn_ld_target": "ld_target_m", "zn_ld_addr": "ld_addr_m", "zn_ld_data": "ld_data_m",
    "zn_card_dl_wr": "card_dl_wr", "zn_card_dl_addr": "card_dl_addr", "zn_card_dl_data": "card_dl_data",
    "zn_fl_ready": "ch3_ready", "zn_fl_dout": "ch3_dout",
}
TB_OUT = {
    "ram_refresh": "ram_refresh", "ram_dataWrite": "ram_dataWrite", "ram_Adr": "ram_Adr",
    "ram_cntDMA": "ram_cntDMA", "ram_be": "ram_be", "ram_rnw": "ram_rnw", "ram_ena": "ram_ena",
    "ram_dma": "ram_dma", "ram_cache": "ram_cache", "ram_dmafifo_adr": "dmafifo_adr",
    "ram_dmafifo_data": "dmafifo_data", "ram_dmafifo_empty": "dmafifo_empty",
    "ddr3_BURSTCNT": "ddr3_BURSTCNT", "ddr3_ADDR": "ddr3_ADDR", "ddr3_DIN": "ddr3_DIN",
    "ddr3_BE": "ddr3_BE", "ddr3_WE": "ddr3_WE", "ddr3_RD": "ddr3_RD",
    "zn_wd_reset": "wd_reset", "zn_coin": "coin",
    "zn_fl_req": "fl_req", "zn_fl_rnw": "fl_rnw", "zn_fl_addr": "fl_addr", "zn_fl_din": "fl_din",
    "zn_fl_be": "fl_be", "zn_card_dl_busy": "card_dl_busy", "vsync": "vsync",
}
CONST_ONE = {"ram8mb", "SPUon", "videoout_on"}
# per split: clock ports, the flash port, generics
SPLIT_MAP = {
    0: ({"clk_cpu": "clk1x", "clk_cpu2x": "clk2x", "clk_cpu3x": "clk3x"}, {},
        "GTE_NARROW_MUL => 1"),
    1: ({"clk_cpu": "f_clk", "clk_cpu2x": "f_clk2", "clk_cpu3x": "f_clk2",
         "zn_fl_ready": "fl_ready"},
        {"zn_fl_req": "fl_req", "zn_fl_rnw": "fl_rnw", "zn_fl_addr": "fl_addr",
         "zn_fl_din": "fl_din", "zn_fl_be": "fl_be"},
        "GTE_NARROW_MUL => 3, CLK_FAST_RATIO => 2, CPU_CLK_SPLIT => 1"),
}


def const_for(name, typ):
    if name in CONST_ONE:
        return "'1'"
    if name.startswith("zn_in_"):
        return 'x"FF"'
    if name == "zn_dsw":
        return 'x"F"'
    if typ.startswith("joypad_t"):
        return "JOY0"
    if typ.startswith("integer"):
        return "0"
    if typ == "std_logic":
        return "'0'"
    return "(others => '0')"


def main(src, out, split=0):
    sin, sout, sgen = SPLIT_MAP[split]
    s = open(src).read()
    ent = s[s.index("entity psx_top is"):s.index("end entity;")]
    port = ent[ent.index("port"):]
    maps = []
    for m in re.finditer(r"^\s+(\w+)\s*:\s*(in|out|buffer|inout)\s+([^;:=]+?)(?:\s*:=\s*[^;]+)?;?\s*(--.*)?$",
                         port, re.M):
        name, d, typ = m.group(1), m.group(2), m.group(3).strip()
        if d == "in":
            v = sin.get(name, TB_IN.get(name, const_for(name, typ)))
        else:
            v = sout.get(name, TB_OUT.get(name, "open"))
        maps.append(f"      {name:<22} => {v}")
    portmap = ",\n".join(maps)
    tpl = open(__file__.replace("gen_tb.py", "tb_zn2_system.tpl")).read()
    # env GTE_NARROW_MUL overrides the GTE variant of the chosen split
    if os.environ.get("GTE_NARROW_MUL"):
        sgen = re.sub(r"GTE_NARROW_MUL => \d", "GTE_NARROW_MUL => " + os.environ["GTE_NARROW_MUL"], sgen)
    tpl = tpl.replace("@SPLIT@", str(split)).replace("@SPLITGEN@", sgen)
    open(out, "w").write(tpl.replace("@PORTMAP@", portmap))


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) == 4 else 0)
