#!/usr/bin/env bash
set -euo pipefail
mkdir -p hybrid-evidence
src=$(jq -er .source qa/hybrid_home/candidate.json)
run=$(jq -er .run qa/hybrid_home/candidate.json)
code=$(jq -er .versionCode qa/hybrid_home/candidate.json)
[[ "$src" =~ ^[0-9a-f]{40}$ && "$run" =~ ^[0-9]+$ && "$code" =~ ^[0-9]+$ ]]
git merge-base --is-ancestor "$src" HEAD
git diff --exit-code "$src" HEAD -- flutter_app src
for i in $(seq 1 80); do
  gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run" > "$RUNNER_TEMP/run.json"
  jq -e --arg src "$src" '.head_sha==$src and .path==".github/workflows/flutter-dev-release.yml"' "$RUNNER_TEMP/run.json" >/dev/null
  if jq -e '.status=="completed"' "$RUNNER_TEMP/run.json" >/dev/null; then break; fi
  sleep 15
done
jq -e '.conclusion=="success"' "$RUNNER_TEMP/run.json" >/dev/null
gh run download "$run" --name nasqo-signed-dev-apk --dir "$RUNNER_TEMP/candidate"
gh run download 44929394951 --name nasqo-signed-dev-apk --dir "$RUNNER_TEMP/baseline"
echo "fed19174edd70fcfca0593376aefc811f5701721cb90a6a1234b1d4f2c2514c4  $RUNNER_TEMP/baseline/app-release.apk" | sha256sum -c -
sign=$(find "$ANDROID_HOME/build-tools" -name apksigner -type f | sort -V | tail -1)
aapt=$(find "$ANDROID_HOME/build-tools" -name aapt -type f | sort -V | tail -1)
for kind in baseline candidate; do
  apk="$RUNNER_TEMP/$kind/app-release.apk"
  "$sign" verify --verbose --print-certs "$apk" > "hybrid-evidence/$kind-signature.txt"
  grep -Fx 'Number of signers: 1' "hybrid-evidence/$kind-signature.txt"
  certs=$(awk '/certificate SHA-256 digest:/ {print tolower($NF)}' "hybrid-evidence/$kind-signature.txt" | sort -u)
  test "$certs" = 0df120c5300269f289cf66ccf48aa9ce81e295055e9f7ae80159ee021e3a5a79
  "$aapt" dump badging "$apk" > "$RUNNER_TEMP/$kind-badging"
  head -1 "$RUNNER_TEMP/$kind-badging" > "hybrid-evidence/$kind-identity.txt"
  grep -F "name='com.indexesstore.nasqo_qa'" "hybrid-evidence/$kind-identity.txt"
  expected=10014; if [ "$kind" = candidate ]; then expected=$code; fi
  grep -F "versionCode='$expected'" "hybrid-evidence/$kind-identity.txt"
  sha256sum "$apk" | tee "hybrid-evidence/$kind-sha256.txt"
  stat -c %s "$apk" > "hybrid-evidence/$kind-bytes.txt"
done
