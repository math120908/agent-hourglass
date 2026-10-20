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

## usagectl (CLI harness + soak)

`usagectl` uses its own Keychain service `cc.kuoc.claude-usage.cli`, never the app's or Claude Code's.

```bash
cd ~/project/claude-usage
swift build -c release --product usagectl
.build/release/usagectl login                 # once; finish login in the browser -> "login ok id=claude:<prefix>…"
security find-generic-password -s cc.kuoc.claude-usage.cli >/dev/null && echo keychain-ok
.build/release/usagectl fetch                 # one line: status, http, session %, weekly %
nohup .build/release/usagectl soak --hours 2 --interval 60 >/tmp/usagectl-soak.out 2>&1 &
scripts/soak-report.sh                        # after ~2 h: count, non-200s, 429s, max gap
.build/release/usagectl logout                # optional: delete the CLI Keychain item
```

Soak log: `~/Library/Application Support/cc.kuoc.claude-usage/soak.log` (0600, append-only). One line per fetch:
`<ISO time> status=<s> http=<code> session=<%> weekly=<%> n429=<count>`. No tokens are ever written.
