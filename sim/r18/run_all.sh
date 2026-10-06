#!/bin/bash
# R18 trace: six G-NET games, 900 emulated seconds each from a cold first boot, 3 at a time
cd "$(dirname "$0")/../.."
run() {
  s=$1
  rm -rf sim/r18/nv_$s sim/r18/$s.txt
  R18_OUT=$PWD/sim/r18/$s.txt R18_COIN_AT=240 nice -n 15 mame $s -rompath roms \
    -nvram_directory sim/r18/nv_$s -cfg_directory sim/r18/cfg_$s -snapshot_directory sim/r18/nv_snap -video none -sound none \
    -nothrottle -skip_gameinfo -seconds_to_run 900 -autoboot_script tools/mame/r18_trace.lua \
    > sim/r18/$s.log 2>&1
  echo "$(date +%H:%M) $s done"
}
run raycris & run psyvarrv & run xiistag & wait
run shikigam & run nightrai & run psyvaria & wait
