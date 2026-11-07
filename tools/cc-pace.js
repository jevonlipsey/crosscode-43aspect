// CrossCode frame pacing (60 fps cadence). The game steps once per requestAnimationFrame with a variable time step.
// On a 120 Hz display (the Retroid Pocket Nova under gamescope) rAF fires every 8.3 ms and the game cannot hold 120,
// so its frames land on 1, 2 or 3 vblanks at random, which is the judder. This runs the game loop at most once per
// ~16.7 ms (every other vblank), the cadence the game was made for. On a 60 Hz display every tick passes: a no-op.
(function () {
  var MIN = 1000 / 60 - 4; // 12.7 ms: lets 16.7 ms ticks through, skips the in-between 8.3 ms ticks of a 120 Hz display
  function hook() {
    if (!(window.ig && ig.system && ig.system.run)) return void setTimeout(hook, 200);
    if (ig.system.__ccPace) return;
    var run = ig.system.run, last = -1e9;
    ig.system.run = function (t) {
      if (typeof t === 'number' && t - last < MIN) { window.requestAnimationFrame(ig.system.run.bind(ig.system)); return; }
      last = typeof t === 'number' ? t : performance.now();
      return run.apply(this, arguments);
    };
    ig.system.__ccPace = window.__ccPace = MIN;
  }
  hook();
})();
