#!/usr/bin/env python3
"""Build candidate files from original/ into out/ (gitignored via build/ rule? no: out/ is added to .gitignore).
usage: build.py <variant>...   variants: diag, flagsB, flagsC, 43-640, 43-568, 43-427
 diag    node-webkit.html with the frame-timing probe (needs tools/cc-diag.js deployed to assets/)
 flagsB  package.json + --disable-accelerated-2d-canvas
 flagsC  package.json with --disable-gpu instead of --in-process-gpu
 43-*    node-webkit.html with IG_WIDTH/IG_HEIGHT set for 4:3 (640x480 = exact 2x, 568x426, 427x320 = exact 3x)
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
        W, H = {'640': (640, 480), '568': (568, 426), '427': (427, 320)}[v[3:]]
        s = o('node-webkit.html')
        s = s.replace('var IG_WIDTH = 568;', f'var IG_WIDTH = {W};').replace('var IG_HEIGHT = 320;', f'var IG_HEIGHT = {H};')
        w(f'node-webkit.{v}.html', s)
