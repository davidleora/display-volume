#!/bin/sh
# ./build.sh          build build/Display Volume.app (Apple Silicon + Intel)
# ./build.sh test     run the core tests
# ./build.sh install  build, copy to /Applications and start it
# ./build.sh release  build and zip it for a GitHub release
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="$ROOT/build/Display Volume.app"
MIN_MACOS=14.4

cd "$ROOT"
mkdir -p build

if [ "${1:-}" = test ]; then
  swiftc -swift-version 5 -sdk "$SDK" Sources/Core.swift tests/main.swift -o build/core-tests
  build/core-tests
  exit 0
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -sdk "$SDK" -target "$arch-apple-macos$MIN_MACOS" Sources/*.swift -o "build/DisplayVolume-$arch"
done
lipo -create build/DisplayVolume-arm64 build/DisplayVolume-x86_64 -output "$APP/Contents/MacOS/DisplayVolume"
codesign --force --sign - --identifier com.davidleora.display-volume "$APP"
echo "built $APP"

case "${1:-}" in
  install)
    pkill -x DisplayVolume 2>/dev/null && sleep 1 || true
    rm -rf "/Applications/Display Volume.app"
    ditto "$APP" "/Applications/Display Volume.app"
    open "/Applications/Display Volume.app"
    echo "installed /Applications/Display Volume.app"
    ;;
  release)
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
    zip="build/Display-Volume-$version.zip"
    rm -f "$zip"
    ditto -c -k --keepParent "$APP" "$zip"
    echo "zipped $zip"
    ;;
esac
