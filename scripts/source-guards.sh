#!/bin/bash
# Enforces source invariants from the spec (Keychain isolation).
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
report() { echo "source-guards: $1" >&2; echo "$2" >&2; fail=1; }
READER='Sources/UsageCore/Storage/ClaudeCodeKeychainReader.swift'

out=$(rg -l 'Claude Code-credentials' Sources App iOS 2>/dev/null | grep -v "^$READER\$")
[ -n "$out" ] && report "'Claude Code-credentials' outside $READER:" "$out"
out=$(rg -l '^import Security' Sources App iOS 2>/dev/null | grep -v 'CredentialStore.swift$' | grep -v "^$READER\$")
[ -n "$out" ] && report "'import Security' outside CredentialStore.swift / $READER:" "$out"
out=$(rg -n 'kSecMatchLimitAll' Sources App iOS 2>/dev/null)
[ -n "$out" ] && report "kSecMatchLimitAll is forbidden:" "$out"
out=$(rg -n 'SecItemDelete' Sources 2>/dev/null | grep -v '^[^:]*CredentialStore.swift:')
[ -n "$out" ] && report "SecItemDelete outside CredentialStore.swift:" "$out"
# The Claude Code reader is read-only: no write, ACL, subprocess, or refresh-token path.
out=$(rg -n -e 'SecItemAdd' -e 'SecItemUpdate' -e 'SecItemDelete' -e 'SecKeychain' -e 'SecAccess' -e 'SecTrusted' \
  -e 'kSecValueData' -e 'Process\(' -e '/usr/bin/security' -e 'refreshToken' "$READER" 2>/dev/null)
[ -n "$out" ] && report "write/ACL/subprocess/refresh path in $READER:" "$out"
out=$(rg -n '/usr/bin/security' Sources App iOS 2>/dev/null)
[ -n "$out" ] && report "/usr/bin/security is forbidden:" "$out"
# Logging: account ids must never be logged in the clear.
out=$(rg -n 'rawValue, privacy: \.public' Sources App 2>/dev/null)
[ -n "$out" ] && report "account id logged with privacy: .public:" "$out"

# Portability: UsageCore must build for iOS; its tests must not depend on macOS-only modules.
out=$(rg -l '^import (AppKit|ServiceManagement)' Sources/UsageCore 2>/dev/null)
[ -n "$out" ] && report "AppKit/ServiceManagement import in portable UsageCore:" "$out"
out=$(rg -l '^(@testable )?import (AppKit|UsageCoreMac)' Tests/UsageCoreTests 2>/dev/null)
[ -n "$out" ] && report "AppKit/UsageCoreMac import in UsageCoreTests:" "$out"

# iOS shell: no iCloud Keychain sync, no standard defaults, no logging to console, no iCloud/push entitlements.
out=$(rg -n 'kSecAttrSynchronizable' Sources App iOS 2>/dev/null)
[ -n "$out" ] && report "kSecAttrSynchronizable is forbidden:" "$out"
out=$(rg -n 'UserDefaults\.standard' iOS 2>/dev/null)
[ -n "$out" ] && report "UserDefaults.standard in iOS/ (use AppGroup.defaults):" "$out"
out=$(rg -n -g '*.swift' -e '\bprint\(' -e '\bNSLog\(' iOS 2>/dev/null)
[ -n "$out" ] && report "print(/NSLog( in iOS/:" "$out"
out=$(rg -n -i -g '*.entitlements' -e 'icloud' -e 'ubiquity' -e 'aps-environment' iOS 2>/dev/null)
[ -n "$out" ] && report "iCloud/push entitlement in iOS/:" "$out"

# Mac-only credential paths: the phone must never reach Claude Code's Keychain item or legacy migration.
macgate() { # file, declaration regex: the declaration must sit after an '#if os(macOS)' line
  gawk -v pat="$2" '/^#if os\(macOS\)/{g=1} $0 ~ pat {found=1; if(!g) bad=1} END{exit (found && !bad) ? 0 : 1}' "$1"
}
macgate "$READER" '^public struct ClaudeCodeKeychainReader' || report "ClaudeCodeKeychainReader not gated by #if os(macOS):" "$READER"
macgate Sources/UsageCore/Storage/LegacyMigration.swift '^public enum LegacyMigration' || report "LegacyMigration not gated by #if os(macOS):" "Sources/UsageCore/Storage/LegacyMigration.swift"
out=$(rg -l -e 'ClaudeCodeKeychainReader' -e 'LegacyMigration' iOS 2>/dev/null)
[ -n "$out" ] && report "iOS/ references Mac-only credential code:" "$out"

# GRDB stays in UsageHistory (Mac app + usagectl); UsageCore and iOS must never link it.
out=$(rg -l '^import (GRDB|UsageHistory)' Sources/UsageCore iOS 2>/dev/null)
[ -n "$out" ] && report "GRDB/UsageHistory import in UsageCore or iOS/:" "$out"
out=$(rg -n 'UsageHistory|GRDB' iOS/project.yml 2>/dev/null)
[ -n "$out" ] && report "iOS target depends on UsageHistory/GRDB:" "$out"

[ $fail -eq 0 ] && echo "source-guards: ok"
exit $fail
