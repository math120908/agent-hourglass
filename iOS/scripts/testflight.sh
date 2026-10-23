#!/bin/bash
# Archive, verify, export and upload the iOS app to TestFlight (P6 Task 13).
#   testflight.sh                 preflight, archive, verify, export a local .ipa, verify it, upload that .ipa
#   testflight.sh --dry-run       same, without the upload
#   testflight.sh --verify-archive <xcarchive> <build> <commit>   verify only (tests)
#   testflight.sh --verify-ipa <ipa> <build> <commit>             verify an exported ipa (tests)
#   testflight.sh --check-export-options <plist>                  assert the export plist keys (tests)
# Env: ASC_ENV (default ~/.config/agent-hourglass/asc.env) holding exactly the lines ASC_KEY_ID=<id> and
# ASC_ISSUER_ID=<uuid> (parsed, not sourced); key at ~/.appstoreconnect/private_keys/AuthKey_<id>.p8.
# Both files must be mode 600.
# Key ID, issuer ID and the key path are never echoed. Preflight test output goes to <out>/preflight.log,
# xcodebuild and altool output to <out>/xcodebuild.log (both 600); failures show a redacted tail.
set -euo pipefail
# --verify-* paths are relative to the caller's cwd, not iOS/.
if [ $# -ge 2 ] && [[ "$1" == --verify-archive || "$1" == --verify-ipa || "$1" == --check-export-options ]] \
  && [[ "$2" != /* ]]; then
  set -- "$1" "$PWD/$2" "${@:3}"
fi
cd "$(dirname "$0")/.."

TEAM=R7V5X99HYA
APP_ID=cc.kuoc.agent-hourglass.ios
WIDGET_ID=cc.kuoc.agent-hourglass.ios.widget
GROUP=group.cc.kuoc.agent-hourglass
KC_GROUP=$TEAM.cc.kuoc.agent-hourglass.shared

die() { echo "testflight: $*" >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true; }
# MARKETING_VERSION from project.yml; the bundles must carry it.
version=$(rg -o -r '$1' '^\s*MARKETING_VERSION:\s*(\S+)' project.yml | head -1 || true)
[ -n "$version" ] || die "no MARKETING_VERSION in project.yml"

# ent_is <entitlements xml> <escaped plutil keypath> <raw|json> <want> <bundle name>: exact value check.
ent_is() {
  local got key=${2//\\/}
  got=$(printf '%s' "$1" | /usr/bin/plutil -extract "$2" "$3" -o - - 2>/dev/null) || got=missing
  [ "$got" = "$4" ] || die "verify: $5 $key is $got, want $4"
}

# Bundle checks on <app> (and its widget appex). <dist>=1 (the exported .ipa) also requires get-task-allow
# false and an Apple Distribution signature: automatic signing archives with the development identity.
verify_bundles() { # <app> <build> <commit> <dist> <label>
  local app=$1 build=$2 commit=$3 dist=$4 label=$5 appex a w b id name ent sig l team auth
  appex=$(echo "$app"/PlugIns/*.appex)
  [ -d "$app" ] || die "verify: no app in $label"
  [ -d "$appex" ] || die "verify: no widget appex in $label"
  a=$(plist CFBundleVersion "$app/Info.plist"); w=$(plist CFBundleVersion "$appex/Info.plist")
  [ "$a" = "$build" ] && [ "$w" = "$build" ] || die "verify: CFBundleVersion mismatch (app $a, widget $w, want $build)"
  a=$(plist CFBundleShortVersionString "$app/Info.plist"); w=$(plist CFBundleShortVersionString "$appex/Info.plist")
  [ -n "$a" ] && [ "$a" = "$w" ] || die "verify: CFBundleShortVersionString mismatch (app $a, widget $w)"
  [ "$a" = "$version" ] || die "verify: CFBundleShortVersionString $a is not project.yml MARKETING_VERSION $version"
  [ "$(plist CFBundleIdentifier "$app/Info.plist")" = "$APP_ID" ] || die "verify: app bundle id"
  [ "$(plist CFBundleIdentifier "$appex/Info.plist")" = "$WIDGET_ID" ] || die "verify: widget bundle id"
  [ "$(plist GitCommit "$app/Info.plist")" = "$commit" ] || die "verify: GitCommit is not $commit"
  for b in "$app:$APP_ID" "$appex:$WIDGET_ID"; do
    id=${b##*:}; b=${b%:*}; name=$(basename "$b")
    ent=$(codesign -d --entitlements :- "$b" 2>/dev/null || true)
    ent_is "$ent" application-identifier raw "$TEAM.$id" "$name"
    ent_is "$ent" 'com\.apple\.developer\.team-identifier' raw "$TEAM" "$name"
    ent_is "$ent" 'com\.apple\.security\.application-groups' json "[\"$GROUP\"]" "$name"
    ent_is "$ent" keychain-access-groups json "[\"$KC_GROUP\"]" "$name"
    [ "$dist" = 1 ] && ent_is "$ent" get-task-allow raw false "$name"
    sig=$(codesign -dvv "$b" 2>&1 || true); team=; auth=
    while IFS= read -r l; do
      case $l in
        TeamIdentifier=*) team=${l#*=} ;;
        Authority=*) [ -n "$auth" ] || auth=${l#*=} ;;
      esac
    done <<< "$sig"
    [ "$team" = "$TEAM" ] || die "verify: $name signing team is $team, want $TEAM"
    if [ "$dist" = 1 ] && [[ "$auth" != "Apple Distribution: "*" ($TEAM)" ]]; then
      die "verify: $name is not signed by Apple Distribution ($TEAM): $auth"
    fi
  done
  echo "testflight: $label verified $a ($build) $commit"
}

verify_archive() { # <xcarchive> <build> <commit>
  verify_bundles "$(echo "$1"/Products/Applications/*.app)" "$2" "$3" 0 archive
}

verify_ipa() { # <ipa> <build> <commit>
  local tmp; tmp=$(mktemp -d)
  ditto -x -k "$1" "$tmp" || { rm -rf "$tmp"; die "verify: cannot unpack ipa"; }
  ( verify_bundles "$(echo "$tmp"/Payload/*.app)" "$2" "$3" 1 ipa ) || { rm -rf "$tmp"; exit 1; }
  rm -rf "$tmp"
}

# check_export_options <plist>: the keys the export relies on. destination export keeps the ipa local so
# it is verified before upload; the upload then sends that same file.
check_export_options() {
  local kv k got
  for kv in destination=export method=app-store-connect signingStyle=automatic "teamID=$TEAM" \
    testFlightInternalTestingOnly=true manageAppVersionAndBuildNumber=false; do
    k=${kv%%=*}; got=$(plist "$k" "$1")
    [ "$got" = "${kv#*=}" ] || die "ExportOptions: $k is ${got:-missing}, want ${kv#*=}"
  done
}

dry=0
case "${1:-}" in
  --verify-archive|--verify-ipa)
    [ $# -eq 4 ] || die "usage: $1 <path> <build> <commit>"
    if [ "$1" = --verify-archive ]; then verify_archive "$2" "$3" "$4"; else verify_ipa "$2" "$3" "$4"; fi
    exit 0 ;;
  --check-export-options)
    [ $# -eq 2 ] || die "usage: $1 <plist>"
    check_export_options "$2"; echo "testflight: export options ok"; exit 0 ;;
  --dry-run) [ $# -eq 1 ] || die "usage: testflight.sh [--dry-run]"; dry=1 ;;
  '') ;;
  *) die "usage: testflight.sh [--dry-run]" ;;
esac

# 1. Preflight. Cheap checks first so a missing key fails in seconds.
[ -z "$(git status --porcelain)" ] || die "dirty tree"
asc=${ASC_ENV:-$HOME/.config/agent-hourglass/asc.env}
[ -f "$asc" ] || die "missing App Store Connect env file (set ASC_ENV or create ~/.config/agent-hourglass/asc.env)"
[ "$(stat -f '%Lp' "$asc")" = 600 ] || die "App Store Connect env file must be mode 600"
# Parse asc.env, never source it: only ASC_KEY_ID=<10 [A-Z0-9]> and ASC_ISSUER_ID=<uuid>, each once, plus
# blank and # comment lines. The values live in unexported shell vars; a caller's exported ASC_* are dropped.
unset ASC_KEY_ID ASC_ISSUER_ID
kid=; iss=; n=0
re_kid='^ASC_KEY_ID=([A-Z0-9]{10})$'
re_iss='^ASC_ISSUER_ID=([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$'
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  if [[ -z "$line" || "$line" == '#'* ]]; then continue
  elif [[ "$line" =~ $re_kid ]] && [ -z "$kid" ]; then kid=${BASH_REMATCH[1]}
  elif [[ "$line" =~ $re_iss ]] && [ -z "$iss" ]; then iss=${BASH_REMATCH[1]}
  else die "App Store Connect env file line $n: only ASC_KEY_ID=<10 chars A-Z0-9> and ASC_ISSUER_ID=<uuid>, once each"
  fi
done < "$asc"
unset line
[ -n "$kid" ] && [ -n "$iss" ] || die "env file must define ASC_KEY_ID and ASC_ISSUER_ID"
p8="$HOME/.appstoreconnect/private_keys/AuthKey_${kid}.p8"
[ -f "$p8" ] || die "missing API key file in ~/.appstoreconnect/private_keys/"
[ "$(stat -f '%Lp' "$p8")" = 600 ] || die "API key file must be mode 600"
check_export_options ExportOptions.plist
security find-identity -v -p codesigning | rg -q 'Apple Distribution' || die "no Apple Distribution identity in the keychain"
# 2. Version and output dir (before the test runs, which log into it).
build=$(scripts/build-number.sh); head=$(git rev-parse HEAD); commit=$(git rev-parse --short "$head")
# check_tree: the shared worktree can change during the minutes-long tests and archive. Re-check that it
# is still clean and at the recorded commit before each step that builds or ships it.
check_tree() {
  [ -z "$(git status --porcelain)" ] || die "tree changed during run"
  [ "$(git rev-parse HEAD)" = "$head" ] || die "HEAD changed during run"
}
out=build/testflight/$build
mkdir -p "$out"; chmod 700 "$out"
# tail_log <log>: last 30 lines to stderr, with any asc.env value lines dropped.
tail_log() { tail -n 30 "$1" | rg -v -F -e "$kid" -e "$iss" >&2 || true; }
plog=$out/preflight.log; ( umask 077; : > "$plog" )
pre() { local what=$1; shift; "$@" >>"$plog" 2>&1 || { tail_log "$plog"; die "$what failed (log: $plog)"; }; }
pre "make test" make -C .. test
pre "make -C iOS test" make test

# 3. Project.
log=$out/xcodebuild.log; ( umask 077; : > "$log" )
xcodegen generate --spec project.yml --quiet
auth=(-allowProvisioningUpdates -authenticationKeyPath "$p8" -authenticationKeyID "$kid" -authenticationKeyIssuerID "$iss")
# xcodebuild with -authenticationKey* writes the key id and issuer id into *.xcdistributionlogs bundles
# in `getconf DARWIN_USER_TEMP_DIR`, even when TMPDIR is overridden. Scan that dir, and $TMPDIR too when it
# differs. Remove the bundles that appear during this run (success or failure); keep any that existed
# before. AH_DARWIN_TEMP_DIR stands in for getconf in tests.
dtmp=${AH_DARWIN_TEMP_DIR:-$(getconf DARWIN_USER_TEMP_DIR)}; dtmp=${dtmp%/}
[ -n "$dtmp" ] && [ -d "$dtmp" ] || die "cannot resolve DARWIN_USER_TEMP_DIR"
tdirs=("$dtmp"); [ -n "${TMPDIR:-}" ] && [ "${TMPDIR%/}" != "$dtmp" ] && tdirs+=("${TMPDIR%/}")
distlogs() { local d t; for t in "${tdirs[@]}"; do for d in "$t"/*.xcdistributionlogs; do [ -e "$d" ] && echo "$d"; done; done; return 0; }
pre_logs=$(distlogs)
rm_distlogs() { local d; distlogs | while IFS= read -r d; do printf '%s\n' "$pre_logs" | rg -q -x -F -- "$d" || rm -rf "$d"; done; }
# Xcode's IPA step runs /usr/bin/rsync (openrsync), which starts its local server as `rsync` from PATH.
# Homebrew rsync 3.x there rejects --extended-attributes and export fails with only "Copy failed".
# Pin `rsync` to the system one for this run.
rsbin=$(mktemp -d); ln -s /usr/bin/rsync "$rsbin/rsync"; PATH="$rsbin:$PATH"
trap 'rm_distlogs; rm -rf "$rsbin"' EXIT
run() { "$@" >>"$log" 2>&1 || { tail_log "$log"; die "$2 failed (log: $log)"; }; }

# 4. Archive.
check_tree
arc=$out/AgentHourglass.xcarchive
run xcodebuild archive -project AgentHourglassiOS.xcodeproj -scheme AgentHourglassiOS -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$arc" "${auth[@]}" \
  CURRENT_PROJECT_VERSION="$build" GIT_COMMIT="$commit" -quiet

# 5. Verify.
verify_archive "$arc" "$build" "$commit"

# 6. Export a local ipa and verify it.
check_export_options ExportOptions.plist
check_tree
run xcodebuild -exportArchive -archivePath "$arc" -exportOptionsPlist ExportOptions.plist -exportPath "$out/export" \
  "${auth[@]}"
ipa=$(echo "$out"/export/*.ipa); [ -f "$ipa" ] || die "export produced no .ipa"
verify_ipa "$ipa" "$build" "$commit"
if [ $dry -eq 1 ]; then
  echo "testflight: dry run ok $version ($build) $commit"
  exit 0
fi

# 7. Upload the verified ipa. altool reads AuthKey_<id>.p8 from ~/.appstoreconnect/private_keys (checked above).
check_tree
run xcrun altool --upload-package "$ipa" --api-key "$kid" --api-issuer "$iss"
echo "testflight: uploaded $version ($build) $commit"
