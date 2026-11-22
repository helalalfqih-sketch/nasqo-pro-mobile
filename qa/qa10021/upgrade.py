"""Install the signed 10020 APK, seed disposable fixtures, upgrade in place and compare every pre-existing business row."""
import hashlib
import json
from pathlib import Path
import re
import shlex
import sqlite3
import subprocess
import sys
import tempfile
import time

PKG = 'com.indexesstore.nasqo_qa'
DB = f'/data/user/0/{PKG}/databases/nasqo_pro_erp.db'
OUT = Path('android-evidence')
TABLES = ['accounts', 'inventory_items', 'warehouses', 'ledger_entries', 'sale_lines',
          'nonposting_documents', 'nonposting_lines']
BASE_HASH = '47732d6230e568ff6c3e8f1f88d8f1724599149e94de34680593ed8195e9bd81'


def adb(*args):
    return subprocess.check_output(['adb', *args], timeout=90).decode().strip()


def shell(*args):
    return adb('shell', '-T', shlex.join(args))


def launch():
    shell('am', 'start', '-W', '-n', PKG + '/.MainActivity')
    until = time.monotonic() + 60
    while time.monotonic() < until:
        query = subprocess.run(['adb','shell','-T',shlex.join(['sqlite3','-readonly',DB,
            'SELECT count(*) FROM inventory_items;'])], capture_output=True, text=True)
        if query.returncode == 0 and query.stdout.strip().isdigit() and int(query.stdout.strip()) > 0:
            return
        time.sleep(0.5)
    raise RuntimeError('10020 did not initialize its QA database')


def snapshot():
    shell('am','force-stop',PKG)
    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp) / 'qa.db'
        for suffix in ['', '-wal', '-journal']:
            if subprocess.run(['adb','shell','test','-f',DB+suffix]).returncode == 0:
                with Path(str(db)+suffix).open('wb') as stream:
                    subprocess.run(['adb','exec-out','cat',DB+suffix],stdout=stream,check=True)
        assert db.is_file()
        with sqlite3.connect(db) as con:
            assert con.execute('pragma integrity_check').fetchall() == [('ok',)]
            assert con.execute('pragma foreign_key_check').fetchall() == []
            result = {}
            for table in TABLES:
                rows = con.execute('SELECT * FROM '+table).fetchall()
                result[table] = sorted(hashlib.sha256(json.dumps(r,ensure_ascii=False).encode()).hexdigest() for r in rows)
            return result


def version():
    return int(re.search(r'versionCode=(\d+)',shell('dumpsys','package',PKG))[1])


def verify(mode):
    original = json.loads((OUT/'baseline-rows.json').read_text())
    current = snapshot()
    for table, rows in original.items():
        if mode == 'upgraded':
            assert current[table] == rows, f'{table}: original records changed during upgrade'
        else:
            from collections import Counter
            assert not (Counter(rows)-Counter(current[table])),f'{table}: pre-upgrade records no longer match'
    (OUT/(mode+'-preservation.json')).write_text(json.dumps({
        'version':version(), 'integrity':'ok', 'foreignKeyErrors':0, 'preExistingRowsIntact':True,
        'originalCounts':{t:len(r) for t,r in original.items()},
        'currentCounts':{t:len(r) for t,r in current.items()}},indent=2))


if __name__ == '__main__':
    assert shell('getprop','ro.boot.qemu')=='1' or shell('getprop','ro.kernel.qemu')=='1'
    OUT.mkdir(exist_ok=True)
    if sys.argv[1] in ('upgraded','after-writes'):
        verify(sys.argv[1])
    else:
        baseline, candidate = sys.argv[1:3]
        assert hashlib.sha256(Path(baseline).read_bytes()).hexdigest()==BASE_HASH
        assert shell('pm','list','packages',PKG)==''
        adb('root')
        adb('wait-for-device')
        assert shell('id','-u')=='0'
        adb('install',baseline)
        assert version()==10020
        shell('wm','size','393x852')
        shell('wm','density','160')
        shell('cmd','connectivity','airplane-mode','enable')
        shell('svc','wifi','disable')
        shell('svc','data','disable')
        assert shell('settings','get','global','airplane_mode_on')=='1'
        launch()
        shell('am','force-stop',PKG)
        fixture=Path('qa/tools/direct_upgrade_fixture.sql').read_text()
        assert fixture.count('COMMIT;')==1
        fixture=fixture.replace('COMMIT;',"""INSERT INTO ledger_entries
        (id,accountId,accountName,kind,typeLabel,payment,direction,amount,currency,exchangeRate,details,documentNumber,warehouseId,warehouseName,expenseCategory,entryNumber,deleted,entryDate)
        VALUES('qa21-existing-voucher','qa-review-usd','عميل المراجعة','voucher','سند','cash','credit',4,'usd',1,'QA','QA20','wh_1','','',91020,0,'2026-11-22');
        COMMIT;""")
        uid=shell('stat','-c','%u',DB)
        assert uid.isdecimal() and int(uid)>=10000
        subprocess.run(['adb','shell','-T','su',uid,'sqlite3',DB],input=fixture.encode(),check=True)
        before=snapshot()
        assert len(before['sale_lines'])>=1
        (OUT/'baseline-rows.json').write_text(json.dumps(before))
        adb('install','-r',candidate)
        assert version()==10021
        assert shell('stat','-c','%u',DB)==uid
        print('Upgraded signed 10020 -> 10021 in place at app UID',uid,flush=True)
