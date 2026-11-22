#!/usr/bin/env python3
"""Fail-closed signed 10021 -> 10022 SQLite preservation test.
Only a new rooted disposable Android emulator is accepted. No phone access."""
import hashlib
import json
import pathlib
import re
import sqlite3
import subprocess
import sys
import tempfile
import time

PACKAGE = "com.indexesstore.nasqo_qa"
DB = f"/data/user/0/{PACKAGE}/databases/nasqo_pro_erp.db"
EXPECTED_BASE_SHA = "419b7146666c2108ec9c3f024871c6b101aeda96bdbe86aa47dc691f342686f9"
EXPECTED_CERT = "0df120c5300269f289cf66ccf48aa9ce81e295055e9f7ae80159ee021e3a5a79"
TABLES = (
    "accounts", "ledger_entries", "inventory_items",
    "sale_lines", "nonposting_documents", "nonposting_lines",
)
EVIDENCE = pathlib.Path("qa-web-import-upgrade-evidence")
EVIDENCE.mkdir(exist_ok=True)

def adb(*args):
    return subprocess.run(["adb", *args], capture_output=True, check=True).stdout

def verify_apk(path, version):
    import os
    tools = sorted((pathlib.Path(os.environ["ANDROID_HOME"]) / "build-tools").iterdir())
    signer = str(tools[-1] / "apksigner")
    aapt = str(tools[-1] / "aapt")
    report = subprocess.run([signer, "verify", "--verbose", "--print-certs", path],
                            check=True, capture_output=True, text=True).stdout
    assert "Verified using v2 scheme (APK Signature Scheme v2): true" in report
    assert EXPECTED_CERT in report.lower(), "QA signature mismatch"
    badge = subprocess.run([aapt, "dump", "badging", path],
                           check=True, capture_output=True, text=True).stdout.splitlines()[0]
    assert f"name='{PACKAGE}'" in badge and f"versionCode='{version}'" in badge, badge

def installed_code():
    data = adb("shell", "dumpsys", "package", PACKAGE)
    match = re.search(rb"versionCode=(\d+)", data)
    assert match, "App not installed"
    return int(match.group(1))

def stop():
    adb("shell", "am", "force-stop", PACKAGE)
    # Android can report a dying process briefly after force-stop.
    # Wait for an actually stopped app; never snapshot a live SQLite database.
    for _ in range(40):
        p = subprocess.run(["adb", "shell", "pidof", PACKAGE],
                           capture_output=True, timeout=8)
        if p.returncode != 0 or not p.stdout.strip():
            return
        time.sleep(0.25)
    raise AssertionError("App still running after force-stop; abort SQLite snapshot")

def launch():
    adb("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
    time.sleep(5)

def snapshot(stage):
    stop()
    with tempfile.TemporaryDirectory() as directory:
        local = pathlib.Path(directory) / "nasqo_pro_erp.db"
        for ext in ("", "-wal", "-journal"):
            remote = DB + ext
            if ext:
                exists = subprocess.run(
                    ["adb", "shell", "test", "-f", remote], capture_output=True
                ).returncode == 0
                if not exists:
                    continue
            local_ext = pathlib.Path(str(local) + ext)
            local_ext.write_bytes(adb("exec-out", "cat", remote))
        with sqlite3.connect(local) as conn:
            assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert conn.execute("PRAGMA foreign_key_check").fetchall() == []
            state = {}
            for table in TABLES:
                quoted = '"' + table + '"'
                columns = [r[1] for r in conn.execute(f"PRAGMA table_info({quoted})")]
                rows = conn.execute(f"SELECT * FROM {quoted}").fetchall()
                serialized = sorted(json.dumps(row, ensure_ascii=False,
                    separators=(",", ":"), default=lambda blob: blob.hex()) for row in rows)
                state[table] = {"columns": columns, "rows": serialized}
            counts = {name: len(value["rows"]) for name, value in state.items()}
            kinds = dict(conn.execute("SELECT kind,COUNT(*) FROM ledger_entries GROUP BY kind"))
            assert counts["accounts"] >= 1, counts
            assert counts["inventory_items"] >= 1, counts
            assert kinds.get("invoice", 0) >= 1, kinds
            assert kinds.get("voucher", 0) >= 1, kinds
    # Only hashes and counts are persisted as CI evidence; never publish raw DB rows.
    info = {
        "stage": stage,
        "integrity": "ok",
        "counts": counts,
        "business_sha256": hashlib.sha256(
            json.dumps(state, sort_keys=True, ensure_ascii=False).encode()
        ).hexdigest(),
    }
    (EVIDENCE / f"{stage}.json").write_text(json.dumps(info, indent=2) + "\n")
    print(json.dumps(info), flush=True)
    return state

def main(baseline, candidate):
    assert adb("shell", "getprop", "ro.kernel.qemu").strip() == b"1", "Disposable emulator required"
    assert not adb("shell", "pm", "list", "packages", PACKAGE).strip(), "Emulator is not empty"
    assert hashlib.sha256(pathlib.Path(baseline).read_bytes()).hexdigest() == EXPECTED_BASE_SHA
    verify_apk(baseline, 10021)
    verify_apk(candidate, 10022)
    adb("root")
    adb("wait-for-device")
    assert adb("shell", "id", "-u").strip() == b"0", "Rooted emulator required"
    adb("install", baseline)
    assert installed_code() == 10021
    launch()
    stop()
    # Seed real persisted business rows using the audited SQLite fixture in a
    # disposable, force-stopped emulator. This never touches a user device.
    sql = pathlib.Path("qa/tools/direct_upgrade_fixture.sql").read_text()
    sql = sql.replace(
        "COMMIT;",
        """INSERT INTO ledger_entries(id,accountId,accountName,kind,typeLabel,payment,
        direction,amount,currency,exchangeRate,details,documentNumber,warehouseId,
        warehouseName,expenseCategory,entryNumber,deleted,entryDate)
        VALUES ('qa-review-voucher','qa-review-usd','عميل المراجعة','voucher',
        'سند قبض','cash','credit',4,'usd',1,'fixture','QA-V-21','wh_1','المخزن الرئيسي','',91015,0,'2026-11-22');
        COMMIT;"""
    )
    proc = subprocess.run(["adb", "shell", "-T", "sqlite3", DB],
                          input=sql.encode(), capture_output=True)
    assert proc.returncode == 0, proc.stderr.decode(errors="replace")
    before = snapshot("baseline-10021")
    adb("shell", "cmd", "connectivity", "airplane-mode", "enable")
    adb("shell", "svc", "wifi", "disable")
    adb("shell", "svc", "data", "disable")
    assert adb("shell", "settings", "get", "global", "airplane_mode_on").strip() == b"1"
    adb("install", "-r", candidate)
    assert installed_code() == 10022
    launch()
    assert adb("shell", "settings", "get", "global", "airplane_mode_on").strip() == b"1"
    (EVIDENCE / "after-upgrade.png").write_bytes(adb("exec-out", "screencap", "-p"))
    subprocess.run([sys.executable, "qa/react_sqlite/assert_one_ui.py",
                    str(EVIDENCE)], check=True)
    first = snapshot("upgraded-10022")
    launch()
    (EVIDENCE / "after-cold-open.png").write_bytes(adb("exec-out", "screencap", "-p"))
    reopened = snapshot("reopened-offline-10022")
    for label, after in (("upgrade", first), ("cold reopen", reopened)):
        for table in TABLES:
            assert after[table] == before[table], f"{label}: {table} changed"
    print("PASS signed 10021 -> 10022: account, invoice, voucher, stock, SQLite unchanged offline", flush=True)

if __name__ == "__main__":
    assert len(sys.argv) == 3, "Usage: release_upgrade.py BASELINE.apk CANDIDATE.apk"
    main(sys.argv[1], sys.argv[2])
