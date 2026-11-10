#!/bin/bash
# Builds a disk image: Island.app, an Applications shortcut to drag it onto, and a short "read me first".
# Uses macOS's own diskutil (the replacement for the deprecated `hdiutil create`), so nothing needs installing.
#
#   ISLAND_DMG=path      where to put it (default build/Island.dmg)
#   ISLAND_SKIP_BUILD=1  use the build/Island.app that is already there instead of building one
# (ISLAND_UNIVERSAL, ISLAND_SIGN_IDENTITY and ISLAND_HARDENED are passed on to build-app.sh.)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${ISLAND_DMG:-build/Island.dmg}"
if [ "${ISLAND_SKIP_BUILD:-0}" != "1" ]; then scripts/build-app.sh; fi

STAGE=build/dmg
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE" "$(dirname "$OUT")"
cp -R build/Island.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Packaging/ReadMeFirst.txt "$STAGE/READ ME FIRST.txt"

diskutil image create from --format UDZO --volumeName Island "$STAGE" "$OUT"
rm -rf "$STAGE"
echo "Built $OUT"
