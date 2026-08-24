#!/usr/bin/env bash
# Serve the overlay harness page for the manual browser sessions (S3-5, S3-9,
# S3-10, S3-12 and S5-3 in docs/manual-qa.md).
#
# The port is not arbitrary: 8907 is what `test/visual/capture_runner.mjs`
# serves the same directory on, so the ORIGIN matches the approved visual
# baselines. Serving it anywhere else gives a different origin, and origin is
# the identity the extension binds entries to — the session would then be
# testing a site the vault has never seen.
#
# This removes no checklist item. It exists because recovering the port and
# the path out of `capture_runner.mjs` every time is most of the setup cost of
# a browser session, and a session that is expensive to start is a session
# that does not get run.
set -euo pipefail

PORT="${1:-8907}"
DIR="$(cd "$(dirname "$0")/test/visual/harness" && pwd)"

echo "harness:  http://127.0.0.1:$PORT/page.html"
echo "serving:  $DIR"
echo "(ctrl-c to stop)"
exec python3 -m http.server "$PORT" --directory "$DIR"
