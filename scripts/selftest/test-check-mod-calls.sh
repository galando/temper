#!/usr/bin/env bash
# Tests for scripts/check-mod-calls.sh using canned `calls:` lines (no claude needed).
set -uo pipefail
# The plugin folder: this test sits in scripts/selftest, so strip that literal suffix.
unset CDPATH
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts/selftest}"
[[ "$ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
PASS=0; FAIL=0
check() { # check <name> <expected exit> <calls line>
  local name="$1" want="$2" line="$3" out rc
  out="$(CHECK_MOD_CALLS_LINE="$line" bash "$ROOT/scripts/check-mod-calls.sh" 2>&1)"; rc=$?
  if [[ $rc -eq $want ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $name (exit $rc, wanted $want): $out"; fi
}
# Every reviewed call, as the validator prints the mod's line (the list is exact, so a line must name them all).
GOOD='./module calls: $.agent.list (via isReviewer), $.command.run (via goOn), $.config.list (via setRow), $.config.set (via setRow), $.fs.read (via makeIo), $.fs.stat (via rootOf), $.session.version (via makeIo), $.state.get (via readUi), $.state.set (via makeIo), $.store.delete (via keepText), $.store.get (via firstRunAsk, makeIo), $.store.set (via keepText), $.ui.ask (via askMode), $.ui.close (via closePane), $.ui.invalidate (via switchMode), $.ui.open (via openPane), $.ui.resolve, $.ui.toast (via showToast)'
check "reviewed calls pass, via lists included" 0 "$GOOD"
check "a reviewed call the mod no longer makes fails (the list is exact)" 1 "${GOOD/\$.command.run (via goOn), /}"
check "fs.list is no longer reviewed (the mod reads only view.json)" 1 "$GOOD, \$.fs.list (via makeIo)"
check "clock.sleep is no longer reviewed (view.json is replaced whole)" 1 "$GOOD, \$.clock.sleep (via makeIo)"
check "prompt.fill is no longer reviewed (the bar decides nothing and drafts nothing)" 1 "$GOOD, \$.prompt.fill (via fillDraft)"
check "prompt.submit is no longer reviewed" 1 "$GOOD, \$.prompt.submit (via press)"
check "ui.focus is no longer reviewed (no reason field)" 1 "$GOOD, \$.ui.focus (via focusReason)"
check "a lookalike of command.run does not pass" 1 "$GOOD, \$.command.register"
check "process call fails" 1 "$GOOD, \$.process.spawn (via run)"
check "http call fails" 1 "$GOOD, \$.http.fetch"
check "env call fails" 1 "$GOOD, \$.env.get"
check "an unreviewed call fails" 1 "$GOOD, \$.model.complete"
check "a lookalike name does not pass" 1 './module calls: $.fs.listing'
check "an empty calls line fails" 1 './module calls: '
check "a line the validator cut short fails (a call could be hidden)" 1 "$GOOD, \$.ui.toast (via announce, askMode, switchEnforce… [+5 chars]"
check "fs.write is no longer reviewed (the mod writes no file)" 1 "$GOOD, \$.fs.write (via makeIo)"
check "a call named twice passes" 0 "$GOOD, \$.store.delete (via keepText)"
check "a forbidden call on a second calls line fails" 1 "$GOOD
./other calls: \$.fs.list (via a), \$.process.spawn (via run)"
check "two clean calls lines pass" 0 "$GOOD
./other calls: \$.fs.read (via a)"
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
