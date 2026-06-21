#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
HOST_BIN="${SCRIPT_DIR}/keyvault_native_host"

if [[ -x "${HOST_BIN}" ]]; then
  exec "${HOST_BIN}"
fi

# TODO(autofill-v2-packaging): ship a signed, compiled native host binary next
# to this launcher. Development falls back to Dart without using `dart run` or
# writing anything to stdout before the Native Messaging frame protocol starts.
exec dart "${REPO_ROOT}/tool/native_host.dart"
