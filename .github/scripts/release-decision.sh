#!/bin/bash
# Decides whether a push to main should publish a release.
#
#   .github/scripts/release-decision.sh <version in the file> [versions or tags already released...]
#
# Prints   release   if this version is new: build whatever is on main and publish it as this version.
# Prints   skip      if this version already has a release: do nothing (merging without raising the version never releases).
# Fails if the version is LOWER than one already released (a mistake: the release marked "latest" would go backwards).
set -euo pipefail

VERSION="${1:?usage: release-decision.sh <version> [already released versions or tags...]}"
shift
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: '$VERSION' is not a version like 1.2.3" >&2
    exit 1
fi

released=()
for item in "$@"; do
    item="${item#v}"
    if [[ "$item" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then released+=("$item"); fi
done

if [ "${#released[@]}" -gt 0 ]; then
    for old in "${released[@]}"; do
        if [ "$old" = "$VERSION" ]; then echo "skip"; exit 0; fi
    done
    highest="$(printf '%s\n' "${released[@]}" | sort -V | tail -1)"
    if [ "$(printf '%s\n%s\n' "$highest" "$VERSION" | sort -V | tail -1)" != "$VERSION" ]; then
        echo "error: version $VERSION is lower than $highest, which is already released. Raise the version in Sources/IslandCore/Version.swift above $highest." >&2
        exit 1
    fi
fi
echo "release"
