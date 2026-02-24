#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacSync"
SCHEME="MacSync"
CONFIG="Release"
LAPTOP="gary@Garys-Laptop.local"
LAPTOP_PATH="~/Applications"

echo "=== Building $APP_NAME ==="
cd "$PROJECT_DIR"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath build/ \
    build

BUILD_DIR="build/Build/Products/$CONFIG"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Build product not found at $APP_PATH"
    exit 1
fi

echo "=== Build Succeeded ==="

echo "=== Deploying to local ~/Applications ==="
cp -R "$APP_PATH" ~/Applications/
echo "=== Deployed locally ==="

echo "=== Deploying to laptop ==="
scp -r "$APP_PATH" "$LAPTOP:$LAPTOP_PATH/"
echo "=== Deployed to $LAPTOP ==="

echo "=== Pushing to GitHub ==="
cd "$PROJECT_DIR"
git push origin main 2>/dev/null || echo "(push skipped)"

echo "=== Done ==="
