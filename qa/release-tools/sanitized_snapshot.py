#!/usr/bin/env python3
"""Tracked-only source package, excluding credentials, databases, user data and caches."""
from pathlib import Path
import subprocess, zipfile, hashlib, json, re, os

out=Path('.qa-out');out.mkdir(exist_ok=True)
sha=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
assert sha=='058310087cf8624568cd1665480d1f9acf5e1449'
items=sorted(set(os.fsdecode(x) for x in subprocess.check_output(['git','ls-files','-z']).split(b'\0') if x))
deny_dirs={'node_modules','.git','.dart_tool','.gradle','.cache','dist','build','coverage','.next','.venv','venv','__pycache__','backups','backup','uploads','secrets','credentials','.ssh','logs'}
deny_ext={'.xls','.xlsx','.sqlite','.sqlite3','.db','.jks','.keystore','.p12','.pfx','.pem','.key','.p8','.bak','.dump','.log','.apk','.aab','.zip','.tar','.tgz','.gz','.pdf'}
deny_names={'key.properties','local.properties','.npmrc','firebase-applet-config.json'}
accepted=[];excluded=[]
for name in items:
    p=Path(name); parts=[x.lower() for x in p.parts]; f=p.name.lower()
    blocked=(any(x in deny_dirs for x in parts[:-1]) or f in deny_names or f=='.env'
      or f.startswith('.env.') or f.startswith('id_rsa') or f.endswith(('-wal','-shm','.db-journal'))
      or p.suffix.lower() in deny_ext or any(x in ('test_logs','screenshots') for x in parts)
      or p.is_symlink() or not p.is_file())
    (excluded if blocked else accepted).append(name)
assert any(p.startswith('src/') for p in accepted)
assert any(p.startswith('flutter_app/lib/') for p in accepted)
assert any(p.startswith('react-hybrid/') for p in accepted)
assert 'package-lock.json' in accepted and 'flutter_app/pubspec.yaml' in accepted
suspicious=[re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),re.compile(rb'github_pat_[A-Za-z0-9_]{20,}'),re.compile(rb'ghp_[A-Za-z0-9]{20,}'),re.compile(rb'AKIA[0-9A-Z]{16}')]
manifest=[]
archive=out/'nasqo-complete-source-0583100-sanitized.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for name in accepted:
        data=Path(name).read_bytes()
        if any(rx.search(data) for rx in suspicious):raise RuntimeError('Secret-like material in '+name)
        z.writestr('nasqo-pro-0583100/'+name,data)
        manifest.append({'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
    guide="""NASQO PRO QA — pinned SHA 058310087cf8624568cd1665480d1f9acf5e1449
Sources and tooling only; no secrets, credentials, databases, spreadsheet exports or signing keys.
Extract ONLY outside the public document root, e.g.
/home/chatgpt-admin/nasqo-qa-source/058310087cf8624568cd1665480d1f9acf5e1449
Do not overwrite the production checkout, database, containers, services or update manifest.
Build web in isolated QA checkout: npm ci --ignore-scripts --no-audit && npm run build
Choose an unused local QA port, and create private /home/chatgpt-admin/nasqo-qa-config/qa.env (chmod 600):
NASQO_QA_ADMIN_PASSWORD=<long random password>
NASQO_QA_SESSION_SECRET=<long random session secret>
NASQO_QA_PUBLIC_ORIGIN=<dedicated QA-only HTTPS origin>
Run, after verifying 18178 is unused and QA isolation:
docker compose --env-file /home/chatgpt-admin/nasqo-qa-config/qa.env -f QA_DEPLOY/compose.qa.yml -p nasqo-qa-0583100 up --build -d
Public QA access requires a SEPARATE authenticated HTTPS route.
Never change flutter-updates/manifest.json without separate approval.
"""
    compose="""services:
  nasqo-qa:
    build:
      context: ..
      dockerfile: Dockerfile.deploy
    restart: unless-stopped
    ports:
      - "127.0.0.1:18178:3000"
    environment:
      NODE_ENV: production
      PORT: "3000"
      NASQO_SQLITE_PATH: /app/data/nasqo-qa.sqlite
      NASQO_SQLITE_ADMIN_PASSWORD: __DOLLAR__{NASQO_QA_ADMIN_PASSWORD:?QA password required}
      NASQO_SQLITE_SESSION_SECRET: __DOLLAR__{NASQO_QA_SESSION_SECRET:?QA secret required}
      NASQO_SQLITE_PUBLIC_ORIGIN: __DOLLAR__{NASQO_QA_PUBLIC_ORIGIN:-}
      NASQO_SKIP_AUTO_SQL_IMPORT: "1"
    volumes:
      - nasqo-qa-data:/app/data
    healthcheck:
      test: ["CMD","node","-e","fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
      interval: 30s
      timeout: 8s
      retries: 3
volumes:
  nasqo-qa-data:
""".replace('__DOLLAR__','$')
    z.writestr('nasqo-pro-0583100/QA_DEPLOY/README-QA.txt',guide)
    z.writestr('nasqo-pro-0583100/QA_DEPLOY/compose.qa.yml',compose)
    z.writestr('nasqo-pro-0583100/FILE_MANIFEST.json',json.dumps({'source_sha':sha,'file_count':len(manifest),'files':manifest},ensure_ascii=False,indent=2))
digest=hashlib.sha256(archive.read_bytes()).hexdigest()
(out/'source-summary.json').write_text(json.dumps({'source_sha':sha,'file_count':len(accepted),'excluded_count':len(excluded),'archive_sha256':digest,'archive_bytes':archive.stat().st_size},indent=2)+'\n')
print('SANITIZED_SOURCE_READY',archive.name,len(accepted),'files',len(excluded),'excluded','sha256',digest)
