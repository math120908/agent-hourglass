# Development

`UsageCore` is an SPM library (no AppKit); `App/` is the AppKit shell built via XcodeGen.

## Build

Requires Xcode, XcodeGen, and a **Developer ID Application** identity in the login keychain (found by team R7V5X99HYA via `security find-identity`, see `scripts/mac-sign-id.sh`; override with `make app ID=<sha1>`). `make sign` fails if the signature has no TeamIdentifier.

```bash
make test      # swift test + check-ios + secret-scan + test-mac-sign-id + source-guards
make check-ios  # build UsageCore for iOS Simulator
make app       # xcodegen + Release build + version bump + GitCommit stamp + codesign
make install   # make app, quit the running app, copy to ~/Applications/AgentHourglass.app
make release   # make app, notarize, staple, zip to dist/AgentHourglass-<version>.zip, tag v<version>
make icon      # regenerate App/Resources/AppIcon.icns from AppIcon.svg
```

## Versioning

Each build on `master` bumps the patch version (`1.0.1`, `1.0.2`, ...) and creates and pushes an annotated `v<version>` tag on the built commit (an existing tag is never moved; if the push fails, push it later with `git push origin v<version>`). The counter lives in the untracked `.build-number`; builds on other branches reuse it with a `-dev` suffix and are not tagged.

## Signing, notarization, release

Builds are signed with Developer ID, hardened runtime, and a secure timestamp. Because the signature carries a Team ID, Keychain access granted once survives rebuilds; the first launch after switching certificates asks once more (click **Allow**).

Notarization uses the notarytool keychain profile `agent-hourglass` (`NOTARY_PROFILE` in the `Makefile`). One-time setup per Mac:

```bash
xcrun notarytool store-credentials agent-hourglass --apple-id <apple-id> --team-id <team-id>
```

It asks for an app-specific password from account.apple.com. Credentials and the `.p12` backup live in 1Password under "Apple Developer - ...".

To publish:

```bash
make release
gh release create v<version> dist/AgentHourglass-<version>.zip --title "v<version>" --generate-notes
```

`make release` also creates and pushes an annotated `v<version>` tag on the built commit (it never moves an existing tag), so `gh release create v<version>` reuses it. It checks the result with `stapler validate` and `spctl` (expect `source=Notarized Developer ID`).

## Claude Code (local) Keychain experiment

The Claude Code (local) account reads the generic Keychain item `Claude Code-credentials` (account = `$USER`) with `SecItemCopyMatching` only, in `ClaudeCodeKeychainReader.swift` (the only file besides `CredentialStore.swift` allowed to import Security; `source-guards.sh` rejects any write, ACL, `security` CLI, or refresh-token reference there). Each read logs (at `notice` level, so it persists) its outcome (`ok`, `notFound`, `userCanceled(<OSStatus>)`, `interactionNotAllowed`, `malformed`, `other(<OSStatus>)`) and the item's modification date from an attribute-only query. No secrets are logged.

To see whether **Always Allow** survives Claude Code token refreshes:

```bash
log show --last 1d --info --predicate 'subsystem == "cc.kuoc.agent-hourglass" AND category == "ClaudeCodeKeychain"'
```

A new `itemModified` value followed by `ok` with no prompt means the grant survived the rewrite. A prompt (or `userCanceled`) right after a new `itemModified` means Claude Code recreated the item and dropped the grant. Use `log stream` with the same predicate to watch live.

## Grok provider (experimental)

Personal builds only: not in a release. Shows the SuperGrok weekly credit pool.

- **Client**: reuses the public Grok-CLI OAuth client (`GrokDeviceAuth.clientID`, issuer `https://auth.x.ai`) with exactly its scope `openid profile email offline_access grok-cli:access api:access`. No extra scopes such as `billing:read` are guessed.
- **Sign-in**: RFC 8628 device code (show code, open the xAI page, poll). No loopback port, so it never clashes with a concurrent `grok login`. `access_denied` / `expired_token` stop at once; `slow_down` adds 5 s.
- **Tokens**: the app keeps its own chain in Keychain service `cc.kuoc.agent-hourglass`. The refresh token rotates on every refresh (a response without one keeps the previous one); `invalid_grant` shows "needs sign-in", never a retry loop.
- **Never reads `~/.grok`**: the Grok CLI's own login is left untouched, so neither side logs the other out. `source-guards.sh` rejects the path.
- **Usage**: `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` (meters) and `/v1/settings` (plan, best effort), at most once per 5 min. A billing 403 shows "Quota unavailable". A missing `creditUsagePercent` gives an empty meter, never 0%.
- **Storage**: Grok accounts live in `accounts-ext.json`, next to `accounts.json`. Shipped builds never open it, so a downgrade only hides Grok accounts until this build runs again.

Response shapes log at `debug` level (category `ResponseShape`), which is not persisted. Values under token, secret, email, project, code, `sub` and similar keys become `<redacted>`; other strings become `<str N>` (length only). Numbers, bools and nulls pass through verbatim, numeric ids included. A billing 403 logs no body: only the status line `billing 403` (category `GrokProvider`, `error` level). Start the stream before adding the account:

```bash
log stream --level debug --predicate 'subsystem == "cc.kuoc.agent-hourglass"'
```

Add `AND category == "ResponseShape"` to see only the shapes.

To read them later with `log show --last 1h --debug` (same predicate), persist debug first: `sudo log config --subsystem cc.kuoc.agent-hourglass --mode "level:debug,persist:debug"`.

## Dev-only tools

Not part of a normal install. These exist for testing and must not be used with shipped builds:

- `usagectl` (CLI harness and soak, `swift build -c release --product usagectl`). Uses its own Keychain service `cc.kuoc.agent-hourglass.cli` and writes `soak.log`, `usagectl-accounts.json`, `usagectl.lock` (all 600) into the app support dir.
- App launch args `--fixture`, `--render-*` (snapshot renderers), `--simulate-keychain-write-failure`. `--theme instrument` (or `glass`) selects which theme the `--render-states` and `--render-history` renderers draw; default Glass. Debug-only paths; not for daily use.
- `make sign ID=<sha1>`, `make hooks` (pre-commit secret-scan + source-guards).

Release checks: `docs/release-checklist.md`.

## Legacy id migration

`Sources/UsageCore/Storage/LegacyMigration.swift` moves data from the old `cc.kuoc.claude-usage` id once per install (dir, defaults, Keychain via `CredentialStoring`; flags `migratedFromClaudeUsage`, `migratedKeychainFromClaudeUsage`). Check outcomes:

```bash
log show --last 1h --info --predicate 'subsystem == "cc.kuoc.agent-hourglass" AND category == "Migration"'
```

## iOS

Requirements: Xcode, XcodeGen, an Apple Distribution identity in the login keychain (team R7V5X99HYA), and for `archive` and `testflight`:

- `~/.config/agent-hourglass/asc.env`, mode 600, holding only `ASC_KEY_ID=<id>` and `ASC_ISSUER_ID=<uuid>`.
- The 1Password CLI (`op`) with the 1Password app integration on. The App Store Connect API key (role Admin, needed for cloud signing) lives only in 1Password: vault `Personal`, item `Apple Developer - App Store Connect API key (agent-hourglass)`, file field `p8`, field `Key ID` equal to `ASC_KEY_ID`. Override with `ASC_OP_VAULT` / `ASC_OP_ITEM`.

Each run asks for Touch ID: once when preflight checks the item, and again before the archive if 1Password locked during the tests. Right before the archive the script copies the key into a mode 700 `mktemp -d` dir (file mode 600) for `xcodebuild -authenticationKeyPath` and for altool (`API_PRIVATE_KEYS_DIR`), and removes it on exit (success, failure, Ctrl-C, TERM). The key is never in the repo and not on disk between runs: keep no `AuthKey_*.p8` in `~/.appstoreconnect/private_keys`, `~/private_keys` or `~/.private_keys`, where altool would also look. `ASC_KEY_PATH=/abs/path/AuthKey_<id>.p8` (mode 600) uses a local file instead of 1Password.

- `make -C iOS build`: generate the Xcode project (XcodeGen) and build for the simulator
- `make -C iOS test`: run the iOS unit tests on the simulator
- `make -C iOS run-sim`: build, boot the simulator headless, install and launch the app
- `make -C iOS render`: launch with `--render latest` and copy the PNGs to `iOS/docs/screenshots/`
- `make -C iOS icon`: regenerate the app icon from `App/Resources/AppIcon.svg`
- `make -C iOS security-pass-start-log` then `make -C iOS security-pass`: runtime security checks S1-S5 against the booted simulator
- `make -C iOS archive`: preflight, archive, verify, export an `.ipa` without uploading
- `make -C iOS testflight`: same, then upload to App Store Connect (TestFlight internal only)

Versioning: `MARKETING_VERSION` 1.0.0 in `iOS/project.yml`; build number `YYMMDD.HMMSS` in UTC from `iOS/scripts/build-number.sh`, set on the archive command line. TestFlight builds expire after 90 days: upload at least that often.

Release checks: [iOS/docs/testflight-checklist.md](iOS/docs/testflight-checklist.md). `make test` includes `make check-ios` (UsageCore builds for iOS) and the source guards and secret scan, which cover `iOS/`.

Simulator defaults: `SIM_NAME=iPhone 17`, `SIM_OS=26.5` (override on the make command line). Signing is automatic with team R7V5X99HYA; simulator builds need no signing.
