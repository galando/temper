#!/usr/bin/env bash
# Tests for scripts/check-mod-calls.sh using canned `calls:` lines (no claude needed).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
check() { # check <name> <expected exit> <calls line>
  local name="$1" want="$2" line="$3" out rc
  out="$(CHECK_MOD_CALLS_LINE="$line" bash "$ROOT/scripts/check-mod-calls.sh" 2>&1)"; rc=$?
  if [[ $rc -eq $want ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $name (exit $rc, wanted $want): $out"; fi
}
GOOD='./temper-mod/register.tsx calls: $.fs.list (via makeIo), $.store.get (via firstRunAsk, makeIo), $.ui.ask (via askDrift), $.ui.resolve'
check "reviewed calls pass, via lists included" 0 "$GOOD"
check "process call fails" 1 "$GOOD, \$.process.spawn (via run)"
check "http call fails" 1 "$GOOD, \$.http.fetch"
check "env call fails" 1 "$GOOD, \$.env.get"
check "an unreviewed call fails" 1 "$GOOD, \$.model.complete"
check "a lookalike name does not pass" 1 './temper-mod/register.tsx calls: $.fs.listing'
check "an empty calls line fails" 1 './temper-mod/register.tsx calls: '
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
