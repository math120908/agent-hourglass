#!/usr/bin/env bash
# Stamp 1.0.<patch> into the built app's Info.plist.
# Builds from master bump the patch counter in .build-number and tag v1.0.<patch>; other branches reuse it with a -dev suffix.
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

# Master builds also tag the commit they were built from (annotated, pushed), so every
# installed version has a matching tag. An existing tag is never moved.
if [ "$(git rev-parse --abbrev-ref HEAD)" = master ]; then
  tag="v$version"
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "tag $tag already exists, not moving it"
  else
    git tag -a "$tag" HEAD -m "Build $tag"
    git push -q origin "refs/tags/$tag" || echo "warning: could not push $tag (push it later: git push origin $tag)"
    echo "tagged $tag at $(git rev-parse --short HEAD)"
  fi
fi
