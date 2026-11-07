// screenshots of every page state through ?mock, at desktop and phone width, light and dark.
//   node web/test/shots.mjs [--app web/app] [--out verify/web] [--prefix cc43] [--only pick,ok]
// --app can point at a sibling repo's web/app (e.g. ../chefrpg-43aspect/web/app) for a side-by-side.
// Output goes to verify/web/ (gitignored: *.png).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { serve, launchChrome } from './cdp.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const app = path.resolve(opt('--app', path.join(root, 'web/app')));
const out = path.resolve(opt('--out', path.join(root, 'verify/web')));
const prefix = opt('--prefix', 'cc43');
const only = opt('--only', '').split(',').filter(Boolean);
fs.mkdirSync(out, { recursive: true });

const tmp = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'cc43-shots-'));
const dummy = (name) => { const p = path.join(tmp, name); fs.writeFileSync(p, Buffer.alloc(4096, 7)); return p; };

// state -> query, file to pick (null = none), view to wait for
const STATES = {
  'pick': { q: 'mock=ok', file: null, wait: 'pick' },
  'loading': { q: 'mock=ok&loadms=60000', file: null, wait: 'loading' },
  'loadfail': { q: 'mock=loadfail&loadms=200', file: null, wait: 'loadfail' },
  'busy': { q: 'mock=ok&patchms=60000', file: 'node-webkit.html', wait: 'busy' },
  'ok': { q: 'mock=ok&patchms=200', file: 'node-webkit.html', wait: 'ok' },
  'already': { q: 'mock=already_patched&patchms=200', file: 'node-webkit.html', wait: 'fail' },
  'notcc': { q: 'mock=not_crosscode&patchms=200', file: 'other.html', wait: 'fail' },
  'unknown': { q: 'mock=unknown_version&patchms=200', file: 'node-webkit.html', wait: 'fail' },
  'verify': { q: 'mock=verify_failed&patchms=200', file: 'node-webkit.html', wait: 'fail' },
  'error': { q: 'mock=error&patchms=200', file: 'node-webkit.html', wait: 'fail' },
};
const SIZES = { desktop: { width: 1280, height: 900, dpr: 1, mobile: false }, phone: { width: 390, height: 844, dpr: 2, mobile: true } };
const THEMES = ['light', 'dark'];

const waitJs = (w) => `new Promise((res) => { const t0 = Date.now(); (function f() {
  const v = (id) => { const e = document.getElementById(id); return e && !e.hidden; };
  const rt = document.getElementById('runtime');
  const st = { pick: rt && rt.classList.contains('ready') && v('view-pick'), loading: v('runtime') && !rt.classList.contains('ready'),
    loadfail: rt && rt.classList.contains('failed'), busy: v('view-busy'), ok: v('view-ok'), fail: v('view-fail') };
  if (st['${w}'] || Date.now() - t0 > 20000) return res(!!st['${w}']); setTimeout(f, 100); })(); })`;

const srv = await serve(app);
const chrome = await launchChrome();
const written = [];
let failed = 0;
try {
  for (const [state, s] of Object.entries(STATES)) {
    if (only.length && !only.includes(state)) continue;
    for (const [sizeName, sz] of Object.entries(SIZES)) {
      for (const theme of THEMES) {
        await chrome.send('Emulation.setDeviceMetricsOverride', { width: sz.width, height: sz.height, deviceScaleFactor: sz.dpr, mobile: sz.mobile });
        await chrome.send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: theme }] });
        await chrome.goto(srv.origin + '/index.html?' + s.q);
        if (s.file) {
          await chrome.evaluate(waitJs('pick'));
          const doc = await chrome.send('DOM.getDocument');
          const { nodeId } = await chrome.send('DOM.querySelector', { nodeId: doc.root.nodeId, selector: '#file' });
          await chrome.send('DOM.setFileInputFiles', { nodeId, files: [dummy(s.file)] });
        }
        const reached = await chrome.evaluate(waitJs(s.wait));
        if (!reached) { console.log('  FAIL ' + state + ' ' + sizeName + ' ' + theme + ': view ' + s.wait + ' not reached'); failed++; }
        await new Promise((r) => setTimeout(r, s.wait === 'busy' || s.wait === 'loading' ? 1200 : 300));
        const m = await chrome.send('Page.getLayoutMetrics');
        const h = Math.ceil(m.cssContentSize.height);
        const png = await chrome.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true,
          clip: { x: 0, y: 0, width: sz.width, height: Math.max(h, sz.height), scale: 1 } });
        const file = path.join(out, `${prefix}-${state}-${sizeName}-${theme}.png`);
        fs.writeFileSync(file, Buffer.from(png.data, 'base64'));
        const scrollX = await chrome.evaluate('document.documentElement.scrollWidth > window.innerWidth');
        if (scrollX) { console.log('  FAIL ' + file + ': horizontal overflow'); failed++; }
        written.push(file);
      }
    }
  }
} finally { await chrome.close(); srv.close(); fs.rmSync(tmp, { recursive: true, force: true }); }
written.forEach((f) => console.log(f));
console.log(failed ? 'SHOTS FAILED (' + failed + ')' : 'SHOTS OK (' + written.length + ')');
process.exit(failed ? 1 : 0);
