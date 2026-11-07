#!/usr/bin/env python3
"""Tests tools/patch43.py end to end on temporary copies of original/node-webkit.html laid out like real installs
(Windows/Proton and Linux depot: <game>/assets/..., macOS: CrossCode.app/Contents/Resources/app.nw/assets/...).
    python3 -I tools/test_patch43.py        (needs original/ with the pristine Steam files, and node for the JS check)
"""
import hashlib, os, re, shutil, subprocess, sys, tempfile
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(R, 'tools'))
import patch43 as P

CLI = [sys.executable, '-I', os.path.join(R, 'tools', 'patch43.py')]
sha = lambda b: hashlib.sha256(b).hexdigest()
rd = lambda p: open(p, 'rb').read()
fails = []
def ok(c, m):
    print(('  ok   ' if c else '  FAIL ') + m)
    if not c: fails.append(m)
def run(*a):
    p = subprocess.run(CLI + list(a), capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr

orig = rd(os.path.join(R, 'original', 'node-webkit.html'))
ok(sha(orig) == P.PRISTINE, 'original/node-webkit.html is the pristine Steam file')
out = P.patch_bytes(orig)
ok(sha(out) == P.PATCHED, 'patch_bytes output == PATCHED (%s..., the 43-480 build the user verified)' % P.PATCHED[:12])
ok(P.unpatch_bytes(out) == orig, 'unpatch_bytes restores the exact original bytes')
diff = [(a, b) for a, b in zip(orig.split(b'\r\n'), out.split(b'\r\n')) if a != b]
ok(len(orig.split(b'\r\n')) == len(out.split(b'\r\n')) and diff == [(b'  var IG_WIDTH = 568;', b'  var IG_WIDTH = 480;'),
   (b'  var IG_HEIGHT = 320;', b'  var IG_HEIGHT = 360;')], 'only the two IG_ lines differ; CRLF line structure kept')
for i, blk in enumerate(re.findall(rb'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>', out, re.S)):
    js = 'new (require("vm").Script)(require("fs").readFileSync(0,"utf8"))'
    p = subprocess.run(['node', '-e', js], input=blk, capture_output=True)
    ok(p.returncode == 0, 'inline <script> %d parses' % i)

tmp = tempfile.mkdtemp(prefix='cc43-test-')
try:
    layouts = {'windows': 'CrossCode', 'macos': 'CrossCode-mac/CrossCode.app/Contents/Resources/app.nw'}
    for name, rel in layouts.items():
        game = os.path.join(tmp, rel)
        os.makedirs(os.path.join(game, 'assets', 'js'))
        html = os.path.join(game, 'assets', 'node-webkit.html')
        open(html, 'wb').write(orig); os.chmod(html, 0o640)
        shutil.copy(os.path.join(R, 'original', 'game.compiled.js'), os.path.join(game, 'assets', 'js'))
        arg = game if name == 'windows' else os.path.join(tmp, 'CrossCode-mac')
        print('== %s layout (%s)' % (name, os.path.relpath(arg, tmp)))
        rc, o = run(arg)
        ok(rc == 0 and sha(rd(html)) == P.PATCHED, 'patch: exit 0, file == PATCHED')
        ok(sha(rd(html + P.BACKUP_SUFFIX)) == P.PRISTINE, 'backup next to it is the original')
        ok(os.stat(html).st_mode & 0o777 == 0o640, 'file mode kept (0640)')
        ok('note:' not in o, 'no game-version note with the tested game.compiled.js')
        rc, o = run(arg)
        ok(rc == 0 and 'already patched' in o and sha(rd(html)) == P.PATCHED, 'patch again: no-op')
        rc, o = run('--status', arg)
        ok(rc == 0 and 'patched for 4:3' in o and 'the original' in o, 'status: patched, backup is the original')
        rc, o = run('--revert', arg)
        ok(rc == 0 and rd(html) == orig and not os.path.exists(html + P.BACKUP_SUFFIX), 'revert: original bytes back, backup removed')
        rc, o = run('--revert', arg)
        ok(rc == 0 and 'nothing to revert' in o and rd(html) == orig, 'revert again: no-op')
        ok(sorted(os.listdir(os.path.join(game, 'assets'))) == ['js', 'node-webkit.html'], 'no leftover files in assets/')

    game = os.path.join(tmp, 'CrossCode'); html = os.path.join(game, 'assets', 'node-webkit.html')
    print('== refusals and recovery')
    bad = orig.replace(b'CrossCode Min', b'CrossCode Mod')
    open(html, 'wb').write(bad)
    rc, o = run(game)
    ok(rc == 1 and 'refusing' in o and rd(html) == bad and not os.path.exists(html + P.BACKUP_SUFFIX), 'unknown CrossCode html: refused, untouched, no backup')
    open(html, 'wb').write(b'<html>not the game</html>')
    rc, o = run(game)
    ok(rc == 1 and 'not CrossCode' in o, 'a different file: refused')
    rc, o = run(os.path.join(tmp, 'nowhere'))
    ok(rc == 1 and 'no assets/node-webkit.html' in o, 'folder without the game: refused')
    open(html, 'wb').write(orig); run(game)
    open(html, 'wb').write(out + b'\r\n')  # patched, then changed by something else
    rc, o = run('--revert', game)
    ok(rc == 0 and rd(html) == orig and 'restoring the backup' in o, 'revert of a changed patched file falls back to the backup')
    open(html, 'wb').write(bad)
    rc, o = run('--revert', game)
    ok(rc == 1 and 'Verify integrity' in o and rd(html) == bad, 'revert without a backup of an unknown file: refused, untouched')
    open(html, 'wb').write(orig)
    open(os.path.join(game, 'assets', 'js', 'game.compiled.js'), 'ab').write(b'\n')
    rc, o = run(html)
    ok(rc == 0 and 'note:' in o and sha(rd(html)) == P.PATCHED, 'html given directly; other game.compiled.js: patched with a note')
    run('--revert', html)
    print('== --out')
    o1 = os.path.join(tmp, 'o1.html'); o2 = os.path.join(tmp, 'o2.html')
    rc, _ = run(os.path.join(R, 'original', 'node-webkit.html'), '--out', o1)
    ok(rc == 0 and sha(rd(o1)) == P.PATCHED and sha(rd(os.path.join(R, 'original', 'node-webkit.html'))) == P.PRISTINE, '--out writes the patched copy, input untouched')
    rc, _ = run('--revert', o1, '--out', o2)
    ok(rc == 0 and rd(o2) == orig, '--revert --out writes the original')
    rc, o = run(o1, '--out', o2)
    ok(rc == 1 and 'already patched' in o, '--out from a patched file: refused')
    rc, _ = run('--bogus', o1)
    ok(rc == 2, 'unknown flag: usage, exit 2')
finally:
    shutil.rmtree(tmp)
print('\nRESULT:', 'FAIL (%d)' % len(fails) if fails else 'PASS')
sys.exit(1 if fails else 0)
