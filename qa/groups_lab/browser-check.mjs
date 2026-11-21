import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
import {computeAccountGroupsSummary} from '../../src/accounting.ts';
const lab=path.dirname(fileURLToPath(import.meta.url));
const doc=JSON.parse(fs.readFileSync(path.join(lab,'assets/fixture.json'),'utf8'));
const html=fs.readFileSync(path.join(lab,'assets/reference.html'),'utf8');
const browser=await chromium.launch({...(process.env.CHROME_BIN?{executablePath:process.env.CHROME_BIN}:{})});
try {
 const context=await browser.newContext({viewport:{width:427,height:952},deviceScaleFactor:1,locale:'ar',offline:true});
 const requests=[];const errors=[];
 const page=await context.newPage();page.on('request',r=>{if(/^https?:/.test(r.url()))requests.push(r.url());});
 page.on('pageerror',e=>errors.push(e.message));
 await page.evaluate(()=>{window.log=[];window.Groups={postMessage:s=>window.log.push(JSON.parse(s))};});
 await page.setContent(html);
 const filters={};
 async function show(dark){
   const rows=computeAccountGroupsSummary(doc.accountGroups,doc.accounts,doc.ledger,filters,'ريال');
   await page.evaluate(s=>window.present(s),{rows,currencies:['ريال','دولار','يورو','عملة 2'],dark});
   await page.locator('tbody tr').last().waitFor();await page.evaluate(()=>document.fonts.ready);
 }
 for(const dark of [false,true]){
   await show(dark);
   assert.equal(await page.locator('tbody tr').count(),2);
   const balance=page.locator('.smart-col-bal strong').first();
   assert.equal(await balance.innerText(),'1,250.5-');
   await page.waitForFunction(v=>document.documentElement.classList.contains('dark')===v,dark);
   assert.equal(await balance.evaluate(e=>getComputedStyle(e).color),dark?'rgb(251, 113, 133)':'rgb(159, 18, 57)');
   const debit=page.locator('.smart-col-bal strong').last();
   assert.equal(await debit.innerText(),'80');
   assert.equal(await debit.evaluate(e=>getComputedStyle(e).color),dark?'rgb(96, 165, 250)':'rgb(11, 92, 168)');
   const dir=path.join(lab,'../screenshots');fs.mkdirSync(dir,{recursive:true});
   await page.locator('#table').screenshot({path:path.join(dir,'react-'+(dark?'dark':'light')+'.png')});
 }
 await page.getByLabel('عملة مجموعة الشمال').selectOption('دولار');
 assert.deepEqual(await page.evaluate(()=>window.log.at(-1)),{action:'currency',id:41,currency:'دولار'});
 filters[41]='دولار';await show(false);
 await page.waitForFunction(()=>document.querySelector('.smart-col-bal strong').innerText==='25');
 await page.getByRole('button',{name:/مجموعة الشمال/}).click();
 assert.deepEqual(await page.evaluate(()=>window.log.at(-1)),{action:'open',id:41});
 filters[41]='الكل';await show(false);
 await page.waitForFunction(()=>document.querySelector('.smart-col-bal strong').innerText==='1,225.5-');
 console.log('Reference all currencies: SAR -1250.5 and USD +25 appear as the unlabeled nominal sum -1225.5.');
 assert.deepEqual(requests,[]);assert.deepEqual(errors,[]);
 console.log('PASS two RTL themes; signed amount, independent currency and open intent; zero HTTP(S) requests and zero page errors (Chromium component).');
}finally{await browser.close();}
