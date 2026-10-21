#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
BUILD_DIR="$PROJECT_DIR/build/Release"
APP_NAME="Fettle"

echo "=== Fettle Release Packaging ==="
echo "Project Directory: $PROJECT_DIR"

# 1. Clean previous dist
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 2. Build Release Configuration
echo "Building Fettle (Release)..."
xcodebuild clean build \
    -project "$PROJECT_DIR/Fettle.xcodeproj" \
    -scheme "Fettle" \
    -configuration "Release" \
    -derivedDataPath "$PROJECT_DIR/build/DerivedData" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    CODE_SIGNING_ALLOWED=NO

APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH was not built."
    exit 1
fi

# 3. Ad-hoc Codesign
echo "Codesigning $APP_NAME.app..."
codesign --force --deep --sign - "$APP_PATH"

# 4. Package Release Zip
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"
echo "Creating Release Zip: $ZIP_PATH..."
(cd "$BUILD_DIR" && zip -r -q -y "$ZIP_PATH" "$APP_NAME.app")

# 5. Create DMG if hdiutil is available
DMG_PATH="$DIST_DIR/$APP_NAME-macOS.dmg"
if command -v hdiutil &> /dev/null; then
    echo "Creating Release DMG: $DMG_PATH..."
    DMG_TEMP="$DIST_DIR/dmg_temp"
    rm -rf "$DMG_TEMP"
    mkdir -p "$DMG_TEMP"
    cp -R "$APP_PATH" "$DMG_TEMP/"
    ln -s /Applications "$DMG_TEMP/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_PATH"
    rm -rf "$DMG_TEMP"
fi

echo "=== Release Artifacts Created Successfully ==="
ls -lh "$DIST_DIR"
