"""Read a stopped test app's Android SQLite database and WAL in a temporary directory."""
import json
import pathlib
import sqlite3
import subprocess
import sys
import tempfile

account, item, invoice, voucher = sys.argv[1:]
package = 'com.indexesstore.nasqo_qa'
base = 'nasqo_pro_erp.db'
adb = ['adb', 'exec-out', 'run-as', package]
available = subprocess.check_output([*adb, 'ls', 'databases']).decode().split()
assert base in available, available
with tempfile.TemporaryDirectory() as temp:
    for suffix in ('', '-wal', '-journal'):
        filename = base + suffix
        if filename in available:
            pathlib.Path(temp, filename).write_bytes(subprocess.check_output([*adb, 'cat', 'databases/' + filename]))
    with sqlite3.connect(pathlib.Path(temp, base)) as db:
        assert db.execute('PRAGMA integrity_check').fetchone() == ('ok',)
        assert db.execute('SELECT id,name FROM accounts').fetchall() == [(account, 'مورد اختبار Android')]
        entries = db.execute('SELECT id,accountId,kind,direction,amount FROM ledger_entries ORDER BY kind').fetchall()
        assert entries == [(invoice, account, 'invoice', 'credit', 15), (voucher, account, 'voucher', 'debit', 4)], entries
        stock = db.execute('SELECT id,name,quantity FROM inventory_items').fetchall()
        assert stock == [(item, 'صنف اختبار Android', 13)], stock
        lines = db.execute('SELECT entryId,itemId,quantity,unitPrice FROM sale_lines').fetchall()
        assert lines == [(invoice, item, 3, 5)], lines
        receipts = db.execute("SELECT COUNT(*) FROM erp_state WHERE stateKey LIKE 'react_receipt/%'").fetchone()[0]
        assert receipts == 4, receipts
        print(json.dumps(dict(integrity='ok', accounts=1, entries=entries, inventory=stock, lines=lines, receipts=receipts), ensure_ascii=False))
