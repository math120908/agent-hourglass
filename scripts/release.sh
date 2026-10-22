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

# Tag the released commit (annotated) and push the tag.
tag="v$version"
commit=$(/usr/libexec/PlistBuddy -c "Print :GitCommit" "$app/Contents/Info.plist")
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "release: tag $tag already exists, not moving it"
else
  git tag -a "$tag" "$commit" -m "Release $tag"
  git push -q origin "refs/tags/$tag"
  echo "release: tagged $tag at $commit"
fi
