#!/bin/bash
# Unit bench of gnet_arcade_video against the framework's arcade_video
# (tb_arcade_video.sv, issue #3), Verilator. sync_fix lives in
# sys/sys_top.v; it is taken from there unchanged. sys/hq2x.sv assigns a
# wire in an always block (Quartus accepts it): -Wno-PROCASSWIRE. Verilator
# makes video_mixer's R_in/G_in/B_in (declared inside a generate block)
# 1-bit implicit nets, the same in both instances, so the colour compare is
# weaker than on hardware; the sync, DE and CE_PIXEL compares are exact.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p obj_dir_av
sed -n '/^module sync_fix/,/^endmodule/p' ../../sys/sys_top.v > obj_dir_av/sync_fix.v
nice -n 15 verilator --binary --timing -Wno-fatal -Wno-PROCASSINIT -Wno-WIDTH -Wno-PROCASSWIRE -j 1 \
  --top-module tb_arcade_video -Mdir obj_dir_av \
  ../../sys/arcade_video.v ../../sys/video_mixer.sv ../../sys/scandoubler.v ../../sys/hq2x.sv \
  ../../sys/gamma_corr.sv ../../sys/video_freezer.sv obj_dir_av/sync_fix.v \
  ../../rtl/gnet/gnet_arcade_video.sv tb_arcade_video.sv > obj_dir_av.log 2>&1 \
  || { tail -30 obj_dir_av.log; exit 1; }
nice -n 15 ./obj_dir_av/Vtb_arcade_video
