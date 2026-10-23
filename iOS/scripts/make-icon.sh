#!/usr/bin/env bash
# Render the iOS app icon (full-bleed, opaque) from the Mac SVG.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/App/Resources/AppIcon.svg"
rel="iOS/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
out="$root/$rel"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed -e 's/viewBox="0 0 1024 1024"/viewBox="100 100 824 824"/' \
    -e '/<rect x="100" y="100" width="824" height="824"/{s/ rx="185"//;s/ filter="url(#shadow)"//;}' \
    "$src" > "$tmp/icon.svg"
rsvg-convert -w 1024 -h 1024 -b '#EFE5D6' "$tmp/icon.svg" -o "$tmp/icon.png"
magick "$tmp/icon.png" -alpha off "$out"
echo "wrote $rel"
