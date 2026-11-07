# CrossCode 4:3 Aspect Ratio Patch

Native 4:3 for **CrossCode**, aimed at the **Retroid Pocket Nova** (4.5", 1280x960) and any other 4:3 display. The game draws a 480x360 view instead of 568x320, and its HUD and menus lay themselves out for it at full size: nothing is shrunk, and on 1280x960 the game is drawn at 2.67x, larger than the stock 2.25x on a 16:9 screen. Part of the [Nova 4:3 collection](https://jevonlipsey.github.io/nova-43aspect/).

The patcher ships only our own patch logic and modifies your own copy of the game. **No game code is redistributed.**

> Unofficial fan project, not affiliated with or endorsed by Radical Fish Games or Deck13. CrossCode and its files belong to them. The code here is MIT licensed ([LICENSE](LICENSE)).

## Install

The mod changes one file in your own copy of the game: `assets/node-webkit.html` (about 2 KB). It is the same file in the Windows and macOS Steam depots, and the Linux depot reads the same file, so one patch covers Proton, the native Linux build and macOS.

- **Web patcher** (any browser, including your phone): <https://jevonlipsey.github.io/crosscode-43aspect/>. Choose `node-webkit.html` from the game's `assets` folder, download the patched file, and put it back in `assets`. It runs in your browser and the file is not uploaded.
- **Desktop**: `python3 tools/patch43.py "/path/to/CrossCode"` (Python 3.6+, standard library only). It checks the file, keeps a backup next to it (`node-webkit.html.cc43-backup`) and writes the patched one.
- **Undo**: `python3 tools/patch43.py --revert "/path/to/CrossCode"`, put your backup back, or use Steam's **Verify integrity of game files**. Saves are never touched.

Where the file is:

| Install | `node-webkit.html` |
|---|---|
| Windows (and Proton) | `C:\Program Files (x86)\Steam\steamapps\common\CrossCode\assets\` |
| Linux, Steam Deck (native Linux build or Proton) | `~/.local/share/Steam/steamapps/common/CrossCode/assets/` |
| DroidDeck (Retroid Pocket Nova) | `/mnt/droiddeck-sd/steamapps/common/CrossCode/assets/` (SD card) or `/root/.local/share/Steam/steamapps/common/CrossCode/assets/` |
| macOS | `CrossCode.app/Contents/Resources/app.nw/assets/` |

Then start the game fullscreen (1280x960 on the Nova) and keep **Options > Display Type** on **Fit**, the default. After a game update, patch the new file again.

### Proton (Windows build on Linux, Steam Deck, DroidDeck)
Nothing special: patch the file in the install folder as above. No launch options are needed.

### Native NW.js (the Linux depot, or your own NW.js runtime)
CrossCode is a web game (impact.js) running in NW.js. The Linux depot runs it natively from the same `assets/node-webkit.html`, so patch that file in the same way. If you run the game folder with a different NW.js build (for example the official linux-arm64 NW.js on an ARM handheld), the patch is the same: it lives in the game's own files, not in the runtime.

## What the patch changes

Two exact byte replacements in `assets/node-webkit.html`, and nothing else (the CRLF line endings and every other byte stay as they are):

```
var IG_WIDTH = 568;   ->   var IG_WIDTH = 480;
var IG_HEIGHT = 320;  ->   var IG_HEIGHT = 360;
```

CrossCode computes its view, HUD anchors and menu layout from these two values at runtime, so the whole UI re-anchors to the 4:3 frame without touching the game code (`assets/js/game.compiled.js` stays as it is). 480x360 is about 95% of the stock pixel count, so it costs no performance. Narrower views (427x320, an exact 3x) were tried and rejected: below about 480 wide, the equipment menu overlaps its stat column.

The patcher only accepts the known Steam file:

| file | sha256 |
|---|---|
| `assets/node-webkit.html`, original (Steam) | `16c7b73f4f92822cc712bfd4db311be0ab60ddc917188eadf5ea2845d1efb6cc` |
| `assets/node-webkit.html`, patched | `6031c9883f3755a67f6bee8ae264ee9d0915ad5a7dffd4a93de808da550232dd` |
| `assets/js/game.compiled.js` it was tested with (not changed) | `28a166b4c5f650056f58294a22b014e2ddec70bf454861ee2095bc885e270521` |

Any other `node-webkit.html` is refused and nothing is written. A different `game.compiled.js` only prints a note.

## Usage

```
python3 tools/patch43.py GAME                     patch
python3 tools/patch43.py --revert GAME            put the original back (and remove the backup)
python3 tools/patch43.py --status GAME            report what is installed, change nothing
python3 tools/patch43.py [--revert] IN --out OUT  write the result to OUT and leave IN alone
```

`GAME` is the CrossCode folder, its `assets` folder, `CrossCode.app`, or the `node-webkit.html` file itself. Writes are atomic (temporary file and rename) and checked by hash afterwards.

## Web patcher

`web/app/` is a static page in plain JavaScript (no WebAssembly, nothing to download). `web/app/cc43-core.js` applies the same edit list as the CLI. `tools/gen_web_data.py` generates that list and the known hashes from `tools/patch43.py` at build time, so the two cannot drift apart. `tools/build_web.sh` builds `web/dist/`, and `.github/workflows/pages.yml` publishes it to GitHub Pages. The file picker has no type filter, because Android and iOS grey out files that a filter does not list. The page checks the content instead.

## Verification

- `python3 -I tools/test_patch43.py`: the CLI on temporary copies laid out like a Windows/Linux install and a macOS app (patch, no-op re-patch, status, revert, refusals of unknown and unrelated files, revert from the backup, `--out`, file mode kept, inline scripts still parse).
- `node web/test/parity.mjs`: the browser core and the CLI give the same bytes and the same verdict for the original, the patched file, a changed file, an LF-converted file and an unrelated file.
- `node web/test/e2e.mjs` (after `tools/build_web.sh`): the built page in headless Chrome, through the real file picker. The downloaded file is byte-identical to the CLI output, and the refusal views appear for the other inputs.
- `node web/test/shots.mjs`: screenshots of every page state through `?mock`, at desktop and phone width, light and dark.
- In the game: the patched file (`6031c988…`) is the build played on the Retroid Pocket Nova under Proton (no letterbox, HUD inside the frame), and it also booted under a native arm64 NW.js runtime at full 1280x960 with the HUD anchored correctly. The menus (items, skills, equipment, status, map, save, options, quests), pause and a dialogue box were rendered with the same file on the macOS build (`tools/rt43.sh`).

These tests need the original files in `original/` (gitignored, never committed).

## Limits

- **Steam build only.** Other stores, or a changed `node-webkit.html`, are refused until the patcher knows that file. The Linux depot's copy has not been hashed yet. If it differs, the patcher refuses it and says so.
- **Frame pacing is not part of this patch.** Under Proton on a 120 Hz screen, the game's frames land 1, 2 or 3 refreshes apart. A simple 60 fps gate was tried (`tools/cc-pace.js`, simulated in `tools/test-pace.mjs`) and does not fix it, so it is not shipped.
- `tools/` also holds the development and device scripts (frame-timing probe, Nova deploy and run scripts, native arm64 launcher). You don't need them to use the patch.

## AI disclosure

This project was built with the help of Claude (Anthropic). The patch was checked with byte-for-byte tests against the original and patched files, a parity test between the browser and command-line patchers, and in the game on a real device.
