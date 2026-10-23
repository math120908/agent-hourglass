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
# The app writes into subfolders (e.g. app/) and exits; wait until the PNG count stops changing.
pngs() { { find "$out" -name '*.png' 2>/dev/null || true; } | wc -l | tr -d ' '; }
prev=-1
for _ in $(seq 120); do
    n="$(pngs)"
    [ "$n" -gt 0 ] && [ "$n" = "$prev" ] && break
    prev="$n"
    sleep 2
done
if [ "$(pngs)" -eq 0 ]; then
    echo "render: no PNGs in $out after 240s" >&2
    exit 1
fi
mkdir -p "$ios/docs/screenshots"
cp -R "$out/." "$ios/docs/screenshots/"
(cd "$out" && find . -name '*.png' | sort | sed "s|^\./|$ios/docs/screenshots/|")
echo "render: $(pngs) PNGs"
