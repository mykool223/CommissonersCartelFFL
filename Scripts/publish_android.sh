#!/usr/bin/env bash
#
# Copies the built release APK into Google Drive, where the league gets it.
#
# Drive for desktop mounts the account as an ordinary folder, so publishing is
# a file copy — no API, no token, nothing to expire. The league's convention is
# the root of My Drive, named for the version:
#
#     CommissionersCartel-0.38.0.apk
#
# Run it after ./Scripts/smoke_android.sh has passed. Publishing a build that
# has not been opened once is how an APK that cannot launch reaches eleven
# people at the same time.
#
#   ./Scripts/publish_android.sh            # publish the current release APK
#   ./Scripts/publish_android.sh --force    # overwrite a version already there
set -euo pipefail

cd "$(dirname "$0")/.."

APK="android/app/build/outputs/apk/release/app-release.apk"
FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

[ -f "$APK" ] || {
  echo "No release APK. Build one first:" >&2
  echo "    (cd android && ./gradlew assembleRelease)" >&2
  exit 1
}

# The version comes from the APK rather than from build.gradle.kts, so a stale
# artifact cannot be published under a version it does not contain.
AAPT=$(ls "$HOME"/Library/Android/sdk/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1 || true)
if [ -n "$AAPT" ]; then
  BADGING=$("$AAPT" dump badging "$APK")
  VERSION=$(echo "$BADGING" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
  CODE=$(echo "$BADGING" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")
else
  echo "==> aapt2 not found; falling back to build.gradle.kts"
  VERSION=$(sed -n 's/.*versionName = "\(.*\)".*/\1/p' android/app/build.gradle.kts)
  CODE=$(sed -n 's/.*versionCode = \([0-9]*\).*/\1/p' android/app/build.gradle.kts)
fi
[ -n "$VERSION" ] || { echo "Could not read the version from the APK." >&2; exit 1; }

# One account is the normal case. More than one is ambiguous enough that
# guessing would eventually publish to the wrong Drive.
#
# Written without arrays or mapfile: macOS still ships bash 3.2, and a release
# script that only runs on a machine with a newer bash installed is a release
# script that fails on somebody else's laptop.
DRIVES=$(find "$HOME/Library/CloudStorage" -maxdepth 1 -name 'GoogleDrive-*' 2>/dev/null || true)
COUNT=$(printf '%s' "$DRIVES" | grep -c . || true)

if [ "$COUNT" -eq 0 ]; then
  echo "Google Drive for desktop is not mounted." >&2
  echo "Install it and sign in, then run this again." >&2
  exit 1
fi
if [ "$COUNT" -gt 1 ]; then
  echo "More than one Google account is mounted; not guessing which:" >&2
  echo "$DRIVES" | sed 's/^/    /' >&2
  exit 1
fi

DEST="$DRIVES/My Drive"
[ -d "$DEST" ] || { echo "No 'My Drive' under $DRIVES — is Drive still syncing?" >&2; exit 1; }

TARGET="$DEST/CommissionersCartel-$VERSION.apk"
if [ -e "$TARGET" ] && [ "$FORCE" != true ]; then
  echo "CommissionersCartel-$VERSION.apk is already in Drive."
  echo "A version that has been handed out should not quietly change underneath"
  echo "it. Bump the version, or pass --force if you are sure."
  exit 1
fi

echo "==> Publishing $VERSION (versionCode $CODE)"
cp "$APK" "$TARGET"

# Drive uploads in the background, so a copy that returns is not yet a copy
# that anybody else can download. Compare sizes to catch a truncated write.
LOCAL=$(stat -f%z "$APK")
COPIED=$(stat -f%z "$TARGET")
[ "$LOCAL" = "$COPIED" ] || { echo "Copied file is $COPIED bytes, expected $LOCAL." >&2; exit 1; }

echo "    $TARGET"
echo "    $LOCAL bytes"
echo
echo "Drive syncs in the background; give it a moment before sharing the link."
