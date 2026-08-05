#!/bin/bash
# Rewrite the project's URLs everywhere they appear.
#
#   ./scripts/set-urls.sh --owner anhthienonline --repo Trimshot
#   ./scripts/set-urls.sh --site https://trimshot-abc123.vercel.app
#   ./scripts/set-urls.sh --site ''          # back to repository links only
#
# The current values live in scripts/urls.env; this reads them, rewrites the old strings to
# the new ones across the tree, and writes the new values back. Idempotent.
#
# Why a script: the owner and repository name are baked into the Settings window, the promo
# site, the privacy page, the Homebrew cask, the release script and four documents — nineteen
# occurrences the first time this had to change. One of them was going to be missed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/scripts/urls.env"
cd "$ROOT"

# shellcheck source=/dev/null
source "$ENV_FILE"
OLD_OWNER="$GITHUB_OWNER"
OLD_REPO="$GITHUB_REPO"
OLD_SITE="$SITE_URL"

NEW_OWNER="$OLD_OWNER"
NEW_REPO="$OLD_REPO"
NEW_SITE="$OLD_SITE"
SITE_GIVEN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --owner) NEW_OWNER="$2"; shift 2 ;;
        --repo)  NEW_REPO="$2"; shift 2 ;;
        --site)  NEW_SITE="$2"; SITE_GIVEN=1; shift 2 ;;
        *) echo "error: unknown option $1" >&2; exit 1 ;;
    esac
done

FILES=$(git ls-files '*.md' '*.html' '*.swift' '*.sh' '*.rb' '*.yml' 2>/dev/null \
    | grep -v '^scripts/set-urls.sh$' || true)
if [ -z "$FILES" ]; then
    echo "error: no tracked files to rewrite" >&2
    exit 1
fi

rewrite() {
    local from="$1" to="$2"
    [ "$from" = "$to" ] && return 0
    [ -z "$from" ] && return 0
    printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 sed -i '' "s|$from|$to|g"
}

echo "==> repository"
if [ "$OLD_OWNER/$OLD_REPO" != "$NEW_OWNER/$NEW_REPO" ]; then
    rewrite "github.com/$OLD_OWNER/$OLD_REPO" "github.com/$NEW_OWNER/$NEW_REPO"
    # The cask's `verified:` stanza carries the host and path without a scheme.
    rewrite "$OLD_OWNER/$OLD_REPO" "$NEW_OWNER/$NEW_REPO"
    # The Homebrew tap is a second repository, named homebrew-<repo>. The owner/repo pattern
    # above does not reach it, which is exactly what the stale check caught the first time.
    rewrite "$OLD_OWNER/homebrew-$OLD_REPO" "$NEW_OWNER/homebrew-$NEW_REPO"
    rewrite "homebrew-$OLD_REPO" "homebrew-$NEW_REPO"
    # The author's profile link carries the owner with no repository after it — in the Settings
    # window, the site's Contact section and its footer. Every pattern above needs a repo name
    # to match, so this has to come last: by now the owner/repo paths are already rewritten,
    # which means whatever still says `github.com/<old owner>` is a bare profile URL.
    rewrite "github.com/$OLD_OWNER" "github.com/$NEW_OWNER"
    echo "    $OLD_OWNER/$OLD_REPO → $NEW_OWNER/$NEW_REPO"
else
    echo "    unchanged ($NEW_OWNER/$NEW_REPO)"
fi

echo "==> site"
if [ "$SITE_GIVEN" = "1" ] && [ "$OLD_SITE" != "$NEW_SITE" ]; then
    if [ -n "$OLD_SITE" ] && [ -n "$NEW_SITE" ]; then
        rewrite "$OLD_SITE" "$NEW_SITE"
        echo "    $OLD_SITE → $NEW_SITE"
    elif [ -n "$NEW_SITE" ]; then
        echo "    now $NEW_SITE — the Settings window and PRIVACY.md need the link added by hand"
        echo "    once, since there was no old URL to substitute for."
    else
        echo "    cleared"
    fi
else
    echo "    unchanged (${NEW_SITE:-none yet})"
fi

cat > "$ENV_FILE" <<EOF
# The canonical URLs, in one place. Edit via scripts/set-urls.sh, not by hand — the values
# are baked into the app's Settings window, the site, the Homebrew cask, the release script
# and four documents, and hand-editing nineteen occurrences is how one gets missed.
#
# SITE_URL is empty until the site is actually deployed. While it is empty the app links to
# the repository instead, because a link that 404s is worse than a link that is not there.
GITHUB_OWNER=$NEW_OWNER
GITHUB_REPO=$NEW_REPO
SITE_URL=$NEW_SITE
EOF

echo "==> checking nothing stale survived"
STALE=$(printf '%s\n' "$FILES" | tr '\n' '\0' \
    | xargs -0 grep -l "$OLD_OWNER" 2>/dev/null || true)
if [ "$OLD_OWNER" != "$NEW_OWNER" ] && [ -n "$STALE" ]; then
    echo "    ✗ still mentioning $OLD_OWNER:" >&2
    printf '%s\n' "$STALE" | sed 's/^/      /' >&2
    exit 1
fi
echo "    ✓ clean"
echo
echo "The Settings window is compiled, so rebuild and reinstall for the app to pick this up:"
echo "    ./scripts/install.sh"
