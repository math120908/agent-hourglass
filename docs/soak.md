# Soak results

## Baseline: usagectl soak, old backoff (reset on first 200)
Run: `.build/release/usagectl soak --hours 2 --interval 60`, 2026-10-20 16:36Z to 18:37Z, build before e981a40.
Summary (`scripts/soak-report.sh`): 118 fetches, 72 x 200, 46 x 429, max gap 64 s.

429s per 10 min (UTC): 17:0x 1 | 17:1x 6 | 17:2x 6 | 17:3x 5 | 17:4x 5 | 17:5x 6 | 18:0x 5 | 18:1x 5 | 18:2x 4 | 18:3x 3.
First 429 at 17:08:34Z after ~32 min of clean 200s; after that roughly 1 in 3 fetches was rate limited.
Concurrent callers on the same account: third-party /Applications/Claude Usage.app (running) and Claude Code [inferred].
Analysis: pokemon_pantheon `workspace/261020-claude-usage-mac/research/soak-429-analysis.md`.

## In-app run: new backoff (step down one level per 200), e981a40+
Claude account added in the app 2026-10-20 19:58 local. Full 2 h run skipped by CK. Partial: `log show` for the app subsystem found 0 lines matching 429/rateLimited between 19:58 and 21:08 local (one query, not cross-checked); history has 19 Claude samples in that window. Third-party Claude Usage.app was running throughout.
