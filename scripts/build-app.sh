#!/bin/bash
# Builds a signed build/Island.app from the Swift package.
# Set ISLAND_SIGN_IDENTITY to override the signing identity.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

APP=build/Island.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Island" "$APP/Contents/MacOS/Island"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The helper that reads and controls "Now Playing" for the player (explained at the top of the file).
clang -dynamiclib -fobjc-arc -Wall -arch arm64 -arch arm64e -framework Foundation \
    Packaging/NowPlayingAdapter.m -o "$APP/Contents/Resources/NowPlayingAdapter.dylib"

ID="${ISLAND_SIGN_IDENTITY:-}"
if [ -z "$ID" ]; then
    ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$ID" ]; then
    echo "warning: no Apple Development identity found; signing ad-hoc (macOS permissions may reset after rebuilds)" >&2
    ID="-"
fi

codesign --force --sign "$ID" "$APP/Contents/Resources/NowPlayingAdapter.dylib"
codesign --force --deep --sign "$ID" "$APP"
echo "Built $APP (signed with: $ID)"
