/* CrossCode 4:3 patcher - browser runtime. Classic script; defines globalThis.CC43:
 *   CC43.load(onProgress) -> Promise<void>      idempotent; onProgress({loaded,total,label})
 *   CC43.patch(Uint8Array) -> Promise<{ok, reason, output, log, passed, failed, skipped,
 *                                      failures, inputSha256, outputSha256, version, fileName}>
 * Pure JavaScript: cc43-core.js does the work, cc43-data.js (generated from tools/patch43.py) carries the edits and
 * the known hashes, and SHA-256 comes from crypto.subtle. The file is about 2 KB, so it runs on the main thread and
 * load() has nothing to download.
 */
(function () {
  'use strict';

  var loadP = null;

  function hex(buf) {
    return Array.prototype.map.call(new Uint8Array(buf), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }
  function sha256(bytes) { return crypto.subtle.digest('SHA-256', bytes).then(hex); }

  function ready() {
    if (!globalThis.CC43Core || !globalThis.CC43Data) throw new Error('cc43-core.js or cc43-data.js did not load.');
    if (!(globalThis.crypto && crypto.subtle)) throw new Error('crypto.subtle is unavailable (needs a secure https page).');
  }

  var CC43 = {
    mode: 'js',
    version: undefined,

    load: function (onProgress) {
      if (loadP) return loadP;
      loadP = Promise.resolve().then(function () {
        ready();
        CC43.version = 'v' + CC43Data.version;
        if (onProgress) onProgress({ label: 'Ready' });
      });
      return loadP;
    },

    patch: async function (bytes) {
      if (!(bytes instanceof Uint8Array)) throw new TypeError('patch() expects a Uint8Array');
      ready();
      var version = 'v' + CC43Data.version;
      var r = await CC43Core.patch(bytes, CC43Data, sha256);
      var log = ['CrossCode 4:3 patcher ' + version + ' (' + CC43Data.width + 'x' + CC43Data.height + ')'].concat(r.log);
      log.push('result: ' + r.reason + ' (' + r.passed + ' passed, ' + r.failed + ' failed)');
      return {
        ok: r.reason === 'ok', reason: r.reason, output: r.output, log: log.join('\n'),
        passed: r.passed, failed: r.failed, skipped: 0, failures: r.failures,
        inputSha256: r.inputSha256, outputSha256: r.outputSha256, version: version, fileName: 'node-webkit.html'
      };
    }
  };

  globalThis.CC43 = CC43;
})();
