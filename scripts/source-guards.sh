#!/bin/bash
# Enforces source invariants from the spec (Keychain isolation).
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
report() { echo "source-guards: $1" >&2; echo "$2" >&2; fail=1; }
READER='Sources/UsageCore/Storage/ClaudeCodeKeychainReader.swift'

out=$(rg -l 'Claude Code-credentials' Sources App 2>/dev/null | grep -v "^$READER\$")
[ -n "$out" ] && report "'Claude Code-credentials' outside $READER:" "$out"
out=$(rg -l '^import Security' Sources App 2>/dev/null | grep -v 'CredentialStore.swift$' | grep -v "^$READER\$")
[ -n "$out" ] && report "'import Security' outside CredentialStore.swift / $READER:" "$out"
out=$(rg -n 'kSecMatchLimitAll' Sources App 2>/dev/null)
[ -n "$out" ] && report "kSecMatchLimitAll is forbidden:" "$out"
out=$(rg -n 'SecItemDelete' Sources 2>/dev/null | grep -v '^[^:]*CredentialStore.swift:')
[ -n "$out" ] && report "SecItemDelete outside CredentialStore.swift:" "$out"
# The Claude Code reader is read-only: no write, ACL, subprocess, or refresh-token path.
out=$(rg -n -e 'SecItemAdd' -e 'SecItemUpdate' -e 'SecItemDelete' -e 'SecKeychain' -e 'SecAccess' -e 'SecTrusted' \
  -e 'kSecValueData' -e 'Process\(' -e '/usr/bin/security' -e 'refreshToken' "$READER" 2>/dev/null)
[ -n "$out" ] && report "write/ACL/subprocess/refresh path in $READER:" "$out"
out=$(rg -n '/usr/bin/security' Sources App 2>/dev/null)
[ -n "$out" ] && report "/usr/bin/security is forbidden:" "$out"

[ $fail -eq 0 ] && echo "source-guards: ok"
exit $fail
