#!/bin/bash
# Assemble a runnable .app bundle without Xcode (Command Line Tools only).
#
#   ./scripts/bundle.sh            release build, native arch
#   CONFIG=debug ./scripts/bundle.sh
#   UNIVERSAL=1 ./scripts/bundle.sh
#
# Signing: macOS ties Screen Recording permission (TCC) to the code signature.
# An ad-hoc signature changes on every rebuild, so the permission gets revoked
# each time. Run ./scripts/create-signing-cert.sh once and the permission sticks.

set -euo pipefail

APP_NAME="Trimshot"
DISPLAY_NAME="Trimshot"
BUNDLE_ID="com.thienho.trimshot"
SIGN_IDENTITY_NAME="${SIGN_IDENTITY_NAME:-Trimshot Dev}"
CONFIG="${CONFIG:-release}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
APP="$OUT/$DISPLAY_NAME.app"

cd "$ROOT"

mkdir -p "$OUT"
LIPO_TEMP="$OUT/.universal-$APP_NAME"
trap 'rm -f "$LIPO_TEMP"' EXIT

if [ "${UNIVERSAL:-0}" = "1" ]; then
    # `swift build --arch arm64 --arch x86_64` in one go needs xcbuild, which ships only
    # with full Xcode. Building each slice on its own works with Command Line Tools, so
    # do that and lipo them together.
    for arch in arm64 x86_64; do
        echo "==> swift build -c $CONFIG --arch $arch"
        swift build -c "$CONFIG" --arch "$arch"
    done
    ARM_BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/$APP_NAME"
    X86_BIN="$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)/$APP_NAME"
    echo "==> lipo -create arm64 + x86_64"
    lipo -create -output "$LIPO_TEMP" "$ARM_BIN" "$X86_BIN"
    BIN="$LIPO_TEMP"
    BIN_DIR="$(dirname "$ARM_BIN")"
else
    echo "==> swift build -c $CONFIG"
    swift build -c "$CONFIG"
    BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
    BIN="$BIN_DIR/$APP_NAME"
fi

if [ ! -x "$BIN" ]; then
    echo "error: binary not found at $BIN" >&2
    exit 1
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Info.plist declares CFBundleIconFile, so the icon has to be there or Finder falls back
# to the generic application icon. Regenerate it with: swift scripts/make-icon.swift
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "    note: Resources/AppIcon.icns missing — run 'swift scripts/make-icon.swift'" >&2
fi

# SwiftPM emits resource bundles next to the binary; carry them along if present.
for b in "$BIN_DIR"/*.bundle; do
    [ -e "$b" ] || continue
    cp -R "$b" "$APP/Contents/Resources/"
done

echo "==> signing"
# No -v: the dev certificate is intentionally untrusted, and -v hides untrusted
# identities. codesign only needs the identity to exist.
if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$SIGN_IDENTITY_NAME\""; then
    codesign --force --deep --options runtime \
        --identifier "$BUNDLE_ID" \
        --sign "$SIGN_IDENTITY_NAME" "$APP"
    echo "    signed with '$SIGN_IDENTITY_NAME' — Screen Recording permission persists across rebuilds"
else
    codesign --force --deep --identifier "$BUNDLE_ID" --sign - "$APP"
    cat >&2 <<EOF
    WARNING: signed ad-hoc. macOS will ask for Screen Recording permission again
    after every rebuild. Fix it with:  ./scripts/create-signing-cert.sh
EOF
fi

echo "==> done: $APP"
echo "    open '$APP'"
