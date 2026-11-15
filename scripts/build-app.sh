#!/bin/bash
# Builds build/Island.app from the Swift package.
#
#   ISLAND_UNIVERSAL=1        build for Apple Silicon AND Intel Macs (a release does); default: Apple Silicon only, which is quicker
#   ISLAND_SIGN_IDENTITY=...  who signs it ("-" for ad-hoc). Default: your Apple Development identity if there is one, else ad-hoc.
#                             The identity is remembered (build/.signing-identity) and used every time, because macOS keeps the
#                             permissions you gave the app (calendar, camera, folders...) only for builds signed by the same one;
#                             see scripts/signing-identity.sh.
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

# macOS decides how an app looks (Liquid Glass sliders, switches, buttons, or the old flat style) from the SDK the app says it
# was built with. A release build is linked through LTO, and with Xcode 27 the linker then writes the app's minimum macOS
# version (14.2) in that place, so macOS treated Island as an old app and drew old-style controls. This writes the SDK that
# really was used (the minimum version stays as it is). It must happen before signing, which covers the file.
stamp_sdk() {
    local binary="$1" sdk have minimum
    sdk="$(xcrun --sdk macosx --show-sdk-version)"
    have="$(vtool -show-build "$binary" | awk '/ sdk / { print $2; exit }')"
    minimum="$(vtool -show-build "$binary" | awk '/ minos / { print $2; exit }')"
    if [ -z "$sdk" ] || [ -z "$minimum" ]; then
        echo "warning: could not read the SDK version, so the app is not stamped with it (controls may look old-style)" >&2
    elif [ "$have" != "$sdk" ]; then
        vtool -set-build-version macos "$minimum" "$sdk" -replace -output "$binary.stamped" "$binary" >/dev/null
        mv "$binary.stamped" "$binary"
        echo "Stamped the app with the macOS $sdk SDK it was built with (it said $have; the minimum stays $minimum)"
    fi
}
stamp_sdk "$APP/Contents/MacOS/Island"

cp Packaging/Info.plist "$APP/Contents/Info.plist"
# One place says what version this is: Sources/IslandCore/Version.swift. The built app is stamped from it.
VERSION="$(sed -n 's/.*islandVersion = "\(.*\)".*/\1/p' Sources/IslandCore/Version.swift)"
if ! echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "error: Sources/IslandCore/Version.swift must say islandVersion = \"MAJOR.MINOR.PATCH\" (found: '$VERSION')" >&2
    exit 1
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The helper that reads and controls "Now Playing" for the player (explained at the top of the file).
clang -dynamiclib -fobjc-arc -Wall "${CLANG_ARCHS[@]}" -framework Foundation \
    Packaging/NowPlayingAdapter.m -o "$APP/Contents/Resources/NowPlayingAdapter.dylib"

ID="${ISLAND_SIGN_IDENTITY:-}"
SHOWN_ID="$ID"
if [ -z "$ID" ]; then
    # The same identity every time, even with several certificates in the keychain: a different one makes macOS ask again.
    CHOSEN="$(security find-identity -v -p codesigning 2>/dev/null | scripts/signing-identity.sh build/.signing-identity || true)"
    if [ -n "$CHOSEN" ]; then
        ID="${CHOSEN%%$'\t'*}"            # signing by the certificate's hash is exact, even if two certificates share a name
        SHOWN_ID="${CHOSEN#*$'\t'}"
    fi
fi
if [ -z "$ID" ]; then
    echo "warning: no signing identity found, so the app is signed ad hoc. macOS then treats every build as a new app and asks for" >&2
    echo "         the calendar, camera and folder permissions again each time. A free Apple Development certificate fixes that" >&2
    echo "         (Xcode > Settings > Accounts > Manage Certificates > +)." >&2
    ID="-"
    SHOWN_ID="ad hoc"
fi

SIGN=(--force --sign "$ID")
if [ "${ISLAND_HARDENED:-0}" = "1" ]; then
    SIGN+=(--options runtime --timestamp --entitlements Packaging/Island.entitlements)
fi
codesign "${SIGN[@]}" "$APP/Contents/Resources/NowPlayingAdapter.dylib"
codesign "${SIGN[@]}" "$APP"

# macOS keeps ONE set of permissions per app id. A second copy with the same id signed differently (an installed release is signed
# ad hoc, a build made here is signed by you) shares that one set: whichever is opened second asks for everything again.
note_other_copies() {
    local mine other theirs
    mine="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^#* *designated => //p' || true)"
    for other in /Applications/Island.app "$HOME/Applications/Island.app"; do
        [ -d "$other" ] || continue
        theirs="$(codesign -d -r- "$other" 2>&1 | sed -n 's/^#* *designated => //p' || true)"
        if [ "$mine" != "$theirs" ]; then
            echo "note: $other is signed differently from this build. macOS keeps one set of permissions for both, so whichever" >&2
            echo "      you open second asks for them again. Use one copy only, or replace that one with this build." >&2
        fi
    done
}
note_other_copies

echo "Built $APP (signed with: $SHOWN_ID)"
