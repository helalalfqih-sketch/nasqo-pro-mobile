import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { setTimeout as pause } from "node:timers/promises";
import { exerciseForms } from "../react_sqlite/forms.mjs";

// Signed APK, disposable Android emulator, offline React screens, real SQLite.
const apk = process.argv[2];
const evidence = process.argv[3] || "qa-qr-evidence";
const app = "com.indexesstore.nasqo_qa";
const workspaceId = "local-erp-workspace";
fs.mkdirSync(evidence, { recursive: true });
const adb = (...args) => execFileSync("adb", args, {encoding:"utf8", maxBuffer:16*1024*1024});
const shell = (...args) => adb("shell", ...args).trim();
async function until(fn, label, timeout = 25000) {
  const deadline = Date.now() + timeout;
  let last;
  while (Date.now() < deadline) {
    try {const result = await fn(); if(result) return result;} catch(e){last=e;}
    await pause(300);
  }
  throw Error(label + (last ? ": "+last : ""));
}
async function attach() {
  shell("am", "start", "-W", "-n", app+"/.MainActivity");
  const pid = await until(()=>shell("pidof",app), "Android process missing");
  const port = adb("forward","tcp:0","localabstract:webview_devtools_remote_"+pid).trim();
  const page = await until(async () => {
    const pages = await (await fetch("http://127.0.0.1:"+port+"/json/list")).json();
    return pages.find(p=>p.url==="https://appassets.androidplatform.net/react/index.html");
  }, "Packaged React WebView missing");
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject});
  let n=0;const pending=new Map();
  ws.onmessage=({data})=>{
    const msg=JSON.parse(data), wake=pending.get(msg.id);
    if(wake){pending.delete(msg.id);wake(msg);}
  };
  function call(method, params={}) {
    const id=++n;
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{pending.delete(id);reject(Error(method+" timeout"))},18000);
      pending.set(id,msg=>{clearTimeout(timer);if(msg.error)reject(Error(JSON.stringify(msg.error)));else resolve(msg.result)});
      ws.send(JSON.stringify({id,method,params}));
    });
  }
  async function evaluate(expression) {
    const result=await call("Runtime.evaluate",{expression,returnByValue:true,awaitPromise:true});
    if(result.exceptionDetails)throw Error(result.exceptionDetails.text);
    return result.result.value;
  }
  await until(()=>evaluate("Boolean(window.__nasqoHybridReady && document.querySelector('[data-testid=home-bottom-nav]'))"),"React dashboard not ready");
  return {pid,evaluate,call,close(){ws.close();adb("forward","--remove","tcp:"+port)}};
}
function nativeRequest(env) {
  return new Promise((resolve,reject)=>{
    const channel=window.NasqoHome;
    const timer=setTimeout(()=>{channel.removeEventListener("message",onMessage);reject(Error("Native reply timed out"))},12000);
    function onMessage(evt) {
      const result=JSON.parse(evt.data);
      if(result.requestId!==env.requestId)return;
      clearTimeout(timer);channel.removeEventListener("message",onMessage);resolve(result);
    }
    channel.addEventListener("message",onMessage);
    channel.postMessage(JSON.stringify(env));
  });
}
let view;
async function snapshot() {
  const env={protocolVersion:"1.0.0",kind:"request",requestId:randomUUID(),action:"getSnapshot",payload:{workspaceId},timestampMs:Date.now()};
  const result=await view.evaluate("("+nativeRequest.toString()+")("+JSON.stringify(env)+")");
  assert.equal(result.ok,true,JSON.stringify(result.error));
  return result.data;
}
async function control(selector,operation,value,label) {
  function act(selector,operation,value,label) {
    const el=[...document.querySelectorAll(selector)].find(x=>
      (!label || (x.getAttribute("aria-label")||x.textContent).trim()===label) && !x.disabled);
    if(!el)return false;
    if(operation==="click"){el.scrollIntoView({block:"nearest"});el.click();}
    else {
      const proto=el.tagName==="SELECT" ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(proto,"value").set.call(el,value);
      el.dispatchEvent(new Event(el.tagName==="SELECT"?"change":"input",{bubbles:true}));
    }
    return true;
  }
  await until(()=>view.evaluate("("+act.toString()+")("+[selector,operation,value,label].map(v=>JSON.stringify(v??null)).join(",")+")"),"Missing React QR control "+selector);
}
const click=(selector,label)=>control(selector,"click",null,label);
const fill=(selector,value)=>control(selector,"fill",value);
const report={versionCode:10026,offline:true,syntheticOnly:true,steps:[],passed:false};
try {
  assert.equal(shell("getprop","ro.kernel.qemu"),"1","Disposable emulator required");
  assert.equal(shell("pm","list","packages",app),"","Fresh emulator required");
  adb("install",apk);
  shell("cmd","connectivity","airplane-mode","enable");
  shell("svc","wifi","disable");
  shell("svc","data","disable");
  assert.equal(shell("settings","get","global","airplane_mode_on"),"1");
  view=await attach();
  assert.equal(await view.evaluate("Boolean(navigator.mediaDevices?.getUserMedia)"),true,"React cannot request camera");
  const ids=await exerciseForms(view,until,snapshot);
  const baseline=await snapshot();
  const item=baseline.inventory.find(x=>x.id===ids[1]);
  assert(item && item.quantity===13);
  report.steps.push("Real React forms created the synthetic inventory item in SQLite");
  await click("[data-testid=home-qr-scanner-btn]");
  await until(()=>view.evaluate("Boolean(document.querySelector('[data-testid=qr-scanner-modal]'))"),"React QR modal missing");
  await fill('[aria-label="إدخال كود QR أو رمز الصنف"]',item.id);
  await click('[data-testid=qr-lookup-btn]');
  await until(()=>view.evaluate("Boolean(document.querySelector('[data-testid=qr-matched-item]'))"),"Existing item lookup not shown");
  await fill('[aria-label="الكمية المضافة للمخزون"]',"2");
  await click('[data-testid=qr-matched-item] button',"توريد للمخزون");
  await until(()=>view.evaluate("!document.querySelector('[data-testid=qr-scanner-modal]')"),"QR stock receipt did not finish",25000);
  const after=await snapshot();
  assert.equal(after.inventory.find(x=>x.id===item.id).quantity,15,"QR receipt did not add exactly 2");
  assert.equal(after.ledger.length,baseline.ledger.length,"QR receipt must never create ledger entries");
  report.steps.push("QR lookup and explicit restock increased the correct item by 2 without creating a ledger entry");
  view.close();
  shell("am","force-stop",app);
  view=await attach();
  const persisted=await snapshot();
  assert.equal(persisted.inventory.find(x=>x.id===item.id).quantity,15);
  assert.equal(persisted.ledger.length,baseline.ledger.length);
  report.steps.push("Native SQLite quantity and ledger stayed intact after offline app restart");
  report.passed=true;
  console.log("PASS QA QR: React lookup and native SQLite stock receipt persisted once offline");
} catch(error) {
  report.error=String(error.stack||error);
  try {fs.writeFileSync(path.join(evidence,"qr-failure-ui.txt"),await view?.evaluate("document.body.innerText.slice(-3000)") || "");} catch {}
  throw error;
} finally {
  report.cameraPermissionOnPhysicalDeviceVerified=false;
  fs.writeFileSync(path.join(evidence,"qr-android-result.json"),JSON.stringify(report,null,2));
  if(view) view.close();
}
