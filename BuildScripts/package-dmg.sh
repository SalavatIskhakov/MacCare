#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
VERSION="${MACCARE_VERSION:-0.1.0}"
APP="$OUT/MacCare.app"
mkdir -p "$OUT"
"$ROOT/BuildScripts/prepare-mole.sh"
xcodebuild -project "$ROOT/MacCare.xcodeproj" -scheme MacCare -configuration Release \
  -derivedDataPath "$OUT/DerivedData" ARCHS="arm64" CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY="-" build
rm -rf "$APP"
ditto "$OUT/DerivedData/Build/Products/Release/MacCare.app" "$APP"
# Mole is copied after Xcode's build phase, so seal the final resource set again.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
# Register the final, signed bundle so Finder and Dock resolve its executable/icon.
"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" \
  -f -R -trusted "$APP"
STAGE="$OUT/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/MacCare.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/MacCare-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Mac Care" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Created unsigned development bundle: $APP"
echo "Created unsigned development image: $DMG"
