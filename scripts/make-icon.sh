#!/usr/bin/env bash
# Regenerate App/Resources/AppIcon.icns from App/Resources/AppIcon.svg.
# Each size is rendered from the SVG directly (no PNG downscaling).
set -euo pipefail
cd "$(dirname "$0")/.."
SVG=App/Resources/AppIcon.svg
OUT=App/Resources/AppIcon.icns
TMP=$(mktemp -d)
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  rsvg-convert -w "$s" -h "$s" "$SVG" -o "$SET/icon_${s}x${s}.png"
  rsvg-convert -w $((s * 2)) -h $((s * 2)) "$SVG" -o "$SET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$SET" -o "$OUT"
rm -rf "$TMP"
echo "wrote $OUT"
