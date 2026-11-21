// Run from the repository root after npm ci. Generates only syntactic candidates.
import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {parseSync} from 'rolldown/utils';
import postcss from 'postcss';

const sha = execFileSync('git',['rev-parse','HEAD:src'],{encoding:'utf8'}).trim();
const files = execFileSync('git',['ls-files','-z','src','server','server.ts','public/assets','flutter_app/lib','flutter_app/assets'],{encoding:'utf8'}).split('\0').filter(Boolean);
const manual = JSON.parse(fs.readFileSync('qa/reviewed-items.json','utf8'));
const fields = ['id','kind','react_file','line','item','context','trigger','expected','data_effect','flutter_target','status','discrepancy','test','screenshot','reference_tree'];
const rows = [], keys = new Map();
function emit(file,line,kind,item,context='') {
  const key = [file,kind,context,item].join('\u001f');
  const serial = (keys.get(key) ?? 0) + 1; keys.set(key,serial);
  const id = createHash('sha256').update(key+'#'+serial).digest('hex').slice(0,16);
  rows.push({id,kind,react_file:file,line,item,context,status:'UNREVIEWED',reference_tree:sha});
}
for (const file of files) {
  if (file.startsWith('flutter_app/')) continue;
  if (/\.(svg|png|webp|jpeg|jpg|woff2?|ttf)$/i.test(file)) {emit(file,'','asset',file);continue;}
  if (!/\.(css|[jt]sx?)$/.test(file)) continue;
  const source=fs.readFileSync(file,'utf8');
  if (file.endsWith('.css')) {
    postcss.parse(source,{from:file}).walkDecls(d=>emit(file,d.source.start.line,'css',d.prop+': '+d.value,d.parent.selector || d.parent.name));
    continue;
  }
  const parsed=parseSync(file,source);
  if(parsed.errors.length) throw new Error(file+': '+parsed.errors[0].message);
  const starts=[0]; for(let i=0;i<source.length;i++) if(source[i]==='\n') starts.push(i+1);
  function line(pos){let lo=0,hi=starts.length;while(lo+1<hi){const m=(lo+hi)>>1;if(starts[m]<=pos)lo=m;else hi=m;}return lo+1;}
  function visit(n,ctx='') {
    if(!n || typeof n!=='object')return;
    if(Array.isArray(n)){for(const child of n)visit(child,ctx);return;}
    const excerpt=o=>source.slice(o.start,o.end);
    const put=(kind,value)=>emit(file,line(n.start),kind,value,ctx);
    if(n.type==='FunctionDeclaration' && n.id){ctx=n.id.name;put('function',ctx);}
    if(n.type==='VariableDeclarator' && ['ArrowFunctionExpression','FunctionExpression'].includes(n.init?.type)){ctx=excerpt(n.id);put('function',ctx);}
    if(n.type==='ImportDeclaration')put('dependency',n.source.value);
    if(n.type==='JSXOpeningElement')put('element',excerpt(n.name));
    if(n.type==='JSXAttribute' && /^(on[A-Z]|aria-|data-testid$|title$|src$|placeholder$|type$|role$|className$)/.test(n.name.name))put('attribute',excerpt(n));
    if(n.type==='CallExpression' && /^(flow\.|ctx\.|fetch$|.*\.(prepare|transaction|exec|run|push|pop|replace)$)/.test(excerpt(n.callee)))put('call',excerpt(n.callee));
    if(['JSXText','Literal','TemplateElement'].includes(n.type)){
      const s=n.type==='TemplateElement'?n.value.raw:n.value;
      if(typeof s==='string' && (n.type==='JSXText'||/[\u0600-\u06ff]/.test(s)) && s.trim())put('text',s.trim());
    }
    for(const [key,val] of Object.entries(n)) if(key!=='parent' && typeof val==='object')visit(val,ctx);
  }
  visit(parsed.program);
}
// Preserve the location of every extracted occurrence, even when grouped.
function classify(r) {
  if(r.kind==='css')return /:(hover|focus|active|disabled|checked)|\.dark/.test(r.context)?'style-state':'style';
  if(r.kind==='element'){
    if(r.item==='button'||/Button$/.test(r.item))return 'button';
    if(/input|select|textarea|TextField|KeyboardInput/i.test(r.item))return 'field';
    if(/Modal|Sheet|Drawer|Menu|Dialog/.test(r.item))return 'overlay';
    if(/Page|Screen/.test(r.item))return 'screen';
  }
  if(r.kind==='function' && /Page|Screen/.test(r.item))return 'screen';
  if(r.kind==='attribute' && /^on[A-Z]/.test(r.item))return 'interaction';
  if(r.kind==='call' && /^flow\./.test(r.item))return 'navigation';
  if(r.kind==='attribute' && /^(aria-(expanded|checked|pressed|busy)|role=)/.test(r.item))return 'state';
  return r.kind;
}
const inventory=new Map();
for(const r of rows){
  const key=JSON.stringify([r.react_file,r.kind,r.context,r.item]);
  if(!inventory.has(key))inventory.set(key,{...r,category:classify(r),occurrences:[]});
  inventory.get(key).occurrences.push(r.line);
}
function csv(v){return '"'+String(v??'').replaceAll('"','""')+'"';}
function writeCsv(file,cols,items){
  fs.writeFileSync(file,[cols,...items.map(r=>cols.map(f=>r[f]))].map(r=>r.map(csv).join(',')).join('\n')+'\n');
}
const index=[...inventory.values()].map(r=>({...r,count:r.occurrences.length,lines:r.occurrences.join('|')}));
writeCsv('qa/PARITY_INVENTORY.csv',['id','category','kind','react_file','context','item','count','lines','reference_tree'],index);
const scenarios=[];
for(const m of manual){
  const lines=fs.readFileSync(m.react_file,'utf8').split('\n');
  const found=lines.findIndex(l=>l.includes(m.anchor));
  if(found<0)throw new Error('Unresolved '+m.id);
  scenarios.push({...m,line:found+1,reference_tree:sha});
}
writeCsv('qa/PARITY_MATRIX.csv',fields,scenarios);
console.log(JSON.stringify({sourceOccurrences:rows.length,uniqueInventoryRows:index.length,retainedOccurrences:index.reduce((sum,r)=>sum+r.count,0),reviewScenarios:scenarios.length}));
