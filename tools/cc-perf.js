// Frame-timing benchmark (probe builds only, never shipped). Loaded by a <script> tag in a test node-webkit.html.
// Deterministic: at the title it presses "Continue" itself (ig.game.loadStart(lastUsedSlot), same call as the button);
// if the game boots straight into a map it uses that. It waits for the map to settle, records DUR ms of frames, writes
// cc-perf.json into the working directory (the package dir: the game dir under Proton, the private app dir natively),
// checks the pad for 12 s, then quits the game so the session ends on its own. No input injection needed for the run
// itself; tools/perfrun.sh walks the player left/right during the recording so the camera scrolls.
// Recorded per GAME frame (each ig.system.delegate.run, i.e. what reaches the screen): start time, run time, the dt the
// game stepped with (ig.system.rawTick), camera (ig.game.screen) and player position. Plus every rAF timestamp.
(function(){
  var fs=require('fs'), N=[], W=[], U=[], D=[], G=[], TK=[], CX=[], CY=[], PX=[], PY=[], SETTLE=8000, DUR=40000,
      info={t0:Date.now(),marks:{},v:2}, phase='boot', tMap=0, wrapped=false;
  function mark(k){info.marks[k]=Math.round(performance.now())}
  try{
    var c=document.createElement('canvas'), gl=c.getContext('webgl'), e=gl&&gl.getExtension('WEBGL_debug_renderer_info');
    info.glRenderer=e?gl.getParameter(e.UNMASKED_RENDERER_WEBGL):(gl?gl.getParameter(gl.RENDERER):'none');
  }catch(x){info.glErr=String(x)}
  info.ua=navigator.userAgent; info.versions=process.versions; info.arch=process.arch; info.platform=process.platform;
  info.argv=process.argv; info.cwd=process.cwd(); info.hw=navigator.hardwareConcurrency;
  try{info.dataPath=require('nw.gui').App.dataPath}catch(x){info.dataPath='err '+x}
  try{info.startPath=nw.App.startPath}catch(x){}
  function snap(){try{return {map:ig.game.mapName,loading:!!ig.loading,ents:ig.game.entities.length,t:Math.round(performance.now())}}catch(x){return String(x)}}
  function r2(a){return a.map(function(v){return +v.toFixed(2)})}
  function r1(a){return a.map(function(v){return +v.toFixed(1)})}
  function stats(x){if(!x.length)return null;var s=x.slice().sort(function(a,b){return a-b}),m=x.reduce(function(a,b){return a+b},0)/x.length;
    return {n:x.length,mean:+m.toFixed(2),med:s[x.length>>1],p95:s[Math.floor(x.length*.95)],p99:s[Math.floor(x.length*.99)],max:s[s.length-1],
      over33:+(100*x.filter(function(v){return v>33.4}).length/x.length).toFixed(2),over17:+(100*x.filter(function(v){return v>17.5}).length/x.length).toFixed(2)}}
  function save(){
    try{
      var d=[];for(var i=1;i<N.length;i++)d.push(N[i]-N[i-1]);
      var g=[];for(i=1;i<G.length;i++)g.push(G[i]-G[i-1]);
      info.deltas=r2(d); info.work=r2(W); info.upd=r2(U); info.drw=r2(D);
      info.frames={t:r2(G),tick:r2(TK),cx:r1(CX),cy:r1(CY),px:r1(PX),py:r1(PY)};
      info.stats={rAF:stats(d),game:stats(g),run:stats(W),update:stats(U),draw:stats(D)};
      var cv=document.getElementById('canvas'); info.canvas=[cv.width,cv.height,cv.style.width,cv.style.height];
      try{info.pads=[].slice.call(navigator.getGamepads()).filter(Boolean).map(function(g){return g.id+' '+g.mapping})}catch(x){info.pads=String(x)}
      info.sys=ig.system?[ig.system.width,ig.system.height,ig.system.scale,ig.system.contextScale,ig.system.frameSkip]:null;
      info.pace=window.__ccPace||null; info.evpad=window.__ccEvpad||null;
      fs.writeFileSync('cc-perf.json',JSON.stringify(info));
    }catch(x){try{fs.writeFileSync('cc-perf-err.txt',String(x&&x.stack||x))}catch(y){}}
  }
  function wrap(){
    if(wrapped||!(window.ig&&ig.system&&ig.system.delegate))return; wrapped=true;
    var d=ig.system.delegate, r=d.run;
    d.run=function(){
      var g=ig.game;
      if(phase==='rec'&&g&&!g.__w){g.__w=1;var u=g.update,dr=g.draw;
        g.update=function(){var s=performance.now();u.apply(this,arguments);if(phase==='rec')U.push(performance.now()-s)};
        g.draw=function(){var s=performance.now();dr.apply(this,arguments);if(phase==='rec')D.push(performance.now()-s)};}
      var s=performance.now(); r.apply(this,arguments);
      if(phase==='rec'){var e=performance.now(); W.push(e-s); G.push(s); TK.push(1000*(ig.system.rawTick||0));
        try{CX.push(g.screen.x);CY.push(g.screen.y)}catch(x){CX.push(0);CY.push(0)}
        try{var p=g.playerEntity.coll.pos;PX.push(p.x);PY.push(p.y)}catch(x){PX.push(0);PY.push(0)}}
    };
  }
  function loop(t){
    if(phase==='rec'){N.push(t); if(t-info.marks.rec>=DUR){phase='pad';mark('done');info.at_end=snap();padCheck();return}}
    requestAnimationFrame(loop);
  }
  function quit(){setTimeout(function(){try{nw.App.quit()}catch(x){try{require('nw.gui').App.quit()}catch(y){process.exit(0)}}},1500)}
  function padCheck(){
    var P=info.pad={ids:{},pressed:{},samples:0,evpad:window.__ccEvpad||null}, t0=performance.now();
    try{fs.writeFileSync('cc-perf-pad.txt','pad')}catch(x){}
    (function poll(){
      try{[].slice.call(navigator.getGamepads()).filter(Boolean).forEach(function(g){P.ids[g.id]=g.mapping;
        g.buttons.forEach(function(b,i){if(b.pressed)P.pressed[g.id+' b'+i]=1})})}catch(x){P.err=String(x)}
      P.samples++;
      if(performance.now()-t0<12000)setTimeout(poll,50);else{P.evpad=window.__ccEvpad||null;phase='done';save();quit()}
    })();
  }
  function inMap(){return ig.game&&ig.game.mapName&&!ig.loading&&sc.model.isGame&&sc.model.isGame()}
  function tick(){
    try{
      wrap();
      if(phase==='boot'&&window.sc&&sc.model&&sc.model.isTitle&&sc.model.isTitle()&&!ig.loading){phase='title';mark('title');
        setTimeout(function(){mark('continue');info.slot=ig.storage.lastUsedSlot;ig.game.loadStart(ig.storage.lastUsedSlot);phase='loading'},2000)}
      else if(phase==='boot'&&window.sc&&sc.model&&inMap()){phase='loading';mark('direct')}
      else if(phase==='loading'&&inMap()){
        if(!tMap){tMap=performance.now();mark('map')}
        else if(performance.now()-tMap>=SETTLE){phase='rec';mark('rec');info.at_start=snap();try{fs.writeFileSync('cc-perf-rec.txt','rec')}catch(x){}requestAnimationFrame(loop);return}
      }
    }catch(x){info.tickErr=String(x)}
    if(phase!=='rec'&&phase!=='done'&&phase!=='pad')setTimeout(tick,250);
  }
  setTimeout(tick,1000);
  setTimeout(function(){if(phase!=='done'){info.timeout=phase;info.at_end=snap();save()}},300000);
})();
