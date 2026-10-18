#!/bin/bash
# Generates AppIcon.icns + .iconset from the 1024px master icon.png.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="/tmp/iconbuild/icon.png"
ICONSET="Scripts/icons.iconset"
ICNS="Scripts/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# macOS icon sizes (points @1x / @2x)
sips -z 16 16       "$SRC" --out "$ICONSET/icon_16x16.png"       >/dev/null
sips -z 32 32       "$SRC" --out "$ICONSET/icon_16x16@2x.png"    >/dev/null
sips -z 32 32       "$SRC" --out "$ICONSET/icon_32x32.png"       >/dev/null
sips -z 64 64       "$SRC" --out "$ICONSET/icon_32x32@2x.png"    >/dev/null
sips -z 128 128     "$SRC" --out "$ICONSET/icon_128x128.png"     >/dev/null
sips -z 256 256     "$SRC" --out "$ICONSET/icon_128x128@2x.png"  >/dev/null
sips -z 256 256     "$SRC" --out "$ICONSET/icon_256x256.png"     >/dev/null
sips -z 512 512     "$SRC" --out "$ICONSET/icon_256x256@2x.png"  >/dev/null
sips -z 512 512     "$SRC" --out "$ICONSET/icon_512x512.png"     >/dev/null
cp "$SRC" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "✅ wrote $ICNS ($(du -h "$ICNS" | cut -f1))"
