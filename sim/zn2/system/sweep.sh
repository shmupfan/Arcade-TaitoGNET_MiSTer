#!/bin/bash
# Clock phase sweep of the G-NET system simulation with psx_top CPU_CLK_SPLIT
# = 1 (docs/r1_cpu_domain_design.md, "ZN-2 layer in the CPU group"): the
# same run once per pair of start delays (PS1 clocks, CPU clocks), so a
# path that depends on the edge relation between the CPU group and the PS1
# group, or on where the CPU clock stands when an event arrives, shows up as
# a run that differs from the others.
#
#   sim/zn2/system/sweep.sh <name> <run_ms> [card set]
#
# Env:
#   PAIRS  "PHASE:CPU_PHASE ..." (default "7ns:0ns 0ns:5ns 0ns:0ns 3ns:0ns
#          11ns:0ns 23ns:0ns 0ns:13ns 0ns:17ns"; 7ns:0ns is the default bench,
#          0ns:5ns the full-system harness)
#   FLASH_FILE, READ_DQM, TRACE_US as for run.sh; GNET_DATA for the inputs
#   JOBS   simulations at a time (default 2)
# Each run gets its own copy of one built work directory (ZN2_WORK, default
# sim/zn2/work/system_sweep). Summary in <work>/sweep_<name>.txt: per pair
# the last progress line, GPU writes, I-cache races, watchdog resets, and
# whether its GPU write sequence (port and data, no times) equals the first
# pair's over their common length.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
NAME=$1; MS=$2; SET=${3:-}
BASE=${ZN2_WORK:-$ROOT/sim/zn2/work/system_sweep}
PAIRS=${PAIRS:-"7ns:0ns 0ns:5ns 0ns:0ns 3ns:0ns 11ns:0ns 23ns:0ns 0ns:13ns 0ns:17ns"}
JOBS=${JOBS:-2}
export SPLIT=1
if [ ! -f "$BASE/.built" ] || [ -n "${REBUILD:-}" ]; then
  "$HERE/build.sh" "$BASE" 1
  touch "$BASE/.built"
fi
k=0
pids=()
for pr in $PAIRS; do
  k=$((k + 1))
  W=$BASE.p$k
  rm -rf "$W"; mkdir -p "$W"
  ( cd "$BASE" && tar -cf - --exclude './run_*' . ) | ( cd "$W" && tar -xf - )
  (
    # every run uses the base's build as it is (REBUILD applies to the base only)
    unset REBUILD
    export ZN2_WORK=$W PHASE=${pr%%:*} CPU_PHASE=${pr##*:}
    nice -n 15 bash "$HERE/run.sh" "${NAME}_p$k" "$MS" "$SET" > "$W/sweep_run.log" 2>&1 || true
  ) &
  pids+=($!)
  if [ ${#pids[@]} -ge "$JOBS" ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); fi
done
wait
OUT=$BASE/sweep_$NAME.txt
: > "$OUT"
first=""
k=0
for pr in $PAIRS; do
  k=$((k + 1))
  R=$BASE.p$k/run_${NAME}_p$k
  last=$(tail -1 "$R/progress.log" 2>/dev/null | awk '{print $1, $2, $3, $4, $5, $6}')
  ng=$(grep -c . "$R/gpu.log" 2>/dev/null || true)
  nr=$(grep -c 'ICACHE RACE' "$R/run.log" 2>/dev/null || true)
  nw=$(grep -c 'WATCHDOG' "$R/progress.log" 2>/dev/null || true)
  awk '{print $2, $3}' "$R/gpu.log" > "$R/gpu_seq.txt" 2>/dev/null || true
  if [ -z "$first" ]; then
    first=$R/gpu_seq.txt; same="reference"
  else
    n=$(( $(wc -l < "$first") < $(wc -l < "$R/gpu_seq.txt") ? $(wc -l < "$first") : $(wc -l < "$R/gpu_seq.txt") ))
    if [ "$n" -eq 0 ] || cmp -s <(head -n "$n" "$first") <(head -n "$n" "$R/gpu_seq.txt"); then same="equal over $n"; else same="DIFFERS within $n"; fi
  fi
  echo "PHASE ${pr%%:*} CPU_PHASE ${pr##*:}: $last | gpu writes $ng ($same) | icache races $nr | watchdog resets $nw" >> "$OUT"
done
cat "$OUT"
