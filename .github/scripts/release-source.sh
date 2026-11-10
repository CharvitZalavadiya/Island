#!/bin/bash
# Says how a commit on main got there, for the release workflow: only a merged pull request into main publishes a release.
#
#   release-source.sh <owner/repo> <commit>
#
# Prints "pull-request <number>" when the commit came in through a merged pull request into main, and "direct-push" when it
# did not (someone pushed to main directly). GitHub can take a few seconds after a merge to link the commit to its pull
# request, so a missing answer is asked for again a few times before it counts. If GitHub cannot be asked at all this fails
# (exit 2) instead of guessing: a failed run can simply be run again, a wrong guess could publish or hold back a release.
#
# RELEASE_SOURCE_TRIES (default 6) and RELEASE_SOURCE_WAIT (default 5 seconds) exist for the tests.
set -uo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: release-source.sh <owner/repo> <commit>" >&2
    exit 64
fi
repo="$1"
commit="$2"
tries="${RELEASE_SOURCE_TRIES:-6}"
wait="${RELEASE_SOURCE_WAIT:-5}"

asked=0
for ((try = 1; try <= tries; try++)); do
    if json="$(gh api "repos/$repo/commits/$commit/pulls" 2>/dev/null)" \
        && number="$(printf '%s' "$json" | jq -r '[.[] | select(.merged_at != null and .base.ref == "main")] | first | .number // empty')"; then
        asked=1
        if [ -n "$number" ]; then
            echo "pull-request $number"
            exit 0
        fi
    fi
    [ "$try" -lt "$tries" ] && sleep "$wait"
done

if [ "$asked" -eq 0 ]; then
    echo "error: could not ask GitHub which pull request commit $commit belongs to" >&2
    exit 2
fi
echo "direct-push"
