#!/usr/bin/env bash
set -euo pipefail
mkdir -p hybrid-evidence
# The PR head can also contain QA-only commits. Resolve the last change to
# running code and test the signed output of precisely that revision.
src=$(git log -1 --format=%H "$REVIEW_HEAD_SHA" -- flutter_app/android flutter_app/lib flutter_app/assets flutter_app/pubspec.yaml flutter_app/pubspec.lock src qa/hybrid_home/build.mjs qa/hybrid_home/host.tsx)
[[ "$src" =~ ^[0-9a-f]{40}$ ]]
git merge-base --is-ancestor "$src" HEAD
git diff --exit-code "$src" HEAD -- flutter_app/android flutter_app/lib flutter_app/assets src
run=''
for i in $(seq 1 80); do
  gh api "repos/$GITHUB_REPOSITORY/actions/workflows/flutter-dev-release.yml/runs?head_sha=$src&branch=poc%2Fhybrid-home-android&event=workflow_dispatch&per_page=20" > "$RUNNER_TEMP/runs.json"
  run=$(jq -r --arg sha "$src" '[.workflow_runs[] | select(.head_sha==$sha and .path==".github/workflows/flutter-dev-release.yml")][0].id // empty' "$RUNNER_TEMP/runs.json")
  if [[ "$run" =~ ^[0-9]+$ ]]; then
    gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run" > "$RUNNER_TEMP/run.json"
    if jq -e '.status=="completed"' "$RUNNER_TEMP/run.json" >/dev/null; then break; fi
  fi
  sleep 15
done
jq -e --arg sha "$src" '.head_sha==$sha and .conclusion=="success"' "$RUNNER_TEMP/run.json" >/dev/null
code=$(jq -r '.run_number+10000' "$RUNNER_TEMP/run.json"); test "$code" -gt 10014
jq -n --arg src "$src" --argjson run "$run" --argjson code "$code" '{source:$src,run:$run,versionCode:$code,baseline:10014}' > hybrid-evidence/candidate.json
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
