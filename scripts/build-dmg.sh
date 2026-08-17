#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build/release"
APP="$ROOT/dist/Pastecap.app"
DMG="$ROOT/dist/Pastecap.dmg"
STAGE="$ROOT/.dmg-staging"
ENTITLEMENTS="$ROOT/Packaging/Pastecap.entitlements"
IDENTITY="${CODESIGN_IDENTITY:--}"
rm -rf "$ROOT/dist"
rm -rf "$STAGE"
mkdir -p "$ROOT/dist" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGE"
"$ROOT/scripts/generate-icons.sh"
swift build -c release --package-path "$ROOT"
ditto "$BUILD/Pastecap" "$APP/Contents/MacOS/Pastecap"
ditto "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
ditto "$ROOT/Packaging/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleName</key><string>Pastecap</string>
	<key>CFBundleDisplayName</key><string>Pastecap</string>
	<key>CFBundleIdentifier</key><string>com.wwm.Pastecap</string>
	<key>CFBundleExecutable</key><string>Pastecap</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleSignature</key><string>????</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIconName</key><string>AppIcon</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>CFBundleVersion</key><string>7</string>
	<key>CFBundleShortVersionString</key><string>1.2.0</string>
	<key>NSScreenCaptureUsageDescription</key><string>Pastecap 需要屏幕录制权限来截取选定区域。</string>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
plutil -lint "$ENTITLEMENTS"
# Clear Finder icon cache hints and re-register the custom icon for the bundle.
touch "$APP" "$APP/Contents/Info.plist" "$APP/Contents/Resources/AppIcon.icns"
REQUIREMENTS='=designated => identifier "com.wwm.Pastecap"'
if [ "$IDENTITY" = "-" ]; then
  echo "Ad-hoc signing (set CODESIGN_IDENTITY for Developer ID)"
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" \
    --requirements "$REQUIREMENTS" --sign - --timestamp=none "$APP"
else
  echo "Signing with $IDENTITY"
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" \
    --requirements "$REQUIREMENTS" --sign "$IDENTITY" --timestamp "$APP"
fi
codesign --verify --strict --deep --verbose=2 "$APP"
ditto "$APP" "$STAGE/Pastecap.app"
ln -s /Applications "$STAGE/Applications"
# Use the app icon as the DMG volume icon when possible.
VOLUME_ICON="$STAGE/.VolumeIcon.icns"
ditto "$ROOT/Assets/AppIcon.icns" "$VOLUME_ICON"
hdiutil create -volname Pastecap -srcfolder "$STAGE" -ov -format UDZO "$DMG"
# Enable custom volume icon on the DMG (hasCustomIcon).
if command -v SetFile >/dev/null 2>&1; then
  MOUNT="$(hdiutil attach -readwrite -nobrowse "$DMG" | awk '/\/Volumes\//{print $3; exit}')"
  if [ -n "${MOUNT:-}" ] && [ -f "$MOUNT/.VolumeIcon.icns" ]; then
    SetFile -a C "$MOUNT" || true
    hdiutil detach "$MOUNT" >/dev/null
  fi
fi
rm -rf "$STAGE"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  if [ "$IDENTITY" = "-" ]; then
    echo "NOTARY_PROFILE is set but CODESIGN_IDENTITY is ad-hoc; skip notarization" >&2
    exit 1
  fi
  echo "Submitting $DMG for notarization"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
  spctl --assess --type open --context context:primary-signature -v "$DMG" || true
fi

# Nudge LaunchServices / Finder to pick up the new bundle icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
echo "Created $DMG"
if [ "$IDENTITY" = "-" ]; then
  echo "Local DMG is ad-hoc signed. For website distribution:"
  echo "  1. Import a Developer ID Application certificate"
  echo "  2. xcrun notarytool store-credentials  (saves a keychain profile)"
  echo "  3. CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' NOTARY_PROFILE=pastecap scripts/build-dmg.sh"
fi
