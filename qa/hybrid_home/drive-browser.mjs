// Mount the real web modal using synthetic Drive responses. Exercise the actual
// APK JavaScript in a second, offline browser context at identical dimensions.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {build} from 'esbuild';
import {chromium} from 'playwright';

const root=fileURLToPath(new URL('../../',import.meta.url));
const assets=path.join(root,'flutter_app/android/app/src/main/assets/hybrid_home');
const out=process.argv[2]??fs.mkdtempSync(path.join(os.tmpdir(),'nasqo-drive-'));
fs.mkdirSync(out,{recursive:true});
const files=Array.from({length:18},(_,i)=>({id:'1_'+i,name:'نسخة اختبار '+(i+1)+'.json',size:String(1400+i),
  modifiedTime:'2026-01-10T10:00:00Z',mimeType:'application/json'}));
const fixture=`
import {createRoot} from 'react-dom/client';
import {GoogleDriveModal} from './src/components/GoogleDriveModal';
const root=createRoot(document.getElementById('home'));
window.nasqoPresent=model=>{
 window.driveModel=model;
 document.documentElement.classList.toggle('dark',model.dark);
 root.render(<GoogleDriveModal key={String(model.connected)} open onClose={()=>{}} onNotify={()=>{}}
  buildBackupPayloadJson={()=>"{}"} onRestoreBackupBytes={async()=>{}}/>);
};`;
const mocks={
 '../firebase':`export const getGoogleAccessToken=()=>window.driveModel.connected?'synthetic':null;
 export const getConnectedGoogleAccountInfo=()=>({}),subscribeGoogleAccessToken=()=>()=>{};
 export const clearGoogleAccessToken=()=>{},connectGoogleDrive=()=>Promise.resolve({accessToken:'synthetic'});`,
 '../services/googleDrive':`export * from './src/services/googleDriveHelpers';
 export const listDriveFiles=async()=>window.driveModel.files,getDriveAbout=async()=>null;
 export class DriveAuthExpiredError extends Error {}
 export const createDriveFolder=()=>{},deleteDriveFilePermanently=()=>{},downloadDriveFileBytes=()=>{},
 findOrCreateDriveFolder=()=>{},trashDriveFile=()=>{},updateDriveFileContent=()=>{},uploadFileToDrive=()=>{};`,
 '../mobile':`export const KeyboardInput='input',useKeyboard=()=>({hide(){}});export {MobileScroll} from './src/mobile/MobileScroll';`,
};
const ref=await build({stdin:{contents:fixture,loader:'tsx',resolveDir:root},write:false,bundle:true,jsx:'automatic',
 define:{'process.env.NODE_ENV':'"production"'},plugins:[{name:'synthetic-services',setup(b){
  b.onResolve({filter:/^\.\.\/(firebase|services\/googleDrive|mobile)$/},args=>args.importer.endsWith('GoogleDriveModal.tsx')?{path:args.path,namespace:'mock'}:undefined);
  b.onLoad({filter:/.*/,namespace:'mock'},args=>({contents:mocks[args.path],loader:'tsx',resolveDir:root}));
 }}]});
const browser=await chromium.launch(process.env.CHROME_BIN?{executablePath:process.env.CHROME_BIN}:{});
const rows=[];
try{
 for(const width of [360,412])for(const dark of [false,true])for(const variant of ['reference','embedded']){
  const height=width===360?740:870;
  const ctx=await browser.newContext({viewport:{width,height},deviceScaleFactor:1,isMobile:true,hasTouch:true,locale:'ar',offline:true});
  const page=await ctx.newPage(), errors=[], forbidden=[];
  page.setDefaultTimeout(8000);
  page.on('pageerror',e=>{errors.push(String(e));console.error(e);});
  await page.route('**/*',route=>{
    const url=new URL(route.request().url());
    const name=url.pathname.replace(/^\/home\//,'');
    if(url.origin!=='https://appassets.androidplatform.net'){forbidden.push(url.origin);return route.abort();}
    if(url.pathname==='/assets/aistudio/NASQO_PRO_ERP_800_022d325f.png'||name==='logo.png')
      return route.fulfill({contentType:'image/png',path:path.join(root,'flutter_app/assets/nasqo_logo.png')});
    if(name==='home.js'&&variant==='reference')return route.fulfill({contentType:'application/javascript',body:Buffer.from(ref.outputFiles[0].contents)});
    const mime={'.html':'text/html','.js':'application/javascript','.css':'text/css','.ttf':'font/ttf'}[path.extname(name)];
    const target=name==='arabic.ttf'?path.join(root,'flutter_app/assets/fonts/NotoSansArabic-Regular.ttf'):path.join(assets,name);
    if(!mime||!fs.existsSync(target)){forbidden.push(url.pathname);return route.abort();}
    return route.fulfill({contentType:mime,path:target});
  });
  await page.addInitScript(()=>{window.events=[];window.NasqoHome={postMessage:s=>window.events.push(JSON.parse(s))};});
  await page.goto('https://appassets.androidplatform.net/home/index.html');
  const show=detail=>page.evaluate(v=>window.nasqoPresent(v),{standalone:'drive',connected:false,files:[],busyAction:null,errorMsg:null,status:null,progress:null,dark,...detail});
  const capture=async(state)=>{
    await page.evaluate(()=>document.fonts.ready);
    const modal=page.locator('.gdrive-modal'), rect=await modal.boundingBox();
    assert.ok(rect&&rect.width<=width+1,variant+' '+state+' overflow');
    const style=await modal.evaluate(el=>({direction:getComputedStyle(el).direction,font:getComputedStyle(el).fontFamily,color:getComputedStyle(el).color}));
    assert.equal(style.direction,'rtl');
    rows.push({variant,width,height,dark,state,rect,style});
    await page.screenshot({path:path.join(out,[variant,width,dark?'dark':'light',state].join('-')+'.png'),animations:'disabled'});
  };
  await show({});await page.getByTestId('gdrive-connect-gate').waitFor();await capture('gate');
  if(variant==='embedded'){
    await page.getByTestId('drive-google-signin-btn').tap();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='connect'));
    await show({errorMsg:'تعذّر الاتصال في بيئة الاختبار.'});await page.getByRole('alert').waitFor();
  }
  await show({connected:true,files});await page.getByTestId('gdrive-files-list').waitFor();
  assert.equal(await page.locator('.gdrive-file-card').count(),18);await capture('files');
  const search=page.getByTestId('gdrive-search-input');await search.fill('18');
  await page.waitForFunction(()=>document.querySelectorAll('.gdrive-file-card').length===1);
  await search.fill('');await page.waitForFunction(()=>document.querySelectorAll('.gdrive-file-card').length===18);
  const card=page.locator('.gdrive-file-card').last();
  await card.scrollIntoViewIfNeeded();
  if(variant==='embedded'){
    await card.getByText('تنزيل',{exact:true}).tap();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='download'&&e.id==='1_17'));
  }
  await card.getByText('استعادة',{exact:true}).tap();
  await page.getByRole('alertdialog').waitFor();await capture('confirm');
  if(variant==='embedded'){
    assert.equal(await page.evaluate(()=>window.nasqoBack()),true);
    await page.getByRole('alertdialog').waitFor({state:'hidden'});
    await card.getByText('استعادة',{exact:true}).tap();
    await page.getByTestId('gdrive-confirm-execute-btn').tap();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='inspect'&&e.id==='1_17'));
    await show({connected:true,files,busyAction:'dl:1_17',progress:47});await page.getByRole('progressbar').waitFor();
    await show({connected:true,files,status:'تم حفظ ملف الاختبار.'});await page.getByRole('status').waitFor();
    await page.getByRole('button',{name:'إغلاق',exact:true}).tap();
    await page.waitForFunction(()=>window.events.some(e=>e.action==='close'));
  }
  assert.deepEqual(errors,[]);assert.deepEqual(forbidden,[]);await ctx.close();
 }
}finally{await browser.close();}
fs.writeFileSync(path.join(out,'measurements.json'),JSON.stringify(rows,null,2)+'\n');
console.log('Drive reference and embedded: '+rows.length+' captures across two viewports and both themes.');
