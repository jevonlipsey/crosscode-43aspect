#!/usr/bin/env python3
"""Generate the 4:3 file sets from original/ into out/43-<variant>/ (mirrors the game dir: assets/..., package.json).

usage: variants43.py [variant ...]      variants: 427 (default first choice), 640, 568, 480   (no args = 427 640 568)

Every edit is an exact-match, count-checked bytes replacement against the pristine file (fail loudly otherwise).
Files are read and written as bytes, so line endings and encoding are preserved outside the edits.
Verify with tools/verify43.py.
"""
import hashlib, os, sys
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRISTINE = {  # sha256 of original/ == device (CLAUDE.local.md)
    'game.compiled.js': '28a166b4c5f650056f58294a22b014e2ddec70bf454861ee2095bc885e270521',
    'node-webkit.html': '16c7b73f4f92822cc712bfd4db311be0ab60ddc917188eadf5ea2845d1efb6cc',
    'package.json': '894c1f1b132dac045aaf60fab2c7520bcbae21845588f206f8236e2214a0a430',
}
DEVICE_PATH = {'game.compiled.js': 'assets/js/game.compiled.js', 'node-webkit.html': 'assets/node-webkit.html', 'package.json': 'package.json'}
SIZES = {'427': (427, 320), '640': (640, 480), '568': (568, 426), '480': (480, 360)}

def sha(b): return hashlib.sha256(b).hexdigest()

def edits(variant):
    """{pristine file name: [(old bytes, new bytes, expected count), ...]}"""
    W, H = SIZES[variant]
    e = {
        'node-webkit.html': [
            (b'var IG_WIDTH = 568;', b'var IG_WIDTH = %d;' % W, 1),
            (b'var IG_HEIGHT = 320;', b'var IG_HEIGHT = %d;' % H, 1),
        ],
    }
    if variant == '640':
        # exact 2x on 1280x960: nearest-neighbour upscale (style.css sets no image-rendering, so Chromium defaults to bilinear = soft pixels)
        e['node-webkit.html'].append((b'</head>', b'<style>#canvas{image-rendering:pixelated}</style>\r\n</head>', 1))
    return e

def apply(data, eds, name):
    for old, new, n in eds:
        c = data.count(old)
        if c != n: sys.exit(f'FAIL {name}: pattern {old[:60]!r} found {c}x, expected {n}x')
        data = data.replace(old, new)
    return data

def build(variant):
    out = f'{R}/out/43-{variant}'
    for name, eds in edits(variant).items():
        src = open(f'{R}/original/{name}', 'rb').read()
        if sha(src) != PRISTINE[name]: sys.exit(f'FAIL {name}: original/ is not pristine ({sha(src)})')
        dst = f'{out}/{DEVICE_PATH[name]}'
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        data = apply(src, eds, name)
        open(dst, 'wb').write(data)
        print(f'43-{variant}/{DEVICE_PATH[name]}  {sha(data)}')

if __name__ == '__main__':
    vs = sys.argv[1:] or ['427', '640', '568']
    for v in vs:
        if v not in SIZES: sys.exit(f'unknown variant {v}')
        build(v)
