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
echo "secret-scan: ok"
