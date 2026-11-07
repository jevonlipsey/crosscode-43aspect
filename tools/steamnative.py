#!/usr/bin/env python3
"""Text edits for tools/steam-native.sh (run on the Mac, on files pulled off the device). Every edit is checked and
fails loudly instead of guessing.

  steamnative.py mapping   IN OUT APPID TOOL      set CompatToolMapping[APPID].name = TOOL (inside that block only)
  steamnative.py getmap    IN APPID               print CompatToolMapping[APPID].name ('' if absent)
  steamnative.py nosteam   IN OUT APPID on|off    DroidDeck game-environment.json: set / drop DROIDDECK_NO_STEAM
  steamnative.py html43    IN OUT [W H]           node-webkit.html: IG_WIDTH 568 -> W, IG_HEIGHT 320 -> H (default 480 360)
  steamnative.py package   IN OUT [shim]          package.json for the native arm64 runtime (from the depot's own one)
"""
import json, re, sys

TOKEN = re.compile(r'\s*(?:"((?:[^"\\]|\\.)*)"|([{}]))')

def die(msg): sys.exit('steamnative: ' + msg)

def vdf_block(text, path):
    """(start, end) character span of the inner text of the block at key path (list), scanning tokens."""
    pos, depth, stack, want = 0, 0, [], list(path)
    last_key, pending = None, None
    while True:
        m = TOKEN.match(text, pos)
        if not m or m.end() == pos:
            break
        pos = m.end()
        if m.group(2) == '{':
            stack.append(last_key)
            if stack[-len(want):] == want and len(stack) >= len(want):
                start, d = pos, 1
                while d:
                    n = TOKEN.match(text, pos)
                    if not n or n.end() == pos: die('unterminated block %s' % path)
                    pos = n.end()
                    d += {'{': 1, '}': -1}.get(n.group(2) or '', 0)
                return start, n.start(2)
            last_key = None
        elif m.group(2) == '}':
            stack.pop()
            last_key = None
        else:
            last_key = m.group(1) if last_key is None else None
    return None

def mapping_span(text):
    span = vdf_block(text, ['Software', 'Valve', 'Steam', 'CompatToolMapping'])
    if not span: die('no CompatToolMapping block')
    return span

def app_entry(inner, appid):
    found = list(re.finditer(r'"%s"\s*\{([^{}]*)\}' % re.escape(appid), inner))
    if len(found) > 1: die('CompatToolMapping has %d entries for %s' % (len(found), appid))
    return found[0] if found else None

def cmd_getmap(src, appid):
    text = open(src, encoding='utf-8', errors='surrogateescape').read()
    a, b = mapping_span(text)
    e = app_entry(text[a:b], appid)
    n = re.search(r'"name"\s*"([^"]*)"', e.group(1)) if e else None
    print(n.group(1) if n else '')

def cmd_mapping(src, dst, appid, tool):
    text = open(src, encoding='utf-8', errors='surrogateescape').read()
    a, b = mapping_span(text)
    inner = text[a:b]
    e = app_entry(inner, appid)
    if e:
        body = e.group(1)
        if len(re.findall(r'"name"\s*"[^"]*"', body)) != 1: die('entry %s has no single "name"' % appid)
        body2 = re.sub(r'("name"\s*")[^"]*(")', lambda m: m.group(1) + tool + m.group(2), body)
        inner2 = inner[:e.start(1)] + body2 + inner[e.end(1):]
    else:
        inner2 = ('\n\t\t\t\t\t"%s"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"%s"\n\t\t\t\t\t\t"config"\t\t""\n'
                  '\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}' % (appid, tool)) + inner
    out = text[:a] + inner2 + text[b:]
    # everything outside the one entry must be byte-identical
    if out.replace(inner2, '', 1) != text.replace(inner, '', 1): die('edit leaked outside CompatToolMapping')
    open(dst, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(out)

def cmd_nosteam(src, dst, appid, state):
    raw = open(src, encoding='utf-8').read()
    cfg = json.loads(raw)
    compact = '\n' not in raw.strip()
    games = cfg.setdefault('games', {})
    g = dict(games.get(appid, {}))
    if state == 'on': g['DROIDDECK_NO_STEAM'] = '1'
    elif state == 'off': g.pop('DROIDDECK_NO_STEAM', None)
    else: die('nosteam takes on|off')
    if g: games[appid] = g
    else: games.pop(appid, None)
    out = json.dumps(cfg, separators=(',', ':')) if compact else json.dumps(cfg, indent=2) + '\n'
    open(dst, 'w', encoding='utf-8').write(out)

def cmd_html43(src, dst, w='480', h='360'):
    b = open(src, 'rb').read()
    for old, new in ((b'var IG_WIDTH = 568;', b'var IG_WIDTH = %d;' % int(w)), (b'var IG_HEIGHT = 320;', b'var IG_HEIGHT = %d;' % int(h))):
        c = b.count(old)
        if c != 1: die('%s: %r found %dx, expected 1x (not a pristine node-webkit.html?)' % (src, old, c))
        b = b.replace(old, new)
    open(dst, 'wb').write(b)

# Proven on the device (native/crosscode-native.sh, 2026-11-06 01:27): no Chromium sandbox in proot, no /dev/shm,
# audio without a gesture, real GPU (blocklist off), no throttling while gamescope reports the window occluded.
FLAGS = ('--no-sandbox --disable-dev-shm-usage --autoplay-policy=no-user-gesture-required --ignore-gpu-blocklist '
         '--disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows '
         '--disable-background-networking --password-store=basic --ozone-platform=x11')

def cmd_package(src, dst, mode='elf'):
    pkg = json.loads(open(src, encoding='utf-8').read())
    if pkg.get('name') != 'CrossCode': die('package name is %r, not "CrossCode" (Steam Cloud path depends on it)' % pkg.get('name'))
    if pkg.get('main') != 'assets/node-webkit.html': die('unexpected main %r' % pkg.get('main'))
    win = dict(pkg.get('window') or {})
    win.update(width=1280, height=960, fullscreen=True, toolbar=False)
    out = {'name': 'CrossCode', 'version': pkg.get('version', '1.0.0'), 'main': pkg['main'],
           # shim mode passes the flags on argv itself; keep the manifest's own flags minimal there
           'chromium-args': FLAGS if mode == 'elf' else '--disable-background-networking --password-store=basic',
           'inject_js_start': 'cc-native-init.js', 'inject_js_end': 'cc-evpad.js', 'window': win}
    open(dst, 'w', encoding='utf-8').write(json.dumps(out, indent=1) + '\n')

if __name__ == '__main__':
    a = sys.argv[1:]
    cmds = {'mapping': (cmd_mapping, 4), 'getmap': (cmd_getmap, 2), 'nosteam': (cmd_nosteam, 4),
            'html43': (cmd_html43, 2), 'package': (cmd_package, 2)}
    if not a or a[0] not in cmds or len(a) - 1 < cmds[a[0]][1]: sys.exit(__doc__)
    cmds[a[0]][0](*a[1:])
