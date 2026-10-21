# Release checklist

Run from the repo root after `make install`. Every check must pass.

| Check | Command | Expected | Result (2026-10-20) |
|---|---|---|---|
| Tests | `make test` | all pass | pass |
| Credential guard | `rg -n 'Claude Code-credentials' Sources App` | only the guard | pass: no match in Sources or App (guard lives in scripts/source-guards.sh) |
| Codesign | `codesign -dvv ~/Applications/AgentHourglass.app 2>&1 \| grep Authority` | `Authority=Claude Usage Dev` | pass: Authority=Claude Usage Dev |
| About commit | `/usr/libexec/PlistBuddy -c 'Print :GitCommit' ~/Applications/AgentHourglass.app/Contents/Info.plist` | equals `git rev-parse --short HEAD` | pass: matches HEAD after rebuild |
| File modes | `stat -f '%Lp %N' ~/Library/Application\ Support/cc.kuoc.claude-usage ~/Library/Application\ Support/cc.kuoc.claude-usage/*` | dir `700`, files `600` | pass: dir 700, all 8 files 600 |
| Diagnostics grep | About > Copy diagnostics, `pbpaste > /tmp/cu-diag.txt`, then `rg -e 'sk-ant-' -e 'gh[opusr]_' -e '[0-9a-f]{8}-[0-9a-f]{4}-' /tmp/cu-diag.txt` | no match (exit 1) | pass: exit 1 (report built from live accounts.json via `Diagnostics.report`; account id and gh login also absent) |
| Log token grep | `log show --last 2d --predicate 'subsystem BEGINSWITH "cc.kuoc.claude-usage"' > /tmp/cu-log.txt; rg -e 'sk-ant-' -e 'gh[opusr]_' -e 'Bearer ' /tmp/cu-log.txt` | no match (exit 1) | pass: exit 1 over 79 lines |
