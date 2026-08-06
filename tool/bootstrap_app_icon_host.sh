#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
LOCK="$ROOT/tool/app_icon_host.lock.json"
PYTHON=/opt/homebrew/opt/python@3.14/bin/python3.14
VENV="$ROOT/.dart_tool/app_icon_host/venv"
WHEEL_DIR="$ROOT/.dart_tool/app_icon_host/wheels"
WHEEL="$WHEEL_DIR/pillow-12.2.0-cp314-cp314-macosx_11_0_arm64.whl"
WHEEL_URL=https://files.pythonhosted.org/packages/ba/8c/1a9e46228571de18f8e28f16fabdfc20212a5d019f3e3303452b3f0a580d/pillow-12.2.0-cp314-cp314-macosx_11_0_arm64.whl

fail() {
  printf 'app icon host bootstrap: %s\n' "$*" >&2
  exit 1
}

[ -z "${PYTHONPATH:-}" ] || fail "PYTHONPATH must be unset"
[ -z "${PYTHONHOME:-}" ] || fail "PYTHONHOME must be unset"
[ "$(sw_vers -productName)" = macOS ] || fail "requires macOS"
[ "$(sw_vers -productVersion)" = 26.6 ] || fail "requires macOS 26.6"
[ "$(sw_vers -buildVersion)" = 25G72 ] || fail "requires macOS build 25G72"
[ "$(uname -m)" = arm64 ] || fail "requires arm64"
[ -x "$PYTHON" ] || fail "missing canonical Python: $PYTHON"

"$PYTHON" - "$LOCK" "$PYTHON" <<'PY' || exit 1
import hashlib
import json
import pathlib
import platform
import struct
import sys
import sysconfig

lock = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
executable = pathlib.Path(sys.argv[2])
checks = {
    "Python version": platform.python_version() == lock["python"]["version"],
    "Python executable": pathlib.Path(sys.executable).resolve() == executable.resolve(),
    "Python SHA-256": hashlib.sha256(executable.read_bytes()).hexdigest()
    == lock["python"]["sha256"],
    "Python ABI": sysconfig.get_config_var("SOABI").startswith("cpython-314-"),
    "pointer width": struct.calcsize("P") * 8 == lock["python"]["pointer_bits"],
    "non-free-threaded ABI": not bool(sysconfig.get_config_var("Py_GIL_DISABLED")),
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("app icon host bootstrap: mismatch: " + ", ".join(failed))
PY

if [ -e "$VENV" ] || [ -L "$VENV" ]; then
  [ -x "$VENV/bin/python" ] || fail "existing venv is invalid; reset with: rm -rf '$ROOT/.dart_tool/app_icon_host'"
  "$VENV/bin/python" -c 'import PIL' 2>/dev/null || fail "existing venv is incomplete; reset with: rm -rf '$ROOT/.dart_tool/app_icon_host'"
else
  mkdir -p -- "$WHEEL_DIR"
  "$PYTHON" -m venv "$VENV"
fi

mkdir -p -- "$WHEEL_DIR"
if [ ! -f "$WHEEL" ]; then
  tmp="$WHEEL.tmp.$$"
  trap 'rm -f -- "$tmp"' EXIT HUP INT TERM
  curl --fail --location --proto '=https' --tlsv1.2 --output "$tmp" "$WHEEL_URL"
  "$PYTHON" - "$tmp" <<'PY'
import hashlib
import pathlib
import sys

expected = "80b2da48193b2f33ed0c32c38140f9d3186583ce7d516526d462645fd98660ae"
actual = hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"wheel SHA-256 mismatch: {actual}")
PY
mv "$tmp" "$WHEEL"
  trap - EXIT HUP INT TERM
fi

"$PYTHON" - "$WHEEL" <<'PY'
import hashlib
import pathlib
import sys

expected = "80b2da48193b2f33ed0c32c38140f9d3186583ce7d516526d462645fd98660ae"
actual = hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"wheel SHA-256 mismatch: {actual}")
PY

if ! "$VENV/bin/python" -c 'import PIL; raise SystemExit(PIL.__version__ != "12.2.0")' 2>/dev/null; then
  "$VENV/bin/python" -m pip install --no-index --no-deps "$WHEEL"
fi

if ! "$VENV/bin/python" "$ROOT/tool/build_app_icon_family.py" --print-toolchain; then
  fail "provisioned venv mismatch; reset with: rm -rf '$ROOT/.dart_tool/app_icon_host'"
fi
