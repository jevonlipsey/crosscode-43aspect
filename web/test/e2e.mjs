// end-to-end: drives the real UI (web/dist/index.html, not ?mock) in headless Chrome with original/node-webkit.html,
// then checks the downloaded file against the CLI's output, and the refusal views.
//   tools/build_web.sh && node web/test/e2e.mjs [--dist web/dist] [--shot out.png]
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { serve, launchChrome } from './cdp.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const dist = path.resolve(opt('--dist', path.join(root, 'web/dist')));
const shot = opt('--shot', path.join(process.env.TMPDIR || os.tmpdir(), 'cc43-e2e.png'));

const tmp = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'cc43-e2e-'));
const orig = path.join(root, 'original/node-webkit.html');
const cliOut = path.join(tmp, 'cli', 'node-webkit.html');
fs.mkdirSync(path.dirname(cliOut));
execFileSync('python3', ['-I', path.join(root, 'tools/patch43.py'), orig, '--out', cliOut], { stdio: 'ignore' });
const want = crypto.createHash('sha256').update(fs.readFileSync(cliOut)).digest('hex');
const file = (dir, buf) => { const p = path.join(tmp, dir, 'node-webkit.html'); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, buf); return p; };

const srv = await serve(dist);
const chrome = await launchChrome();
let failed = 0;
const ok = (c, m) => { console.log((c ? '  ok   ' : '  FAIL ') + m); if (!c) failed++; };
const pageErrors = [];
chrome.on('Runtime.exceptionThrown', (p) => pageErrors.push(p.exceptionDetails.exception?.description || p.exceptionDetails.text));
const waitView = () => chrome.evaluate(`new Promise((res) => { const t0 = Date.now(); (function w() {
  const v = ['view-ok', 'view-fail'].find((i) => !document.getElementById(i).hidden);
  if (v || Date.now() - t0 > 30000) return res(v || 'timeout'); setTimeout(w, 100); })(); })`);
const pick = async (p) => {
  const doc = await chrome.send('DOM.getDocument');
  const { nodeId } = await chrome.send('DOM.querySelector', { nodeId: doc.root.nodeId, selector: '#file' });
  await chrome.send('DOM.setFileInputFiles', { nodeId, files: [p] });
  return waitView();
};
const reset = () => chrome.evaluate(`(() => { const b = [...document.querySelectorAll('[data-action="reset"]')].find((x) => x.offsetParent !== null); b.click(); return 1; })()`);
const failText = () => chrome.evaluate(`document.getElementById('fail-title-text').textContent`);
try {
  await chrome.goto(srv.origin + '/index.html');
  await chrome.evaluate(`new Promise((res, rej) => { const t0 = Date.now(); (function w() {
    const e = document.getElementById('runtime'); if (e && e.classList.contains('ready')) return res(1);
    if (e && e.classList.contains('failed')) return rej(new Error('runtime failed: ' + document.getElementById('runtime-fail-text').textContent));
    if (Date.now() - t0 > 15000) return rej(new Error('runtime load timeout')); setTimeout(w, 100); })(); })`);
  const acc = await chrome.evaluate(`JSON.stringify([...document.querySelectorAll('input[type=file]')].map((i) => i.getAttribute('accept')))`);
  ok(acc === '[null]', 'the file input has no accept filter (Android/iOS would grey out the game file): ' + acc);

  let v = await pick(orig);
  ok(v === 'view-ok', 'the Steam node-webkit.html patches');
  const info = JSON.parse(await chrome.evaluate(`(async () => {
    const a = document.getElementById('download'); const r = await fetch(a.href); const b = new Uint8Array(await r.arrayBuffer());
    const hex = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', b)), (x) => x.toString(16).padStart(2, '0')).join('');
    return JSON.stringify({ visible: a.offsetParent !== null, href: a.href.slice(0, 5), name: a.getAttribute('download'),
      size: b.length, blobSha: hex, outHash: document.getElementById('ok-out-hash').textContent.trim(),
      inHash: document.getElementById('ok-in-hash').textContent.trim(), verified: document.getElementById('ok-verified').textContent.trim(),
      version: document.getElementById('version').textContent });
  })()`));
  console.log('  ' + JSON.stringify(info));
  ok(info.visible && info.href === 'blob:' && info.name === 'node-webkit.html', 'download button visible, blob: url, saves as node-webkit.html');
  ok(info.blobSha === info.outHash, 'blob sha256 equals the hash shown in the UI');
  ok(info.blobSha === want, 'download is byte-identical to the CLI output (' + want.slice(0, 12) + '...)');
  ok(/^v1\./.test(info.version), 'footer shows the patcher version');
  const png = await chrome.send('Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync(shot, Buffer.from(png.data, 'base64'));
  console.log('  screenshot ' + shot);

  await reset();
  v = await pick(cliOut);
  ok(v === 'view-fail' && /already patched/.test(await failText()), 'the patched file is refused as already patched');
  await reset();
  v = await pick(file('changed', fs.readFileSync(orig, 'latin1').replace('CrossCode Min', 'CrossCode Mod')));
  const t = await failText();
  const rep = await chrome.evaluate(`!document.getElementById('copy-report').hidden && !document.getElementById('fail-hashes').hidden`);
  ok(v === 'view-fail' && /isn't supported/.test(t) && rep, 'a changed CrossCode file is refused as an unsupported version, with its hash and a report button');
  await reset();
  v = await pick(file('other', '<!DOCTYPE html><title>Other</title>'));
  ok(v === 'view-fail' && /doesn't look like CrossCode/.test(await failText()), 'an unrelated file is refused as not CrossCode');
  ok(pageErrors.length === 0, 'no uncaught page exceptions' + (pageErrors.length ? ': ' + pageErrors.join('; ') : ''));
} catch (e) { console.log('  FAIL ' + e.message); failed++; }
finally { await chrome.close(); srv.close(); fs.rmSync(tmp, { recursive: true, force: true }); }
console.log(failed ? 'E2E FAILED' : 'E2E OK');
process.exit(failed ? 1 : 0);
