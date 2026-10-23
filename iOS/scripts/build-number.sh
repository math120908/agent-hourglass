#!/bin/bash
# Prints the build number YYMMDD.HMMSS (UTC; second component HHMMSS as an integer, no leading zeros).
# BUILD_NUMBER_NOW=YYYY-MM-DDTHH:MM:SSZ overrides the clock (tests).
set -euo pipefail
if [ -n "${BUILD_NUMBER_NOW:-}" ]; then
  stamp=$(TZ=UTC date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$BUILD_NUMBER_NOW" '+%y%m%d %H%M%S')
else
  stamp=$(date -u '+%y%m%d %H%M%S')
fi
day=${stamp% *}; t=${stamp#* }
echo "$day.$((10#$t))"
