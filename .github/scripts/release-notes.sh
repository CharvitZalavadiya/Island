#!/bin/bash
# Prints the release notes for a version: that version's section of CHANGELOG.md, then the install guide.
# Usage: .github/scripts/release-notes.sh 1.1.0
# Fails (so nothing is published) if CHANGELOG.md has no "## 1.1.0" section: write what changed before releasing.
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION="${1:?usage: release-notes.sh <version, like 1.1.0>}"

CHANGES="$(awk -v v="$VERSION" '
    /^## / {
        title = $0
        sub(/^## +\[?/, "", title)      # "## [1.1.0] - 2026-11-11" and "## 1.1.0" both start with 1.1.0
        if (found) exit
        n = length(v)
        if (substr(title, 1, n) == v && (length(title) == n || substr(title, n + 1, 1) ~ /[] ]/)) found = 1
        next
    }
    found { print }
' CHANGELOG.md)"

if [[ -z "${CHANGES//[[:space:]]/}" ]]; then
    echo "error: CHANGELOG.md has no '## $VERSION' section (or it is empty). Add one before releasing." >&2
    exit 1
fi

cat <<NOTES
$CHANGES

## Install

1. Download **Island-$VERSION.dmg** below and open it.
2. Drag **Island** onto **Applications**, then open Island from there.
3. The first time, macOS says it cannot verify Island (it is not signed with a paid Apple developer account). Open it anyway, once:
   - **System Settings → Privacy & Security**, scroll down, and press **Open Anyway** next to Island; or
   - in Terminal: \`xattr -dr com.apple.quarantine /Applications/Island.app\`
4. Island has no Dock icon. Point at the top middle of your screen: on a Mac with a notch it lives in the notch, on any other Mac it shows a small black notch of its own. To quit, open it and use the gear icon → **Quit Island**.

## Already have Island?

Open Island → gear icon → **Settings → Updates → Check for updates → Install and restart**. Island downloads this version, replaces itself and opens again, so there is nothing to delete and no disk image to open. macOS may ask again for permissions (camera, calendar) after an update.

*Versions before 1.1.0 cannot update themselves: install this one as described above, once.*

Needs macOS 14.2 or later. A universal app (Apple silicon and Intel). The SHA-256 of the disk image is in \`Island-$VERSION.dmg.sha256\`.
Full history: [CHANGELOG.md](https://github.com/CharvitZalavadiya/Island/blob/main/CHANGELOG.md).
NOTES
