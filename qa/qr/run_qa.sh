#!/usr/bin/env bash
set -euo pipefail
test "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = 1
adb root
adb wait-for-device
candidate="$(find candidate -name app-release.apk -type f | head -1)"
test -n "$candidate" && test -s "$candidate"
mkdir -p qa-qr-evidence
node qa/qr/qr_android.mjs "$candidate" qa-qr-evidence
python3 qa/react_sqlite/assert_one_ui.py qa-qr-evidence
