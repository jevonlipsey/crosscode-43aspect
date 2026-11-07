// Browser core vs the CLI: web/app/cc43-core.js with the generated data must give the same bytes and the same verdict
// as tools/patch43.py for every input (pristine, patched, a changed CrossCode file, an unrelated file).
//   node web/test/parity.mjs        (needs original/node-webkit.html, the pristine Steam file, and python3)
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import vm from 'node:vm';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cc43-parity-'));
const dataJs = path.join(tmp, 'cc43-data.js');
execFileSync('python3', ['-I', path.join(root, 'tools/gen_web_data.py'), dataJs], { stdio: 'ignore' });
vm.runInThisContext(fs.readFileSync(dataJs, 'utf8'));
vm.runInThisContext(fs.readFileSync(path.join(root, 'web/app/cc43-core.js'), 'utf8'));
const { CC43Data: data, CC43Core: core } = globalThis;
const sha = async (b) => crypto.createHash('sha256').update(b).digest('hex');

const orig = fs.readFileSync(path.join(root, 'original/node-webkit.html'));
const cli = (input) => {  // -> {rc, out: Buffer|null}
  const i = path.join(tmp, 'in.html'), o = path.join(tmp, 'out.html');
  fs.writeFileSync(i, input); fs.rmSync(o, { force: true });
  const p = spawnSync('python3', ['-I', path.join(root, 'tools/patch43.py'), i, '--out', o]);
  return { rc: p.status, out: fs.existsSync(o) ? fs.readFileSync(o) : null };
};
const patchedCli = cli(orig).out;
const cases = {
  pristine: orig,
  patched: patchedCli,
  changed: Buffer.from(orig.toString('latin1').replace('CrossCode Min', 'CrossCode Mod'), 'latin1'),
  lf: Buffer.from(orig.toString('latin1').replace(/\r\n/g, '\n'), 'latin1'),
  other: Buffer.from('<!DOCTYPE html><html><head><title>Something else</title></head></html>'),
};
const want = { pristine: 'ok', patched: 'already_patched', changed: 'unknown_version', lf: 'unknown_version', other: 'not_crosscode' };

let bad = 0;
const ok = (c, m) => { console.log((c ? '  ok   ' : '  FAIL ') + m); if (!c) bad++; };
ok(data.pristine === await sha(orig), 'generated data: pristine hash == original/node-webkit.html');
for (const [name, input] of Object.entries(cases)) {
  const c = cli(input);
  const r = await core.patch(new Uint8Array(input), data, sha);
  const webOut = r.output ? Buffer.from(r.output) : null;
  const same = c.out && webOut ? c.out.equals(webOut) : c.out === null && webOut === null;
  ok(r.reason === want[name] && (c.rc === 0) === (r.reason === 'ok') && same,
    `${name}: web ${r.reason} (${r.passed} passed, ${r.failed} failed), cli exit ${c.rc}` +
    (webOut ? `, both ${await sha(webOut)}` : ', no output from either'));
}
ok(patchedCli && (await sha(patchedCli)) === data.patched && data.patched.startsWith('6031c988'), 'CLI output is the user-verified 43-480 build 6031c988');
fs.rmSync(tmp, { recursive: true, force: true });
console.log(bad ? `PARITY FAILED (${bad})` : 'PARITY OK');
process.exit(bad ? 1 : 0);
