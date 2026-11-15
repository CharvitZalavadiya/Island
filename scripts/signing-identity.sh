#!/bin/bash
# Chooses the identity a local build is signed with, so every build is signed by the SAME one.
#
# macOS remembers the permissions given to an app (calendar, camera, folders, accessibility...) by who signed it. A build signed
# by another identity is, to macOS, another app, and it asks for everything again. With two or more "Apple Development"
# certificates in the keychain, taking "the first" is a gamble that can flip between builds, so the choice is remembered.
#
#   security find-identity -v -p codesigning | scripts/signing-identity.sh PIN_FILE
#
# Reads the identities from standard input (the output of `security find-identity`). PIN_FILE remembers the one used last
# ("HASH<TAB>NAME"). Prints "HASH<TAB>NAME" of the one to use: the remembered one while it is still there, otherwise the first
# "Apple Development" one (and remembers it), or nothing if there is none. Says on standard error when the identity changes,
# because that is the one time macOS asks for the permissions again.
set -euo pipefail

pin_file="${1:?usage: signing-identity.sh PIN_FILE}"
pinned=""
[ -f "$pin_file" ] && pinned="$(head -n 1 "$pin_file")"
pinned_hash="${pinned%%$'\t'*}"
pinned_name="${pinned#*$'\t'}"

upper() { printf '%s' "$1" | tr 'a-f' 'A-F'; }

# A line of `security find-identity`:  1) 40 hex digits "Apple Development: Name (TEAMID)"
pattern='^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-Fa-f]{40})[[:space:]]+"(Apple Development:[^"]*)"'
first=""
chosen=""
while IFS= read -r line; do
    [[ "$line" =~ $pattern ]] || continue
    hash="${BASH_REMATCH[1]}"
    name="${BASH_REMATCH[2]}"
    [ -n "$first" ] || first="$hash"$'\t'"$name"
    if [ -n "$pinned_hash" ] && [ "$(upper "$hash")" = "$(upper "$pinned_hash")" ]; then
        chosen="$hash"$'\t'"$name"
    fi
done
[ -n "$chosen" ] || chosen="$first"

if [ -z "$chosen" ]; then
    [ -z "$pinned" ] || echo "warning: the identity this app was signed with before (\"$pinned_name\") is no longer available" >&2
    exit 0
fi
if [ -n "$pinned" ] && [ "$chosen" != "$pinned" ]; then
    echo "warning: the signing identity changed from \"$pinned_name\" to \"${chosen#*$'\t'}\": macOS will ask for the permissions again, once" >&2
fi
mkdir -p "$(dirname "$pin_file")"
printf '%s\n' "$chosen" > "$pin_file"
printf '%s\n' "$chosen"
