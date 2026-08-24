#!/usr/bin/env bash
# spec 011 AC-2 / AC-6 — preserve one iOS app container across two real
# integration-test processes. Flutter still stops each process; --no-uninstall
# skips only the teardown step that would delete the vault fixture and registry.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE=""
SCENARIO="all"
while getopts "d:s:h" opt; do
  case "$opt" in
    d) DEVICE="$OPTARG" ;;
    s) SCENARIO="$OPTARG" ;;
    h)
      echo "usage: tool/run_ios_keystore_qa.sh -d <device-id> [-s ac2|ac6|all]"
      exit 0
      ;;
    *) exit 64 ;;
  esac
done

if [[ -z "$DEVICE" ]]; then
  echo "error: -d <device-id> is required" >&2
  exit 64
fi
if [[ "$SCENARIO" != "ac2" && "$SCENARIO" != "ac6" && "$SCENARIO" != "all" ]]; then
  echo "error: -s must be ac2, ac6, or all" >&2
  exit 64
fi

FLUTTER=(flutter)
if command -v fvm >/dev/null 2>&1 && [[ -f .fvmrc ]]; then
  FLUTTER=(fvm flutter)
fi

run_phase() {
  "${FLUTTER[@]}" test \
    integration_test/master_password_keystore_qa_test.dart \
    -d "$DEVICE" \
    --no-uninstall \
    --dart-define=QA_PHASE="$1"
}

if [[ "$SCENARIO" == "ac2" || "$SCENARIO" == "all" ]]; then
  run_phase ac2_unlock
  run_phase ac2_relaunch
fi
if [[ "$SCENARIO" == "ac6" || "$SCENARIO" == "all" ]]; then
  run_phase ac6_seed
  run_phase ac6_upgrade
fi
