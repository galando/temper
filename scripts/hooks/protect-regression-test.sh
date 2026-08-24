#!/usr/bin/env bash
#
# protect-regression-test.sh — PreToolUse (Edit|Write) shield for the fix loop.
#
# During a /temper:fix run, the regression test written at RED is the proof the bug
# exists — and the proof the fix works. An agent fixing code must not be able to weaken
# the check on that code, so once the fix flow records the test's path
# (`temper state set regression_test <path>`, done right after RED is confirmed), this
# hook blocks any Edit/Write that targets that file until the run's state is cleared.
# Fix the code, not the test.
#
# A human can lift the shield deliberately (the test itself was wrong):
#   temper state set regression_test ""
# That decision is a state edit a person makes, not something the fixing agent should
# do on its own — the block message says exactly this so the route is always visible.
#
# DEGRADATION CONTRACT:
#   - Edit targets the recorded regression test during a fix run => exit 2 (BLOCK —
#     the one fail-closed path)
#   - No active fix run / no recorded test / different file      => exit 0
#   - python3 absent / unparseable input / any internal error    => exit 0 (fail-open)
set -uo pipefail

_main() {
  command -v python3 >/dev/null 2>&1 || return 0

  local dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  local state="$dir/.temper/build-state.json"
  [[ -f "$state" ]] || return 0

  local verdict=""
  verdict=$(python3 -c "
import json, os, sys
state_path, project_dir = sys.argv[1], sys.argv[2]
try:
    state = json.load(open(state_path))
except Exception:
    sys.exit(0)
if state.get('command') != 'fix':
    sys.exit(0)
guarded = state.get('regression_test') or ''
if not guarded:
    sys.exit(0)
try:
    target = json.load(sys.stdin).get('tool_input', {}).get('file_path', '') or ''
except Exception:
    sys.exit(0)
if not target:
    sys.exit(0)
def norm(p):
    if not os.path.isabs(p):
        p = os.path.join(project_dir, p)
    return os.path.realpath(p)
if norm(target) == norm(guarded):
    print(guarded)
" "$state" "$dir" 2>/dev/null) || return 0

  if [[ -n "$verdict" ]]; then
    echo "BLOCK: '$verdict' is this fix run's recorded regression test — the proof the bug exists." >&2
    echo "Fix the code, not the test. If the test itself is wrong, that is a human's call:" >&2
    echo "  temper state set regression_test \"\"   # lifts the shield, deliberately" >&2
    return 2
  fi
  return 0
}

_main
