#!/bin/bash
# build.sh — Build ZotLight.app bundle
set -e

APP="dist/ZotLight.app"
MACOS="$APP/Contents/MacOS"
BINARY="$MACOS/ZotLight"

echo "Building ZotLight.app..."

# Extract icon from installed Zotero.app if not already present
if [ ! -f "ZotLight/zotero.icns" ]; then
    bash extract-icon.sh
fi

# Create bundle structure
mkdir -p "$MACOS"
mkdir -p "$APP/Contents/Resources"

# Copy Info.plist and icon
cp ZotLight/Info.plist "$APP/Contents/Info.plist"
cp ZotLight/zotero.icns "$APP/Contents/Resources/zotero.icns"

# Compile all Swift sources (order: Config → SettingsWindow → main)
swiftc -O \
    ZotLight/Config.swift \
    ZotLight/SettingsWindow.swift \
    ZotLight/main.swift \
    -o "$BINARY" \
    -framework Foundation \
    -framework CoreServices \
    -framework CoreSpotlight \
    -framework AppKit

chmod +x "$BINARY"

# Ad-hoc sign (required for Core Spotlight to surface results in Cmd+Space)
codesign --force --deep --sign - "$APP"

echo "Built and signed: dist/ZotLight.app"
