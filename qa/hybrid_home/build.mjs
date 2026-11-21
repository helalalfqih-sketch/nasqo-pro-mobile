// Bundle just DashboardPage. Fail when reference seams change, so a source update
// cannot silently switch the Android pilot to a stale handwritten dashboard.
import fs from 'node:fs';
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
if(!reference) body=body.replace(amount,'{row.amounts ? row.amounts.map(a => <span key={a.currency} style={{display:"block"}}><bdi>{formatSignedSmartBalance(a.value)}</bdi> · {a.currency}</span>) : '+amount+'}');
const icons=ast.program.body.find(n=>n.type==='ImportDeclaration' && n.source.value==='@radix-ui/react-icons');
const extras=['PeopleIcon','QrScanIcon','GaugeIcon','TagPriceIcon'].map(n=>slice(decl(n))).join('\n');
const virtual=[
  "import React,{useState,useEffect,useRef,useCallback,useMemo} from 'react';",
  slice(icons),"import {MobileScroll} from './src/mobile/MobileScroll';",
  "import {DEFAULT_HOME_TILE_LAYOUT,getVisibleOrderedHomeTiles,isDefaultHomeTileLayout,moveHomeTile,stepHomeTile,toggleHideHomeTile,togglePinHomeTile,toggleToneHomeTile} from './src/utils/dashboardPrefs';",
  "import {formatSignedSmartBalance"+(reference?",computeAccountGroupsSummary":"")+"} from './src/accounting';",
  'const APP_ICON_URL="logo.png";',extras,body
].join('\n');
const bundled=await build({entryPoints:[path.join(root,'qa/hybrid_home/host.tsx')],bundle:true,write:false,
  target:'chrome83',jsx:'automatic',minify:true,legalComments:'eof',metafile:true,
  define:{'process.env.NODE_ENV':'"production"','__REFERENCE__':String(reference)},
  plugins:[{name:'dashboard-presentation',setup(b){
    b.onResolve({filter:/^dashboard:presentation$/},()=>({path:'home',namespace:'presentation'}));
    b.onLoad({filter:/.*/,namespace:'presentation'},()=>({contents:virtual,loader:'tsx',resolveDir:root}));
  }}]});
const used=Object.entries(Object.values(bundled.metafile.outputs)[0].inputs).filter(([,v])=>v.bytesInOutput);
if(used.some(([p])=>/firebase|\/src\/services\/|\/server\/|[\\/]motion[\\/]/.test(p))) throw Error('Unexpected service or runtime dependency');
function stylesheet(file,keep) {
 const sheet=postcss.parse(fs.readFileSync(path.join(root,file),'utf8'));
 if(reference) return sheet.toString();
 sheet.walkRules(rule=>{
   const selected=rule.selectors.filter(s=>keep.test(s));
   if(selected.length)rule.selectors=selected;else rule.remove();
 });
 sheet.walkAtRules(rule=>{if(!rule.nodes?.length)rule.remove();});
 sheet.walkComments(c=>c.remove());
 return sheet.toString();
}
const css=stylesheet('src/styles.css',/^(:root|\*|body|button|input|textarea)$|\.mobile-(page|scroll)/)+'\n'+
  stylesheet('src/prototype.css',/^:root(?:\.dark)?$|^\.nasqo-app(?:$| \*| button$)|\.smart-|\.app-screen\b|\.dashboard-page\b|\.page-with-footer\b|\.mobile-scroll\b|\.workspace-sync-error\b|^\.toast\b/)+
  '\n@font-face{font-family:NasqoPilot;src:url("arabic.ttf")}html,body{margin:0;height:100%}.nasqo-app{--nasqo-font-family:NasqoPilot,sans-serif}.smart-tile.editing{touch-action:none}';
const html='<!doctype html><html lang="ar" dir="rtl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'self\'; style-src \'self\' \'unsafe-inline\'; font-src \'self\'; img-src \'self\'; connect-src \'none\'; frame-src \'none\'; base-uri \'none\'; form-action \'none\'"><link rel="stylesheet" href="home.css"></head><body><div id="home" class="nasqo-app"></div><script src="home.js"></script></body></html>\n';
fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(out,'home.js'),bundled.outputFiles[0].contents);
fs.writeFileSync(path.join(out,'home.css'),css);
fs.writeFileSync(path.join(out,'index.html'),html);
if(reference){
 fs.copyFileSync(path.join(root,'flutter_app/assets/fonts/NotoSansArabic-Regular.ttf'),path.join(out,'arabic.ttf'));
 fs.copyFileSync(path.join(root,'flutter_app/assets/nasqo_logo.png'),path.join(out,'logo.png'));
}
console.log((reference?'Standalone React':'Android React')+' assets built from DashboardPage and '+used.length+' bundled modules.');

