#!/bin/bash

set -e  # Exit on any error
set -x  # Print each command before executing

# Configuration
APP_NAME="Speed"
VERSION="1.0.0"
SCHEME="Speed"
CONFIGURATION="Release"
ARCHIVE_PATH="./build/${APP_NAME}.xcarchive"
EXPORT_PATH="./build/${APP_NAME}-${VERSION}"
ZIP_NAME="${APP_NAME}.app.zip"

# Clean build directory
echo "Cleaning build directory..."
rm -rf ./build
mkdir -p ./build

# Check for exportOptions.plist
if [ ! -f "exportOptions.plist" ]; then
    echo "Error: exportOptions.plist not found"
    exit 1
fi

# Build archive
echo "Building archive..."
xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=34HCA7L7PV \
    CODE_SIGN_IDENTITY="Apple Development"

echo "Archive contents:"
ls -la "$ARCHIVE_PATH"

# Export archive
echo "Exporting archive..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist exportOptions.plist \
    DEVELOPMENT_TEAM=34HCA7L7PV

echo "Export directory contents:"
ls -la "$EXPORT_PATH"

# Create zip
echo "Creating zip..."
cd "$EXPORT_PATH"
if [ ! -d "$APP_NAME.app" ]; then
    echo "Error: $APP_NAME.app not found in export directory"
    exit 1
fi
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$ZIP_NAME"

echo "Zip created, contents of $EXPORT_PATH:"
ls -la

# Notarize the app
echo "Notarizing app..."
xcrun notarytool submit "$ZIP_NAME" --keychain-profile "AC_PASSWORD" --wait

# Staple the notarization ticket
echo "Stapling notarization ticket..."
xcrun stapler staple "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$ZIP_NAME"

echo "Moving zip to root directory..."
mv "$ZIP_NAME" ../..
cd ../..

echo "Root directory contents:"
ls -la

# Generate Sparkle signature
echo "Generating Sparkle signature..."
if [ ! -f "./scripts/sign_update" ]; then
    echo "Error: sign_update tool not found"
    exit 1
fi

# Run the sign_update tool and capture its output
SIGNATURE_OUTPUT=$(./scripts/sign_update "$ZIP_NAME")
if [ $? -ne 0 ]; then
    echo "Error: Failed to generate signature"
    exit 1
fi

# Extract and save the signature and public key
echo "$SIGNATURE_OUTPUT" > signature.txt
echo "Signature generated and saved to signature.txt"

echo "Release artifacts created:"
echo "- $ZIP_NAME"
echo "- signature.txt"
echo
echo "Next steps:"
echo "1. Upload $ZIP_NAME to GitHub releases"
echo "2. Update appcast.xml with the new version, download URL, and signature" 