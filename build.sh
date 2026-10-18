#!/bin/sh
# ./build.sh          build build/Display Volume.app
# ./build.sh test     run the core tests
# ./build.sh install  build, copy to /Applications and start it
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="$ROOT/build/Display Volume.app"
FLAGS="-swift-version 5 -sdk $SDK -target arm64-apple-macos14.4"

cd "$ROOT"
mkdir -p build

if [ "${1:-}" = test ]; then
  swiftc $FLAGS Sources/Core.swift tests/main.swift -o build/core-tests
  build/core-tests
  exit 0
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O $FLAGS Sources/*.swift -o "$APP/Contents/MacOS/DisplayVolume"
codesign --force --sign - --identifier com.davidleora.display-volume "$APP"
echo "built $APP"

if [ "${1:-}" = install ]; then
  pkill -x DisplayVolume 2>/dev/null && sleep 1 || true
  rm -rf "/Applications/Display Volume.app"
  ditto "$APP" "/Applications/Display Volume.app"
  open "/Applications/Display Volume.app"
  echo "installed /Applications/Display Volume.app"
fi
