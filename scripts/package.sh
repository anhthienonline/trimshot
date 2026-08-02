#!/bin/bash
# Build a universal release and wrap it in a zip (and a dmg) for another Mac.
#
#   ./scripts/package.sh                                # this Mac's architecture only
#   UNIVERSAL=1 ./scripts/package.sh                    # also run on Intel Macs
#   NOTARIZE_PROFILE=my-profile ./scripts/package.sh    # also notarize + staple
#
# Native-only by default: the build is quicker, the download is smaller, and an arm64 slice
# is all Apple Silicon Macs need. Set UNIVERSAL=1 if any recipient is on an Intel Mac —
# without it they cannot launch the app at all.
#
# Output: build/dist/Trimshot.zip and .dmg
#
# WITHOUT notarization the receiving Mac will refuse to open it on the first try —
# "Apple could not verify …is free of malware" — because the app is signed with a local
# self-signed certificate, not a Developer ID. The person on the other end has to go to
# System Settings › Privacy & Security, find the blocked-app notice, and click
# "Open Anyway". macOS 15 removed the old Control-click → Open shortcut, so that panel is
# now the only route. They only have to do it once.
#
# WITH notarization it opens with no warning at all. That needs a paid Apple Developer
# account and a "Developer ID Application" certificate in the keychain, then a stored
# notarytool profile:
#
#   xcrun notarytool store-credentials my-profile \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
# and SIGN_IDENTITY_NAME set to that Developer ID certificate when bundling.
#
# Either way, Screen Recording has to be granted per machine — TCC permissions are local
# and cannot be shipped.
#
# ICON, if the recipients are not all on macOS 26: the shipped artwork is full-bleed because
# macOS 26 wraps every legacy .icns in its own squircle. Older macOS does no such thing and
# will draw it as a hard-edged square. For those machines regenerate the icon first with the
# self-contained silhouette, then package:
#
#   swift scripts/make-icon.swift --framed && ./scripts/package.sh
#   swift scripts/make-icon.swift            # put the macOS 26 version back afterwards

set -euo pipefail

APP_NAME="Trimshot"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/$APP_NAME.app"
DIST="$ROOT/build/dist"
ZIP="$DIST/$APP_NAME.zip"
DMG="$DIST/$APP_NAME.dmg"

cd "$ROOT"

echo "==> building a release${UNIVERSAL:+ (universal)}"
UNIVERSAL="${UNIVERSAL:-0}" CONFIG=release "$ROOT/scripts/bundle.sh" >/dev/null

if [ ! -d "$APP" ]; then
    echo "error: $APP not found" >&2
    exit 1
fi

ARCHS="$(lipo -archs "$APP/Contents/MacOS/Trimshot")"
echo "    architectures: $ARCHS"
case "$ARCHS" in
    *x86_64*) ;;
    *) echo "    (Apple Silicon only — set UNIVERSAL=1 if anyone is on an Intel Mac)" ;;
esac

echo "==> verifying the signature"
codesign --verify --deep --strict --verbose=1 "$APP"

rm -rf "$DIST"
mkdir -p "$DIST"

# ditto, not zip: it preserves the bundle's symlinks and extended attributes, so the code
# signature survives the round trip. A plain `zip` can invalidate it.
echo "==> zipping"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> building the dmg"
DMG_STAGE="$(mktemp -d)"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$DMG_STAGE" \
    -ov -format UDZO "$DMG"
rm -rf "$DMG_STAGE"

if [ -n "${NOTARIZE_PROFILE:-}" ]; then
    echo "==> notarizing (this waits on Apple, usually a couple of minutes)"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARIZE_PROFILE" --wait
    # The ticket is stapled to the .app and the .dmg, never to a zip — a zip has nowhere
    # to keep it. So staple, then rebuild the zip from the stapled app.
    xcrun stapler staple "$APP"
    xcrun stapler staple "$DMG"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "==> checking Gatekeeper's verdict"
    spctl --assess --type execute --verbose=2 "$APP"
else
    echo
    echo "note: not notarized. Gatekeeper on the receiving Mac will block the first launch;"
    echo "      the user must allow it in System Settings › Privacy & Security."
    echo "      Set NOTARIZE_PROFILE to notarize — see the comments in this script."
fi

echo
echo "✓ $ZIP"
echo "✓ $DMG"
du -h "$ZIP" "$DMG" | sed 's/^/  /'
