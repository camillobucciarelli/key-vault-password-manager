#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
OUT_PATH="${ROOT_DIR}/desktop/native_host/keyvault_native_host"

case "${OS:-$(uname -s 2>/dev/null || printf 'unknown')}" in
  Windows_NT|MINGW*|MSYS*|CYGWIN*)
    OUT_PATH="${OUT_PATH}.exe"
    ;;
esac

find_dart() {
  local candidate

  candidate="${ROOT_DIR}/.fvm/flutter_sdk/bin/dart"
  if [[ -x "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  if candidate="$(command -v dart 2>/dev/null || true)" && [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  if [[ -n "${HOME:-}" ]]; then
    for candidate in \
      "${HOME}/fvm/versions/stable/bin/dart" \
      "${HOME}/.fvm/versions/stable/bin/dart"; do
      if [[ -x "${candidate}" ]]; then
        printf '%s\n' "${candidate}"
        return 0
      fi
    done
  fi

  return 1
}

dart_cmd=()
if DART_BIN="$(find_dart)"; then
  dart_cmd=("${DART_BIN}")
elif FVM_BIN="$(command -v fvm 2>/dev/null || true)" && \
  [[ -n "${FVM_BIN}" ]] && \
  "${FVM_BIN}" dart --version >/dev/null 2>&1; then
  dart_cmd=("${FVM_BIN}" dart)
else
  printf 'Error: dart not found. Install Dart/Flutter/FVM or set PATH, then retry.\n' >&2
  exit 127
fi

mkdir -p "$(dirname -- "${OUT_PATH}")"

(
  cd "${ROOT_DIR}"
  "${dart_cmd[@]}" compile exe tool/native_host.dart -o "${OUT_PATH}"
)

chmod u+x "${OUT_PATH}" 2>/dev/null || true
printf 'Built native host: %s\n' "${OUT_PATH}"
