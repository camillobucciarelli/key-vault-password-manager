#!/usr/bin/env bash
set -euo pipefail

HOST_NAME="dev.camillobucciarelli.keyvault_native_host"

if [[ "$#" -lt 2 ]]; then
  echo "Usage: $0 <chrome|arc|edge|brave|vivaldi|chromium|opera> <extension-id>"
  exit 1
fi

BROWSER="$1"
EXTENSION_ID="$2"

if [[ ! "${EXTENSION_ID}" =~ ^[a-p]{32}$ ]]; then
  echo "Invalid extension ID '${EXTENSION_ID}'. Expected 32 lowercase characters from a to p." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOST_PATH="${SCRIPT_DIR}/keyvault_native_host.sh"

# The manifest content is browser-independent; only the destination differs.
# Arc reads Chrome's directories, so `arc` is an alias for `chrome`.
case "${BROWSER}" in
  chrome|arc)
    TEMPLATE="${SCRIPT_DIR}/manifests/chrome/${HOST_NAME}.json"
    DEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    ;;
  edge)
    TEMPLATE="${SCRIPT_DIR}/manifests/edge/${HOST_NAME}.json"
    DEST_DIR="$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
    ;;
  brave)
    TEMPLATE="${SCRIPT_DIR}/manifests/chrome/${HOST_NAME}.json"
    DEST_DIR="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
    ;;
  vivaldi)
    TEMPLATE="${SCRIPT_DIR}/manifests/chrome/${HOST_NAME}.json"
    DEST_DIR="$HOME/Library/Application Support/Vivaldi/NativeMessagingHosts"
    ;;
  chromium)
    TEMPLATE="${SCRIPT_DIR}/manifests/chrome/${HOST_NAME}.json"
    DEST_DIR="$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
    ;;
  opera)
    TEMPLATE="${SCRIPT_DIR}/manifests/chrome/${HOST_NAME}.json"
    DEST_DIR="$HOME/Library/Application Support/com.operasoftware.Opera/NativeMessagingHosts"
    ;;
  *)
    echo "Unsupported browser '${BROWSER}'. Use chrome, arc, edge, brave, vivaldi, chromium or opera."
    exit 1
    ;;
esac

[[ -f "${HOST_PATH}" ]] || {
  echo "Native host launcher not found: ${HOST_PATH}" >&2
  exit 1
}
[[ -f "${TEMPLATE}" ]] || {
  echo "Native host manifest template not found: ${TEMPLATE}" >&2
  exit 1
}

mkdir -p "${DEST_DIR}"
DEST_PATH="${DEST_DIR}/${HOST_NAME}.json"

python3 - "${TEMPLATE}" "${HOST_PATH}" "${EXTENSION_ID}" "${DEST_PATH}" <<'PY'
import json
import sys
from pathlib import Path

template_path, host_path, extension_id, destination_path = sys.argv[1:]
manifest = json.loads(Path(template_path).read_text(encoding="utf-8"))
manifest["path"] = host_path
manifest["allowed_origins"] = [f"chrome-extension://{extension_id}/"]
Path(destination_path).write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY

chmod +x "${HOST_PATH}"
python3 -m json.tool "${DEST_PATH}" >/dev/null

echo "Installed native host manifest at: ${DEST_PATH}"
echo "Host name: ${HOST_NAME}"
