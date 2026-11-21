import fs from 'node:fs';
import {build} from 'esbuild';
import {parseSync} from 'rolldown/utils';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const lab=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(lab,'../..');
const src=fs.readFileSync(path.join(root,'src/Prototype.tsx'),'utf8');
const parsed=parseSync('Prototype.tsx',src);
const matches=[];
function walk(n){
  if(!n || typeof n!=='object')return;
  if(n.type==='JSXElement' && n.openingElement.attributes.some(a=>a.name?.name==='className' && a.value?.value==='smart-groups-table'))matches.push(n);
  for(const v of Object.values(n))if(v && typeof v==='object')walk(v);
}
walk(parsed.program);
if(matches.length!==1)throw Error('Expected a single reference table');
const original=src.slice(matches[0].start,matches[0].end);
const amountNode='<bdi>{formatSignedSmartBalance(row.netDebitMinusCredit)}</bdi>';
if(!original.includes(amountNode)) throw Error('Reference balance cell changed');
const reference=process.argv.includes('--reference');
const jsx=reference ? original : original.replace(amountNode,'{row.amounts ? row.amounts.map(a=><span key={a.currency} style={{display:"block"}}><bdi>{formatSignedSmartBalance(a.value)}</bdi> · {a.currency}</span>) : '+amountNode+'}');
// Reuse the actual JSX; adapt its callbacks to two data-only host messages.
const code=`
import React from 'react';import {createRoot} from 'react-dom/client';
import {formatSignedSmartBalance} from './src/accounting.ts';
const root=createRoot(document.getElementById('table'));
function send(action,id,currency){window.Groups.postMessage(JSON.stringify({action,id,currency}));}
const purchasesScreen=(_,id)=>id;
const flow={push:id=>send('open',id)};
const triggerHaptic=()=>{};
function Table({groupRows,currencies}){
 const ctx={currencyCodes:currencies};
 const setGroupCurrencyMap=update=>{
   const change=Object.entries(update({}));
   if(change.length===1)send('currency',Number(change[0][0]),change[0][1]);
 };
 return (${jsx});
}
window.present=({rows,currencies,dark})=>{
 document.documentElement.classList.toggle('dark',!!dark);
 root.render(<Table groupRows={rows} currencies={currencies}/>);
};
window.Groups.postMessage(JSON.stringify({action:'ready'}));`;
const bundle=await build({stdin:{contents:code,loader:'tsx',resolveDir:root},bundle:true,minify:true,write:false,define:{'process.env.NODE_ENV':'"production"'}});
const js=bundle.outputFiles[0].text.trim().replace(/<\/script/gi,'<\\/script');
const digest=createHash('sha256').update(js).digest('base64');
const css=fs.readFileSync(path.join(root,'src/prototype.css'),'utf8');
fs.copyFileSync(path.join(root,"flutter_app/assets/fonts/NotoSansArabic-Regular.ttf"),path.join(lab,"assets/NotoSansArabic-Regular.ttf"));
const font=fs.readFileSync(path.join(root,'flutter_app/assets/fonts/NotoSansArabic-Regular.ttf')).toString('base64');
const html=`<!doctype html><html lang="ar" dir="rtl"><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'sha256-${digest}'; style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'"><style>${css}
@font-face{font-family:LabArabic;src:url(data:font/ttf;base64,${font})}*{box-sizing:border-box}body{margin:0;font-family:LabArabic,sans-serif}</style><div id="table" class="smart-groups-table-wrap"></div><script>${js}</script></html>`;
fs.writeFileSync(path.join(lab,reference?'assets/reference.html':'assets/table.html'),html);
