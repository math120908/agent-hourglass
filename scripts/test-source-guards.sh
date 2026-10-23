#!/bin/bash
# Guard self-test: runs source-guards.sh against a copy of the tree with one fixture dropped in.
# Fixtures live in scripts/guard-fixtures/{bad,good}/*.swift.txt (never scanned, never compiled).
# Line 1 of each fixture: `// fixture: <tree path> [<rule id>]`. A bad fixture must exit 1 and
# print `[<rule id>]`; a good fixture must exit 0. GUARD=<file> tests another guard version.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
(cd "$root" && git ls-files -z -c -o --exclude-standard | xargs -0 tar cf - 2>/dev/null) | tar xf - -C "$tmp"
[ -n "${GUARD:-}" ] && cp "$GUARD" "$tmp/scripts/source-guards.sh"
guard="$tmp/scripts/source-guards.sh"

pass=0 failed=0 nbad=0 ngood=0
"$guard" >/dev/null 2>"$tmp/.base" || { echo "test-source-guards: baseline tree fails the guard:" >&2; cat "$tmp/.base" >&2; exit 1; }
for kind in bad good; do
  for fx in "$root"/scripts/guard-fixtures/$kind/*.swift.txt; do
    read -r _ _ path rule < "$fx"
    name="$kind/$(basename "$fx" .swift.txt)"
    target="$tmp/$path"
    mkdir -p "$(dirname "$target")"
    orig=""; [ -f "$target" ] && { orig="$tmp/.orig"; cp "$target" "$orig"; }
    cp "$fx" "$target"
    err=$("$guard" 2>&1 >/dev/null); rc=$?
    if [ -n "$orig" ]; then mv "$orig" "$target"; else rm -f "$target"; fi
    if [ $kind = bad ]; then
      nbad=$((nbad + 1))
      if [ $rc -eq 1 ] && grep -qF "[$rule]" <<<"$err"; then pass=$((pass + 1))
      else failed=$((failed + 1)); echo "FAIL $name: want exit 1 naming [$rule], got exit $rc" >&2; fi
    else
      ngood=$((ngood + 1))
      if [ $rc -eq 0 ]; then pass=$((pass + 1))
      else failed=$((failed + 1)); echo "FAIL $name: want exit 0, got exit $rc:" >&2; echo "$err" >&2; fi
    fi
  done
done
echo "test-source-guards: $pass/$((nbad + ngood)) ok ($nbad bad, $ngood good)"
[ $failed -eq 0 ]
