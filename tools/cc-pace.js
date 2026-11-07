// RESEARCH ONLY, not in the shipped patch. A start-time frame-pacing gate for CrossCode on >100 Hz displays.
// CrossCode steps its game once per requestAnimationFrame with a variable time step. At 120 Hz (the Retroid Pocket Nova)
// the game cannot keep up with every refresh, so its frames land 1, 2 or 3 refreshes apart at random. This runs the game
// at most once per ~16.7 ms, and only while refreshes come under 9.5 ms apart (60-100 Hz displays run as stock).
// tools/test-pace.mjs (2026-11-07): it evens out frame STARTS only; frames still reach the screen 1 or 2 vblanks after
// they start (cost straddles 8.3 ms), so the judder stays (holds 1/2/3/4 vs stock 1/2/3). See CLAUDE.local.md for the
// present-aligned design that should fix it. window.__cc43pace shows what it is doing.
(function () {
  var MIN = 1000 / 60 - 4, FAST = 9.5, KEEP = 120;
  var st = window.__cc43pace = { version: 1, min: MIN, active: false, ran: 0, skipped: 0 };
  function hook() {
    var s = window.ig && window.ig.system;
    if (!(s && s.run)) return void setTimeout(hook, 200);
    if (s.__cc43pace) return;
    var run = s.run, last = -1e9, prev = -1e9, quiet = KEEP;
    s.run = function (t) {
      if (typeof t === 'number') {
        var gap = t - prev;
        prev = t;
        quiet = gap > 0 && gap < FAST ? 0 : Math.min(quiet + 1, KEEP);
        st.active = quiet < KEEP;
        if (st.active && t - last < MIN) { st.skipped++; window.requestAnimationFrame(s.run.bind(s)); return; }
        last = t;
      }
      st.ran++;
      return run.apply(this, arguments);
    };
    s.__cc43pace = true;
  }
  hook();
})();
