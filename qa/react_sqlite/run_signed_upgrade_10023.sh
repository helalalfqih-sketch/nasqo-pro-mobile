#!/usr/bin/env bash
set -euo pipefail
test "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = 1
baseline="$(find baseline -name app-release.apk -type f | head -1)"
candidate="$(find candidate -name app-release.apk -type f | head -1)"
test -s "$baseline"
test -s "$candidate"
python3 qa/react_sqlite/release_upgrade_10023.py "$baseline" "$candidate"
