#!/bin/bash
# LOCAL render test on the Mac using the Steam Mac install's assets (never touches the device, never modifies the Steam dir).
# usage: rt43.sh <label> <node-webkit.html> [game.compiled.js or -] [package.json or -]   -> $RT_OUT/<label>/*.png + report.json
set -u
R=$(cd "$(dirname "$0")/.." && pwd); L=$1; HTML=$2; JS=${3:--}; PKG=${4:--}
W=${RT_OUT:-$R/runs/rt43}; D=$W/$L; mkdir -p "$D"; APP=$W/.app-$L; UD=$W/.ud-$L
SRC="$HOME/Library/Application Support/Steam/steamapps/common/CrossCode/CrossCode.app/Contents"
AS="$SRC/Resources/app.nw"; BUNDLE=$W/.CC.app; NW="$BUNDLE/Contents/MacOS/nwjs"
# NW ignores an app dir argument when a bundled Resources/app.nw exists, so run a private (APFS-cloned) copy of the bundle with our app dir as app.nw
if [ ! -x "$NW" ]; then rm -rf "$BUNDLE"; mkdir -p "$BUNDLE"; cp -cR "$SRC" "$BUNDLE/Contents"; fi
rm -rf "$APP" "$UD"; mkdir -p "$APP/assets/js" "$UD/Default"; rm -rf "$BUNDLE/Contents/Resources/app.nw"; ln -s "$APP" "$BUNDLE/Contents/Resources/app.nw"
for f in "$AS"/*; do b=$(basename "$f"); [ "$b" = assets ] || [ "$b" = package.json ] || ln -s "$f" "$APP/$b"; done
for f in "$AS"/assets/*; do b=$(basename "$f"); case $b in js|node-webkit.html) ;; *) ln -s "$f" "$APP/assets/$b";; esac; done
for f in "$AS"/assets/js/*; do b=$(basename "$f"); [ "$b" = game.compiled.js ] || ln -s "$f" "$APP/assets/js/$b"; done
# harness is appended to the TEST copy of game.compiled.js (a separately <script>-loaded harness did not run under NW)
{ cat "$([ "$JS" = - ] && echo "$AS/assets/js/game.compiled.js" || echo "$JS")"; printf '\n;'; cat "$R/tools/rt43.js"; } > "$APP/assets/js/game.compiled.js"
# test package.json: same as given/pristine but 1280x960 window and no occlusion throttling
python3 - "$([ "$PKG" = - ] && echo "$AS/package.json" || echo "$PKG")" "$APP/package.json" <<'P'
import sys,re
s=open(sys.argv[1],newline='').read()
if '"width" : 1280' not in s: s=re.sub(r'"width" : \d+','"width" : 1280',s); s=re.sub(r'"height": \d+','"height": 960',s)
s=s.replace('--password-store=basic','--password-store=basic --disable-renderer-backgrounding --disable-backgrounding-occluded-windows')
open(sys.argv[2],'w',newline='').write(s)
P
cp "$HOME/Library/Application Support/CrossCode/Default/cc.save" "$UD/Default/cc.save"   # a COPY; the real save is never opened
python3 - "$HTML" "$APP/assets/node-webkit.html" <<'P'
import sys
s=open(sys.argv[1],newline='').read()
open(sys.argv[2],'w',newline='').write(s)
P
rm -f "$D"/*.png "$D/report.json"
# RT_NW=<path to another nwjs binary>: run the same app dir in that NW.js build (e.g. a newer runtime) instead of the game's own
if [ -n "${RT_NW:-}" ]; then CC_OUT="$D" "$RT_NW" --user-data-dir="$UD" --enable-logging=stderr "$APP" >"$D/nw.log" 2>&1 &
else CC_OUT="$D" "$NW" --user-data-dir="$UD" --enable-logging=stderr >"$D/nw.log" 2>&1 &
fi
P=$!; for i in $(seq 1 90); do sleep 2; kill -0 $P 2>/dev/null || break; grep -q '"done"' "$D/report.json" 2>/dev/null && break; done
sleep 2; kill $P 2>/dev/null; sleep 1; for q in $(ps -axo pid,command | grep -F "$APP" | grep -v grep | awk '{print $1}'); do kill $q 2>/dev/null; done
echo "== $L"; ls "$D"; python3 -c "import json;d=json.load(open('$D/report.json'));print(d.get('info'),d.get('info2'),d.get('err'),d.get('done'),d.get('timeout'))"
