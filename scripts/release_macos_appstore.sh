#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ARCHIVE_PATH="${ARCHIVE_PATH:-build/archives/VibeRadar-macOS.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-build/macos/appstore}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-macos/ExportOptions-appstore.plist}"
WORKSPACE="macos/Runner.xcworkspace"
SCHEME="Runner"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM_ID="${APPLE_TEAM_ID:-36TZ8UKL8W}"
ASC_KEY_ID="${ASC_KEY_ID:-R7BYLGVT9L}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-2d61090e-20f6-4c5c-9868-b0ecb45d51ad}"
PUBSPEC_VERSION="$(awk '/^version:/{print $2; exit}' pubspec.yaml)"
BUILD_NAME="${BUILD_NAME:-${PUBSPEC_VERSION%%+*}}"
BUILD_NUMBER="${BUILD_NUMBER:-${PUBSPEC_VERSION##*+}}"
FIREBASE_APP_CHECK_ENABLED="${FIREBASE_APP_CHECK_ENABLED:-false}"

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

has_identity() {
  local pattern="$1"
  security find-identity -v -p codesigning | grep -q "$pattern"
}

require_command flutter
require_command plutil
require_command security
require_command xcodebuild
require_command xcrun

[[ -d "$WORKSPACE" ]] || die "missing workspace: $WORKSPACE"
[[ -f "$EXPORT_OPTIONS_PLIST" ]] || die "missing export options: $EXPORT_OPTIONS_PLIST"

if ! has_identity "3rd Party Mac Developer Application:" && ! has_identity "Apple Distribution:"; then
  die "missing a Mac App Store signing identity; install an Apple Distribution or 3rd Party Mac Developer Application certificate"
fi

if ! security find-identity -v -p codesigning | grep -q "$TEAM_ID"; then
  die "no codesigning identity was found for team $TEAM_ID"
fi

echo "Preparing Flutter macOS release inputs..."
flutter pub get
flutter build macos \
  --release \
  --config-only \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER" \
  --dart-define=FIREBASE_APP_CHECK_ENABLED="$FIREBASE_APP_CHECK_ENABLED"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"

echo "Archiving macOS app for App Store Connect..."
xcodebuild \
  -quiet \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  FLUTTER_BUILD_NAME="$BUILD_NAME" \
  FLUTTER_BUILD_NUMBER="$BUILD_NUMBER" \
  archive

echo "Exporting App Store Connect package..."
xcodebuild \
  -quiet \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

PKG_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -type f -name '*.pkg' -print -quit)"
[[ -n "$PKG_PATH" ]] || die "export completed but no .pkg was produced in $EXPORT_PATH"

echo "Validating package with App Store Connect..."
xcrun altool \
  --validate-app \
  -f "$PKG_PATH" \
  -t macos \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo ""
echo "Mac App Store package ready:"
echo "  $PKG_PATH"
echo ""
echo "Upload with:"
echo "  xcrun altool --upload-app -f \"$PKG_PATH\" -t macos --apiKey \"$ASC_KEY_ID\" --apiIssuer \"$ASC_ISSUER_ID\""
