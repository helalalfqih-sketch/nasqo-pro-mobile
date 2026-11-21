import React from 'react';
import {createRoot} from 'react-dom/client';
import {DashboardPage} from 'dashboard:presentation';
import {normalizeHomeTileLayout} from '../../src/utils/dashboardPrefs';

const root=createRoot(document.getElementById('home')!);
let initialized=false;
function send(action:string, fields:object={}) {
  window.NasqoHome?.postMessage(JSON.stringify({action,...fields}));
}
function restoreViewport(y:number) {
  const scroller=document.querySelector<HTMLElement>('.mobile-scroll');
  if(!scroller) {requestAnimationFrame(()=>restoreViewport(y));return;}
  document.fonts.ready.then(()=>requestAnimationFrame(()=>{
    scroller.scrollTop=y;
    let timer=0;
    scroller.addEventListener('scroll',()=>{
      clearTimeout(timer);
      timer=window.setTimeout(()=>send('scroll',{y:Math.round(scroller.scrollTop)}),140);
    },{passive:true});
    requestAnimationFrame(()=>send('paint'));
  }));
}
window.nasqoPresent=(snapshot)=>{
  const context={
    workspace:{companyName:snapshot.company,defaultCurrency:snapshot.defaultCurrency},
    accounts:__REFERENCE__ ? snapshot.fixture.accounts : [],
    accountGroups:__REFERENCE__ ? snapshot.fixture.accountGroups : [],
    ledger:__REFERENCE__ ? snapshot.fixture.ledger : [],
    extendedSettings:{},currencyCodes:snapshot.currencies,
    openQrScanner:()=>send('tile',{id:'qr-scanner'}),
    showToast:(text:string)=>{
      let el=document.getElementById('toast');
      if(!el){el=document.createElement('div');el.id='toast';el.className='toast';el.setAttribute('role','status');document.body.appendChild(el);}
      el.textContent=text;setTimeout(()=>{if(el?.textContent===text)el.remove();},1600);
    }
  };
  document.documentElement.classList.toggle('dark',snapshot.dark);
  const host={context,rows:snapshot.rows,layout:normalizeHomeTileLayout(snapshot.layout),
    selectCurrency:update=>{const [[id,currency]]=Object.entries(update({}));send('currency',{id:Number(id),currency});},
    openGroup:(id:number)=>send('group',{id}),openTile:(id:string)=>send('tile',{id}),
    editing:active=>send('editing',{active}),saveLayout:layout=>send('layout',{value:layout}),haptic:kind=>send('haptic',{kind})};
  root.render(<DashboardPage host={host}/>);
  if(!initialized){initialized=true;restoreViewport(snapshot.scroll??0);}
};
window.nasqoBack=()=>{
  if(!document.querySelector('[data-testid="home-tiles-edit-bar"]'))return false;
  window.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));
  return true;
};
window.nasqoTop=()=>document.querySelector('.mobile-scroll')?.scrollTo({top:0,behavior:'smooth'});
window.addEventListener('message',event=>{
  if(typeof event.data==='string') window.nasqoPresent(JSON.parse(event.data));
});
send('ready');
