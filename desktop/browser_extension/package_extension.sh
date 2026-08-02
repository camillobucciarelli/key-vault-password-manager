#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/dist"
OUT_FILE="${OUT_DIR}/keyvault-browser-extension.zip"

mkdir -p "${OUT_DIR}"
rm -f "${OUT_FILE}"

cd "${SCRIPT_DIR}"
zip -X "${OUT_FILE}" \
  manifest.json \
  background.js \
  popup.html \
  popup.js \
  popup.css \
  README.md

echo "Packaged extension at ${OUT_FILE}"
