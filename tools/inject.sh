#!/bin/bash
# Drive title -> Continue -> load newest save. Face buttons EV_KEY on the physical pad; every press ends with SYN. Screenshots between steps.
N=/dev/input/event7
shot() { adb exec-out screencap -p > "$OUT/$L-$1.png"; }
press() { printf 'sendevent %s 1 304 1\nsendevent %s 0 0 0\nsleep 0.15\nsendevent %s 1 304 0\nsendevent %s 0 0 0\n' $N $N $N $N | adb shell su; }
sleep ${BOOT:-75}; shot t0
for i in 1 2 3; do press; sleep 8; shot a$i; done
