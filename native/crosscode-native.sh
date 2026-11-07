#!/bin/bash
# CrossCode, native ARM64, for DroidDeck: runs the Steam install's own game files (assets/, package.json) in the
# official NW.js linux-arm64 build. No Proton, no Wine, no FEX translation of V8's JIT-generated code.
# Add this script in DroidDeck as a Linux app. NW.js is taken from nwjs/ beside the script, else from
# ~/.local/share/crosscode-native/, and downloaded there (sha256-checked, ~200 MB) on the first launch if missing.
# Saves are the same cc.save the Windows build uses (the Proton prefix's AppData/Local/CrossCode), so both launches
# share progress. Overrides: CC_GAME_DIR, CC_SAVE_DIR, CC_FLAGS (extra Chromium flags), set in the environment or in
# local.env beside this script; flags.txt beside it (flags, # comments) is read too.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
[ -f "$HERE/local.env" ] && . "$HERE/local.env"
NW_VERSION=v0.119.2
NW_SHA256=892f1a39739d1e83ef042997abc6506e08ef8efe53843185058e71d186535b0b
DATA=$HOME/.local/share/crosscode-native
log() { echo "crosscode-native: $*" >&2; }
NW=$HERE/nwjs/nw
[ -f "$NW" ] || NW=$DATA/nwjs-$NW_VERSION/nw
if [ ! -f "$NW" ]; then
  url=https://dl.nwjs.io/$NW_VERSION/nwjs-$NW_VERSION-linux-arm64.tar.gz
  log "downloading NW.js $NW_VERSION for arm64 ($url)"
  mkdir -p "$DATA" && rm -rf "$DATA/dl" && mkdir "$DATA/dl" || exit 1
  curl -fL --retry 3 -o "$DATA/dl/nw.tgz" "$url" || { log "download failed"; exit 1; }
  echo "$NW_SHA256  $DATA/dl/nw.tgz" | sha256sum -c --quiet || { log "download does not match its sha256"; rm -rf "$DATA/dl"; exit 1; }
  tar -xzf "$DATA/dl/nw.tgz" -C "$DATA/dl" && mv "$DATA/dl/nwjs-$NW_VERSION-linux-arm64" "$DATA/nwjs-$NW_VERSION" || exit 1
  rm -rf "$DATA/dl"
fi
[ -x "$NW" ] || chmod +x "$NW" "${NW%/nw}/chrome_crashpad_handler" 2>/dev/null
[ -x "$NW" ] || { log "no runnable NW.js at $NW"; exit 127; }

libs=(/mnt/droiddeck-sd "$HOME/.local/share/Steam")
for vdf in "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf" "$HOME/.local/share/Steam/config/libraryfolders.vdf"; do
  [ -f "$vdf" ] || continue
  while IFS= read -r p; do libs+=("$p"); done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\([^"]*\)".*/\1/p' "$vdf")
done

game=${CC_GAME_DIR:-}
if [ -z "$game" ]; then
  for lib in "${libs[@]}"; do
    [ -f "$lib/steamapps/common/CrossCode/assets/node-webkit.html" ] && { game=$lib/steamapps/common/CrossCode; break; }
  done
fi
[ -n "$game" ] || { log "CrossCode is not installed in any Steam library (${libs[*]})"; exit 2; }

save=${CC_SAVE_DIR:-}
if [ -z "$save" ]; then
  for lib in "${libs[@]}"; do
    d=$lib/steamapps/compatdata/368340/pfx/drive_c/users/steamuser/AppData/Local/CrossCode
    [ -d "$d" ] && { save=$d; break; }
  done
fi
if [ -z "$save" ]; then save=$DATA/save; log "no Proton prefix for 368340; saves go to $save"; fi
mkdir -p "$save"

# NW.js puts nw.App.dataPath at <user-data-dir>/Default and the game keeps cc.save there, so Default points at the
# save folder. The Chromium profile files land beside cc.save; the Windows build keeps its own in "User Data".
profile=$DATA/profile
mkdir -p "$profile"
if [ -L "$profile/Default" ] || [ ! -e "$profile/Default" ]; then ln -sfn "$save" "$profile/Default"
else log "$profile/Default is a real folder; leaving it (saves stay there)"; fi

flags=(--no-sandbox --disable-dev-shm-usage --autoplay-policy=no-user-gesture-required --ignore-gpu-blocklist
       --disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows)
extra=()
[ -f "$HERE/flags.txt" ] && read -r -a extra <<< "$(grep -v '^#' "$HERE/flags.txt" | tr '\n' ' ')"
[ ${#extra[@]} -gt 0 ] && flags+=("${extra[@]}")
extra=()
[ -n "${CC_FLAGS:-}" ] && read -r -a extra <<< "$CC_FLAGS"
[ ${#extra[@]} -gt 0 ] && flags+=("${extra[@]}")
# A private app dir: every top-level entry of the game folder linked in, plus our own package.json (window sized for
# the Nova's 1280x960 screen, Windows-only flags dropped) and the evdev pad fallback injected into the page. The Steam
# folder itself is never written to, so the Windows/Proton launch is unaffected.
app=$DATA/app
rm -rf "$app" && mkdir -p "$app" || exit 1
for f in "$game"/*; do b=${f##*/}; [ "$b" = package.json ] || ln -s "$f" "$app/$b"; done
inject=
[ -f "$HERE/cc-native-init.js" ] && cp "$HERE/cc-native-init.js" "$app/" && inject=',"inject_js_start":"cc-native-init.js"'
[ -f "$HERE/cc-evpad.js" ] && cp "$HERE/cc-evpad.js" "$app/" && inject="$inject"',"inject_js_end":"cc-evpad.js"'
cat > "$app/package.json" <<EOF
{"name":"CrossCode","version":"1.0.0","main":"assets/node-webkit.html",
 "chromium-args":"--ignore-gpu-blocklist --disable-background-networking --password-store=basic"$inject,
 "window":{"toolbar":false,"icon":"favicon.png","width":1280,"height":960,"fullscreen":true}}
EOF
unset WAYLAND_DISPLAY
log "game $game, saves $save, flags ${flags[*]}"
cd "$game" || exit 2
exec "$NW" --user-data-dir="$profile" "${flags[@]}" "$app"
