#!/usr/bin/env python3
"""CrossCode 4:3 patch (crosscode-43aspect). Changes your own copy of the game; no game files are shipped.

    python3 tools/patch43.py GAME                 patch
    python3 tools/patch43.py --revert GAME        put the original file back
    python3 tools/patch43.py --status GAME        report what is installed, change nothing
    python3 tools/patch43.py [--revert] IN --out OUT    write the result to OUT and leave IN alone

GAME is the CrossCode folder (Windows/Proton, the Linux depot, a native NW.js setup, or CrossCode.app on macOS), its
assets folder, or assets/node-webkit.html itself.

Only assets/node-webkit.html changes, and it must be byte-identical to the Steam file (sha256 below) or nothing is
written. The edit is two exact, count-checked byte replacements, IG_WIDTH 568 -> 480 and IG_HEIGHT 320 -> 360, so
the rest of the file (CRLF line endings included) is untouched. The game lays out its view, HUD and menus from these
two numbers, so the whole UI re-anchors to a 4:3 frame at full size: on 1280x960 the game draws at 2.67x, larger
than the stock 2.25x on a 16:9 screen. The game code (assets/js/game.compiled.js) is not touched.
Patching in place keeps a backup next to the file (node-webkit.html.cc43-backup). --revert rebuilds the original from
the patched file (or restores that backup) and removes the backup. Steam's "Verify integrity of game files" also
restores the original.
"""
import hashlib, os, shutil, sys

VERSION = '1.0.0'
PRISTINE = '16c7b73f4f92822cc712bfd4db311be0ab60ddc917188eadf5ea2845d1efb6cc'  # assets/node-webkit.html (Steam)
PATCHED = '6031c9883f3755a67f6bee8ae264ee9d0915ad5a7dffd4a93de808da550232dd'   # the same file after EDITS
# assets/js/game.compiled.js the patch was tested with (Steam Windows depot == macOS depot); a different one only warns
TESTED_GAME_JS = '28a166b4c5f650056f58294a22b014e2ddec70bf454861ee2095bc885e270521'
BACKUP_SUFFIX = '.cc43-backup'
W, H = 480, 360

# (old, new, count in the pristine file). Each old must occur exactly count times, and each new must not occur at all.
EDITS = [
    (b'var IG_WIDTH = 568;', b'var IG_WIDTH = %d;' % W, 1),
    (b'var IG_HEIGHT = 320;', b'var IG_HEIGHT = %d;' % H, 1),
]

def sha(b): return hashlib.sha256(b).hexdigest()

class Refused(Exception): pass

def _replace(data, edits, reverse=False):
    for old, new, n in edits:
        if reverse: old, new = new, old
        if data.count(old) != n: raise Refused('expected %d x %r, found %d' % (n, old, data.count(old)))
        if data.count(new) != 0: raise Refused('%r is already there' % new)
        data = data.replace(old, new)
    return data

def classify(data):
    """'pristine' | 'patched' | 'crosscode' (a CrossCode node-webkit.html this patcher does not know) | 'other'"""
    h = sha(data)
    if h == PRISTINE: return 'pristine'
    if h == PATCHED: return 'patched'
    if b'<title>CrossCode' in data and b'var IG_WIDTH = ' in data: return 'crosscode'
    return 'other'

def patch_bytes(data):
    """pristine bytes -> patched bytes, verified: exact output hash and an exact round trip back to the input"""
    if sha(data) != PRISTINE: raise Refused('input is not the Steam node-webkit.html (sha256 %s)' % sha(data))
    out = _replace(data, EDITS)
    if sha(out) != PATCHED: raise Refused('output sha256 %s, expected %s' % (sha(out), PATCHED))
    if _replace(out, list(reversed(EDITS)), reverse=True) != data: raise Refused('output does not revert to the input')
    return out

def unpatch_bytes(data):
    """patched bytes -> the original bytes, verified by hash"""
    if sha(data) == PRISTINE: return data
    if sha(data) != PATCHED: raise Refused('not a file this patcher made (sha256 %s)' % sha(data))
    out = _replace(data, list(reversed(EDITS)), reverse=True)
    if sha(out) != PRISTINE: raise Refused('reverted file does not match the original hash')
    return out

def find_html(path):
    if os.path.isfile(path): return path
    for rel in ('assets/node-webkit.html', 'node-webkit.html', 'Contents/Resources/app.nw/assets/node-webkit.html',
                'CrossCode.app/Contents/Resources/app.nw/assets/node-webkit.html'):
        p = os.path.join(path, rel)
        if os.path.isfile(p): return p
    raise Refused('no assets/node-webkit.html under %s (give the CrossCode game folder)' % path)

def read(p):
    with open(p, 'rb') as f: return f.read()

def write(p, data, like=None):
    """atomic write (temp file + rename) that keeps the mode of `like`, then checks what landed on disk"""
    tmp = p + '.cc43-tmp'
    with open(tmp, 'wb') as f: f.write(data)
    if like and os.path.exists(like): shutil.copymode(like, tmp)
    os.replace(tmp, p)
    if sha(read(p)) != sha(data): raise Refused('%s did not write correctly' % p)

def is_backup(p): return os.path.isfile(p) and sha(read(p)) == PRISTINE

def describe(kind, data):
    return {'pristine': 'original (not patched)', 'patched': 'patched for 4:3 (crosscode-43aspect %s)' % VERSION,
            'crosscode': 'a CrossCode node-webkit.html this patcher does not know',
            'other': 'not CrossCode\'s node-webkit.html'}[kind] + ', sha256 ' + sha(data)

def game_js_note(html):
    js = os.path.join(os.path.dirname(html), 'js', 'game.compiled.js')
    if os.path.isfile(js) and sha(read(js)) != TESTED_GAME_JS:
        print('  note: assets/js/game.compiled.js is not the version this was tested with (%s...); the patch\n'
              '  still applies, but check the menus' % TESTED_GAME_JS[:12])

def main(argv):
    out = None
    if '--out' in argv:
        i = argv.index('--out')
        if i + 1 >= len(argv): return usage()
        out = argv[i + 1]; argv = argv[:i] + argv[i + 2:]
    flags = [a for a in argv if a.startswith('--')]
    args = [a for a in argv if not a.startswith('--')]
    if '--help' in flags: print(__doc__); return 0
    if '--version' in flags: print('crosscode-43aspect patch43.py', VERSION); return 0
    if any(f not in ('--revert', '--status') for f in flags) or len(flags) > 1 or len(args) != 1: return usage()
    html = find_html(args[0])
    backup = html + BACKUP_SUFFIX
    data = read(html)
    kind = classify(data)
    print(html + '\n  ' + describe(kind, data))

    if '--status' in flags:
        if os.path.exists(backup): print('  backup: %s (%s)' % (backup, 'the original' if is_backup(backup) else 'NOT the original'))
        return 0

    if '--revert' in flags:
        if kind == 'patched': orig = unpatch_bytes(data)
        elif kind == 'pristine': orig = data
        elif is_backup(backup): orig = read(backup); print('  restoring the backup', backup)
        else: raise Refused('cannot revert this file; use Steam > Properties > Installed Files > Verify integrity')
        if out: write(out, orig); print('wrote the original to %s (sha256 %s)' % (out, PRISTINE)); return 0
        if kind != 'pristine': write(html, orig, like=html)
        if is_backup(backup): os.remove(backup)
        print('reverted: the original file is back (sha256 %s)' % PRISTINE if kind != 'pristine' else
              'nothing to revert: this is already the original file')
        return 0

    if kind == 'patched':
        if out: raise Refused('this file is already patched; give the original file')
        print('already patched: nothing to do'); return 0
    if kind != 'pristine':
        raise Refused('refusing to patch: only the Steam file (sha256 %s) is supported. Get the original back with '
                      'Steam > Properties > Installed Files > Verify integrity, then run this again' % PRISTINE)
    result = patch_bytes(data)
    if out: write(out, result); print('wrote %s (sha256 %s)' % (out, PATCHED)); return 0
    game_js_note(html)
    if not is_backup(backup): write(backup, data, like=html)
    write(html, result, like=html)
    print('patched: 480x360 4:3 view (sha256 %s)\n  backup: %s\n  undo:   python3 %s --revert "%s"'
          % (PATCHED, backup, sys.argv[0], args[0]))
    return 0

def usage():
    print(__doc__.split('\n\n')[1].strip(), file=sys.stderr)
    return 2

if __name__ == '__main__':
    try: sys.exit(main(sys.argv[1:]))
    except Refused as e:
        print('error:', e, file=sys.stderr); sys.exit(1)
