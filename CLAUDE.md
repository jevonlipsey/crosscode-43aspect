# crosscode-43aspect

Native 4:3 for *CrossCode* (Radical Fish Games, Steam appid 368340), part of the nova-43aspect collection.

## Status
- **v1.0.0 patch ready (4:3 only).** `assets/node-webkit.html` IG 568x320 -> 480x360, pristine `16c7b73f…` -> `6031c988…`
  (the build the user played on the Nova and judged "perfect 4:3"). CLI `tools/patch43.py`, web patcher `web/app/`.
- Frame pacing is NOT shipped: the start-time gate (`tools/cc-pace.js`) does not fix 120 Hz judder in simulation
  (`tools/test-pace.mjs`); a present-aligned design is the next candidate (see CLAUDE.local.md).

## Commands
- `python3 -I tools/test_patch43.py` (CLI), `node web/test/parity.mjs` (web core == CLI), `tools/build_web.sh && node web/test/e2e.mjs`
  (real page in headless Chrome), `node web/test/shots.mjs --out <dir>` (every page state, ?mock), `node tools/test-pace.mjs` (pacing research).
- The edit list and hashes live only in `tools/patch43.py`; `tools/gen_web_data.py` exports them for the web at build time.
- `tools/variants43.py` + `tools/verify43.py` build/verify the old dev variants (427/568/640/480) into `out/`.

## Engine facts
- HTML5/JavaScript game (impact.js) running in **NW.js** (`nw.dll`, `node.dll`, `package.json`). The game code is plain JS under `assets/` (`assets/js/game.compiled.js`), so it is very moddable (CCLoader exists).
- Under Proton the Windows build renders through ANGLE d3d11 -> DXVK -> Turnip (real GPU, measured on device); the game draws
  with 2D canvas. Game loop: one step per requestAnimationFrame, variable dt capped at 1/30 s (`ig.Timer.maxStep`).
- Base resolution 568x320 (`IG_WIDTH`/`IG_HEIGHT` in node-webkit.html); view, HUD and menus derive from them at runtime.
  Options > Display Type (Original/Double/Fit/Stretch) scales the canvas; Fit is the default (`IG_SCREEN_MODE_OVERRIDE = 2`).
- The Windows and macOS depots ship byte-identical node-webkit.html and game.compiled.js.

## Open work
1. Device check of the shipped patch through the web patcher's output on the user's Proton install (same bytes as live `6031c988…`).
2. Steam-native route (`tools/steam-native.sh`, Linux depot + arm64 NW.js inside the real Steam install): built, never run.
3. Present-aligned frame pacing for Proton at 120 Hz (design in CLAUDE.local.md); judge only from screen captures.

## Conventions
- Follow the nova-43aspect skill (device access, test workflow, repo conventions, web patcher design contract).
- Pristine inputs live in `original/` (gitignored, read-only), pulled from the device (== the Mac depot's files).
- Never commit game files, decompiler output, logs or screenshots.
