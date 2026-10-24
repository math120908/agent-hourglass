#!/usr/bin/env bash
# Regenerate App/Resources/AppIcon.icns from App/Resources/AppIcon.svg
# (and AppIcon-small.svg for the 16 and 32 px slots).
# Each size is rendered from the SVG directly (no PNG downscaling).
set -euo pipefail
cd "$(dirname "$0")/.."
SVG=App/Resources/AppIcon.svg
OUT=App/Resources/AppIcon.icns
TMP=$(mktemp -d)
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
SMALL=App/Resources/AppIcon-small.svg  # simplified art for 16, 16@2x and 32
for s in 16 32 128 256 512; do
  case $s in 16) one=$SMALL two=$SMALL ;; 32) one=$SMALL two=$SVG ;; *) one=$SVG two=$SVG ;; esac
  rsvg-convert -w "$s" -h "$s" "$one" -o "$SET/icon_${s}x${s}.png"
  rsvg-convert -w $((s * 2)) -h $((s * 2)) "$two" -o "$SET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$SET" -o "$OUT"
rm -rf "$TMP"
echo "wrote $OUT"
