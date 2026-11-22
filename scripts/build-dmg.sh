#!/bin/bash
# Builds a universal (Apple Silicon + Intel) Release of Blippy and packs it into a drag-to-install DMG.
#
#   scripts/build-dmg.sh                       # ad-hoc signed (free; users confirm "Open Anyway" once)
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build-dmg.sh   # with a paid Apple Developer ID
#
# Output: dist/Blippy-<version>.dmg and dist/Blippy-<version>.dmg.sha256
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:--}"
VERSION="$(grep -m1 'MARKETING_VERSION' Blippy.xcodeproj/project.pbxproj | sed 's/.*= \(.*\);/\1/')"
NAME="Blippy"
DERIVED="build-release"
DMG="dist/$NAME-$VERSION.dmg"

[ -x Vendor/adb ] || ./scripts/fetch-adb.sh

echo "==> Building $NAME $VERSION (universal, Release)"
rm -rf "$DERIVED" dist
mkdir -p dist
xcodebuild -project Blippy.xcodeproj -scheme Blippy -configuration Release -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES build | tail -3

APP="$DERIVED/Build/Products/Release/$NAME.app"
[ -d "$APP" ] || { echo "Build failed: $APP not found"; exit 1; }

echo "==> Checking the signature"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/$NAME" | sed 's/^/    architectures: /'

echo "==> Preparing the disk image"
STAGE="$(mktemp -d)"
RW="$(mktemp -d)/rw.dmg"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
[ -f Design/dmg-background.png ] || swift Design/make_dmg_background.swift Design/dmg-background.png
cp Design/dmg-background.png "$STAGE/.background/background.png"
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

hdiutil create -srcfolder "$STAGE" -volname "$NAME" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
MOUNT="$(hdiutil attach "$RW" -noautoopen -nobrowse | grep -o '/Volumes/.*' | head -1)"
SetFile -a C "$MOUNT" 2>/dev/null || true

# Lay out the window (needs Finder automation; if macOS blocks it the DMG still works, just unstyled).
timeout 90 osascript >/dev/null 2>&1 <<APPLESCRIPT || echo "    (could not style the window; the DMG still works)"
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set background picture of opts to file ".background:background.png"
    set position of item "$NAME.app" of container window to {180, 200}
    set position of item "Applications" of container window to {480, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach "$MOUNT" -quiet || { sleep 2; hdiutil detach "$MOUNT" -force -quiet; }

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -f "$RW"
( cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )

echo "==> Done"
ls -lh "$DMG" | awk '{print "    " $5 "  " $9}'
cat "dist/$(basename "$DMG").sha256" | sed 's/^/    sha256: /'
if [ "$IDENTITY" = "-" ]; then
  echo "    Signed ad-hoc: users confirm 'Open Anyway' once on first launch (see docs/INSTALL.md)."
fi
