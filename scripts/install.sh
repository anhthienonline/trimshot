#!/bin/bash
# Install the app somewhere permanent and start it.
#
#   ./scripts/install.sh              # /Applications, or ~/Applications if not writable
#   ./scripts/install.sh ~/Applications
#
# Why this matters beyond tidiness: `scripts/bundle.sh` wipes build/ on every run, so a
# login item pointing there breaks the next time the Mac boots. The app only turns
# launch-at-login on for itself when it is running from /Applications or ~/Applications.
#
# The Screen Recording grant follows the app: its designated requirement is
# `identifier "…" and certificate leaf = H"…"`, which has nothing to do with the path.

set -euo pipefail

APP_NAME="Trimshot.app"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/build/$APP_NAME"

if [ $# -ge 1 ]; then
    DESTINATION_DIR="$1"
elif [ -w /Applications ]; then
    DESTINATION_DIR="/Applications"
else
    DESTINATION_DIR="$HOME/Applications"
fi
DESTINATION="$DESTINATION_DIR/$APP_NAME"

echo "==> building a release bundle"
CONFIG=release "$ROOT/scripts/bundle.sh" >/dev/null

if [ ! -d "$SOURCE" ]; then
    echo "error: $SOURCE not found" >&2
    exit 1
fi

# Quit both the build copy and any already-installed copy, or the running instance keeps a
# stale menu bar icon around and `cp` can fail mid-bundle.
pkill -f "$SOURCE/Contents/MacOS/Trimshot" 2>/dev/null || true
pkill -f "$DESTINATION/Contents/MacOS/Trimshot" 2>/dev/null || true
sleep 1

echo "==> installing to $DESTINATION"
mkdir -p "$DESTINATION_DIR"
rm -rf "$DESTINATION"
cp -R "$SOURCE" "$DESTINATION"

echo "==> starting it"
open -a "$DESTINATION"
sleep 2

if pgrep -f "$DESTINATION/Contents/MacOS/Trimshot" >/dev/null 2>&1; then
    echo "✓ running from $DESTINATION"
    echo "  It registers itself as a login item on this first run, so it will come back"
    echo "  after a restart. Toggle that in the menu bar icon › Settings…"
else
    echo "✗ it did not stay running — check Console.app for com.thienho.trimshot" >&2
    exit 1
fi
