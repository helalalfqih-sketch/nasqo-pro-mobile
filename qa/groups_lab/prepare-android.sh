#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
node build-table.mjs
if [[ ! -d android ]]; then
  runner="$(mktemp -d)"
  flutter create --no-pub --platforms=android --org dev.nasqo.audit --project-name nasqo_groups_lab "$runner/runner"
  cp -R "$runner/runner/android" android
fi
flutter pub get --enforce-lockfile
flutter build apk --debug --no-pub
