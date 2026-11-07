#!/bin/bash
# CrossCode, native arm64 inside the REAL Steam install (DroidDeck on the Retroid Pocket Nova), over root adb.
#
# Steam's own CrossCode entry (and so Cocoon) runs the official Linux depot with its x86 NW.js swapped for the official
# NW.js linux-arm64 build: no Proton, no Wine, no FEX. Steam Cloud and playtime work as for any Linux game; the Linux
# cloud path (~/.config/CrossCode/Default/cc.save*) is the NW.js save folder, and the cloud copy is the Proton save.
#
#   tools/steam-native.sh status            read-only report
#   tools/steam-native.sh stage             (Steam down, lock held) back up, copy the install SD -> internal library,
#                                           map 368340 to DroidDeck's "Linux x86 (FEX)" tool, turn no-steam off,
#                                           seed the save. Then launch CrossCode once through Steam: Steam swaps in the
#                                           Linux depot 368343 (it will start the x86 build under FEX afterwards).
#   tools/steam-native.sh patch [elf|shim]  (game not running, lock held) swap the x86 NW.js runtime for arm64 and
#                                           apply the 4:3 html. elf (default): CrossCode IS the arm64 nw. shim: a
#                                           6-line script CrossCode execs nw with the flags on argv.
#   tools/steam-native.sh unpatch           put the Linux depot's own x86 runtime, package.json and html back
#   tools/steam-native.sh revert            (Steam down) everything back to the Proton install on the SD card
#
# Why the internal library: the SD card is exFAT mounted noexec (no symlinks either), so an arm64 binary or .so there
# can never be executed or mapped. FEX only reads x86 binaries, which is why Proton/FEX games run from the SD card.
# Backups: <container>/root/.local/share/crosscode-43aspect/ on the device, saves also in runs/saves/ on the Mac.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
S=${ADB_SERIAL:-6f1b78cc}
APP=368340
L=/data/data/com.droiddeck.launcher/files/linuxfs
ST=$L/root/.local/share/Steam
SDA=/mnt/media_rw/6988-E33F/Android/data/com.droiddeck.launcher/files/steam/steamapps
SDG=$SDA/common/CrossCode
IG=$ST/steamapps/common/CrossCode
IM=$ST/steamapps/appmanifest_$APP.acf
BK=$L/root/.local/share/crosscode-43aspect
NATSAVE=$L/root/.config/CrossCode/Default
ENV_A=/data/data/com.droiddeck.launcher/files/game-environment.json
ENV_G=$L/root/.config/droiddeck/game-environment.json
CFG=$ST/config/config.vdf
NWV=v0.119.2
NWSHA=892f1a39739d1e83ef042997abc6506e08ef8efe53843185058e71d186535b0b
NWTGZ=/data/local/tmp/nwjs-arm64.tgz
PROTON_TOOL=DroidDeck-Proton-11-12.3
TMP=/data/local/tmp/cc43sn
# top-level entries of the game folder: game content stays, NW.js runtime is swapped; anything else stops the patch
KEEP=" assets favicon.png package.json steam_appid.txt "
RUNTIME=" CrossCode nw lib locales swiftshader icudtl.dat natives_blob.bin snapshot_blob.bin v8_context_snapshot.bin \
nw_100_percent.pak nw_200_percent.pak resources.pak credits.html chrome-sandbox chrome_crashpad_handler nacl_helper \
nacl_helper_bootstrap nacl_irt_x86_64.nexe libffmpeg.so libnode.so libnw.so debug.log cc-native-init.js cc-evpad.js \
.cc43-native CrossCode.exe d3dcompiler_47.dll ffmpeg.dll libEGL.dll libGLESv2.dll node.dll notification_helper.exe nw.dll \
nw_elf.dll "
PY="python3 -I $R/tools/steamnative.py"
W=$(mktemp -d "${TMPDIR:-/tmp}/cc43sn.XXXXXX"); trap 'rm -rf "$W"' EXIT

root() { adb -s "$S" shell su; }
die() { echo "steam-native: $*" >&2; exit 1; }
say() { echo "== $*"; }
pull() { adb -s "$S" exec-out su -c "cat '$1'" > "$2"; }
dsha() { echo "sha256sum '$1' 2>/dev/null | cut -d' ' -f1" | root | tr -d '\r'; }
lsha() { shasum -a 256 "$1" | cut -d' ' -f1; }
# push a local file over a device file: stage, hash-check, keep owner/mode of the file it replaces (or the given ones)
put() {  # put LOCAL DEVICE [owner mode]
  local h; h=$(lsha "$1")
  adb -s "$S" push "$1" "$TMP/put.new" >/dev/null || die "push $1 failed"
  cat <<EOF | root | tr -d '\r'
set -e
[ "\$(sha256sum $TMP/put.new | cut -d' ' -f1)" = "$h" ] || { echo "HASH MISMATCH on $2"; exit 1; }
if [ -e "$2" ]; then o=\$(stat -c %u:%g "$2"); m=\$(stat -c %a "$2"); else o=${3:-10114:10114}; m=${4:-600}; fi
cp $TMP/put.new "$2.cc43new" && mv "$2.cc43new" "$2" && chown \$o "$2" && chmod \$m "$2" && rm -f $TMP/put.new
echo "put $2 $h (\$o \$m)"
EOF
  [ "$(dsha "$2")" = "$h" ] || die "device copy of $2 does not match"
}
busy() {  # prints the session / game processes that are running (empty = idle)
  echo "ps -A -o pid,args 2>/dev/null | grep -E 'steamrtarm64/steam|gamescope|wineserver|FEXInterpreter|/CrossCode( |\$)|/nw( |\$)|proot' | grep -v grep" | root | tr -d '\r'
}
need_lock() {
  local o; o=$(echo "cat /data/local/tmp/nova-43aspect.lock/owner 2>/dev/null" | root | tr -d '\r')
  case $o in crosscode-43aspect*) ;; *) die "take the device lock first (owner now: '${o:-none}')";; esac
}
elf() {  # elf DEVICE_PATH -> x86_64 | i386 | arm64 | other | none  (ELF magic + e_machine, from raw hex bytes)
  echo "od -An -tx1 -N20 '$1' 2>/dev/null" | root | tr -d '\r' | tr -s ' \n' '  ' | awk '{
    if ($1!="7f" || $2!="45" || $3!="4c" || $4!="46") { print "none"; exit }
    m=$19 $20; if (m=="3e00") print "x86_64"; else if (m=="b700") print "arm64"; else if (m=="0300") print "i386"; else print "other" }'
}
prefix_save() {
  echo "ls -d /data/data/com.droiddeck.launcher/files/steam-libraries/*/steamapps/compatdata/$APP/pfx/drive_c/users/steamuser/AppData/Local/CrossCode 2>/dev/null | head -1" | root | tr -d '\r'
}

status() {
  local m; pull "$CFG" "$W/config.vdf"; m=$($PY getmap "$W/config.vdf" $APP)
  say "Steam mapping for $APP: ${m:-<none>}"
  pull "$ENV_A" "$W/ea.json"; pull "$ENV_G" "$W/eg.json"
  say "no-steam: android $(grep -c "\"$APP\":{[^}]*DROIDDECK_NO_STEAM" "$W/ea.json"), guest $(grep -c "\"$APP\":{[^}]*DROIDDECK_NO_STEAM" "$W/eg.json")"
  cat <<EOF | root | tr -d '\r'
for f in "$IM" "$SDA/appmanifest_$APP.acf" "$SDA/appmanifest_$APP.acf.cc43-moved"; do
  [ -f "\$f" ] && { echo "manifest \$f"; grep -E '"(StateFlags|buildid|BytesToDownload|BytesDownloaded)"' "\$f"; sed -n '/InstalledDepots/,/^\t}/p' "\$f" | grep -E '^\t\t"[0-9]+"\$'; }
done
for d in "$IG" "$SDG"; do [ -d "\$d" ] && { echo "dir \$d: \$(ls "\$d" | tr '\n' ' ')"; sha256sum "\$d/package.json" "\$d/assets/node-webkit.html" 2>/dev/null; cat "\$d/.cc43-native" 2>/dev/null; }; done
echo "native save:"; sha256sum "$NATSAVE"/cc.save* 2>/dev/null; cat "$L/root/.config/CrossCode/cc43-native.json" 2>/dev/null | head -40
EOF
  local p; p=$(prefix_save); say "prefix save $p"; echo "sha256sum '$p'/cc.save*" | root | tr -d '\r'
  [ -n "$(echo "ls $IG/CrossCode 2>/dev/null" | root | tr -d '\r')" ] && say "internal CrossCode binary: $(elf "$IG/CrossCode")"
  local b; b=$(busy); say "running: ${b:-nothing}"
}

stage() {
  need_lock; [ -z "$(busy)" ] || die "a session is running; Steam must be down to edit its config"
  local ts; ts=$(date +%Y%m%d-%H%M%S); local B=$BK/stage-$ts
  local p; p=$(prefix_save); [ -n "$p" ] || die "no Proton prefix save folder for $APP"
  say "backups -> $B"
  cat <<EOF | root | tr -d '\r' || die "backup failed"
set -e
[ ! -e "$IG" ] || { echo "REFUSE: $IG already exists"; exit 1; }
[ -f "$SDA/appmanifest_$APP.acf" ] || { echo "REFUSE: no SD manifest"; exit 1; }
mkdir -p "$B/save"
cp -p "$CFG" "$B/config.vdf"; cp -p "$SDA/appmanifest_$APP.acf" "$B/appmanifest_$APP.acf"
cp -p "$ENV_A" "$B/game-environment.android.json"; cp -p "$ENV_G" "$B/game-environment.guest.json"
cp -p "$ST/steamapps/libraryfolders.vdf" "$B/" 2>/dev/null || true
cp -p "$L/root/.local/share/droiddeck-compat/state.json" "$B/compat-state.json" 2>/dev/null || true
cp -p "$p"/cc.save* "$B/save/"
cd "$p" && sha256sum cc.save* > "$B/save/SHA256SUMS" && cd "$B/save" && sha256sum -c SHA256SUMS
chown -R 10114:10114 "$BK"
EOF
  mkdir -p "$R/runs/saves/steamnative-$ts"
  for f in cc.save cc.save.backup cc.save.backup2; do pull "$p/$f" "$R/runs/saves/steamnative-$ts/$f"; done
  pull "$B/save/SHA256SUMS" "$R/runs/saves/steamnative-$ts/SHA256SUMS"
  (cd "$R/runs/saves/steamnative-$ts" && shasum -a 256 -c SHA256SUMS) || die "Mac save copy does not verify"

  say "copy the install SD -> internal library (~1 GB)"
  cat <<EOF | root | tr -d '\r' || die "copy failed"
set -e
cp -r "$SDG" "$IG.cc43tmp"
a=\$(cd "$SDG" && find . -type f | wc -l); b=\$(cd "$IG.cc43tmp" && find . -type f | wc -l)
sa=\$(cd "$SDG" && find . -type f -exec stat -c %s {} + | awk '{s+=\$1} END{print s}')
sb=\$(cd "$IG.cc43tmp" && find . -type f -exec stat -c %s {} + | awk '{s+=\$1} END{print s}')
echo "files \$a -> \$b, bytes \$sa -> \$sb"
[ "\$a" = "\$b" ] && [ "\$sa" = "\$sb" ] || { echo "COPY MISMATCH"; rm -rf "$IG.cc43tmp"; exit 1; }
for f in CrossCode.exe package.json assets/node-webkit.html assets/js/game.compiled.js nw.dll; do
  [ "\$(sha256sum "$SDG/\$f" | cut -d' ' -f1)" = "\$(sha256sum "$IG.cc43tmp/\$f" | cut -d' ' -f1)" ] || { echo "HASH MISMATCH \$f"; exit 1; }
done
chown -R 10114:10114 "$IG.cc43tmp"; chmod -R u=rwX,go= "$IG.cc43tmp"; mv "$IG.cc43tmp" "$IG"
cp "$SDA/appmanifest_$APP.acf" "$IM"; chown 10114:10114 "$IM"; chmod 700 "$IM"
mv "$SDA/appmanifest_$APP.acf" "$SDA/appmanifest_$APP.acf.cc43-moved"
echo "manifest moved; SD install left in place as the Proton copy"
EOF
  say "Steam mapping $APP -> droiddeck-fex, no-steam off"
  pull "$CFG" "$W/config.vdf"; [ "$(lsha "$W/config.vdf")" = "$(dsha "$B/config.vdf")" ] || die "config.vdf changed during staging"
  $PY mapping "$W/config.vdf" "$W/config.new.vdf" $APP droiddeck-fex || die "mapping edit failed"
  put "$W/config.new.vdf" "$CFG"
  pull "$ENV_A" "$W/ea.json"; $PY nosteam "$W/ea.json" "$W/ea.new.json" $APP off && put "$W/ea.new.json" "$ENV_A"
  pull "$ENV_G" "$W/eg.json"; $PY nosteam "$W/eg.json" "$W/eg.new.json" $APP off && put "$W/eg.new.json" "$ENV_G"

  say "seed the native save folder (Steam Cloud's Linux path) with the Proton save"
  cat <<EOF | root | tr -d '\r' || die "save seed failed"
set -e
mkdir -p "$NATSAVE"
for f in cc.save cc.save.backup cc.save.backup2; do
  if [ -e "$NATSAVE/\$f" ]; then
    [ "\$(sha256sum "$NATSAVE/\$f" | cut -d' ' -f1)" = "\$(sha256sum "$B/save/\$f" | cut -d' ' -f1)" ] || { echo "REFUSE: a different $NATSAVE/\$f exists"; exit 1; }
  else cp -p "$B/save/\$f" "$NATSAVE/\$f"; fi
done
cd "$NATSAVE" && sha256sum -c "$B/save/SHA256SUMS"
chown -R 10114:10114 "$L/root/.config/CrossCode"; chmod 700 "$L/root/.config/CrossCode" "$NATSAVE"; chmod 644 "$NATSAVE"/cc.save*
EOF
  say "staged. Next: launch CrossCode through Steam once (Steam installs depot 368343), stop, then: $0 patch"
}

patch() {
  local mode=${1:-elf}; case $mode in elf|shim) ;; *) die "patch takes elf|shim";; esac
  need_lock
  case "$(busy)" in *CrossCode*|*/nw*|*FEXInterpreter*) die "CrossCode is running";; esac
  cat <<EOF | root | tr -d '\r' > "$W/m.txt"
grep -E '"StateFlags"' "$IM"; sed -n '/InstalledDepots/,/^\t}/p' "$IM" | grep -E '^\t\t"[0-9]+"\$'
EOF
  grep -q '"StateFlags"[[:space:]]*"4"' "$W/m.txt" || die "Steam has not finished installing $APP ($(tr '\n' ' ' < "$W/m.txt"))"
  grep -q -E '"36834(2|3)"' "$W/m.txt" || die "the Linux depot 368343 (or 32-bit 368342) is not installed yet ($(tr '\n' ' ' < "$W/m.txt"))"
  grep -q -E '"36834(1|9)"' "$W/m.txt" && die "Windows depots still installed ($(tr '\n' ' ' < "$W/m.txt"))"
  local a; a=$(elf "$IG/CrossCode")
  local inv; inv=$(echo "ls -a '$IG' | grep -v -E '^\.\.?\$'" | root | tr -d '\r')
  for e in $inv; do case "$KEEP$RUNTIME" in *" $e "*) ;; *) die "unexpected entry '$e' in $IG: not touching it, check by hand";; esac; done

  if [ "$a" = x86_64 ] || [ "$a" = i386 ]; then
    say "fresh Linux depot ($a CrossCode): back up its runtime, package.json and html"
    pull "$IG/assets/node-webkit.html" "$W/linux.html"
    pull "$IG/package.json" "$W/linux.json"
    $PY html43 "$W/linux.html" "$W/node-webkit.html" || die "Linux html is not the expected pristine file"
    local ts; ts=$(date +%Y%m%d-%H%M%S)
    local mv_list=""; for e in $inv; do case "$KEEP" in *" $e "*) ;; *) mv_list="$mv_list $e";; esac; done
    cat <<EOF | root | tr -d '\r' || die "runtime backup failed"
set -e
[ ! -d "$BK/x86" ] || mv "$BK/x86" "$BK/x86.old-$ts"
mkdir -p "$BK/x86"
cp -p "$IG/package.json" "$BK/x86/package.json.linux"; cp -p "$IG/assets/node-webkit.html" "$BK/x86/node-webkit.html.linux"
cd "$IG"; for e in $mv_list; do mv "\$e" "$BK/x86/"; done
ls "$BK/x86" > "$BK/x86/.list"; sha256sum "$BK/x86/package.json.linux" "$BK/x86/node-webkit.html.linux"
EOF
  elif [ "$a" = arm64 ] || [ "$(echo "[ -f '$IG/.cc43-native' ] && echo y" | root | tr -d '\r')" = y ]; then
    say "already patched ($(echo "cat '$IG/.cc43-native'" | root | tr -d '\r' | head -1)); re-applying in $mode form"
    pull "$BK/x86/node-webkit.html.linux" "$W/linux.html"
    pull "$BK/x86/package.json.linux" "$W/linux.json"
    $PY html43 "$W/linux.html" "$W/node-webkit.html" || die "backed-up Linux html is not pristine"
    echo "cd '$IG' && rm -rf CrossCode nw lib locales swiftshader icudtl.dat v8_context_snapshot.bin nw_100_percent.pak nw_200_percent.pak resources.pak credits.html chrome_crashpad_handler" | root
  else
    die "$IG/CrossCode is '$a': expected the Linux depot's x86_64 binary"
  fi

  say "arm64 NW.js $NWV ($mode form)"
  [ "$(dsha $NWTGZ)" = "$NWSHA" ] || {
    [ -f "${NWJS_TGZ:-}" ] && [ "$(lsha "$NWJS_TGZ")" = "$NWSHA" ] || die "no verified nwjs-$NWV-linux-arm64.tar.gz on the device; set NWJS_TGZ=<file> (https://dl.nwjs.io/$NWV/nwjs-$NWV-linux-arm64.tar.gz, sha256 $NWSHA)"
    adb -s "$S" push "$NWJS_TGZ" $NWTGZ >/dev/null; [ "$(dsha $NWTGZ)" = "$NWSHA" ] || die "push of the NW.js tarball is corrupt"; }
  $PY package "$W/linux.json" "$W/package.json" "$mode" || die "package.json build failed"
  for f in package.json node-webkit.html; do adb -s "$S" push "$W/$f" "$TMP/$f" >/dev/null; done
  for f in cc-native-init.js cc-evpad.js CrossCode.shim; do adb -s "$S" push "$R/native/$f" "$TMP/$f" >/dev/null; done
  local H; H="pkg=$(lsha "$W/package.json") html=$(lsha "$W/node-webkit.html") init=$(lsha "$R/native/cc-native-init.js") evpad=$(lsha "$R/native/cc-evpad.js") shim=$(lsha "$R/native/CrossCode.shim")"
  cat <<EOF | root | tr -d '\r' || die "install failed"
set -e
mkdir -p $TMP/nw; rm -rf $TMP/nw/*; tar -xzf $NWTGZ -C $TMP/nw
N=$TMP/nw/nwjs-$NWV-linux-arm64; [ -x "\$N/nw" ] || { echo "tarball has no nw"; exit 1; }
cd "\$N"; ls -a | grep -v -E '^\.\.?\$' > $TMP/nw/list; for e in \$(cat $TMP/nw/list); do mv "\$e" "$IG/"; done
cd "$IG"
if [ $mode = elf ]; then mv nw CrossCode; else cp $TMP/CrossCode.shim CrossCode; fi
cp $TMP/package.json package.json; cp $TMP/node-webkit.html assets/node-webkit.html
cp $TMP/cc-native-init.js cc-native-init.js; cp $TMP/cc-evpad.js cc-evpad.js
printf 'mode=$mode nw=$NWV nwsha=$NWSHA\n$H\nfiles=%s\n' "\$(cat $TMP/nw/list | tr '\n' ' ')" > .cc43-native
chown -R 10114:10114 "$IG"; chmod -R u=rwX,go= "$IG"
chmod 700 CrossCode chrome_crashpad_handler lib/*.so* 2>/dev/null || true; [ ! -f nw ] || chmod 700 nw
rm -rf $TMP/nw $TMP/*.js $TMP/*.json $TMP/*.html $TMP/CrossCode.shim
sha256sum package.json assets/node-webkit.html cc-native-init.js cc-evpad.js CrossCode | sed 's/^/  /'
EOF
  [ "$(dsha "$IG/package.json")" = "$(lsha "$W/package.json")" ] && [ "$(dsha "$IG/assets/node-webkit.html")" = "$(lsha "$W/node-webkit.html")" ] || die "installed files do not match"
  if [ $mode = elf ]; then [ "$(elf "$IG/CrossCode")" = arm64 ] || die "CrossCode is not the arm64 nw"; else [ "$(elf "$IG/nw")" = arm64 ] || die "nw is not arm64"; fi
  say "patched ($mode). Launch CrossCode from Steam / Cocoon as usual."
}

unpatch() {
  need_lock
  case "$(busy)" in *CrossCode*|*/nw*|*FEXInterpreter*) die "CrossCode is running";; esac
  cat <<EOF | root | tr -d '\r' || die "unpatch failed"
set -e
[ -f "$IG/.cc43-native" ] && [ -f "$BK/x86/.list" ] || { echo "not patched (no marker or no backup)"; exit 1; }
cd "$IG"; for e in \$(sed -n 's/^files=//p' .cc43-native) CrossCode nw cc-native-init.js cc-evpad.js; do rm -rf "\$e"; done
for e in \$(cat "$BK/x86/.list"); do case \$e in package.json.linux|node-webkit.html.linux) ;; *) mv "$BK/x86/\$e" "$IG/";; esac; done
cp -p "$BK/x86/package.json.linux" package.json; cp -p "$BK/x86/node-webkit.html.linux" assets/node-webkit.html
rm -f .cc43-native; rm -rf "$BK/x86"
chown -R 10114:10114 "$IG"; ls "$IG"
EOF
  say "unpatched: the Linux depot's own x86 build is back (Steam runs it through FEX)"
}

revert() {
  need_lock; [ -z "$(busy)" ] || die "a session is running; Steam must be down to edit its config"
  local B; B=$(echo "ls -d $BK/stage-* 2>/dev/null | tail -1" | root | tr -d '\r'); [ -n "$B" ] || die "no stage backup in $BK"
  local p; p=$(prefix_save); local ts; ts=$(date +%Y%m%d-%H%M%S)
  say "save: if the native save is newer than the Proton one, it goes back into the prefix (prefix trio backed up)"
  cat <<EOF | root | tr -d '\r' || die "save step failed"
set -e
if [ -f "$NATSAVE/cc.save" ] && [ "$NATSAVE/cc.save" -nt "$p/cc.save" ]; then
  mkdir -p "$BK/revert-$ts/prefix-save"; cp -p "$p"/cc.save* "$BK/revert-$ts/prefix-save/"
  for f in cc.save cc.save.backup cc.save.backup2; do [ -f "$NATSAVE/\$f" ] && cp -p "$NATSAVE/\$f" "$p/\$f"; done
  chown 10114:10114 "$p"/cc.save*; echo "native save copied into the prefix"; sha256sum "$p"/cc.save*
else echo "prefix save is current"; fi
EOF
  pull "$CFG" "$W/config.vdf"; $PY mapping "$W/config.vdf" "$W/config.new.vdf" $APP $PROTON_TOOL && put "$W/config.new.vdf" "$CFG"
  pull "$ENV_A" "$W/ea.json"; $PY nosteam "$W/ea.json" "$W/ea.new.json" $APP on && put "$W/ea.new.json" "$ENV_A"
  pull "$ENV_G" "$W/eg.json"; $PY nosteam "$W/eg.json" "$W/eg.new.json" $APP on && put "$W/eg.new.json" "$ENV_G"
  cat <<EOF | root | tr -d '\r' || die "manifest step failed"
set -e
[ -f "$SDA/appmanifest_$APP.acf.cc43-moved" ] && mv "$SDA/appmanifest_$APP.acf.cc43-moved" "$SDA/appmanifest_$APP.acf"
mkdir -p "$BK/revert-$ts"; [ -f "$IM" ] && mv "$IM" "$BK/revert-$ts/"; [ -d "$IG" ] && mv "$IG" "$BK/revert-$ts/CrossCode"
chown -R 10114:10114 "$BK"
echo "Proton install on the SD card is live again. The internal copy is parked in $BK/revert-$ts/CrossCode (delete by hand)."
EOF
}

[ "$(adb -s "$S" get-state 2>/dev/null)" = device ] || die "device '$S' is not reachable over adb (set ADB_SERIAL; see adb devices)"
[ "$(echo id -u | root | tr -d '\r')" = 0 ] || die "no root shell on the device"
# staging dir for adb push (runs as the shell user, so it must own it)
[ "${1:-status}" = status ] || echo "mkdir -p $TMP && chown 2000:2000 $TMP && chmod 775 $TMP" | root >/dev/null
case ${1:-status} in
  status) status;; stage) stage;; patch) patch "${2:-elf}";; unpatch) unpatch;; revert) revert;;
  *) sed -n '2,22p' "$0"; exit 2;;
esac
