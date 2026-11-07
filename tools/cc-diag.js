// Frame-timing probe. Injected via node-webkit.html; writes cc-diag.json into the game dir.
(function(){
  var fs=require('fs'), N=[], W=[], U=[], D=[], last=0, started=0, DUR=45000, wrapped=false, info={};
  try{
    var c=document.createElement('canvas'), gl=c.getContext('webgl'), e=gl&&gl.getExtension('WEBGL_debug_renderer_info');
    info.glRenderer=e?gl.getParameter(e.UNMASKED_RENDERER_WEBGL):'none';
    info.glVendor=e?gl.getParameter(e.UNMASKED_VENDOR_WEBGL):'none';
  }catch(x){info.glErr=String(x)}
  info.ua=navigator.userAgent; info.dpr=window.devicePixelRatio; info.inner=[innerWidth,innerHeight];
  info.screen=[screen.width,screen.height]; info.argv=(typeof nw!=='undefined'&&nw.App.argv)||null;
  info.cmd=process.argv; info.display=window.IG_SCREEN_MODE;
  function snap(k){try{info[k]={map:ig.game.mapName,loading:!!ig.loading,paused:!!ig.game.paused,ents:ig.game.entities.length,t:Math.round(performance.now())}}catch(x){info[k]=String(x)}}
  function save(){
    try{
      var d=[];for(var i=1;i<N.length;i++)d.push(N[i]-N[i-1]);
      info.deltas=d.map(function(v){return +v.toFixed(2)}); info.work=W.map(function(v){return +v.toFixed(2)});info.upd=U.map(function(v){return +v.toFixed(2)});info.drw=D.map(function(v){return +v.toFixed(2)});
      var cv=document.getElementById('canvas'); info.canvas=[cv.width,cv.height,cv.style.width,cv.style.height,cv.getBoundingClientRect().width];
      info.sys=ig.system?[ig.system.width,ig.system.height,ig.system.scale,ig.system.contextScale]:null;
      fs.writeFileSync('cc-diag.json',JSON.stringify(info));
    }catch(x){fs.writeFileSync('cc-diag-err.txt',String(x))}
  }
  function loop(t){
    if(!started){started=t;snap('at_start')}
    N.push(t);
    if(!wrapped&&window.ig&&ig.system&&ig.system.delegate){
      wrapped=true; var d=ig.system.delegate, r=d.run;
      d.run=function(){
        var g=ig.game;
        if(g&&!g.__w){g.__w=1;var u=g.update,dr=g.draw;
          g.update=function(){var s=performance.now();u.apply(this,arguments);U.push(performance.now()-s)};
          g.draw=function(){var s=performance.now();dr.apply(this,arguments);D.push(performance.now()-s)};}
        var s=performance.now(); r.apply(this,arguments); W.push(performance.now()-s)};
    }
    if(t-started<DUR)requestAnimationFrame(loop); else {snap('at_end');save();}
  }
  setTimeout(function(){requestAnimationFrame(loop)},60000);
})();
