#!/bin/bash
# One benchmark run on the Nova: deterministic Continue -> bergen.bergen2 autosave, 8 s settle, 40 s of frames
# (tools/cc-perf.js), then the game quits itself. Root adb only; takes and releases the device lock.
#   tools/perfrun.sh <label> proton            the user's normal launch (droiddeck://game/368340, no-steam)
#   tools/perfrun.sh <label> native            DroidDeck Linux app /opt/droiddeck-apps/crosscode-native (NW.js arm64)
# During the recording it walks the player right/left for 10 s (left stick on the pad node) so the camera scrolls, and
# meanwhile captures (a) a 12 s `screenrecord` (runs/perf/<label>-rec.mp4: on-screen cadence of new game images, see
# tools/recstat.py) and (b) SurfaceFlinger present times of the DroidDeck layer (<label>-sf.txt).
# env: ADB_SERIAL; KEEP_LOCK=1 (hold the lock for the next run; reuses a lock this repo already holds);
#      PACE=1 load tools/cc-pace.js (60 fps cadence gate) before the probe;
#      PKG=<local package.json> to test a package.json variant (restored after);
#      NFLAGS="<chromium flags>" extra flags for the native launcher (flags.txt beside it, removed after);
#      GAME_ENV='{"FEX_X":"1",...}' extra per-game env for 368340 in game-environment.json (restored after).
# Always: backs up the save trio first (sha-checked, Mac + device), restores it after the run if it changed,
# puts the user's build back (43-480 html 6031c988, pristine package.json), removes probe files, releases the lock.
set -u
R=$(cd "$(dirname "$0")/.." && pwd); L=${1:?label}; MODE=${2:?proton|native}
S=${ADB_SERIAL:-6f1b78cc}; export ANDROID_SERIAL=$S
OUT=$R/runs/perf; mkdir -p "$OUT"
F=/data/data/com.droiddeck.launcher/files
G=/mnt/media_rw/6988-E33F/Android/data/com.droiddeck.launcher/files/steam/steamapps/common/CrossCode
APP=$F/linuxfs/opt/droiddeck-apps/crosscode-native
NAPP=$F/linuxfs/root/.local/share/crosscode-native/app   # native NW.js package dir = the probe's working dir
ENVF=$F/game-environment.json
LOCK=/data/local/tmp/nova-43aspect.lock
LIVE_HTML=$R/out/43-480/assets/node-webkit.html
HTML=$R/out/perf/node-webkit.perf480.html; [ -n "${PACE:-}" ] && HTML=$R/out/perf/node-webkit.perf480-pace.html
PROBE="cc-perf.json cc-perf-err.txt cc-perf-rec.txt cc-perf-pad.txt"
root() { adb -s "$S" shell su; }
dsha() { printf 'sha256sum "%s" 2>/dev/null\n' "$1" | root | tr -d '\r' | awk '{print $1}'; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
die() { echo "ERROR: $*" >&2; exit 1; }
take() { printf 'grep -q "^crosscode-43aspect " %s/owner 2>/dev/null && echo GOT && exit\nmkdir %s 2>/dev/null && { echo "crosscode-43aspect $(date +%%s)" > %s/owner || rmdir %s; } && echo GOT\n' $LOCK $LOCK $LOCK $LOCK | root | grep -q GOT; }
until take; do echo "lock held by: $(echo "cat $LOCK/owner" | root | tr -d '\r')"; [ -n "${WAIT:-}" ] || exit 3; sleep 60; done
HAVE=1
running() { echo "ps -A -o ARGS | grep -E 'gamescope|wineserver|CrossCode.exe|nwjs[^ ]*/nw' | grep -v grep" | root | tr -d '\r' | grep -q .; }
put() { local h; h=$(sha "$1"); adb -s "$S" push "$1" /data/local/tmp/cc.stage >/dev/null || die "push $1"
  printf 'cp /data/local/tmp/cc.stage "%s.new" && mv "%s.new" "%s"; chown 10114:10114 "%s" 2>/dev/null; chmod %s "%s" 2>/dev/null; rm -f /data/local/tmp/cc.stage\n' "$2" "$2" "$2" "$2" "${3:-770}" "$2" | root
  [ "$(dsha "$2")" = "$h" ] || die "hash mismatch $2"; }
rmprobe() { local c="rm -f $G/assets/cc-perf.js $G/assets/cc-pace.js $APP/files/flags.txt"; for f in $PROBE; do c="$c $G/$f $NAPP/$f $F/linuxfs/$f"; done; echo "$c" | root; }
SAVED=$(echo "ls -d $F/steam-libraries/*/steamapps/compatdata/368340/pfx/drive_c/users/steamuser/AppData/Local/CrossCode 2>/dev/null | head -1" | root | tr -d '\r')
[ -n "$SAVED" ] || die "no live save folder found"
TS=$(date +%s); BK=$R/runs/saves/$TS; mkdir -p "$BK"
cleanup() {
  echo "== cleanup"
  if [ -n "${HAVE_NOFIX:-}${NODEPLOY:-}" ]; then [ -z "${KEEP_LOCK:-}" ] && echo "rm -rf $LOCK" | root; return; fi
  if running; then python3 -I ~/.claude/skills/nova-43aspect/tools/dd-stop.py --owner crosscode-43aspect; sleep 5; fi
  put "$LIVE_HTML" "$G/assets/node-webkit.html"
  [ -n "${PKG:-}" ] && put "$R/original/package.json" "$G/package.json"
  rmprobe
  if [ -n "${GAME_ENV:-}" ]; then echo "cp -p /data/local/tmp/game-environment.json.perf-$TS $ENVF; chown 10114:10114 $ENVF; chmod 600 $ENVF" | root; fi
  for f in cc.save cc.save.backup cc.save.backup2; do
    [ -f "$BK/$f" ] || continue
    if [ "$(dsha "$SAVED/$f")" != "$(sha "$BK/$f")" ]; then echo "restoring $f"; put "$BK/$f" "$SAVED/$f" 644; fi
  done
  echo "live html $(dsha "$G/assets/node-webkit.html" | cut -c1-12) pkg $(dsha "$G/package.json" | cut -c1-12) save $(dsha "$SAVED/cc.save" | cut -c1-12)"
  if [ -n "${KEEP_LOCK:-}" ]; then echo "lock kept (KEEP_LOCK)"; elif [ -n "${HAVE:-}" ]; then echo "rm -rf $LOCK" | root; echo "lock released"; fi
}
trap cleanup EXIT
LH=$(dsha "$G/assets/node-webkit.html"); [ "$LH" = "$(sha "$LIVE_HTML")" ] || [ -n "${FORCE:-}" ] || { HAVE_NOFIX=1; echo "live html is ${LH:0:12}, not the 43-480 build; refusing (FORCE=1)"; exit 5; }
running && { NODEPLOY=1; echo "a game session is running (user may be playing); not touching the device"; exit 4; }
for f in cc.save cc.save.backup cc.save.backup2; do
  adb -s "$S" exec-out su -c "cat '$SAVED/$f'" > "$BK/$f"; [ "$(sha "$BK/$f")" = "$(dsha "$SAVED/$f")" ] || die "save backup mismatch $f"
done
echo "mkdir -p /data/local/tmp/cc-saves-$TS && cp -p '$SAVED'/cc.save* /data/local/tmp/cc-saves-$TS/" | root
echo "save backed up: $BK ($(sha "$BK/cc.save" | cut -c1-12))"
rmprobe
put "$R/tools/cc-perf.js" "$G/assets/cc-perf.js"
[ -n "${PACE:-}" ] && put "$R/tools/cc-pace.js" "$G/assets/cc-pace.js"
put "$HTML" "$G/assets/node-webkit.html"
[ -n "${PKG:-}" ] && put "$PKG" "$G/package.json"
if [ "$MODE" = native ] && [ -n "${NFLAGS:-}" ]; then printf 'printf "%%s\\n" "%s" > %s/files/flags.txt; chown 10114:10114 %s/files/flags.txt; chmod 600 %s/files/flags.txt; cat %s/files/flags.txt\n' "$NFLAGS" "$APP" "$APP" "$APP" "$APP" | root; fi
PAD=$(echo "grep -lE '^(Retroid Pocket Controller|Xbox Wireless Controller)$' /sys/class/input/event*/device/name | head -1" | root | tr -d '\r' | sed -n 's#.*/\(event[0-9]*\)/device/name#/dev/input/\1#p')
[ -n "$PAD" ] && [ "$PAD" != /dev/input/event4 ] || die "no pad event node (or it resolved to the touchscreen)"; echo "pad node $PAD"
if [ -n "${GAME_ENV:-}" ]; then
  adb -s "$S" exec-out su -c "cat $ENVF" > "$OUT/genv-$TS.json"
  python3 - "$OUT/genv-$TS.json" "$GAME_ENV" > "$OUT/genv-$TS.new.json" <<'P'
import json,sys
c=json.load(open(sys.argv[1])); g=c.setdefault('games',{}).setdefault('368340',{}); g.update(json.loads(sys.argv[2])); print(json.dumps(c,separators=(',',':')))
P
  echo "cp -p $ENVF /data/local/tmp/game-environment.json.perf-$TS" | root
  put "$OUT/genv-$TS.new.json" "$ENVF" 600
fi
python3 -I ~/.claude/skills/nova-43aspect/tools/dd-stop.py --owner crosscode-43aspect >/dev/null 2>&1; sleep 3
python3 -I ~/.claude/skills/nova-43aspect/tools/dd-dismiss.py; adb -s "$S" shell input keyevent KEYCODE_WAKEUP; adb -s "$S" shell input keyevent KEYCODE_HOME; sleep 2
T0=$(date +%s)
if [ "$MODE" = native ]; then
  printf 'wm dismiss-keyguard\nam start -n com.droiddeck.launcher/.SessionActivity --es mode run --es program /usr/local/bin/droiddeck-script-run --esa programArgs /opt/droiddeck-apps/crosscode-native\n' | root
else
  printf 'wm dismiss-keyguard\nam start -a android.intent.action.VIEW -d "droiddeck://game/368340" com.droiddeck.launcher/.FrontEndActivity\n' | root
fi
# the probe writes into its working dir: the game dir under Proton, the private package dir natively; check both
WD=; shot=0; pad=0; walk=0; MAXWAIT=${MAXWAIT:-$([ "$MODE" = native ] && echo 220 || echo 330)}
while [ $(( $(date +%s) - T0 )) -lt "$MAXWAIT" ]; do sleep 3
  st=$(printf 'for d in %s %s %s; do for f in cc-perf.json cc-perf-rec.txt cc-perf-pad.txt; do test -f $d/$f && echo "$f $d"; done; done\n' "$G" "$NAPP" "$F/linuxfs" | root | tr -d '\r')
  case $st in *cc-perf.json*) WD=$(echo "$st" | sed -n 's/^cc-perf.json //p' | head -1); break;; esac
  if [ $walk = 0 ] && case $st in *cc-perf-rec.txt*) true;; *) false;; esac; then walk=1; sleep 4
    echo "walk + screenrecord + SF latency at $(( $(date +%s) - T0 )) s"
    cat <<EOF | root
L=\$(dumpsys SurfaceFlinger --list | grep -m1 -E '^SurfaceView\[com.droiddeck.launcher/.*SessionActivity\]\(BLAST\)')
echo "\$L" > /data/local/tmp/cc-sf.txt; rm -f /data/local/tmp/cc-rec.mp4
screenrecord --time-limit 12 --bit-rate 24000000 /data/local/tmp/cc-rec.mp4 &
( i=0; while [ \$i -lt 16 ]; do dumpsys SurfaceFlinger --latency "\$L" >> /data/local/tmp/cc-sf.txt; sleep 0.7; i=\$((i+1)); done ) &
sleep 1; i=0
while [ \$i -lt 5 ]; do sendevent $PAD 3 0 32767; sendevent $PAD 0 0 0; sleep 1; sendevent $PAD 3 0 -32767; sendevent $PAD 0 0 0; sleep 1; i=\$((i+1)); done
sendevent $PAD 3 0 0; sendevent $PAD 0 0 0
wait
EOF
    adb -s "$S" exec-out screencap -p > "$OUT/$L-mid.png"; shot=1
    adb -s "$S" exec-out su -c 'cat /data/local/tmp/cc-rec.mp4' > "$OUT/$L-rec.mp4"
    adb -s "$S" exec-out su -c 'cat /data/local/tmp/cc-sf.txt' > "$OUT/$L-sf.txt"
    echo "rm -f /data/local/tmp/cc-rec.mp4 /data/local/tmp/cc-sf.txt" | root
    echo "walk done at $(( $(date +%s) - T0 )) s, rec $(wc -c < "$OUT/$L-rec.mp4") bytes, sf layer: $(head -1 "$OUT/$L-sf.txt")"; fi
  if [ $pad = 0 ] && case $st in *cc-perf-pad.txt*) true;; *) false;; esac; then pad=1; sleep 2
    printf 'for i in 1 2 3; do sendevent %s 1 304 1; sendevent %s 0 0 0; sleep 0.2; sendevent %s 1 304 0; sendevent %s 0 0 0; sleep 1.5; done\n' $PAD $PAD $PAD $PAD | root
    echo "BTN_SOUTH x3 injected on $PAD"; fi
done
echo "elapsed $(( $(date +%s) - T0 )) s, results in ${WD:-<none>}"
[ $shot = 0 ] && adb -s "$S" exec-out screencap -p > "$OUT/$L-end.png"
if [ -n "$WD" ]; then
  adb -s "$S" exec-out su -c "cat $WD/cc-perf.json" > "$OUT/$L.json" 2>/dev/null
  adb -s "$S" exec-out su -c "cat $WD/cc-perf-err.txt" 2>/dev/null | head -5
else echo "no cc-perf.json in $G or $NAPP" > "$OUT/$L.json"; fi
sleep 6; running && echo "(session still up after the probe quit)"
LOGD=$(echo "ls -td $F/logs/*-* | head -1" | root | tr -d '\r'); echo "session log: $LOGD"
adb -s "$S" exec-out su -c "cat $LOGD/session.log" > "$OUT/$L-session.log" 2>/dev/null
python3 -I "$R/tools/perfstat.py" "$OUT/$L.json" || true
[ -s "$OUT/$L-rec.mp4" ] && python3 -I "$R/tools/recstat.py" "$OUT/$L-rec.mp4" > "$OUT/$L-rec.json" 2>&1 && grep -A3 '"content"' "$OUT/$L-rec.json" | tr -s ' \n' ' '; echo
[ -s "$OUT/$L-sf.txt" ] && python3 -I "$R/tools/recstat.py" --sf "$OUT/$L-sf.txt" > "$OUT/$L-sf.json" 2>&1
true
