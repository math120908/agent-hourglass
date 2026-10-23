#!/bin/bash
# Fails if any test fixture looks like it contains a real secret or account id.
set -uo pipefail
cd "$(dirname "$0")/.."
hits=$(rg -n --hidden \
  -e 'sk-ant-' -e 'gho_' -e 'ghu_' \
  -e '"access"\s*:\s*"[^"]{8,}' -e '"refresh"' \
  -e '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
  Tests/UsageCoreTests/Fixtures)
if [ -n "$hits" ]; then
  echo "secret-scan: possible secret in fixtures:" >&2
  echo "$hits" >&2
  exit 1
fi
hits=$(rg -n --hidden \
  -e 'sk-ant-' -e 'gho_' -e 'ghu_' \
  -e '"access"\s*:\s*"[^"]{8,}' -e '"refresh"' \
  iOS)
if [ -n "$hits" ]; then
  echo "secret-scan: possible secret in iOS/:" >&2
  echo "$hits" >&2
  exit 1
fi
# Signing material and App Store Connect keys must never be committed.
hits=$(git ls-files | rg -e '\.p8$' -e '\.p12$' -e '\.mobileprovision$' -e '\.cer$' -e '(^|/)AuthKey_[^/]*$')
if [ -n "$hits" ]; then
  echo "secret-scan: signing material tracked by git:" >&2
  echo "$hits" >&2
  exit 1
fi
# Private keys, App Store Connect env files, and issuer ids in any tracked file.
hits=$(git ls-files -z | gxargs -0 rg -n -l -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' -e 'ASC_ISSUER_ID=[0-9a-f-]{8,}' 2>/dev/null; git ls-files | rg -e '(^|/)asc\.env$')
if [ -n "$hits" ]; then
  echo "secret-scan: private key / App Store Connect material tracked by git:" >&2
  echo "$hits" >&2
  exit 1
fi
echo "secret-scan: ok"
