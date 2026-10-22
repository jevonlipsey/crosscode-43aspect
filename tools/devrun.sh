#!/bin/bash
# usage: devrun.sh <label>   (caller holds the device lock; deploys nothing, launches, waits for cc-diag.json, pulls it, stops the game)
set -u
L=$1; OUT=${2:-/private/tmp/claude-501/-Users-jevonlipsey-Downloads-nova-43aspect/d6d39d74-1345-4a89-8a72-32c5d881d4e3/scratchpad}
G=/mnt/droiddeck-sd/steamapps/common/CrossCode
ssh droiddeck "rm -f $G/cc-diag.json"
pid=$(ssh droiddeck 'pgrep -n konsole || pgrep -n lxqt-panel')
ssh droiddeck "python3 /root/ddlaunch.py $pid /usr/local/bin/droiddeck-gpu /usr/local/bin/droiddeck-proton-run --app 368340"
for i in $(seq 1 60); do sleep 10; ssh droiddeck "test -f $G/cc-diag.json" && break; [ $i = 25 ] && adb -s 6f1b78cc exec-out screencap -p > $OUT/$L-mid.png; done
adb -s 6f1b78cc exec-out screencap -p > $OUT/$L-end.png
ssh droiddeck "cat $G/cc-diag.json" > $OUT/diag-$L.json
ssh droiddeck 'for p in $(ps -eo pid,args | grep -E "gamescope|CrossCode.exe|steam.exe|wineserver|winedevice|droiddeck-gpu" | grep -vE "grep|ps -eo|bash -c" | awk "{print \$1}"); do kill -TERM $p 2>/dev/null; done; sleep 10; for p in $(ps -eo pid,args | grep -E "gamescope|CrossCode.exe|steam.exe|wineserver|winedevice|droiddeck-gpu" | grep -vE "grep|ps -eo|bash -c" | awk "{print \$1}"); do kill -KILL $p 2>/dev/null; done; ps -eo pid,args | grep -E "gamescope|CrossCode|wineserver|winedevice" | grep -vE "grep|ps -eo|bash -c"'
