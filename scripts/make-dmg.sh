#!/bin/bash
# Builds build/Island.dmg: Island.app plus an Applications shortcut, so it can be dragged into place.
# Uses macOS's own diskutil (the replacement for the deprecated `hdiutil create`), so nothing needs installing.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh

STAGE=build/dmg
rm -rf "$STAGE" build/Island.dmg
mkdir -p "$STAGE"
cp -R build/Island.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

diskutil image create from --format UDZO --volumeName Island "$STAGE" build/Island.dmg
rm -rf "$STAGE"
echo "Built build/Island.dmg"
