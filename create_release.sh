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
rm -rf build
mkdir -p build

# Build archive
echo "Building archive..."
xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="Sign to Run Locally"

echo "Archive contents:"
ls -la "$ARCHIVE_PATH"

# Export archive
echo "Exporting archive..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist exportOptions.plist

echo "Export directory contents:"
ls -la "$EXPORT_PATH"

# Create zip
echo "Creating zip..."
cd "$EXPORT_PATH"
if [ ! -d "${APP_NAME}.app" ]; then
    echo "Error: ${APP_NAME}.app directory not found in $EXPORT_PATH"
    exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "$ZIP_NAME"
echo "Zip created, contents of $EXPORT_PATH:"
ls -la

echo "Moving zip to root directory..."
mv "$ZIP_NAME" "../.."
cd ../..

echo "Root directory contents:"
ls -la

# Generate signature
echo "Generating Sparkle signature..."
if [ ! -f "./bin/sign_update" ]; then
    echo "Error: sign_update not found"
    exit 1
fi

./bin/sign_update "$ZIP_NAME"

echo "Done! Release artifacts created:"
echo "- $ZIP_NAME"
ls -la "$ZIP_NAME"
echo "Please upload these to GitHub releases" 