#!/usr/bin/env python3
"""Generate a PUBLIC synthetic schema-28 SQLite fixture. Never reads real backups.

The table names/column names and counts emulate a SmartPro v28 export; every
row is fabricated. No customer names, balances, IDs, or phone numbers are
copied from a user source. All financial rows remain unreconciled by design.
"""
import argparse
import pathlib
import sqlite3

SPECS = {
    'alerts': 'id mdate det per_id',
    'bill_details': 'id bill_id prod_id price amount total details unit store_id discount bonus unitnum exdate',
    'bill_details2': 'id bill_id price amount unit total details discount bonus',
    'bin': 'id per_id dain madin details day month year bill cur bill_type hour mint isam img ref bonus discount sender recever comp ndate bstate added added2 curprice cboxid pername curname boxname discount_amount',
    'bin_bill_details': 'id bill_id prod_id price amount total details unit store_id discount bonus unitnum exdate',
    'bin_bill_details2': 'id bill_id price amount unit total details discount bonus',
    'boxes': 'id name hasbill isemp cur img ord',
    'cboxes': 'id name details state cur type ord',
    'currencies': 'id name sympol amount amount2 name2',
    'customers': 'id name details type phone img lim phon msg msgway tax',
    'input_move': 'id per_id dain madin details day month year bill cur bill_type hour mint isam img ref bonus discount sender recever comp ndate bstate added added2 curprice cboxid discount_amount',
    'macc': 'id name det d1 d2 type',
    'meters': 'id name cust total day month year acc_id cur mtr ndate',
    'meters_move': 'id name det total wdth hit price meter_id amount',
    'offer_bill_details': 'id bill_id prod_id price amount unit total details unitnum',
    'offer_sbill_details': 'id bill_id price amount unit total details',
    'offers': 'id per_id dain madin cur bill_type details day month year hour mint isam name ndate type bonus discount',
    'products': 'id name price barcode price2 unit exdate unit2 unit3 count2 count3 sprice2 sprice3 defunit dated cur bstate',
    'shtable': 'id name sdate',
    'store_trans': 'id store_id1 store_id2 details day month year hour mint isam ndate type',
    'stores': 'id name details state',
    'trans_details': 'id amount details bill_id prod_id unit unitnum exdate',
}

COUNTS = {
    'alerts': 2, 'bill_details': 13536, 'bill_details2': 258,
    'bin': 172, 'bin_bill_details': 270, 'bin_bill_details2': 26,
    'boxes': 11, 'cboxes': 3, 'currencies': 1, 'customers': 125,
    'input_move': 8703, 'macc': 0, 'meters': 0, 'meters_move': 0,
    'offer_bill_details': 85, 'offer_sbill_details': 0, 'offers': 4,
    'products': 1402, 'shtable': 0, 'store_trans': 25, 'stores': 5,
    'trans_details': 1373,
}
assert sum(COUNTS.values()) == 26001 and len(SPECS) == 22
NUMBERS = set('id per_id prod_id bill_id cur bill_type store_id store_id1 store_id2 type amount unitnum day month year state bstate cboxid defunit dated ord'.split())

def value(table, name, i):
    if name == 'id': return i
    if name in ('per_id', 'acc_id'): return i % 125 + 1
    if name == 'prod_id': return i % 1402 + 1
    if name == 'bill_id': return i % (25 if table == 'trans_details' else 8703) + 1
    if name == 'store_id': return i % 5 + 1
    if name == 'store_id1': return 0 if i <= 4 else i % 5 + 1
    if name == 'store_id2': return 66 if 4 < i <= 8 else (i + 1) % 5 + 1
    if name == 'type': return i % 11 + 1 if table == 'customers' else 1
    if name == 'bill_type': return (1, 2, 3, 4, 5, 7, 9)[i % 7]
    if name == 'cur':
        return (2 if i <= 2 else 3) if table == 'input_move' and i <= 7 else 1
    if name in ('day', 'month'): return 1
    if name == 'year': return 2026
    if name in NUMBERS: return 1
    if name in ('name', 'pername', 'boxname', 'curname', 'details', 'det'):
        return f'synthetic-{table}-{name}-{i}'
    if name in ('dain', 'madin'): return '1.25'
    if name in ('price', 'price2', 'total', 'curprice', 'lim', 'amount2'): return '10'
    if name in ('discount', 'discount_amount'):
        return '1' if table == 'bill_details' and i <= 5 else '0'
    if name in ('quantity', 'bonus', 'added', 'added2'): return '0'
    if name == 'unit': return 'piece'
    if name == 'ndate': return '2026-11-22'
    return None

def generate(destination):
    path = pathlib.Path(destination)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists(): path.unlink()
    with sqlite3.connect(path) as db:
        for table, definition in SPECS.items():
            cols = definition.split()
            declarations = [
                '"id" INTEGER PRIMARY KEY AUTOINCREMENT' if col == 'id' else
                f'"{col}" {"INTEGER" if col in NUMBERS else "TEXT"}'
                for col in cols
            ]
            db.execute(f'CREATE TABLE "{table}" ({", ".join(declarations)})')
            if COUNTS[table]:
                slots = ','.join('?' for _ in cols)
                sql = f'INSERT INTO "{table}" ({",".join(chr(34)+c+chr(34) for c in cols)}) VALUES ({slots})'
                db.executemany(sql,
                    (tuple(value(table,col,i) for col in cols)
                     for i in range(1,COUNTS[table]+1)))
        db.execute('PRAGMA user_version = 28')
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        assert db.execute('PRAGMA user_version').fetchone()[0] == 28
        for table,n in COUNTS.items():
            assert db.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0] == n
    print('PUBLIC_SYNTHETIC_SMARTPRO_V28_OK',len(SPECS),sum(COUNTS.values()))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('destination')
    generate(parser.parse_args().destination)
