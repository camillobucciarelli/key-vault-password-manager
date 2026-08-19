#!/usr/bin/env bash
# 009 A041 — host entry point for canonical visual baseline capture/verify.
#
# Runs the capture/verify runner inside the ONE pinned Linux x86_64 OCI image
# (immutable digest from visual_environment_v1.json). Refuses mutable image
# references, missing podman, and any non-digest pin. All environment checks
# beyond the image digest (Chrome archive/binary hashes, fonts, timezone,
# os-release) happen inside the container in capture_runner.mjs and fail
# closed there.
#
# Usage:
#   ./desktop/browser_extension/test/run_visual_baselines.sh --verify
#   ./desktop/browser_extension/test/run_visual_baselines.sh --approve
#
# --verify  recaptures into screenshots/actual/ and compares decoded pixels +
#           approved hashes against screenshots/expected/. Never writes
#           expected/.
# --approve regenerates screenshots/expected/ and visual_baselines_v1.sha256.
#           Only for explicitly human-reviewed baseline changes.

set -euo pipefail

MODE="${1:-}"
if [[ "$MODE" != "--verify" && "$MODE" != "--approve" ]]; then
  echo "usage: $0 --verify | --approve" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_MANIFEST="$SCRIPT_DIR/visual_environment_v1.json"

if ! command -v podman >/dev/null 2>&1; then
  echo "FAIL: podman is required (the canonical environment is an OCI container)" >&2
  exit 1
fi

IMAGE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["reference"])' "$ENV_MANIFEST")"
IMAGE_ARCH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["arch"])' "$ENV_MANIFEST")"
TIMEZONE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["timezone"])' "$ENV_MANIFEST")"

if [[ "$IMAGE" != *"@sha256:"* ]]; then
  echo "FAIL: image reference is not pinned by immutable digest: $IMAGE" >&2
  exit 1
fi

# Host-side cache for the hash-verified Chrome for Testing archive; contents
# are verified against the pinned sha256 inside the container on every run.
CACHE_DIR="${KEYVAULT_VISUAL_CACHE:-$HOME/.cache/keyvault-visual}"
mkdir -p "$CACHE_DIR"

# On Apple Silicon the amd64 image must run under a Rosetta-enabled podman
# machine (qemu TCG cannot run Chrome; the runner then fails loudly on CDP
# timeouts, never silently). Select that machine's connection explicitly:
#   KEYVAULT_VISUAL_PODMAN_CONNECTION=kv-visual-amd64 ...run_visual_baselines.sh --verify
PODMAN_ARGS=()
if [[ -n "${KEYVAULT_VISUAL_PODMAN_CONNECTION:-}" ]]; then
  PODMAN_ARGS+=(-c "$KEYVAULT_VISUAL_PODMAN_CONNECTION")
fi

exec podman "${PODMAN_ARGS[@]}" run --rm \
  --arch "$IMAGE_ARCH" \
  -e "TZ=$TIMEZONE" \
  -v "$EXT_DIR:/work/desktop/browser_extension" \
  -v "$CACHE_DIR:/cache" \
  "$IMAGE" \
  node /work/desktop/browser_extension/test/visual/capture_runner.mjs "$MODE"
