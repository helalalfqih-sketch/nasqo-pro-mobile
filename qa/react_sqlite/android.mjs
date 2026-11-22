import assert from 'node:assert/strict';
import { exerciseForms } from './forms.mjs';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const apk = process.argv[2];
const evidence = process.argv[3] || 'android-evidence';
const app = 'com.indexesstore.nasqo_qa';
const localUrl = 'https://appassets.androidplatform.net/react/index.html';
const workspaceId = 'local-erp-workspace';
fs.mkdirSync(evidence, { recursive: true });
const adb = (...args) => execFileSync('adb', args, { maxBuffer: 64 * 1024 * 1024 });
const shell = (...args) => adb('shell', ...args).toString().trim();
const save = (name, data) => fs.writeFileSync(path.join(evidence, name), data);
async function until(fn, explanation, limit = 100000) {
  const end = Date.now() + limit;
  let last;
  do {
    try { const value = await fn(); if (value) return value; } catch (e) { last = e; }
    await delay(400);
  } while (Date.now() < end);
  throw Error(explanation + (last ? ' (' + last.message + ')' : ''));
}

async function attach() {
  shell('am', 'start', '-W', '-n', app + '/.MainActivity');
  const pid = await until(() => shell('pidof', app), 'Missing Android process');
  const port = adb('forward', 'tcp:0', 'localabstract:webview_devtools_remote_' + pid).toString().trim();
  const target = await until(async () => {
    const pages = await (await fetch('http://127.0.0.1:' + port + '/json/list')).json();
    return pages.find(p => p.url === localUrl);
  }, 'Packaged offline WebView did not open');
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((ok, fail) => { socket.onopen = ok; socket.onerror = fail; });
  const pending = new Map();
  let sequence = 0;
  socket.onmessage = ({data}) => {
    const msg = JSON.parse(data);
    const wake = pending.get(msg.id);
    if (wake) { pending.delete(msg.id); wake(msg); }
  };
  function call(method, params) {
    const id = ++sequence;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { pending.delete(id); reject(Error(method + ' timed out')); }, 12000);
      pending.set(id, msg => { clearTimeout(timer); if (msg.error) reject(Error(JSON.stringify(msg.error))); else resolve(msg.result); });
      socket.send(JSON.stringify({id, method, params}));
    });
  }
  async function evaluate(expression) {
    const res = await call('Runtime.evaluate', {expression, returnByValue:true, awaitPromise:true});
    if (res.exceptionDetails) throw Error(res.exceptionDetails.exception?.description || res.exceptionDetails.text);
    return res.result.value;
  }
  try {
    await until(() => evaluate("Boolean(window.__nasqoHybridReady && window.NasqoHome && document.querySelector('[data-testid=hybrid-viewport]') && document.querySelectorAll('button').length >= 6)"), 'React dashboard failed to render');
  } catch (e) {
    save('boot-failure.txt', await evaluate("document.body.innerText.slice(0,8000)"));
    throw e;
  }
  return {pid, evaluate, call, close() { socket.close(); adb('forward','--remove','tcp:'+port); }};
}

// Read back the actual WebViewCompat reply for the installed app. This test
// does not replace the host, its database, or the JavaScript transport.
function nativeRequest(envelope) {
  return new Promise((resolve, reject) => {
    const transport = window.NasqoHome;
    const timer = setTimeout(() => { transport.removeEventListener('message', listener); reject(Error('No native reply for '+envelope.action)); }, 8500);
    function listener(event) {
      const reply = JSON.parse(event.data);
      if (reply.requestId !== envelope.requestId) return;
      clearTimeout(timer); transport.removeEventListener('message', listener); resolve(reply);
    }
    transport.addEventListener('message', listener);
    transport.postMessage(JSON.stringify(envelope));
  });
}
function presentation() {
  return {url: location.href, lang:document.documentElement.lang, rtl:getComputedStyle(document.querySelector('[dir=rtl]') || document.body).direction,
    width:innerWidth, height:innerHeight, buttons:[...document.querySelectorAll('button')].filter(n=>n.offsetWidth&&n.offsetHeight)
      .map(n=>({label:(n.getAttribute('aria-label')||n.innerText||'').trim().replace(/\s+/g,' '), x: Math.round(n.getBoundingClientRect().x), y:Math.round(n.getBoundingClientRect().y)})).filter(n=>n.label),
    remoteAssets:performance.getEntriesByType('resource').map(r=>r.name).filter(n=>/^https?:/.test(n)&&new URL(n).origin!==location.origin)};
}
let view;
async function request(action, payload, key, success=true) {
  const env={kind:'request',protocolVersion:'1.0.0',requestId:'qa_'+randomUUID(),action,payload,timestampMs:Date.now(),...(key?{idempotencyKey:key}:{})};
  const res=await view.evaluate('('+nativeRequest.toString()+')('+JSON.stringify(env)+')');
  assert.equal(res.ok,success,JSON.stringify(res.error||{})); return success?res.data:res.error;
}
const post=(action,data,key,ok=true)=>request(action,{workspaceId,payload:data},key,ok);
async function capture(name) {
  const data=await view.evaluate('('+presentation.toString()+')()');
  assert.equal(data.url,localUrl); assert.equal(data.rtl,'rtl'); assert.deepEqual(data.remoteAssets,[]);
  assert(data.buttons.some(b=>b.label.includes('فاتورة جديدة')), 'Home invoice action missing');
  save(name+'-ui.json',JSON.stringify(data,null,2));
  save(name+'-android.png',adb('exec-out','screencap','-p'));
  const screenshot=await view.call('Page.captureScreenshot',{format:'png'});
  save(name+'-webview.png',Buffer.from(screenshot.data,'base64'));
  return data;
}
function stop() {
  view.close();
  shell('am','force-stop',app);
  const ps = shell('ps','-A').split(/\r?\n/);
  assert(ps.every(row => row.trim().split(/\s+/).at(-1) !== app), 'Process survived force-stop');
}
const result={app, exercise:'Production WebViewCompat to Dart and native SQLite', apkSha256:execFileSync('sha256sum',[apk],{encoding:'utf8'}).split(' ')[0], steps:[]};
try {
  // Only run on a new disposable Android emulator, never a developer phone.
  assert([shell('getprop','ro.kernel.qemu'),shell('getprop','ro.boot.qemu')].includes('1'));
  assert.equal(shell('pm','list','packages',app),'', 'Use a fresh test emulator');
  adb('install','-r',apk);
  shell('wm','size','393x852'); shell('wm','density','160');
  shell('cmd','connectivity','airplane-mode','enable');
  shell('svc','wifi','disable'); shell('svc','data','disable');
  assert.equal(shell('settings','get','global','airplane_mode_on'),'1');
  result.androidApi=shell('getprop','ro.build.version.sdk');
  view=await attach();
  result.firstPid=view.pid;
  await capture('first-launch');
  const fresh=await request('getSnapshot',{workspaceId});
  assert.deepEqual([fresh.accounts.length,fresh.ledger.length,fresh.inventory.length],[0,0,0]);
  assert.equal(fresh.capabilities.readOnlyFinancial,false);
  const acc=(await post('saveAccount',{name:'مورد اختبار Android',category:'purchases'},'qa-account')).account;
  const item=(await post('createInventoryItem',{name:'صنف اختبار Android',warehouseId:'wh_1',unit:'حبة',quantity:10,avgCost:2},'qa-stock')).item;
  const invoice={accountId:acc.id,kind:'invoice',direction:'credit',payment:'credit',currency:'ريال',amount:15,lines:[{inventoryItemId:item.id,quantity:3,price:5}],warehouseId:'wh_1',documentNumber:'QA-1'};
  const voucher={accountId:acc.id,kind:'voucher',direction:'debit',payment:'cash',amount:4,currency:'ريال'};
  const inv=await Promise.all([post('createLedgerEntry',invoice,'qa-invoice'),post('createLedgerEntry',invoice,'qa-invoice')]);
  assert.deepEqual(inv.map(e=>e.postingReceipt.replayed).sort(),[false,true]);
  assert.equal(inv[0].entry.id,inv[1].entry.id);
  const v=await post('createLedgerEntry',voucher,'qa-voucher');
  result.steps.push('Posted account, item, invoice and voucher offline; simultaneous invoice saved once');
  stop();
  const firstDb=JSON.parse(execFileSync('python3',['qa/react_sqlite/read_device_db.py',acc.id,item.id,inv[0].entry.id,v.entry.id],{encoding:'utf8'}));
  result.sqliteBeforeRestart=firstDb;
  view=await attach();
  assert.notEqual(view.pid,result.firstPid);
  result.secondPid=view.pid;
  assert.equal(shell('settings','get','global','airplane_mode_on'),'1');
  await capture('after-restart');
  const recovered=await request('getSnapshot',{workspaceId});
  assert.equal(recovered.accounts[0].id,acc.id); assert.equal(recovered.inventory[0].quantity,13);
  assert.deepEqual(recovered.ledger.map(e=>e.id).sort(),[inv[0].entry.id,v.entry.id].sort());
  assert.equal((await post('createLedgerEntry',invoice,'qa-invoice')).postingReceipt.replayed,true);
  assert.equal((await post('createLedgerEntry',voucher,'qa-voucher')).postingReceipt.replayed,true);
  const conflict=await post('createLedgerEntry',{...voucher,amount:8},'qa-voucher',false);
  assert.equal(conflict.code,'VALIDATION_ERROR');
  stop();
  result.sqliteAfterReplay=JSON.parse(execFileSync('python3',['qa/react_sqlite/read_device_db.py',acc.id,item.id,inv[0].entry.id,v.entry.id],{encoding:'utf8'}));
  assert.deepEqual(result.sqliteAfterReplay,firstDb);
  result.steps.push('Offline process restart, readback, repeated and conflicting postings; database identical');
  view=await attach();
  const ids=await exerciseForms(view,until,()=>request('getSnapshot',{workspaceId}));
  stop();
  result.formsDatabase=JSON.parse(execFileSync('python3',['qa/react_sqlite/read_device_db.py',...ids,'forms'],{encoding:'utf8'}));
  view=await attach();
  const final=await request('getSnapshot',{workspaceId});
  assert.equal(final.accounts.length,2); assert.equal(final.ledger.length,4);
  assert.equal(final.inventory.find(i=>i.id===ids[1]).quantity,13);
  assert(final.ledger.some(e=>e.id===ids[2]) && final.ledger.some(e=>e.id===ids[3]));
  result.steps.push('Submitted the four real React forms, force-stopped the APK and verified their native rows from a new Android process');
  stop();
  result.passed=true;
} catch(e) {
  result.passed=false;result.error=String(e.stack||e);
  try { save('failure-android.png',adb('exec-out','screencap','-p')); } catch {}
  if (view) try { save('failure-ui.txt',await view.evaluate('document.body.innerText.slice(-10000)')); view.close(); } catch {}
  throw e;
} finally {
  save('device.json',JSON.stringify(result,null,2));
  console.log(JSON.stringify(result,null,2));
}
