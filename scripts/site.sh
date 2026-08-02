#!/bin/bash
# Assemble the promo site in site/ and, optionally, deploy it to Vercel.
#
#   ./scripts/site.sh                 # build the dmg and stage it into site/
#   ./scripts/site.sh --preview       # …then deploy a Vercel preview URL
#   ./scripts/site.sh --prod          # …then deploy to production
#
# The disk image is a build artifact, so it is staged rather than committed — see
# site/.gitignore. Run this before every deploy or the download link 404s.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE="$ROOT/site"
DMG_SOURCE="$ROOT/build/dist/Trimshot.dmg"

cd "$ROOT"

echo "==> packaging the app"
"$ROOT/scripts/package.sh" >/dev/null

if [ ! -f "$DMG_SOURCE" ]; then
    echo "error: $DMG_SOURCE not found" >&2
    exit 1
fi

cp "$DMG_SOURCE" "$SITE/Trimshot.dmg"
SIZE_KB=$(( ($(stat -f%z "$SITE/Trimshot.dmg") + 512) / 1024 ))
echo "    staged site/Trimshot.dmg — ${SIZE_KB} KB"

# The page advertises the download size in three places. Rewrite them from the file that
# was actually built — a hand-typed number is wrong the first time the binary changes, and
# on a page whose whole argument is "the numbers are exact" that is worse than saying
# nothing.
# One expression covering every element that ends in a KB figure, rather than one pattern
# per wrapper — the first version matched two of the three and left a stale number behind.
sed -i '' "s|>[0-9][0-9]* KB<|>${SIZE_KB} KB<|g" "$SITE/index.html"

STALE=$(grep -o '>[0-9][0-9]* KB<' "$SITE/index.html" | grep -cv ">${SIZE_KB} KB<" || true)
if [ "$STALE" -ne 0 ]; then
    echo "error: $STALE size mention(s) did not update" >&2
    exit 1
fi
echo "    index.html advertises ${SIZE_KB} KB in $(grep -c ">${SIZE_KB} KB<" "$SITE/index.html") place(s)"

case "${1:-}" in
    --preview)
        echo "==> vercel deploy (preview)"
        ( cd "$SITE" && npx --yes vercel deploy )
        ;;
    --prod)
        echo "==> vercel deploy (production)"
        ( cd "$SITE" && npx --yes vercel deploy --prod )
        ;;
    "")
        echo
        echo "Ready. Deploy with:"
        echo "    ./scripts/site.sh --preview     # a throwaway URL to check first"
        echo "    ./scripts/site.sh --prod        # the real thing"
        echo
        echo "First run asks you to log in and link the directory to a Vercel project."
        ;;
    *)
        echo "error: unknown option $1" >&2
        exit 1
        ;;
esac
