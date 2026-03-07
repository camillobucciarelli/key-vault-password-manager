#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "Usage: $0 <chrome|edge|firefox> <extension-id-or-addon-id>"
  exit 1
fi

BROWSER="$1"
EXTENSION_ID="$2"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
HOST_PATH="${SCRIPT_DIR}/keyvault_native_host.sh"

case "${BROWSER}" in
  chrome)
    TEMPLATE="${SCRIPT_DIR}/manifests/chrome/dev.camillobucciarelli.password_manager_native_host.json"
    DEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    ;;
  edge)
    TEMPLATE="${SCRIPT_DIR}/manifests/edge/dev.camillobucciarelli.password_manager_native_host.json"
    DEST_DIR="$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
    ;;
  firefox)
    TEMPLATE="${SCRIPT_DIR}/manifests/firefox/dev.camillobucciarelli.password_manager_native_host.json"
    DEST_DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"
    ;;
  *)
    echo "Unsupported browser '${BROWSER}'. Use chrome, edge, or firefox."
    exit 1
    ;;
esac

mkdir -p "${DEST_DIR}"
DEST_PATH="${DEST_DIR}/dev.camillobucciarelli.password_manager_native_host.json"

python3 - <<PY
from pathlib import Path

template = Path("${TEMPLATE}").read_text(encoding="utf-8")
output = template.replace("__HOST_PATH__", "${HOST_PATH}").replace("__EXTENSION_ID__", "${EXTENSION_ID}")
Path("${DEST_PATH}").write_text(output, encoding="utf-8")
PY

chmod +x "${HOST_PATH}"

echo "Installed native host manifest at: ${DEST_PATH}"
echo "Repository root: ${REPO_ROOT}"
