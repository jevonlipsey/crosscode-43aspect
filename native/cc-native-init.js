// Runs before the game's own scripts (NW.js inject_js_start).
// 1. A fresh native profile has empty localStorage, and options.js then defaults the render scale to 2 (canvas 2x2 the
//    pixels). The Windows build the user plays runs at scale 1 (canvas IG_WIDTH x IG_HEIGHT, measured on device), so seed
//    1 when nothing is stored yet. A value the game itself stores later (Options > Pixel Size) wins from then on.
// 2. Proof of load: writes <dataPath>/../cc43-native.json (next to the save folder, not in it) at 20 s, 60 s and 180 s:
//    runtime arch and versions, where saves go, the canvas size, and which pads the page sees (ids + buttons pressed).
try { if (localStorage.getItem('options.scale') === null) localStorage.setItem('options.scale', '1'); } catch (e) {}
(function(){
  if (typeof require === 'undefined' || typeof nw === 'undefined') return;
  var fs = require('fs'), path = require('path'), t0 = Date.now(), seen = {};
  function pads() {
    var r = [];
    try { [].slice.call(navigator.getGamepads()).forEach(function(p){ if (p) r.push(p); }); } catch (e) {}
    return r;
  }
  var poll = setInterval(function(){
    pads().forEach(function(p){ p.buttons.forEach(function(b, i){ if (b.pressed) seen[p.index + ':' + i] = 1; });
      p.axes.forEach(function(a, i){ if (Math.abs(a) > 0.5) seen[p.index + ':axis' + i + (a > 0 ? '+' : '-')] = 1; }); });
  }, 50);
  function dump(final) {
    try {
      var c = document.getElementById('canvas'), w = window;
      var out = {t: Math.round((Date.now() - t0) / 1000), at: new Date().toISOString(), arch: process.arch,
        nw: process.versions.nw, chromium: process.versions.chromium, dataPath: nw.App.dataPath, cwd: process.cwd(),
        argv: nw.App.fullArgv, IG: [w.IG_WIDTH, w.IG_HEIGHT, w.IG_GAME_SCALE], canvas: c ? [c.width, c.height] : null,
        window: [w.innerWidth, w.innerHeight], pads: pads().map(function(p){ return p.id; }), evpad: w.__ccEvpad || null,
        seen: Object.keys(seen), map: (w.ig && w.ig.game && w.ig.game.mapName) || null};
      fs.writeFileSync(path.join(nw.App.dataPath, '..', 'cc43-native.json'), JSON.stringify(out, null, 1) + '\n');
    } catch (e) {}
    if (final) clearInterval(poll);
  }
  setTimeout(dump, 20000); setTimeout(dump, 60000); setTimeout(function(){ dump(true); }, 180000);
})();
