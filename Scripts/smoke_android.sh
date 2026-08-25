#!/usr/bin/env bash
#
# Installs the release APK on a running emulator and checks it actually opens.
#
# This exists because a release build once shipped that could not launch at
# all: R8 shrinking removed a constructor Room finds by name, and nothing in
# the build, the unit tests or the debug build could see it. Only running the
# minified APK finds that class of fault, so the minified APK gets run.
#
# Usage:
#   ./Scripts/smoke_android.sh            # build, install, launch, walk tabs
#   ./Scripts/smoke_android.sh --no-build # use the APK already built
set -euo pipefail

cd "$(dirname "$0")/.."

export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

APK="android/app/build/outputs/apk/release/app-release.apk"
PACKAGE="com.commissionerscartel.app"

if [ "${1:-}" != "--no-build" ]; then
  echo "==> Building the release APK"
  (cd android && ./gradlew --quiet assembleRelease)
fi

if ! adb devices | grep -q "device$"; then
  echo "No emulator or device is attached. Start one with:"
  echo "  emulator -avd cartel &"
  exit 1
fi

echo "==> Installing"
adb uninstall "$PACKAGE" >/dev/null 2>&1 || true
adb install -r "$APK" >/dev/null

echo "==> Launching"
adb logcat -c
adb shell am start -n "$PACKAGE/.MainActivity" >/dev/null
sleep 8

fail() {
  echo
  echo "FAILED: $1"
  echo
  adb logcat -d -b crash -v brief | grep -A 25 "FATAL EXCEPTION" | head -30
  exit 1
}

adb shell pidof "$PACKAGE" >/dev/null 2>&1 || fail "the app died on launch"

# Every tab, since shrinking tends to break one screen rather than all of them.
echo "==> Walking the tabs"
for x in 150 330 500 670 840; do
  adb shell input tap "$x" 2270 >/dev/null 2>&1
  sleep 3
  adb shell pidof "$PACKAGE" >/dev/null 2>&1 || fail "the app died while navigating"
done

if adb logcat -d -b crash -v brief | grep -q "$PACKAGE"; then
  fail "something crashed while navigating"
fi

VERSION=$(adb shell dumpsys package "$PACKAGE" | grep versionName | head -1 | tr -d ' ')
echo
echo "The release build opens and every tab survives. $VERSION"
