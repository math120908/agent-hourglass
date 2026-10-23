#!/bin/bash
# Tests for testflight.sh with fake tools on PATH (no real archive, export or upload).
#   distlogs-*: the run removes the .xcdistributionlogs bundles its own xcodebuild calls write
#               (they hold the ASC key id and issuer id), on success and on failure, and leaves
#               bundles that existed before the run alone. Real xcodebuild writes them to
#               `getconf DARWIN_USER_TEMP_DIR` even when TMPDIR is overridden; the fake writes to
#               AH_DARWIN_TEMP_DIR, which testflight.sh reads in place of getconf.
#   relpath:    --verify-archive resolves a relative path against the caller's cwd.
#   rsync:      export runs with rsync resolving to /usr/bin/rsync. Xcode's IPA step runs /usr/bin/rsync
#               (openrsync), which starts its local server as `rsync` from PATH; Homebrew rsync 3.x there
#               rejects --extended-attributes and the export fails with "Copy failed".
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
KEY=FAKEKEY123; ISS=fake-issuer-0000
printf 'ASC_KEY_ID=%s\nASC_ISSUER_ID=%s\n' "$KEY" "$ISS" > "$t/asc.env"; chmod 600 "$t/asc.env"
: > "$t/home/.appstoreconnect/private_keys/AuthKey_$KEY.p8"; chmod 600 "$t/home/.appstoreconnect/private_keys/AuthKey_$KEY.p8"

# make_app <app> <build> <commit>: minimal app + widget bundle with the Info.plist keys verify reads.
cat > "$bin/make_app" <<'EOF'
#!/bin/bash
set -e
app=$1; mkdir -p "$app/PlugIns/W.appex"
for p in "$app:cc.kuoc.agent-hourglass.ios" "$app/PlugIns/W.appex:cc.kuoc.agent-hourglass.ios.widget"; do
  d=${p%%:*}; f=$d/Info.plist; rm -f "$f"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${p#*:}" -c "Add :CFBundleVersion string $2" \
    -c 'Add :CFBundleShortVersionString string 1.0.0' -c "Add :GitCommit string $3" "$f" >/dev/null
done
EOF
cat > "$bin/codesign" <<'EOF'
#!/bin/bash
cat <<X
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.application-groups</key><array><string>group.cc.kuoc.agent-hourglass</string></array>
<key>get-task-allow</key><false/>
<key>keychain-access-groups</key><array><string>R7V5X99HYA.cc.kuoc.agent-hourglass.shared</string></array>
</dict></plist>
X
EOF
cat > "$bin/git" <<'EOF'
#!/bin/bash
case "$*" in "status --porcelain") ;; "rev-parse --short HEAD") echo abc1234 ;; *) exit 2 ;; esac
EOF
printf '#!/bin/bash\necho "1) X \\"Apple Distribution: Fake\\""\n' > "$bin/security"
printf '#!/bin/bash\nexit 0\n' > "$bin/xcodegen"
# Fake make: FAKE_MAKE_FAIL=1 prints a marker line after some noise and fails.
cat > "$bin/make" <<'EOF2'
#!/bin/bash
[ "${FAKE_MAKE_FAIL:-0}" = 1 ] || exit 0
for i in $(seq 1 50); do echo "noise $i"; done
echo "FAKE-MARKER killedHolderReleasesLock failed"; exit 2
EOF2
# Fake xcodebuild: like Xcode with -authenticationKey*, writes the key id into a bundle in the
# Darwin user temp dir (AH_DARWIN_TEMP_DIR here), not in $TMPDIR.
cat > "$bin/xcodebuild" <<'EOF'
#!/bin/bash
args=("$@"); val() { local i; for ((i=0; i<${#args[@]}; i++)); do [ "${args[i]}" = "$1" ] && echo "${args[i+1]}"; done; }
logs=$(mktemp -d "${AH_DARWIN_TEMP_DIR%/}/AgentHourglassiOS_XXXX")
mv "$logs" "$logs.xcdistributionlogs"; echo "key $(val -authenticationKeyID) $(val -authenticationKeyIssuerID)" > "$logs.xcdistributionlogs/IDEDistribution.log"
build=; for a in "$@"; do case $a in CURRENT_PROJECT_VERSION=*) build=${a#*=} ;; esac; done
case "$1" in
  archive) make_app "$(val -archivePath)/Products/Applications/AgentHourglass.app" "$build" abc1234 ;;
  -exportArchive)
    [ "${FAKE_EXPORT_FAIL:-0}" = 1 ] && { echo "error: exportArchive fake failure"; exit 70; }
    r=$(command -v rsync); [ "$(readlink -f "$r")" = /usr/bin/rsync ] || { echo "error: exportArchive Copy failed (rsync $r)"; exit 70; }
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :destination' "$(val -exportOptionsPlist)")" = export ]; then
      arc=$(val -archivePath); exp=$(val -exportPath); s=$(mktemp -d)
      mkdir -p "$s/Payload" "$exp"; cp -R "$arc"/Products/Applications/*.app "$s/Payload/"
      ditto -c -k "$s" "$exp/AgentHourglass.ipa"; rm -rf "$s"
    fi ;;
esac
EOF
# Fake Homebrew rsync shadowing /usr/bin/rsync, as /opt/homebrew/bin does on this Mac.
printf '#!/bin/bash\nexit 1\n' > "$bin/rsync"
chmod +x "$bin"/*

# run_flow <name> <want exit> [script args...]: full flow with a scratch Darwin temp dir holding one
# older bundle. RUN_TMPDIR=other runs with TMPDIR set to a different scratch dir (also holding one).
run_flow() {
  local name=$1 want=$2 tmp=$t/tmp-$1 code=0 out left d; shift 2
  local tmpdir=$tmp/
  [ "${RUN_TMPDIR:-}" = other ] && tmpdir=$t/tmpdir-$name/
  mkdir -p "$tmp/Older_1.xcdistributionlogs" "${tmpdir}Older_1.xcdistributionlogs"
  local before; before=$(ls "$outroot" 2>/dev/null || true)
  out=$(env PATH="$bin:$PATH" HOME="$t/home" ASC_ENV="$t/asc.env" AH_DARWIN_TEMP_DIR="$tmp/" TMPDIR="$tmpdir" \
    "$script" "$@" 2>&1) || code=$?
  for d in "$outroot"/*; do [ -e "$d" ] || continue; printf '%s\n' "$before" | rg -q -x -F -- "$(basename "$d")" || rm -rf "$d"; done
  left=
  for d in "$tmp" "$tmpdir"; do left="$left$(cd "$d" && ls -d -- *.xcdistributionlogs 2>/dev/null | tr '\n' ' ' || true)"; done
  if [ "$code" != "$want" ]; then bad "$name" "exit $code want $want: $out"
  elif [ "$left" != "Older_1.xcdistributionlogs Older_1.xcdistributionlogs " ]; then bad "$name" "bundles left: '$left'"
  elif [[ "$out" == *"$KEY"* || "$out" == *"$ISS"* ]]; then bad "$name" "key id or issuer id in output"
  else pass "$name"; fi
}
run_flow distlogs-upload 0
run_flow distlogs-dry-run 0 --dry-run
FAKE_EXPORT_FAIL=1 run_flow distlogs-export-fail 1
RUN_TMPDIR=other run_flow distlogs-tmpdir-override 0 --dry-run

# preflight-log: the build number is pinned so the run's output dir is known.
pb=261023.120000; pdir=$outroot/$pb; plog=$pdir/preflight.log
[ ! -e "$pdir" ] || bad preflight-log "$pdir already exists"
code=0; out=$(env PATH="$bin:$PATH" HOME="$t/home" ASC_ENV="$t/asc.env" AH_DARWIN_TEMP_DIR="$t/" TMPDIR="$t/" FAKE_MAKE_FAIL=1 \
  BUILD_NUMBER_NOW=2026-10-23T12:00:00Z "$script" --dry-run 2>&1) || code=$?
if [ $code = 0 ]; then bad preflight-log "exit 0"
elif [[ "$out" != *"FAKE-MARKER killedHolderReleasesLock failed"* ]]; then bad preflight-log "no tail in output: $out"
elif [[ "$out" != *"$plog"* && "$out" != *"build/testflight/$pb/preflight.log"* ]]; then bad preflight-log "no log path in output: $out"
elif [ ! -f "$plog" ]; then bad preflight-log "no $plog"
elif [ "$(stat -f '%Lp' "$plog")" != 600 ]; then bad preflight-log "log mode $(stat -f '%Lp' "$plog")"
elif ! rg -q -F 'FAKE-MARKER' "$plog"; then bad preflight-log "marker not in log"
elif [[ "$out" == *"$KEY"* || "$out" == *"$ISS"* ]]; then bad preflight-log "key id or issuer id in output"
else pass preflight-log; fi
rm -rf "$pdir"

# relpath: a relative archive path from the caller's cwd.
mkdir -p "$t/cwd"; PATH="$bin:$PATH" make_app "$t/cwd/rel.xcarchive/Products/Applications/AgentHourglass.app" 1.1 abc1234
code=0; out=$(cd "$t/cwd" && PATH="$bin:$PATH" "$script" --verify-archive rel.xcarchive 1.1 abc1234 2>&1) || code=$?
[ $code = 0 ] && pass relpath || bad relpath "exit $code: $out"
exit $fail
