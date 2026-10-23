#!/bin/bash
# Runtime security pass against the booted simulator (P6 Task 6).
#   security-pass.sh --start-log        start background log capture (PID in $TMPDIR/ah-log.pid)
#   security-pass.sh [--log <file>]     run S1-S5; exit 0 only if no check FAILs
# Prints one PASS|FAIL|SKIP line per check. Never prints a matched secret: file:line and pattern name only.
# Simulator keychain schema (confirmed 2026-10-23, iOS 26.0): table genp, columns agrp, pdmn, sync;
# pdmn 'cku' = AfterFirstUnlockThisDeviceOnly.
set -euo pipefail

BUNDLE=cc.kuoc.agent-hourglass.ios
GROUP=group.cc.kuoc.agent-hourglass
DIR=cc.kuoc.agent-hourglass
AGRP_SUFFIX=cc.kuoc.agent-hourglass.shared
PRED='subsystem BEGINSWITH "cc.kuoc.agent-hourglass" OR process == "AgentHourglass" OR process == "AgentHourglassWidget"'
TMP="${TMPDIR:-/tmp}"
PIDFILE="$TMP/ah-log.pid"
DEFAULT_LOG="$TMP/ah-security-log.txt"
PATTERNS=(
  'anthropic-key=sk-an[t]-' 'github-token=gh[opusr]_' 'bearer=Bearer ' 'jwt=eyJ[A-Za-z0-9_-]{10,}'
  'refresh_token=refresh_token' 'access_token=access_token' 'oauth-code=[?&]code='
  'device_code=device_code' 'code_verifier=code_verifier'
)

udid() { xcrun simctl list devices booted -j | jq -r '..|.udid? // empty' | head -1; }

# scan <file...>: prints "<file>:<line> <pattern-name>" for every hit, never the text.
scan() {
  local p name re
  for p in "${PATTERNS[@]}" "${@:2}"; do
    [ -z "$p" ] && continue
    name="${p%%=*}"; re="${p#*=}"
    rg -n -o -a -e "$re" "$1" 2>/dev/null | cut -d: -f1 | sed "s|^|$1:|; s|\$| $name|" || true
  done
}

fails=0
result() { echo "$1 $2"; [ "$1" = FAIL ] && fails=1; return 0; }

if [ "${1:-}" = --start-log ]; then
  [ -n "$(udid)" ] || { echo "security-pass: no booted simulator" >&2; exit 1; }
  ( umask 077; : > "$DEFAULT_LOG" )
  xcrun simctl spawn booted log stream --level debug --style compact --predicate "$PRED" > "$DEFAULT_LOG" 2>/dev/null &
  echo $! > "$PIDFILE"
  echo "security-pass: log capture started -> $DEFAULT_LOG"
  exit 0
fi

LOG="$DEFAULT_LOG"
[ "${1:-}" = --log ] && LOG="$2"
UDID=$(udid)
[ -n "$UDID" ] || { echo "security-pass: no booted simulator" >&2; exit 1; }
work=$(mktemp -d "$TMP/ah-sp.XXXXXX"); chmod 700 "$work"
trap 'rm -rf "$work"' EXIT

# S1 logs: captured stream plus the last 2h of the unified log.
if [ -f "$PIDFILE" ]; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE"; fi
xcrun simctl spawn booted log show --last 2h --style compact --predicate "$PRED" > "$work/show.txt" 2>/dev/null || true
hits=""
[ -f "$LOG" ] && hits+=$(scan "$LOG")
hits+=$(scan "$work/show.txt")
if [ -n "$hits" ]; then echo "$hits"; result FAIL "S1 logs"
elif [ ! -f "$LOG" ]; then result SKIP "S1 logs (log show clean; no stream capture at $LOG)"
else result PASS "S1 logs"; fi

# S2 App Group modes and snapshot content.
grp=$(xcrun simctl get_app_container booted "$BUNDLE" "$GROUP" 2>/dev/null || true)
if [ -z "$grp" ] || [ ! -d "$grp/$DIR" ]; then result FAIL "S2 app group (container or $DIR missing)"
else
  bad=$(find "$grp/$DIR" \( -type d ! -perm 700 \) -o \( -type f ! -perm 600 \) | sed "s|^$grp/||")
  content=""
  while IFS= read -r f; do
    content+=$(scan "$f" 'email=@' | sed "s|^$grp/||")
  done < <(find "$grp/$DIR" -type f -name '*.json')
  if [ -n "$bad" ]; then echo "$bad"; result FAIL "S2 app group modes"; else result PASS "S2 app group modes"; fi
  if [ -n "$content" ]; then echo "$content"; result FAIL "S2 snapshot content"; else result PASS "S2 snapshot content"; fi
fi

# S3 Keychain attributes in the simulator keychain db.
db="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/Keychains/keychain-2-debug.db"
cols=$(sqlite3 -readonly "$db" "select group_concat(name) from pragma_table_info('genp')" 2>/dev/null || true)
if [[ ",$cols," != *,agrp,* || ",$cols," != *,pdmn,* || ",$cols," != *,sync,* ]]; then
  result SKIP "S3 keychain (schema lacks agrp/pdmn/sync; CredentialStoreAttributesTests is the evidence)"
else
  rows=$(sqlite3 -readonly "$db" "select count(*) from genp where agrp like '%$AGRP_SUFFIX'")
  badrows=$(sqlite3 -readonly "$db" "select count(*) from genp where agrp like '%$AGRP_SUFFIX' and (pdmn != 'cku' or sync != 0)")
  if [ "$rows" -eq 0 ]; then result FAIL "S3 keychain (no items in *.$AGRP_SUFFIX; sign in first)"
  elif [ "$badrows" -ne 0 ]; then result FAIL "S3 keychain ($badrows of $rows items not cku/sync=0)"
  else result PASS "S3 keychain ($rows items cku, sync=0)"; fi
fi

# S4 web store: no claude/anthropic data persisted in the app container (auth session is ephemeral).
app=$(xcrun simctl get_app_container booted "$BUNDLE" data 2>/dev/null || true)
if [ -z "$app" ]; then result FAIL "S4 web store (app not installed)"
else
  dirs=(); for d in Library/Cookies Library/WebKit Library/Caches; do [ -d "$app/$d" ] && dirs+=("$app/$d"); done
  w=""; [ ${#dirs[@]} -gt 0 ] && w=$(rg -l -a -i -e 'claude' -e 'anthropic' "${dirs[@]}" 2>/dev/null | sed "s|^$app/||" || true)
  if [ -n "$w" ]; then echo "$w"; result FAIL "S4 web store"; else result PASS "S4 web store"; fi
fi

# S5 Diagnostics: operator taps About > Copy diagnostics before running.
( umask 077; xcrun simctl pbpaste booted > "$work/diag.txt" 2>/dev/null || true )
d=$(scan "$work/diag.txt" 'uuid=[0-9a-f]{8}-[0-9a-f]{4}-' 'email=@' | sed "s|^$work/||")
if [ -n "$d" ]; then echo "$d"; result FAIL "S5 diagnostics"
elif ! rg -q 'accounts:' "$work/diag.txt"; then result FAIL "S5 diagnostics (clipboard has no 'accounts:'; tap Copy diagnostics)"
else result PASS "S5 diagnostics"; fi

exit $fails
