#!/bin/bash

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

# Export archive
echo "Exporting archive..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist exportOptions.plist

# Create zip
echo "Creating zip..."
cd "$EXPORT_PATH"
ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "../../$ZIP_NAME"
cd ../..

# Generate signature
echo "Generating Sparkle signature..."
./bin/sign_update "$ZIP_NAME"

echo "Done! Release artifacts created:"
echo "- $ZIP_NAME"
echo "Please upload these to GitHub releases" 