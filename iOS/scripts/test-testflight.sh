#!/bin/bash
# Tests for testflight.sh with fake tools on PATH (no real archive, export or upload).
#   distlogs-*: the run removes the .xcdistributionlogs bundles its own xcodebuild calls write
#               (they hold the ASC key id and issuer id), on success and on failure, and leaves
#               bundles that existed before the run alone. Real xcodebuild writes them to
#               `getconf DARWIN_USER_TEMP_DIR` even when TMPDIR is overridden; the fake writes to
#               AH_DARWIN_TEMP_DIR, which testflight.sh reads in place of getconf.
#   verify-*:   --verify-archive / --verify-ipa pass a good fixture; each mutated fixture (versions vs each
#               other and project.yml, bundle ids, GitCommit, entitlements compared as exact plist values,
#               signing identity and team) exits 1 with a message naming the failed check.
#   relpath:    --verify-archive resolves a relative path against the caller's cwd.
#   rsync:      export runs with rsync resolving to /usr/bin/rsync. Xcode's IPA step runs /usr/bin/rsync
#               (openrsync), which starts its local server as `rsync` from PATH; Homebrew rsync 3.x there
#               rejects --extended-attributes and the export fails with "Copy failed".
#   asc-*:      asc.env is parsed, never sourced: only ASC_KEY_ID=<10 [A-Z0-9]> and ASC_ISSUER_ID=<uuid>
#               lines (plus blanks and comments). Anything else exits 1 before make or xcodebuild run,
#               without executing it; the values never reach a child's environment.
#   tree-*:     a tracked change or a new HEAD during preflight or archive exits 1 before the next xcodebuild.
#   upload-*:   upload mode exports a local ipa, verifies it, and uploads that same file with
#               `xcrun altool --upload-package`; a failed verify never uploads; altool output is redacted.
#   exportoptions-*: ExportOptions.plist keys are asserted (destination export, app-store-connect,
#               internal TestFlight only, no version management, team).
#   build-number-now-upload: upload mode refuses a pinned build number.
#   All flows run with a GNU-style fake `stat` first on PATH; the mode checks must use /usr/bin/stat.
#   preflight-log: a failing preflight `make test` leaves its output in <out>/preflight.log (mode 600)
#               and the failure message shows the log's tail and path.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=$here/testflight.sh
outroot=$here/../build/testflight
fail=0
pass() { echo "PASS $1"; }
bad() { echo "FAIL $1: $2"; fail=1; }

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
bin=$t/bin; mkdir -p "$bin" "$t/home/.appstoreconnect/private_keys"
KEY=FAKEKEY123; ISS=0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0
printf '# App Store Connect API key\n\nASC_KEY_ID=%s\nASC_ISSUER_ID=%s\n' "$KEY" "$ISS" > "$t/asc.env"; chmod 600 "$t/asc.env"
export FAKE_CALLS=$t/calls FAKE_KEY=$KEY FAKE_ISS=$ISS
: > "$t/home/.appstoreconnect/private_keys/AuthKey_$KEY.p8"; chmod 600 "$t/home/.appstoreconnect/private_keys/AuthKey_$KEY.p8"

# sign_fake <bundle> <dev|dist> <bundle id>: the signature the fake codesign reports for <bundle>, kept as
# files inside it. dev = the automatic-signing archive (Apple Development, get-task-allow true); dist = the
# cloud-signed export (Apple Distribution, get-task-allow false, or FAKE_EXPORT_GTA).
cat > "$bin/sign_fake" <<'EOF'
#!/bin/bash
set -e
b=$1; id=$3; e=$b/_fake_ent.plist; rm -f "$e"
if [ "$2" = dist ]; then gta=${FAKE_EXPORT_GTA:-false}; auth="Apple Distribution: Fake Name (R7V5X99HYA)"
else gta=true; auth="Apple Development: Fake Name (J3BB4FRPJR)"; fi
/usr/libexec/PlistBuddy -c "Add :application-identifier string R7V5X99HYA.$id" \
  -c 'Add :com.apple.developer.team-identifier string R7V5X99HYA' \
  -c 'Add :com.apple.security.application-groups array' \
  -c 'Add :com.apple.security.application-groups:0 string group.cc.kuoc.agent-hourglass' \
  -c "Add :get-task-allow bool $gta" \
  -c 'Add :keychain-access-groups array' \
  -c 'Add :keychain-access-groups:0 string R7V5X99HYA.cc.kuoc.agent-hourglass.shared' "$e" >/dev/null
printf 'Identifier=%s\nAuthority=%s\nAuthority=Apple Worldwide Developer Relations Certification Authority\nAuthority=Apple Root CA\nTeamIdentifier=R7V5X99HYA\n' \
  "$id" "$auth" > "$b/_fake_sig.txt"
EOF
# make_app <app> <build> <commit> [dev|dist]: minimal app + widget bundle with the Info.plist keys verify
# reads and a fake signature (default dev, like the archive).
cat > "$bin/make_app" <<'EOF'
#!/bin/bash
set -e
app=$1; mkdir -p "$app/PlugIns/W.appex"
for p in "$app:cc.kuoc.agent-hourglass.ios" "$app/PlugIns/W.appex:cc.kuoc.agent-hourglass.ios.widget"; do
  d=${p%%:*}; f=$d/Info.plist; rm -f "$f"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${p#*:}" -c "Add :CFBundleVersion string $2" \
    -c 'Add :CFBundleShortVersionString string 1.0.0' -c "Add :GitCommit string $3" "$f" >/dev/null
  sign_fake "$d" "${4:-dev}" "${p#*:}"
done
EOF
# Fake codesign: `-d --entitlements ... <bundle>` prints <bundle>/_fake_ent.plist (stdout, like real);
# `-dvv <bundle>` prints <bundle>/_fake_sig.txt (stderr, like real).
cat > "$bin/codesign" <<'EOF'
#!/bin/bash
b=${!#}
case " $* " in
  *" -dvv "*) cat "$b/_fake_sig.txt" >&2 ;;
  *" --entitlements "*) cat "$b/_fake_ent.plist" ;;
  *) exit 2 ;;
esac
EOF
# Fake git: the tree turns dirty once $FAKE_STATE/dirty exists, HEAD moves once $FAKE_STATE/moved exists.
# fake_touch <flag> (in the fake make and xcodebuild) creates one when FAKE_<WHEN>=<flag> asks for it.
export FAKE_STATE=$t/state; mkdir -p "$FAKE_STATE"
cat > "$bin/git" <<'EOF'
#!/bin/bash
case "$*" in
  "status --porcelain") [ ! -e "$FAKE_STATE/dirty" ] || echo " M App/AgentHourglassApp.swift" ;;
  "rev-parse HEAD") if [ -e "$FAKE_STATE/moved" ]; then echo 1111111111111111111111111111111111111111
    else echo abc1234000000000000000000000000000000000; fi ;;
  "rev-parse --short abc1234000000000000000000000000000000000") echo abc1234 ;;
  "rev-parse --short HEAD") echo abc1234 ;;
  *) exit 2 ;;
esac
EOF
printf '#!/bin/bash\necho "1) X \\"Apple Distribution: Fake\\""\n' > "$bin/security"
printf '#!/bin/bash\nexit 0\n' > "$bin/xcodegen"
# Fake make: FAKE_MAKE_FAIL=1 prints a marker line after some noise and fails.
cat > "$bin/make" <<'EOF2'
#!/bin/bash
echo "make $*" >> "$FAKE_CALLS"
[ -z "${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ] || { echo "ASC_* in make env"; exit 3; }
[ -z "${FAKE_MAKE_TOUCH:-}" ] || touch "$FAKE_STATE/$FAKE_MAKE_TOUCH"
[ "${FAKE_MAKE_FAIL:-0}" = 1 ] || exit 0
for i in $(seq 1 50); do echo "noise $i"; done
echo "FAKE-MARKER killedHolderReleasesLock failed"; exit 2
EOF2
# Fake xcodebuild: like Xcode with -authenticationKey*, writes the key id into a bundle in the
# Darwin user temp dir (AH_DARWIN_TEMP_DIR here), not in $TMPDIR.
cat > "$bin/xcodebuild" <<'EOF'
#!/bin/bash
echo "xcodebuild $1" >> "$FAKE_CALLS"
[ -z "${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ] || { echo "ASC_* in xcodebuild env"; exit 3; }
args=("$@"); val() { local i; for ((i=0; i<${#args[@]}; i++)); do [ "${args[i]}" = "$1" ] && echo "${args[i+1]}"; done; }
logs=$(mktemp -d "${AH_DARWIN_TEMP_DIR%/}/AgentHourglassiOS_XXXX")
mv "$logs" "$logs.xcdistributionlogs"; echo "key $(val -authenticationKeyID) $(val -authenticationKeyIssuerID)" > "$logs.xcdistributionlogs/IDEDistribution.log"
build=; for a in "$@"; do case $a in CURRENT_PROJECT_VERSION=*) build=${a#*=} ;; esac; done
case "$1" in
  archive) make_app "$(val -archivePath)/Products/Applications/AgentHourglass.app" "$build" abc1234
    [ -z "${FAKE_ARCHIVE_TOUCH:-}" ] || touch "$FAKE_STATE/$FAKE_ARCHIVE_TOUCH" ;;
  -exportArchive)
    [ -z "${FAKE_EXPORT_TOUCH:-}" ] || touch "$FAKE_STATE/$FAKE_EXPORT_TOUCH"
    [ "${FAKE_EXPORT_FAIL:-0}" = 1 ] && { echo "error: exportArchive fake failure"; exit 70; }
    r=$(command -v rsync); [ "$(readlink -f "$r")" = /usr/bin/rsync ] || { echo "error: exportArchive Copy failed (rsync $r)"; exit 70; }
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :destination' "$(val -exportOptionsPlist)")" = export ]; then
      arc=$(val -archivePath); exp=$(val -exportPath); s=$(mktemp -d)
      mkdir -p "$s/Payload" "$exp"; cp -R "$arc"/Products/Applications/*.app "$s/Payload/"
      sign_fake "$s/Payload/AgentHourglass.app" dist cc.kuoc.agent-hourglass.ios
      sign_fake "$s/Payload/AgentHourglass.app/PlugIns/W.appex" dist cc.kuoc.agent-hourglass.ios.widget
      ditto -c -k "$s" "$exp/AgentHourglass.ipa"; rm -rf "$s"
    fi ;;
esac
EOF
# Fake xcrun altool: records the call (ids replaced by KEYID / ISSID), prints the key id and issuer id like
# a chatty uploader, and fails with FAKE_UPLOAD_FAIL=1.
cat > "$bin/xcrun" <<'EOF'
#!/bin/bash
[ "$1" = altool ] || exit 2
a="$*"; a=${a//$FAKE_KEY/KEYID}; a=${a//$FAKE_ISS/ISSID}; echo "xcrun $a" >> "$FAKE_CALLS"
[ "$2" = --upload-package ] && [ -f "$3" ] || { echo "no package"; exit 2; }
echo "Authenticating with key $FAKE_KEY issuer $FAKE_ISS"
[ "${FAKE_UPLOAD_FAIL:-0}" = 1 ] && { echo "ERROR fake upload error"; exit 1; }
echo "UPLOAD SUCCEEDED"
EOF
# Fake GNU stat first on PATH (coreutils gnubin): `stat -f` means filesystem status there.
printf '#!/bin/bash\necho "  File: GNU stat"\n' > "$bin/stat"
# Fake Homebrew rsync shadowing /usr/bin/rsync, as /opt/homebrew/bin does on this Mac.
printf '#!/bin/bash\nexit 1\n' > "$bin/rsync"
chmod +x "$bin"/*

# snap_out / clean_out: remove the <out> dirs a run creates under build/testflight.
snap_out() { out_before=$(ls "$outroot" 2>/dev/null || true); }
clean_out() {
  local d
  for d in "$outroot"/*; do [ -e "$d" ] || continue; printf '%s\n' "$out_before" | rg -q -x -F -- "$(basename "$d")" || rm -rf "$d"; done
}
# run_flow <name> <want exit> [script args...]: full flow with a scratch Darwin temp dir holding one
# older bundle. RUN_TMPDIR=other runs with TMPDIR set to a different scratch dir (also holding one).
run_flow() {
  local name=$1 want=$2 tmp=$t/tmp-$1 code=0 out left d; shift 2
  local tmpdir=$tmp/
  [ "${RUN_TMPDIR:-}" = other ] && tmpdir=$t/tmpdir-$name/
  mkdir -p "$tmp/Older_1.xcdistributionlogs" "${tmpdir}Older_1.xcdistributionlogs"
  : > "$FAKE_CALLS"; rm -f "$FAKE_STATE"/*
  snap_out
  out=$(env PATH="$bin:$PATH" HOME="$t/home" ASC_ENV="$t/asc.env" AH_DARWIN_TEMP_DIR="$tmp/" TMPDIR="$tmpdir" \
    "$script" "$@" 2>&1) || code=$?
  clean_out
  left=
  for d in "$tmp" "$tmpdir"; do left="$left$(cd "$d" && ls -d -- *.xcdistributionlogs 2>/dev/null | tr '\n' ' ' || true)"; done
  if [ "$code" != "$want" ]; then bad "$name" "exit $code want $want: $out"
  elif [ "$left" != "Older_1.xcdistributionlogs Older_1.xcdistributionlogs " ]; then bad "$name" "bundles left: '$left'"
  elif [[ "$out" == *"$KEY"* || "$out" == *"$ISS"* ]]; then bad "$name" "key id or issuer id in output"
  elif [ -n "${RUN_WANT_MSG:-}" ] && [[ "$out" != *"$RUN_WANT_MSG"* ]]; then bad "$name" "message lacks '$RUN_WANT_MSG': $out"
  elif [ -n "${RUN_NO_CALL:-}" ] && rg -q -F -- "$RUN_NO_CALL" "$FAKE_CALLS"; then bad "$name" "called $RUN_NO_CALL"
  elif [ -n "${RUN_CALL:-}" ] && ! rg -q -F -- "$RUN_CALL" "$FAKE_CALLS"; then bad "$name" "did not call $RUN_CALL"
  else pass "$name"; fi
}
RUN_CALL='/export/AgentHourglass.ipa --api-key KEYID --api-issuer ISSID' run_flow distlogs-upload 0
RUN_NO_CALL=xcrun run_flow distlogs-dry-run 0 --dry-run
FAKE_EXPORT_FAIL=1 run_flow distlogs-export-fail 1
RUN_TMPDIR=other run_flow distlogs-tmpdir-override 0 --dry-run

# tree-*: the tree and HEAD are checked again before archive and before export.
RUN_WANT_MSG='tree changed during run' RUN_NO_CALL='xcodebuild archive' FAKE_MAKE_TOUCH=dirty \
  run_flow tree-dirty-in-preflight 1 --dry-run
RUN_WANT_MSG='HEAD changed during run' RUN_NO_CALL='xcodebuild archive' FAKE_MAKE_TOUCH=moved \
  run_flow tree-head-moved-in-preflight 1 --dry-run
RUN_WANT_MSG='tree changed during run' RUN_NO_CALL='xcodebuild -exportArchive' FAKE_ARCHIVE_TOUCH=dirty \
  run_flow tree-dirty-in-archive 1
RUN_WANT_MSG='HEAD changed during run' RUN_NO_CALL='xcodebuild -exportArchive' FAKE_ARCHIVE_TOUCH=moved \
  run_flow tree-head-moved-in-archive 1 --dry-run
RUN_WANT_MSG='tree changed during run' RUN_NO_CALL=xcrun FAKE_EXPORT_TOUCH=dirty run_flow tree-dirty-in-export 1

# upload-*: upload mode exports an ipa, verifies it, then uploads that file with altool.
RUN_WANT_MSG='get-task-allow' RUN_NO_CALL=xcrun FAKE_EXPORT_GTA=true run_flow upload-verifies-ipa-first 1
RUN_WANT_MSG='fake upload error' FAKE_UPLOAD_FAIL=1 run_flow upload-fail-redacted 1

# build-number-now-upload: BUILD_NUMBER_NOW is for --dry-run only.
RUN_WANT_MSG='BUILD_NUMBER_NOW' RUN_NO_CALL=make BUILD_NUMBER_NOW=2026-10-23T12:00:00Z run_flow build-number-now-upload 1

# exportoptions-*: --check-export-options guards the export plist's keys.
eo_case() { # <name> <want 0|1> [PlistBuddy cmd]
  local f=$t/eo-$1.plist code=0 out
  cp "$here/../ExportOptions.plist" "$f"; [ -z "${3:-}" ] || /usr/libexec/PlistBuddy -c "$3" "$f" >/dev/null
  out=$("$script" --check-export-options "$f" 2>&1) || code=$?
  if [ $code = "$2" ]; then pass "$1"; else bad "$1" "exit $code want $2: $out"; fi
}
eo_case exportoptions-ok 0
eo_case exportoptions-internal-only 1 'Set :testFlightInternalTestingOnly false'
eo_case exportoptions-internal-only-missing 1 'Delete :testFlightInternalTestingOnly'
eo_case exportoptions-destination 1 'Set :destination upload'
eo_case exportoptions-method 1 'Set :method debugging'
eo_case exportoptions-manage-version 1 'Set :manageAppVersionAndBuildNumber true'
eo_case exportoptions-team 1 'Set :teamID OTHERTEAM1'

# asc_case <name> <asc.env content> [env...]: must exit 1 before any make/xcodebuild call, no marker.
asc_case() {
  local name=$1 body=$2 f=$t/asc-$1.env m=$t/marker code=0 out; shift 2
  rm -f "$m"; : > "$FAKE_CALLS"; printf '%s\n' "$body" > "$f"; chmod 600 "$f"
  snap_out
  out=$(cd "$t" && env PATH="$bin:$PATH" HOME="$t/home" ASC_ENV="$f" AH_DARWIN_TEMP_DIR="$t/" "$@" "$script" --dry-run 2>&1) || code=$?
  clean_out
  if [ $code != 1 ]; then bad "$name" "exit $code want 1: $out"
  elif [ -e "$m" ]; then bad "$name" "asc.env code ran"
  elif [ -s "$FAKE_CALLS" ]; then bad "$name" "ran: $(tr '\n' ' ' < "$FAKE_CALLS")"
  elif [[ "$out" == *"$KEY"* || "$out" == *"$ISS"* ]]; then bad "$name" "key id or issuer id in output"
  else pass "$name"; fi
}
ok="ASC_KEY_ID=$KEY
ASC_ISSUER_ID=$ISS"
asc_case asc-cmdsubst "ASC_KEY_ID=\$(touch $t/marker)
ASC_ISSUER_ID=$ISS"
asc_case asc-backtick "ASC_KEY_ID=$KEY
ASC_ISSUER_ID=\`touch $t/marker\`"
asc_case asc-extra-cmd "$ok
touch $t/marker"
asc_case asc-extra-var "$ok
GROUP=x"
asc_case asc-setx "set -x
$ok"
asc_case asc-export "export ASC_KEY_ID=$KEY
ASC_ISSUER_ID=$ISS"
asc_case asc-trailing "$ok; touch $t/marker"
asc_case asc-dup "$ok
ASC_KEY_ID=$KEY"
asc_case asc-bad-keyid "ASC_KEY_ID=../x
ASC_ISSUER_ID=$ISS"
asc_case asc-bad-issuer "ASC_KEY_ID=$KEY
ASC_ISSUER_ID=fake-issuer-0000"
asc_case asc-missing "ASC_KEY_ID=$KEY"
# A caller that exported the names must not leak them into make/xcodebuild (checked by the fakes).
ASC_KEY_ID=$KEY ASC_ISSUER_ID=$ISS run_flow asc-not-exported 0 --dry-run

# preflight-log: the build number is pinned so the run's output dir is known.
pb=261023.120000; pdir=$outroot/$pb; plog=$pdir/preflight.log
[ ! -e "$pdir" ] || bad preflight-log "$pdir already exists"
code=0; out=$(env PATH="$bin:$PATH" HOME="$t/home" ASC_ENV="$t/asc.env" AH_DARWIN_TEMP_DIR="$t/" TMPDIR="$t/" FAKE_MAKE_FAIL=1 \
  BUILD_NUMBER_NOW=2026-10-23T12:00:00Z "$script" --dry-run 2>&1) || code=$?
if [ $code = 0 ]; then bad preflight-log "exit 0"
elif [[ "$out" != *"FAKE-MARKER killedHolderReleasesLock failed"* ]]; then bad preflight-log "no tail in output: $out"
elif [[ "$out" != *"$plog"* && "$out" != *"build/testflight/$pb/preflight.log"* ]]; then bad preflight-log "no log path in output: $out"
elif [ ! -f "$plog" ]; then bad preflight-log "no $plog"
elif [ "$(/usr/bin/stat -f '%Lp' "$plog")" != 600 ]; then bad preflight-log "log mode $(/usr/bin/stat -f '%Lp' "$plog")"
elif ! rg -q -F 'FAKE-MARKER' "$plog"; then bad preflight-log "marker not in log"
elif [[ "$out" == *"$KEY"* || "$out" == *"$ISS"* ]]; then bad preflight-log "key id or issuer id in output"
else pass preflight-log; fi
rm -rf "$pdir"

# relpath: a relative archive path from the caller's cwd.
mkdir -p "$t/cwd"; PATH="$bin:$PATH" make_app "$t/cwd/rel.xcarchive/Products/Applications/AgentHourglass.app" 1.1 abc1234
code=0; out=$(cd "$t/cwd" && PATH="$bin:$PATH" "$script" --verify-archive rel.xcarchive 1.1 abc1234 2>&1) || code=$?
[ $code = 0 ] && pass relpath || bad relpath "exit $code: $out"

# verify-*: one mutation per case on a fresh fixture.
# pbe <plist> <PlistBuddy cmd...>; gsub_sig <bundle> <from> <to> edits the fake `codesign -dvv` output.
pbe() { local f=$1 c; shift; for c in "$@"; do /usr/libexec/PlistBuddy -c "$c" "$f" >/dev/null; done; }
gsub_sig() { local f=$1/_fake_sig.txt x; x=$(cat "$f"); printf '%s\n' "${x//"$2"/"$3"}" > "$f"; }
# vcase <name> <archive|ipa> <want: 0, or a substring of the failure message> <mutation on $A app / $W widget>
vcase() {
  local name=$1 mode=$2 want=$3 mut=$4 d=$t/v-$1 code=0 out A W sig=dev
  rm -rf "$d"; A=$d/x.xcarchive/Products/Applications/AgentHourglass.app
  [ "$mode" = ipa ] && { A=$d/s/Payload/AgentHourglass.app; sig=dist; }
  W=$A/PlugIns/W.appex
  PATH="$bin:$PATH" make_app "$A" 1.1 abc1234 "$sig"
  eval "$mut"
  if [ "$mode" = ipa ]; then ditto -c -k "$d/s" "$d/x.ipa"; set -- --verify-ipa "$d/x.ipa"
  else set -- --verify-archive "$d/x.xcarchive"; fi
  out=$(PATH="$bin:$PATH" "$script" "$@" 1.1 abc1234 2>&1) || code=$?
  if [ "$want" = 0 ]; then if [ $code = 0 ]; then pass "$name"; else bad "$name" "exit $code: $out"; fi
  elif [ $code != 1 ]; then bad "$name" "exit $code want 1: $out"
  elif [[ "$out" != *"$want"* ]]; then bad "$name" "message lacks '$want': $out"
  else pass "$name"; fi
}
EA='$A/_fake_ent.plist'; EW='$W/_fake_ent.plist'
vcase verify-archive-ok archive 0 ':'
vcase verify-ipa-ok ipa 0 ':'
vcase verify-widget-build archive 'CFBundleVersion mismatch' 'pbe $W/Info.plist "Set :CFBundleVersion 1.2"'
vcase verify-app-build ipa 'CFBundleVersion mismatch' 'pbe $A/Info.plist "Set :CFBundleVersion 1.2"'
vcase verify-widget-short-version archive 'CFBundleShortVersionString mismatch' \
  'pbe $W/Info.plist "Set :CFBundleShortVersionString 1.0.1"'
vcase verify-project-version ipa 'project.yml' \
  'pbe $A/Info.plist "Set :CFBundleShortVersionString 9.9.9"; pbe $W/Info.plist "Set :CFBundleShortVersionString 9.9.9"'
vcase verify-app-bundle-id archive 'app bundle id' 'pbe $A/Info.plist "Set :CFBundleIdentifier cc.kuoc.other"'
vcase verify-widget-bundle-id ipa 'widget bundle id' \
  'pbe $W/Info.plist "Set :CFBundleIdentifier cc.kuoc.agent-hourglass.ios.other"'
vcase verify-git-commit archive 'GitCommit' 'pbe $A/Info.plist "Set :GitCommit deadbee"'
vcase verify-gta-app ipa 'get-task-allow' "pbe $EA 'Set :get-task-allow true'"
vcase verify-gta-widget ipa 'get-task-allow' "pbe $EW 'Set :get-task-allow true'"
vcase verify-gta-missing ipa 'get-task-allow' "pbe $EA 'Delete :get-task-allow'"
vcase verify-appid-team ipa 'application-identifier' \
  "pbe $EA 'Set :application-identifier OTHERTEAM1.cc.kuoc.agent-hourglass.ios'"
vcase verify-appid-widget archive 'application-identifier' \
  "pbe $EW 'Set :application-identifier R7V5X99HYA.cc.kuoc.agent-hourglass.ios'"
vcase verify-team-id ipa 'team-identifier' "pbe $EW 'Set :com.apple.developer.team-identifier OTHERTEAM1'"
vcase verify-group-missing archive 'application-groups' "pbe $EA 'Delete :com.apple.security.application-groups'"
vcase verify-group-similar ipa 'application-groups' \
  "pbe $EW 'Set :com.apple.security.application-groups:0 group.cc.kuoc.agent-hourglass.dev'"
vcase verify-group-extra ipa 'application-groups' \
  "pbe $EA 'Add :com.apple.security.application-groups:1 string group.cc.kuoc.other'"
vcase verify-group-wrong-key archive 'application-groups' \
  "pbe $EA 'Delete :com.apple.security.application-groups' 'Add :com.apple.other array' 'Add :com.apple.other:0 string group.cc.kuoc.agent-hourglass'"
vcase verify-keychain-missing ipa 'keychain-access-groups' "pbe $EW 'Delete :keychain-access-groups'"
vcase verify-keychain-other archive 'keychain-access-groups' \
  "pbe $EA 'Set :keychain-access-groups:0 R7V5X99HYA.cc.kuoc.other'"
vcase verify-sign-team-archive archive 'signing team' 'gsub_sig $A TeamIdentifier=R7V5X99HYA TeamIdentifier=OTHERTEAM1'
vcase verify-sign-team-ipa ipa 'signing team' 'gsub_sig $W TeamIdentifier=R7V5X99HYA TeamIdentifier=OTHERTEAM1'
vcase verify-sign-development ipa 'Apple Distribution' \
  'gsub_sig $A "Apple Distribution: Fake Name (R7V5X99HYA)" "Apple Development: Fake Name (J3BB4FRPJR)"'
vcase verify-sign-other-team ipa 'Apple Distribution' 'gsub_sig $W "Fake Name (R7V5X99HYA)" "Fake Name (OTHERTEAM1)"'
exit $fail
