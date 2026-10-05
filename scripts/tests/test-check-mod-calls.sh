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
check "command.run (the orchestrator Resume) and prompt.fill (Discuss) are reviewed" 0 "$GOOD, \$.command.run (via resumeRun), \$.prompt.fill (via fillDraft)"
check "a lookalike of command.run does not pass" 1 "$GOOD, \$.command.register"
check "process call fails" 1 "$GOOD, \$.process.spawn (via run)"
check "http call fails" 1 "$GOOD, \$.http.fetch"
check "env call fails" 1 "$GOOD, \$.env.get"
check "an unreviewed call fails" 1 "$GOOD, \$.model.complete"
check "a lookalike name does not pass" 1 './temper-mod/register.tsx calls: $.fs.listing'
check "an empty calls line fails" 1 './temper-mod/register.tsx calls: '
# A surface module (a file named *-client.tsx) may make no engine call at all.
client() { # client <name> <expected exit> <file content>
  local name="$1" want="$2" body="$3" dir out rc
  dir="$(mktemp -d)"; printf '%s\n' "$body" > "$dir/game-client.tsx"
  out="$(CHECK_MOD_CALLS_LINE="$GOOD" CHECK_MOD_CLIENT_DIR="$dir" bash "$ROOT/scripts/check-mod-calls.sh" 2>&1)"; rc=$?
  rm -f "$dir/game-client.tsx"; rmdir "$dir"
  if [[ $rc -eq $want ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $name (exit $rc, wanted $want): $out"; fi
}
client "a surface module without engine calls passes" 0 'const x = surface.state; const y = `${x}`'
client "a surface module with a store call fails" 1 'await $.store.get("a")'
client "a surface module with a post call on the engine fails" 1 'const a = 1; $.ui.toast("x")'
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
