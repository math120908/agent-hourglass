#!/bin/bash
# Mac logins still work after the phone signs in (P6 Task 15). Behavioral checks only:
# Keychain mdat is not evidence because Claude Code refreshes its own item.
# One PASS|FAIL line per check; exit 0 only if all pass. Model output is never printed.
set -uo pipefail
fails=0
result() { echo "$1 $2"; [ "$1" = FAIL ] && fails=1; return 0; }
asks() { timeout 120 "$@" </dev/null 2>&1 | tail -n 20; }

out=$(asks env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_BASE_URL claude -p 'Reply with exactly: ok')
# Last line must be exactly ok; banners (e.g. connector notices) before it are ignored.
last=$(printf '%s\n' "$out" | rg -v '^\s*$' | tail -n 1 | tr -d '[:space:].')
if [ "$last" = ok ] && ! printf '%s' "$out" | rg -q -i -e 'please run /login' -e 'not logged in' -e 'invalid api key'; then result PASS "claude code"; else result FAIL "claude code"; fi

out=$(asks codex exec --skip-git-repo-check 'Reply with exactly: ok')
if [[ "$out" == *ok* ]]; then result PASS "codex cli"; else result FAIL "codex cli"; fi

if pgrep -x AgentHourglass >/dev/null; then result PASS "agent hourglass running"; else result FAIL "agent hourglass running"; fi
n=$(log show --last 2h --predicate 'subsystem == "cc.kuoc.agent-hourglass"' 2>/dev/null | rg -c -e needsLogin -e invalid_grant || true)
if [ "${n:-0}" -eq 0 ]; then result PASS "agent hourglass no needsLogin/invalid_grant (2h)"; else result FAIL "agent hourglass needsLogin/invalid_grant x$n (2h)"; fi
exit $fails
