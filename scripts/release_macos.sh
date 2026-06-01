#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_PRODUCTS_DIR="build/macos/Build/Products/Release"
APP_NAME="${APP_NAME:-}"
APP_PATH="${APP_PATH:-}"
SKIP_BUILD="${SKIP_BUILD:-0}"
APP_DISPLAY_NAME_OVERRIDE="${APP_DISPLAY_NAME_OVERRIDE:-}"
ENTITLEMENTS_PATH="macos/Runner/Release.entitlements"
OUTPUT_DIR="build/macos/dist"
KEYCHAIN_PROFILE="${APPLE_NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

discover_app_path() {
  if [[ -n "$APP_PATH" ]]; then
    printf '%s\n' "$APP_PATH"
    return
  fi

  if [[ -n "$APP_NAME" ]]; then
    local candidate="${BUILD_PRODUCTS_DIR}/${APP_NAME}.app"
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  fi

  # bash 3.x compatible (macOS default bash) — no `mapfile`.
  local app_paths=()
  while IFS= read -r line; do
    app_paths+=("$line")
  done < <(find "$BUILD_PRODUCTS_DIR" -maxdepth 1 -name '*.app' -type d | sort)

  if [[ "${#app_paths[@]}" -eq 0 ]]; then
    die "no app bundle found in ${BUILD_PRODUCTS_DIR}; set APP_PATH explicitly if your build uses a custom output location"
  fi

  if [[ "${#app_paths[@]}" -gt 1 ]]; then
    die "multiple app bundles found in ${BUILD_PRODUCTS_DIR}; set APP_PATH explicitly"
  fi

  printf '%s\n' "${app_paths[0]}"
}

bundle_display_name() {
  local app_path="$1"
  local plist_path="${app_path}/Contents/Info.plist"
  local display_name

  display_name="$(plutil -extract CFBundleName raw -o - "$plist_path" 2>/dev/null || true)"
  if [[ -n "$display_name" ]]; then
    printf '%s\n' "$display_name"
    return
  fi

  printf '%s\n' "$(basename "$app_path" .app)"
}

discover_identity() {
  if [[ -n "${APPLE_DEVELOPER_IDENTITY:-}" ]]; then
    printf '%s\n' "$APPLE_DEVELOPER_IDENTITY"
    return
  fi

  local identity
  identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"

  if [[ -z "$identity" ]]; then
    die "no Developer ID Application certificate found; set APPLE_DEVELOPER_IDENTITY explicitly"
  fi

  printf '%s\n' "$identity"
}

submit_for_notarization() {
  local artifact_path="$1"

  if [[ -n "$KEYCHAIN_PROFILE" ]]; then
    xcrun notarytool submit "$artifact_path" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    return
  fi

  [[ -n "$APPLE_ID" ]] || die "set APPLE_NOTARY_PROFILE or APPLE_ID"
  [[ -n "$APPLE_TEAM_ID" ]] || die "set APPLE_NOTARY_PROFILE or APPLE_TEAM_ID"
  [[ -n "$APPLE_APP_SPECIFIC_PASSWORD" ]] || die "set APPLE_NOTARY_PROFILE or APPLE_APP_SPECIFIC_PASSWORD"

  xcrun notarytool submit \
    "$artifact_path" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
}

create_dmg() {
  local app_path="$1"
  local dmg_path="$2"
  local volume_name="$3"
  local bundle_name="$4"
  local staging_dir

  staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/viberadar-dmg.XXXXXX")"

  rm -f "$dmg_path"
  ditto "$app_path" "${staging_dir}/${bundle_name}"
  ln -s /Applications "${staging_dir}/Applications"

  hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path"

  rm -rf "$staging_dir"
}

require_command flutter
require_command codesign
require_command ditto
require_command hdiutil
require_command plutil
require_command security
require_command spctl
require_command xcrun

IDENTITY="$(discover_identity)"

echo "Building macOS release..."
if [[ "$SKIP_BUILD" == "1" ]]; then
  echo "Skipping build because SKIP_BUILD=1"
else
  flutter build macos --release
fi

APP_PATH="$(discover_app_path)"
[[ -d "$APP_PATH" ]] || die "expected app bundle at $APP_PATH"
[[ -f "$ENTITLEMENTS_PATH" ]] || die "missing entitlements file at $ENTITLEMENTS_PATH"

APP_DISPLAY_NAME="$(bundle_display_name "$APP_PATH")"
if [[ -n "$APP_DISPLAY_NAME_OVERRIDE" ]]; then
  APP_DISPLAY_NAME="$APP_DISPLAY_NAME_OVERRIDE"
fi
ARTIFACT_BASENAME="${ARTIFACT_BASENAME:-$APP_DISPLAY_NAME}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-$APP_DISPLAY_NAME}"
NOTARY_ZIP_PATH="${OUTPUT_DIR}/${ARTIFACT_BASENAME}-notary.zip"
FINAL_ZIP_PATH="${OUTPUT_DIR}/${ARTIFACT_BASENAME}-macos.zip"
FINAL_DMG_PATH="${OUTPUT_DIR}/${ARTIFACT_BASENAME}.dmg"

mkdir -p "$OUTPUT_DIR"
rm -f "$NOTARY_ZIP_PATH" "$FINAL_ZIP_PATH" "$FINAL_DMG_PATH"

echo "Signing app with Developer ID identity:"
echo "  $IDENTITY"
xattr -cr "$APP_PATH" || true
codesign \
  --force \
  --deep \
  --sign "$IDENTITY" \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS_PATH" \
  "$APP_PATH"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Packaging for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP_PATH"

echo "Submitting notarization request..."
submit_for_notarization "$NOTARY_ZIP_PATH"

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

echo "Running Gatekeeper check..."
spctl -a -vvv --type exec "$APP_PATH"

echo "Writing distributable archive..."
rm -f "$NOTARY_ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP_PATH"

echo "Creating DMG..."
create_dmg "$APP_PATH" "$FINAL_DMG_PATH" "$DMG_VOLUME_NAME" "${APP_DISPLAY_NAME}.app"

echo "Submitting DMG for notarization..."
submit_for_notarization "$FINAL_DMG_PATH"

echo "Stapling DMG ticket..."
xcrun stapler staple "$FINAL_DMG_PATH"

echo "Validating DMG notarization ticket..."
xcrun stapler validate "$FINAL_DMG_PATH"

echo ""
echo "Release artifacts ready:"
echo "  $FINAL_ZIP_PATH"
echo "  $FINAL_DMG_PATH"
echo ""
echo "Upload the DMG to the hosting site. Do not upload the raw app bundle from ${BUILD_PRODUCTS_DIR}."
