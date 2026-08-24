#!/usr/bin/env bash
#
# Builds a signed archive and uploads it to App Store Connect for TestFlight.
#
# Prerequisites, both one-time:
#   1. Xcode > Settings > Accounts — sign in with your Apple Developer account.
#   2. DEVELOPMENT_TEAM set in Config/Secrets.xcconfig.
#
# Then:
#   ./Scripts/archive.sh              # build and upload
#   ./Scripts/archive.sh --no-upload  # build only, to check signing works
#
# Uploading needs an app-specific password for your Apple ID, in the keychain:
#   xcrun notarytool store-credentials  # or set ASC_API_KEY below
set -euo pipefail

cd "$(dirname "$0")/.."

# Command Line Tools cannot archive, and `xcode-select` often points at them
# on a machine that also builds from the terminal. Pick Xcode explicitly
# rather than depending on whatever the global setting happens to be.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

UPLOAD=true
[ "${1:-}" = "--no-upload" ] && UPLOAD=false

SCHEME="CommissionersCartel"
PROJECT="CommissionersCartel.xcodeproj"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"

TEAM=$(grep -E '^DEVELOPMENT_TEAM' Config/Secrets.xcconfig 2>/dev/null | cut -d= -f2 | tr -d ' ' || true)
if [ -z "$TEAM" ]; then
  echo "DEVELOPMENT_TEAM is not set in Config/Secrets.xcconfig." >&2
  echo "Find it in Xcode > Settings > Accounts, then add:" >&2
  echo "    DEVELOPMENT_TEAM = ABCDE12345" >&2
  exit 1
fi
echo "==> Team $TEAM"

# Bump the build number so App Store Connect accepts the upload; it rejects a
# build number it has already seen, which is the most common upload failure.
BUILD_NUMBER=$(date +%Y%m%d%H%M)
echo "==> Build $BUILD_NUMBER"

PROFILE="iOS Team Store Provisioning Profile: com.commissionerscartel.app"

rm -rf "$ARCHIVE"
echo "==> Archiving"
# -allowProvisioningUpdates is needed on the archive too, not only the export:
# without it Xcode refuses to create the provisioning profile and fails with
# "No profiles for ... were found".
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -allowProvisioningUpdates \
  -quiet

# Automatic signing archives with the *development* certificate, which rewrites
# aps-environment from production down to development. -exportArchive then sees
# a value the App Store profile does not grant and drops the entitlement
# altogether — producing a build that uploads, installs, and never receives a
# single push, with no error anywhere.
#
# Re-signing the archived app with the distribution identity and the App Store
# profile puts the right value back before export reads it. Manual signing at
# archive time is not an option: the profile is Xcode-managed, and the build
# system refuses to use one of those manually.
APP="$ARCHIVE/Products/Applications/$SCHEME.app"
PROFILE_PATH=$(
  for f in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision; do
    [ -e "$f" ] || continue
    security cms -D -i "$f" > "$BUILD_DIR/p.plist" 2>/dev/null || continue
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :Name' "$BUILD_DIR/p.plist" 2>/dev/null)" = "$PROFILE" ]; then
      echo "$f"; break
    fi
  done
)
if [ -z "$PROFILE_PATH" ]; then
  echo "Could not find the App Store provisioning profile locally." >&2
  echo "Archive once from Xcode to have it issued, then run this again." >&2
  exit 1
fi

echo "==> Re-signing for distribution"
security cms -D -i "$PROFILE_PATH" > "$BUILD_DIR/profile.plist"
/usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$BUILD_DIR/profile.plist" \
  > "$BUILD_DIR/entitlements.plist"
# The profile grants a wildcard keychain group. Keeping it would change which
# group the app writes to and orphan every stored session and ESPN cookie, so
# the app keeps its implicit default.
/usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "$BUILD_DIR/entitlements.plist" 2>/dev/null || true
cp "$PROFILE_PATH" "$APP/embedded.mobileprovision"
codesign --force --sign "Apple Distribution" \
  --entitlements "$BUILD_DIR/entitlements.plist" \
  --generate-entitlement-der \
  --timestamp=none \
  "$APP" 2>&1 | sed 's/^/    /'

# The failure this guards against is silent: everything below succeeds, the
# build reaches TestFlight, and notifications simply never arrive.
echo "==> Checking entitlements"
APS=$(codesign -d --entitlements :- "$APP" 2>/dev/null \
      | plutil -extract aps-environment raw - 2>/dev/null || true)
if [ "$APS" != "production" ]; then
  echo "" >&2
  echo "aps-environment is '${APS:-missing}', expected 'production'." >&2
  echo "This build would install fine and never deliver a notification." >&2
  echo "Check that the App ID has Push Notifications enabled and that" >&2
  echo "  $PROFILE" >&2
  echo "grants aps-environment. See docs/PUSH_NOTIFICATIONS.md." >&2
  exit 1
fi
echo "    aps-environment = production"

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>$TEAM</string>
    <key>uploadSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>$([ "$UPLOAD" = true ] && echo upload || echo export)</string>
</dict>
</plist>
PLIST

# With destination=upload xcodebuild uploads directly and writes no .ipa, so
# anything left here is from an earlier run. Removing it stops a stale artifact
# being mistaken for the build that just went out.
rm -rf "$BUILD_DIR/export"

echo "==> Exporting$([ "$UPLOAD" = true ] && echo ' and uploading' || echo '')"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR/export" \
  -allowProvisioningUpdates

echo ""
if [ "$UPLOAD" = true ]; then
  # TestFlight builds expire 90 days after upload, and an expired build stops
  # launching for every tester. Recording the date here lets a scheduled job
  # warn before that happens rather than finding out from eleven people at once.
  mkdir -p .testflight
  cat > .testflight/last-upload.json <<JSON
{
  "build": "$BUILD_NUMBER",
  "uploadedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "note": "Written by Scripts/archive.sh. Read by .github/workflows/testflight-expiry.yml to warn before the 90-day expiry."
}
JSON

  if git diff --quiet -- .testflight/last-upload.json 2>/dev/null; then
    :
  elif git rev-parse --git-dir >/dev/null 2>&1; then
    git add .testflight/last-upload.json
    git commit -q -m "Record TestFlight upload $BUILD_NUMBER" || true
    git push -q 2>/dev/null || echo "  (couldn't push the upload record — commit it when convenient)"
  fi

  echo "Uploaded build $BUILD_NUMBER. It takes App Store Connect a few minutes"
  echo "to process before it appears in TestFlight."
  echo "Expires $(date -u -v+90d +%Y-%m-%d 2>/dev/null || date -u -d '+90 days' +%Y-%m-%d)."
else
  echo "Archive exported to $BUILD_DIR/export — signing works."
fi
