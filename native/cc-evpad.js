// Fallback gamepad for the native build: if Chromium's own gamepad API sees no pad, read DroidDeck's virtual
// Xbox 360 pad straight from evdev (/dev/input/event*, served by libfakeinput) with Node and present it to the game
// as a standard-mapping Gamepad from navigator.getGamepads(). Linux only; does nothing when a real pad is visible.
(function(){
  if (typeof process === 'undefined' || process.platform !== 'linux') return;
  var fs = require('fs'), orig = navigator.getGamepads ? navigator.getGamepads.bind(navigator) : function(){ return []; };
  var buttons = [], axes = [0, 0, 0, 0], tmax = 255, pad = null, ts = 0, path = null;
  for (var i = 0; i < 17; i++) buttons.push({pressed: false, touched: false, value: 0});
  var KEY = {304: 0, 305: 1, 307: 2, 308: 3, 310: 4, 311: 5, 314: 8, 315: 9, 317: 10, 318: 11, 316: 16, 312: 6, 313: 7};
  function btn(i, v) { var b = buttons[i]; b.value = v; b.pressed = b.touched = v > 0.12; }
  function stick(v) { v = v / 32767; if (v < -1) v = -1; return Math.abs(v) < 0.08 ? 0 : v; }
  function onEvent(type, code, value) {
    ts = performance.now();
    if (type === 1 && KEY[code] !== undefined) btn(KEY[code], value ? 1 : 0);
    else if (type === 3) {
      if (code === 0) axes[0] = stick(value); else if (code === 1) axes[1] = stick(value);
      else if (code === 3) axes[2] = stick(value); else if (code === 4) axes[3] = stick(value);
      else if (code === 2 || code === 5) { if (value > tmax) tmax = value > 255 ? 1023 : 255; btn(code === 2 ? 6 : 7, value / tmax); }
      else if (code === 16) { btn(14, value < 0 ? 1 : 0); btn(15, value > 0 ? 1 : 0); }
      else if (code === 17) { btn(12, value < 0 ? 1 : 0); btn(13, value > 0 ? 1 : 0); }
    }
  }
  function open(p) {
    var s = fs.createReadStream(p, {highWaterMark: 24 * 64}), rest = Buffer.alloc(0);
    s.on('data', function(chunk) {
      var b = Buffer.concat([rest, chunk]), n = Math.floor(b.length / 24);
      for (var i = 0; i < n; i++) onEvent(b.readUInt16LE(i * 24 + 16), b.readUInt16LE(i * 24 + 18), b.readInt32LE(i * 24 + 20));
      rest = b.slice(n * 24);
    });
    s.on('error', function(e) { console.warn('cc-evpad: ' + p + ': ' + e); if (pad && path === p) pad = null; });
  }
  function start() {
    try { if ([].slice.call(orig()).filter(Boolean).length) return; } catch (e) {}
    var name = '';
    try { name = fs.readFileSync('/sys/class/input/event0/device/name', 'utf8').trim(); } catch (e) {}
    path = '/dev/input/event0';
    try { fs.accessSync(path, fs.constants.R_OK); } catch (e) { console.warn('cc-evpad: no ' + path); return; }
    open(path);
    pad = {id: (name || 'Xbox 360 Controller') + ' (cc-evpad evdev)', index: 0, connected: true, mapping: 'standard',
           buttons: buttons, axes: axes, vibrationActuator: null};
    Object.defineProperty(pad, 'timestamp', {get: function(){ return ts; }});
    navigator.getGamepads = function() { var r = [].slice.call(orig()); if (r.filter(Boolean).length) return r; return [pad, null, null, null]; };
    window.dispatchEvent && setTimeout(function(){ try { var e = new Event('gamepadconnected'); e.gamepad = pad; window.dispatchEvent(e); } catch (x) {} }, 0);
    window.__ccEvpad = path + ' "' + name + '"';
    console.log('cc-evpad: using ' + path + ' "' + name + '"');
  }
  setTimeout(start, 3000);
})();
