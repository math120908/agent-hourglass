# S1 spike: Claude OAuth PKCE loopback probe

Throwaway probe for Stage 3 S1a/S1b/S1c/S1d. Tokens stay in process memory: they are never printed, written to disk, or stored in Keychain.

## Run

```bash
cd ~/project/claude-usage/spikes/s1-claude-oauth
swift run S1Probe                              # S1a/S1b: scope user:profile
swift run S1Probe --login-hint you@example.com # choose the account
swift run S1Probe --scope "user:profile user:inference"  # if user:profile alone fails
swift run S1Probe --poll 10                    # S1d rate limit: 10 calls, 60 s apart
```

For S1b, run it twice and confirm that the two `listening on` ports differ and both runs get a callback.
To pick a different claude.ai account, paste the printed URL into a private window.

## Output

- `cc-item[before|after]`: attributes of `Claude Code-credentials` from `security find-generic-password` without `-w`/`-g`. Compare `mdat` (S1c).
- Token exchange: response keys, granted scope, `expires_in`, and whether a refresh token came back.
- Usage: HTTP status, top-level keys, each `limits[]` kind/group/percent/resets_at/model, `spend.*`, and `extra_usage` currency and amounts.
- `--poll`: one line per call with HTTP status and `Retry-After`.

If the authorize page rejects the `127.0.0.1` redirect, the error appears **in the browser** and no callback arrives. Copy that exact text, then press Ctrl-C (the script would otherwise time out after 5 min). The script never falls back to a fixed port or to `localhost`.
