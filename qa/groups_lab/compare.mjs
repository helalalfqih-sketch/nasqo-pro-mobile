import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
const dir=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../screenshots');
const browser=await chromium.launch(process.env.CHROME_BIN?{executablePath:process.env.CHROME_BIN}:{});
try{
 const page=await browser.newPage();
 for(const mode of ['light','dark']){
   const urls=['react','native'].map(k=>'data:image/png;base64,'+fs.readFileSync(path.join(dir,k+'-'+mode+'.png')).toString('base64'));
   const r=await page.evaluate(async urls=>{
     const imgs=await Promise.all(urls.map(async src=>{const i=new Image();i.src=src;await i.decode();return i;}));
     const w=Math.max(...imgs.map(i=>i.width)),h=Math.max(...imgs.map(i=>i.height));
     const c=document.createElement('canvas');c.width=w;c.height=h;
     const ctx=c.getContext('2d',{willReadFrequently:true});
     const px=imgs.map(i=>{ctx.clearRect(0,0,w,h);ctx.drawImage(i,0,0);return ctx.getImageData(0,0,w,h).data;});
     const out=ctx.createImageData(w,h);let differing=0;
     for(let i=0;i<out.data.length;i+=4){
       let max=0;for(let k=0;k<4;k++)max=Math.max(max,Math.abs(px[0][i+k]-px[1][i+k]));
       if(max>16)differing++;
       out.data.set(max>16?[190,30,65,255]:[248,248,248,255],i);
     }
     ctx.putImageData(out,0,0);
     const composite=document.createElement('canvas');composite.width=3*w+16;composite.height=h+32;
     const cc=composite.getContext('2d');cc.fillStyle='white';cc.fillRect(0,0,composite.width,composite.height);
     cc.fillStyle='#182539';cc.font='16px sans-serif';
     [imgs[0],imgs[1],c].forEach((image,index)=>{cc.fillText(['React','Flutter','Pixel difference'][index],index*(w+8),20);cc.drawImage(image,index*(w+8),32);});
     return {dimensions:imgs.map(i=>[i.width,i.height]),canvas:[w,h],differing,tolerance:16,png:composite.toDataURL()};
   },urls);
   const {png,...stats}=r;
   fs.writeFileSync(path.join(dir,'compare-'+mode+'.png'),Buffer.from(png.split(',')[1],'base64'));
   console.log(JSON.stringify({mode,...stats}));
 }
}finally{await browser.close();}
