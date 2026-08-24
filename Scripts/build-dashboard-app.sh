#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
PRODUCT_DIR="$PROJECT_DIR/.build/app"
APP_BUNDLE="$PRODUCT_DIR/Flipper Dashboard.app"
XCODE_APP="$PROJECT_DIR/.xcode-build/Build/Products/Release/Flipper Dashboard.app"

xcodegen generate --quiet --spec "$PROJECT_DIR/project.yml" --project "$PROJECT_DIR"
xcodebuild \
    -quiet \
    -project "$PROJECT_DIR/FlipperDashboard.xcodeproj" \
    -scheme DashboardBar \
    -configuration Release \
    -derivedDataPath "$PROJECT_DIR/.xcode-build" \
    build

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
"$LSREGISTER" -u "$XCODE_APP" 2>/dev/null || true

rm -rf "$APP_BUNDLE"
mkdir -p "$PRODUCT_DIR"
ditto "$XCODE_APP" "$APP_BUNDLE"

codesign --verify --deep --strict "$APP_BUNDLE"
echo "$APP_BUNDLE"
