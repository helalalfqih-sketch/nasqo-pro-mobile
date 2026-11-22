import fs from 'node:fs';
import path from 'node:path';
import { chromium } from '@playwright/test';

const out = process.argv[2] || 'android-evidence';
const device = JSON.parse(fs.readFileSync(path.join(out,'first-launch-ui.json'),'utf8'));
const browser=await chromium.launch({channel:'chrome', headless:true});
try {
  const page=await browser.newPage({viewport:{width:device.width,height:device.height},deviceScaleFactor:1,isMobile:true,hasTouch:true,locale:'ar'});
  await page.goto('https://nasqo-pro-erp-1.ai.studio/',{waitUntil:'domcontentloaded',timeout:45000});
  await page.getByRole('button',{name:'فاتورة جديدة',exact:true}).first().waitFor({timeout:45000});
  await page.evaluate(async()=>{
    await document.fonts.ready;
    const images=[...document.images].filter(img=>img.getBoundingClientRect().height && img.getBoundingClientRect().top<innerHeight);
    await Promise.race([Promise.allSettled(images.map(img=>img.decode())),new Promise(resolve=>setTimeout(resolve,5000))]);
  });
  const web=await page.locator('button').evaluateAll(nodes=>nodes.filter(n=>n.offsetWidth&&n.offsetHeight).map(n=>({label:(n.getAttribute('aria-label')||n.innerText||'').trim().replace(/\s+/g,' '),x:Math.round(n.getBoundingClientRect().x),y:Math.round(n.getBoundingClientRect().y)})).filter(n=>n.label));
  const comparable=['فتح القائمة','سند جديد','فاتورة جديدة','حوالة جديدة','كشف حساب','الأصناف','الرئيسية','الإدارة','التقارير','الإعدادات'];
  const difference=comparable.map(label=>{
    const a=device.buttons.find(b=>b.label===label), b=web.find(b=>b.label===label);
    return {label,android:a||null,web:b||null,dx:a&&b?a.x-b.x:null,dy:a&&b?a.y-b.y:null};
  });
  await page.screenshot({path:path.join(out,'live-web.png'),animations:'disabled'});
  const report={url:page.url(),width:device.width,height:device.height,webButtonCount:web.length,androidButtonCount:device.buttons.length,
    matched:difference.filter(b=>b.android&&b.web).length,outOf:comparable.length,difference,web};
  fs.writeFileSync(path.join(out,'comparison.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
  if (report.matched !== comparable.length) throw Error('Required home controls are missing from one of the two views');
} finally { await browser.close(); }
