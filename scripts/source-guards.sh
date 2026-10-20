#!/bin/bash
# Enforces source invariants from the spec (Keychain isolation).
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
report() { echo "source-guards: $1" >&2; echo "$2" >&2; fail=1; }

out=$(rg -l 'Claude Code-credentials' Sources App 2>/dev/null)
[ -n "$out" ] && report "forbidden 'Claude Code-credentials' reference:" "$out"
out=$(rg -l '^import Security' Sources App 2>/dev/null | grep -v 'CredentialStore.swift$')
[ -n "$out" ] && report "'import Security' outside CredentialStore.swift:" "$out"
out=$(rg -n 'kSecMatchLimitAll' Sources App 2>/dev/null)
[ -n "$out" ] && report "kSecMatchLimitAll is forbidden:" "$out"
out=$(rg -n 'SecItemDelete' Sources 2>/dev/null | grep -v '^[^:]*CredentialStore.swift:')
[ -n "$out" ] && report "SecItemDelete outside CredentialStore.swift:" "$out"

[ $fail -eq 0 ] && echo "source-guards: ok"
exit $fail
