#!/usr/bin/env bash
set -euo pipefail
# Usage: publish-flutter-dev-apk.sh signed.apk VERSION_CODE VERSION_NAME "Release notes"
# Fail closed: never publish unsigned, incorrectly signed or non-monotonic releases.
[[ $# -ge 3 ]] || { echo "Usage: $0 signed.apk versionCode versionName [notes]" >&2; exit 2; }
command -v apksigner >/dev/null || { echo "Android apksigner required" >&2; exit 2; }
command -v aapt >/dev/null || { echo "Android aapt required" >&2; exit 2; }
APK="$(realpath "$1")"
CODE="$2"
NAME="$3"
NOTES="${4:-Development build}"
[[ -f "$APK" && "$CODE" =~ ^[1-9][0-9]*$ && "$NAME" =~ ^[A-Za-z0-9.+_-]+$ ]] || exit 2
apksigner verify --verbose "$APK" >/dev/null
BADGING="$(aapt dump badging "$APK" | head -n 1)"
[[ "$BADGING" == *"name='com.indexesstore.nasqo_qa'"* && "$BADGING" == *"versionCode='$CODE'"* ]] || { echo "Package/version mismatch" >&2; exit 3; }
FINGERPRINT="$(apksigner verify --print-certs "$APK" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n 1)"
[[ "$FINGERPRINT" =~ ^[0-9a-fA-F]{64}$ ]] || exit 3
ROOT="${NASQO_DEV_UPDATE_DIR:-/home/chatgpt-admin/nasqo-flutter-updates}"
mkdir -p "$ROOT"
LOCK="$ROOT/.signer-sha256"
if [[ -f "$LOCK" ]]; then
  [[ "$(cat "$LOCK")" == "$FINGERPRINT" ]] || { echo "APK signer differs from first published build" >&2; exit 4; }
fi
python3 - "$ROOT/manifest.json" "$CODE" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
if data.get('enabled') and int(data['versionCode']) >= int(sys.argv[2]):
    raise SystemExit('versionCode must increase')
PY
TEMP="$(mktemp "$ROOT/.upload-XXXXXX")"
trap 'rm -f "$TEMP"' EXIT
cp "$APK" "$TEMP"
SIZE="$(stat -c %s "$TEMP")"
[[ "$SIZE" -ge 1024 && "$SIZE" -le 262144000 ]] || exit 3
SHA="$(sha256sum "$TEMP" | cut -d ' ' -f 1)"
mv "$TEMP" "$ROOT/nasqo-dev-$CODE.apk"
if [[ ! -f "$LOCK" ]]; then printf '%s' "$FINGERPRINT" > "$LOCK"; chmod 600 "$LOCK"; fi
python3 - "$ROOT/manifest.json" "$CODE" "$NAME" "$SHA" "$SIZE" "$NOTES" <<'PY'
import json,os,sys,tempfile
target,code,name,sha,size,notes=sys.argv[1:]
data={'enabled':True,'versionCode':int(code),'versionName':name,
      'apkUrl':f'https://erp.indexesstore.com/flutter-updates/nasqo-dev-{code}.apk',
      'sha256':sha,'sizeBytes':int(size),'notes':notes}
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(target))
with os.fdopen(fd,'w') as f:
    json.dump(data,f,ensure_ascii=False)
    f.write('\n')
os.replace(tmp,target)
PY
echo "Signed development release $CODE published; sha256=$SHA"
