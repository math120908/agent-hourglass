#!/usr/bin/env bash
# Stamp 1.0.<patch> into the built app's Info.plist.
# Builds from master bump the patch counter in .build-number; other branches reuse it with a -dev suffix.
set -euo pipefail
plist="$1"
counter=.build-number
patch=$(cat "$counter" 2>/dev/null || echo 0)
if [ "$(git rev-parse --abbrev-ref HEAD)" = master ]; then
  patch=$((patch + 1))
  echo "$patch" > "$counter"
  version="1.0.$patch"
else
  version="1.0.$patch-dev"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $patch" "$plist"
echo "version $version"
