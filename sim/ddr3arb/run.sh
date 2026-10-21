#!/bin/bash
# DDR3 arbiter testbenches (Verilator), nice -n 15.
#   sim/ddr3arb/run.sh arb <seed> <cycles> <busy %> <lat base> <lat jitter> [stall]
#   sim/ddr3arb/run.sh zport <seed> <clk_1x cycles>
#   sim/ddr3arb/run.sh mirror <seed> <ns> <busy %> [nostall]
#   sim/ddr3arb/run.sh flcopy <seed> <busy %> <lat> <jit> [len ...]   (FLC_SRC: copier source, for mutants;
#     FLC_TRIES: the copier's TRIES, default 1; FLC_FAULT: sdram, ddr3 or hang)
# (no bench name: arb, as before)
set -euo pipefail
cd "$(dirname "$0")"
R=../../rtl/gnet
case "${1:-}" in
  zport)  shift; TOP=gnet_ddr3_zport;  SRC=$R/gnet_ddr3_zport.sv;  TB=tb_zport.cpp;  OBJ=obj_zport ;;
  mirror) shift; TOP=gnet_ddr3_mirror; SRC=$R/gnet_ddr3_mirror.sv; TB=tb_mirror.cpp; OBJ=obj_mirror ;;
  flcopy) shift; TOP=tb_flcopy_top;   GEN="-GTRIES=${FLC_TRIES:-1}"; [ "${FLC_TRIES:-1}" = 1 ] || OBJ_SFX=_t${FLC_TRIES}; SRC="tb_flcopy_top.sv ${FLC_SRC:-$R/gnet_ddr3_flcopy.sv} $R/gnet_ddr3_gmux.sv $R/gnet_ddr3_mirror.sv $R/gnet_ddr3_arb.sv"; TB=tb_flcopy.cpp; OBJ=${FLC_OBJ:-obj_flcopy${OBJ_SFX:-}} ;;
  arb)    shift; TOP=gnet_ddr3_arb;    SRC=$R/gnet_ddr3_arb.sv;    TB=tb.cpp;        OBJ=obj ;;
  *)             TOP=gnet_ddr3_arb;    SRC=$R/gnet_ddr3_arb.sv;    TB=tb.cpp;        OBJ=obj ;;
esac
nice -n 15 verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH \
  --top-module $TOP ${GEN:-} -Mdir $OBJ $SRC $TB > $OBJ.log 2>&1 || { tail -30 $OBJ.log; exit 1; }
nice -n 15 $OBJ/V$TOP "$@"
