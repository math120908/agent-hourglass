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
# Google / Grok use owned credentials only: the CLI stores are never read or written (no path to them).
out=$(rg -n -e '\.gemini/' -e '\.grok/' -e 'oauth_creds\.json' -e 'antigravity-cli' Sources App iOS 2>/dev/null)
[ -n "$out" ] && report "[cli-creds] CLI credential store path (never read or write ~/.gemini / ~/.grok):" "$out"
# Logging: account ids must never be logged in the clear.
out=$(rg -n 'rawValue, privacy: \.public' Sources App 2>/dev/null)
[ -n "$out" ] && report "account id logged with privacy: .public:" "$out"
# Error text can embed file paths and Keychain attributes: log type(of:) and the code only (S2).
out=$(rg -n 'String\(describing: error\), privacy: \.public' Sources App iOS 2>/dev/null)
[ -n "$out" ] && report "raw error logged with privacy: .public (log type(of: error) + code):" "$out"
# History db gets an explicit file-protection class after open, not only the inherited one (N9).
rg -q 'SnapshotCache\.protect' Sources/UsageHistory/History/HistoryStore.swift || report "HistoryStore does not call SnapshotCache.protect (N9):" "Sources/UsageHistory/History/HistoryStore.swift"

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

# iOS sign-in surfaces: no embedded web view at all (Claude signs in through an ephemeral
# ASWebAuthenticationSession plus paste), no programmatic pasteboard reads (only the system
# PasteButton reads; writes and hasStrings are fine), no dump(. Full-line // comments are ignored.
# Sources/UsageCore is linked into the iOS app, so it gets the WebKit, pasteboard and session
# rules too (S7); neither the Mac app nor UsageCore uses WebKit or UIPasteboard.
# All of iOS/ (so a new extension directory is covered) except test targets and build output.
IOSSRC=(iOS -g '!iOS/Tests/**' -g '!iOS/WidgetTests/**' -g '!iOS/build/**' -g '!**/DerivedData/**')
IOSLINKED=("${IOSSRC[@]}" Sources/UsageCore)
nocomment() { rg -v '^[^:]+:[0-9]+:\s*//'; }
# Any attributes (with arguments) and access level before import, any import kind, after ; too;
# any WK* type, SwiftUI WebPage/WebView, any SFSafari* type (persistent cookie store).
# ASWebAuthenticationSession lives in AuthenticationServices: allowed, but see [ephemeral].
out=$(rg -n -P -g '*.swift' \
  -e '(^|;)\s*((@\w+(\([^)]*\))?|public|package|internal|fileprivate|private)\s*)*\bimport\s+(\w+\s+)?(WebKit|SafariServices)\b' \
  -e '\bWK[A-Z]\w*' -e '\bWeb(Page|View)\b' -e '\bSFSafari\w*' "${IOSLINKED[@]}" 2>/dev/null | nocomment)
[ -n "$out" ] && report "[webkit] WebKit / WebView / SafariServices in iOS-linked code (sign in with ASWebAuthenticationSession):" "$out"
# Allowlist: every UIPasteboard use must be UIPasteboard.general.hasStrings or a write
# UIPasteboard.general.string = ...; aliases, split member access and any other API fail.
out=$(rg -n -g '*.swift' 'UIPasteboard' "${IOSLINKED[@]}" 2>/dev/null | nocomment |
  perl -ne '($c = $_) =~ s/^[^:]+:\d+://; $c =~ s/\bUIPasteboard\.general\.hasStrings\b//g; $c =~ s/\bUIPasteboard\.general\.string\s*=(?!=)//g; print if $c =~ /UIPasteboard/')
[ -n "$out" ] && report "[pasteboard] UIPasteboard use outside the allowlist in iOS-linked code (only .general.hasStrings and .general.string = ...; reads use PasteButton):" "$out"
# One file builds the web-auth session; everywhere else (Mac app included) it is never named, and
# SwiftUI's webAuthenticationSession environment value is never used.
AUTH='iOS/App/AddAccount/PasteBrowser.swift'
out=$(rg -n -g '*.swift' -e '\bASWebAuthenticationSession\w*' -e 'prefersEphemeralWebBrowserSession' Sources App iOS 2>/dev/null |
  grep -v "^$AUTH:" | nocomment)
[ -n "$out" ] && report "[auth-session] ASWebAuthenticationSession outside $AUTH:" "$out"
out=$(rg -n -g '*.swift' '\b[Ww]ebAuthenticationSession\b' Sources App iOS 2>/dev/null | nocomment)
[ -n "$out" ] && report "[auth-session] SwiftUI WebAuthenticationSession (use PasteBrowser's ephemeral session):" "$out"
# In that file: each `let X = ASWebAuthenticationSession(...)` is immediately followed by
# `X.prefersEphemeralWebBrowserSession = true` in code; no other mention, .init, Self, #if or KVC.
if [ -f "$AUTH" ]; then
  out=$(perl scripts/guard-auth-session.pl "$AUTH" 2>&1) || report "[ephemeral] $AUTH must build only ephemeral sessions:" "$out"
fi
out=$(rg -n -g '*.swift' '\bdump\(' "${IOSSRC[@]}" 2>/dev/null)
[ -n "$out" ] && report "[dump] dump( in iOS/:" "$out"

[ $fail -eq 0 ] && echo "source-guards: ok"
exit $fail
