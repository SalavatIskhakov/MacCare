#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MacCare.app"
VERSION="${MACCARE_VERSION:-0.1.0}"
DMG="${1:-$ROOT/build/MacCare-$VERSION.dmg}"
: "${MACCARE_SIGN_IDENTITY:?Set MACCARE_SIGN_IDENTITY to the Developer ID Application identity}"
: "${MACCARE_TEAM_ID:?Set MACCARE_TEAM_ID to the Apple Developer Team ID}"
: "${MACCARE_NOTARY_PROFILE:?Set MACCARE_NOTARY_PROFILE to a configured notarytool keychain profile}"
[[ -d "$APP" ]] || { echo "Build the app first" >&2; exit 1; }
for helper in analyze-go status-go; do
  BINARY="$APP/Contents/Resources/Mole/arm64/bin/$helper"
  [[ -x "$BINARY" ]] || { echo "Missing bundled Mole helper: $BINARY" >&2; exit 1; }
  codesign --force --options runtime --timestamp --sign "$MACCARE_SIGN_IDENTITY" "$BINARY"
  codesign --verify --strict --verbose=2 "$BINARY"
done
codesign --force --options runtime --timestamp --sign "$MACCARE_SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"
STAGE="$ROOT/build/signed-dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/MacCare.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Mac Care" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$MACCARE_NOTARY_PROFILE" --team-id "$MACCARE_TEAM_ID" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
