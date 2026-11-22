import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import {states,findControl,measure} from './states.mjs';

export async function exerciseReleaseNavigation({view,until,shell,adb,save}) {
  const results=[];
  const evalCall=(fn,arg)=>view.evaluate('('+fn.toString()+')('+JSON.stringify(arg)+')');
  const element=(arg,action)=>view.evaluate('(() => {const n=('+findControl.toString()+')('+JSON.stringify(arg)+'); if(!n)return false; '+action+'})()');
  for(const state of states){
    console.log('Android release screen',state.name);
    for(const step of state.path){
      const arg=typeof step==='string'?{selector:step}:step;
      const point=await until(()=>element(arg,'n.scrollIntoView({block:"nearest"}); const r=n.getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2}'),state.name+' missing '+JSON.stringify(arg),10000);
      await view.call('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[point]});
      await view.call('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
    }
    await until(()=>evalCall(measure,state.screen),state.name+' did not open',12000);
    await delay(400);
    const ui=await evalCall(measure,state.screen);
    assert(ui.headers.length<=1 && ui.navBars.length<=1 && ui.footers.length<=1,state.name+' duplicate React navigation');
    if(state.name==='home'){
      assert.equal(ui.headers.length,1);assert.equal(ui.footers.length,1);assert.equal(ui.navBars.length,1);
    }
    assert.equal(await view.evaluate('location.pathname'),'/react/index.html');
    save(state.name+'-release.png',adb('exec-out','screencap','-p'));
    const screen=await view.call('Page.captureScreenshot',{format:'png'});
    save(state.name+'-content.png',Buffer.from(screen.data,'base64'));
    const native=JSON.parse(execFileSync('python3',['qa/qa10021/native_chrome.py','android-evidence/'+state.name+'-native.xml'],{encoding:'utf8'}));
    results.push({name:state.name,...ui,...native});
    save('release-navigation.json',JSON.stringify(results,null,2));
    if(state.name==='settings'){
      for(const label of ['المنشأة','المظهر','الطباعة','قاعدة البيانات']){
        await until(()=>element({selector:'[role=tab]',label},'n.click(); return true;'),'settings tab '+label,8000);
        await until(()=>element({selector:'[role=tab][aria-selected=true]',label},'return true;'),'active settings tab '+label,8000);
      }
    }
    if(state.name==='home')continue;
    for(let back=0;back<(state.back??1);back++){
      shell('input','keyevent','4');
      await delay(450);
    }
    await until(()=>view.evaluate("Boolean(document.querySelector('[data-flow-current=true] [data-testid=dashboard-screen]') && !document.querySelector('.drawer-layer.open,[data-testid=home-quick-sheet],[data-testid=dashboard-add-menu],[role=dialog]:not([hidden])'))"),'Android back from '+state.name+' did not return to React home',10000);
  }
  return results.map(({name,headers,navBars,outerWebViews,outsideNavigation})=>({name,headers:headers.length,navBars:navBars.length,outerWebViews:outerWebViews.length,outsideNavigation:outsideNavigation.length}));
}
