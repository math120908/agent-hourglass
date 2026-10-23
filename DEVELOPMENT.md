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

Each build on `master` bumps the patch version (`1.0.1`, `1.0.2`, ...). The counter lives in the untracked `.build-number`; builds on other branches reuse it with a `-dev` suffix.

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

Requirements: Xcode, XcodeGen, an Apple Distribution identity in the login keychain (team R7V5X99HYA), and for uploads `~/.config/agent-hourglass/asc.env` (defines `ASC_KEY_ID`, `ASC_ISSUER_ID`) plus `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`. Both files mode 600, backed up in 1Password, never in the repo.

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

Simulator defaults: `SIM_NAME=iPhone 17`, `SIM_OS=26.0` (override on the make command line). Signing is automatic with team R7V5X99HYA; simulator builds need no signing.
