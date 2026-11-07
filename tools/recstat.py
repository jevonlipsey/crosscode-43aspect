#!/usr/bin/env python3
"""On-screen frame pacing, measured outside the game.

  recstat.py <screenrecord.mp4> [--frames DIR]   content cadence from an `adb shell screenrecord` capture
  recstat.py --sf <sf-latency.txt>               output cadence from repeated `dumpsys SurfaceFlinger --latency <layer>`

Screenrecord: the capture is variable-frame-rate (one encoded frame per composition, up to the panel's 120 Hz). Each
frame is compared with the previous one over the playfield (the top 12% is skipped: the DroidDeck HUD overlay redraws
there on its own). A frame that differs is a new game image; the time between new images is what the eye sees. With the
camera scrolling, a steady 60 fps game gives new images every 16.7 ms; judder shows up as 8.3/25/33 ms gaps.
--frames DIR also writes every 3rd new image as PNG for looking at.

SurfaceFlinger: actual present times of the DroidDeck layer (the gamescope output) on the panel. At 120 Hz every
interval should be 8.33 ms; longer ones are vblanks where nothing new reached the screen.
"""
import json, subprocess, sys, statistics as st

VB = 1000 / 120


def summary(x, label):
    if len(x) < 5:
        return {'label': label, 'n': len(x)}
    s = sorted(x)
    n = len(x)
    vb = [max(1, round(v / VB)) for v in x]
    med = s[n // 2]
    return {'label': label, 'n': n, 'mean_ms': round(st.mean(x), 2), 'fps': round(1000 / st.mean(x), 1),
            'sd_ms': round(st.pstdev(x), 2), 'p50': round(med, 2), 'p99': round(s[min(n - 1, int(n * .99))], 2),
            'low1_fps': round(1000 / st.mean(s[-max(1, n // 100):]), 1),
            'judder_pct': round(100 * sum(abs(x[i] - x[i - 1]) > 4 for i in range(1, n)) / (n - 1), 1),
            'off_median_pct': round(100 * sum(abs(v - med) > 4 for v in x) / n, 1),
            'vblanks_1_2_3_4plus_pct': [round(100 * vb.count(k) / n) for k in (1, 2, 3)] + [round(100 * sum(v >= 4 for v in vb) / n)]}


def rec(path, frames_dir=None):
    import numpy as np
    pr = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                                             'stream=width,height:frame=pts_time', '-of', 'json', path]))
    pts = [float(f['pts_time']) for f in pr['frames'] if 'pts_time' in f]
    W, H = 320, 240
    raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', path, '-fps_mode', 'passthrough', '-vf',
                                   'scale=%d:%d,format=gray' % (W, H), '-f', 'rawvideo', '-'])
    a = np.frombuffer(raw, np.uint8).reshape(-1, H, W)[:, int(H * .12):, :].astype(np.int16)
    n = min(len(a), len(pts))
    d = [float(np.abs(a[i] - a[i - 1]).mean()) for i in range(1, n)]
    nz = sorted(v for v in d if v > 0.01)
    thr = max(0.03, 0.08 * nz[len(nz) // 2]) if nz else 0.03
    new = [i for i in range(1, n) if d[i - 1] > thr]
    t = [pts[i] * 1000 for i in new]
    content = [b - a_ for a_, b in zip(t, t[1:])]
    cap = [1000 * (b - a_) for a_, b in zip(pts, pts[1:n])]
    out = {'file': path, 'capture': summary(cap, 'screenrecord frames'), 'content': summary(content, 'new game images'),
           'diff_threshold': round(thr, 3), 'duration_s': round(pts[n - 1] - pts[0], 2) if n > 1 else 0}
    if frames_dir:
        import os
        os.makedirs(frames_dir, exist_ok=True)
        sel = ','.join('eq(n\\,%d)' % i for i in new[::3][:60])
        if sel:
            subprocess.call(['ffmpeg', '-v', 'error', '-y', '-i', path, '-fps_mode', 'passthrough', '-vf',
                             "select='%s'" % sel, os.path.join(frames_dir, 'f%03d.png')])
    return out


def sf(path):
    pres, period = set(), None
    for line in open(path, errors='replace'):
        p = line.split()
        if len(p) == 1 and p[0].isdigit() and period is None:
            period = int(p[0]) / 1e6
        elif len(p) == 3 and all(q.isdigit() for q in p):
            v = int(p[1])
            if 0 < v < 2 ** 62:
                pres.add(v)
    t = sorted(pres)
    x = [(b - a) / 1e6 for a, b in zip(t, t[1:]) if (b - a) / 1e6 < 200]  # gaps between polling windows are dropped
    return {'file': path, 'refresh_ms': period, 'present': summary(x, 'layer presents')}


if __name__ == '__main__':
    a = sys.argv[1:]
    if a[:1] == ['--sf']:
        print(json.dumps(sf(a[1]), indent=1))
    else:
        fd = a[a.index('--frames') + 1] if '--frames' in a else None
        print(json.dumps(rec(a[0], fd), indent=1))
