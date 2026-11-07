// Research harness for frame-pacing candidates (NOT part of the shipped patch). Simulates CrossCode's rAF game loop on
// displays of different refresh rates, stock and with a pacing script loaded.
//   node tools/test-pace.mjs [pacing.js] [--expect-fix]     (default tools/cc-pace.js)
// Model: a vblank every 1000/hz ms; queued rAF callbacks run at the first vblank after the main thread is free, all with
// that vblank's timestamp. The game's own loop (impact `a()`) costs `cost` ms, then asks for the next frame with
// requestAnimationFrame(ig.system.run.bind(ig.system)), exactly as game.compiled.js does. A game frame is on screen
// from the vblank after it FINISHES until the next game frame replaces it.
// Always asserted (safety): 60/75/90/100 Hz and a slower-than-60 game run exactly as stock; no-timestamp calls pass.
// Reported, and asserted only with --expect-fix: at 120/144/240 Hz every frame is held the same number of vblanks.
// Result 2026-11-07 for tools/cc-pace.js (a start-time gate): safe, but it does NOT fix the judder (holds 1/2/3/4).
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const expectFix = args.includes('--expect-fix');
const PACE = fs.readFileSync(args.find((a) => !a.startsWith('--')) || path.join(root, 'tools/cc-pace.js'), 'utf8');

function rng(seed) { let s = seed >>> 0; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); }

// schedule: [[hz, frames], ...] (display mode changes are allowed); cost(rand) -> ms per game frame
function sim({ schedule, cost, gate, seed = 1 }) {
  const rand = rng(seed);
  let now = 0, queue = [], timers = [];
  const runs = [], presents = [];
  const win = {
    requestAnimationFrame(f) { queue.push(f); return queue.length; },
    setTimeout(f, ms) { timers.push([now + (ms || 0), f]); return timers.length; },
  };
  win.window = win;
  const system = { run() { loop(); } };
  function loop() {  // impact's a(): one game step, then the next rAF
    const c = cost(rand); runs.push(now); presents.push(now + c); now += c;
    win.requestAnimationFrame(win.ig.system.run.bind(win.ig.system));
  }
  win.ig = { system };
  if (gate) { vm.createContext(win); vm.runInContext(PACE, win); }
  win.requestAnimationFrame(system.run.bind(system));  // startRunLoop
  let t = 0;
  const marks = [];
  for (const [hz, frames] of schedule) {
    const P = 1000 / hz;
    marks.push({ hz, from: runs.length });
    for (let k = 0; k < frames; k++, t += P) {
      for (const tm of timers.splice(0)) tm[1]();  // the hook's setTimeout retry, if any
      if (now > t + 1e-9) continue;               // main thread still busy: this vblank is missed
      now = t;
      const q = queue; queue = [];
      for (const f of q) { now += 0.05; f.call(null, t); }
    }
  }
  return { runs, presents, marks, stats: win.__cc43pace };
}

// vblank index each game frame first shows at, then how many vblanks each one stays up
function holds(res, hz, from = 0) {
  const P = 1000 / hz;
  const shown = res.presents.slice(from).map((p) => Math.floor(p / P + 1e-9) + 1);
  const h = [];
  for (let i = 1; i < shown.length; i++) h.push(shown[i] - shown[i - 1]);
  return h.slice(5);  // skip warm-up
}
const hist = (h) => { const o = {}; h.forEach((x) => { o[x] = (o[x] || 0) + 1; }); return o; };
const pct = (h, f) => Math.round(100 * h.filter(f).length / h.length);
const judder = (h) => pct(h.slice(1).map((x, i) => x !== h[i]), (x) => x);

let failed = 0;
const ok = (c, m) => { console.log((c ? '  ok   ' : '  FAIL ') + m); if (!c) failed++; };
const same = (a, b) => a.runs.length === b.runs.length && a.runs.every((x, i) => Math.abs(x - b.runs[i]) < 1e-6);

// Proton-like cost: 4..11 ms per game frame, 5% spikes of +10 ms (Nova measurement: 61/31/5/4 % on 1/2/3/4+ vblanks)
const proton = (r) => 4 + 7 * r() + (r() < 0.05 ? 10 : 0);
const slow = (r) => 18 + 4 * r();

for (const hz of [60, 75, 90, 100]) {
  const a = sim({ schedule: [[hz, 3000]], cost: proton, gate: false });
  const b = sim({ schedule: [[hz, 3000]], cost: proton, gate: true });
  ok(same(a, b) && b.stats.skipped === 0 && !b.stats.active, `${hz} Hz: gated loop is identical to stock (${b.stats.ran} frames, 0 skipped)`);
}
for (const [hz, want] of [[120, 2], [144, 2], [240, 4]]) {
  const a = sim({ schedule: [[hz, 6000]], cost: proton, gate: false });
  const b = sim({ schedule: [[hz, 6000]], cost: proton, gate: true });
  const ha = holds(a, hz), hb = holds(b, hz);
  console.log(`  ${hz} Hz stock: holds ${JSON.stringify(hist(ha))}, judder ${judder(ha)}%;  gated: holds ${JSON.stringify(hist(hb))}, judder ${judder(hb)}%, ${(1000 * want / hz).toFixed(1)} ms cadence ${pct(hb, (x) => x === want)}%`);
  ok(b.stats.active && b.stats.skipped > 0, `${hz} Hz: gate active`);
  if (expectFix) {
    ok(pct(hb, (x) => x === want) >= 90 && judder(hb) < judder(ha) / 3, `${hz} Hz: gated frames hold ${want} vblanks (${(hz / want).toFixed(0)} fps) with far less judder than stock`);
    ok(Math.min(...hb) >= want, `${hz} Hz: no gated frame shorter than ${want} vblanks`);
  }
}
{
  const a = sim({ schedule: [[120, 3000]], cost: slow, gate: false });
  const b = sim({ schedule: [[120, 3000]], cost: slow, gate: true });
  ok(same(a, b) && b.stats.skipped === 0, '120 Hz, game slower than 60 fps (18-22 ms): the gate never skips, identical to stock');
}
{
  const b = sim({ schedule: [[120, 2000], [90, 2000]], cost: proton, gate: true });
  const a = sim({ schedule: [[120, 2000], [90, 2000]], cost: proton, gate: false });
  const m = b.marks[1].from;
  const after = b.runs.slice(m + 200);
  const gaps = after.slice(1).map((x, i) => x - after[i]);
  ok(!b.stats.active && gaps.every((g) => g > 11.1 - 1e-6 && Math.abs(g / 11.111 - Math.round(g / 11.111)) < 1e-3),
    '120 -> 90 Hz switch: the gate turns itself off (after ' + 120 + ' ticks) and the loop runs on every 90 Hz vblank it can');
  void a;
}
{  // the hook waits for ig.system: start without it, add it later
  const win = { setTimeout(f) { win._t = f; }, requestAnimationFrame() {} }; win.window = win;
  vm.createContext(win); vm.runInContext(PACE, win);
  ok(win.__cc43pace && win.__cc43pace.ran === 0 && typeof win._t === 'function', 'hook retries until ig.system exists');
  const sys = { run() { sys.n = (sys.n || 0) + 1; } }; win.ig = { system: sys }; win._t();
  sys.run(); sys.run();  // no timestamp (setInterval mode below 60 fps): always passes
  ok(sys.__cc43pace === true && win.__cc43pace.ran === 2 && sys.n === 2, 'calls without a timestamp pass straight through');
}
console.log(failed ? `PACE TEST FAILED (${failed})` : 'PACE TEST OK (safety' + (expectFix ? ' + fix' : ' only; judder fix not asserted') + ')');
process.exit(failed ? 1 : 0);
