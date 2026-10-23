#!/bin/bash
# Archive, verify, export and upload the iOS app to TestFlight (P6 Task 13).
#   testflight.sh                 preflight, archive, verify, export with destination=upload
#   testflight.sh --dry-run       same, but export with destination=export (no upload); checks the .ipa
#   testflight.sh --verify-archive <xcarchive> <build> <commit>   verify only (tests)
# Env: ASC_ENV (default ~/.config/agent-hourglass/asc.env) defining ASC_KEY_ID and ASC_ISSUER_ID;
# key at ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8. Both files must be mode 600.
# Key ID, issuer ID and the key path are never echoed. xcodebuild output goes to <out>/xcodebuild.log (600).
# Upload fallback (manual, not automatic): if destination=upload fails after a good export, run
#   xcrun altool --upload-app -f <out>/export/*.ipa -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=R7V5X99HYA
APP_ID=cc.kuoc.agent-hourglass.ios
WIDGET_ID=cc.kuoc.agent-hourglass.ios.widget
GROUP=group.cc.kuoc.agent-hourglass
KC_GROUP=$TEAM.cc.kuoc.agent-hourglass.shared

die() { echo "testflight: $*" >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true; }

verify_archive() { # <xcarchive> <build> <commit>
  local arc=$1 build=$2 commit=$3 app appex a w ent
  app=$(echo "$arc"/Products/Applications/*.app); appex=$(echo "$app"/PlugIns/*.appex)
  [ -d "$app" ] || die "verify: no app in archive"
  [ -d "$appex" ] || die "verify: no widget appex in archive"
  a=$(plist CFBundleVersion "$app/Info.plist"); w=$(plist CFBundleVersion "$appex/Info.plist")
  [ "$a" = "$build" ] && [ "$w" = "$build" ] || die "verify: CFBundleVersion mismatch (app $a, widget $w, want $build)"
  a=$(plist CFBundleShortVersionString "$app/Info.plist"); w=$(plist CFBundleShortVersionString "$appex/Info.plist")
  [ -n "$a" ] && [ "$a" = "$w" ] || die "verify: CFBundleShortVersionString mismatch (app $a, widget $w)"
  [ "$(plist CFBundleIdentifier "$app/Info.plist")" = "$APP_ID" ] || die "verify: app bundle id"
  [ "$(plist CFBundleIdentifier "$appex/Info.plist")" = "$WIDGET_ID" ] || die "verify: widget bundle id"
  [ "$(plist GitCommit "$app/Info.plist")" = "$commit" ] || die "verify: GitCommit is not $commit"
  for b in "$app" "$appex"; do
    ent=$(codesign -d --entitlements - --xml "$b" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null || true)
    [[ "$ent" == *"$GROUP"* ]] || die "verify: $(basename "$b") lacks $GROUP"
    [[ "$ent" == *"$KC_GROUP"* ]] || die "verify: $(basename "$b") lacks keychain group"
    if echo "$ent" | rg -q -U '<key>get-task-allow</key>\s*<true/>'; then die "verify: $(basename "$b") has get-task-allow true"; fi
  done
  echo "testflight: archive verified $a ($build) $commit"
}

if [ "${1:-}" = --verify-archive ]; then
  [ $# -eq 4 ] || die "usage: --verify-archive <xcarchive> <build> <commit>"
  verify_archive "$2" "$3" "$4"; exit 0
fi
dry=0; [ "${1:-}" = --dry-run ] && dry=1

# 1. Preflight. Cheap checks first so a missing key fails in seconds.
[ -z "$(git status --porcelain)" ] || die "dirty tree"
asc=${ASC_ENV:-$HOME/.config/agent-hourglass/asc.env}
[ -f "$asc" ] || die "missing App Store Connect env file (set ASC_ENV or create ~/.config/agent-hourglass/asc.env)"
[ "$(stat -f '%Lp' "$asc")" = 600 ] || die "App Store Connect env file must be mode 600"
# shellcheck disable=SC1090
source "$asc"
[ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] || die "env file must define ASC_KEY_ID and ASC_ISSUER_ID"
p8="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[ -f "$p8" ] || die "missing API key file in ~/.appstoreconnect/private_keys/"
[ "$(stat -f '%Lp' "$p8")" = 600 ] || die "API key file must be mode 600"
security find-identity -v -p codesigning | rg -q 'Apple Distribution' || die "no Apple Distribution identity in the keychain"
make -C .. test >/dev/null || die "make test failed"
make test >/dev/null || die "make -C iOS test failed"

# 2-3. Version and project.
build=$(scripts/build-number.sh); commit=$(git rev-parse --short HEAD)
version=$(rg -o -r '$1' '^\s*MARKETING_VERSION:\s*(\S+)' project.yml | head -1)
out=build/testflight/$build
mkdir -p "$out"; chmod 700 "$out"
log=$out/xcodebuild.log; ( umask 077; : > "$log" )
xcodegen generate --spec project.yml --quiet
auth=(-allowProvisioningUpdates -authenticationKeyPath "$p8" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
run() { "$@" >>"$log" 2>&1 || { tail -n 30 "$log" | rg -v -F -e "$ASC_KEY_ID" -e "$ASC_ISSUER_ID" >&2; die "$2 failed (log: $log)"; }; }

# 4. Archive.
arc=$out/AgentHourglass.xcarchive
run xcodebuild archive -project AgentHourglassiOS.xcodeproj -scheme AgentHourglassiOS -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$arc" "${auth[@]}" \
  CURRENT_PROJECT_VERSION="$build" GIT_COMMIT="$commit" -quiet

# 5. Verify.
verify_archive "$arc" "$build" "$commit"

# 6. Export (+ upload).
opts=ExportOptions.plist
if [ $dry -eq 1 ]; then
  opts=$out/ExportOptions-dry.plist; cp ExportOptions.plist "$opts"
  /usr/libexec/PlistBuddy -c 'Set :destination export' "$opts"
fi
run xcodebuild -exportArchive -archivePath "$arc" -exportOptionsPlist "$opts" -exportPath "$out/export" "${auth[@]}"
if [ $dry -eq 1 ]; then
  ls "$out"/export/*.ipa >/dev/null 2>&1 || die "export produced no .ipa"
  echo "testflight: dry run ok $version ($build) $commit"
else
  echo "testflight: uploaded $version ($build) $commit"
fi
