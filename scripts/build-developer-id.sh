#!/bin/bash
#
# Local Developer ID build: archive → export → DMG → sign → notarize → staple
# → Sparkle sign → appcast. Mirrors .github/workflows/release-macos.yml, but
# uses the local Keychain Developer ID cert and the gitignored EdDSA private
# key in keys/.
#
# Prerequisites:
#   - Developer ID Application cert in the login Keychain (team YXDJG24NWG).
#   - keys/sparkle_private_key.pem  (exported EdDSA private key).
#   - A stored notarytool profile:  see NOTARY_PROFILE below. Create once with:
#       xcrun notarytool store-credentials photobooks-notary \
#         --apple-id <you@example.com> --team-id YXDJG24NWG --password <app-specific-pw>
#   - brew install xcodegen create-dmg
#
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="PhotoBooks (Direct)"
TEAM_ID="YXDJG24NWG"
SIGNING_IDENTITY="Developer ID Application: MB Modernios Aplikacijos (YXDJG24NWG)"
NOTARY_PROFILE="${NOTARY_PROFILE:-photobooks-notary}"
SPARKLE_KEY_FILE="keys/sparkle_private_key.pem"
BUILD_DIR="build/developer-id"

VERSION=$(grep -E '^\s+MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*: *"?([0-9.]+)"?.*/\1/')
TAG="v$VERSION"
DMG_NAME="PhotoBooks-$VERSION.dmg"

echo "▸ PhotoBooks $VERSION — Developer ID build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "▸ Generating project"
xcodegen generate

echo "▸ Archiving"
xcodebuild archive \
  -project PhotoBooks.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$BUILD_DIR/PhotoBooks.xcarchive" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID"

echo "▸ Exporting (developer-id)"
cat > "$BUILD_DIR/exportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>$TEAM_ID</string>
</dict></plist>
EOF
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/PhotoBooks.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/exportOptions.plist" \
  -exportPath "$BUILD_DIR/export"

echo "▸ Creating DMG"
create-dmg \
  --volname "PhotoBooks $VERSION" \
  --app-drop-link 450 180 \
  --icon "PhotoBooks.app" 150 180 \
  --window-size 620 400 \
  "$BUILD_DIR/$DMG_NAME" \
  "$BUILD_DIR/export/PhotoBooks.app"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$BUILD_DIR/$DMG_NAME"

echo "▸ Notarizing (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$BUILD_DIR/$DMG_NAME"
spctl --assess --type open --context context:primary-signature -v "$BUILD_DIR/$DMG_NAME" || true

echo "▸ Signing for Sparkle + writing appcast"
SIG_LINE=$(.tooling/sparkle-bin/sign_update "$BUILD_DIR/$DMG_NAME" -f "$SPARKLE_KEY_FILE")
PUBDATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
URL="https://github.com/GraphicMeat/PhotoBooks/releases/download/$TAG/$DMG_NAME"
cat > "$BUILD_DIR/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>PhotoBooks</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure url="$URL" type="application/octet-stream" $SIG_LINE />
    </item>
  </channel>
</rss>
EOF

echo "✓ Done: $BUILD_DIR/$DMG_NAME + $BUILD_DIR/appcast.xml"
