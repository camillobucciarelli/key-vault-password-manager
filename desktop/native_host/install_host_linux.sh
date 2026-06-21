#!/usr/bin/env bash
set -euo pipefail

HOST_NAME="dev.camillobucciarelli.keyvault_native_host"

usage() {
  cat <<'USAGE'
Usage: install_host_linux.sh [--browser chrome|chromium|edge] <extension-id>

Installs the KeyVault native messaging host manifest for the current Linux user.
No sudo is required. The default browser target is Google Chrome.

Examples:
  ./desktop/native_host/install_host_linux.sh abcdefghijklmnopabcdefghijklmnop
  ./desktop/native_host/install_host_linux.sh --browser chromium abcdefghijklmnopabcdefghijklmnop
  ./desktop/native_host/install_host_linux.sh --browser edge abcdefghijklmnopabcdefghijklmnop

The extension ID is shown on chrome://extensions or edge://extensions after
loading the desktop/browser_extension folder in Developer mode.
USAGE
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

BROWSER="chrome"
EXTENSION_ID=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --browser)
      [[ "$#" -ge 2 ]] || die "--browser requires chrome, chromium or edge"
      BROWSER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      die "Unknown option: $1"
      ;;
    *)
      [[ -z "${EXTENSION_ID}" ]] || die "Only one extension ID can be provided"
      EXTENSION_ID="$1"
      shift
      ;;
  esac
done

[[ -n "${EXTENSION_ID}" ]] || {
  usage >&2
  die "Extension ID is required"
}

if [[ ! "${EXTENSION_ID}" =~ ^[a-p]{32}$ ]]; then
  die "Invalid extension ID '${EXTENSION_ID}'. Expected 32 lowercase characters from a to p."
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOST_PATH="${SCRIPT_DIR}/keyvault_native_host.sh"

[[ -f "${HOST_PATH}" ]] || die "Native host launcher not found: ${HOST_PATH}"

case "${BROWSER}" in
  chrome)
    TEMPLATE="${SCRIPT_DIR}/manifests/chrome/${HOST_NAME}.json"
    DEST_DIR="${HOME}/.config/google-chrome/NativeMessagingHosts"
    ;;
  chromium)
    TEMPLATE="${SCRIPT_DIR}/manifests/chrome/${HOST_NAME}.json"
    DEST_DIR="${HOME}/.config/chromium/NativeMessagingHosts"
    ;;
  edge)
    TEMPLATE="${SCRIPT_DIR}/manifests/edge/${HOST_NAME}.json"
    DEST_DIR="${HOME}/.config/microsoft-edge/NativeMessagingHosts"
    ;;
  *)
    die "Unsupported browser '${BROWSER}'. Use chrome, chromium or edge."
    ;;
esac

[[ -f "${TEMPLATE}" ]] || die "Native host manifest template not found: ${TEMPLATE}"

if [[ ! -x "${HOST_PATH}" ]]; then
  chmod u+x "${HOST_PATH}"
fi

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

python3 -m json.tool "${DEST_PATH}" >/dev/null

printf 'Installed KeyVault native messaging host for %s.\n' "${BROWSER}"
printf 'Manifest: %s\n' "${DEST_PATH}"
printf 'Host launcher: %s\n' "${HOST_PATH}"
printf 'Allowed origin: chrome-extension://%s/\n' "${EXTENSION_ID}"
printf 'Restart the browser before testing the extension.\n'
