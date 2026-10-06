#!/usr/bin/env bash
# Tests for scripts/check-mod-calls.sh using canned `calls:` lines (no claude needed).
set -uo pipefail
# The plugin folder: this test sits in scripts/tests, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts/tests}"
[[ "$ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
PASS=0; FAIL=0
check() { # check <name> <expected exit> <calls line>
  local name="$1" want="$2" line="$3" out rc
  out="$(CHECK_MOD_CALLS_LINE="$line" bash "$ROOT/scripts/check-mod-calls.sh" 2>&1)"; rc=$?
  if [[ $rc -eq $want ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $name (exit $rc, wanted $want): $out"; fi
}
GOOD='./module calls: $.fs.list (via makeIo), $.store.get (via firstRunAsk, makeIo), $.ui.ask (via askDrift), $.ui.resolve'
check "reviewed calls pass, via lists included" 0 "$GOOD"
check "command.run (the orchestrator Resume) and prompt.fill (Discuss) are reviewed" 0 "$GOOD, \$.command.run (via resumeRun), \$.prompt.fill (via fillDraft)"
check "a lookalike of command.run does not pass" 1 "$GOOD, \$.command.register"
check "process call fails" 1 "$GOOD, \$.process.spawn (via run)"
check "http call fails" 1 "$GOOD, \$.http.fetch"
check "env call fails" 1 "$GOOD, \$.env.get"
check "an unreviewed call fails" 1 "$GOOD, \$.model.complete"
check "a lookalike name does not pass" 1 './module calls: $.fs.listing'
check "an empty calls line fails" 1 './module calls: '
check "a line the validator cut short fails (a call could be hidden)" 1 "$GOOD, \$.ui.toast (via announce, askMode, switchEnforce… [+5 chars]"
check "fs.write is no longer reviewed (the mod writes no file)" 1 "$GOOD, \$.fs.write (via makeIo)"
check "store.delete (drops the oldest kept folder) is reviewed" 0 "$GOOD, \$.store.delete (via keepText)"
check "a forbidden call on a second calls line fails" 1 "$GOOD
./other calls: \$.fs.list (via a), \$.process.spawn (via run)"
check "two clean calls lines pass" 0 "$GOOD
./other calls: \$.fs.read (via a)"
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
