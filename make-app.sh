#!/usr/bin/env bash
# Builds dist/Notchivity.app (ad-hoc signed) plus a drag-to-Applications .dmg and a .zip.
# Notification Center and launch-at-login only work from the bundle, not from the bare
# SwiftPM binary. Ad-hoc signing means other Macs need right-click → Open on first launch.
set -euo pipefail

VERSION="${1:-0.1.0}"
APP_NAME="Notchivity"
BUNDLE_ID="com.notchivity.app"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "▸ Building release binary…"
swift build -c release --package-path "$ROOT"

echo "▸ Assembling $APP_NAME.app…"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

# Icons: the .icns serves Finder, the Dock and older systems; macOS 26 Notification Center
# only reads the asset-catalog icon named by CFBundleIconName, so we compile that too.
ICON_KEY=''
if [[ -f "$ROOT/AppIcon.png" ]]; then
  ICONSET="$WORK/AppIcon.iconset"; mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size*2)) $((size*2)) "$ROOT/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  [[ -f "$ROOT/AppIcon.icns" ]] || iconutil -c icns "$ICONSET" -o "$ROOT/AppIcon.icns"

  if ACTOOL="$(xcrun --find actool 2>/dev/null)"; then
    APPICONSET="$WORK/Assets.xcassets/AppIcon.appiconset"; mkdir -p "$APPICONSET"
    cp "$ICONSET"/*.png "$APPICONSET/"
    IMAGES=''
    for size in 16 32 128 256 512; do
      IMAGES+="{\"idiom\":\"mac\",\"size\":\"${size}x${size}\",\"scale\":\"1x\",\"filename\":\"icon_${size}x${size}.png\"},"
      IMAGES+="{\"idiom\":\"mac\",\"size\":\"${size}x${size}\",\"scale\":\"2x\",\"filename\":\"icon_${size}x${size}@2x.png\"},"
    done
    echo "{\"images\":[${IMAGES%,}],\"info\":{\"version\":1,\"author\":\"make-app\"}}" > "$APPICONSET/Contents.json"
    "$ACTOOL" "$WORK/Assets.xcassets" --compile "$CONTENTS/Resources" --platform macosx \
      --minimum-deployment-target 14.0 --app-icon AppIcon \
      --output-partial-info-plist "$WORK/icon.plist" >/dev/null
    ICON_KEY='<key>CFBundleIconName</key><string>AppIcon</string>'
  else
    echo "  actool not found (needs Xcode); skipping asset-catalog icon"
  fi
fi
if [[ -f "$ROOT/AppIcon.icns" ]]; then
  cp "$ROOT/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
  ICON_KEY+='<key>CFBundleIconFile</key><string>AppIcon</string>'
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    $ICON_KEY
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signing…"
codesign --force --sign - "$APP"

mkdir -p "$DIST"
rm -rf "$DIST/$APP_NAME.app"
ditto "$APP" "$DIST/$APP_NAME.app"

echo "▸ Zipping…"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Building DMG…"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGE="$WORK/dmg/$APP_NAME"
rm -f "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

echo "✓ $DIST/$APP_NAME.app"
echo "✓ $ZIP"
echo "✓ $DMG"
