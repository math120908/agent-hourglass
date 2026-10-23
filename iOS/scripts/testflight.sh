#!/bin/bash
# Archive, verify, export and upload the iOS app to TestFlight (P6 Task 13).
#   testflight.sh                 preflight, archive, verify, export a local .ipa, verify it, upload that .ipa
#   testflight.sh --dry-run       same, without the upload
#   testflight.sh --verify-archive <xcarchive> <build> <commit>   verify only (tests)
#   testflight.sh --verify-ipa <ipa> <build> <commit>             verify an exported ipa (tests)
#   testflight.sh --check-export-options <plist>                  assert the export plist keys (tests)
# Env: ASC_ENV (default ~/.config/agent-hourglass/asc.env, mode 600) holding exactly the lines
# ASC_KEY_ID=<id> and ASC_ISSUER_ID=<uuid> (parsed, not sourced).
# The Admin API key (.p8) lives only in 1Password: vault ASC_OP_VAULT (default Personal), item ASC_OP_ITEM
# (default below), file field p8, text field Key ID equal to ASC_KEY_ID. Preflight checks the item; right
# before the archive (after `make test`) a fresh mode 700 mktemp dir is created and `op read` copies the key
# into it (file mode 600) for xcodebuild (-authenticationKeyPath) and altool (API_PRIVATE_KEYS_DIR). The EXIT
# trap removes that dir first, on success, failure, HUP, INT and TERM. 1Password asks for Touch ID.
# ASC_KEY_PATH=/abs/AuthKey_<id>.p8 (mode 600) uses a local file instead. The run refuses to start, and to
# upload, while any AuthKey_*.p8 sits in a dir altool searches before API_PRIVATE_KEYS_DIR.
# Key ID, issuer ID, the key and its path are never echoed. Preflight test output goes to <out>/preflight.log,
# xcodebuild and altool output to <out>/xcodebuild.log (both 600); failures show a redacted tail.
# Verify requires iPhone only (UIDeviceFamily [1]) and portrait only.
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

# plist_is <plist> <key> <json> <label>: exact JSON value of a top-level key ("missing" when absent).
plist_is() {
  local got
  got=$(/usr/bin/plutil -extract "$2" json -o - "$1" 2>/dev/null) || got=missing
  [ "$got" = "$3" ] || die "verify: $4 $2 is $got, want $3"
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
  # iPhone only and portrait only. A build that also targets iPad must support every orientation, or App
  # Store Connect rejects it (ITMS-90474); XcodeGen's per-target preset once overrode the project's "1".
  plist_is "$app/Info.plist" UIDeviceFamily '[1]' app
  plist_is "$appex/Info.plist" UIDeviceFamily '[1]' widget
  plist_is "$app/Info.plist" UISupportedInterfaceOrientations '["UIInterfaceOrientationPortrait"]' app
  plist_is "$app/Info.plist" 'UISupportedInterfaceOrientations~ipad' missing app
  # The internal-only export stamps the app Info.plist (seen in the 261023.201712 ipa); the archive has none.
  if [ "$dist" = 1 ] && [ "$(plist TFInternalTestingOnly "$app/Info.plist")" != true ]; then
    die "verify: app TFInternalTestingOnly is not true"
  fi
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

# Cleanup for every exit of a run (the --verify-* modes above exit before this). Each part is armed once
# its state exists. HUP/INT/TERM exit through it too. The key dir goes first, and no step can stop the
# others (no errexit here); a step that fails says so and the run keeps its exit status.
rsbin=; keydir=; operr=; distlogs_armed=0
cleanup() {
  set +e
  [ -z "$keydir" ] || rm -rf "$keydir" || echo "testflight: could not remove the key dir $keydir; remove it by hand" >&2
  [ -z "$operr" ] || rm -f "$operr"
  [ "$distlogs_armed" = 0 ] || rm_distlogs
  [ -z "$rsbin" ] || rm -rf "$rsbin"
}
trap cleanup EXIT
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
ASC_OP_VAULT=${ASC_OP_VAULT:-Personal}
ASC_OP_ITEM=${ASC_OP_ITEM:-Apple Developer - App Store Connect API key (agent-hourglass)}

# 1. Preflight. Cheap checks first so a missing key fails in seconds.
# A pinned build number would repeat across uploads; it is for --dry-run and tests only.
[ $dry -eq 1 ] || [ -z "${BUILD_NUMBER_NOW:-}" ] || die "BUILD_NUMBER_NOW is only allowed with --dry-run"
[ -z "$(git status --porcelain)" ] || die "dirty tree"
asc=${ASC_ENV:-$HOME/.config/agent-hourglass/asc.env}
[ -f "$asc" ] || die "missing App Store Connect env file (set ASC_ENV or create ~/.config/agent-hourglass/asc.env)"
[ "$(/usr/bin/stat -f '%Lp' "$asc")" = 600 ] || die "App Store Connect env file must be mode 600"
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
# tail_log <log>: last 30 lines to stderr, with any asc.env value lines dropped.
tail_log() { tail -n 30 "$1" | rg -v -F -e "$kid" -e "$iss" >&2 || true; }
check_export_options ExportOptions.plist
# altool searches these dirs for AuthKey_<id>.p8 before API_PRIVATE_KEYS_DIR (`xcrun altool --help`): a
# leftover key there would be used instead of the 1Password copy. Checked now and again before the upload.
no_stale_keys() {
  local d f
  for d in ./private_keys "$HOME/private_keys" "$HOME/.private_keys" "$HOME/.appstoreconnect/private_keys"; do
    for f in "$d"/AuthKey_*.p8; do
      [ ! -e "$f" ] && [ ! -L "$f" ] || die "an AuthKey_*.p8 is in $d, which altool searches first: move it into 1Password and delete it"
    done
  done
}
no_stale_keys
security find-identity -v -p codesigning | rg -q 'Apple Distribution' || die "no Apple Distribution identity in the keychain"

# API key. check_p8 <file> <label>: a regular file (not a symlink), mode 600, a PEM private key; never printed.
check_p8() {
  [ -f "$1" ] && [ ! -L "$1" ] || die "$2: no API key file"
  [ "$(/usr/bin/stat -f '%Lp' "$1")" = 600 ] || die "$2: API key file must be mode 600"
  [ "$(head -n 1 "$1")" = '-----BEGIN PRIVATE KEY-----' ] && /usr/bin/openssl pkey -in "$1" -noout >/dev/null 2>&1 \
    || die "$2: API key file is not a PEM private key"
}
keyfile=AuthKey_${kid}.p8; p8=; opref=
if [ -n "${ASC_KEY_PATH:-}" ]; then
  [[ "$ASC_KEY_PATH" == /* ]] && [ "$(basename "$ASC_KEY_PATH")" = "$keyfile" ] \
    || die "ASC_KEY_PATH must be an absolute path to AuthKey_<ASC_KEY_ID>.p8"
  check_p8 "$ASC_KEY_PATH" ASC_KEY_PATH; p8=$ASC_KEY_PATH
else
  # The item is checked now (Touch ID prompt); the key itself is copied only right before the archive, so
  # it is not on disk during the minutes of `make test`, which run repo and package code as this user.
  command -v op >/dev/null || die "1Password CLI 'op' not found: install it and enable the 1Password app integration, or set ASC_KEY_PATH"
  operr=$(umask 077; mktemp)
  item=$( (umask 077; op item get "$ASC_OP_ITEM" --vault "$ASC_OP_VAULT" --format json 2>"$operr") ) \
    || { tail_log "$operr"; die "1Password: cannot read item \"$ASC_OP_ITEM\" in vault $ASC_OP_VAULT (unlock 1Password and approve Touch ID)"; }
  # Count-only checks; prints only a status word and the vault and item ids for the op:// reference.
  opref=$(printf '%s' "$item" | AH_KID=$kid jq -r '
    if ([.files[]? | select(.name == "p8")] | length) != 1 then "nofile"
    elif [.fields[]? | select(.label == "Key ID") | .value] != [env.AH_KID] then "kid"
    elif (.vault.id | type) != "string" or (.id | type) != "string" then "noid"
    else "op://\(.vault.id)/\(.id)/p8" end' 2>/dev/null) || opref=badjson
  unset item
  case $opref in
    nofile) die "1Password: item \"$ASC_OP_ITEM\" needs exactly one file named p8" ;;
    kid) die "1Password: item \"$ASC_OP_ITEM\" Key ID does not match ASC_KEY_ID in the env file" ;;
    op://*/*/p8) ;;
    *) die "1Password: cannot parse item \"$ASC_OP_ITEM\"" ;;
  esac
fi
# fetch_key: create a fresh private dir and copy the key from 1Password into it (no-op with ASC_KEY_PATH).
# The dir does not exist before this, so nothing run by `make test` can plant a file or link at its path.
fetch_key() {
  [ -z "$p8" ] || return 0
  [ -z "$keydir" ] || die "key dir already exists"
  keydir=$(umask 077; mktemp -d) || die "cannot create the key dir"
  chmod 700 "$keydir"
  [ -d "$keydir" ] && [ ! -L "$keydir" ] && [ "$(/usr/bin/stat -f '%u %Lp' "$keydir")" = "$(id -u) 700" ] \
    && [ -z "$(ls -A "$keydir")" ] || die "key dir must be a new empty dir of this user, mode 700"
  local f=$keydir/$keyfile
  [ ! -e "$f" ] && [ ! -L "$f" ] || die "key file path already exists"
  ( umask 077; op read --file-mode 0600 --out-file "$f" "$opref" ) >>"$operr" 2>&1 \
    || { tail_log "$operr"; die "1Password: op read of the p8 file failed (approve Touch ID)"; }
  check_p8 "$f" 1Password; p8=$f
}
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
plog=$out/preflight.log; ( umask 077; : > "$plog" )
pre() { local what=$1; shift; "$@" >>"$plog" 2>&1 || { tail_log "$plog"; die "$what failed (log: $plog)"; }; }
pre "make test" make -C .. test
pre "make -C iOS test" make test

# 3. Project.
log=$out/xcodebuild.log; ( umask 077; : > "$log" )
xcodegen generate --spec project.yml --quiet
# xcodebuild with -authenticationKey* writes the key id and issuer id into *.xcdistributionlogs bundles
# in `getconf DARWIN_USER_TEMP_DIR`, even when TMPDIR is overridden. Scan that dir, and $TMPDIR too when it
# differs. Remove this scheme's bundles that appear during this run (success or failure); keep any that
# existed before, and other schemes' bundles.
dtmp=$(getconf DARWIN_USER_TEMP_DIR); dtmp=${dtmp%/}
[ -n "$dtmp" ] && [ -d "$dtmp" ] || die "cannot resolve DARWIN_USER_TEMP_DIR"
tdirs=("$dtmp"); [ -n "${TMPDIR:-}" ] && [ "${TMPDIR%/}" != "$dtmp" ] && tdirs+=("${TMPDIR%/}")
distlogs() {
  local d t
  for t in "${tdirs[@]}"; do for d in "$t"/AgentHourglassiOS_*.xcdistributionlogs; do [ -e "$d" ] && echo "$d"; done; done
  return 0
}
# all_distlogs: every bundle in the scanned dirs. The AgentHourglassiOS_ prefix is [inferred] from the scheme
# name; a new bundle named otherwise is counted (never named) so a wrong guess does not go unnoticed.
all_distlogs() {
  local d t
  for t in "${tdirs[@]}"; do for d in "$t"/*.xcdistributionlogs; do [ -e "$d" ] && echo "$d"; done; done
  return 0
}
pre_logs=$(distlogs); pre_all=$(all_distlogs)
rm_distlogs() {
  local d n=0
  while IFS= read -r d; do
    printf '%s\n' "$pre_logs" | rg -q -x -F -- "$d" || rm -rf "$d" 2>/dev/null \
      || echo "testflight: could not remove $d (holds the key id and issuer id); remove it by hand" >&2
  done < <(distlogs)
  while IFS= read -r d; do
    case $(basename "$d") in AgentHourglassiOS_*) continue ;; esac
    printf '%s\n' "$pre_all" | rg -q -x -F -- "$d" || n=$((n + 1))
  done < <(all_distlogs)
  [ $n = 0 ] || echo "testflight: warning: $n new *.xcdistributionlogs bundle(s) not named AgentHourglassiOS_* appeared during this run; they may hold the key id and issuer id. Check \`getconf DARWIN_USER_TEMP_DIR\` and \$TMPDIR and remove them by hand." >&2
}
distlogs_armed=1
# Xcode's IPA step runs /usr/bin/rsync (openrsync), which starts its local server as `rsync` from PATH.
# Homebrew rsync 3.x there rejects --extended-attributes and export fails with only "Copy failed".
# Pin `rsync` to the system one for this run.
rsbin=$(mktemp -d); ln -s /usr/bin/rsync "$rsbin/rsync"; PATH="$rsbin:$PATH"
run() { "$@" >>"$log" 2>&1 || { tail_log "$log"; die "$2 failed (log: $log)"; }; }

# 4. Archive. The key reaches disk here, for archive, export and upload only.
check_tree
fetch_key
auth=(-allowProvisioningUpdates -authenticationKeyPath "$p8" -authenticationKeyID "$kid" -authenticationKeyIssuerID "$iss")
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

# 7. Upload the verified ipa. altool finds AuthKey_<id>.p8 in $API_PRIVATE_KEYS_DIR (`xcrun altool --help`,
# --api-key); iOS/private_keys, which altool searches first, is not in the clean tree.
check_tree
no_stale_keys
export API_PRIVATE_KEYS_DIR; API_PRIVATE_KEYS_DIR=$(dirname "$p8")
run xcrun altool --upload-package "$ipa" --api-key "$kid" --api-issuer "$iss"
echo "testflight: uploaded $version ($build) $commit"
