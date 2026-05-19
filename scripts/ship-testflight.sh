#!/bin/bash
# Build, archive, export, and upload CheerPracticePlayer to TestFlight.
# Uses xcodebuild + xcrun altool. Bypasses fastlane (broken on Ruby 4.0.4
# OpenSSL — "invalid curve name" parsing the ASC P-256 key).
#
# Prereqs: ASC API key .p8 at ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
# CURRENT_PROJECT_VERSION in project.yml MUST be > any existing TestFlight build
# for the same MARKETING_VERSION.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$PWD"
echo "Working in: $REPO"

API_KEY_ID="6H24WZ2RQ5"
API_ISSUER="7642a25e-aca7-402d-8b7d-de18dfef1756"
SCHEME="CheerPracticePlayer"
TEAM_ID="WC46K49VFA"

# PATH=/usr/bin first — Homebrew/MacPorts rsync breaks xcodebuild exportArchive
export PATH=/usr/bin:$PATH

echo "== Regenerating Xcode project from project.yml =="
xcodegen generate

BUILD_DIR="$REPO/build"
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTS="$BUILD_DIR/ExportOptions.plist"
mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

cat > "$EXPORT_OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF

echo "== Archiving =="
xcodebuild archive \
  -project "$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  | grep -E '^\*\*|error:|warning:' || true

if [ ! -d "$ARCHIVE" ]; then
  echo "FAIL: archive not produced at $ARCHIVE"
  exit 1
fi

echo "== Exporting .ipa =="
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  | grep -E '^\*\*|error:|warning:' || true

IPA=$(find "$EXPORT_DIR" -name "*.ipa" | head -1)
if [ -z "$IPA" ] || [ ! -f "$IPA" ]; then
  echo "FAIL: no .ipa in $EXPORT_DIR"
  exit 1
fi
echo "Built: $IPA"

echo "== Uploading to TestFlight via altool =="
xcrun altool --upload-app \
  --type ios \
  --file "$IPA" \
  --apiKey "$API_KEY_ID" \
  --apiIssuer "$API_ISSUER"

echo ""
echo "== Done. Watch processing in App Store Connect. =="
echo "TestFlight builds usually take 10-30 minutes to process."
