import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const repo=fileURLToPath(new URL('../../',import.meta.url));
const out=path.resolve(process.argv[2] ?? '/tmp/nasqo-home-browser');
const width=Number(process.argv[3] ?? 427), height=Number(process.argv[4] ?? 710);
const ref=path.resolve(process.env.NASQO_REFERENCE ?? '/tmp/nasqo-hybrid-ref');
const fixture=JSON.parse(fs.readFileSync(path.join(repo,'qa/groups_lab/assets/fixture.json')));
const dto=JSON.parse(fs.readFileSync(path.join(repo,'qa/hybrid_home/fixture_snapshot.json')));
fs.mkdirSync(out,{recursive:true});
const browser=await chromium.launch(process.env.CHROME_BIN?{executablePath:process.env.CHROME_BIN}:{});
try{
 for(const variant of ['reference','embedded']){
  const base=variant==='reference'?ref:path.join(repo,'flutter_app/android/app/src/main/assets/hybrid_home');
  for(const dark of [false,true]){
   const context=await browser.newContext({viewport:{width,height},deviceScaleFactor:1,isMobile:true,hasTouch:true,locale:'ar',offline:true});
   const page=await context.newPage(), errors=[], forbidden=[];
   page.on('pageerror',e=>{errors.push(e.message);console.error(e.message);});
   const assets={'index.html':['text/html',path.join(base,'index.html')],'home.js':['application/javascript',path.join(base,'home.js')],'home.css':['text/css',path.join(base,'home.css')],'logo.png':['image/png',path.join(repo,'flutter_app/assets/nasqo_logo.png')],'arabic.ttf':['font/ttf',path.join(repo,'flutter_app/assets/fonts/NotoSansArabic-Regular.ttf')]};
   await page.route('**/*',route=>{
    const url=new URL(route.request().url()), entry=assets[url.pathname.slice(6)];
    if(url.origin!=='https://appassets.androidplatform.net'||!url.pathname.startsWith('/home/')||!entry){forbidden.push(url.href);return route.abort();}
    return route.fulfill({contentType:entry[0],path:entry[1]});
   });
   await page.addInitScript(()=>{window.events=[];window.NasqoHome={postMessage(raw){window.events.push(JSON.parse(raw));}};});
   await page.goto('https://appassets.androidplatform.net/home/index.html');
   await page.evaluate(s=>window.nasqoPresent(s),{...dto,fixture,dark});
   await page.waitForFunction(()=>window.events.some(e=>e.action==='paint'),null,{timeout:6000});
   await page.evaluate(()=>document.fonts.ready);
   const first=page.locator('.smart-col-bal strong').first();
   assert.equal(await first.innerText(),'1,250.5-');
   assert.equal(await page.locator('tbody tr').count(),2);
   assert.equal(await page.locator('[data-home-tile-id] svg').count(),24);
   assert.equal(await page.locator('html').getAttribute('dir'),'rtl');
   const name=variant+'-'+(dark?'dark':'light');
   const geometry=await page.evaluate(()=>{
    const rect=s=>{const r=document.querySelector(s).getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height};};
    const scroll=document.querySelector('.mobile-scroll');
    return {table:rect('table'),select:rect('select'),name:rect('.smart-col-name button'),row:rect('tbody tr'),tile:rect('[data-home-tile-id="new-voucher"]'),search:rect('[data-home-tile-id="quick-search"]'),scrollRange:scroll.scrollHeight-scroll.clientHeight,background:getComputedStyle(document.querySelector('.app-screen')).backgroundColor,fontLoaded:document.fonts.check('16px NasqoPilot'),balanceColor:getComputedStyle(document.querySelector('.smart-col-bal strong')).color};
   });
   assert.ok(geometry.fontLoaded);assert.ok(geometry.scrollRange>0);
   fs.writeFileSync(path.join(out,name+'.json'),JSON.stringify(geometry));
   await page.screenshot({path:path.join(out,name+'.png')});
   if(variant==='embedded'&&!dark){
    await page.getByLabel('عملة مجموعة الشمال').selectOption('دولار');
    assert.ok(await page.evaluate(()=>window.events.some(e=>e.action==='currency'&&e.id===41&&e.currency==='دولار')));
    await page.evaluate(s=>window.nasqoPresent(s),{...dto,rows:[{...dto.rows[0],currency:'دولار',netDebitMinusCredit:25},dto.rows[1]]});
    await page.waitForFunction(()=>document.querySelector('.smart-col-bal strong').innerText==='25');
    await page.getByRole('button',{name:/مجموعة الشمال/}).click();
    assert.ok(await page.evaluate(()=>window.events.some(e=>e.action==='group'&&e.id===41)));
    const tile=page.locator('[data-home-tile-id="new-voucher"]');
    await tile.scrollIntoViewIfNeeded();
    const pos=await tile.boundingBox();await page.mouse.move(pos.x+pos.width/2,pos.y+pos.height/2);
    await page.mouse.down();await page.waitForTimeout(720);await page.mouse.up();
    await page.getByTestId('home-tiles-edit-bar').waitFor({timeout:2500});
    await page.getByTestId('tile-pin-new-voucher').click();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='layout'&&e.value.pinned.includes('new-voucher')));
    assert.ok(await page.evaluate(()=>window.nasqoBack()));
    await page.getByTestId('home-tiles-edit-bar').waitFor({state:'detached'});
    await page.locator('[data-home-tile-id="quick-search"]').click();
    assert.ok(await page.evaluate(()=>window.events.some(e=>e.action==='tile'&&e.id==='quick-search')));
    await page.locator('.mobile-scroll').evaluate(el=>el.scrollTop=220);
    await page.waitForFunction(()=>window.events.some(e=>e.action==='scroll'&&e.y>0));
   }
   assert.deepEqual(errors,[]);assert.deepEqual(forbidden,[]);
   console.log('PASS',name,JSON.stringify(geometry));
   await context.close();
  }
 }
}finally{await browser.close();}
