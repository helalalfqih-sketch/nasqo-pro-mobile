"""Exercise the installed APK on a disposable Android emulator with networking off."""
import pathlib
import re
import sqlite3
import subprocess
import time
import xml.etree.ElementTree as ET

PACKAGE = "com.indexesstore.nasqo_qa"
OUT = pathlib.Path("offline-check")
OUT.mkdir(exist_ok=True)


def adb(*args):
    return subprocess.check_output(["adb", *args])


def launch():
    adb("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")


def screen():
    adb("shell", "uiautomator", "dump", "/sdcard/window.xml")
    return ET.fromstring(adb("exec-out", "cat", "/sdcard/window.xml"))


def wait_for(predicate, label):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        try:
            for node in screen().iter("node"):
                if predicate(node):
                    return node
        except (ET.ParseError, subprocess.CalledProcessError):
            pass
        time.sleep(.4)
    raise AssertionError("Missing Android control: " + label)


def control(label):
    return wait_for(lambda n: label in (n.get("content-desc") or "").splitlines()
                    or label == n.get("text"), label)


def tap(node):
    left, top, right, bottom = map(int, re.findall(r"\d+", node.get("bounds")))
    adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))


def capture(name):
    (OUT / (name + ".png")).write_bytes(adb("exec-out", "screencap", "-p"))


def lookup():
    tap(control("الإجراءات السريعة"))
    tap(control("مسح باركود"))
    field = wait_for(lambda n: n.get("class") == "android.widget.EditText", "manual code")
    tap(field)
    adb("shell", "input", "text", "SKU-101")
    adb("shell", "input", "keyevent", "4")
    tap(control("بحث"))
    return control("توريد للمخزون")


def stock_quantity():
    # Copy the ephemeral test database and its WAL after the app has stopped.
    database = "databases/nasqo_pro_erp.db"
    for suffix in ("", "-wal"):
        path = OUT / ("inspect.sqlite" + suffix)
        p = subprocess.run(["adb", "exec-out", "run-as", PACKAGE, "cat", database + suffix],
                           stdout=subprocess.PIPE)
        if p.returncode == 0:
            path.write_bytes(p.stdout)
        else:
            path.unlink(missing_ok=True)
    with sqlite3.connect(OUT / "inspect.sqlite") as db:
        return db.execute("select quantity from inventory_items where sku='SKU-101'").fetchone()[0]


if __name__ == "__main__":
    adb("shell", "cmd", "connectivity", "airplane-mode", "enable")
    adb("shell", "svc", "wifi", "disable")
    adb("shell", "svc", "data", "disable")
    assert adb("shell", "settings", "get", "global", "airplane_mode_on").strip() == b"1"
    adb("install", "-r", "offline-apk/app-debug.apk")
    launch()
    control("الإجراءات السريعة")
    capture("home")
    adb("shell", "am", "force-stop", PACKAGE)
    before = stock_quantity()
    launch()
    supply = lookup()
    capture("inventory-lookup")
    tap(supply)
    control("الإجراءات السريعة")
    adb("shell", "am", "force-stop", PACKAGE)
    assert stock_quantity() == before + 1
    launch()
    control("الإجراءات السريعة")
    tap(control("التقارير"))
    control("المخزون المتبقي")
    capture("reports")
    print("Offline launch, item lookup, restock, restart and reports verified.")
