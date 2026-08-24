#!/usr/bin/env bash
# spec 008 Gate 1 T111 — run the safe-vault-writer harness on one target and
# file the artifact.
#
# This is the runner whose absence blocked five manual-QA items (S1-7, S4-4,
# S5-4 and the iOS/macOS artifact rows). It drives
# `integration_test/safe_vault_writer_harness_test.dart` on a device, captures
# the artifact the harness emits on stdout, and writes:
#
#   build/safety-evidence/<platform>/safe-vault-writer.json
#   build/safety-evidence/<platform>/safe-vault-writer.log
#
# Usage:
#   tool/run_safety_harness.sh -d <device-id> [-p <platform>]
#
#   -d  Flutter device id (`flutter devices`). Required.
#   -p  Platform the artifact is filed under. Defaults to the platform the
#       harness reports it actually ran on; passing it only makes the runner
#       REFUSE a mismatch, it never overrides one.
#
# A `failed` artifact is a successful run of this script: recording that a
# platform cannot hold the writer's contract is the gate working. The exit
# code reflects whether the artifact could be FILED, not whether it passed —
# except that a `failed` artifact exits 2 so CI-style callers can branch.
#
# Provenance is stamped from here because the device cannot know it. The
# schema refuses an empty `commit`/`command`, so a harness run without this
# script cannot be filed as evidence.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE=""
EXPECTED_PLATFORM=""
HOST_MODE=false
while getopts "d:p:Hh" opt; do
  case "$opt" in
    d) DEVICE="$OPTARG" ;;
    p) EXPECTED_PLATFORM="$OPTARG" ;;
    H) HOST_MODE=true ;;
    h) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "run with -h for usage" >&2; exit 64 ;;
  esac
done

if [[ "$HOST_MODE" == false && -z "$DEVICE" ]]; then
  echo "error: -d <device-id> is required (see \`flutter devices\`), or -H" >&2
  exit 64
fi
if [[ "$HOST_MODE" == true ]]; then
  DEVICE="host"
fi

# fvm when the repo is pinned through it, plain flutter otherwise. The
# toolchain is pinned in .fvmrc; a harness run on an unpinned Flutter would
# stamp a version into the artifact that nobody can reproduce.
FLUTTER="flutter"
DART="dart"
if command -v fvm >/dev/null 2>&1 && [[ -f .fvmrc ]]; then
  FLUTTER="fvm flutter"
  # Must be the SAME SDK as $FLUTTER. A plain `dart` here resolves to whatever
  # is on PATH and fails with "Invalid kernel binary format version" against a
  # .dart_tool/ that fvm's SDK produced.
  DART="fvm dart"
fi

COMMIT="$(git rev-parse HEAD)"
if ! git diff --quiet HEAD 2>/dev/null; then
  COMMIT="$COMMIT-dirty"
fi
FLUTTER_VERSION="$($FLUTTER --version 2>/dev/null | head -1 | tr -d '\r')"

# Best effort, and honestly labelled when it fails: the filesystem type is not
# reachable from inside the iOS sandbox, and a guessed value in an evidence
# artifact is worse than `unknown`.
FILESYSTEM="unknown"
case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin) FILESYSTEM="$(df -Y . 2>/dev/null | awk 'NR==2{print $2}')" ;;
  Linux)  FILESYSTEM="$(df -T . 2>/dev/null | awk 'NR==2{print $2}')" ;;
esac
FILESYSTEM="${FILESYSTEM:-unknown}"

if [[ "$HOST_MODE" == true ]]; then
  COMMAND="tool/run_safety_harness.sh -H"
else
  COMMAND="tool/run_safety_harness.sh -d $DEVICE"
fi

OUT_ROOT="build/safety-evidence"
# Kept, not a temp file: when filing fails the transcript is the only copy of
# a run that may have taken a device and a person to produce.
mkdir -p "$OUT_ROOT"
RAW_LOG="$OUT_ROOT/last-harness-run.log"

echo "==> running the T111 harness on device: $DEVICE"
echo "    commit:  $COMMIT"
echo "    flutter: $FLUTTER_VERSION"

# Host mode runs the SAME eight cases through the ordinary test runner. It is
# how the Linux and Windows rows get closed in CI, where the runner is itself
# the target platform. It is not a substitute for Android, iOS or macOS — the
# filer refuses an artifact whose platform is not the one asked for.
if [[ "$HOST_MODE" == true ]]; then
  TARGET_ARGS=(test/tool/safe_vault_writer_harness_test.dart
    --dart-define=HARNESS_EMIT=true)
else
  TARGET_ARGS=(integration_test/safe_vault_writer_harness_test.dart
    -d "$DEVICE")
fi

set +e
$FLUTTER test "${TARGET_ARGS[@]}" \
  --dart-define=HARNESS_COMMIT="$COMMIT" \
  --dart-define=HARNESS_FLUTTER_VERSION="$FLUTTER_VERSION" \
  --dart-define=HARNESS_COMMAND="$COMMAND" \
  --dart-define=HARNESS_FILESYSTEM="$FILESYSTEM" \
  --dart-define=HARNESS_DEVICE="$DEVICE" \
  2>&1 | tee "$RAW_LOG"
TEST_STATUS=${PIPESTATUS[0]}
set -e

if ! grep -q 'QA|ARTIFACT_B64|' "$RAW_LOG"; then
  echo "" >&2
  echo "error: the harness emitted no artifact (flutter test exit $TEST_STATUS)." >&2
  echo "       Nothing was filed. This is 'the harness could not run', which is" >&2
  echo "       NOT the same as 'this platform failed' — do not record a result." >&2
  exit 1
fi

# `dart run` rather than a shell JSON parser: the decode and the validation
# both go through tool/safety_evidence_schema.dart, the same code the Gate 0
# test pins. A second, shell-shaped copy of the schema is exactly how a runner
# starts filing artifacts the gate would reject.
set +e
$DART run tool/file_safety_evidence.dart \
  "$RAW_LOG" "$OUT_ROOT" "$EXPECTED_PLATFORM"
FILE_STATUS=$?
set -e

exit $FILE_STATUS
