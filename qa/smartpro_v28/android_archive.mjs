import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {createHash} from "node:crypto";
import { execFileSync } from "node:child_process";
import { setTimeout as pause } from "node:timers/promises";

// Real signed Release, disposable emulator and Android SAF picker test.
// Data comes from a synthetic NASQO Web JSON export; no user data is uploaded.
const apk = process.argv[2];
const evidence = process.argv[3] || "qa-native-import-evidence";
const app = "com.indexesstore.nasqo_qa";
const workspace = "local-erp-workspace";
const fileName = "smartpro-v28-synthetic.back";
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

assert.equal(shell("getprop", "ro.kernel.qemu"), "1", "Disposable emulator required");
assert.equal(shell("pm", "list", "packages", app), "", "Emulator must be fresh");
const fixturePath = path.resolve(evidence, fileName);
if (!process.argv[4]) throw Error("Synthetic SmartPro v28 fixture path required.");
fs.copyFileSync(process.argv[4],fixturePath);
const sourceSha = createHash("sha256").update(fs.readFileSync(fixturePath)).digest("hex");
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
  const pickerStartedAt = Date.now();
  await click(view,"[data-testid=native-web-backup-pick]");
  stage = "picker";
  await selectThroughAndroidPicker();
  console.log("SMARTPRO_PICKER_ELAPSED_MS", Date.now() - pickerStartedAt);
  stage = "historical-preview";
  await until(() => view.evaluate(
    "Boolean(document.querySelector('[data-testid=smartpro-v28-historical-preview]'))"),
    "SmartPro v28 read-only archive preview missing", 240000);
  const previewText = await view.evaluate(
    "document.querySelector('[data-testid=smartpro-v28-historical-preview]').innerText");
  assert(previewText.includes("SmartPro v28"), "Incorrect source version");
  assert(previewText.includes("26,001") || previewText.includes("26001"),
         "All synthetic business records must be counted");
  assert(previewText.includes(sourceSha), "Native archive SHA differs from original file");
  assert.equal(await view.evaluate(
    "Boolean(document.querySelector('[data-testid=native-web-backup-confirm]'))"),
    false, "Unreconciled legacy export must never expose financial restore");
  stage = "save-read-only-archive";
  await click(view,"[data-testid=smartpro-save-archive]");
  await until(() => view.evaluate(
    "Boolean(document.querySelector('select option[value=customers]'))"),
    "Archived customers table missing from React paginator", 60000);
  const tables = await view.evaluate(
    "document.querySelector('select').querySelectorAll('option').length");
  assert.equal(tables,23);
  const originalPage = await until(() => view.evaluate(
    "(() => {const table=document.querySelector('.full-sqlite-import-modal table');return table?.querySelectorAll('tbody tr').length || 0})()"),
    "Legacy record page not rendered", 30000);
  assert(originalPage>0 && originalPage<=30);
  const after = await readSnapshot(view);
  assert.deepEqual(
    [after.accounts.length,after.ledger.length,after.inventory.length],
    [before.accounts.length,before.ledger.length,before.inventory.length],
    "Historical archive must not create operational financial rows");
  const png = execFileSync("adb",["exec-out","screencap","-p"]);
  fs.writeFileSync(path.join(evidence,"smartpro-v28-archive-android.png"),png);
  stage = "cold-reopen";
  view.close();
  adb("shell","am","force-stop",app);
  view=await attach();
  const reopened=await readSnapshot(view);
  assert.deepEqual(
    [reopened.accounts.length,reopened.ledger.length,reopened.inventory.length],
    [before.accounts.length,before.ledger.length,before.inventory.length]);
  await click(view,"[data-testid=home-nav-profile]");
  await click(view,"[data-testid=settings-tab-database]");
  await click(view,"[data-testid=settings-restore-backup-btn]");
  await until(() => view.evaluate(
    "Boolean(document.querySelector('.full-sqlite-import-modal button'))"),
    "React archive data center missing after cold restart", 20000);
  const archiveButton=await until(() => view.evaluate(
    "(() => {const b=[...document.querySelectorAll('.full-sqlite-import-modal button')].find(x=>x.textContent?.includes('فتح أرشيف'));if(!b)return false;b.click();return true})()"),
    "Saved SmartPro archive missing after cold reopen",30000);
  assert(archiveButton);
  await until(() => view.evaluate(
    "Boolean(document.querySelector('select option[value=customers]'))"),
    "Saved historical customers table not visible after reopening");
  const report={
    passed:true,
    syntheticOnly:true,
    engine:"Android signed Release API35 airplane mode",
    schemaVersion:28,
    sourceSha256:sourceSha,
    selectedUsingAndroidSaf:true,
    archivedTables:tables,
    expectedBusinessRows:26001,
    recordPagesAvailable:true,
    operationalRecordsAdded:0,
    retainedAfterRestart:true,
    financialPostingAllowed:false,
  };
  fs.writeFileSync(path.join(evidence,"smartpro-v28-archive-qa.json"),JSON.stringify(report,null,2));
  console.log("PASS SmartPro v28: original archive preserved, 23 tables paginated, no financial posting, offline cold reopen");
} catch(error) {
  console.error("Native import test failed at", stage, error);
  // CI uses fabricated records only. Capture minimal UI state to distinguish
  // a native picker/bridge failure from a React rendering or timing failure.
  try {
    const diag = await view.evaluate(`(() => {
      const modal = document.querySelector(".full-sqlite-import-modal");
      const text = modal?.innerText || "";
      return {
        modalOpen: Boolean(modal),
        pickerControlVisible: Boolean(modal?.querySelector("[data-testid=native-web-backup-pick]")),
        historicalPreview: Boolean(modal?.querySelector("[data-testid=smartpro-v28-historical-preview]")),
        normalPreview: Boolean(modal?.querySelector("[data-testid=native-web-backup-preview]")),
        busy: Boolean(modal?.querySelector("[data-testid=native-web-backup-pick]")?.disabled),
        uiDiagnosticLines: text.split("\\n").map(x => x.trim()).filter(x =>
          /تعذّر|فشل|انتهت مهلة|خطأ|غير مدعوم|SQLite|SmartPro|المعاينة/.test(x)).slice(0, 7),
      };
    })()`);
    fs.writeFileSync(path.join(evidence,"failure-ui-diagnostics.json"),JSON.stringify(diag,null,2));
    console.error("SMARTPRO_UI_DIAGNOSTICS", JSON.stringify(diag));
    fs.writeFileSync(path.join(evidence,"failure-ui.png"),
      execFileSync("adb", ["exec-out","screencap","-p"], {maxBuffer: 16 * 1024 * 1024}));
  } catch (diagError) {
    console.error("Unable to capture SmartPro UI diagnostics", String(diagError));
  }
  fs.writeFileSync(path.join(evidence,"failure-stage.txt"),stage+"\\n"+String(error));
  throw error;
} finally {
  view.close();
}
