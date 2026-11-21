"""Verify a signed upgrade using only the UI of an empty Android test emulator."""
from decimal import Decimal
from pathlib import Path
import re
import sys

from android_offline_smoke import PACKAGE, adb, capture, control, launch, lookup, tap, wait_for


def stock():
    def label(node):
        return node.get("content-desc", "") + node.get("text", "")

    node = wait_for(lambda n: "الرصيد الحالي:" in label(n), "fixture stock")
    match = re.search(r"الرصيد الحالي:\s*([\d.]+)", label(node))
    if not match:
        raise AssertionError("Could not read the quantity from the UI")
    return Decimal(match.group(1))


def installed_code():
    report = adb("shell", "dumpsys", "package", PACKAGE)
    return int(re.search(rb"versionCode=(\d+)", report).group(1))


def upgrade(baseline, candidate):
    if adb("shell", "getprop", "ro.kernel.qemu").strip() != b"1":
        raise RuntimeError("This fixture requires a disposable emulator")
    if PACKAGE.encode() in adb("shell", "pm", "list", "packages", PACKAGE):
        raise RuntimeError("An existing workspace was found")
    adb("shell", "cmd", "connectivity", "airplane-mode", "enable")
    adb("shell", "svc", "wifi", "disable")
    adb("shell", "svc", "data", "disable")
    adb("install", baseline)
    previous = installed_code()
    launch()
    supply = lookup()
    opening = stock()
    tap(supply)
    control("الرئيسية")
    adb("shell", "am", "force-stop", PACKAGE)
    launch()
    lookup()
    posted = stock()
    assert posted == opening + 1
    capture("signed-before")
    adb("shell", "am", "force-stop", PACKAGE)
    adb("install", "-r", candidate)
    assert installed_code() > previous
    launch()
    lookup()
    assert stock() == posted
    assert adb("shell", "settings", "get", "global", "airplane_mode_on").strip() == b"1"
    capture("signed-after")
    print(f"Signed upgrade {previous} -> {installed_code()}, stock {opening} -> {posted} -> {posted}")


if __name__ == "__main__":
    upgrade(*(str(Path(path).resolve(strict=True)) for path in sys.argv[1:]))
