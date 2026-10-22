# crosscode-43aspect

Native 4:3 for *CrossCode* (Radical Fish Games, Steam appid 368340), part of the nova-43aspect collection.

## Status
- **Planned.** Scaffold only, nothing verified yet. Engine facts below are first impressions from the install folder; confirm each one before relying on it.

## Engine facts (unverified)
- HTML5/JavaScript game (impact.js) running in **NW.js** (`nw.dll`, `node.dll`, `package.json`). The game code is plain JS under `assets/` (`assets/js/game.compiled.js`), so it is very moddable (CCLoader exists).
- The Windows build ships ANGLE (`libEGL.dll`, `libGLESv2.dll`, `d3dcompiler_47.dll`) **and a `swiftshader/` folder**. Under Proton + FEX, Chromium may fall back to SwiftShader software rendering, which would explain the jitter.
- Base resolution 568x320. The game offers "fit" and "stretch" scaling; stretch looks bad at 4:3.

## Plan
**Priority 1 is the jitter.** The user won't play it on the Nova until it's smooth, so 4:3 comes second.

1. **Diagnose:** find out what Chromium is rendering with on the device (GPU process flags, `chrome://gpu`-style info, NW.js logs). Measure frame pacing from an adb screenrecord.
2. **Cheap fixes:** NW.js `chromium-args` in `package.json` (ANGLE backend choice, `--ignore-gpu-blocklist`, vsync and frame-rate-limit flags, GPU rasterization). Test one change per run.
3. **Bigger idea:** the game is a web app, so it may run on a native ARM64 runtime with no x86 translation at all (ARM64 Chromium or Electron in the proot, or an Android WebView). Check which NW.js/node APIs the game needs (saves, Steam, file access) before going down this road.
4. **Then 4:3:** pick a pixel-perfect 4:3 base resolution (e.g. 427x320 at 3x = 1281x960, or 480x360 / 320x240 multiples) via a JS patch, and check the HUD and menus.

## Conventions
- Follow the nova-43aspect skill (device access, test workflow, repo conventions, web patcher design contract).
- Patch only the Windows build pulled from the device into `original/` (gitignored, read-only).
- Never commit game files, decompiler output, logs or screenshots.
