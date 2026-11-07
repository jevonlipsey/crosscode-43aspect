#!/bin/bash
# Deploy a 4:3 build to the Nova over root adb (NO launch, NO game-process control).  NOT run during authoring: the device was off limits.
#   tools/deploy43.sh <640|568|480>   take lock, check device files, back up cc.save, push out/43-<v>/ files, verify sha256 both ends, release lock
#   tools/deploy43.sh --rollback      restore the three pristine files and delete the leftover probe files, verify, release lock
#   tools/deploy43.sh --status        read-only: sha256 of the three live files and which build each one matches (no lock needed)
# env: ADB_SERIAL (default 6f1b78cc), WAIT=1 (poll for the lock every 60 s instead of exiting), FORCE=1 (deploy over unknown device files),
#      FORCE_BROKEN=1 (allow the known-bad 427 build), SAVE_DIR (where the save backup is pulled on the Mac, default runs/saves)
# Prefix 427 is refused: tools/rt43.sh showed the equipment/inventory/status menus overlap and clip (see CLAUDE.local.md).
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
S=${ADB_SERIAL:-6f1b78cc}
G=/mnt/media_rw/6988-E33F/Android/data/com.droiddeck.launcher/files/steam/steamapps/common/CrossCode
SAVE=/mnt/media_rw/6988-E33F/Android/data/com.droiddeck.launcher/files/steam/steamapps/compatdata/368340/pfx/drive_c/users/steamuser/AppData/Local/CrossCode/cc.save
LOCK=/data/local/tmp/nova-43aspect.lock
STAGE=/data/local/tmp/cc43.stage
SAVE_DIR=${SAVE_DIR:-$R/runs/saves}
PRISTINE_JS=28a166b4c5f650056f58294a22b014e2ddec70bf454861ee2095bc885e270521
PRISTINE_HTML=16c7b73f4f92822cc712bfd4db311be0ab60ddc917188eadf5ea2845d1efb6cc
PRISTINE_PKG=894c1f1b132dac045aaf60fab2c7520bcbae21845588f206f8236e2214a0a430
PROBE_HTML_PREFIX=93abca3a   # run-1 probe build left on the device (pristine + cc-diag script tag, LF endings)
PROBES="assets/cc-diag.js cc-diag.json cc-diag-err.txt assets/cc-tweak.js"
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
root() { adb -s "$S" shell su; }          # script on stdin
dsha() { printf 'sha256sum "%s" 2>/dev/null\n' "$1" | root | tr -d '\r' | awk '{print $1}'; }   # empty if missing
die() { echo "ERROR: $*" >&2; exit 1; }

known() { # known <sha> -> label of the build it matches, or empty
  local h=$1 f
  case $h in $PRISTINE_JS|$PRISTINE_HTML|$PRISTINE_PKG) echo pristine; return;; "$PROBE_HTML_PREFIX"*) echo "run-1 probe build"; return;; esac
  for f in "$R"/out/43-*/assets/node-webkit.html "$R"/out/43-*/package.json "$R"/out/43-*/assets/js/game.compiled.js; do
    [ -f "$f" ] && [ "$(sha "$f")" = "$h" ] && { echo "built: ${f#$R/out/}"; return; }
  done
}

if [ "${1:-}" = --status ]; then
  adb -s "$S" get-state >/dev/null 2>&1 || die "no adb device $S"
  for rel in assets/node-webkit.html assets/js/game.compiled.js package.json; do
    h=$(dsha "$G/$rel"); echo "$rel  ${h:-MISSING}  [$(known "$h")]"; done
  for rel in $PROBES; do printf 'test -e "%s" && echo "probe file present: %s"\n' "$G/$rel" "$rel" | root | tr -d '\r'; done
  echo "lock: $(echo "cat $LOCK/owner 2>/dev/null || echo free" | root | tr -d '\r')"; exit 0
fi

MODE=deploy; V=${1:-}
[ "$V" = --rollback ] && MODE=rollback
if [ $MODE = deploy ]; then
  [ -n "$V" ] || die "usage: deploy43.sh <640|568|480> | --rollback | --status"
  [ "$V" = 427 ] && [ -z "${FORCE_BROKEN:-}" ] && die "427 is known broken (menus overlap/clip). FORCE_BROKEN=1 to override."
  OUT=$R/out/43-$V; [ -d "$OUT" ] || die "$OUT missing: run tools/patch43.py $V"
  python3 "$R/tools/verify43.py" "$V" >/dev/null || die "verify43.py failed for $V"
fi
adb -s "$S" get-state >/dev/null 2>&1 || die "no adb device $S (is the Nova plugged in?)"

# ---- lock (SKILL.md recipe; the || rmdir cleans up a half-taken lock) ----
take_lock() { printf 'mkdir %s 2>/dev/null && { echo "crosscode-43aspect $(date +%%s)" > %s/owner || rmdir %s; } && echo GOT\n' "$LOCK" "$LOCK" "$LOCK" | root | grep -q GOT; }
until take_lock; do
  echo "lock held by: $(echo "cat $LOCK/owner" | root | tr -d '\r')"
  [ -n "${WAIT:-}" ] || die "device lock is held; retry later (or WAIT=1)"; sleep 60
done
HAVE_LOCK=1
release() { [ -n "${HAVE_LOCK:-}" ] && { echo "rm -rf $LOCK" | root; echo "lock released"; }; }
trap release EXIT

# game must not be running (the user may be playing)
# toybox pgrep -fa lists every pid on android, so match process args with ps instead
if echo "ps -A -o ARGS | grep -E 'gamescope|wineserver|CrossCode.exe' | grep -v grep" | root | tr -d '\r' | grep -q .; then die "a game session is running; not touching the device"; fi

put() { # put <local file> <device path>: stage, root-copy, restore mode, best-effort chown, verify sha256 both ends
  local src=$1 dst=$2 h want
  h=$(sha "$src")
  adb -s "$S" push "$src" "$STAGE" >/dev/null || die "adb push failed for $src"
  [ "$(dsha "$STAGE")" = "$h" ] || die "stage hash mismatch for $src"
  printf 'm=$(stat -c %%a "%s" 2>/dev/null || echo 700)\ncp "%s" "%s.new" && mv "%s.new" "%s"\nchown 10114:10114 "%s" || echo "(chown refused: expected on the exFAT SD, which forces uid 1023 / mode 770)"\nchmod $m "%s" 2>/dev/null\nrm -f "%s"\n' "$dst" "$STAGE" "$dst" "$dst" "$dst" "$dst" "$dst" "$STAGE" | root | tr -d '\r'
  [ "$(dsha "$dst")" = "$h" ] || die "device hash mismatch after copy: $dst"
  echo "ok  $dst  $h"
}

if [ $MODE = deploy ]; then
  # device files must be pristine, a known probe, or a previous build of ours
  for rel in assets/node-webkit.html assets/js/game.compiled.js package.json; do
    h=$(dsha "$G/$rel"); k=$(known "$h")
    echo "device $rel  ${h:0:12}  [${k:-UNKNOWN}]"
    [ -n "$k" ] || [ -n "${FORCE:-}" ] || die "$rel on the device is not pristine or a known build (FORCE=1 to override)"
  done
  # back up the save BEFORE anything runs against the new build
  mkdir -p "$SAVE_DIR"; TS=$(date +%s)
  if [ -n "$(dsha "$SAVE")" ]; then
    printf 'cp -p "%s" /data/local/tmp/cc.save.bak-%s\n' "$SAVE" "$TS" | root
    adb -s "$S" exec-out su -c "cat '$SAVE'" > "$SAVE_DIR/cc.save.$TS"
    [ "$(sha "$SAVE_DIR/cc.save.$TS")" = "$(dsha "$SAVE")" ] || die "save backup hash mismatch"
    echo "save backed up: $SAVE_DIR/cc.save.$TS and device /data/local/tmp/cc.save.bak-$TS ($(sha "$SAVE_DIR/cc.save.$TS" | cut -c1-12))"
  else echo "WARNING: no cc.save at the expected path (new prefix or never played?); nothing to back up"; fi
  while read -r rel; do put "$OUT/$rel" "$G/$rel"; done < <(cd "$OUT" && find . -type f | sed 's#^\./##' | sort)
  echo "DEPLOYED 43-$V. Launch CrossCode normally from DroidDeck. Rollback: tools/deploy43.sh --rollback"
else
  put "$R/original/node-webkit.html" "$G/assets/node-webkit.html"
  put "$R/original/package.json" "$G/package.json"
  for rel in $PROBES; do echo "rm -f \"$G/$rel\"" | root; done
  for rel in assets/node-webkit.html assets/js/game.compiled.js package.json; do
    h=$(dsha "$G/$rel"); echo "$rel ${h:0:12} [$(known "$h")]"; done
  [ "$(dsha "$G/assets/node-webkit.html")" = "$PRISTINE_HTML" ] && [ "$(dsha "$G/package.json")" = "$PRISTINE_PKG" ] && [ "$(dsha "$G/assets/js/game.compiled.js")" = "$PRISTINE_JS" ] || die "rollback did not reach pristine"
  echo "ROLLED BACK to pristine; probe files removed"
fi
