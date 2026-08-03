#!/bin/bash
# Cut a release: build, package, stamp the Homebrew cask, and print the commands to publish.
#
#   ./scripts/release.sh 0.1.0
#   UNIVERSAL=1 ./scripts/release.sh 0.1.0     # include an Intel slice
#
# Deliberately stops short of pushing anything. Creating a tag, a GitHub release, and a
# public download are outward-facing and one-way; this prepares them and hands you the exact
# commands.

set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: ./scripts/release.sh <major.minor.patch>" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="anhthienonline/Trimshot"
DMG="$ROOT/build/dist/Trimshot.dmg"
CASK="$ROOT/homebrew/trimshot.rb"

cd "$ROOT"

# --- Preflight ------------------------------------------------------------------------
echo "==> preflight"

if ! grep -q "<string>$VERSION</string>" Resources/Info.plist; then
    CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
    echo "  ✗ Info.plist says $CURRENT, you asked for $VERSION" >&2
    echo "    /usr/libexec/PlistBuddy -c \"Set :CFBundleShortVersionString $VERSION\" Resources/Info.plist" >&2
    exit 1
fi
echo "  ✓ Info.plist version matches"

if ! grep -q "^## $VERSION " CHANGELOG.md; then
    echo "  ✗ CHANGELOG.md has no '## $VERSION' section" >&2
    exit 1
fi
echo "  ✓ CHANGELOG has an entry"

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "  ! working tree is dirty — commit before tagging" >&2
fi

echo "==> checks"
swift build -c release 2>&1 | tail -1
swift run TrimshotChecks 2>&1 | tail -1

# --- Build ----------------------------------------------------------------------------
echo "==> packaging"
"$ROOT/scripts/package.sh" >/dev/null
test -f "$DMG" || { echo "error: $DMG missing" >&2; exit 1; }

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
SIZE_KB=$(( ($(stat -f%z "$DMG") + 512) / 1024 ))
ARCHS=$(lipo -archs "$ROOT/build/Trimshot.app/Contents/MacOS/Trimshot")
echo "  Trimshot.dmg  ${SIZE_KB} KB  [$ARCHS]"
echo "  sha256        $SHA"

# --- Stamp the cask -------------------------------------------------------------------
echo "==> stamping $CASK"
sed -i '' \
    -e "s|^  version \".*\"$|  version \"$VERSION\"|" \
    -e "s|^  sha256 \".*\"$|  sha256 \"$SHA\"|" \
    "$CASK"
grep -E "^  (version|sha256) " "$CASK" | sed 's/^/    /'

# --- What is left for a human ---------------------------------------------------------
cat <<EOS

Prepared. Nothing has been pushed.

Before publishing, run the two checks that CI cannot — they need a Screen Recording grant:

    ./scripts/self-check.sh
    ./scripts/render-chrome.sh

Then publish:

    git commit -am "Release $VERSION"
    git tag -a "v$VERSION" -m "Trimshot $VERSION"
    git push origin main --tags
    gh release create "v$VERSION" "$DMG" \\
        --repo "$REPO" \\
        --title "Trimshot $VERSION" \\
        --notes-file CHANGELOG.md

Update the Homebrew tap (a separate repo, github.com/anhthienonline/homebrew-Trimshot):

    cp homebrew/trimshot.rb ../homebrew-Trimshot/Casks/trimshot.rb
    cd ../homebrew-Trimshot
    git commit -am "trimshot $VERSION" && git push

Then refresh the promo site so its download link points at the new build:

    ./scripts/site.sh --prod

Reminder: the cask does not skip Gatekeeper. Homebrew quarantines its downloads by default,
so a brew install of an un-notarised build still needs the one-time approval in System
Settings. Notarising is the only thing that removes that step.
EOS
