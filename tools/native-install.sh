#!/bin/bash
# Install / remove the native ARM64 CrossCode launcher on the Nova over root adb (no game files are touched).
#   tools/native-install.sh            install: NW.js (from the device staging dir /data/local/tmp/ccn-stage/nwjs,
#                                       else pushed from $NWJS_TGZ) + the DroidDeck Linux app "CrossCode (native)"
#   tools/native-install.sh --remove   delete the Linux app, its menu entry and ~/.local/share/crosscode-native
#                                       (the save is NOT there: it stays in the Proton prefix)
# What it writes is exactly what DroidDeck's own "add a script" does (UserApps.addScript, DroidDeck 0.6.9):
#   /opt/droiddeck-apps/crosscode-native/{entry,name,source,fex,icon.png,files/crosscode-native.sh}
#   /usr/local/share/applications/droiddeck-app-crosscode-native.desktop
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
S=${ADB_SERIAL:-6f1b78cc}
L=/data/data/com.droiddeck.launcher/files/linuxfs
APP=$L/opt/droiddeck-apps/crosscode-native
DATA=$L/root/.local/share/crosscode-native
MENU=$L/usr/local/share/applications/droiddeck-app-crosscode-native.desktop
G=/mnt/media_rw/6988-E33F/Android/data/com.droiddeck.launcher/files/steam/steamapps/common/CrossCode
NWV=v0.119.2
root() { adb -s "$S" shell su; }
if [ "${1:-}" = --remove ]; then
  printf 'rm -rf "%s" "%s" "%s"\nls -d "%s" "%s" 2>&1\n' "$APP" "$DATA" "$MENU" "$APP" "$DATA" | root; exit 0
fi
SH=$R/native/crosscode-native.sh; H=$(shasum -a 256 "$SH" | cut -d' ' -f1)
adb -s "$S" push "$SH" /data/local/tmp/ccn.sh >/dev/null
adb -s "$S" push "$R/native/cc-evpad.js" /data/local/tmp/ccn-evpad.js >/dev/null
adb -s "$S" push "$R/native/cc-native-init.js" /data/local/tmp/ccn-init.js >/dev/null
NWSHA=892f1a39739d1e83ef042997abc6506e08ef8efe53843185058e71d186535b0b
have=$(printf 'test -x %s/nwjs-%s/nw && echo HAVE; sha256sum /data/local/tmp/nwjs-arm64.tgz 2>/dev/null | grep -q %s && echo TGZ\n' "$DATA" "$NWV" "$NWSHA" | root | tr -d '\r')
case $have in
  *HAVE*) echo "NW.js $NWV already installed";;
  *) if [ "$have" != TGZ ]; then
       [ -f "${NWJS_TGZ:-}" ] || { echo "no verified NW.js tgz on the device; set NWJS_TGZ=<nwjs-$NWV-linux-arm64.tar.gz>"; exit 1; }
       adb -s "$S" push "$NWJS_TGZ" /data/local/tmp/nwjs-arm64.tgz >/dev/null
     fi
     printf 'mkdir -p "%s/dl" && cd "%s/dl" && tar -xzf /data/local/tmp/nwjs-arm64.tgz && mv nwjs-%s-linux-arm64 "../nwjs-%s" && cd .. && rmdir dl\n' "$DATA" "$DATA" "$NWV" "$NWV" | root;;
esac
cat <<EOF | root
set -e
mkdir -p "$APP/files" "${MENU%/*}"
cp /data/local/tmp/ccn.sh "$APP/files/crosscode-native.sh"; rm -f /data/local/tmp/ccn.sh
cp /data/local/tmp/ccn-evpad.js "$APP/files/cc-evpad.js"; rm -f /data/local/tmp/ccn-evpad.js
cp /data/local/tmp/ccn-init.js "$APP/files/cc-native-init.js"; rm -f /data/local/tmp/ccn-init.js
printf 'crosscode-native.sh' > "$APP/entry"
printf 'CrossCode (native)' > "$APP/name"
printf 'nova-43aspect crosscode-native.sh' > "$APP/source"
printf 'off' > "$APP/fex"
[ -f "$APP/icon.png" ] || cp "$G/favicon.png" "$APP/icon.png" 2>/dev/null || true
printf '[Desktop Entry]\nType=Application\nName=CrossCode (native)\nExec=/usr/local/bin/droiddeck-script-run /opt/droiddeck-apps/crosscode-native\nIcon=/opt/droiddeck-apps/crosscode-native/icon.png\nTerminal=false\nCategories=Game;\nX-DroidDeck-App=crosscode-native\n' > "$MENU"
chown -R 10114:10114 "$APP" "$DATA" "$MENU" "$L/opt/droiddeck-apps"
chmod 700 "$L/opt/droiddeck-apps" "$APP" "$APP/files"; chmod 600 "$APP/entry" "$APP/name" "$APP/source" "$APP/fex" "$MENU"; chmod 700 "$APP/files/crosscode-native.sh"; chmod 600 "$APP/files/cc-evpad.js" "$APP/files/cc-native-init.js"
ls -la "$APP" "$APP/files"; ls "$DATA"; sha256sum "$APP/files/crosscode-native.sh" "$APP/files/cc-evpad.js" "$APP/files/cc-native-init.js"
EOF
echo "expected script sha $H"
