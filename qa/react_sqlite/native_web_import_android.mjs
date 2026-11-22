import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { setTimeout as pause } from "node:timers/promises";

// Real signed Release, disposable emulator and Android SAF picker test.
// Data comes from a synthetic NASQO Web JSON export; no user data is uploaded.
const apk = process.argv[2];
const evidence = process.argv[3] || "qa-native-import-evidence";
const app = "com.indexesstore.nasqo_qa";
const workspace = "local-erp-workspace";
const fileName = "nasqo-web-qa.json";
fs.mkdirSync(evidence, { recursive: true });
const adb = (...args) => execFileSync("adb", args, { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
const shell = (...args) => adb("shell", ...args).trim();

async function until(work, label, ms = 80000) {
  const deadline = Date.now() + ms;
  let last;
  while (Date.now() < deadline) {
    try { const result = await work(); if (result) return result; }
    catch (error) { last = error; }
    await pause(450);
  }
  throw Error(label + (last ? ": " + String(last) : ""));
}

function webXmlNodes() {
  try {
    adb("shell", "uiautomator", "dump", "/sdcard/nasqo-picker-ui.xml");
    const xml = adb("exec-out", "cat", "/sdcard/nasqo-picker-ui.xml");
    return [...xml.matchAll(/<node\s+[^>]*\/>/g)].map(([record]) => {
      const prop = (key) => record.match(new RegExp(key + '="([^"]*)"'))?.[1] || "";
      return { text: prop("text"), desc: prop("content-desc"), bounds: prop("bounds") };
    });
  } catch { return []; }
}

function tapNode(node) {
  const parts = [...node.bounds.matchAll(/\d+/g)].map(x => Number(x[0]));
  if (parts.length !== 4) return false;
  adb("shell", "input", "tap", String(Math.round((parts[0] + parts[2]) / 2)),
      String(Math.round((parts[1] + parts[3]) / 2)));
  return true;
}

async function selectThroughAndroidPicker() {
  let selectedDownloads = false;
  let openedRoots = false;
  await until(async () => {
    const nodes = webXmlNodes();
    const target = nodes.find(n => (n.text + " " + n.desc).includes(fileName));
    if (target && tapNode(target)) return true;
    const roots = nodes.find(n =>
      /^(Show roots|عرض الجذور|Navigate up|Open navigation drawer)$/i.test(n.desc));
    if (roots && !openedRoots) {
      openedRoots = tapNode(roots); return false;
    }
    const downloads = nodes.find(n => /^(Downloads|Download|التنزيلات|تنزيلات)$/i.test(n.text));
    if (downloads && !selectedDownloads) {
      selectedDownloads = tapNode(downloads); return false;
    }
    return false;
  }, "Android system picker did not select the local backup file", 85000);
}

async function attach() {
  adb("shell", "am", "start", "-W", "-n", app + "/.MainActivity");
  const pid = await until(() => shell("pidof", app), "Android process did not start", 30000);
  const port = adb("forward", "tcp:0", "localabstract:webview_devtools_remote_" + pid).trim();
  const target = await until(async () => {
    const pages = await (await fetch("http://127.0.0.1:" + port + "/json/list")).json();
    return pages.find(p => p.url === "https://appassets.androidplatform.net/react/index.html");
  }, "Packaged React WebView did not load", 35000);
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((ok, fail) => { socket.onopen = ok; socket.onerror = fail; });
  const pending = new Map();
  let sequence = 0;
  socket.onmessage = ({data}) => {
    const msg = JSON.parse(data);
    const cb = pending.get(msg.id);
    if (cb) { pending.delete(msg.id); cb(msg); }
  };
  function call(method, params = {}) {
    const id = ++sequence;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { pending.delete(id); reject(Error(method + " timeout")); }, 30000);
      pending.set(id, message => {
        clearTimeout(timer);
        if (message.error) reject(Error(JSON.stringify(message.error)));
        else resolve(message.result);
      });
      socket.send(JSON.stringify({id, method, params}));
    });
  }
  async function evaluate(expression) {
    const result = await call("Runtime.evaluate", {expression, returnByValue:true, awaitPromise:true});
    if (result.exceptionDetails) throw Error(JSON.stringify(result.exceptionDetails));
    return result.result.value;
  }
  await until(() => evaluate("Boolean(window.__nasqoHybridReady && document.querySelector('[data-testid=home-bottom-nav]'))"),
              "React dashboard not ready", 40000);
  return {evaluate, call, close() { socket.close(); adb("forward","--remove","tcp:"+port); }};
}

async function click(view, selector) {
  await until(() => view.evaluate(
    "(() => {const el=document.querySelector(" + JSON.stringify(selector) +
    ");if (!el || !el.offsetWidth || el.disabled) return false;el.click();return true})()"),
    "Missing React control " + selector, 14000);
}

async function readSnapshot(view) {
  const payload = {
    protocolVersion: "1.0.0", kind: "request", action: "getSnapshot",
    requestId: "qa_snapshot_" + Date.now(), timestampMs: Date.now(),
    payload: {workspaceId: workspace, forceRefresh:true},
  };
  const expression = "(async () => new Promise((resolve,reject) => {" +
    "const env="+ JSON.stringify(payload) +";" +
    "const timeout=setTimeout(()=>reject(Error('No native reply')),12000);" +
    "function callback(event){const v=JSON.parse(event.data);" +
    "if(v.requestId!==env.requestId)return;" +
    "clearTimeout(timeout);window.NasqoHome.removeEventListener('message',callback);resolve(v)}" +
    "window.NasqoHome.addEventListener('message',callback);" +
    "window.NasqoHome.postMessage(JSON.stringify(env))" +
    "}))()";
  const result = await view.evaluate(expression);
  assert.equal(result.ok, true, JSON.stringify(result.error || {}));
  return result.data;
}

const exportPayload = {
  format: "nasqo-pro-erp-backup",
  version: 2,
  workspace: {companyName: "شركة تجربة استيراد الويب"},
  accountGroups: [{id:17,legacyId:7,name:"مجموعة العملاء"}],
  currencies: [{code:"USD",name:"الدولار"}],
  accounts: [{
    id:"web-qa-customer",groupId:17,name:"حساب اختبار الاستيراد",category:"clients",
    currency:"USD",creditLimit:500,isCashAccount:false,openingBalance:20,
    openingDirection:"debit",codeNumber:1
  }],
  warehouses: [{id:"w1",name:"المخزن الرئيسي",details:"",isDefault:true}],
  inventory: [{id:"web-qa-item",name:"صنف الويب",unit:"حبة",warehouseId:"w1",quantity:7,avgCost:15}],
  ledger: [{
    id:"web-qa-invoice",accountId:"web-qa-customer",accountName:"حساب اختبار الاستيراد",
    kind:"invoice",typeLabel:"فاتورة بيع",payment:"credit",direction:"debit",amount:30,
    currency:"USD",exchangeRate:3.75,entryNumber:11,deleted:false,entryDate:"2026-11-22",
    warehouseId:"w1",warehouseName:"المخزن الرئيسي",
    lines:[{inventoryItemId:"web-qa-item",itemName:"صنف الويب",unit:"حبة",quantity:2,price:15}]
  },{
    id:"web-qa-voucher",accountId:"web-qa-customer",accountName:"حساب اختبار الاستيراد",
    kind:"voucher",typeLabel:"سند قبض",payment:"cash",direction:"credit",amount:5,
    currency:"USD",exchangeRate:1,entryNumber:12,deleted:false,entryDate:"2026-11-22",
    warehouseId:"w1",warehouseName:"المخزن الرئيسي"
  }]
};

assert.equal(shell("getprop", "ro.kernel.qemu"), "1", "Disposable emulator required");
assert.equal(shell("pm", "list", "packages", app), "", "Emulator must be fresh");
const fixturePath = path.resolve(evidence, fileName);
fs.writeFileSync(fixturePath, JSON.stringify(exportPayload));
adb("push", fixturePath, "/sdcard/Download/" + fileName);
adb("shell", "am", "broadcast", "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE",
    "-d", "file:///sdcard/Download/" + fileName);
adb("install", apk);
shell("cmd","connectivity","airplane-mode","enable");
shell("svc","wifi","disable");
shell("svc","data","disable");
assert.equal(shell("settings","get","global","airplane_mode_on"),"1");
let view = await attach();
let stage = "start";
try {
  const before = await readSnapshot(view);
  assert.equal(before.accounts.length, 0);
  assert.equal(before.ledger.length, 0);
  stage = "settings";
  await click(view, "[data-testid=home-nav-profile]");
  await click(view,"[data-testid=settings-tab-database]");
  await click(view,"[data-testid=settings-restore-backup-btn]");
  await click(view,"[data-testid=native-web-backup-pick]");
  stage = "picker";
  await selectThroughAndroidPicker();
  stage = "preview";
  await until(() => view.evaluate("Boolean(document.querySelector('[data-testid=native-web-backup-preview]'))"),
              "Native SQLite preview not returned", 60000);
  const previewText = await view.evaluate(
    "document.querySelector('[data-testid=native-web-backup-preview]').innerText");
  assert(previewText.includes("الحسابات") && previewText.includes("الفواتير") &&
         previewText.includes("السندات") && previewText.includes("المخازن"),
         "Native preview does not include required counts");
  await click(view,"[data-testid=native-web-backup-review-consent]");
  await click(view,"[data-testid=native-web-backup-confirm]");
  stage = "restore";
  await until(() => view.evaluate(
    "Boolean(document.body.innerText.includes('اكتملت الاستعادة والتحقق من قاعدة SQLite'))"),
    "Confirmed native restore did not complete", 60000);
  const after = await readSnapshot(view);
  assert.equal(after.accounts.length,1);
  assert.equal(after.ledger.filter(e=>e.kind==="invoice").length,1);
  assert.equal(after.ledger.filter(e=>e.kind==="voucher").length,1);
  assert.equal(after.inventory.length,1);
  assert.equal(after.inventory[0].quantity,7);
  const png = execFileSync("adb", ["exec-out","screencap","-p"]);
  fs.writeFileSync(path.join(evidence, "after-website-restore-android.png"),png);
  view.close();
  adb("shell","am","force-stop",app);
  view=await attach();
  const reopened = await readSnapshot(view);
  assert.deepEqual(
    [reopened.accounts.length,reopened.ledger.length,reopened.inventory[0].quantity],
    [1,2,7]);
  const report = {
    passed:true, environment:"Release API35 airplane mode",
    selectedWithAndroidSaf:true, previewWasNativeAndCountOnly:true,
    sqliteAccountCount:reopened.accounts.length,
    invoiceCount:reopened.ledger.filter(e=>e.kind==="invoice").length,
    voucherCount:reopened.ledger.filter(e=>e.kind==="voucher").length,
    inventoryCount:reopened.inventory.length,
    persistedOnColdOpen:true,
  };
  fs.writeFileSync(path.join(evidence,"native-web-restore.json"),JSON.stringify(report,null,2));
  console.log("PASS: native Android file picker + JSON Web backup + explicit React consent + SQLite cold reopen offline");
} catch(error) {
  console.error("Native import test failed at", stage, error);
  fs.writeFileSync(path.join(evidence,"failure-stage.txt"),stage+"\n"+String(error));
  throw error;
} finally {
  view.close();
}
