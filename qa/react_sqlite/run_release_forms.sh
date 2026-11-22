#!/usr/bin/env bash
set -euo pipefail
test "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = 1
adb root
adb wait-for-device
candidate="$(find candidate -name app-release.apk -type f | head -1)"
test -n "$candidate" && test -s "$candidate"
mkdir -p qa-release-evidence
node qa/react_sqlite/android.mjs "$candidate" qa-release-evidence
adb shell am start -W -n com.indexesstore.nasqo_qa/.MainActivity
sleep 5
python3 qa/react_sqlite/assert_one_ui.py qa-release-evidence
node qa/react_sqlite/web_reference.mjs qa-release-evidence
