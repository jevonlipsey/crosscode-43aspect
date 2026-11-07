#!/bin/bash
# Headless device run over root adb (no desktop mode, no ssh). UNTESTED as a whole; pieces verified by the lead 2026-10-27.
# usage: hrun.sh <label> [package.json variant file in out/ or "-"] [html variant in out/ or "-"]
#  Takes the root-adb lock, deploys (hash-checked, chown 10114, mode kept), launches via droiddeck:// (needs
#  DROIDDECK_NO_STEAM=1 under games."368340"), waits for cc-diag.json, pulls it, SIGTERM -> 12 s -> SIGKILL stragglers,
#  ALWAYS rolls back to the baseline files and releases the lock. Baseline = original/ (pristine package.json + game files).
set -u
R=$(cd "$(dirname "$0")/.." && pwd); L=$1; PKG=${2:--}; HTML=${3:-out/node-webkit.diag.html}
OUT=${OUT:-$R/runs}; mkdir -p "$OUT"
G=/mnt/media_rw/6988-E33F/Android/data/com.droiddeck.launcher/files/steam/steamapps/common/CrossCode
LOCK=/data/local/tmp/nova-43aspect.lock
root() { adb shell su; }
until echo "mkdir $LOCK 2>/dev/null && echo \"crosscode \$(date +%s)\" > $LOCK/owner && echo GOT" | root | grep -q GOT; do
  echo "lock held: $(echo "cat $LOCK/owner" | root)"; sleep 60; done
cleanup() { echo "== rollback + unlock"; rollback; echo "rm -rf $LOCK" | root; }
put() { # put <local> <device path>: stage, hash-check, copy, restore owner and the mode the target had
  local src=$1 dst=$2 h; h=$(shasum -a 256 "$src" | cut -d' ' -f1)
  adb push "$src" /data/local/tmp/stage.cc >/dev/null
  printf 'm=$(stat -c %%a "%s" 2>/dev/null || echo 700)\ncp /data/local/tmp/stage.cc "%s"\nchown 10114:10114 "%s"\nchmod $m "%s"\nsha256sum "%s"\nrm /data/local/tmp/stage.cc\n' "$dst" "$dst" "$dst" "$dst" "$dst" | root | grep -q "^$h" || { echo "HASH MISMATCH $dst"; return 1; }
}
rollback() {
  put "$R/original/package.json" $G/package.json
  put "$R/original/node-webkit.html" $G/assets/node-webkit.html
  echo "rm -f $G/assets/cc-diag.js $G/assets/cc-tweak.js" | root
}
trap cleanup EXIT
echo "pgrep -fa 'gamescope|wineserver|CrossCode'" | root
[ "$PKG" != - ] && put "$R/out/$PKG" $G/package.json
put "$R/tools/cc-diag.js" $G/assets/cc-diag.js
[ -n "${TWEAK:-}" ] && put "$R/out/$TWEAK" $G/assets/cc-tweak.js
put "$R/$HTML" $G/assets/node-webkit.html
echo "rm -f $G/cc-diag.json" | root
E=/data/data/com.droiddeck.launcher/files/game-environment.json
printf 'if ! grep -q 368340 %s; then cp -p %s /data/local/tmp/game-environment.json.cc-bak; sed -i "s/\\"games\\":{/\\"games\\":{\\"368340\\":{\\"DROIDDECK_NO_STEAM\\":\\"1\\"},/" %s; fi\ngrep -o "368340[^}]*}" %s\nls -l %s\n' "$E" "$E" "$E" "$E" "$E" | root
for try in 1 2 3; do
  python3 -I ~/.claude/skills/nova-43aspect/tools/dd-dismiss.py; sleep 3; python3 -I ~/.claude/skills/nova-43aspect/tools/dd-dismiss.py
  adb shell input keyevent KEYCODE_WAKEUP
  printf 'wm dismiss-keyguard\nam start -a android.intent.action.VIEW -d "droiddeck://game/368340" com.droiddeck.launcher/.FrontEndActivity\n' | root
  sleep 30
  echo "pgrep -f gamescope >/dev/null && echo UP" | root | grep -q UP && break
  echo "launch attempt $try: no session yet"
done
[ -n "${INJECT:-}" ] && OUT=$OUT L=$L bash "$INJECT"
for i in $(seq 1 60); do sleep 10
  echo "test -f $G/cc-diag.json && echo HAVE" | root | grep -q HAVE && break
  [ $i = 8 ] && adb exec-out screencap -p > "$OUT/$L-mid.png"   # also confirms the game is on screen
done
adb exec-out screencap -p > "$OUT/$L-end.png"
adb exec-out su -c "cat $G/cc-diag.json" > "$OUT/diag-$L.json"
# stop: app-level force-stop via dd-stop.py (per-process kills are refused and wedge DroidDeck). Back up saves first.
python3 -I ~/.claude/skills/nova-43aspect/tools/dd-stop.py
python3 -I ~/.claude/skills/nova-43aspect/tools/dd-stop.py --check
python3 -I "$R/tools/analyze.py" "$OUT/diag-$L.json"
