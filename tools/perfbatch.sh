#!/bin/bash
# ONE device slot for CrossCode smoothness: takes the device lock once, chains unattended self-terminating launches
# (tools/perfrun.sh: the probe presses Continue itself, lands in the bergen.bergen2 autosave, settles 8 s, records
# 40 s of game frames while the player walks right/left for 10 s under a screenrecord + SurfaceFlinger capture, checks
# the pad for 12 s while BTN_SOUTH is injected, then quits the game), restores the user's build + save after every
# launch, and releases the lock on exit. Variants, in order:
#   base   Proton, the user's live 43-480 build (BEFORE)
#   nat    native ARM64 NW.js 0.119.2, default GPU path (ANGLE-GL on zink)
#   pace   Proton + tools/cc-pace.js (game loop at a steady 60 fps on the 120 Hz output)
#   natvk  native + ANGLE on Vulkan (Turnip directly, no zink)      [natsw = --disable-gpu instead, if nat failed]
#   natsw  native, software canvas/compositing (only if the budget allows)
# No new launch starts after BUDGET seconds (default 720), so the slot ends by ~15 min.
# Results: runs/perf/<stamp>-<v>.json (+ -rec.mp4, -rec.json, -sf.txt/json, -mid.png, -session.log), and a
# consistency table (tools/perfstat.py) plus the on-screen cadence from the screenrecords at the end.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
S=${ADB_SERIAL:-6f1b78cc}; export ADB_SERIAL=$S KEEP_LOCK=1
LOCK=/data/local/tmp/nova-43aspect.lock; BUDGET=${BUDGET:-720}; T0=$(date +%s); ST=$(date +%m%d-%H%M)
root() { adb -s "$S" shell su; }
printf 'mkdir %s 2>/dev/null && { echo "crosscode-43aspect $(date +%%s)" > %s/owner && echo GOT || rmdir %s; }\n' $LOCK $LOCK $LOCK | root | grep -q GOT \
  || { echo "lock held by: $(echo "cat $LOCK/owner" | root)"; exit 3; }
trap 'echo "rm -rf '$LOCK'" | root; echo "lock released"' EXIT
if echo "ps -A -o ARGS | grep -E 'gamescope|wineserver|\.exe|nwjs[^ ]*/nw' | grep -v grep" | root | grep -q .; then
  echo "a game session is running (the user may be playing): not touching the device"; exit 4; fi
mkdir -p "$R/runs/perf"; IL=$R/runs/perf/install-$ST.log
"$R/tools/native-install.sh" > "$IL" 2>&1 || { tail -5 "$IL"; echo "native install failed"; exit 1; }
tail -4 "$IL"
LABELS=()
run() { local v=$1 m=$2; shift 2
  [ $(( $(date +%s) - T0 )) -lt "$BUDGET" ] || { echo "== skip $v (budget)"; return; }
  echo "== $v ($m) at +$(( $(date +%s) - T0 )) s, $(echo 'dumpsys battery | grep temperature' | root | tr -d '\r ')"
  env "$@" "$R/tools/perfrun.sh" "$ST-$v" "$m"; LABELS+=("$R/runs/perf/$ST-$v.json"); }
valid() { python3 -I - "$R/tools" "$R/runs/perf/$ST-$1.json" <<'P'
import sys; sys.path.insert(0, sys.argv[1]); import perfstat
r, _ = perfstat.row(sys.argv[2]); print('ok' if r and r['valid'] else 'FAIL')
P
}
run base proton
run nat native
NAT=$(valid nat); echo "native run: $NAT"
run pace proton PACE=1
if [ "$NAT" = ok ]; then
  run natvk native NFLAGS="--use-angle=vulkan"
  run natsw native NFLAGS="--disable-gpu"
else
  run natsw native NFLAGS="--disable-gpu"
fi
echo "== done at +$(( $(date +%s) - T0 )) s"
[ ${#LABELS[@]} -gt 0 ] && python3 -I "$R/tools/perfstat.py" --table "${LABELS[@]}"
echo "on-screen (screenrecord, new game images while walking):"
for j in "${LABELS[@]}"; do r=${j%.json}-rec.json; [ -f "$r" ] && python3 -I -c "
import json,sys; d=json.load(open(sys.argv[1])); c=d.get('content',{}); k=d.get('capture',{})
print('  %-16s images %s  fps %s  sd %s ms  judder %s%%  off-median %s%%  vblanks %s  | capture %s fps' % (sys.argv[2], c.get('n'), c.get('fps'), c.get('sd_ms'), c.get('judder_pct'), c.get('off_median_pct'), c.get('vblanks_1_2_3_4plus_pct'), k.get('fps')))" "$r" "${j##*/}"; done
echo "output stage (SurfaceFlinger presents of the DroidDeck layer):"
for j in "${LABELS[@]}"; do r=${j%.json}-sf.json; [ -f "$r" ] && python3 -I -c "
import json,sys; d=json.load(open(sys.argv[1])); c=d.get('present',{})
print('  %-16s presents %s  fps %s  sd %s ms  vblanks %s' % (sys.argv[2], c.get('n'), c.get('fps'), c.get('sd_ms'), c.get('vblanks_1_2_3_4plus_pct')))" "$r" "${j##*/}"; done
