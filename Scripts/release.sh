#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DERIVED_DATA="$PROJECT_DIR/.xcode-release"
DIST_DIR="$PROJECT_DIR/.build/release"
APP_PATH="$DERIVED_DATA/Build/Products/Release/Flipper Dashboard.app"
DMG_PATH="$DIST_DIR/Flipper-Dashboard.dmg"
CHECKSUM_PATH="$DIST_DIR/Flipper-Dashboard.dmg.sha256"
VERSION="${FLIPPER_VERSION:-1.0.0}"
SIGNING_IDENTITY="${FLIPPER_SIGNING_IDENTITY:?Set FLIPPER_SIGNING_IDENTITY to a Developer ID Application certificate}"
DEVELOPMENT_TEAM="${FLIPPER_DEVELOPMENT_TEAM:?Set FLIPPER_DEVELOPMENT_TEAM to your Apple team ID}"
NOTARY_PROFILE="${FLIPPER_NOTARY_PROFILE:?Set FLIPPER_NOTARY_PROFILE to a notarytool Keychain profile}"

for tool in xcodegen xcodebuild hdiutil codesign xcrun; do
    command -v "$tool" >/dev/null || {
        print -u2 "Missing required tool: $tool"
        exit 1
    }
done

xcodegen generate --quiet --spec "$PROJECT_DIR/project.yml" --project "$PROJECT_DIR"
xcodebuild \
    -quiet \
    -project "$PROJECT_DIR/FlipperDashboard.xcodeproj" \
    -scheme DashboardBar \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGNING_REQUIRED=YES \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    MARKETING_VERSION="$VERSION" \
    build

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
signature_details="$(codesign -dvvv --verbose=4 "$APP_PATH" 2>&1)"
print -r -- "$signature_details" | grep -F "Authority=$SIGNING_IDENTITY" >/dev/null
print -r -- "$signature_details" | grep -F "TeamIdentifier=$DEVELOPMENT_TEAM" >/dev/null
print -r -- "$signature_details" | grep -E 'flags=.*runtime' >/dev/null
print -r -- "$signature_details" | grep -F 'Timestamp=' >/dev/null
if codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q 'com.apple.security.get-task-allow'; then
    print -u2 "Release contains the forbidden get-task-allow entitlement"
    exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH" "$CHECKSUM_PATH"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT

ditto "$APP_PATH" "$staging_dir/Flipper Dashboard.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create \
    -volname "Flipper Dashboard" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
notary_result="$(xcrun notarytool submit \
    "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format json)"
print -r -- "$notary_result"
notary_status="$(print -r -- "$notary_result" | plutil -extract status raw -o - -)"
if [[ "$notary_status" != "Accepted" ]]; then
    print -u2 "Apple notarization failed with status: $notary_status"
    exit 1
fi
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

(
    cd "$DIST_DIR"
    shasum -a 256 "${DMG_PATH:t}" > "${CHECKSUM_PATH:t}"
)

print "$DMG_PATH"
print "$CHECKSUM_PATH"
