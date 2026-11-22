#!/usr/bin/env bash
set -euo pipefail
test "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = 1
baseline="$(find baseline -name app-release.apk -type f | head -1)"
candidate="$(find candidate -name app-release.apk -type f | head -1)"
test -n "$baseline" && test -s "$baseline"
test -n "$candidate" && test -s "$candidate"
python3 qa/react_sqlite/release_web_import_upgrade.py "$baseline" "$candidate"
