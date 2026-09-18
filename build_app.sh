#!/bin/bash
# Builds MetalHUDToggle.app (requires Xcode or the Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MetalHUDToggle"

APP="MetalHUDToggle.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MetalHUDToggle"
cp Info.plist "$APP/Contents/Info.plist"

# Build AppIcon.icns from the 1024px PNG
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Icon/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" Icon/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Done: $(pwd)/$APP"
echo "Install: cp -R \"$(pwd)/$APP\" /Applications/"
