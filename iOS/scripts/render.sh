#!/usr/bin/env bash
# Launch the app with --render latest and copy the PNGs to iOS/docs/screenshots/.
# Usage: render.sh <app path>   (run after build)
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
ios="$(cd "$dir/.." && pwd)"
udid="$("$dir/sim-udid.sh" "${SIM_NAME:-iPhone 17}" "${SIM_OS:-26.0}")"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl install "$udid" "$1"
container="$(xcrun simctl get_app_container "$udid" cc.kuoc.agent-hourglass.ios data)"
out="$container/Documents/renders/latest"
rm -rf "$out"
# Launch directly: reinstalling via run-sim.sh can move the data container.
xcrun simctl terminate "$udid" cc.kuoc.agent-hourglass.ios 2>/dev/null || true
xcrun simctl launch "$udid" cc.kuoc.agent-hourglass.ios --render latest
for _ in $(seq 60); do
    [ -n "$(ls -A "$out" 2>/dev/null)" ] && break
    sleep 1
done
if [ -z "$(ls -A "$out" 2>/dev/null)" ]; then
    echo "render: no output in $out after 60s" >&2
    exit 1
fi
sleep 1  # let the last file finish writing
mkdir -p "$ios/docs/screenshots"
cp -R "$out/." "$ios/docs/screenshots/"
(cd "$out" && find . -name '*.png' | sed "s|^\./|$ios/docs/screenshots/|")
