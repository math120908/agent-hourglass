#!/bin/bash
# Tests scripts/mac-sign-id.sh against a fake `security` on PATH (no real certificate needed).
set -uo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
A=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
D=DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD
O=EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
dev="  1) $D \"Apple Development: Test Person (ZZZZZZZZZZ)\""
other="  2) $O \"Developer ID Application: Other Person (QQQQQQQQQQ)\""
fail=0
run() { # name, fake output, expected stdout, expected exit, expected stderr substring
  printf '#!/bin/bash\ncat <<"X"\n%s\nX\n' "$2" > "$tmp/security"; chmod +x "$tmp/security"
  out=$(PATH="$tmp:$PATH" scripts/mac-sign-id.sh 2>"$tmp/err"); rc=$?
  if [ "$out" != "$3" ] || [ "$rc" -ne "$4" ] || { [ -n "$5" ] && ! grep -qF -- "$5" "$tmp/err"; } || grep -q 'Person' "$tmp/err"; then
    echo "FAIL $1: rc=$rc out='$out' err='$(cat "$tmp/err")'" >&2; fail=1
  else echo "ok $1"; fi
}
run zero "$dev
$other
     2 valid identities found" "" 1 "no Developer ID Application identity for team R7V5X99HYA"
run one "$dev
  3) $A \"Developer ID Application: Test Person (R7V5X99HYA)\"
$other
     3 valid identities found" "$A" 0 ""
run two "$dev
  3) $A \"Developer ID Application: Test Person (R7V5X99HYA)\"
  4) $B \"Developer ID Application: Test Person (R7V5X99HYA)\"
     4 valid identities found" "$A" 0 "2 Developer ID Application identities for team R7V5X99HYA; using $A"
exit $fail
