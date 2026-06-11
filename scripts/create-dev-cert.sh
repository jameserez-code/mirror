#!/bin/bash
# One-time setup: creates a self-signed code signing identity named "Mirror Dev"
# This lets macOS recognize the app across rebuilds so Accessibility permission sticks.
set -e

CERT_NAME="Mirror Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo "=== Creating code signing identity: '${CERT_NAME}' ==="

# Clean up any previous broken entries
security delete-certificate -c "${CERT_NAME}" "${KEYCHAIN}" 2>/dev/null || true

# Generate key & certificate
openssl genrsa -out /tmp/mirror-key.pem 2048 2>/dev/null
openssl req -new -x509 -key /tmp/mirror-key.pem -out /tmp/mirror-cert.pem -days 3650 \
  -subj "/CN=${CERT_NAME}" 2>/dev/null

# Combine into a single PEM (cert first, then key) for identity import
cat /tmp/mirror-cert.pem /tmp/mirror-key.pem > /tmp/mirror-identity.pem

# Import as a paired identity
security import /tmp/mirror-identity.pem -k "${KEYCHAIN}" -A -T /usr/bin/codesign -T /usr/bin/security 2>/dev/null

# Trust for code signing
security add-trusted-cert -d -r trustRoot -p codeSign -k "${KEYCHAIN}" /tmp/mirror-cert.pem 2>/dev/null

# Cleanup
rm -f /tmp/mirror-key.pem /tmp/mirror-cert.pem /tmp/mirror-identity.pem

# Verify
if security find-identity -v -p codesigning 2>/dev/null | grep -q "${CERT_NAME}"; then
    echo "SUCCESS: '${CERT_NAME}' identity ready for code signing."
else
    echo "FAILED: identity not found. Use the manual approach:"
    echo "  Keychain Access → Certificate Assistant → Create Certificate"
    echo "  Name: Mirror Dev → Type: Code Signing → Create"
fi