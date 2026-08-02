#!/bin/bash
# Run the capture pipeline end to end and compare the crop against macOS's own
# `screencapture` for the identical region. See Sources/Trimshot/SelfCheck.swift.
#
#   ./scripts/self-check.sh [outputDir]     # default: ./build/selfcheck
#
# Has to go through `open` rather than running the binary directly: a process started
# from a shell inherits the *terminal's* Screen Recording permission, not the app's.
# And `open` silently ignores --args and the stdout redirect when the app is already
# running, so any existing instance is quit first.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Trimshot.app"
OUT="${1:-$ROOT/build/selfcheck}"
LOG="$OUT/selfcheck.log"

# The diagnostic flags are compiled out of release builds on purpose — they would let
# any local process borrow this app's Screen Recording grant. So build a debug bundle.
echo "==> building a debug bundle (diagnostics are release-stripped)"
CONFIG=debug "$ROOT/scripts/bundle.sh" >/dev/null

mkdir -p "$OUT"
rm -f "$LOG"

WAS_RUNNING=0
if pgrep -f "$APP/Contents/MacOS/Trimshot" >/dev/null 2>&1; then
    WAS_RUNNING=1
    echo "==> quitting the running instance so --args takes effect"
    pkill -f "$APP/Contents/MacOS/Trimshot" || true
    # Give launchd a moment to reap it, or `open` reuses the dying instance.
    for _ in $(seq 1 20); do
        pgrep -f "$APP/Contents/MacOS/Trimshot" >/dev/null 2>&1 || break
        sleep 0.1
    done
fi

echo "==> running self-check"
open -W --stdout "$LOG" --stderr "$LOG" -a "$APP" --args --self-check "$OUT" || true

if [ -s "$LOG" ]; then
    cat "$LOG"
else
    echo "(no output — the app may have failed to launch)" >&2
fi

STATUS=0
grep -q "self-check passed" "$LOG" 2>/dev/null || STATUS=1

if [ "$WAS_RUNNING" = "1" ]; then
    echo
    echo "==> relaunching the app"
    open -a "$APP"
fi

echo
echo "note: build/ now holds a DEBUG bundle. Run ./scripts/bundle.sh for a release one."

exit "$STATUS"
