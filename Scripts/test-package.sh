#!/usr/bin/env bash
#
# Runs the CartelKit tests without needing Xcode.
#
# `swift test` normally finds swift-testing via Xcode's platform path. With only
# Command Line Tools installed, the framework exists but SwiftPM doesn't look
# there, so we point it at both the framework and its interop dylib by hand.
#
# If you have full Xcode installed, plain `swift test` works and so does
# Cmd-U in the IDE — this script is the no-Xcode fallback.
set -euo pipefail

cd "$(dirname "$0")/../Packages/CartelKit"

CLT="$(xcode-select -p)"
FRAMEWORKS="$CLT/Library/Developer/Frameworks"
INTEROP="$CLT/Library/Developer/usr/lib"

if [ -d "$FRAMEWORKS/Testing.framework" ] && [ ! -d "$CLT/Platforms" ]; then
  echo "==> Command Line Tools toolchain: adding swift-testing search paths"
  exec swift test --disable-xctest --enable-swift-testing \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$INTEROP" \
    "$@"
fi

echo "==> Full Xcode toolchain"
exec swift test "$@"
