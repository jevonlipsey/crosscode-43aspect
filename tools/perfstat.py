#!/usr/bin/env python3
"""Summarise cc-perf.json files (tools/cc-perf.js) for frame-time CONSISTENCY, not just average fps.

usage: perfstat.py [--table] <json>...

Frame times are the intervals between GAME frames (each ig.system.delegate.run = one new image on screen); probe v1
files only have rAF deltas, which are the same thing without the cc-pace gate. The Nova's panel and gamescope run at
120 Hz, so every frame time is a whole number of 8.33 ms vblanks; what the eye reads as jitter is that number changing
from frame to frame.
  fps        frames per second (1000 / mean frame time)
  sd         standard deviation of the frame time, ms
  1% / 0.1%  "lows": fps over the slowest 1% / 0.1% of frames (1000 / mean of those frame times)
  judder     % of frames whose time differs from the previous frame's by more than 4 ms (a cadence change)
  on60       % of frames within 4 ms of 16.67 ms (one image every second vblank: the steady 60 fps cadence)
  1v..4v+    share of frames lasting 1, 2, 3, 4+ vblanks
  >50        frames slower than 50 ms (hitches)
  walk       game frames in which the camera moved (proves the injected stick reached the game), and the judder
             measured over those frames only
"""
import json, sys, statistics as st

VB = 1000 / 120


def consistency(x):
    s = sorted(x)
    n = len(x)
    m = st.mean(x)
    worst = lambda f: s[-max(1, int(n * f)):]
    ch = sum(abs(x[i] - x[i - 1]) > 4 for i in range(1, n))
    vb = [max(1, round(v / VB)) for v in x]
    return dict(n=n, mean=m, fps=1000 / m, sd=st.pstdev(x), p50=s[n // 2], p99=s[min(n - 1, int(n * .99))],
                low1=1000 / st.mean(worst(.01)), low01=1000 / st.mean(worst(.001)),
                judder=100 * ch / max(1, n - 1), on60=100 * sum(abs(v - 1000 / 60) <= 4 for v in x) / n,
                v1=100 * vb.count(1) / n, v2=100 * vb.count(2) / n, v3=100 * vb.count(3) / n,
                v4=100 * sum(v >= 4 for v in vb) / n, hitch=sum(v > 50 for v in x))


def row(path):
    try:
        d = json.load(open(path))
    except Exception as e:
        return None, {'timeout': 'unreadable: %s' % e}
    f = d.get('frames') or {}
    t = f.get('t') or []
    if len(t) > 1:
        x = [b - a for a, b in zip(t, t[1:])]
    else:
        x = d.get('deltas') or []
    if len(x) < 10:
        return None, d
    r = consistency(x)
    r['src'] = 'game' if len(t) > 1 else 'rAF'
    mean = lambda k: st.mean(d[k]) if d.get(k) else float('nan')
    r.update(upd=mean('upd'), drw=mean('drw'), run=mean('work'))
    cx, cy = f.get('cx') or [], f.get('cy') or []
    mv = [i for i in range(1, min(len(cx), len(t))) if abs(cx[i] - cx[i - 1]) + abs(cy[i] - cy[i - 1]) > 0.05]
    r['walk'] = len(mv)
    wx = [t[i] - t[i - 1] for i in mv]
    r['wjudder'] = consistency(wx)['judder'] if len(wx) > 10 else float('nan')
    a, b = d.get('at_start') or {}, d.get('at_end') or {}
    r['valid'] = len(x) >= 500 and isinstance(a, dict) and bool(a.get('map')) and a.get('map') == (b or {}).get('map')
    return r, d


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    table = '--table' in argv
    if table:
        print('| run | src | frames | fps | sd ms | 1% low | 0.1% low | judder | on60 | 1v/2v/3v/4v+ % | >50 ms | walk (judder) | run ms | valid |')
        print('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')
    for p in args:
        r, d = row(p)
        name = p.rsplit('/', 1)[-1].replace('.json', '')
        if r is None:
            print(('| %s | NO FRAMES %s %s %s |' if table else '%s NO FRAMES %s %s %s') % (
                name, d.get('timeout'), d.get('tickErr'), d.get('marks')))
            continue
        if table:
            print('| %s | %s | %d | %.1f | %.1f | %.1f | %.1f | %.1f%% | %.1f%% | %.0f/%.0f/%.0f/%.0f | %d | %d (%.1f%%) | %.1f | %s |' % (
                name, r['src'], r['n'], r['fps'], r['sd'], r['low1'], r['low01'], r['judder'], r['on60'],
                r['v1'], r['v2'], r['v3'], r['v4'], r['hitch'], r['walk'], r['wjudder'], r['run'], 'yes' if r['valid'] else 'NO'))
        else:
            print(p)
            for k in ('glRenderer', 'arch', 'platform', 'cwd', 'startPath', 'dataPath', 'pads', 'pad', 'evpad', 'pace',
                      'canvas', 'sys', 'at_start', 'at_end', 'marks', 'timeout', 'tickErr'):
                if k in d:
                    print('  %-10s %s' % (k, d[k]))
            print('  versions   nw %s chrome %s node %s' % tuple((d.get('versions') or {}).get(k) for k in ('nw', 'chromium', 'node')))
            print('  %(n)d %(src)s frames  %(fps).1f fps  sd %(sd).1f ms  p50 %(p50).1f  p99 %(p99).1f  1%%low %(low1).1f  '
                  '0.1%%low %(low01).1f  judder %(judder).1f%%  on60 %(on60).1f%%  vblanks 1/2/3/4+ %(v1).0f/%(v2).0f/%(v3).0f/%(v4).0f%%  '
                  '>50ms %(hitch)d  walk %(walk)d (judder %(wjudder).1f%%)  | run %(run).1f update %(upd).1f draw %(drw).1f  valid %(valid)s' % r)


if __name__ == '__main__':
    main(sys.argv[1:])
