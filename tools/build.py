#!/usr/bin/env python3
"""Build candidate files from original/ into out/ (gitignored via build/ rule? no: out/ is added to .gitignore).
usage: build.py <variant>...   variants: diag, flagsB, flagsC, 43-640, 43-568, 43-427
 diag    node-webkit.html with the frame-timing probe (needs tools/cc-diag.js deployed to assets/)
 flagsB  package.json + --disable-accelerated-2d-canvas
 flagsC  package.json with --disable-gpu instead of --in-process-gpu
 43-*    REMOVED: use tools/patch43.py
"""
import sys, os, re
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
o = lambda f: open(f'{R}/original/{f}', newline='').read()
os.makedirs(f'{R}/out', exist_ok=True)
def w(n, s): open(f'{R}/out/{n}', 'w', newline='').write(s); print('wrote out/' + n)
for v in sys.argv[1:]:
    if v == 'diag':
        w('node-webkit.diag.html', o('node-webkit.html').replace('</body>', '<script src="cc-diag.js"></script>\r\n</body>'))
    elif v == 'flagsB':
        w('package.B.json', o('package.json').replace('--password-store=basic', '--password-store=basic --disable-accelerated-2d-canvas'))
    elif v == 'flagsC':
        w('package.C.json', o('package.json').replace('--in-process-gpu ', '--disable-gpu '))
    elif v.startswith('43-'):
        sys.exit('43-* variants moved to tools/patch43.py (exact-match, count-checked, writes out/43-<v>/); verify with tools/verify43.py')
