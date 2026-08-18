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
# Explicit allowlist, not a glob. A runtime file missing from this list is left
# out of the ZIP silently: zip exits 0, the build is green, and the extension
# breaks only once installed. Every task that adds a runtime file adds it here
# in the same commit (spec 009 A042). `test/overlay_lifecycle.test.js` asserts
# the list stays complete, so the omission fails a test instead of a user.
zip -X "${OUT_FILE}" \
  LICENSE \
  LICENSE-EXCEPTIONS.txt \
  manifest.json \
  background.js \
  overlay_security.js \
  overlay_lifecycle.js \
  overlay_routes.js \
  content_overlay.js \
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
