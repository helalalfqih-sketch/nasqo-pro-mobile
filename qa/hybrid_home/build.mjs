// Bundle just DashboardPage. Fail when reference seams change, so a source update
// cannot silently switch the Android pilot to a stale handwritten dashboard.
import fs from 'node:fs';
import {directoryComponents} from './directories.mjs';
import {documentComponents} from './document.mjs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { parseSync } from 'rolldown/utils';
import postcss from 'postcss';
const root = fileURLToPath(new URL('../../', import.meta.url));
const pilot = path.join(root, 'flutter_app/android/app/src/main/assets/hybrid_home');
const reference = process.argv[2] === '--reference';
const out = process.argv[3] ?? pilot;
if (reference && path.resolve(out) === pilot) throw Error('Use a separate reference directory');
const source = fs.readFileSync(path.join(root,'src/Prototype.tsx'),'utf8');
const ast = parseSync('Prototype.tsx',source);
if (ast.errors.length) throw Error(ast.errors[0].message);
const decl = name => {
  const n = ast.program.body.find(n=>n.type==='FunctionDeclaration' && n.id?.name===name);
  if(!n) throw Error('Missing reference function: '+name);
  return n;
};
const slice = n => source.slice(n.start,n.end);
const dashboard = decl('DashboardPage');
const changes = [];
function edit(n,replacement) { changes.push([n.start,n.end,replacement]); }
function visit(n) {
  if(!n || typeof n!=='object') return;
  if(n.type==='VariableDeclarator' && n.id.name==='ctx') edit(n.init,'host.context');
  if(n.type==='ExpressionStatement' && slice(n).includes('ctx.flowRef.current = flow')) edit(n,'');
  if(n.type==='VariableDeclarator' && n.id.name==='allTiles') {
    for(const tile of n.init.elements) {
      const id=tile.properties.find(p=>p.key.name==='id').value.value;
      const action=tile.properties.find(p=>p.key.name==='action').value;
      const haptic=slice(action).includes('triggerHaptic("light")')?'host.haptic("light");':'';
      edit(action,'() => {'+haptic+'host.openTile('+JSON.stringify(id)+');}');
    }
  }
  if(n.type==='VariableDeclarator' && n.id.name==='groupRows' && !reference)
    edit(n.init,'host.rows');
  if(n.type==='VariableDeclarator' && n.id.type==='ArrayPattern' &&
      n.id.elements[0]?.name==='groupCurrencyMap' && !reference){
    edit(n.init,'[{}, host.selectCurrency]');
  }
  if(n.type==='CallExpression' && slice(n).startsWith('flow.push(purchasesScreen(row.category, row.id, row.name))'))
    edit(n,'host.openGroup(row.id)');
  for(const v of Object.values(n)) if(Array.isArray(v)) v.forEach(visit); else if(v?.type) visit(v);
}
visit(dashboard);
changes.push([dashboard.start,dashboard.body.start+1,
  'export function DashboardPage({host}) { const readHomeTileLayout=()=>host.layout; const writeHomeTileLayout=host.saveLayout; const triggerHaptic=host.haptic;']);
let body=slice(dashboard);
for(const [start,end,replacement] of changes.sort((a,b)=>b[0]-a[0]))
  body=body.slice(0,start-dashboard.start)+replacement+body.slice(end-dashboard.start);
body=body.replace('const selectedTile =', 'useEffect(() => {if(!tileEditMode)suppressNextClickRef.current=false; host.editing(tileEditMode);},[tileEditMode]); const selectedTile =');
const amount='<bdi>{formatSignedSmartBalance(row.netDebitMinusCredit)}</bdi>';
if(!body.includes(amount)) throw Error('Missing reference amount cell');
if(!reference) {
  body=body.replace('isNeg ? "neg" : isPos ? "pos" : "zero"', 'row.amounts ? "separate-currencies" : isNeg ? "neg" : isPos ? "pos" : "zero"');
  const cell='<strong>\n                                  '+amount+'\n                                </strong>';
  if(!body.includes(cell)) throw Error('Missing reference amount wrapper');
  body=body.replace(cell,'{row.amounts ? row.amounts.map(a => <span key={a.currency} className={"smart-col-bal "+(a.value < -0.005 ? "neg" : a.value > 0.005 ? "pos" : "zero")} style={{display:"block"}}><strong><bdi>{formatSignedSmartBalance(a.value)}</bdi> · {a.currency}</strong></span>) : <strong>'+amount+'</strong>}');
}
const icons=ast.program.body.find(n=>n.type==='ImportDeclaration' && n.source.value==='@radix-ui/react-icons');
// Keep the JSX, labels, icons, motion settings and CSS from the reference.
function replaceOnce(text, from, to) {
  if (!text.includes(from) || text.indexOf(from) !== text.lastIndexOf(from)) {
    throw Error('Changed React integration point: '+from);
  }
  return text.replace(from, () => to);
}
body = replaceOnce(body, '{tileEditMode ? (\n              <div className="smart-edit-bar"',
  '{host.metrics(tileEditMode)}\n            {tileEditMode ? (\n              <div className="smart-edit-bar"');
const extras=['PeopleIcon','QrScanIcon','GaugeIcon','TagPriceIcon','AppHeader'].map(n=>slice(decl(n))).join('\n');
let navigation=slice(decl('DashboardBottomNav'));
navigation=replaceOnce(navigation,'  const scrollHomeTop =', '  useEffect(() => ctx.quickState(quickOpen), [quickOpen]);\n  const scrollHomeTop =');
navigation=replaceOnce(navigation,'.dashboard-scroll .mobile-scroll-content','.dashboard-scroll .mobile-scroll');

let headerOptions=slice(decl('HeaderOptionsMenu'));
const downloadStart=headerOptions.indexOf('            void downloadUnifiedSqliteFile(');
const downloadEnd=headerOptions.indexOf('          }}',downloadStart);
if (downloadStart<0 || downloadEnd<0) throw Error('Missing original backup action');
headerOptions=headerOptions.slice(0,downloadStart)+'            ctx.openLocalBackups();\n'+headerOptions.slice(downloadEnd);
for (const id of ['options-seed-demo-btn','options-reset-db-btn']) {
  headerOptions=replaceOnce(headerOptions,'data-testid="'+id+'"','disabled aria-description="غير متاح في مساحة Android المحلية" data-testid="'+id+'"');
}
headerOptions=replaceOnce(headerOptions,'      </aside>',`        <div className="opt-menu-divider" role="separator"/>
        {[[GearIcon,"تبديل المظهر","theme"],[ReloadIcon,"التحقق من تحديثات التطبيق","app-update"],[HomeIcon,"الرئيسية الأصلية","home-mode"]].map(([Icon,label,route])=>
          <button key={route} type="button" role="menuitem" className="opt-tile" onClick={()=>{onClose();ctx.openAndroidOption(route);}}>
            <Icon aria-hidden="true"/><span>{label}</span>
          </button>)}
      </aside>`);
const virtual=[
  "import React,{useState,useEffect,useRef,useCallback,useMemo} from 'react';",
  "import {createPortal} from 'react-dom';",
  "import {motion,AnimatePresence} from 'motion/react';",
  "import {WhatsAppIcon} from './src/components/WhatsAppIcon';",
  "import {useWorkspace,useKeyboard,useScreenPortal,triggerHaptic,simpleEntryScreen,erpModuleScreen} from './qa/hybrid_home/workspace';",
  slice(icons),"import {MobileScroll} from './src/mobile/MobileScroll';",
  "import {DEFAULT_HOME_TILE_LAYOUT,getVisibleOrderedHomeTiles,isDefaultHomeTileLayout,moveHomeTile,stepHomeTile,toggleHideHomeTile,togglePinHomeTile,toggleToneHomeTile} from './src/utils/dashboardPrefs';",
  "import {formatSignedSmartBalance"+(reference?",computeAccountGroupsSummary":"")+"} from './src/accounting';",
  'const APP_ICON_URL="logo.png";',extras,body,
  ...['DashboardHeader','AppDrawer','DashboardAddMenu'].map(n=>'export '+slice(decl(n))),
  'export '+navigation, 'export '+headerOptions,
  ...['CartIcon','ShopIcon'].map(n=>'export '+slice(decl(n))), 'export {PeopleIcon};',
  "import {rankAccountSearchMatches,normalizeArabicSearch,matchesArabicSearch,formatAmount,amountToArabicWords} from './src/accounting';",
  "import {summaryOf,balanceLabel,currencyFooter} from './qa/hybrid_home/directory_amounts';",
  directoryComponents(n=>slice(decl(n)),replaceOnce),
  documentComponents(n=>slice(decl(n)),replaceOnce)
].join('\n');
const bundled=await build({entryPoints:[path.join(root,'qa/hybrid_home/host.tsx')],bundle:true,write:false,
  target:'chrome83',jsx:'automatic',minify:true,legalComments:'eof',metafile:true,
  define:{'process.env.NODE_ENV':'"production"','__REFERENCE__':String(reference)},
  plugins:[{name:'dashboard-presentation',setup(b){
    b.onResolve({filter:/^dashboard:presentation$/},()=>({path:'home',namespace:'presentation'}));
    b.onLoad({filter:/.*/,namespace:'presentation'},()=>({contents:virtual,loader:'tsx',resolveDir:root}));
  }}]});
const used=Object.entries(Object.values(bundled.metafile.outputs)[0].inputs).filter(([,v])=>v.bytesInOutput);
if (used.some(([p]) => /firebase|(?:^|[/\\\\])(?:services|server)[/\\\\]/.test(p))) {
  throw Error('Service dependency in the Android presentation bundle');
}
function stylesheet(file) {
  const sheet = postcss.parse(fs.readFileSync(path.join(root,file),'utf8'));
  // All app-owned screens use the same cascade. The APK contains its fonts.
  sheet.walkAtRules('import',rule=>{ throw Error('External stylesheet: '+rule.params); });
  if (!reference) sheet.walkComments(comment=>comment.remove());
  return sheet.toString();
}
const fontWeights={Regular:400,Medium:500,SemiBold:600,Bold:700};
const fonts=Object.entries(fontWeights).map(([name,weight])=>
  '@font-face{font-family:"IBM Plex Sans Arabic";font-style:normal;font-weight:'+weight+';src:url("fonts/IBMPlexSansArabic-'+name+'.ttf") format("truetype")}').join('\n');
const css=fonts+'\n'+stylesheet('src/styles.css')+'\n'+stylesheet('src/prototype.css')+'\n'+
  fs.readFileSync(path.join(root,'qa/hybrid_home/android.css'),'utf8');
const html='<!doctype html><html lang="ar" dir="rtl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'self\'; style-src \'self\' \'unsafe-inline\'; font-src \'self\'; img-src \'self\'; connect-src \'none\'; frame-src \'none\'; base-uri \'none\'; form-action \'none\'"><link rel="stylesheet" href="home.css"></head><body><div id="home" class="nasqo-app"></div><script src="home.js"></script></body></html>\n';
const logo=fs.readFileSync(path.join(root,'flutter_app/assets/nasqo_logo.png'));
if(!logo.equals(fs.readFileSync(path.join(root,'public/assets/aistudio/NASQO_PRO_ERP_800_022d325f.png')))) throw Error('Android logo differs from the React brand mark');
fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(out,'home.js'),bundled.outputFiles[0].contents);
fs.writeFileSync(path.join(out,'home.css'),css);
fs.writeFileSync(path.join(out,'index.html'),html);
if(reference){
 fs.cpSync(path.join(pilot,'fonts'),path.join(out,'fonts'),{recursive:true});
 fs.copyFileSync(path.join(root,'flutter_app/assets/fonts/NotoSansArabic-Regular.ttf'),path.join(out,'arabic.ttf'));
 fs.copyFileSync(path.join(root,'flutter_app/assets/nasqo_logo.png'),path.join(out,'logo.png'));
}
console.log((reference?'Standalone React':'Android React')+' assets built from DashboardPage and '+used.length+' bundled modules.');

