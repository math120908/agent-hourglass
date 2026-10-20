#!/bin/bash
# Usage: ./build.sh [identity]   identity defaults to "-" (ad-hoc)
set -euo pipefail
cd "$(dirname "$0")"
ID="${1:--}"
xcodegen generate --quiet
xcodebuild -project ClaudeUsageSpike.xcodeproj -scheme ClaudeUsageSpike -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="$ID" CODE_SIGNING_ALLOWED=YES -quiet build
APP=build/Build/Products/Release/ClaudeUsageSpike.app
codesign --force -s "$ID" "$APP"
pkill -x ClaudeUsageSpike || true
rm -rf ~/Applications/ClaudeUsageSpike.app
mkdir -p ~/Applications
cp -R "$APP" ~/Applications/
codesign -dvv ~/Applications/ClaudeUsageSpike.app 2>&1 | grep -E 'Authority|Signature|CDHash|Identifier'
codesign -d -r- ~/Applications/ClaudeUsageSpike.app 2>&1 | tail -1
