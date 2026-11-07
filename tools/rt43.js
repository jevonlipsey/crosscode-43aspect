// LOCAL Mac render test (never deployed). Injected into a test copy of node-webkit.html by tools/rt43.sh.
// Drives the real game (Steam Mac install assets) through title -> save load -> menus, dumping canvas PNGs + a JSON report.
console.log("RT43 loaded env="+(typeof process!="undefined"&&process.env.CC_OUT)+" req="+typeof require);
(function(){
  var fs=require('fs'), OUT=process.env.CC_OUT, rep={steps:[],err:[]};
  function sys(){try{var c=document.getElementById('canvas');return {sys:[ig.system.width,ig.system.height,ig.system.scale,ig.system.contextScale],canvas:[c.width,c.height,c.style.width,c.style.height],win:[innerWidth,innerHeight],hd:sc.options.hdMode,mode:window.IG_SCREEN_MODE}}catch(e){return String(e)}}
  function shot(n){try{var d=document.getElementById('canvas').toDataURL('image/png').split(',')[1];fs.writeFileSync(OUT+'/'+n+'.png',Buffer.from(d,'base64'))}catch(e){rep.err.push(n+': '+e)}rep.steps.push({n:n,map:ig.game&&ig.game.mapName,st:sc.model&&sc.model.currentState,sub:sc.model&&sc.model.currentSubState})}
  function save(){fs.writeFileSync(OUT+'/report.json',JSON.stringify(rep,null,1))}
  function menu(sub){sc.menu.setDirectMode(true,sub);sc.model.enterMenu(true)}
  function leave(){try{sc.menu.exitMenu&&sc.menu.exitMenu();}catch(e){}try{sc.model.enterRunning()}catch(e){rep.err.push('leave '+e)}}
  fs.writeFileSync(OUT+'/loaded.txt',String(Date.now()));
  var steps=[],tick=0;
  function S(ms,f){steps.push([ms,f])}
  S(9000,function(){rep.info=sys();shot('00-title')});
  S(500,function(){ig.game.loadStart(0)});
  S(14000,function(){rep.info2=sys();shot('01-game')});
  S(4000,function(){shot('02-game-b')});
  var subs={items:1,skills:2,equip:3,status:4,synopsis:5,map:6,save:7,options:8,quests:10};
  Object.keys(subs).forEach(function(k){
    S(500,function(){menu(subs[k])}); S(3500,function(){shot('m-'+k)}); S(300,leave); S(1500,function(){});
  });
  S(500,function(){try{sc.model.enterPause(true)}catch(e){rep.err.push(e+'')}}); S(2500,function(){shot('p-pause')}); S(300,leave);
  S(500,function(){try{var m=sc.model.message,ce=new sc.CharacterExpression('main.lea','DEFAULT');m.addPerson(ce,sc.MESSAGE_SIDES.LEFT,0);m.showMessage('main.lea',new ig.LangLabel({en_US:'Dialogue box test: the quick brown fox jumps over the lazy dog, twice over.'}),true)}catch(e){rep.err.push('msg '+e)}}); S(2500,function(){shot('d-dialog')});
  S(500,function(){rep.done=1;save();try{nw.App.quit()}catch(e){process.exit(0)}});
  var i=0;function next(){if(i>=steps.length)return;var s=steps[i++];setTimeout(function(){try{s[1]()}catch(e){rep.err.push(i+': '+e)}save();next()},s[0])}
  function wait(){if(++tick%6==0)try{fs.writeFileSync(OUT+'/wait.txt',JSON.stringify({ig:!!window.ig,game:!!(window.ig&&ig.game),sc:!!window.sc,model:!!(window.sc&&sc.model),title:!!(window.sc&&sc.model&&sc.model.isTitle&&sc.model.isTitle()),loading:window.ig&&ig.loading,state:window.sc&&sc.model&&sc.model.currentState}))}catch(e){}if(window.ig&&ig.game&&window.sc&&sc.model&&sc.model.isTitle&&sc.model.isTitle()&&!ig.loading){next()}else setTimeout(wait,500)}
  setTimeout(wait,3000);
  setTimeout(function(){rep.timeout=1;save();process.exit(1)},170000);
})();
