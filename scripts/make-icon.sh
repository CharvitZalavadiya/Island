#!/bin/bash
# Draws the app icon and turns it into Packaging/AppIcon.icns. Uses only tools that ship with macOS
# (swift, sips, iconutil). Run it again after changing scripts/make-icon.swift; the result is kept in the repo
# so a normal build does not need to.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=build/icon
rm -rf "$WORK"
mkdir -p "$WORK/AppIcon.iconset"

swift scripts/make-icon.swift "$WORK/icon_1024.png"

# size, file name (the @2x files hold twice the pixels of the size in their name)
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" "512 icon_512x512"; do
    set -- $spec
    sips -z "$1" "$1" "$WORK/icon_1024.png" --out "$WORK/AppIcon.iconset/$2.png" >/dev/null
done
cp "$WORK/icon_1024.png" "$WORK/AppIcon.iconset/icon_512x512@2x.png"

iconutil -c icns "$WORK/AppIcon.iconset" -o Packaging/AppIcon.icns
echo "Wrote Packaging/AppIcon.icns"
