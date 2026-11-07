/* DEV ONLY - fake CC43 runtime that implements the real contract with delays.
 * Loaded by main.js only when the URL has ?mock. Always overrides any existing CC43.
 *
 * Choose the outcome with a query param:   ?mock=ok | already_patched | not_crosscode | unknown_version | verify_failed | error | loadfail
 * Otherwise (plain ?mock) it is picked from the chosen file name (case-insensitive):
 *   "patched" -> already_patched, "other" -> not_crosscode, "old" -> unknown_version, "bad" or "fail" -> verify_failed,
 *   "error" -> error, anything else -> ok.
 * Extra knobs:  ?loadms=3000 (runtime load time)  ?patchms=4000 (patch time)  ?version=v1.0-mock
 */
(function () {
  'use strict';
  var q = new URLSearchParams(location.search);
  var forced = q.get('mock');
  var LOAD_MS = +(q.get('loadms') || 1500);
  var PATCH_MS = +(q.get('patchms') || 1500);
  var VERSION = q.get('version') || 'v1.0-mock';
  var loadP = null;

  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  function hex(buf) {
    return Array.prototype.map.call(new Uint8Array(buf), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }
  function sha256(bytes) {
    if (globalThis.crypto && crypto.subtle) return crypto.subtle.digest('SHA-256', bytes).then(hex);
    var s = ''; for (var i = 0; i < 64; i++) s += ((bytes[i % bytes.length] || 0) + i * 7 & 15).toString(16);
    return Promise.resolve(s);
  }

  function pick(name) {
    if (forced === 'ok') return 'ok';
    if (forced) return forced;
    var n = (name || '').toLowerCase();
    if (n.indexOf('patched') >= 0) return 'already_patched';
    if (n.indexOf('other') >= 0) return 'not_crosscode';
    if (n.indexOf('old') >= 0) return 'unknown_version';
    if (n.indexOf('bad') >= 0 || n.indexOf('fail') >= 0) return 'verify_failed';
    if (n.indexOf('error') >= 0) return 'error';
    return 'ok';
  }

  var CC43 = {
    version: undefined,   // the real runtime sets it on load; the mock leaves it to patch()

    load: function (onProgress) {
      if (loadP) return loadP;
      loadP = (async function () {
        if (onProgress) onProgress({ label: 'Starting' });
        await sleep(LOAD_MS / 2);
        if (forced === 'loadfail') {
          await sleep(300);
          throw new Error('mock: cc43-core.js or cc43-data.js did not load (simulated)');
        }
        await sleep(LOAD_MS / 2);
      })();
      return loadP;
    },

    patch: async function (bytes) {
      if (!(bytes instanceof Uint8Array)) throw new TypeError('mock: patch() expects a Uint8Array');
      var name = '';
      // main.js hands us only bytes, so fall back to the picked file name in the <input>.
      try { var inp = document.getElementById('file'); if (inp && inp.files && inp.files[0]) name = inp.files[0].name; } catch (e) { /* ignore */ }
      var reason = pick(name);
      await sleep(PATCH_MS);
      var inSha = await sha256(bytes);
      var base = { ok: false, reason: reason, output: null, log: '', passed: 0, failed: 0, skipped: 0, failures: [],
        inputSha256: inSha, outputSha256: null, version: VERSION, fileName: 'node-webkit.html' };
      var log = ['[mock] CrossCode 4:3 patcher ' + VERSION, '[mock] input ' + bytes.length + ' bytes, sha256 ' + inSha];

      if (reason === 'ok') {
        var out = new Uint8Array(bytes.length + 8);
        out.set(bytes); out.set([0x43, 0x34, 0x33, 0x2d, 0x6d, 0x6f, 0x63, 0x6b], bytes.length);
        base.ok = true; base.output = out; base.outputSha256 = await sha256(out); base.passed = 5;
        log.push('[mock] ok   input is the Steam node-webkit.html', '[mock] ok   2 edits applied', '[mock] ok   output is the expected file',
          '[mock] ok   output reverts to the exact input', '[mock] ok   view is 480x360');
      } else if (reason === 'already_patched') {
        log.push('[mock] this is the patched file');
      } else if (reason === 'not_crosscode') {
        log.push('[mock] not CrossCode\'s node-webkit.html');
      } else if (reason === 'unknown_version') {
        base.failed = 1; base.failures = ['input is the Steam node-webkit.html (sha256 16c7b73f4f92822cc712bfd4db311be0ab60ddc917188eadf5ea2845d1efb6cc)'];
        log.push('[mock] FAIL ' + base.failures[0]);
      } else if (reason === 'verify_failed') {
        base.passed = 2; base.failed = 1;
        base.failures = ['output is the expected file (sha256 6031c9883f3755a67f6bee8ae264ee9d0915ad5a7dffd4a93de808da550232dd)'];
        log.push('[mock] verify: 2 passed, 1 failed');
        base.failures.forEach(function (x) { log.push('FAIL ' + x); });
      } else {
        base.reason = 'error';
        log.push('[mock] TypeError: Cannot read properties of undefined (reading \'edits\')');
      }
      base.log = log.join('\n');
      return base;
    }
  };

  globalThis.CC43 = CC43;
})();
