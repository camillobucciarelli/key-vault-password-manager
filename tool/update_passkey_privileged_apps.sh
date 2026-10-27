#!/usr/bin/env bash
# Refreshes the Android passkey privileged-browser allowlist.
#
# PasskeyAuthActivity trusts the web origin in a passkey request only when the
# calling app is on this list (CallingAppInfo.getOrigin). The list is Google's
# published one: package names and signing-certificate fingerprints of the
# browsers allowed to sign in on a web page's behalf. Copying it by hand would
# invite a typo in a fingerprint, so it is only ever downloaded and validated.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
URL="${PASSKEY_PRIVILEGED_APPS_URL:-https://www.gstatic.com/gpm-passkeys-privileged-apps/apps.json}"
OUT_PATH="${ROOT_DIR}/android/app/src/main/res/raw/passkey_privileged_apps.json"

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

curl -sSfL --retry 3 -o "${tmp}" "${URL}"

# Refuse anything that would make getOrigin reject every browser, so a bad
# download fails here instead of silently disabling web passkeys.
python3 - "${tmp}" <<'PY'
import json, re, sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

apps = data.get("apps")
if not isinstance(apps, list) or not apps:
    sys.exit("allowlist has no apps")

fingerprint = re.compile(r"^([0-9A-F]{2}:){31}[0-9A-F]{2}$", re.IGNORECASE)
android = [app for app in apps if app.get("type") == "android"]
if not android:
    sys.exit("allowlist has no android apps")
for app in android:
    info = app.get("info") or {}
    if not info.get("package_name"):
        sys.exit("android app without package_name")
    signatures = info.get("signatures") or []
    if not signatures:
        sys.exit(f"{info['package_name']}: no signatures")
    for signature in signatures:
        if not fingerprint.match(signature.get("cert_fingerprint_sha256", "")):
            sys.exit(f"{info['package_name']}: malformed cert_fingerprint_sha256")

print(f"allowlist ok: {len(android)} android apps")
PY

mv "${tmp}" "${OUT_PATH}"
trap - EXIT
echo "Wrote ${OUT_PATH}"
