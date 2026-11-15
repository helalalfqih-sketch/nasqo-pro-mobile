/**
 * Real Chromium mobile-emulation QA against the deployed NASQO UI.
 * All Odoo JSON-RPC calls are intercepted with synthetic fixtures; no
 * real account, database, record or external service is modified.
 * Run with LD_LIBRARY_PATH=/home/chatgpt-admin/nasqo-mobile-ops/playwright-libs/root/usr/lib/x86_64-linux-gnu.
 */
import { chromium, devices } from "@playwright/test";
import { mkdirSync, existsSync, readFileSync } from "node:fs";
import { resolve, extname } from "node:path";

const APP = "https://erp.indexesstore.com/nasqo-mobile/";
const OUTPUT = "/home/chatgpt-admin/nasqo-mobile-ops/mobile-browser-qa";
mkdirSync(OUTPUT, { recursive: true });
let browser;
const results = [];
const errors = [];
const calls = [];
const assert = (condition, message) => { if (!condition) throw Error(message); };
const run = async (label, task) => {
  try {
    await task();
    results.push({ label, status: "PASS" });
    console.log("PASS", label);
  } catch (e) {
    results.push({ label, status: "FAIL", error: String(e).slice(0, 450) });
    console.log("FAIL", label, String(e).slice(0, 450));
  }
};

const today = new Date();
const iso = d => [d.getFullYear(), String(d.getMonth()+1).padStart(2,"0"), String(d.getDate()).padStart(2,"0")].join("-");
const due = new Date(today); due.setDate(today.getDate()+3);
const lastWeek = new Date(today); lastWeek.setDate(today.getDate()-3);
const rows = {
  "res.partner": [
    {id:41,name:"عميل اختبار أ",phone:"+967700000001"},
    {id:42,name:"مورد اختبار ب",phone:"+967700000002"},
  ],
  "stock.warehouse": [{id:3,name:"مخزن تجريبي",company_id:[1,"اختبار"]}],
  "account.move": [
    {id:90,name:"INV-TEST-90",partner_id:[41,"عميل اختبار أ"],move_type:"out_invoice",
      invoice_date:iso(today),invoice_date_due:iso(due),amount_total:100,
      amount_residual:100,state:"posted",currency_id:[1,"YER"]},
    {id:89,name:"INV-TEST-89",partner_id:[42,"مورد اختبار ب"],move_type:"in_invoice",
      invoice_date:iso(lastWeek),invoice_date_due:iso(due),amount_total:40,
      amount_residual:40,state:"posted",currency_id:[1,"YER"]},
  ],
  "stock.warehouse.orderpoint": [
    {id:71,product_id:[11,"صنف تجريبي منخفض"],product_min_qty:10,
      qty_on_hand:2,location_id:[3,"مخزن تجريبي"],product_uom:[1,"قطعة"],
      write_date:iso(today)+" 11:00:00"},
  ],
  "mail.message": [
    {id:801,subject:"تنبيه اختبار للنظام",date:iso(today)+" 10:00:00",message_type:"notification"},
  ],
  "product.product": [
    {id:11,display_name:"منتج QR تجريبي",barcode:"TEST-QR-001",default_code:"TEST-QR-001"},
  ],
};
const response = result => JSON.stringify({jsonrpc:"2.0",id:1,result});
const allowed = new Set(["search_read","search_count","get_session_info"]);

try {
  browser = await chromium.launch({
    headless:true,
    args:["--no-sandbox","--use-fake-device-for-media-stream","--use-fake-ui-for-media-stream"],
  });
  const context = await browser.newContext({
    ...devices[process.env.NASQO_QA_DEVICE || "Pixel 7"], ignoreHTTPSErrors:true,
    permissions:["camera"],
    colorScheme:"light",
  });
  await context.addInitScript(() => {
    window.__mobileTestNotifications = [];
    window.__mobileTestVibrations = [];
    Object.defineProperty(navigator, "vibrate", {
      configurable:true, value(pattern) { window.__mobileTestVibrations.push(pattern); return true; },
    });
    Object.defineProperty(window, "Notification", {
      configurable:true,
      value:class {
        static permission = "granted";
        static async requestPermission() { return "granted"; }
        constructor(title, options) { window.__mobileTestNotifications.push({title,body:options?.body}); }
      },
    });
  });
  const page = await context.newPage();
  if (process.env.NASQO_QA_ASSETS_DIR) {
    const root = resolve(process.env.NASQO_QA_ASSETS_DIR);
    await page.route("https://erp.indexesstore.com/nasqo-mobile/**",async route => {
      const uri = new URL(route.request().url()).pathname;
      const relative = uri === "/nasqo-mobile/" ? "index.html" : uri.slice("/nasqo-mobile/".length);
      const local = resolve(root, relative);
      if (local !== root && !local.startsWith(root+"/")) return route.abort();
      if (!existsSync(local)) return route.fulfill({status:404,body:"QA asset not found"});
      const type = {".html":"text/html",".js":"text/javascript",".css":"text/css",
        ".woff2":"font/woff2",".woff":"font/woff"}[extname(local)] || "application/octet-stream";
      return route.fulfill({status:200,body:readFileSync(local),contentType:type});
    });
  }
  page.on("pageerror",error=>errors.push({type:"pageerror",message:String(error).slice(0,250)}));
  page.on("console",m=>{if(m.type()==="error") errors.push({type:"console",message:m.text().slice(0,250)});});
  await page.route("https://erp.indexesstore.com/web/**",async route=>{
    const req = route.request();
    const url = new URL(req.url());
    if(req.method()!=="POST") return route.fulfill({status:403,body:"forbidden in fixture"});
    let body;
    try {body=JSON.parse(req.postData()||"{}");}catch {return route.fulfill({status:400,body:"bad rpc"});}
    const method = body.params?.method || (url.pathname.includes("/get_session_info")?"get_session_info":"");
    const model = body.params?.model;
    calls.push({method,model,pathname:url.pathname});
    if(!allowed.has(method)) return route.fulfill({status:403,contentType:"application/json",body:response(null)});
    let result;
    if(method==="get_session_info") result={uid:91001};
    else if(!Object.prototype.hasOwnProperty.call(rows,model)) {
      return route.fulfill({status:200,contentType:"application/json",body:response([])});
    } else if(method==="search_count") result=rows[model].length;
    else {
      result=rows[model];
      if(model==="account.move"){
        const domain=body.params?.args?.[0]??[];
        const invoiceTypes=domain.flat().map(String).join(":");
        if(invoiceTypes.includes("out_refund")) result=result.filter(r=>r.move_type==="out_invoice");
      }
      if(model==="product.product") result=result.filter(r=>r.barcode==="TEST-QR-001");
      const limit=body.params?.kwargs?.limit??100;
      const offset=body.params?.kwargs?.offset??0;
      result=result.slice(offset,offset+limit);
    }
    await route.fulfill({status:200,contentType:"application/json",body:response(result)});
  });

  await run("Dashboard loads at mobile viewport without simulator chrome", async ()=>{
    await page.goto(APP,{waitUntil:"domcontentloaded",timeout:30000});
    await page.locator('[data-testid="nasqo-dashboard-insights"]').waitFor({timeout:20000});
    assert(await page.locator("body").getAttribute("data-nasqo-color-mode")==="light","default theme not light");
    assert(await page.locator(".device-picker-trigger").isHidden(),"device picker remains visible");
    assert(await page.locator(".phone-bezel").isHidden(),"phone bezel remains visible");
    assert(await page.locator(".nasqo-insights").isVisible(),"dashboard not visible");
    assert(await page.locator("body").evaluate(e=>e.scrollWidth<=window.innerWidth+2),"horizontal viewport overflow");
    await page.screenshot({path:OUTPUT+"/mobile-initial.png",fullPage:false});
  });

  await run("Native touchscreen scrolls dashboard without swallowing controls",async()=>{
    const scroller=page.locator(".nasqo-native-scroll .mobile-scroll");
    assert(await scroller.count()===1,"production native scroll container missing");
    await scroller.evaluate(el=>{el.scrollTop=0;});
    const box=await scroller.boundingBox();
    assert(box,"scroll container invisible");
    const session=await context.newCDPSession(page);
    const x=box.x+box.width/2;
    const from=box.y+box.height*.7;
    const to=box.y+box.height*.25;
    try {
      await session.send("Input.dispatchTouchEvent",{type:"touchStart",touchPoints:[{x,y:from}]});
      for(let n=1;n<=12;n++){
        await session.send("Input.dispatchTouchEvent",{type:"touchMove",touchPoints:[{x,y:from+(to-from)*n/12}]});
        await page.waitForTimeout(16);
      }
      await session.send("Input.dispatchTouchEvent",{type:"touchEnd",touchPoints:[]});
      await page.waitForTimeout(180);
    } finally {await session.detach();}
    const offset=await scroller.evaluate(el=>el.scrollTop);
    assert(offset>40,"native touch scrolling did not move content: "+offset);
    await scroller.evaluate(el=>{el.scrollTop=0;});
  });

  await run("Live mocked Odoo alerts and real-date low-stock widgets render", async()=>{
    await page.locator(".nasqo-notifications li").first().waitFor({timeout:18000});
    assert(await page.getByText("تنبيه اختبار للنظام").count()>0,"Odoo system message absent");
    assert(await page.getByText("صنف تجريبي منخفض").count()>0,"low stock product absent");
    assert(await page.getByText("استحقاق فاتورة عميل").count()>0,"due customer invoice absent");
    assert(await page.getByText("استحقاق فاتورة مورد").count()>0,"due vendor bill absent");
  });

  await run("Theme switch dark, light, and system is live and restores across reloads",async()=>{
    await page.locator('#nasqo-theme-mode').selectOption("dark");
    assert(await page.locator("body").getAttribute("data-nasqo-color-mode")==="dark","dark mode did not apply");
    await page.screenshot({path:OUTPUT+"/mobile-dark.png",fullPage:false});
    await page.locator('#nasqo-theme-mode').selectOption("light");
    assert(await page.locator("body").getAttribute("data-nasqo-color-mode")==="light","light mode did not apply");
    await page.locator('#nasqo-theme-mode').selectOption("system");
    assert(await page.locator("body").getAttribute("data-nasqo-color-mode")==="light","system mode did not follow light context");
    await page.locator('#nasqo-theme-mode').selectOption("dark");
    await page.reload({waitUntil:"domcontentloaded"});
    await page.locator('[data-testid="nasqo-dashboard-insights"]').waitFor();
    assert(await page.locator("body").getAttribute("data-nasqo-color-mode")==="dark","theme not persisted after reload");
  });

  await run("Primary color updates CSS token and meta theme-color",async()=>{
    await page.locator("#nasqo-brand-color").fill("#8040a0");
    await page.waitForTimeout(100);
    const {primary,meta} = await page.evaluate(()=>({
      primary: document.body.style.getPropertyValue("--nasqo-blue"),
      meta: document.querySelector('meta[name="theme-color"]')?.getAttribute("content"),
    }));
    assert(primary==="#8040a0"&&meta==="#8040a0",JSON.stringify({primary,meta}));
    await page.getByRole("button",{name:"الافتراضي"}).click();
    assert(await page.locator('meta[name="theme-color"]').getAttribute("content")==="#0b5ca8","default color did not reset");
  });

  await run("Favorites pin/unpin persists and are user-scoped",async()=>{
    const select=page.getByRole("combobox",{name:"اختيار مهمة للمفضلة"});
    await select.selectOption("report:vendorBills");
    await page.getByRole("button",{name:"تثبيت",exact:true}).click();
    assert(await page.locator(".nasqo-favorites-row").getByRole("button",{name:"فواتير الموردين",exact:true}).count()===1,"favorite not pinned");
    await page.reload({waitUntil:"domcontentloaded"});
    await page.locator('[data-testid="nasqo-dashboard-insights"]').waitFor();
    assert(await page.locator(".nasqo-favorites-row").getByRole("button",{name:"فواتير الموردين",exact:true}).count()===1,"favorite not persisted");
    await page.getByRole("button",{name:"إزالة فواتير الموردين من المفضلة"}).click();
    assert(await page.locator(".nasqo-favorites-row").getByRole("button",{name:"فواتير الموردين",exact:true}).count()===0,"favorite not removed");
  });

  await run("Drag reorders summaries without breaking Odoo data",async()=>{
    const locator=page.locator('.nasqo-sort-tile[data-id="summary:sales"] .nasqo-sort-handle');
    const destination=page.locator('.nasqo-sort-tile[data-id="summary:invoices"]');
    await locator.scrollIntoViewIfNeeded();
    const start=await locator.boundingBox(),end=await destination.boundingBox();
    assert(start && end,"missing DnD nodes");
    await page.mouse.move(start.x+start.width/2,start.y+start.height/2);
    await page.mouse.down();
    await page.mouse.move(end.x+end.width/2,end.y+end.height/2,{steps:15});
    await page.mouse.up();
    await page.waitForTimeout(350);
    const order=await page.locator('[data-zone="summary"]').evaluateAll(nodes=>nodes.map(e=>e.dataset.id));
    assert(order[0]!=="summary:sales","DND order unchanged: "+order.join(","));
    assert(await page.getByText("صنف تجريبي منخفض").count()>0,"lost live data after reorder");
  });

  await run("Real emulated Android touch reorders cards without clicking an action", async()=>{
    // CDP synthesizes a touch stream, not a desktop mouse movement.
    const first=page.locator('.nasqo-sort-tile[data-id="summary:invoices"] .nasqo-sort-handle');
    const target=page.locator('.nasqo-sort-tile[data-id="summary:lowStock"]');
    await first.scrollIntoViewIfNeeded();
    const start=await first.boundingBox(), end=await target.boundingBox();
    assert(start && end,"touch drag targets missing");
    const sx=start.x+start.width/2,sy=start.y+start.height/2;
    const tx=end.x+end.width/2,ty=end.y+end.height/2;
    const session=await context.newCDPSession(page);
    try {
      await session.send("Input.dispatchTouchEvent",{type:"touchStart",touchPoints:[{x:sx,y:sy}]});
      await page.waitForTimeout(280);
      for(let i=1;i<=12;i++){
        await session.send("Input.dispatchTouchEvent",{type:"touchMove",touchPoints:[{
          x:sx+(tx-sx)*i/12,y:sy+(ty-sy)*i/12,
        }]});
        await page.waitForTimeout(14);
      }
      await session.send("Input.dispatchTouchEvent",{type:"touchEnd",touchPoints:[]});
      await page.waitForTimeout(250);
    } finally {await session.detach();}
    const order=await page.locator('[data-zone="summary"]').evaluateAll(nodes=>nodes.map(e=>e.dataset.id));
    assert(order.indexOf("summary:invoices")>0,"touch drag failed to rearrange cards: "+order.join(","));
  });

  await run("QR scanner can request fake camera, stop tracks and search barcode without writes",async()=>{
    await page.getByRole("button",{name:/مسح QR/}).click();
    const dialog=page.getByRole("dialog",{name:"مسح رمز المنتج"});
    await dialog.waitFor();
    await dialog.getByRole("button",{name:"فتح كاميرا المسح"}).click();
    try {
      await page.waitForFunction(()=>{
        const video=document.querySelector('.nasqo-scan-modal video');
        return video && video.srcObject && video.srcObject.getVideoTracks()?.length>0;
      },null,{timeout:8000});
    } catch (error) {
      console.log("CAMERA_DIAGNOSTICS",await page.evaluate(async()=>{
        let direct;
        try {
          const stream=await navigator.mediaDevices.getUserMedia({video:true});
          direct={ok:true,tracks:stream.getVideoTracks().map(t=>t.readyState)};
          stream.getTracks().forEach(t=>t.stop());
        } catch(err){direct={ok:false,error:String(err)};}
        return {
          message:document.querySelector(".nasqo-scan-modal")?.innerText?.slice(0,420),
          videoPresent:Boolean(document.querySelector(".nasqo-scan-modal video")),
          secure:window.isSecureContext,
          cameraAPI:!!navigator.mediaDevices,
          direct,
        };
      }));
      throw error;
    }
    await page.evaluate(()=>{ window.__cameraTracks=Array.from(document.querySelector('.nasqo-scan-modal video').srcObject.getTracks());});
    await dialog.getByRole("button",{name:"إيقاف الكاميرا"}).click();
    await page.waitForTimeout(180);
    assert(await page.evaluate(()=>window.__cameraTracks.every(x=>x.readyState==="ended")),"camera remains active after stop");
    await dialog.getByRole("textbox",{name:/الباركود أو رقم الصنف/}).fill("TEST-QR-001");
    await dialog.getByRole("button",{name:"البحث عن المنتج"}).click();
    await dialog.getByText("منتج QR تجريبي").waitFor({timeout:8000});
    assert(await dialog.getByRole("button",{name:"استلام مخزني"}).count()===1,"stock receipt action missing");
    await dialog.getByRole("button",{name:"إغلاق الماسح"}).click();
    await dialog.waitFor({state:"detached",timeout:8000});
  });

  if(await page.getByRole("dialog",{name:"مسح رمز المنتج"}).count()){
    await page.getByRole("button",{name:"إغلاق الماسح"}).click({force:true}).catch(()=>{});
    await page.waitForTimeout(120);
  }
  await run("Manual backup-age warning and opt-in device Notification with no server backup claim",async()=>{
    const nineDaysAgo=new Date();
    nineDaysAgo.setDate(nineDaysAgo.getDate()-9);
    await page.locator('input[aria-label="تاريخ التصدير الكامل الذي تحققت منه يدويًا"]').fill(iso(nineDaysAgo));
    await page.getByRole("button",{name:"تسجيل التاريخ"}).click();
    assert(await page.getByText("تجاوز 7 أيام", {exact:false}).count()>=1,"no stale alert");
    await page.getByRole("button",{name:"تفعيل تنبيه الجهاز عند التأخر"}).click();
    await page.waitForTimeout(250);
    const sent=await page.evaluate(()=>window.__mobileTestNotifications);
    assert(sent.length>=1,"browser local notification did not fire");
    assert(sent[0].title.includes("تنبيه نسقو"),"unexpected notification");
  });

  await run("Haptic toggle disables vibration and back on restores it",async()=>{
    const before=await page.evaluate(()=>window.__mobileTestVibrations.length);
    await page.getByRole("button",{name:"تحديث لوحة التحكم"}).click();
    const after=await page.evaluate(()=>window.__mobileTestVibrations.length);
    assert(after>before,"tap haptic missing");
    const toggle=page.getByRole("switch",{name:"اهتزاز اللمس"});
    await toggle.click();
    await toggle.waitFor({state:"visible"});
    assert(await toggle.getAttribute("aria-checked")==="false","haptic switch failed to disable");
    const disabledBefore=await page.evaluate(()=>window.__mobileTestVibrations.length);
    await page.getByRole("button",{name:"تحديث لوحة التحكم"}).click();
    const disabledAfter=await page.evaluate(()=>window.__mobileTestVibrations.length);
    assert(disabledBefore===disabledAfter,"vibration still fired when disabled");
  });

  await run("No Odoo production writes while testing",async()=>{
    const forbidden=calls.filter(x=>!allowed.has(x.method));
    assert(!forbidden.length,"write-like RPCs detected: "+JSON.stringify(forbidden));
    console.log("MOCK_ODOO_CALLS",calls.length,"MODELS",[...new Set(calls.map(x=>x.model))].filter(Boolean).join(", "));
  });

  await page.screenshot({path:OUTPUT+"/mobile-final.png",fullPage:false}).catch(()=>{});
  console.log("PAGE_ERRORS",JSON.stringify(errors).slice(0,2000));
  await context.close();
} catch (e) {
  console.log("TEST_SETUP_ERROR",String(e).slice(0,2500));
  process.exitCode=2;
} finally {
  await browser?.close();
}
const failed=results.filter(r=>r.status==="FAIL");
console.log("QA_RESULT",JSON.stringify({passed:results.length-failed.length,failed:failed.length,items:results}));
if(failed.length)process.exitCode=1;
