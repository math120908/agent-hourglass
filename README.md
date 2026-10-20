# claude-usage

macOS menu bar app showing Claude plan usage. `UsageCore` is an SPM library (no AppKit); `App/` is the AppKit shell built via XcodeGen.

## Signing identity

- Name: `Claude Usage Dev` (self-signed, login keychain)
- SHA-1: `FA3D8189AA4D9C1371B314CBDD1278672754EE99`
- Validity: 10 years

## make targets

- `make test` — `swift test` + `scripts/secret-scan.sh` + `scripts/source-guards.sh`
- `make app` — xcodegen + Release build + sign
- `make sign ID=<sha1>` — re-sign `build/.../ClaudeUsage.app` (default ID above)
- `make install` — build and copy to `~/Applications/ClaudeUsage.app`
- `make hooks` — install the pre-commit hook (secret-scan + source-guards)
