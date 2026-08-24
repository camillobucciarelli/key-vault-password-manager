#!/usr/bin/env bash
# spec 011 AC-2 / AC-6 — preserve one iOS app container across two real
# integration-test processes. Flutter still stops each process; --no-uninstall
# skips only the teardown step that would delete the vault fixture and registry.
set -euo pipefail

cd "$(dirname "$0")/.."

XCODE_QUIT_TIMEOUT_SECONDS=60

xcode_is_running() {
  pgrep -x Xcode >/dev/null 2>&1
}

close_xcode() {
  if ! xcode_is_running; then
    return 0
  fi
  if ! osascript -e 'tell application "Xcode" to quit'; then
    echo "error: could not ask Xcode to quit gracefully" >&2
    return 1
  fi

  local waited=0
  while xcode_is_running; do
    if (( waited >= XCODE_QUIT_TIMEOUT_SECONDS )); then
      echo "error: Xcode did not quit within $XCODE_QUIT_TIMEOUT_SECONDS seconds" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

cleanup() {
  local status=$?
  trap - EXIT
  if ! close_xcode; then
    exit 1
  fi
  exit "$status"
}

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
if xcode_is_running; then
  echo "error: Xcode is already open. Save files, quit Xcode, then rerun." >&2
  exit 1
fi
trap cleanup EXIT

FLUTTER=(flutter)
if command -v fvm >/dev/null 2>&1 && [[ -f .fvmrc ]]; then
  FLUTTER=(fvm flutter)
fi

run_phase() {
  set +e
  "${FLUTTER[@]}" test \
    integration_test/master_password_keystore_qa_test.dart \
    -d "$DEVICE" \
    --no-uninstall \
    --dart-define=QA_PHASE="$1"
  local phase_status=$?
  set -e
  close_xcode
  return "$phase_status"
}

if [[ "$SCENARIO" == "ac2" || "$SCENARIO" == "all" ]]; then
  run_phase ac2_unlock
  run_phase ac2_relaunch
fi
if [[ "$SCENARIO" == "ac6" || "$SCENARIO" == "all" ]]; then
  run_phase ac6_seed
  run_phase ac6_upgrade
fi
