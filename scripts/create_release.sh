#!/bin/bash

# Exit on error
set -e

if [ -z "$1" ]; then
    echo "Please provide a version number (e.g. ./create_release.sh 1.0.0)"
    exit 1
fi

VERSION=$1

# Build the app
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
    "dist/Speed.dmg" \
    "$APP_PATH"

# Sign the DMG with Sparkle
echo "🔏 Signing DMG with Sparkle..."
SIGNATURE=$(/usr/local/Caskroom/sparkle/2.6.4/bin/sign_update dist/Speed.dmg)

# Create or update appcast.xml
echo "📝 Updating appcast.xml..."
DMG_SIZE=$(stat -f%z "dist/Speed.dmg")

cat > appcast.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Speed App Updates</title>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
        <item>
            <title>Version $VERSION</title>
            <sparkle:version>$VERSION</sparkle:version>
            <description>
                <![CDATA[
                    <h2>Version $VERSION</h2>
                    <ul>
                        <li>New release version $VERSION</li>
                    </ul>
                ]]>
            </description>
            <pubDate>$(date -R)</pubDate>
            <enclosure
                url="https://raw.githubusercontent.com/jetlej/Speed/main/dist/Speed.dmg"
                sparkle:version="$VERSION"
                sparkle:shortVersionString="$VERSION"
                length="$DMG_SIZE"
                type="application/octet-stream"
                sparkle:edSignature="$SIGNATURE" />
        </item>
    </channel>
</rss>
EOF

echo "✅ Done! Now you can:"
echo "1. Commit the changes (new DMG and updated appcast.xml)"
echo "2. Tag the commit: git tag v$VERSION"
echo "3. Push everything: git push && git push --tags" 