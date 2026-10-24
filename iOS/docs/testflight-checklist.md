# TestFlight checklist

Run before every TestFlight upload. Runtime checks run against the booted simulator after a real sign-in:
`make -C iOS security-pass-start-log`, sign in to each provider, tap About > Copy diagnostics, then `make -C iOS security-pass`.

| Check | Command | Expected | Result (date) |
|---|---|---|---|
| S1 logs | `make -C iOS security-pass` | `PASS S1 logs` (no token, code, or verifier pattern in the stream or `log show --last 2h`) | |
| S2 App Group modes | `make -C iOS security-pass` | `PASS S2 app group modes`, `PASS S2 snapshot content` (dirs 700, files 600, no `@`) | |
| S3 Keychain | `make -C iOS security-pass` | `PASS S3 keychain` (every item in `*.cc.kuoc.agent-hourglass.shared` is `cku`, `sync = 0`) | |
| S4 web store | `make -C iOS security-pass` | `PASS S4 web store` (no claude/anthropic data in Cookies, WebKit, Caches) | |
| S5 Diagnostics | `make -C iOS security-pass` | `PASS S5 diagnostics` (has `accounts:`, no uuid, no `@`) | |
| Static guards | `make test` | `source-guards: ok`, `secret-scan: ok` | |
| Mac logins | `iOS/scripts/mac-logins-check.sh` | every line `PASS` | PASS x4 (2026-10-23, baseline before phone sign-in) |
| Upload | `make -C iOS testflight` | `testflight: uploaded 1.0.0 (<build>) <commit>` | |

## On-device acceptance

TestFlight build `1.0.0 (261024.2558)`, commit `99040fb`, tested 2026-10-24 on iPhone 16 Pro by the owner. The build is TestFlight Internal only (App Store Connect status: Testing, Internal).

| Row | Check | Expected | Result (date) |
|---|---|---|---|
| A1 | App > **+** > Claude: paste-code sign-in | Claude card shows meters and "updated" age; the sheet stays open | PASS (2026-10-24) |
| A2 | **+** > Codex: device code login | Codex card shows meters | PASS (2026-10-24) |
| A3 | **+** > GitHub Copilot | Copilot card shows meters | N/A (not in iPhone v1) |
| A4 | Home Screen small widget, Edit Widget: pick account and two rows | Shows the configured account and rows with reset line and age | PASS (2026-10-24) |
| A5 | Lock Screen circular, rectangular, inline widgets | Each shows a value for its account/meter | PASS (2026-10-24) |
| A6 | Settings: switch **Show remaining** | Every widget shows remaining % | PASS (2026-10-24) |
| A7 | Tap a reset line (clock <-> countdown) | Widgets follow | PASS (2026-10-24) |
| A8 | Settings > Theme > Instrument | App and every widget switch theme | PASS (2026-10-24) |
| A9 | Home Screen Tinted / Clear, dark / light; lock 30 min | Small widget legible in each; Lock Screen age under 30 min on wake | PASS (2026-10-24) |
| A10 | Tap a widget | App opens scrolled to that account | PASS (2026-10-24) |
| A11 | `iOS/scripts/mac-logins-check.sh` | Claude Code, Codex CLI, Agent Hourglass running, no `needsLogin` / `invalid_grant` in 2h | PASS 4/4 (2026-10-24) |
| A12 | Remove account: confirmation dialog, tap Cancel | Account is kept | PASS (2026-10-24) |
