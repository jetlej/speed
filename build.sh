#!/bin/bash

# Exit on error
set -e

echo "🏗️  Building Speed in Release mode..."
xcodebuild -scheme Speed -configuration Release clean build

# Get the path to the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Speed.app" -path "*/Release/*" -type d)

if [ -z "$APP_PATH" ]; then
    echo "❌ Could not find built Speed.app"
    exit 1
fi

echo "📦 Creating DMG..."
create-dmg \
    --volname "Speed" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "Speed.app" 200 190 \
    --hide-extension "Speed.app" \
    --app-drop-link 600 185 \
    "Speed.dmg" \
    "$APP_PATH"

echo "✅ Done! DMG created at: $(pwd)/Speed.dmg" 