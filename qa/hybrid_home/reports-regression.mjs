// Exercise the full web ReportsHubModal from before and after its menu extraction.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {build} from 'esbuild';
import {chromium} from 'playwright';

const root = fileURLToPath(new URL('../../',import.meta.url));
const out = path.resolve(process.argv[2] ?? '/tmp/nasqo-reports-regression');
const base = '848a55527221d8982f32522b3f434c4d1c931b00';
const fixed = file=>execFileSync('git',['show',base+':'+file],{cwd:root,encoding:'utf8'});
const modulePath = 'src/components/ReportsHubModal.tsx';
assert.equal(execFileSync('git',['rev-parse',base+':'+modulePath],{cwd:root,encoding:'utf8'}).trim(),
  '58de38bdfe7f6af5fb31386b6cad3f2dcc4f539b');
const frozen = ['src/styles.css','src/prototype.css'].map(fixed).join('\n');
const fixture=JSON.parse(fixed('qa/groups_lab/assets/fixture.json'));
const fonts=path.join(root,'flutter_app/android/app/src/main/assets/hybrid_home/fonts');
fs.mkdirSync(out,{recursive:true});
const browser=await chromium.launch(process.env.CHROME_BIN?{executablePath:process.env.CHROME_BIN}:{});
const evidence={};
try {
  for (const variant of ['before','after']) {
    const bundle=await build({stdin:{resolveDir:root,loader:'tsx',contents:`
      import React,{useState} from 'react';
      import {createRoot} from 'react-dom/client';
      import {ReportsHubModal} from 'regression:reports';
      const fixture=${JSON.stringify(fixture)};
      window.actions=[];
      function Test() {
        const [open,setOpen]=useState(false);
        return <><button id="open" onClick={()=>setOpen(true)}>التقارير</button>
          <ReportsHubModal open={open} onClose={()=>setOpen(false)} uid="fixture"
            accounts={fixture.accounts} ledger={fixture.ledger} cashboxes={[]}
            warehouses={[{id:'w',name:'المخزن'}]} inventory={[{id:'i',name:'قماش',warehouseId:'w',quantity:3,avgCost:12,unit:'متر'}]}
            defaultCurrency="ريال" currencyCodes={['ريال','دولار']}
            onOpenCashboxes={()=>window.actions.push('cashboxes')} onOpenTrialBalance={()=>window.actions.push('trial')}
            onOpenInventoryMovements={()=>window.actions.push('movement')}/></>;
      }
      createRoot(document.getElementById('root')).render(<Test/>);`},
      bundle:true,write:false,jsx:'automatic',minify:true,define:{'process.env.NODE_ENV':'"production"'},
      plugins:[{name:'fixed-web-report',setup(b) {
        b.onResolve({filter:/^regression:reports$/},()=>({path:'report',namespace:'report'}));
        b.onLoad({filter:/.*/,namespace:'report'},()=>({contents:variant==='before'?fixed(modulePath):fs.readFileSync(path.join(root,modulePath),'utf8'),
          resolveDir:path.join(root,'src/components'),loader:'tsx'}));
        b.onResolve({filter:/^\.\.\/firebase$/},()=>({path:'fixture',namespace:'fixture'}));
        b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export async function fetchInventoryMovementsReport(){return {itemRows:[],totals:{totalSales:0,totalProfit:0}}}'}));
      }}]});
    for (const mode of ['light','dark']) {
      const context=await browser.newContext({viewport:{width:427,height:900},locale:'ar',offline:true,deviceScaleFactor:1});
      const page=await context.newPage(), errors=[], outside=[];
      page.on('pageerror',err=>errors.push(err.message));
      const origin='https://appassets.androidplatform.net';
      await page.route('**/*',route=>{
        const url=new URL(route.request().url());
        if (url.origin===origin) {
          if (url.pathname==='/') return route.fulfill({contentType:'text/html',body:`<!doctype html><html dir="rtl" lang="ar" class="${mode==='dark'?'dark':''}"><meta charset="utf-8"><link rel="stylesheet" href="/style.css"><div id="root" class="nasqo-app"></div><script src="/test.js"></script></html>`});
          if (url.pathname==='/assets/aistudio/NASQO_PRO_ERP_800_022d325f.png')
            return route.fulfill({contentType:'image/png',path:path.join(root,'public',url.pathname.slice(1))});
          if (url.pathname==='/test.js') return route.fulfill({contentType:'text/javascript',body:bundle.outputFiles[0].text});
          if (url.pathname==='/style.css') {
            const css=variant==='before'?frozen:['src/styles.css','src/prototype.css'].map(f=>fs.readFileSync(path.join(root,f),'utf8')).join('\n');
            const font=[['Regular',400],['Medium',500],['SemiBold',600],['Bold',700]].map(([name,weight])=>
              '@font-face{font-family:"IBM Plex Sans Arabic";font-weight:'+weight+';src:url("/IBMPlexSansArabic-'+name+'.ttf")}').join('\n');
            return route.fulfill({contentType:'text/css',body:font+'\n'+css});
          }
          if (/^\/IBMPlexSansArabic-(Regular|Medium|SemiBold|Bold)\.ttf$/.test(url.pathname))
            return route.fulfill({contentType:'font/ttf',path:path.join(fonts,path.basename(url.pathname))});
        }
        outside.push(url.href);return route.abort();
      });
      await page.goto(origin+'/');await page.locator('#open').click();
      const menu=page.getByTestId('reports-hub-menu');
      const buttons=menu.getByRole('button');
      const names=await buttons.allTextContents();assert.equal(names.length,10);
      await page.evaluate(async()=>{
        await document.fonts.ready;
        await Promise.all(Array.from(document.images,img=>img.decode().catch(()=>{})));
        for (const animation of document.getAnimations()) {
          if (animation.effect?.getComputedTiming().iterations!==Infinity) animation.finish();
        }
        await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
      });
      await page.screenshot({path:path.join(out,variant+'-'+mode+'.png'),animations:'disabled'});
      const details=[];
      for (const [i,name] of names.entries()) {
        await menu.getByRole('button',{name,exact:true}).click();
        if ([0,3,4].includes(i)) {
          await menu.waitFor({state:'detached'});
          assert.equal(await page.evaluate(()=>window.actions.at(-1)),({0:'cashboxes',3:'trial',4:'movement'})[i]);
          await page.locator('#open').click();continue;
        }
        if (i===7) await page.getByText('إجمالي الأرباح', {exact:true}).waitFor();
        const detail=page.locator('.reports-hub-detail');await detail.waitFor();
        const select=detail.locator('select').first();
        if (await select.count()) {
          const values=await select.locator('option').evaluateAll(opts=>opts.map(o=>o.value));
          if(values.length>1) await select.selectOption(values[1]);
        }
        details.push({name,body:await detail.innerText()});
        await page.getByTestId('reports-back-btn').click();await menu.waitFor();
      }
      await page.locator('.account-groups-footer button').click();
      await menu.waitFor({state:'detached'});
      assert.deepEqual(errors,[]);assert.deepEqual(outside,[]);
      evidence[variant+'-'+mode]={names,details,external:await page.evaluate(()=>window.actions)};
      if(variant==='after'){
        assert.deepEqual(evidence['after-'+mode],evidence['before-'+mode]);
        assert.ok(fs.readFileSync(path.join(out,'before-'+mode+'.png')).equals(fs.readFileSync(path.join(out,'after-'+mode+'.png'))),'menu pixels changed: '+mode);
      }
      console.log('PASS',variant,mode,'10 report routes, currency/warehouse selection, back, close; no external requests or page errors');
      await context.close();
    }
  }
  fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({base,blob:'58de38bdfe7f6af5fb31386b6cad3f2dcc4f539b',evidence},null,2)+'\n');
} finally {await browser.close();}
