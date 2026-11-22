import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {chromium} from '@playwright/test';
import {states,measure} from './states.mjs';

const root='android-evidence';
const android=JSON.parse(fs.readFileSync(path.join(root,'release-navigation.json')));
const browser=await chromium.launch({channel:'chrome',headless:true});
const page=await browser.newPage({viewport:{width:android[0].width,height:android[0].height},
  deviceScaleFactor:1,isMobile:true,hasTouch:true,locale:'ar'});
const results=[];
try {
  for(const state of states){
    const native=android.find(s=>s.name===state.name);
    assert(native,state.name+' is missing on the emulator');
    await page.goto('https://nasqo-pro-erp-1.ai.studio/',{waitUntil:'domcontentloaded'});
    await page.getByRole('button',{name:'فاتورة جديدة',exact:true}).first().waitFor({timeout:45000});
    for(const step of state.path){
      const node=typeof step==='string'?page.locator(step).first():
        page.getByRole(step.selector==='button'?'button':'menuitem',{name:step.label,exact:true}).first();
      await node.click({timeout:9000});
    }
    await page.locator(state.screen).first().waitFor({timeout:12000});
    await page.evaluate(()=>document.fonts.ready);
    await page.screenshot({path:path.join(root,state.name+'-reference.png'),animations:'disabled'});
    const reference=await page.evaluate(measure,state.screen);
    assert(reference,state.name+' missing on reference');
    const delta=(a,b)=>({x:a.x-b.x,y:a.y-b.y,width:a.width-b.width,height:a.height-b.height});
    const result={name:state.name,referenceHeaders:reference.headers.length,androidHeaders:native.headers.length,
      referenceNav:reference.navBars.length,androidNav:native.navBars.length,
      screenDelta:delta(native.screen,reference.screen),buttonsInBoth:reference.labels.filter(l=>native.labels.includes(l)).length,
      referenceButtons:reference.labels.length,androidButtons:native.labels.length};
    results.push(result);
    fs.writeFileSync(path.join(root,'route-comparison.json'),JSON.stringify(results,null,2));
    assert.equal(native.navBars.length,reference.navBars.length,state.name+' bottom bar mismatch');
    assert.equal(native.headers.length,reference.headers.length,state.name+' toolbar mismatch');
  }
} finally { await browser.close(); }
