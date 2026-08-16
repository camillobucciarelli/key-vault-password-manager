#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/dist"
OUT_FILE="${OUT_DIR}/keyvault-browser-extension.zip"

mkdir -p "${OUT_DIR}"
rm -f "${OUT_FILE}"

# AGPL-3.0: every separately distributed artifact ships its own license copy.
cp "${SCRIPT_DIR}/../../LICENSE" "${SCRIPT_DIR}/LICENSE"
cp "${SCRIPT_DIR}/../../LICENSE-EXCEPTIONS.txt" "${SCRIPT_DIR}/LICENSE-EXCEPTIONS.txt"
trap 'rm -f "${SCRIPT_DIR}/LICENSE" "${SCRIPT_DIR}/LICENSE-EXCEPTIONS.txt"' EXIT

cd "${SCRIPT_DIR}"
zip -X "${OUT_FILE}" \
  LICENSE \
  LICENSE-EXCEPTIONS.txt \
  manifest.json \
  background.js \
  popup.html \
  popup.js \
  popup.css \
  tokens.css \
  README.md \
  icons/icon-16.png \
  icons/icon-32.png \
  icons/icon-48.png \
  icons/icon-128.png

echo "Packaged extension at ${OUT_FILE}"
