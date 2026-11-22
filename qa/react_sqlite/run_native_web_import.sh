#!/usr/bin/env bash
set -euo pipefail
test "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = 1
adb root
adb wait-for-device
candidate="$(find candidate -name app-release.apk -type f | head -1)"
test -s "$candidate"
node qa/react_sqlite/native_web_import_android.mjs "$candidate" qa-native-import-evidence
