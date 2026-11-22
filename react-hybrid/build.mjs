import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// AI Studio and the native pilot share most React modules. Overlay the exact
// Studio variants in a disposable build root, preserving both entry points.
const overlay = path.dirname(fileURLToPath(import.meta.url));
const root = path.dirname(overlay);
const work = fs.mkdtempSync(path.join(root, '.hybrid-build-'));
try {
  fs.cpSync(path.join(root, 'src'), path.join(work, 'src'), {recursive:true});
  for (const name of ['src', 'scripts', 'tests', 'vite.hybrid.config.ts', 'hybrid.html']) {
    fs.cpSync(path.join(overlay, name), path.join(work, name), {recursive:true});
  }
  for (const name of ['node_modules', 'public', 'package.json', 'firebase-applet-config.json']) {
    fs.symlinkSync(path.join(root, name), path.join(work, name));
  }
  fs.copyFileSync(path.join(root, 'tsconfig.json'), path.join(work, 'tsconfig.json'));
  execFileSync(process.execPath, [path.join(root, 'node_modules/typescript/bin/tsc'), '--noEmit'], {cwd:work, stdio:'inherit'});
  execFileSync(process.execPath,['scripts/build-hybrid.mjs'],{cwd:work,stdio:'inherit'});
  execFileSync(process.execPath,['--import','tsx','--test','tests/hybrid.test.ts'],{cwd:work,stdio:'inherit'});
  const built = path.join(work,'dist','hybrid');
  const dest = path.join(root,'flutter_app','assets','react');
  fs.mkdirSync(dest,{recursive:true});
  fs.cpSync(built,dest,{recursive:true});
  const manifest=JSON.parse(fs.readFileSync(path.join(built,'hybrid-manifest.json'),'utf8'));
  const expected=new Set(manifest.files.map(f=>f.path));
  for (const asset of fs.readdirSync(path.join(dest,'assets'))) {
    if (!expected.has('assets/'+asset)) fs.unlinkSync(path.join(dest,'assets',asset));
  }
} finally {
  fs.rmSync(work,{recursive:true,force:true});
}
