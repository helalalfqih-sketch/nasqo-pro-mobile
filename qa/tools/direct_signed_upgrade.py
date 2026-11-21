"""Compare the entire app database across a signed update on an empty CI emulator."""
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
from decimal import Decimal

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "flutter_app/test"))
from android_offline_smoke import PACKAGE, adb, launch, control, lookup, tap, capture
from android_upgrade_smoke import installed_code, stock

DB = f"/data/user/0/{PACKAGE}/databases/nasqo_pro_erp.db"
OUT = Path("offline-check")
BASE_SHA = "40d08a52af3bad0ff9d418c2417ead42dfab809681c84fe6823fc384067e4c6b"
NEW_SHA = "fed19174edd70fcfca0593376aefc811f5701721cb90a6a1234b1d4f2c2514c4"

def check(condition, message):
    if not condition:
        raise AssertionError(message)

def stop():
    adb("shell", "am", "force-stop", PACKAGE)
    pid = subprocess.run(["adb", "shell", "pidof", PACKAGE], capture_output=True)
    check(pid.returncode == 1 and not pid.stdout.strip(), "App must be stopped for a consistent snapshot")

def encoded(row):
    return json.dumps(row, ensure_ascii=False, separators=(",", ":"), allow_nan=False,
                      default=lambda blob: {"blob_hex": blob.hex()})

def summary(conn):
    check(conn.execute("PRAGMA integrity_check").fetchall() == [("ok",)], "integrity_check failed")
    check(not conn.execute("PRAGMA foreign_key_check").fetchall(), "foreign_key_check failed")
    tables = {}
    for (name,) in conn.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"):
        ident = '"' + name.replace('"', '""') + '"'
        cursor = conn.execute("SELECT * FROM " + ident)
        columns = [column[0] for column in cursor.description]
        rows = sorted(encoded(row) for row in cursor)
        digest = hashlib.sha256(encoded([columns, rows]).encode()).hexdigest()
        tables[name] = {"rows":len(rows),"sha256":digest}

    # Keep opening balances and nominal movements in their original currencies.
    amounts = {}
    def add(account, currency, direction, value):
        check(direction in {"debit","credit"}, "Unknown entry direction")
        key = account + "/" + currency
        value = Decimal(str(value))
        amounts[key] = amounts.get(key, Decimal(0)) + (value if direction=="debit" else -value)
    for row in conn.execute("SELECT id,currency,openingDirection,openingBalance FROM accounts"): add(*row)
    for row in conn.execute("SELECT accountId,currency,direction,amount FROM ledger_entries WHERE deleted=0 AND kind NOT IN ('order','quote')"): add(*row)
    balances = {k:format(v,"f") for k,v in sorted(amounts.items())}
    inventory = conn.execute("SELECT id,sku,warehouseId,quantity,avgCost FROM inventory_items ORDER BY id").fetchall()
    documents = conn.execute("SELECT id,documentNumber,accountId,kind,currency,amount FROM ledger_entries ORDER BY id").fetchall()
    check(Decimal(balances["qa-review-usd/usd"]) == Decimal("102.75"), "USD customer balance")
    check(("qa-review-invoice","QA-INV-14","qa-review-usd","invoice","usd",12.5) in documents, "Invoice header")
    check(conn.execute("SELECT itemId,quantity,unitPrice FROM sale_lines WHERE entryId='qa-review-invoice'").fetchall() == [("inv_1",1.25,10.0)], "Invoice line")
    check(conn.execute("SELECT quantity,unitPrice FROM nonposting_lines JOIN nonposting_documents ON id=documentId WHERE notes='qa-review-10014'").fetchall() == [(2.5,8.25)], "Quote line")
    check(any(row[1]=="SKU-101" and row[3]==81 for row in inventory), "Persisted stock")
    return {"tables":tables,"account_balances_by_currency":balances,"inventory":inventory,"ledger_documents":documents,
            "user_version":conn.execute("PRAGMA user_version").fetchone()[0],
            "integrity_check":"ok","foreign_key_violations":0}

def snapshot(stage):
    stop()
    with tempfile.TemporaryDirectory() as tmp:
        local = Path(tmp)/"snapshot.db"
        # A force-stopped SQLite instance may have committed pages in the WAL.
        for suffix in ("","-wal","-journal"):
            remote = DB + suffix
            if suffix and subprocess.run(["adb","shell","test","-f",remote]).returncode: continue
            with Path(str(local)+suffix).open("wb") as dst:
                subprocess.run(["adb","exec-out","cat",remote],stdout=dst,check=True)
        with sqlite3.connect(local) as conn:
            conn.execute("PRAGMA query_only=ON")
            state = summary(conn)
    (OUT/(stage+".json")).write_text(json.dumps(state,ensure_ascii=False,indent=2)+"\n")
    return state

def reopen_and_read(stage):
    launch()
    lookup()
    check(stock() == Decimal("81"), stage + " UI stock mismatch")
    capture(stage)
    return snapshot(stage)

def compare(before, after, stage):
    changed = [name for name in sorted(before["tables"].keys() | after["tables"].keys())
               if before["tables"].get(name) != after["tables"].get(name)]
    check(not changed, stage+" changed tables: "+str(changed))
    check(before == after, stage+" changed business totals or schema version")
    print(stage, "all tables and financial results match", flush=True)

def main(baseline, candidate):
    check(os.getenv("GITHUB_ACTIONS") == "true", "Requires isolated CI")
    check(adb("get-serialno").strip().startswith(b"emulator-") and adb("shell","getprop","ro.kernel.qemu").strip()==b"1", "Requires emulator")
    check(PACKAGE.encode() not in adb("shell","pm","list","packages",PACKAGE), "Requires an empty emulator")
    for file,digest in [(baseline, BASE_SHA),(candidate, NEW_SHA)]:
        check(hashlib.sha256(Path(file).read_bytes()).hexdigest()==digest, "Unexpected APK "+file)
    adb("root")
    adb("wait-for-device")
    check(adb("shell","id","-u").strip()==b"0", "Requires Android test-image debugging support")
    check(adb("shell","settings","get","global","airplane_mode_on").strip()!=b"1","Normal-mode baseline required")
    adb("install",baseline)
    check(installed_code()==10013,"Unexpected baseline")
    launch()
    supply=lookup()
    check(stock()==Decimal("80"), "Expected initial fixture stock")
    tap(supply)
    control("الرئيسية")
    stop()
    # Fixture creation is confined to the verified blank CI emulator on 10013.
    sql=(Path(__file__).with_name("direct_upgrade_fixture.sql")).read_bytes()
    uid=adb("shell","stat","-c","%u",DB).decode().strip()
    check(uid.isdecimal() and int(uid)>=10000, "Unexpected application DB owner")
    subprocess.run(["adb","shell","-T","su",uid,"sqlite3",DB],input=sql,check=True)
    before=reopen_and_read("baseline-10013")
    adb("install","-r",candidate)
    check(installed_code()==10014, "Unexpected installed candidate")
    for stage in ("first-10014","reopened-10014"):
        compare(before, reopen_and_read(stage), stage)
    adb("shell","cmd","connectivity","airplane-mode","enable")
    adb("shell","svc","wifi","disable")
    adb("shell","svc","data","disable")
    check(adb("shell","settings","get","global","airplane_mode_on").strip()==b"1","Airplane mode required")
    compare(before,reopen_and_read("offline-10014"),"offline-10014")
    print("PASS 10013 -> 10014", len(before["tables"]), "tables;", sum(t["rows"] for t in before["tables"].values()), "rows", flush=True)

if __name__ == "__main__":
    main(*sys.argv[1:])

