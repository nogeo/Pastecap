#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$ROOT/Assets"
ICONSET="$ROOT/.build/AppIcon.iconset"
MASTER="$ASSETS/AppIcon-1024.png"
mkdir -p "$ASSETS" "$ROOT/.build"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift "$ROOT/scripts/generate-app-icon.swift" "$MASTER"
for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  set -- $spec
  sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ASSETS/AppIcon.icns"
echo "Created $ASSETS/AppIcon.icns"
