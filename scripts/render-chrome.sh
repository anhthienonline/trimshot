#!/bin/bash
# Render the selection UI to PNGs and verify the pieces that are easy to get wrong:
# the live preview must match the exported file pixel for pixel, and OCR must read
# Vietnamese back out of text drawn by the annotation renderer.
#
#   ./scripts/render-chrome.sh [outputDir]     # default: ./build/preview
#
# Outputs, all cropped to the same region so they can be flipped between:
#   chrome-raw.png         the capture with no chrome, as a baseline for the dim
#   chrome-dragging.png    mid-drag: crosshair, magnifier, size label
#   chrome-settled.png     after the drag: resize handles
#   chrome-annotated.png   one of every annotation tool
#   export-annotated.png   the same selection as it would be saved
#
# Same `open` dance as self-check.sh — see the comment there.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Trimshot.app"
OUT="${1:-$ROOT/build/preview}"
LOG="$OUT/render.log"

# The diagnostic flags are compiled out of release builds on purpose — they would let
# any local process borrow this app's Screen Recording grant. So build a debug bundle.
echo "==> building a debug bundle (diagnostics are release-stripped)"
CONFIG=debug "$ROOT/scripts/bundle.sh" >/dev/null

mkdir -p "$OUT"
rm -f "$LOG"

WAS_RUNNING=0
if pgrep -f "$APP/Contents/MacOS/Trimshot" >/dev/null 2>&1; then
    WAS_RUNNING=1
    pkill -f "$APP/Contents/MacOS/Trimshot" || true
    for _ in $(seq 1 20); do
        pgrep -f "$APP/Contents/MacOS/Trimshot" >/dev/null 2>&1 || break
        sleep 0.1
    done
fi

open -W --stdout "$LOG" --stderr "$LOG" -a "$APP" --args --render-chrome "$OUT" || true

if [ -s "$LOG" ]; then
    cat "$LOG"
else
    echo "(no output — the app may have failed to launch)" >&2
fi

STATUS=0
grep -q "OCR reads Vietnamese" "$LOG" 2>/dev/null || STATUS=1

if [ "$WAS_RUNNING" = "1" ]; then
    open -a "$APP"
fi

echo
echo "note: build/ now holds a DEBUG bundle. Run ./scripts/bundle.sh for a release one."

exit "$STATUS"
