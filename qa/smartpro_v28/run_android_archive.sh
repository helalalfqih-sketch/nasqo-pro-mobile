#!/usr/bin/env bash
set -euo pipefail
test "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = "1"
adb root
adb wait-for-device
apk="$(find candidate -name app-release.apk -type f | head -1)"
test -s "$apk"
mkdir -p qa-smartpro-evidence
python3 qa/smartpro_v28/generate_synthetic.py qa-smartpro-evidence/smartpro-v28-synthetic.back
node qa/smartpro_v28/android_archive.mjs "$apk" qa-smartpro-evidence qa-smartpro-evidence/smartpro-v28-synthetic.back
python3 qa/react_sqlite/assert_one_ui.py qa-smartpro-evidence
