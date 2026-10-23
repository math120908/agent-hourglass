#!/bin/bash
# Tests for build-number.sh (YYMMDD.HMMSS, UTC, leading zeros stripped from the second component).
set -euo pipefail
cd "$(dirname "$0")"
fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2' want '$3'"; fail=1; fi; }
out=$(./build-number.sh)
[[ "$out" =~ ^[0-9]{6}\.([1-9][0-9]{0,5}|0)$ ]] && echo "PASS format" || { echo "FAIL format: $out"; fail=1; }
check midnight "$(BUILD_NUMBER_NOW=2026-10-24T00:05:12Z ./build-number.sh)" 261024.512
check afternoon "$(BUILD_NUMBER_NOW=2026-10-23T15:30:12Z ./build-number.sh)" 261023.153012
check zero "$(BUILD_NUMBER_NOW=2026-10-24T00:00:00Z ./build-number.sh)" 261024.0
check order "$(printf '261024.512\n261023.153012\n' | sort -t. -k1,1n -k2,2n | tail -1)" 261024.512
exit $fail
