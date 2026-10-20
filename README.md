# claude-usage

macOS menu bar app that shows plan usage for Claude and GitHub Copilot accounts: current session and weekly meters in a popover, a menu bar icon for one chosen account, and a History window with charts and export.

`UsageCore` is an SPM library (no AppKit); `App/` is the AppKit shell built via XcodeGen.

## Install

Requires Xcode, XcodeGen, and the self-signed code-signing identity `Claude Usage Dev` in the login keychain:

- SHA-1: `FA3D8189AA4D9C1371B314CBDD1278672754EE99`
- Valid until 2036-10-17

```bash
make test      # swift test + secret-scan + source-guards
make app       # xcodegen + Release build + GitCommit stamp + codesign
make install   # make app, quit the running app, copy to ~/Applications/ClaudeUsage.app
```

The app installs as `~/Applications/ClaudeUsage.app`. It is a different app from Anthropic's `/Applications/Claude Usage.app` (note the space); never overwrite or delete that one.

When macOS asks for Keychain access, click **Allow**, never **Always Allow**. The app only reads its own items.

## Accounts

Settings > Accounts:

- **Add Claude account...** opens the browser OAuth login. The token is stored in the Keychain under service `cc.kuoc.claude-usage`. The app never reads Claude Code's own credential.
- **Add Copilot account...** uses the GitHub CLI. Install `gh` (Homebrew) and run `gh auth login` first; the app asks `gh` for the token on each poll and does not store it.

## History and export

Usage samples are kept in a local SQLite file. Raw samples are kept for 90 days (30 if `historyRawDays` is set to 30, or automatically if the file grows past 100 MB), then rolled up to hourly points kept for 2 years.

The History window shows 24 Hours, 7 Days, 30 Days, or 90 Days. **Export Data** saves CSV or JSON for the selected account; hold Option while choosing to export all accounts.

## Data locations

| Path | Mode | Content |
|---|---|---|
| `~/Library/Application Support/cc.kuoc.claude-usage/` | 700 | app support dir |
| `.../accounts.json` | 600 | account list (display names, ids, gh login) |
| `.../history.sqlite` (+ `-wal`, `-shm`) | 600 | usage history |
| `.../instance.lock` | 600 | single-instance lock |
| Keychain, service `cc.kuoc.claude-usage` | | Claude OAuth tokens |

Logs go to the unified log, subsystem `cc.kuoc.claude-usage`. Tokens are never logged. About > **Copy diagnostics** hashes account ids and contains no tokens, emails, or names.

## Uninstall

```bash
pkill -x ClaudeUsage
rm -rf ~/Applications/ClaudeUsage.app
rm -rf ~/Library/Application\ Support/cc.kuoc.claude-usage
# Keychain items (repeat until "could not be found"):
security delete-generic-password -s cc.kuoc.claude-usage
security delete-generic-password -s cc.kuoc.claude-usage.cli
```

If launch at login was on, turn it off in Settings first (or remove ClaudeUsage from System Settings > General > Login Items).

## Known limits

- Usage endpoints are undocumented and may change; unknown fields show as a schema error and appear in diagnostics.
- Polling backs off on HTTP 429 (at least the Retry-After value, minimum 60 s), so a card can show "Rate limited" for a while.
- Copilot requires `gh`; removing the login from `gh` shows "Login not in gh".
- Self-signed: other Macs need their own identity (`make app ID=<sha1>`). Not notarized.
- No notifications.

## Dev only

Not part of a normal install. These exist for testing and must not be used with shipped builds:

- `usagectl` (CLI harness and soak, `swift build -c release --product usagectl`). Uses its own Keychain service `cc.kuoc.claude-usage.cli` and writes `soak.log`, `usagectl-accounts.json`, `usagectl.lock` (all 600) into the app support dir.
- App launch args `--fixture`, `--render-*` (snapshot renderers), `--simulate-keychain-write-failure`. Debug-only paths; not for daily use.
- `make sign ID=<sha1>`, `make hooks` (pre-commit secret-scan + source-guards).

Release checks: `docs/release-checklist.md`.
