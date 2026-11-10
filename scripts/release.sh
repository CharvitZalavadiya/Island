#!/bin/bash
# Makes everything to publish for a release, in dist/: Island-<version>.dmg and its checksum.
#
# It builds a UNIVERSAL app (Apple Silicon and Intel), signs it, puts it in a disk image, and checks the result. It does not
# publish anything: the last lines it prints are the commands for that.
#
# Signing: with a "Developer ID Application" certificate in your keychain the app is signed with it (hardened runtime), and
# if ISLAND_NOTARY_PROFILE names a saved `notarytool` credential it is also notarized and stapled, so macOS opens it without
# any warning. Without one it is signed ad-hoc: it works, but macOS asks the person to press "Open Anyway" once (the
# READ ME FIRST file in the disk image says how).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/.*islandVersion = "\(.*\)".*/\1/p' Sources/IslandCore/Version.swift)"
if ! echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "error: Sources/IslandCore/Version.swift must say islandVersion = \"MAJOR.MINOR.PATCH\" (found: '$VERSION')." >&2
    exit 1
fi

DEVELOPER_ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
if [ -n "$DEVELOPER_ID" ]; then
    export ISLAND_SIGN_IDENTITY="$DEVELOPER_ID" ISLAND_HARDENED=1
    SIGNING="Developer ID ($DEVELOPER_ID)"
else
    export ISLAND_SIGN_IDENTITY="-"
    SIGNING="ad-hoc (no Developer ID certificate found)"
fi
export ISLAND_UNIVERSAL=1

DMG="dist/Island-$VERSION.dmg"
mkdir -p dist
ISLAND_DMG="$DMG" scripts/make-dmg.sh

if [ -n "$DEVELOPER_ID" ] && [ -n "${ISLAND_NOTARY_PROFILE:-}" ]; then
    echo "Notarizing (this takes a few minutes)..."
    xcrun notarytool submit "$DMG" --keychain-profile "$ISLAND_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

( cd dist && shasum -a 256 "Island-$VERSION.dmg" > "Island-$VERSION.dmg.sha256" )

echo
echo "== Checks"
APP=build/Island.app
echo "version:       $VERSION   (app says: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"))"
echo "signing:       $SIGNING"
echo "architectures: $(lipo -archs "$APP/Contents/MacOS/Island")   (adapter: $(lipo -archs "$APP/Contents/Resources/NowPlayingAdapter.dylib"))"
echo "minimum macOS: $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")   (binary: $(vtool -show-build "$APP/Contents/MacOS/Island" | awk '/minos/ {print $2}' | sort -u | tr '\n' ' '))"
codesign --verify --deep --strict "$APP" && echo "signature:     valid"
spctl --assess --type execute "$APP" 2>&1 | sed 's/^/gatekeeper:    /' || true
echo "disk image:    $(du -h "$DMG" | cut -f1)  $DMG"
cat "dist/Island-$VERSION.dmg.sha256"
echo
echo "== Publishing"
echo "Normally you do not run this by hand: merging into main with a NEW version in Sources/IslandCore/Version.swift makes the"
echo "Release workflow build and publish it (see docs/distribution.md). To publish these files yourself instead:"
echo "  gh release create v$VERSION $DMG dist/Island-$VERSION.dmg.sha256 --title \"Island $VERSION\" --notes-file <(.github/scripts/release-notes.sh $VERSION)"
