#!/usr/bin/env bash
# Notarize, staple, and zip a signed app. Usage: scripts/release.sh <app> <notarytool keychain profile>
set -euo pipefail
app="$1"; profile="$2"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
mkdir -p dist
submit="dist/submit-$version.zip"
ditto -c -k --keepParent "$app" "$submit"
xcrun notarytool submit "$submit" --keychain-profile "$profile" --wait
rm -f "$submit"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl -a -vv -t exec "$app"
out="dist/AgentHourglass-$version.zip"
ditto -c -k --keepParent "$app" "$out"
echo "release: $out"
