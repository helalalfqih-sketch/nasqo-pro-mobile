#!/usr/bin/env python3
"""Disposable, rooted Android emulator: signed 10019->10020 upgrade, SQLite snapshots and airplane mode."""
import hashlib, subprocess, sys, re, json, sqlite3, tempfile, time
from pathlib import Path

pkg = 'com.indexesstore.nasqo_qa'
remote_db = f'/data/user/0/{pkg}/databases/nasqo_pro_erp.db'
out = Path('qa-upgrade-evidence')
out.mkdir(exist_ok=True)
def adb(*args):
    return subprocess.check_output(['adb', *args], stderr=subprocess.STDOUT).decode(errors='replace').strip()
def shell(*args):
    return adb('shell', *args)
def check(condition, message):
    if not condition: raise AssertionError(message)
def sha256(filename):
    return hashlib.sha256(Path(filename).read_bytes()).hexdigest()
baseline, candidate = sys.argv[1:]
check(sha256(baseline) == '36bac5302e4c31aa38e5d6a2e8ec39af29c8c1cbe4dcb9b2d2011d7ec2675d0a', 'Unexpected baseline APK')
check(shell('getprop','ro.kernel.qemu') == '1', 'Only a disposable emulator may be used')
check(pkg not in shell('pm','list','packages',pkg), 'Emulator must start blank')
adb('root')
adb('wait-for-device')
check(shell('id','-u') == '0', 'Rooted test image required')
def installed():
    m = re.search(r'versionCode=(\d+)', shell('dumpsys', 'package', pkg))
    check(m is not None, 'Cannot read installed package version')
    return int(m.group(1))
def launch():
    shell('am','start','-W','-n',pkg+'/.MainActivity')
    for _ in range(80):
        try:
            if shell('pidof',pkg): return
        except subprocess.CalledProcessError: pass
        time.sleep(1)
    raise AssertionError('App did not start')
def stop():
    shell('am','force-stop',pkg)
def snapshot():
    stop()
    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp)/'snapshot.db'
        for suff in ('','-wal','-journal'):
            file=remote_db+suff
            if subprocess.run(['adb','shell','test','-f',file],stdout=subprocess.DEVNULL).returncode:
                continue
            with Path(str(db)+suff).open('wb') as f:
                subprocess.run(['adb','exec-out','cat',file],stdout=f,check=True)
        check(db.exists(), 'App SQLite DB missing')
        with sqlite3.connect(db) as cx:
            check(cx.execute('PRAGMA integrity_check').fetchone()==('ok',), 'SQLite corruption')
            check(not cx.execute('PRAGMA foreign_key_check').fetchall(), 'SQLite foreign key errors')
            business=['accounts','ledger_entries','sale_lines','inventory_items','nonposting_documents','nonposting_lines']
            result={}
            for table in business:
                check(cx.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?",(table,)).fetchone() is not None,'Missing '+table)
                cols=[x[1] for x in cx.execute('PRAGMA table_info("'+table+'")')]
                rows=cx.execute('SELECT * FROM "'+table+'"').fetchall()
                result[table]={'columns':cols,'rows':rows}
            check(cx.execute("SELECT count(*) FROM accounts WHERE id='qa-review-usd'").fetchone()[0]==1,'Synthetic account missing')
            check(cx.execute("SELECT count(*) FROM ledger_entries WHERE id in ('qa-review-invoice','qa-review-voucher')").fetchone()[0]==2,'Invoice/voucher missing')
            check(cx.execute("SELECT count(*) FROM sale_lines WHERE entryId='qa-review-invoice'").fetchone()[0]==1,'Invoice line missing')
            check(cx.execute("SELECT count(*) FROM nonposting_documents WHERE notes='qa-review-10014'").fetchone()[0]==1,'Quote missing')
            check(cx.execute("SELECT count(*) FROM inventory_items WHERE sku='SKU-101'").fetchone()[0]==1,'Stock missing')
            return result
def compare(before, after):
    for table, value in before.items():
        current = after[table]
        check(all(c in current['columns'] for c in value['columns']), table+' lost a column')
        indices=[current['columns'].index(c) for c in value['columns']]
        projected=[[r[i] for i in indices] for r in current['rows']]
        original=[list(r) for r in value['rows']]
        check(sorted(map(repr,projected))==sorted(map(repr,original)), table+' records changed during update')
adb('install',baseline)
check(installed()==10019, 'Old code mismatch')
launch()
stop()
fixture=Path('qa/tools/direct_upgrade_fixture.sql').read_text()
voucher="""INSERT INTO ledger_entries(id,accountId,accountName,kind,typeLabel,payment,direction,amount,currency,exchangeRate,details,documentNumber,warehouseId,warehouseName,expenseCategory,entryNumber,deleted,entryDate)
VALUES ('qa-review-voucher','qa-review-usd','عميل المراجعة','voucher','سند صرف','cash','credit',4,'usd',1,'QA validation','QA-VOU-20','wh_1','المخزن الرئيسي','',91020,0,'2026-11-22');
"""
check(fixture.count('COMMIT;')==1, 'Unexpected fixture structure')
fixture=fixture.replace('COMMIT;',voucher+'COMMIT;')
uid=shell('stat','-c','%u',remote_db)
check(uid.isdecimal() and int(uid)>10000,'Invalid database owner')
subprocess.run(['adb','shell','-T','su',uid,'sqlite3',remote_db],input=fixture.encode(),check=True)
before=snapshot()
adb('install','-r',candidate)
check(installed()==10020,'New code mismatch')
shell('cmd','connectivity','airplane-mode','enable')
shell('svc','wifi','disable')
shell('svc','data','disable')
check(shell('settings','get','global','airplane_mode_on')=='1','Airplane mode missing')
launch()
after=snapshot()
compare(before,after)
launch()
again=snapshot()
compare(before,again)
evidence={'baseline_code':10019,'candidate_code':10020,'source_sha':'058310087cf8624568cd1665480d1f9acf5e1449',
'package':pkg,'offline':True,'sqlite_integrity':'ok','foreign_key_errors':0,
'tables_preserved':{k:len(v['rows']) for k,v in before.items()},
'data_preserved_after_update':True,'data_preserved_after_reopen':True,
'candidate_sha256':sha256(candidate)}
(out/'signed-upgrade.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
print('PASS_QA_SIGNED_10019_TO_10020',json.dumps(evidence))
