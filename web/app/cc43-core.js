/* CrossCode 4:3 patch - browser core (same logic as tools/patch43.py, data from cc43-data.js). Classic script;
 * defines globalThis.CC43Core:
 *   CC43Core.patch(Uint8Array, data, sha256) -> Promise<{reason, output, inputSha256, outputSha256, passed, failed,
 *                                                       failures, log}>
 *   reason: ok | already_patched | not_crosscode | unknown_version | verify_failed
 *   sha256(Uint8Array) -> Promise<hex string>   (crypto.subtle in the browser, node:crypto in the tests)
 * The edits are exact, count-checked replacements on the file's bytes (one char per byte), so nothing else changes.
 */
(function () {
  'use strict';

  function toStr(bytes) {
    var s = '', CH = 8192;
    for (var i = 0; i < bytes.length; i += CH) s += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
    return s;
  }
  function toBytes(s) {
    var b = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) b[i] = s.charCodeAt(i);
    return b;
  }
  function count(s, sub) {
    var n = 0, i = 0;
    while ((i = s.indexOf(sub, i)) >= 0) { n++; i += sub.length; }
    return n;
  }
  function replaceAll(s, a, b) { return s.split(a).join(b); }

  // returns the edited string, or pushes failures and returns null
  function apply(s, edits, reverse, failures, note) {
    for (var i = 0; i < edits.length; i++) {
      var old = edits[i][0], neu = edits[i][1], n = edits[i][2];
      if (reverse) { var t = old; old = neu; neu = t; }
      var c = count(s, old), c2 = count(s, neu);
      if (c !== n || c2 !== 0) {
        failures.push(note + ': expected ' + n + ' x "' + old + '" and none of "' + neu + '", found ' + c + ' and ' + c2);
        return null;
      }
      s = replaceAll(s, old, neu);
    }
    return s;
  }

  async function patch(bytes, data, sha256) {
    var log = [], failures = [], passed = 0;
    var r = { reason: 'verify_failed', output: null, inputSha256: '', outputSha256: null, passed: 0, failed: 0, failures: failures, log: log };
    function check(ok, what) { if (ok) { passed++; log.push('ok   ' + what); } else { failures.push(what); log.push('FAIL ' + what); } return ok; }
    function done(reason) { r.reason = reason; r.passed = passed; r.failed = failures.length; return r; }

    r.inputSha256 = await sha256(bytes);
    log.push('input ' + bytes.length + ' bytes, sha256 ' + r.inputSha256);
    var s = toStr(bytes);
    if (r.inputSha256 === data.patched) { log.push('this is the patched file (sha256 ' + data.patched + ')'); return done('already_patched'); }
    if (s.indexOf('<title>CrossCode') < 0 || s.indexOf('var IG_WIDTH = ') < 0) {
      log.push('no "<title>CrossCode" / "var IG_WIDTH = " in it: not CrossCode\'s node-webkit.html');
      return done('not_crosscode');
    }
    if (!check(r.inputSha256 === data.pristine, 'input is the Steam node-webkit.html (sha256 ' + data.pristine + ')')) {
      return done('unknown_version');
    }
    var edits = data.edits, back = edits.slice().reverse();
    var out = apply(s, edits, false, failures, 'patch');
    if (!check(out !== null, edits.length + ' edits applied, each exactly as often as expected')) return done('verify_failed');
    var ob = toBytes(out);
    r.outputSha256 = await sha256(ob);
    if (!check(r.outputSha256 === data.patched, 'output is the expected file (sha256 ' + data.patched + ')')) return done('verify_failed');
    if (!check(apply(out, back, true, failures, 'round trip') === s, 'output reverts to the exact input')) return done('verify_failed');
    var m = /var IG_WIDTH = (\d+);[\s\S]*?var IG_HEIGHT = (\d+);/.exec(out);
    if (!check(m && +m[1] === data.width && +m[2] === data.height, 'view is ' + data.width + 'x' + data.height)) return done('verify_failed');
    r.output = ob;
    log.push('output ' + ob.length + ' bytes, sha256 ' + r.outputSha256);
    return done('ok');
  }

  globalThis.CC43Core = { patch: patch };
})();
