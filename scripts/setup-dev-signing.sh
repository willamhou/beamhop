#!/usr/bin/env bash
# setup-dev-signing.sh — one-shot, idempotent dev-signing setup.
#
# Why (PROGRESS.md §6 pitfall): ad-hoc signing changes the cdhash on every repack, so the
# Accessibility (TCC) grant silently drops and Beamhop has to be re-authorized by hand each
# time. Signing every repack with a STABLE self-signed identity anchors TCC to the certificate
# instead of the cdhash — one grant survives all future rebuilds.
#
# What this script creates (all local, no Apple account, no network):
#   1. A dedicated keychain ~/Library/Keychains/beamhop-sign.keychain-db.
#      Requires BEAMHOP_KEYCHAIN_PASSWORD supplied privately; no default password.
#   2. A self-signed code-signing certificate "Beamhop Sign" (RSA-2048, 10y, EKU=codeSigning).
#   3. Private key imported with partition-list apple-tool:,apple:,codesign: so `codesign` can
#      use it WITHOUT any GUI consent dialog (the login-keychain variant prompts securityd and
#      blocks headless operation — see PROGRESS.md pitfall "TCC binds signature identity").
#
# Trust settings are intentionally NOT set: none are needed for codesigning, for
# `codesign --verify`, or for TCC's designated-requirement matching (TCC anchors on the leaf
# certificate, not on keychain trust). Gatekeeper/spctl will still reject the app — expected;
# Developer ID notarization is a Phase-1-release concern.
#
# Re-run safely: skips any step whose target already exists.
set -euo pipefail

PW="${BEAMHOP_KEYCHAIN_PASSWORD:?Supply the signing password through a secret provider}"
CERT_NAME="Beamhop Sign"
KC="$HOME/Library/Keychains/beamhop-sign.keychain-db"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/beamhop-sign.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# 1) dedicated keychain
if [[ -f "$KC" ]]; then
  echo "keychain exists: $KC"
else
  security create-keychain -p "$PW" beamhop-sign.keychain
  echo "created keychain: $KC"
fi
security unlock-keychain -p "$PW" "$KC"
security set-keychain-settings -lut 86400 "$KC"   # relock after 24h idle, not on sleep

# 2) certificate + key (skip if the cert is already in the keychain)
if security find-certificate -c "$CERT_NAME" "$KC" >/dev/null 2>&1; then
  echo "certificate exists: $CERT_NAME"
else
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$CERT_NAME/C=US" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" 2>/dev/null
  # security import wants traditional PKCS#1 PEM for private keys ("BEGIN RSA PRIVATE KEY")
  openssl rsa -in "$WORK/key.pem" -out "$WORK/key-traditional.pem" 2>/dev/null
  security import "$WORK/key-traditional.pem" -k "$KC" -f openssl -A
  security import "$WORK/cert.pem" -k "$KC" -f openssl -t cert
  echo "imported certificate + key: $CERT_NAME"
fi

# 3) partition list — the step that makes signing consent-dialog-free
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null
echo "partition list set (apple-tool:,apple:,codesign:)"

SHA1="$(security find-certificate -c "$CERT_NAME" -Z "$KC" 2>/dev/null | awk '/SHA-1/ {print $3}')"
echo ""
echo "done. SHA-1: $SHA1"
echo "build-app.sh picks this up automatically; or explicitly:"
echo "  BEAMHOP_CODESIGN_IDENTITY=$SHA1 packaging/build-app.sh"
