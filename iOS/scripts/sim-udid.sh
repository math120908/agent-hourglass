#!/usr/bin/env bash
# Print the UDID of the available simulator with this exact name on iOS <os>.
set -euo pipefail
name="$1"; os="$2"
runtime="com.apple.CoreSimulator.SimRuntime.iOS-${os//./-}"
udid="$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
devs = json.load(sys.stdin)["devices"].get(sys.argv[1], [])
print(next((d["udid"] for d in devs if d["name"] == sys.argv[2]), ""))
' "$runtime" "$name")"
if [ -z "$udid" ]; then
    echo "no simulator \"$name\" on iOS $os" >&2
    exit 1
fi
echo "$udid"
