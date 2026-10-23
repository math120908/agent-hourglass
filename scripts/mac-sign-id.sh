#!/bin/bash
# Prints the SHA1 of the Developer ID Application identity for TEAM (default R7V5X99HYA).
# Several matches: the first one listed is used and its SHA1 is reported on stderr.
set -uo pipefail
team="${TEAM:-R7V5X99HYA}"
list=$(security find-identity -v -p codesigning 2>/dev/null)
ids=$(printf '%s\n' "$list" \
  | rg -o "^\s*[0-9]+\) ([0-9A-F]{40}) \"Developer ID Application: .* \($team\)\"$" -r '$1')
n=$(printf '%s' "$ids" | rg -c '^[0-9A-F]{40}$' || true)
n=${n:-0}
if [ "$n" -eq 0 ]; then
  echo "mac-sign-id: no Developer ID Application identity for team $team in the keychain." >&2
  echo "mac-sign-id: install the certificate and its private key (Xcode > Settings > Accounts > Manage Certificates, or import the .p12 from 1Password), or pass ID=<sha1>." >&2
  exit 1
fi
id=$(printf '%s\n' "$ids" | head -n 1)
[ "$n" -gt 1 ] && echo "mac-sign-id: $n Developer ID Application identities for team $team; using $id" >&2
echo "$id"
