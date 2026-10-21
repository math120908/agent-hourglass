# Development

`UsageCore` is an SPM library (no AppKit); `App/` is the AppKit shell built via XcodeGen.

## Build

Requires Xcode, XcodeGen, and the self-signed code-signing identity `Claude Usage Dev` in the login keychain:

- SHA-1: `FA3D8189AA4D9C1371B314CBDD1278672754EE99`
- Valid until 2036-10-17

```bash
make test      # swift test + secret-scan + source-guards
make app       # xcodegen + Release build + version bump + GitCommit stamp + codesign
make install   # make app, quit the running app, copy to ~/Applications/AgentHourglass.app
make icon      # regenerate App/Resources/AppIcon.icns from AppIcon.svg
```

## Versioning

Each build on `master` bumps the patch version (`1.0.1`, `1.0.2`, ...). The counter lives in the untracked `.build-number`; builds on other branches reuse it with a `-dev` suffix.

## Signing and Keychain prompts

The build is self-signed, so it has no Team ID and every rebuild changes the signature macOS checks. After each rebuild macOS may ask once for Keychain access; click **Allow**, never **Always Allow**. Other Macs need their own identity (`make app ID=<sha1>`). Not notarized.

## Dev-only tools

Not part of a normal install. These exist for testing and must not be used with shipped builds:

- `usagectl` (CLI harness and soak, `swift build -c release --product usagectl`). Uses its own Keychain service `cc.kuoc.claude-usage.cli` and writes `soak.log`, `usagectl-accounts.json`, `usagectl.lock` (all 600) into the app support dir.
- App launch args `--fixture`, `--render-*` (snapshot renderers), `--simulate-keychain-write-failure`. `--theme instrument` (or `glass`) selects which theme the `--render-states` and `--render-history` renderers draw; default Glass. Debug-only paths; not for daily use.
- `make sign ID=<sha1>`, `make hooks` (pre-commit secret-scan + source-guards).

Release checks: `docs/release-checklist.md`.
