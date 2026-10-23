# TestFlight checklist

Run before every TestFlight upload. Runtime checks run against the booted simulator after a real sign-in:
`make -C iOS security-pass-start-log`, sign in to each provider, tap About > Copy diagnostics, then `make -C iOS security-pass`.

| Check | Command | Expected | Result (date) |
|---|---|---|---|
| S1 logs | `make -C iOS security-pass` | `PASS S1 logs` (no token, code, or verifier pattern in the stream or `log show --last 2h`) | |
| S2 App Group modes | `make -C iOS security-pass` | `PASS S2 app group modes`, `PASS S2 snapshot content` (dirs 700, files 600, no `@`) | |
| S3 Keychain | `make -C iOS security-pass` | `PASS S3 keychain` (every item in `*.cc.kuoc.agent-hourglass.shared` is `cku`, `sync = 0`) | |
| S4 WKWebView store | `make -C iOS security-pass` | `PASS S4 web store` (no claude/anthropic data in Cookies, WebKit, Caches) | |
| S5 Diagnostics | `make -C iOS security-pass` | `PASS S5 diagnostics` (has `accounts:`, no uuid, no `@`) | |
| Static guards | `make test` | `source-guards: ok`, `secret-scan: ok` | |
| Mac logins | `iOS/scripts/mac-logins-check.sh` | every line `PASS` | |
| Upload | `make -C iOS testflight` | `testflight: uploaded 1.0.0 (<build>) <commit>` | |
