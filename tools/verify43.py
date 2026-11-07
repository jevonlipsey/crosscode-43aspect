#!/usr/bin/env python3
"""Verify out/43-<variant>/ against the pristine originals.  usage: verify43.py [variant ...]  (default: every out/43-* present)

Checks per output file:
  1. original/<file> sha256 == the pristine hash recorded in CLAUDE.local.md (and == patch43.PRISTINE)
  2. the output equals the original with ONLY the registered edits applied (rebuilt independently here by position,
     not by calling patch43.apply), so any other differing byte is a failure; line endings are therefore preserved
  3. each edit's old pattern occurs exactly the expected number of times in the pristine file
  4. JS parses (vm.Script via node) for .js files and for the inline <script> blocks of the html; package.json parses as JSON
Also prints the game's own FIT-mode scaling math for a 1280x960 window (copied from sc.OptionModel._setDisplaySize).
"""
import glob, hashlib, json, os, re, subprocess, sys
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, f'{R}/tools')
import variants43 as patch43
sha = lambda b: hashlib.sha256(b).hexdigest()
fails = []
def fail(m): fails.append(m); print('  FAIL', m)

def node_check(code, label):
    js = 'const vm=require("vm");const s=require("fs").readFileSync(0,"utf8");try{new vm.Script(s,{filename:process.argv[1]});}catch(e){console.error(String(e));process.exit(1)}'
    p = subprocess.run(['node', '-e', js, label], input=code.encode('utf-8'), capture_output=True)
    if p.returncode: fail(f'{label}: JS does not parse: {p.stderr.decode()[:200]}')
    else: print(f'  ok   {label}: parses')

def fit(W, H, ww=1280, wh=960):  # sc.OptionModel._setDisplaySize, FIT branch (display-type 2) + snap
    a, b = (wh * W / H, wh) if ww / wh > W / H else (ww, H * ww / W)
    for i in range(1, 4):
        if abs(a - W * i) < 20: a, b = W * i, H * i
    return a, b

local = open(f'{R}/CLAUDE.local.md').read()
for name, h in patch43.PRISTINE.items():
    if h not in local: fail(f'CLAUDE.local.md does not record the pristine sha256 for {name} ({h[:12]}...)')

variants = sys.argv[1:] or sorted(os.path.basename(d)[3:] for d in glob.glob(f'{R}/out/43-*') if os.path.isdir(d))
if not variants: sys.exit('nothing to verify: run tools/variants43.py first')
for v in variants:
    print(f'== 43-{v}')
    W, H = patch43.SIZES[v]
    eds_all = patch43.edits(v)
    root = f'{R}/out/43-{v}'
    found = {os.path.relpath(p, root) for p in glob.glob(f'{root}/**/*', recursive=True) if os.path.isfile(p)}
    expect = {patch43.DEVICE_PATH[n] for n in eds_all}
    if found != expect: fail(f'file set {sorted(found)} != expected {sorted(expect)}')
    for name, eds in eds_all.items():
        rel = patch43.DEVICE_PATH[name]
        src = open(f'{R}/original/{name}', 'rb').read()
        if sha(src) != patch43.PRISTINE[name]: fail(f'original/{name} sha {sha(src)[:12]} is not pristine')
        try: out = open(f'{root}/{rel}', 'rb').read()
        except FileNotFoundError: fail(f'missing {rel}'); continue
        # independent rebuild: collect (start, end, new) spans, require exact counts and no overlaps
        spans = []
        for old, new, n in eds:
            pos = [m.start() for m in re.finditer(re.escape(old), src)]
            if len(pos) != n: fail(f'{rel}: {old[:50]!r} occurs {len(pos)}x in pristine, expected {n}x')
            spans += [(p, p + len(old), new) for p in pos]
        spans.sort()
        if any(spans[i][1] > spans[i + 1][0] for i in range(len(spans) - 1)): fail(f'{rel}: overlapping edits')
        rebuilt, cur = b'', 0
        for s, e, new in spans: rebuilt += src[cur:s] + new; cur = e
        rebuilt += src[cur:]
        if rebuilt != out:
            i = next((k for k in range(min(len(out), len(rebuilt))) if out[k] != rebuilt[k]), min(len(out), len(rebuilt)))
            fail(f'{rel}: output differs from pristine+registered edits at byte {i}')
        else:
            print(f'  ok   {rel}: pristine {sha(src)[:12]} -> {sha(out)[:12]}; {len(spans)} edit span(s) at bytes {[s for s, _, _ in spans]}; CRLF {src.count(b"\r\n")}->{out.count(b"\r\n")}, LF-only {src.count(b"\n")-src.count(b"\r\n")}->{out.count(b"\n")-out.count(b"\r\n")}')
        if rel.endswith('.js'): node_check(out.decode('utf-8'), rel)
        elif rel.endswith('.html'):
            for k, blk in enumerate(re.findall(r'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>', out.decode('utf-8'), re.S)):
                if blk.strip(): node_check(blk, f'{rel}#inline{k}')
            m = (re.search(rb'var IG_WIDTH = (\d+);', out), re.search(rb'var IG_HEIGHT = (\d+);', out))
            if (int(m[0][1]), int(m[1][1])) != (W, H): fail(f'{rel}: IG_WIDTH/HEIGHT not {W}x{H}')
        elif rel.endswith('.json'):
            try: json.loads(out)
            except Exception as ex: fail(f'{rel}: bad json {ex}')
    a, b = fit(W, H)
    print(f'  scaling: {W}x{H} ({W/H:.4f}) on 1280x960 FIT -> canvas CSS {a:g}x{b:g} = {a/W:.4f}x ({"exact integer" if a/W==int(a/W) else "non-integer"}); pixels vs 568x320: {W*H/(568*320):.0%}')
print('\nRESULT:', 'FAIL (%d)' % len(fails) if fails else 'PASS')
sys.exit(1 if fails else 0)
