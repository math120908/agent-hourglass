#!/usr/bin/env bash
# Leave exactly one booted simulator (<name> on iOS <os>), fully booted, and print its UDID.
# A cold boot or a second booted sim during xcodebuild test kills the test host before it connects.
set -euo pipefail
udid="$("$(dirname "$0")/sim-udid.sh" "$1" "$2")"
xcrun simctl list devices booted -j | python3 -I -c '
import json, sys
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["udid"] != sys.argv[1]:
            print(d["udid"])
' "$udid" | while read -r other; do xcrun simctl shutdown "$other" >&2 || true; done
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >&2
echo "$udid"
