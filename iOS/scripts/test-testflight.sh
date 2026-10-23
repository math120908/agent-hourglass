#!/bin/bash
# Tests for testflight.sh with fake tools on PATH (no real archive, export or upload).
#   distlogs-*: the run removes the AgentHourglassiOS_*.xcdistributionlogs bundles its own xcodebuild calls
#               write (they hold the ASC key id and issuer id), on success and on failure, and leaves
#               bundles that existed before the run, and other schemes' bundles, alone. Real xcodebuild
#               writes them to `getconf DARWIN_USER_TEMP_DIR` even when TMPDIR is overridden; the fake
#               xcodebuild does the same through a fake `getconf` (FAKE_GETCONF). A stray
#               AH_DARWIN_TEMP_DIR export is ignored. A new bundle named otherwise (the prefix is a guess)
#               is kept and reported as a count-only warning.
#   altlogs-*:  the altool log the upload writes to ~/Library/Logs/ContentDelivery/com.apple.itunes.altool/
#               (it holds the key id and issuer id; the fake altool writes one under the fake HOME) is
#               removed after success, failure and SIGTERM; earlier logs stay; a new file elsewhere under
#               ContentDelivery is kept and reported as a count-only warning; an undeletable log never keeps
#               the key dir on disk.
#   verify-device-* / verify-orientation-*: the app and widget must be iPhone only (UIDeviceFamily exactly
#               [1]) and the app portrait only, with no ~ipad orientations (ITMS-90474).
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
#               internal TestFlight only, no version management, team), by --check-export-options and
#               by a full run of a copy of iOS/ (before the archive, and again before the export).
#   build-number-now-upload: upload mode refuses a pinned build number.
#   All flows run with a GNU-style fake `stat` first on PATH; the mode checks must use /usr/bin/stat.
#   preflight-log: a failing preflight `make test` leaves its output in <out>/preflight.log (mode 600)
#               and the failure message shows the log's tail and path.
#   key-* / op-*: the Admin .p8 lives only in 1Password. A fake `op` serves the item; the run copies the key
#               into a mode 700 mktemp dir (file mode 600), hands that path to xcodebuild and the dir to
#               altool (API_PRIVATE_KEYS_DIR), and the dir is gone after success, failure and SIGTERM.
#               op missing, not signed in, a non-PEM file, no p8 file or a Key ID mismatch exit 1.
#               ASC_KEY_PATH=<AuthKey_<id>.p8, mode 600> is the only local fallback. The key dir is
#               created only after `make test` (the fake make exits 3 if op read already ran);
#               an undeletable distlogs bundle never keeps the key dir on disk.
#   stale-key-*: any AuthKey_*.p8 in one of altool's own search dirs (./private_keys, ~/private_keys,
#               ~/.private_keys, ~/.appstoreconnect/private_keys) stops the run before make, and one that
#               appears during the run stops it before altool.
#   Every flow runs with a PATH that cannot reach the real `op`.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=$here/testflight.sh
outroot=$here/../build/testflight
fail=0
pass() { echo "PASS $1"; }
bad() { echo "FAIL $1: $2"; fail=1; }

t=$(mktemp -d); trap 'chflags -R nouchg "$t" 2>/dev/null; rm -rf "$t"' EXIT
bin=$t/bin; mkdir -p "$bin" "$t/home/.appstoreconnect/private_keys" "$t/sys"
KEY=FAKEKEY123; ISS=0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0
printf '# App Store Connect API key\n\nASC_KEY_ID=%s\nASC_ISSUER_ID=%s\n' "$KEY" "$ISS" > "$t/asc.env"; chmod 600 "$t/asc.env"
export FAKE_CALLS=$t/calls FAKE_KEY=$KEY FAKE_ISS=$ISS
# A real PEM key for the fake op to serve. home_key: where altool used to look (absent; the fakes reject it).
/usr/bin/openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$t/fake.pem" 2>/dev/null
home_key=$t/home/.appstoreconnect/private_keys/AuthKey_$KEY.p8
export FAKE_PEM=$t/fake.pem FAKE_HOME_KEY=$home_key FAKE_KEYS=$t/keypaths
# Test PATH: fakes, then only rg and jq from Homebrew (never the real op), then the system.
for x in rg jq; do ln -s "$(command -v "$x")" "$t/sys/$x"; done
tpath=$bin:$t/sys:/usr/bin:/bin:/usr/sbin:/sbin

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
    -c 'Add :CFBundleShortVersionString string 1.0.0' -c "Add :GitCommit string $3" \
    -c 'Add :UIDeviceFamily array' -c 'Add :UIDeviceFamily:0 integer 1' "$f" >/dev/null
  # iPhone only, portrait only (the app; Xcode stamps UIDeviceFamily into both bundles).
  [ "$d" != "$app" ] || /usr/libexec/PlistBuddy -c 'Add :UISupportedInterfaceOrientations array' \
    -c 'Add :UISupportedInterfaceOrientations:0 string UIInterfaceOrientationPortrait' "$f" >/dev/null
  # The internal-only export stamps the app (not the widget) Info.plist, as in the 261023.201712 ipa.
  if [ "${4:-dev}" = dist ] && [ "$d" = "$app" ]; then /usr/libexec/PlistBuddy -c 'Add :TFInternalTestingOnly bool true' "$f" >/dev/null; fi
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
# Fake make: FAKE_MAKE_FAIL=1 prints a marker line after some noise and fails. Exits 3 if the key was
# already fetched (fetch_key creates the key dir and runs op read) while the tests run.
cat > "$bin/make" <<'EOF2'
#!/bin/bash
echo "make $*" >> "$FAKE_CALLS"
[ -z "${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ] || { echo "ASC_* in make env"; exit 3; }
! rg -q -F 'op read' "$FAKE_CALLS" || { echo "key fetched before make"; exit 3; }
[ -z "${FAKE_MAKE_TOUCH:-}" ] || touch "$FAKE_STATE/$FAKE_MAKE_TOUCH"
[ "${FAKE_MAKE_FAIL:-0}" = 1 ] || exit 0
for i in $(seq 1 50); do echo "noise $i"; done
echo "FAKE-MARKER killedHolderReleasesLock failed"; exit 2
EOF2
# Fake xcodebuild: like Xcode with -authenticationKey*, writes the key id into a bundle in
# `getconf DARWIN_USER_TEMP_DIR` (the fake getconf), not in $TMPDIR. FAKE_DISTLOGS_UCHG=1 makes the bundle
# undeletable; FAKE_OTHER_LOGS=1 also writes another scheme's bundle; FAKE_ARCHIVE_EO=<plist> turns off
# internal-only in that plist during the archive; FAKE_EXPORT_PLANT=<file> writes a key there during export.
cat > "$bin/xcodebuild" <<'EOF'
#!/bin/bash
echo "xcodebuild $1" >> "$FAKE_CALLS"
[ -z "${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ] || { echo "ASC_* in xcodebuild env"; exit 3; }
args=("$@"); val() { local i; for ((i=0; i<${#args[@]}; i++)); do [ "${args[i]}" = "$1" ] && echo "${args[i+1]}"; done; }
k=$(val -authenticationKeyPath)
[ -n "$k" ] && [ -f "$k" ] || { echo "error: no key file"; exit 4; }
[ "$k" != "$FAKE_HOME_KEY" ] && [[ "$k" != "$HOME"/* ]] || { echo "error: key from HOME"; exit 4; }
[ "$(/usr/bin/stat -f '%Lp' "$k")" = 600 ] || { echo "error: key mode"; exit 4; }
[ "$k" = "${FAKE_KEEP_KEY:-}" ] || [ "$(/usr/bin/stat -f '%Lp' "$(dirname "$k")")" = 700 ] || { echo "error: key dir mode"; exit 4; }
[ "$(head -n 1 "$k")" = '-----BEGIN PRIVATE KEY-----' ] || { echo "error: key not PEM"; exit 4; }
echo "$k" >> "$FAKE_KEYS"
[ "${FAKE_ARCHIVE_HANG:-0}" = 1 ] && [ "$1" = archive ] && { echo $$ > "$FAKE_STATE/../hang.pid"; sleep 30; }
dt=$(getconf DARWIN_USER_TEMP_DIR); logs=$(mktemp -d "${dt%/}/AgentHourglassiOS_XXXX")
mv "$logs" "$logs.xcdistributionlogs"; echo "key $(val -authenticationKeyID) $(val -authenticationKeyIssuerID)" > "$logs.xcdistributionlogs/IDEDistribution.log"
[ "${FAKE_DISTLOGS_UCHG:-0}" = 0 ] || chflags uchg "$logs.xcdistributionlogs/IDEDistribution.log"
[ "${FAKE_OTHER_LOGS:-0}" = 0 ] || mkdir -p "${dt%/}/OtherApp_run.xcdistributionlogs"
[ -z "${FAKE_LOGS_NAME:-}" ] || { mkdir -p "${dt%/}/$FAKE_LOGS_NAME${1#-}.xcdistributionlogs"; echo "key $(val -authenticationKeyID)" > "${dt%/}/$FAKE_LOGS_NAME${1#-}.xcdistributionlogs/IDEDistribution.log"; }
build=; for a in "$@"; do case $a in CURRENT_PROJECT_VERSION=*) build=${a#*=} ;; esac; done
case "$1" in
  archive) make_app "$(val -archivePath)/Products/Applications/AgentHourglass.app" "$build" abc1234
    [ -z "${FAKE_ARCHIVE_EO:-}" ] || /usr/libexec/PlistBuddy -c 'Set :testFlightInternalTestingOnly false' "$FAKE_ARCHIVE_EO"
    [ -z "${FAKE_ARCHIVE_TOUCH:-}" ] || touch "$FAKE_STATE/$FAKE_ARCHIVE_TOUCH" ;;
  -exportArchive)
    [ -z "${FAKE_EXPORT_TOUCH:-}" ] || touch "$FAKE_STATE/$FAKE_EXPORT_TOUCH"
    [ -z "${FAKE_EXPORT_PLANT:-}" ] || { mkdir -p "$(dirname "$FAKE_EXPORT_PLANT")"; cp "$FAKE_PEM" "$FAKE_EXPORT_PLANT"; }
    [ "${FAKE_EXPORT_FAIL:-0}" = 1 ] && { echo "error: exportArchive fake failure"; exit 70; }
    r=$(command -v rsync); [ "$(readlink -f "$r")" = /usr/bin/rsync ] || { echo "error: exportArchive Copy failed (rsync $r)"; exit 70; }
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :destination' "$(val -exportOptionsPlist)")" = export ]; then
      arc=$(val -archivePath); exp=$(val -exportPath); s=$(mktemp -d)
      mkdir -p "$s/Payload" "$exp"; cp -R "$arc"/Products/Applications/*.app "$s/Payload/"
      sign_fake "$s/Payload/AgentHourglass.app" dist cc.kuoc.agent-hourglass.ios
      sign_fake "$s/Payload/AgentHourglass.app/PlugIns/W.appex" dist cc.kuoc.agent-hourglass.ios.widget
      if [ "$(/usr/libexec/PlistBuddy -c 'Print :testFlightInternalTestingOnly' "$(val -exportOptionsPlist)")" = true ]; then
        /usr/libexec/PlistBuddy -c 'Add :TFInternalTestingOnly bool true' "$s/Payload/AgentHourglass.app/Info.plist" >/dev/null
      fi
      ditto -c -k "$s" "$exp/AgentHourglass.ipa"; rm -rf "$s"
    fi ;;
esac
EOF
# Fake xcrun altool: records the call (ids replaced by KEYID / ISSID), writes a log holding the key id and
# issuer id to ~/Library/Logs/ContentDelivery/com.apple.itunes.altool/ like the real one (one file per run),
# prints them like a chatty uploader, and fails with FAKE_UPLOAD_FAIL=1. FAKE_CD_OTHER=1 also writes a file
# elsewhere under ContentDelivery; FAKE_ALTLOG_UCHG=1 makes the log undeletable; FAKE_UPLOAD_HANG=1 hangs.
cat > "$bin/xcrun" <<'EOF'
#!/bin/bash
[ "$1" = altool ] || exit 2
a="$*"; a=${a//$FAKE_KEY/KEYID}; a=${a//$FAKE_ISS/ISSID}; echo "xcrun $a" >> "$FAKE_CALLS"
cd_dir=$HOME/Library/Logs/ContentDelivery; al=$cd_dir/com.apple.itunes.altool/com.apple.itunes.altool_$(date +%Y%m%d%H%M%S)_$$.txt
mkdir -p "$(dirname "$al")"; echo "apiKey $FAKE_KEY issuer $FAKE_ISS" > "$al"; echo "xcrun altool log written" >> "$FAKE_CALLS"
[ "${FAKE_ALTLOG_UCHG:-0}" = 0 ] || chflags uchg "$al"
[ "${FAKE_CD_OTHER:-0}" = 0 ] || { mkdir -p "$cd_dir/other"; echo "apiKey $FAKE_KEY" > "$cd_dir/other/new.log"; }
[ "${FAKE_UPLOAD_HANG:-0}" = 1 ] && { echo $$ > "$FAKE_STATE/../hang.pid"; sleep 30; }
[ "$2" = --upload-package ] && [ -f "$3" ] || { echo "no package"; exit 2; }
d=${API_PRIVATE_KEYS_DIR:-}; [ -n "$d" ] && [ -f "$d/AuthKey_$FAKE_KEY.p8" ] || { echo "ERROR no key in API_PRIVATE_KEYS_DIR"; exit 4; }
[ "$d/AuthKey_$FAKE_KEY.p8" != "$FAKE_HOME_KEY" ] || { echo "ERROR key from HOME"; exit 4; }
echo "$d/AuthKey_$FAKE_KEY.p8" >> "$FAKE_KEYS"; echo "xcrun altool key ok" >> "$FAKE_CALLS"
echo "Authenticating with key $FAKE_KEY issuer $FAKE_ISS"
[ "${FAKE_UPLOAD_FAIL:-0}" = 1 ] && { echo "ERROR fake upload error"; exit 1; }
echo "UPLOAD SUCCEEDED"
EOF
# Fake 1Password CLI. FAKE_OP_FAIL=auth: not signed in. FAKE_OP_KID: the item's Key ID (default the
# asc.env one). FAKE_OP_FILE: the item's file name (default p8). FAKE_OP_CONTENT=junk: op read writes a
# non-PEM file. `op read` prints the written path (it holds the key id) like the real one.
cat > "$bin/op" <<'EOF'
#!/bin/bash
echo "op $1 $2" >> "$FAKE_CALLS"
[ "${FAKE_OP_FAIL:-}" != auth ] || { echo "[ERROR] account is not signed in for $FAKE_KEY" >&2; exit 1; }
case "$1 $2" in
  "item get")
    [ "$3" = "Apple Developer - App Store Connect API key (agent-hourglass)" ] && [ "$4 $5 $6 $7" = "--vault Personal --format json" ] \
      || { echo "[ERROR] item isn't in vault" >&2; exit 1; }
    printf '{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaa","title":"%s","vault":{"id":"vvvvvvvvvvvvvvvvvvvvvvvvvv","name":"Personal"},"fields":[{"id":"k","label":"Key ID","value":"%s"},{"id":"i","label":"Issuer ID","value":"%s"}],"files":[{"id":"f","name":"%s","size":241}]}\n' \
      "$3" "${FAKE_OP_KID:-$FAKE_KEY}" "$FAKE_ISS" "${FAKE_OP_FILE:-p8}" ;;
  "read "*)
    shift; out=; mode=; ref=
    while [ $# -gt 0 ]; do case $1 in --out-file) out=$2; shift ;; --file-mode) mode=$2; shift ;; op://*) ref=$1 ;; esac; shift; done
    [ "$ref" = op://vvvvvvvvvvvvvvvvvvvvvvvvvv/aaaaaaaaaaaaaaaaaaaaaaaaaa/p8 ] || { echo "[ERROR] bad reference" >&2; exit 1; }
    [ -n "$out" ] || { echo "[ERROR] no --out-file" >&2; exit 1; }
    if [ "${FAKE_OP_CONTENT:-}" = junk ]; then echo "not a key" > "$out"; else cat "$FAKE_PEM" > "$out"; fi
    [ -z "$mode" ] || chmod "${mode#0}" "$out"; echo "$out" ;;
  *) exit 2 ;;
esac
EOF
# Fake getconf: DARWIN_USER_TEMP_DIR is FAKE_GETCONF (each flow's scratch dir).
cat > "$bin/getconf" <<'EOF'
#!/bin/bash
[ "$*" = DARWIN_USER_TEMP_DIR ] && [ -n "${FAKE_GETCONF:-}" ] || { echo "fake getconf: unset" >&2; exit 2; }
echo "$FAKE_GETCONF"
EOF
# Fake GNU stat first on PATH (coreutils gnubin): `stat -f` means filesystem status there.
printf '#!/bin/bash\necho "  File: GNU stat"\n' > "$bin/stat"
# Fake Homebrew rsync shadowing /usr/bin/rsync, as /opt/homebrew/bin does on this Mac.
printf '#!/bin/bash\nexit 1\n' > "$bin/rsync"
chmod +x "$bin"/*
# bin2: the same fakes without op.
mkdir -p "$t/bin2"; for x in "$bin"/*; do [ "$(basename "$x")" = op ] || ln -s "$x" "$t/bin2/"; done

# snap_out / clean_out: remove the <out> dirs a run creates under build/testflight.
snap_out() { out_before=$(ls "$outroot" 2>/dev/null || true); }
clean_out() {
  local d
  for d in "$outroot"/*; do [ -e "$d" ] || continue; printf '%s\n' "$out_before" | rg -q -x -F -- "$(basename "$d")" || rm -rf "$d"; done
}
# run_flow <name> <want exit> [script args...]: full flow with a scratch Darwin temp dir holding two
# older bundles (this scheme's and another). RUN_TMPDIR=other runs with TMPDIR set to a different scratch
# dir (also holding them). RUN_SCRIPT runs another copy of testflight.sh, RUN_HOME another HOME.
# RUN_LEFT: the bundles expected afterwards in the two dirs (default: the older ones).
older='AgentHourglassiOS_older.xcdistributionlogs Older_1.xcdistributionlogs '
# old_cd_logs <ContentDelivery dir>: a fresh dir with an altool log and another file from earlier runs, which must be kept.
# cd_files <dir>: the files under it, relative, sorted, space separated.
cd_older='com.apple.itunes.altool/com.apple.itunes.altool_older.txt older.txt '
old_cd_logs() {
  rm -rf "$1"; mkdir -p "$1/com.apple.itunes.altool"
  echo "earlier run" > "$1/com.apple.itunes.altool/com.apple.itunes.altool_older.txt"; echo "earlier" > "$1/older.txt"
}
cd_files() { [ -d "$1" ] || return 0; (cd "$1" && find . -type f | sed 's|^\./||' | sort | tr '\n' ' '); }
run_flow() {
  local name=$1 want=$2 tmp=$t/tmp-$1 code=0 out left d; shift 2
  local tmpdir=$tmp/
  [ "${RUN_TMPDIR:-}" = other ] && tmpdir=$t/tmpdir-$name/
  for d in "$tmp/" "$tmpdir"; do mkdir -p "${d}Older_1.xcdistributionlogs" "${d}AgentHourglassiOS_older.xcdistributionlogs"; done
  local cdl=${RUN_HOME:-$t/home}/Library/Logs/ContentDelivery cdleft
  old_cd_logs "$cdl"
  : > "$FAKE_CALLS"; : > "$FAKE_KEYS"; rm -f "$FAKE_STATE"/*
  snap_out
  out=$(env PATH="${RUN_PATH:-$tpath}" HOME="${RUN_HOME:-$t/home}" ASC_ENV="$t/asc.env" FAKE_GETCONF="$tmp/" TMPDIR="$tmpdir" \
    "${RUN_SCRIPT:-$script}" "$@" 2>&1) || code=$?
  clean_out
  # An undeletable bundle is expected to stay; clear its flag and drop it so the other checks still apply.
  if [ "${FAKE_DISTLOGS_UCHG:-0}" != 0 ]; then
    chflags -R nouchg "$tmp" "$tmpdir"
    for d in "$tmp"/AgentHourglassiOS_*.xcdistributionlogs "$tmpdir"AgentHourglassiOS_*.xcdistributionlogs; do
      [ "$(basename "$d")" = AgentHourglassiOS_older.xcdistributionlogs ] || rm -rf "$d"
    done
  fi
  # An undeletable altool log is expected to stay; clear its flag and drop it so the other checks still apply.
  if [ "${FAKE_ALTLOG_UCHG:-0}" != 0 ]; then
    chflags -R nouchg "$cdl"; rm -f "$cdl"/com.apple.itunes.altool/com.apple.itunes.altool_2*.txt
  fi
  cdleft=$(cd_files "$cdl")
  left=
  # Every key copy the fakes saw must be gone with its dir (an owner's ASC_KEY_PATH file stays).
  local kleft= k kuse
  while IFS= read -r k; do
    [ -n "$k" ] && [ "$k" != "${FAKE_KEEP_KEY:-}" ] || continue
    [ ! -e "$k" ] && [ ! -e "$(dirname "$k")" ] || kleft="$kleft $k"
  done < "$FAKE_KEYS"
  kuse=$({ rg -v -F -x -- "${FAKE_KEEP_KEY:-/nonexistent}" "$FAKE_KEYS" || true; } | wc -l | tr -d ' ')
  for d in "$tmp" "$tmpdir"; do left="$left$(cd "$d" && ls -d -- *.xcdistributionlogs 2>/dev/null | tr '\n' ' ' || true)"; done
  if [ "$code" != "$want" ]; then bad "$name" "exit $code want $want: $out"
  elif [ "$left" != "${RUN_LEFT:-$older$older}" ]; then bad "$name" "bundles left: '$left'"
  elif [ "$cdleft" != "${RUN_CD_LEFT:-$cd_older}" ]; then bad "$name" "ContentDelivery files left: '$cdleft'"
  elif [[ "$out" == *"$KEY"* || "$out" == *"$ISS"* ]]; then bad "$name" "key id or issuer id in output"
  elif [ -n "$kleft" ]; then bad "$name" "key copies left:$kleft"
  elif [ -n "${RUN_KEY:-}" ] && [ "$kuse" != "$RUN_KEY" ]; then bad "$name" "want $RUN_KEY key copy uses, got $kuse"
  elif [ -n "${RUN_WANT_MSG:-}" ] && [[ "$out" != *"$RUN_WANT_MSG"* ]]; then bad "$name" "message lacks '$RUN_WANT_MSG': $out"
  elif [ -n "${RUN_NO_CALL:-}" ] && rg -q -F -- "$RUN_NO_CALL" "$FAKE_CALLS"; then bad "$name" "called $RUN_NO_CALL"
  elif [ -n "${RUN_CALL:-}" ] && ! rg -q -F -- "$RUN_CALL" "$FAKE_CALLS"; then bad "$name" "did not call $RUN_CALL"
  else pass "$name"; fi
}
RUN_CALL='/export/AgentHourglass.ipa --api-key KEYID --api-issuer ISSID' run_flow distlogs-upload 0
RUN_NO_CALL=xcrun run_flow distlogs-dry-run 0 --dry-run
# altlogs-*: the altool log the upload writes (it holds the key id and issuer id) is removed after success
# and failure; earlier logs stay; a new file elsewhere under ContentDelivery is kept and counted.
RUN_CALL='xcrun altool log written' run_flow altlogs-upload 0
RUN_CALL='xcrun altool log written' RUN_WANT_MSG='fake upload error' FAKE_UPLOAD_FAIL=1 run_flow altlogs-upload-fail 1
RUN_CD_LEFT="${cd_older}other/new.log " RUN_WANT_MSG='warning: 1 new file(s) under ~/Library/Logs/ContentDelivery' \
  FAKE_CD_OTHER=1 run_flow altlogs-other-warns 0
RUN_KEY=3 RUN_WANT_MSG='could not remove' FAKE_ALTLOG_UCHG=1 run_flow altlogs-undeletable-key-still-removed 0
FAKE_EXPORT_FAIL=1 run_flow distlogs-export-fail 1
RUN_TMPDIR=other run_flow distlogs-tmpdir-override 0 --dry-run
# A stray AH_DARWIN_TEMP_DIR (the old test hook) must not replace getconf: the run's bundles are still removed.
mkdir -p "$t/stray"; RUN_TMPDIR=other AH_DARWIN_TEMP_DIR=$t/stray/ run_flow distlogs-stray-hook-ignored 0 --dry-run
# Only this scheme's bundles: another scheme's bundle written during the run stays.
o2="AgentHourglassiOS_older.xcdistributionlogs Older_1.xcdistributionlogs OtherApp_run.xcdistributionlogs "
RUN_LEFT="$o2$o2" FAKE_OTHER_LOGS=1 run_flow distlogs-other-scheme-kept 0 --dry-run
# Xcode names its bundle differently from the AgentHourglassiOS_ guess: kept, and a count-only warning.
o3="AgentHourglassiOS_older.xcdistributionlogs Older_1.xcdistributionlogs Xcode_archive.xcdistributionlogs Xcode_exportArchive.xcdistributionlogs "
RUN_LEFT="$o3$o3" RUN_WANT_MSG='warning: 2 new *.xcdistributionlogs bundle(s) not named AgentHourglassiOS_*' FAKE_LOGS_NAME=Xcode_ \
  run_flow distlogs-unexpected-name-warns 0 --dry-run

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

# key-*: the key is copied from 1Password for the run, used by archive, export and altool, then removed.
RUN_KEY=3 RUN_CALL='op read' run_flow key-removed-upload 0
RUN_KEY=2 RUN_NO_CALL=xcrun run_flow key-removed-dry-run 0 --dry-run
RUN_KEY=2 FAKE_EXPORT_FAIL=1 run_flow key-removed-export-fail 1
# An undeletable distlogs bundle (uchg) must not stop cleanup before the key dir is removed.
RUN_KEY=2 RUN_WANT_MSG='could not remove' FAKE_DISTLOGS_UCHG=1 run_flow key-removed-distlogs-undeletable 0 --dry-run
RUN_KEY=2 RUN_WANT_MSG='could not remove' FAKE_DISTLOGS_UCHG=1 FAKE_EXPORT_FAIL=1 \
  run_flow key-removed-distlogs-undeletable-fail 1 --dry-run
# op-*: every failure stops before the key is used, with a message and no secret in the output.
RUN_WANT_MSG="'op' not found" RUN_NO_CALL=xcodebuild RUN_PATH="$t/bin2:$t/sys:/usr/bin:/bin:/usr/sbin:/sbin" \
  run_flow op-missing 1 --dry-run
RUN_WANT_MSG='1Password' RUN_NO_CALL=make FAKE_OP_FAIL=auth run_flow op-not-signed-in 1 --dry-run
RUN_WANT_MSG='Key ID' RUN_NO_CALL=make FAKE_OP_KID=OTHERKEY12 run_flow op-kid-mismatch 1 --dry-run
RUN_WANT_MSG='p8' RUN_NO_CALL=make FAKE_OP_FILE=AuthKey.p8 run_flow op-no-p8-file 1 --dry-run
RUN_WANT_MSG='not a PEM private key' RUN_NO_CALL=xcodebuild FAKE_OP_CONTENT=junk run_flow op-non-pem 1 --dry-run
# key-path-*: ASC_KEY_PATH is the only local fallback; the owner's file is used, not removed, op never runs.
mkdir -p "$t/local"; lk=$t/local/AuthKey_$KEY.p8; cp "$t/fake.pem" "$lk"; chmod 600 "$lk"
RUN_KEY=0 RUN_NO_CALL='op ' FAKE_KEEP_KEY=$lk ASC_KEY_PATH=$lk RUN_PATH="$t/bin2:$t/sys:/usr/bin:/bin:/usr/sbin:/sbin" \
  run_flow key-path-fallback 0
[ -f "$lk" ] && pass key-path-kept || bad key-path-kept "ASC_KEY_PATH file removed"
chmod 644 "$lk"
RUN_WANT_MSG='mode 600' RUN_NO_CALL=make FAKE_KEEP_KEY=$lk ASC_KEY_PATH=$lk run_flow key-path-mode 1 --dry-run
chmod 600 "$lk"; cp "$lk" "$t/local/other.p8"
RUN_WANT_MSG='AuthKey_' RUN_NO_CALL=make ASC_KEY_PATH=$t/local/other.p8 run_flow key-path-name 1 --dry-run

# sigterm_case <name> <hang var> [script args]: TERM to the script and its hanging fake (as a terminal or
# process-group kill does); the key copy, the run's distribution logs and altool logs are gone afterwards.
sigterm_case() {
  local name=$1 hang=$2 st=$t/tmp-$1 h=$t/home-$1 k kw code; shift 2
  : > "$FAKE_KEYS"; : > "$FAKE_CALLS"; rm -f "$FAKE_STATE"/* "$t/hang.pid"; snap_out
  mkdir -p "$st" "$h"; old_cd_logs "$h/Library/Logs/ContentDelivery"
  env PATH="$tpath" HOME="$h" ASC_ENV="$t/asc.env" FAKE_GETCONF="$st/" TMPDIR="$st/" "$hang=1" \
    "$script" "$@" > "$t/sigterm.out" 2>&1 &
  local spid=$! i=0
  while [ ! -s "$t/hang.pid" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  if [ ! -s "$t/hang.pid" ]; then kill "$spid" 2>/dev/null || true; wait "$spid" || true; clean_out; bad "$name" "fake never hung: $(cat "$t/sigterm.out")"; return; fi
  k=$(head -n 1 "$FAKE_KEYS")
  if [ -z "$k" ] || [ ! -f "$k" ]; then kw="no key during the hang"; else kw=; fi
  kill -TERM "$spid" "$(cat "$t/hang.pid")" 2>/dev/null || true
  code=0; wait "$spid" || code=$?
  clean_out
  if [ -n "$kw" ]; then bad "$name" "$kw"
  elif [ "$code" = 0 ]; then bad "$name" "exit 0 after TERM"
  elif [ -e "$k" ] || [ -e "$(dirname "$k")" ]; then bad "$name" "key copy left after TERM"
  elif [ -n "$(cd "$st" && ls -d AgentHourglassiOS_*.xcdistributionlogs 2>/dev/null)" ]; then bad "$name" "distlogs left after TERM"
  elif [ "$(cd_files "$h/Library/Logs/ContentDelivery")" != "$cd_older" ]; then bad "$name" "altool log left after TERM"
  elif rg -q -F -e "$KEY" -e "$ISS" "$t/sigterm.out"; then bad "$name" "key id or issuer id in output"
  else pass "$name"; fi
}
sigterm_case key-removed-sigterm FAKE_ARCHIVE_HANG --dry-run
sigterm_case altlogs-removed-sigterm-upload FAKE_UPLOAD_HANG

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
# fresh_copy: a minimal copy of iOS/ (script, build number, project.yml, ExportOptions.plist) at $cp.
cp=$t/copy/iOS
fresh_copy() {
  rm -rf "$t/copy"; mkdir -p "$cp/scripts"
  cp "$script" "$here/build-number.sh" "$cp/scripts/"; cp "$here/../project.yml" "$here/../ExportOptions.plist" "$cp/"
}
# exportoptions-run-*: a full run checks the plist before the archive and again before the export.
fresh_copy; /usr/libexec/PlistBuddy -c 'Set :testFlightInternalTestingOnly false' "$cp/ExportOptions.plist"
RUN_SCRIPT=$cp/scripts/testflight.sh RUN_WANT_MSG='testFlightInternalTestingOnly' RUN_NO_CALL=xcodebuild \
  run_flow exportoptions-run-preflight 1 --dry-run
fresh_copy
RUN_SCRIPT=$cp/scripts/testflight.sh RUN_WANT_MSG='testFlightInternalTestingOnly' RUN_NO_CALL='xcodebuild -exportArchive' \
  FAKE_ARCHIVE_EO=$cp/ExportOptions.plist run_flow exportoptions-run-before-export 1 --dry-run

# stale-key-*: a key in one of altool's own search dirs takes precedence over API_PRIVATE_KEYS_DIR.
for sd in private_keys .private_keys .appstoreconnect/private_keys; do
  h=$t/home-stale-${sd//\//-}; mkdir -p "$h/$sd"; cp "$t/fake.pem" "$h/$sd/AuthKey_OTHERKEY12.p8"; chmod 600 "$h/$sd/AuthKey_OTHERKEY12.p8"
  RUN_HOME=$h RUN_WANT_MSG='private_keys' RUN_NO_CALL=make run_flow "stale-key-home-${sd//\//-}" 1
done
fresh_copy; mkdir -p "$cp/private_keys"; cp "$t/fake.pem" "$cp/private_keys/AuthKey_$KEY.p8"
RUN_SCRIPT=$cp/scripts/testflight.sh RUN_WANT_MSG='private_keys' RUN_NO_CALL=make run_flow stale-key-cwd 1 --dry-run
h=$t/home-stale-late; mkdir -p "$h"
RUN_HOME=$h RUN_WANT_MSG='private_keys' RUN_NO_CALL=xcrun FAKE_EXPORT_PLANT=$h/.private_keys/AuthKey_$KEY.p8 \
  run_flow stale-key-during-run 1

# asc_case <name> <asc.env content> [env...]: must exit 1 before any make/xcodebuild call, no marker.
asc_case() {
  local name=$1 body=$2 f=$t/asc-$1.env m=$t/marker code=0 out; shift 2
  rm -f "$m"; : > "$FAKE_CALLS"; printf '%s\n' "$body" > "$f"; chmod 600 "$f"
  snap_out
  out=$(cd "$t" && env PATH="$tpath" HOME="$t/home" ASC_ENV="$f" FAKE_GETCONF="$t/" "$@" "$script" --dry-run 2>&1) || code=$?
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
: > "$FAKE_CALLS"
code=0; out=$(env PATH="$tpath" HOME="$t/home" ASC_ENV="$t/asc.env" FAKE_GETCONF="$t/" TMPDIR="$t/" FAKE_MAKE_FAIL=1 \
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
vcase verify-ipa-internal-only ipa 'TFInternalTestingOnly' 'pbe $A/Info.plist "Delete :TFInternalTestingOnly"'
vcase verify-ipa-internal-only-false ipa 'TFInternalTestingOnly' 'pbe $A/Info.plist "Set :TFInternalTestingOnly false"'
vcase verify-widget-build archive 'CFBundleVersion mismatch' 'pbe $W/Info.plist "Set :CFBundleVersion 1.2"'
vcase verify-app-build ipa 'CFBundleVersion mismatch' 'pbe $A/Info.plist "Set :CFBundleVersion 1.2"'
vcase verify-widget-short-version archive 'CFBundleShortVersionString mismatch' \
  'pbe $W/Info.plist "Set :CFBundleShortVersionString 1.0.1"'
vcase verify-project-version ipa 'project.yml' \
  'pbe $A/Info.plist "Set :CFBundleShortVersionString 9.9.9"; pbe $W/Info.plist "Set :CFBundleShortVersionString 9.9.9"'
vcase verify-app-bundle-id archive 'app bundle id' 'pbe $A/Info.plist "Set :CFBundleIdentifier cc.kuoc.other"'
vcase verify-widget-bundle-id ipa 'widget bundle id' \
  'pbe $W/Info.plist "Set :CFBundleIdentifier cc.kuoc.agent-hourglass.ios.other"'
# device-*: iPhone only (UIDeviceFamily exactly [1] in app and widget) and portrait only; ASC rejects an
# iPad-capable build that is not all-orientations (ITMS-90474).
vcase verify-device-family-ipad archive 'UIDeviceFamily' 'pbe $A/Info.plist "Add :UIDeviceFamily:1 integer 2"'
vcase verify-device-family-ipad-ipa ipa 'UIDeviceFamily' 'pbe $A/Info.plist "Add :UIDeviceFamily:1 integer 2"'
vcase verify-device-family-ipad-only ipa 'UIDeviceFamily' 'pbe $A/Info.plist "Set :UIDeviceFamily:0 2"'
vcase verify-device-family-missing archive 'UIDeviceFamily' 'pbe $A/Info.plist "Delete :UIDeviceFamily"'
vcase verify-device-family-widget ipa 'UIDeviceFamily' 'pbe $W/Info.plist "Add :UIDeviceFamily:1 integer 2"'
vcase verify-orientation-landscape archive 'UISupportedInterfaceOrientations' \
  'pbe $A/Info.plist "Add :UISupportedInterfaceOrientations:1 string UIInterfaceOrientationLandscapeLeft"'
vcase verify-orientation-landscape-ipa ipa 'UISupportedInterfaceOrientations' \
  'pbe $A/Info.plist "Set :UISupportedInterfaceOrientations:0 UIInterfaceOrientationLandscapeRight"'
vcase verify-orientation-missing ipa 'UISupportedInterfaceOrientations' \
  'pbe $A/Info.plist "Delete :UISupportedInterfaceOrientations"'
vcase verify-orientation-ipad-key archive 'UISupportedInterfaceOrientations~ipad' \
  'pbe $A/Info.plist "Add :UISupportedInterfaceOrientations~ipad array" "Add :UISupportedInterfaceOrientations~ipad:0 string UIInterfaceOrientationPortrait"'
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
