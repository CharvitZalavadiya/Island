#!/bin/bash
# Builds build/Island.app from the Swift package.
#
#   ISLAND_UNIVERSAL=1        build for Apple Silicon AND Intel Macs (a release does); default: Apple Silicon only, which is quicker
#   ISLAND_SIGN_IDENTITY=...  who signs it ("-" for ad-hoc). Default: your Apple Development identity if there is one (it keeps
#                             macOS permissions across rebuilds on your own Mac), else ad-hoc.
#   ISLAND_HARDENED=1         sign with the hardened runtime and Packaging/Island.entitlements (needed to notarize; only
#                             useful with a "Developer ID Application" identity)
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64)
CLANG_ARCHS=(-arch arm64 -arch arm64e)
if [ "${ISLAND_UNIVERSAL:-0}" = "1" ]; then
    ARCHS=(--arch arm64 --arch x86_64)
    CLANG_ARCHS=(-arch arm64 -arch arm64e -arch x86_64)
fi

swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP=build/Island.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Island" "$APP/Contents/MacOS/Island"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The helper that reads and controls "Now Playing" for the player (explained at the top of the file).
clang -dynamiclib -fobjc-arc -Wall "${CLANG_ARCHS[@]}" -framework Foundation \
    Packaging/NowPlayingAdapter.m -o "$APP/Contents/Resources/NowPlayingAdapter.dylib"

ID="${ISLAND_SIGN_IDENTITY:-}"
if [ -z "$ID" ]; then
    ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$ID" ]; then
    echo "warning: no signing identity found; signing ad-hoc (macOS permissions may reset after rebuilds)" >&2
    ID="-"
fi

SIGN=(--force --sign "$ID")
if [ "${ISLAND_HARDENED:-0}" = "1" ]; then
    SIGN+=(--options runtime --timestamp --entitlements Packaging/Island.entitlements)
fi
codesign "${SIGN[@]}" "$APP/Contents/Resources/NowPlayingAdapter.dylib"
codesign "${SIGN[@]}" "$APP"
echo "Built $APP (signed with: $ID)"
