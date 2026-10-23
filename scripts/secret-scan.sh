#!/bin/bash
# Fails if any test fixture looks like it contains a real secret or account id.
# Every rg call goes through scan(): exit 2 (bad regex, unreadable file) fails the scan, never "ok".
set -uo pipefail
cd "$(dirname "$0")/.."
die() { echo "secret-scan: $*" >&2; exit 1; }
# scan <rg args...>: matches land in $hits; any rg error fails the run.
scan() { hits=$(rg "$@"); local rc=$?; [ $rc -le 1 ] || die "rg failed (exit $rc): rg $*"; }
report() { [ -z "$hits" ] || { echo "secret-scan: $1:" >&2; echo "$hits" >&2; exit 1; }; }

# A private key: a PEM header followed by a key body, so scripts may compare against the bare header.
# The gap allows CRLF, indentation (YAML, Swift """), JSON \n escapes and trailing spaces; legacy
# encrypted PEM puts Proc-Type / DEK-Info lines before the body. Matched with rg -U -P.
pem_re='-----BEGIN [A-Z ]*PRIVATE KEY-----[^A-Za-z0-9+/]{0,40}(?:(?:Proc-Type|DEK-Info):[^\n]*\s*)*[A-Za-z0-9+/]{40,}'

# Self-test: throwaway keys generated now (never committed), one file per form; each must match, and
# the bare header compare must not.
st_dir=
trap '[ -z "$st_dir" ] || rm -rf "$st_dir"' EXIT
selftest() {
  local d f missed= ossl=/usr/bin/openssl
  d=$(mktemp -d) || die "self-test: mktemp failed"
  st_dir=$d
  ( umask 077
    $ossl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$d/pkcs8.pem" 2>/dev/null \
      && $ossl ec -in "$d/pkcs8.pem" -out "$d/ec.pem" 2>/dev/null \
      && $ossl ec -in "$d/pkcs8.pem" -aes256 -passout pass:selftest -out "$d/legacy-proc-type.pem" 2>/dev/null \
      && $ossl pkcs8 -topk8 -v2 aes-256-cbc -passout pass:selftest -in "$d/pkcs8.pem" -out "$d/encrypted.pem" 2>/dev/null \
      && ssh-keygen -q -t ed25519 -N '' -C '' -f "$d/openssh.pem" >/dev/null 2>&1 \
      && rm -f "$d/openssh.pem.pub" \
      && sed 's/$/\r/' "$d/pkcs8.pem" > "$d/crlf.pem" \
      && { echo 'key: |'; sed 's/^/  /' "$d/pkcs8.pem"; } > "$d/indented.yaml" \
      && { echo 'let k = """'; sed 's/^/    /' "$d/ec.pem"; echo '    """'; } > "$d/indented.swift" \
      && { printf '{"key": "'; awk '{printf "%s\\n", $0}' "$d/pkcs8.pem"; printf '"}\n'; } > "$d/json-escaped.json" \
      && sed '1s/$/   /' "$d/pkcs8.pem" > "$d/trailing-space.pem" \
      && rg -q -F 'Proc-Type:' "$d/legacy-proc-type.pem" \
      && [ "$(head -n 1 "$d/encrypted.pem")" = '-----BEGIN ENCRYPTED PRIVATE KEY-----' ] \
      && [ "$(head -n 1 "$d/openssh.pem")" = '-----BEGIN OPENSSH PRIVATE KEY-----' ] \
      && [ "$(head -n 1 "$d/ec.pem")" = '-----BEGIN EC PRIVATE KEY-----' ]
  ) || die "self-test: could not generate throwaway keys"
  for f in "$d"/*; do
    scan -U -P -l -e "$pem_re" -- "$f"
    [ -n "$hits" ] || missed="$missed $(basename "$f")"
  done
  [ -z "$missed" ] || die "self-test: PEM rule missed:$missed"
  # The negative: a script comparing the first line against the bare header.
  printf '%s\n' "[ \"\$(head -n 1 \"\$k\")\" = '-----BEGIN PRIVATE KEY-----' ] || exit 4" > "$d/bare-header.sh"
  scan -U -P -l -e "$pem_re" -- "$d/bare-header.sh"
  [ -z "$hits" ] || die "self-test: PEM rule flags a bare header compare"
}
selftest

scan -n --hidden \
  -e 'sk-ant-' -e 'gho_' -e 'ghu_' \
  -e '"access"\s*:\s*"[^"]{8,}' -e '"refresh"' \
  -e '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
  Tests/UsageCoreTests/Fixtures
report "possible secret in fixtures"
scan -n --hidden \
  -e 'sk-ant-' -e 'gho_' -e 'ghu_' \
  -e '"access"\s*:\s*"[^"]{8,}' -e '"refresh"' \
  iOS
report "possible secret in iOS/"
# Signing material and App Store Connect keys must never be committed.
files=$(git ls-files) || die "git ls-files failed"
hits=$(printf '%s\n' "$files" | rg -e '\.p8$' -e '\.p12$' -e '\.mobileprovision$' -e '\.cer$' -e '(^|/)AuthKey_[^/]*$' -e '(^|/)asc\.env$')
[ $? -le 1 ] || die "rg failed on the tracked file list"
report "signing material / App Store Connect material tracked by git"
# Private keys and issuer ids in any tracked file (files deleted in the work tree are skipped).
tracked=()
while IFS= read -r -d '' f; do [ -e "$f" ] && tracked+=("$f"); done < <(git ls-files -z)
[ ${#tracked[@]} -gt 0 ] || die "no tracked files"
scan -U -P -n -l -e "$pem_re" -e 'ASC_ISSUER_ID=[0-9a-f-]{8,}' -- "${tracked[@]}"
report "private key / App Store Connect material tracked by git"
echo "secret-scan: ok"
