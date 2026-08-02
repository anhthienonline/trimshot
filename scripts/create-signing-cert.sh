#!/bin/bash
# Create a self-signed code-signing certificate, once, so rebuilds keep their
# Screen Recording permission.
#
# Why this exists: macOS ties a TCC permission to the app's designated requirement. An
# ad-hoc signature (`codesign -s -`) is derived from the binary's hash, so it changes on
# every build and macOS treats each build as a brand new app — meaning you re-grant
# Screen Recording after every single rebuild. Signing with a stable certificate makes
# the requirement `identifier "…" and certificate leaf = H"…"`, which does not change.
#
# Run once:  ./scripts/create-signing-cert.sh
# Undo:      security delete-identity -c "Trimshot Dev"
#
# No password prompt: the certificate is never marked as trusted, because codesign only
# needs the identity to exist, not to chain to a trusted root. `security find-identity`
# will report it as CSSMERR_TP_NOT_TRUSTED — that is expected and harmless here.

set -euo pipefail

NAME="${SIGN_IDENTITY_NAME:-Trimshot Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

EXISTING="$(security find-identity -p codesigning 2>/dev/null | grep -cF "\"$NAME\"" || true)"
if [ "$EXISTING" -gt 1 ]; then
    # codesign refuses to run when a name matches more than one identity.
    echo "✗ $EXISTING certificates are named '$NAME'. Delete all but one:" >&2
    security find-identity -p codesigning 2>/dev/null | grep -F "\"$NAME\"" >&2
    echo "    security delete-identity -Z <the SHA-1 hash to remove>" >&2
    exit 1
fi
if [ "$EXISTING" -eq 1 ]; then
    echo "✓ '$NAME' already exists — nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# LibreSSL refuses to export a PKCS#12 with an empty password in a way the macOS
# Security framework will accept ("MAC verification failed"), so use a throwaway one.
TRANSFER_PASSWORD="$(openssl rand -hex 16)"

echo "==> generating certificate"
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
    -keyout "$WORK/key.pem" \
    -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    2>/dev/null

openssl pkcs12 -export \
    -inkey "$WORK/key.pem" \
    -in "$WORK/cert.pem" \
    -out "$WORK/cert.p12" \
    -passout pass:"$TRANSFER_PASSWORD"

echo "==> importing into the login keychain"
# -T /usr/bin/codesign -A lets codesign use the key without a keychain prompt per build.
security import "$WORK/cert.p12" \
    -k "$KEYCHAIN" \
    -P "$TRANSFER_PASSWORD" \
    -T /usr/bin/codesign \
    -A

if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$NAME\""; then
    echo "✓ '$NAME' is ready. ./scripts/bundle.sh will pick it up automatically."
else
    echo "✗ the identity did not show up in 'security find-identity -p codesigning'." >&2
    exit 1
fi
