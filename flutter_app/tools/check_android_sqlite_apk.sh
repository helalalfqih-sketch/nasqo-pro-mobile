#!/usr/bin/env bash
# Usage: bash tools/check_android_sqlite_apk.sh path/to.apk path/to/build-tools
set -euo pipefail
apk=${1:?APK path required}
build_tools=${2:?Android build-tools directory required}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -q "$apk" 'classes*.dex' -d "$work"
{
  for dex in "$work"/classes*.dex; do
    "$build_tools/dexdump" "$dex"
  done
} | grep 'Class descriptor' > "$work/classes.txt"
grep -Fq 'Lcom/tekartik/sqflite/SqflitePlugin;' "$work/classes.txt" ||
  { echo 'Missing native Android SQLite plugin; run flutter pub get before building.' >&2; exit 1; }
grep -Fq 'Lio/flutter/plugins/GeneratedPluginRegistrant;' "$work/classes.txt" ||
  { echo 'Missing Flutter Android generated plugin registrant.' >&2; exit 1; }
echo 'APK contains the Android SQLite plugin and Flutter plugin registrant.'
