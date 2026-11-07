#!/usr/bin/env bash
# builds the browser patcher into web/dist/ (a static site). run from anywhere:
#   tools/build_web.sh
# pure JavaScript, so there is no toolchain beyond python3; no game files are needed
# (cc43-data.js, the edit list and the known hashes, is generated from tools/patch43.py).
set -euo pipefail

cd "$(dirname "$0")/.."

DIST=web/dist
rm -rf "$DIST"
mkdir -p "$DIST"

echo "[+] generating cc43-data.js from tools/patch43.py"
python3 -I tools/gen_web_data.py "$DIST/cc43-data.js"

for f in index.html style.css main.js patcher-runtime.js cc43-core.js; do
  cp "web/app/$f" "$DIST/$f"
done

touch "$DIST/.nojekyll"

echo "[+] web/dist ready"
for f in cc43-data.js cc43-core.js patcher-runtime.js main.js index.html style.css; do
  echo "    $f: $(wc -c < "$DIST/$f" | awk '{printf "%.1f KB", $1/1024}')"
done
echo "    total:      $(du -sk "$DIST" | cut -f1) KB"
