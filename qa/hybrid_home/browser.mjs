import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const repo=fileURLToPath(new URL('../../',import.meta.url));
const out=path.resolve(process.argv[2] ?? '/tmp/nasqo-home-browser');
const captureOnly=process.argv.includes('--capture-only');
const width=Number(process.argv[3] ?? 427), height=Number(process.argv[4] ?? 710);
const ref=path.resolve(process.env.NASQO_REFERENCE ?? '/tmp/nasqo-hybrid-ref');
const directory=JSON.parse(fs.readFileSync(path.join(repo,'qa/hybrid_home/directory_fixture.json')));
const deviceSample=process.env.NASQO_ANDROID_FIXTURE ? JSON.parse(fs.readFileSync(process.env.NASQO_ANDROID_FIXTURE)) : null;
if(deviceSample && !captureOnly) throw Error('The emulator sample is for visual comparison only');
const fixture=deviceSample?.fixture ?? JSON.parse(fs.readFileSync(path.join(repo,'qa/groups_lab/assets/fixture.json')));
const dto=JSON.parse(fs.readFileSync(path.join(repo,'qa/hybrid_home/fixture_snapshot.json')));
fs.mkdirSync(out,{recursive:true});
const browser=await chromium.launch(process.env.CHROME_BIN?{executablePath:process.env.CHROME_BIN}:{});
try{
 for(const variant of (deviceSample ? ['reference'] : ['reference','embedded'])){
  const base=variant==='reference'?ref:path.join(repo,'flutter_app/android/app/src/main/assets/hybrid_home');
  for(const dark of [false,true]){
   const context=await browser.newContext({viewport:{width,height},deviceScaleFactor:1,isMobile:true,hasTouch:true,locale:'ar',offline:true});
   const page=await context.newPage(), errors=[], forbidden=[];
   page.on('pageerror',e=>{errors.push(e.message);console.error(e.message);});
   const assets={'index.html':['text/html',path.join(base,'index.html')],'home.js':['application/javascript',path.join(base,'home.js')],'home.css':['text/css',path.join(base,'home.css')],'logo.png':['image/png',path.join(repo,'flutter_app/assets/nasqo_logo.png')],'arabic.ttf':['font/ttf',path.join(repo,'flutter_app/assets/fonts/NotoSansArabic-Regular.ttf')]};
   for(const weight of ['Regular','Medium','SemiBold','Bold']){
    const name='fonts/IBMPlexSansArabic-'+weight+'.ttf';
    assets[name]=['font/ttf',path.join(base,name)];
   }
   await page.route('**/*',route=>{
    const url=new URL(route.request().url()), entry=assets[url.pathname.slice(6)];
    if(url.origin!=='https://appassets.androidplatform.net'||!url.pathname.startsWith('/home/')||!entry){forbidden.push(url.href);return route.abort();}
    return route.fulfill({contentType:entry[0],path:entry[1]});
   });
   await page.addInitScript(()=>{window.events=[];window.NasqoHome={postMessage(raw){window.events.push(JSON.parse(raw));}};});
   await page.goto('https://appassets.androidplatform.net/home/index.html');
   await page.evaluate(s=>window.nasqoPresent(s),{...dto,fixture,dark,unread:deviceSample?.unread ?? dto.unread});
   await page.waitForFunction(()=>window.events.some(e=>e.action==='paint'),null,{timeout:6000});
   await page.evaluate(()=>document.fonts.ready);
   const first=page.locator('.smart-col-bal strong').first();
   assert.equal(await first.innerText(),'1,250.5-');
   assert.equal(await page.locator('tbody tr').count(),2);
   assert.equal(await page.locator('[data-metric]').count(),8);
   if (!deviceSample) {
     assert.equal(await page.locator('[data-metric="clients"] strong').innerText(),'1,250.5');
     assert.equal(await page.locator('[data-metric="purchases"] strong').innerText(),'−80');
   }
   assert.equal(await page.getByTestId('home-bottom-nav').count(),1);
   assert.equal(await page.locator('.flow-fixed-header:visible').count(),1);
   assert.equal(await page.locator('.flow-fixed-footer:visible').count(),1);
   assert.ok(await page.locator('.dashboard-header img').evaluate(img=>img.complete && img.naturalWidth>0));
   assert.equal(await page.locator('[data-home-tile-id] svg').count(),24);
   assert.equal(await page.locator('html').getAttribute('dir'),'rtl');
   const name=variant+'-'+(dark?'dark':'light');
   const geometry=await page.evaluate(()=>{
    const rect=s=>{const r=document.querySelector(s).getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height};};
    const scroll=document.querySelector('.mobile-scroll');
    return {metrics:Array.from(document.querySelectorAll('[data-metric]'),el=>el.getAttribute('aria-label')),table:rect('table'),select:rect('select'),name:rect('.smart-col-name button'),row:rect('tbody tr'),tile:rect('[data-home-tile-id="new-voucher"]'),search:rect('[data-home-tile-id="quick-search"]'),scrollRange:scroll.scrollHeight-scroll.clientHeight,background:getComputedStyle(document.querySelector('.app-screen')).backgroundColor,fontLoaded:document.fonts.check('700 16px "IBM Plex Sans Arabic"','مجموعة')&&document.fonts.check('400 16px "IBM Plex Sans Arabic"','ريال'),balanceColor:getComputedStyle(document.querySelector('.smart-col-bal strong')).color};
   });
   assert.equal(await page.evaluate(()=>document.documentElement.dataset.homeStyle),'pill');
   assert.ok(geometry.fontLoaded);assert.ok(geometry.scrollRange>0);
   fs.writeFileSync(path.join(out,name+'.json'),JSON.stringify(geometry));
   await page.screenshot({path:path.join(out,name+'.png')});
   if(captureOnly){await context.close();continue;}
   await page.getByTestId('home-nav-center-fab').tap();
   const quick=page.getByTestId('home-quick-sheet');
   await quick.getByText('مسح باركود').waitFor();
   assert.equal(await quick.getByRole('button').count(),4);
   await page.waitForFunction(()=>getComputedStyle(document.querySelector('.home-quick-sheet')).opacity==='1');
   await page.screenshot({path:path.join(out,name+'-quick.png'),animations:'disabled'});
   await quick.getByText('مسح باركود').tap();
   await page.waitForFunction(()=>window.events.some(e=>e.action==='tile'&&e.id==='qr-scanner'));
   await quick.waitFor({state:'detached'});
   await page.getByRole('button',{name:'فتح القائمة',exact:true}).tap();
   const drawer=page.getByRole('complementary',{name:'قائمة نسقو'});
   await drawer.getByText('حركة المخزون').waitFor();
   async function alignDrawerRow(name) {
     const row=drawer.getByRole('button',{name,exact:true});
     await row.evaluate(el=>{
       const scroll=el.closest('.mobile-scroll');
       scroll.scrollTop+=el.getBoundingClientRect().top-scroll.getBoundingClientRect().top;
     });
     return row;
   }
   async function visibleInDrawer(row) {
     return row.evaluate(el=>{
       const view=el.closest('.mobile-scroll').getBoundingClientRect();
       const rect=el.getBoundingClientRect();
       return rect.top>=view.top-1 && rect.bottom<=view.bottom+1;
     });
   }
   const backup=await alignDrawerRow('حفظ نسخة احتياطية على الهاتف');
   assert.ok(await visibleInDrawer(backup));
   assert.ok(await visibleInDrawer(drawer.getByRole('button',{name:'استعادة الصور من جوجل درايف',exact:true})));
   await page.screenshot({path:path.join(out,name+'-drawer-backup.png'),animations:'disabled'});
   await alignDrawerRow('مشاركة مجلد الصور');
   const about=drawer.locator('.drawer-sections > section').filter({has:page.getByRole('heading',{name:'عن التطبيق',exact:true})});
   assert.deepEqual(await about.getByRole('button').allTextContents(),[
     'شرح عن التطبيق على اليوتيوب','شروط الخدمة','سياسة الخصوصية','تواصل معنا',
     'تحديث التطبيق','مشاركة التطبيق','عن التطبيق','قيم التطبيق']);
   assert.ok(await visibleInDrawer(about.getByRole('button',{name:'قيم التطبيق',exact:true})));
   await page.screenshot({path:path.join(out,name+'-drawer-about.png'),animations:'disabled'});
   assert.ok(await page.evaluate(()=>window.nasqoBack()));
   await page.getByTestId('header-options-btn').tap();
   const opts=page.getByTestId('options-menu');
   await opts.getByRole('menuitem',{name:'نسخ إحتياطي'}).waitFor();
   assert.equal(await opts.getByTestId('options-reset-db-btn').isDisabled(),true);
   await opts.getByTestId('options-restore-backup-btn').tap();
   await page.waitForFunction(()=>window.events.some(e=>e.action==='navigate'&&e.id==='local-backups'));
   await page.getByRole('button',{name:'إضافة',exact:true}).tap();
   await page.getByTestId('dashboard-add-menu').getByText('قيد بسيط').tap();
   await page.waitForFunction(()=>window.events.some(e=>e.action==='tile'&&e.id==='simple-entry'));
   await page.getByTestId('home-nav-reports').tap();
   assert.equal(await page.getByTestId('reports-hub-menu').getByRole('button').count(),10);
   await page.screenshot({path:path.join(out,name+'-reports.png')});
   await page.getByTestId('reports-hub-menu').getByText('المخزون المتبقي',{exact:true}).tap();
   await page.waitForFunction(()=>window.events.some(e=>e.action==='navigate'&&e.id==='report-stock'));
   assert.ok(await page.evaluate(()=>window.nasqoBack()));
   await page.getByTestId('reports-hub-menu').waitFor({state:'detached'});
   if(variant==='embedded'&&!dark){
    await page.getByTestId('home-nav-reports').tap();
    await page.getByTestId('reports-hub-menu').getByText('ميزان المراجعة',{exact:true}).tap();
    await page.evaluate(s=>window.nasqoPresent(s),{...dto,directory:directory.trial});
    const trial=page.getByTestId('trial-balance-modal');
    assert.equal(await trial.getByTestId('trial-total-debit').innerText(),'80');
    assert.equal(await trial.getByTestId('trial-total-credit').innerText(),'1,250.50');
    await trial.getByLabel('عملة ميزان المراجعة').selectOption('الكل');
    await page.waitForFunction(()=>window.events.some(e=>e.action==='trialFilter'&&e.currency==='الكل'));
    await page.evaluate(s=>window.nasqoPresent(s),{...dto,directory:directory.trialAll});
    const dollars=trial.locator('[data-currency="دولار"]');
    assert.equal(await dollars.getByTestId('trial-total-debit').innerText(),'25');
    assert.equal(await trial.locator('[data-currency]').count(),4);
    await page.screenshot({path:path.join(out,'embedded-trial-all.png')});
    await trial.getByRole('radio',{name:'شهري'}).check();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='trialFilter'&&/^\d{4}-\d{2}-01$/.test(e.from)));
    assert.ok(await page.evaluate(()=>window.nasqoBack()));
    await page.getByTestId('reports-hub-menu').waitFor();
    assert.ok(await page.evaluate(()=>window.nasqoBack()));
    await page.evaluate(s=>window.nasqoPresent(s),dto);
    const metric=id=>page.locator('[data-metric="'+id+'"]');
    const region=page.getByTestId('metric-editor');
    const sales=metric('sales'), purchases=metric('purchases');
    const hit=await sales.boundingBox(), otherMetric=await purchases.boundingBox();
    const client=await context.newCDPSession(page);
    const point=b=>({x:b.x+b.width/2,y:b.y+b.height/2});
    await client.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[point(hit)]});
    await region.waitFor();
    await client.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
    await page.mouse.move(point(hit).x,point(hit).y);await page.mouse.down();
    await page.mouse.move(point(otherMetric).x,point(otherMetric).y,{steps:9});await page.mouse.up();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='metricLayout'&&e.value.order[0]==='purchases'));
    await region.getByLabel('تثبيت المؤشر').click();
    await region.getByText('تبديل اللون').click();
    await metric('employees').click();await region.getByLabel('إخفاء المؤشر').click();
    const metricsLayout=await page.evaluate(()=>window.events.filter(e=>e.action==='metricLayout').at(-1).value);
    assert.deepEqual(metricsLayout.pinned,['sales']);assert.deepEqual(metricsLayout.hidden,['employees']);
    assert.equal(metricsLayout.toneOverrides.sales,'amber');
    await page.reload();await page.evaluate(s=>window.nasqoPresent(s),{...dto,metricLayout:metricsLayout});
    await page.waitForFunction(()=>window.events.some(e=>e.action==='paint'));
    assert.equal(await metric('employees').count(),0);assert.equal(await sales.getAttribute('data-accent'),'amber');
    await sales.focus();await page.keyboard.press('F2');
    await region.getByText('إظهار الموظفين').click();await region.getByText('افتراضي').click();
    assert.equal(await page.locator('[data-metric]').count(),8);
    assert.ok(await page.evaluate(()=>window.nasqoBack()));
    await region.waitFor({state:'detached'});
    await page.getByLabel('عملة مجموعة الشمال').selectOption('دولار');
    assert.ok(await page.evaluate(()=>window.events.some(e=>e.action==='currency'&&e.id===41&&e.currency==='دولار')));
    await page.evaluate(s=>window.nasqoPresent(s),{...dto,rows:[{...dto.rows[0],currency:'دولار',netDebitMinusCredit:25},dto.rows[1]]});
    await page.waitForFunction(()=>document.querySelector('.smart-col-bal strong').innerText==='25');
    await page.getByRole('button',{name:/مجموعة الشمال/}).click();
    assert.ok(await page.evaluate(()=>window.events.some(e=>e.action==='group'&&e.id===41)));
    await page.evaluate(s=>window.nasqoPresent(s),{...dto,directory:directory.suppliers});
    const vendors=page.getByTestId('purchases-screen');
    await vendors.waitFor();
    assert.equal(await vendors.locator('article').count(),2);
    assert.equal(await page.locator('.flow-fixed-header:visible').count(),1);
    assert.equal(await page.locator('.flow-fixed-footer:visible').count(),1);
    await page.getByLabel('حسابات العملة فقط').check();
    assert.equal(await vendors.locator('article').count(),1);
    await vendors.getByRole('button',{name:'فتح كشف عميل دولار تجريبي'}).tap();
    assert.ok(await page.evaluate(()=>window.events.some(e=>e.action==='account'&&e.id==='qa-u'&&e.op==='statement')));
    await vendors.getByRole('button',{name:'عمليات عميل دولار تجريبي'}).click();
    await page.getByTestId('vendor-operations-menu').getByText('حوالة جديدة').click();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='account'&&e.id==='qa-u'&&e.op==='transfer'));
    await page.getByLabel('عملة المشتريات').selectOption('الكل');
    assert.ok(await page.evaluate(()=>window.events.some(e=>e.action==='filter'&&e.currency==='الكل')));
    await page.evaluate(s=>window.nasqoPresent(s),{...dto,directory:directory.allCurrencies});
    await page.getByLabel('تصدير المشتريات').click();await page.getByTestId('export-menu').waitFor();
    assert.ok(await page.evaluate(()=>window.nasqoBack()));
    await page.screenshot({path:path.join(out,'embedded-suppliers.png')});
    assert.ok(await page.evaluate(()=>window.nasqoBack()));
    await page.evaluate(s=>window.nasqoPresent(s),dto);
    await page.getByLabel('عملة مجموعة الشمال').selectOption('الكل');
    await page.evaluate(s=>window.nasqoPresent(s),{...dto,rows:[{...dto.rows[0],currency:'الكل',netDebitMinusCredit:null,amounts:[{value:-1250.5,currency:'ريال'},{value:25,currency:'دولار'}]},dto.rows[1]]});
    const multi=page.locator('tbody tr').first().locator('td.smart-col-bal');
    await multi.locator('span.neg strong').waitFor();
    assert.equal(await multi.locator('span.neg strong').innerText(),'1,250.5- · ريال');
    assert.equal(await multi.locator('span.pos strong').innerText(),'25 · دولار');
    assert.equal(await multi.locator('span.neg strong').evaluate(e=>getComputedStyle(e).color),'rgb(159, 18, 57)');
    assert.equal(await multi.locator('span.pos strong').evaluate(e=>getComputedStyle(e).color),'rgb(11, 92, 168)');
    await page.evaluate(s=>window.nasqoPresent(s),dto);
    const tile=page.locator('[data-home-tile-id="new-voucher"]');
    await tile.scrollIntoViewIfNeeded();
    const pos=await tile.boundingBox();await page.mouse.move(pos.x+pos.width/2,pos.y+pos.height/2);
    await page.mouse.down();await page.waitForTimeout(720);await page.mouse.up();
    await page.getByTestId('home-tiles-edit-bar').waitFor({timeout:2500});
    const other=page.locator('[data-home-tile-id="new-transfer"]');
    assert.ok(await other.evaluate(el=>el.getAnimations().some(a=>a.animationName==='smart-tile-jiggle' && a.effect.getKeyframes().length>=2)), 'real reference keyframes while editing');
    await page.emulateMedia({reducedMotion:'reduce'});
    assert.equal(await other.evaluate(el=>el.getAnimations().filter(a=>a.animationName==='smart-tile-jiggle').length),0);
    await tile.scrollIntoViewIfNeeded();
    await tile.evaluate(e=>e.scrollIntoView({block:'center',behavior:'instant'}));
    const a=await tile.boundingBox(), b=await other.boundingBox();
    await page.mouse.move(a.x+a.width/2,a.y+a.height/2);await page.mouse.down();
    await page.mouse.move(b.x+b.width/2,b.y+b.height/2,{steps:8});await page.mouse.up();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='layout'&&e.value.order.indexOf('new-voucher')>e.value.order.indexOf('new-transfer')));
    await page.getByTestId('tile-pin-new-voucher').click();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='layout'&&e.value.pinned.includes('new-voucher')));
    await page.getByTestId('selected-tile-tone-btn').click();
    await page.getByTestId('tile-hide-new-transfer').click();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='layout'&&e.value.hidden.includes('new-transfer')));
    const layout=await page.evaluate(()=>window.events.filter(e=>e.action==='layout').at(-1).value);
    assert.ok(Object.keys(layout.toneOverrides).length>0);
    // Recreate the browser document with the layout returned by the host.
    await page.reload();
    await page.evaluate(s=>window.nasqoPresent(s),{...dto,layout});
    await page.waitForFunction(()=>window.events.some(e=>e.action==='paint'));
    assert.equal(await page.locator('[data-home-tile-id="new-transfer"]').count(),0);
    assert.equal(await page.getByTestId('home-pinned-tiles').locator('[data-home-tile-id="new-voucher"]').count(),1);
    const pinned=page.locator('[data-home-tile-id="new-voucher"]');
    await pinned.scrollIntoViewIfNeeded();
    const box=await pinned.boundingBox();
    const cdp=await context.newCDPSession(page);
    const finger={x:box.x+box.width/2,y:box.y+box.height/2};
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[finger]});
    await page.getByTestId('home-tiles-edit-bar').waitFor();
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
    assert.equal(await page.locator('.hybrid-shell').evaluate(el=>el.inert),false,'long press release must not activate a group beneath the moved tile');
    await page.getByTestId('tile-restore-new-transfer').click();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='layout'&&!e.value.hidden.includes('new-transfer')));
    await page.getByTestId('home-tiles-reset-btn').click();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='layout'&&e.value.pinned.length===0&&e.value.hidden.length===0&&Object.keys(e.value.toneOverrides).length===0));
    assert.ok(await page.evaluate(()=>window.nasqoBack()));
    await page.getByTestId('home-tiles-edit-bar').waitFor({state:'detached'});
    await page.locator('[data-home-tile-id="quick-search"]').click();
    assert.ok(await page.evaluate(()=>window.events.some(e=>e.action==='tile'&&e.id==='quick-search')));
    for (const [id,screen] of [['warehouses','warehouses'],['accounts','chart'],['statement','picker']]) {
      await page.locator('[data-home-tile-id="'+id+'"]').click();
      await page.evaluate(s=>window.nasqoPresent(s),{...dto,directory:directory[screen]});
      if (screen==='warehouses') {
        await page.getByRole('button',{name:'بحث في المخازن'}).click();
        await page.getByLabel('اسم المخزن للبحث').fill('المختبر');
        await page.getByLabel('تعديل مخزن المختبر').click();
        assert.ok(await page.evaluate(()=>window.events.some(e=>e.action==='warehouse'&&e.op==='edit'&&e.id==='qa-wh')));
        await page.getByLabel('اسم المخزن للبحث').fill('مفقود');
        await page.getByText('لا توجد مخازن مطابقة للبحث.').waitFor();
      } else if (screen==='chart') {
        await page.getByTestId('coa-search-input').fill('دولار');
        await page.getByRole('button',{name:'عميل دولار تجريبي',exact:true}).click();
        await page.getByTestId('chart-of-accounts-modal').waitFor();
      } else {
        await page.getByTestId('account-picker-search-input').fill('دولار');
        await page.getByRole('listbox',{name:'الحسابات'}).getByRole('option',{name:/عميل دولار تجريبي/}).click();
        await page.getByRole('button',{name:'موافق',exact:true}).click();
        await page.waitForFunction(()=>window.events.some(e=>e.action==='account'&&e.id==='qa-u'&&e.op==='statement'));
      }
      assert.ok(await page.evaluate(()=>window.nasqoBack()));
      await page.evaluate(s=>window.nasqoPresent(s),dto);
    }
    await page.evaluate(s=>window.nasqoPresent(s),{...dto,appearance:{primary:'#047857',secondary:'#0f766e',radius:9}});
    await page.waitForFunction(()=>{
      const tile=document.querySelector('[data-home-tile-id="new-voucher"]');
      const style=getComputedStyle(tile);
      return style.backgroundColor==='rgb(4, 120, 87)' && style.borderRadius==='9px';
    });
    await page.locator('.mobile-scroll').evaluate(el=>el.scrollTop=220);
    await page.waitForFunction(()=>window.events.some(e=>e.action==='scroll'&&e.y>0));
   }
   if (variant === 'embedded') {
     const entry = {id:'doc-41',entryNumber:9041,documentNumber:'QA-41',entryDate:'2026-11-21',
       accountName:'مورد الاختبار',warehouseName:'مخزن الاختبار',typeLabel:'فاتورة اختبار',details:'كشف محفوظ',
       amount:25.5,currency:'دولار',lineCount:1};
     const doc = {screen:'document',company:'مختبر المطابقة',generatedAt:'2026-11-21T09:30:00',
       dark,entry,lines:[{id:0,itemName:'خيط تجريبي',unit:'حبة',price:8.5,quantity:3,total:25.5}]};
     await page.evaluate(data=>window.nasqoPresent(data),doc);
     await page.getByRole('table',{name:'بنود المستند'}).getByText('خيط تجريبي').waitFor();
     assert.equal(await page.getByTestId('cash-invoice-quantity-total').innerText(),'3');
     assert.equal(await page.getByTestId('cash-invoice-grand-total').innerText(),'25.5');
     assert.equal(await page.getByTestId('home-bottom-nav').count(),0);
     await page.getByTestId('cash-invoice-actual-size').click();
     assert.equal(await page.getByTestId('cash-invoice-zoom-value').innerText(),'100%');
     await page.getByTestId('cash-invoice-reset').click();
     assert.notEqual(await page.getByTestId('cash-invoice-zoom-value').innerText(),'100%');
     assert.equal(await page.getByTestId('cash-invoice-upload-drive').isDisabled(),true);
     await page.getByRole('button',{name:'طباعة الفاتورة'}).click();
     await page.waitForFunction(()=>window.events.some(e=>e.action==='documentOutput'&&e.op==='print'));
     await page.screenshot({path:path.join(out,name+'-document.png')});
     await page.evaluate(data=>window.nasqoPresent(data),{...doc,lines:[],entry:{...entry,lineCount:0}});
     await page.getByText('تفاصيل البنود غير متاحة').waitFor();
     assert.equal(await page.getByTestId('cash-invoice-quantity-total').innerText(),'—');
     await page.getByRole('button',{name:'رجوع',exact:true}).click();
     await page.waitForFunction(()=>window.events.some(e=>e.action==='documentClose'));
   }
   assert.deepEqual(errors,[]);assert.deepEqual(forbidden,[]);
   console.log('PASS',name,JSON.stringify(geometry));
   await context.close();
  }
 }
}finally{await browser.close();}
