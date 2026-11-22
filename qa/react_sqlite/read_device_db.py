"""Read a stopped test app's Android SQLite database and WAL in a temporary directory."""
import json
import pathlib
import sqlite3
import shlex
import subprocess
import sys
import tempfile

account, item, invoice, voucher = sys.argv[1:5]
forms = sys.argv[5:] == ['forms']
expected = 2 if forms else 1
fixture_label = 'الواجهة' if forms else 'Android'
package = 'com.indexesstore.nasqo_qa'
base = 'nasqo_pro_erp.db'
adb = ['adb', 'exec-out', 'run-as', package]
available = subprocess.check_output([*adb, 'ls', 'databases']).decode().split()
assert base in available, available
# Some emulator system images provide the Android SQLite shell. Independently
# query the stopped app's DB in place before the byte-for-byte host inspection.
android_sql = None
sqlite_shell = subprocess.run(['adb','shell','command','-v','sqlite3'], capture_output=True, text=True)
if sqlite_shell.returncode == 0 and sqlite_shell.stdout.strip().endswith('/sqlite3'):
    sql = 'PRAGMA integrity_check; SELECT sqlite_version(); SELECT count(*) FROM ledger_entries;'
    device_command = shlex.join(['run-as', package, 'sqlite3', '-readonly', 'databases/' + base, sql])
    native = subprocess.run(['adb', 'shell', '-T', device_command],
        capture_output=True, text=True, check=True, timeout=20).stdout.strip().splitlines()
    assert len(native) == 3 and native[0] == 'ok' and int(native[2]) == 2 * expected, native
    android_sql = dict(integrity=native[0], sqliteVersion=native[1], ledgerRows=int(native[2]))
with tempfile.TemporaryDirectory() as temp:
    for extension in ('', '-wal', '-journal'):
        filename = base + extension
        if filename in available:
            pathlib.Path(temp, filename).write_bytes(subprocess.check_output([*adb, 'cat', 'databases/' + filename]))
    with sqlite3.connect(pathlib.Path(temp, base)) as db:
        assert db.execute('PRAGMA integrity_check').fetchone() == ('ok',)
        assert db.execute('SELECT COUNT(*) FROM accounts').fetchone()[0] == expected
        assert db.execute('SELECT id,name FROM accounts WHERE id=?',(account,)).fetchall() == [(account, 'مورد اختبار '+fixture_label)]
        assert db.execute('SELECT COUNT(*) FROM ledger_entries').fetchone()[0] == 2 * expected
        entries = db.execute('SELECT id,accountId,kind,direction,amount FROM ledger_entries WHERE accountId=? ORDER BY kind',(account,)).fetchall()
        assert entries == [(invoice, account, 'invoice', 'credit', 15), (voucher, account, 'voucher', 'debit', 4)], entries
        stock = db.execute('SELECT id,name,quantity FROM inventory_items WHERE id=?',(item,)).fetchall()
        assert stock == [(item, 'صنف اختبار '+fixture_label, 13)], stock
        lines = db.execute('SELECT entryId,itemId,quantity,unitPrice FROM sale_lines WHERE entryId=?',(invoice,)).fetchall()
        assert lines == [(invoice, item, 3, 5)], lines
        receipts = db.execute("SELECT COUNT(*) FROM erp_state WHERE stateKey LIKE 'react_receipt/%'").fetchone()[0]
        assert receipts == 4 * expected, receipts
        print(json.dumps(dict(integrity='ok', androidSql=android_sql, accounts=expected, entries=entries, inventory=stock, lines=lines, receipts=receipts), ensure_ascii=False))
