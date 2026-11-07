#!/bin/bash
# Device-run helpers for the Steam-native CrossCode test (tools/steam-native.sh). Hold the device lock first.
#   sn-run.sh launch            clear DroidDeck's dialog, force-stop, HOME, start CrossCode through Steam (Cocoon's path)
#   sn-run.sh poll LABEL        manifest state, game/Steam processes, last Steam content/cloud log lines, screenshot
#   sn-run.sh shot LABEL        screenshot only (runs/steam-native/LABEL.png)
#   sn-run.sh pad stick|a|start|mode|down|up   inject on the physical pad (EV_ABS / EV_KEY, SYN-terminated)
#   sn-run.sh marker            pull ~/.config/CrossCode/cc43-native.json (proof the arm64 build loaded)
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
S=${ADB_SERIAL:-6f1b78cc}
L=/data/data/com.droiddeck.launcher/files/linuxfs
ST=$L/root/.local/share/Steam
OUT=$R/runs/steam-native; mkdir -p "$OUT"
root() { adb -s "$S" shell su; }
shot() { adb -s "$S" exec-out screencap -p > "$OUT/$1.png" && echo "shot $OUT/$1.png"; }
padnode() {
  echo "grep -lE '^(Retroid Pocket Controller|Xbox Wireless Controller)\$' /sys/class/input/event*/device/name | head -1" | root | tr -d '\r' |
    sed -n 's#.*/\(event[0-9]*\)/device/name#/dev/input/\1#p'
}
case ${1:-} in
  launch)
    python3 -I ~/.claude/skills/nova-43aspect/tools/dd-dismiss.py || true
    cat <<'EOF' | root
input keyevent KEYCODE_WAKEUP
am force-stop com.droiddeck.launcher
input keyevent KEYCODE_HOME
wm dismiss-keyguard
sleep 2
am start -a android.intent.action.VIEW -d "droiddeck://game/368340" com.droiddeck.launcher/.FrontEndActivity
EOF
    date +%s > "$OUT/.launch";;
  poll)
    t=$(( $(date +%s) - $(cat "$OUT/.launch" 2>/dev/null || date +%s) ))
    echo "== T+${t}s"
    cat <<EOF | root | tr -d '\r'
M=$ST/steamapps/appmanifest_368340.acf
[ -f \$M ] && { grep -E '"(StateFlags|BytesToDownload|BytesDownloaded|BytesToStage|BytesStaged)"' \$M | tr -s '\t' ' ' | tr '\n' ' '; echo; sed -n '/InstalledDepots/,/^\t}/p' \$M | grep -E '^\t\t"[0-9]+"\$' | tr -d '\t' | tr '\n' ' '; echo; }
ls -d $ST/steamapps/downloading/368340 2>/dev/null && du -s $ST/steamapps/downloading/368340
ps -A -o pid,etime,args | grep -E 'steamrtarm64/steam |CrossCode|FEXInterpreter|/nw |gamescope' | grep -v grep | cut -c1-200
for f in content_log.txt cloud_log.txt compat_log.txt; do echo "-- \$f"; tail -n 4 $ST/logs/\$f 2>/dev/null | cut -c1-200; done
dumpsys window | grep mCurrentFocus
EOF
    shot "${2:-poll}-$t";;
  shot) shot "${2:?label}";;
  pad)
    N=$(padnode); case $N in /dev/input/event4|'') echo "no pad node ($N)"; exit 1;; esac
    case ${2:-} in
      stick) seq="sendevent $N 3 0 32767; sendevent $N 0 0 0; sleep 1.5; sendevent $N 3 0 0; sendevent $N 0 0 0";;
      a)     seq="sendevent $N 1 304 1; sendevent $N 0 0 0; sleep 0.15; sendevent $N 1 304 0; sendevent $N 0 0 0";;
      start) seq="sendevent $N 1 315 1; sendevent $N 0 0 0; sleep 0.15; sendevent $N 1 315 0; sendevent $N 0 0 0";;
      mode)  seq="sendevent $N 1 316 1; sendevent $N 0 0 0; sleep 0.15; sendevent $N 1 316 0; sendevent $N 0 0 0";;
      down)  seq="sendevent $N 3 17 1; sendevent $N 0 0 0; sleep 0.15; sendevent $N 3 17 0; sendevent $N 0 0 0";;
      up)    seq="sendevent $N 3 17 -1; sendevent $N 0 0 0; sleep 0.15; sendevent $N 3 17 0; sendevent $N 0 0 0";;
      *) echo "pad stick|a|start|mode|down|up"; exit 2;;
    esac
    echo "$seq" | root; echo "pad ${2} on $N";;
  marker) adb -s "$S" exec-out su -c "cat $L/root/.config/CrossCode/cc43-native.json" | tee "$OUT/cc43-native-$(date +%H%M%S).json";;
  *) sed -n '2,8p' "$0"; exit 2;;
esac
