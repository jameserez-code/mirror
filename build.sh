#!/bin/bash
set -e

APP_NAME="Mirror"
BUILD_DIR=".build/release"
APP_DIR="/Applications/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "Building ${APP_NAME}..."
swift build -c release

echo "Creating app bundle at ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"

# Info.plist
cat > "${CONTENTS}/Info.plist" << INFOEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.mirror.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Mirror captures your screen during recordings to analyze your workflows.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Mirror uses accessibility access to capture keyboard and mouse events during recordings.</string>
</dict>
</plist>
INFOEOF

# Copy entitlements
cp entitlements.plist "${RESOURCES}/"

# Copy HTML resources
cp Mirror/ui.html "${RESOURCES}/"
cp Mirror/settings.html "${RESOURCES}/"

# Codesign with consistent identity (prevents re-prompting for permissions)
SIGN_IDENTITY="Mirror Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "${SIGN_IDENTITY}"; then
    echo "Signing with identity: ${SIGN_IDENTITY}"
    # Grant codesign access to the private key (prevents interactive prompt)
    security unlock-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null || true
    codesign --force --deep --sign "${SIGN_IDENTITY}" --entitlements entitlements.plist --timestamp=none "${APP_DIR}" 2>&1 || {
        echo "Signing failed (keychain access prompt?) — falling back to ad-hoc"
        codesign --force --deep --sign - --entitlements entitlements.plist "${APP_DIR}"
    }
else
    echo "No '${SIGN_IDENTITY}' cert found — using ad-hoc signing."
    echo "Run: scripts/create-dev-cert.sh to create a persistent identity."
    codesign --force --deep --sign - --entitlements entitlements.plist "${APP_DIR}"
fi

# Strip quarantine so macOS doesn't flag each rebuild as a new download
xattr -cr "${APP_DIR}"

# Verify signature
if codesign -v "${APP_DIR}" 2>/dev/null; then
    echo "Signature valid"
else
    echo "Signature verification failed"
fi

echo "Mirror installed to ${APP_DIR}"
echo "Launch with: open ${APP_DIR}"
