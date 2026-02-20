#!/bin/bash
# extract-icon.sh — Extract Zotero.app icon into ZotLight/zotero.icns
# Usage: bash extract-icon.sh [/path/to/dir/containing/Zotero.app]
# Defaults to /Applications if no argument given.
set -e

SEARCH_DIR="${1:-/Applications}"
ZOTERO_APP="$SEARCH_DIR/Zotero.app"
OUT="ZotLight/zotero.icns"

if [ ! -d "$ZOTERO_APP" ]; then
    echo "Error: Zotero.app not found at $ZOTERO_APP"
    exit 1
fi

echo "Extracting Zotero icon..."

ICONSET=$(mktemp -d)/zotero.iconset
mkdir -p "$ICONSET"

swift - "$ZOTERO_APP" "$ICONSET" << 'SWIFT'
import AppKit
let appPath = CommandLine.arguments[1]
let iconsetPath = CommandLine.arguments[2]
let icon = NSWorkspace.shared.icon(forFile: appPath)

// Write icon at each required iconset size
let sizes: [(Int, String)] = [
    (16,  "icon_16x16"),
    (32,  "icon_16x16@2x"),
    (32,  "icon_32x32"),
    (64,  "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024,"icon_512x512@2x"),
]

for (size, name) in sizes {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
}
SWIFT

iconutil --convert icns "$ICONSET" --output "$OUT"
rm -rf "$(dirname $ICONSET)"

echo "Extracted icon to $OUT"
