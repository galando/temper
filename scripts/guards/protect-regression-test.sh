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
#
# The edited file is the recorded test when both name the same file (device and inode, so
# letter case, symlinks and hard links cannot hide it); a file not made yet is compared by
# its full path with every symlink followed.
set -uo pipefail

# cd prints the folder it changes to when CDPATH is set, which would spoil the folder worked
# out below with cd and pwd.
unset CDPATH

_cli_path() { # prints the temper CLI of the plugin this script belongs to, %q-quoted: this
              # script's own file (every symlink followed, as the CLI finds itself), its folder
              # with the literal suffix /scripts/guards removed, then scripts/temper. Prints the
              # bare name temper when the script is not laid out that way.
  local self="${BASH_SOURCE[0]}" hops=0 link_dir here root
  while [[ -L "$self" && $hops -lt 40 ]]; do
    link_dir="$(cd -P "$(dirname "$self")" 2>/dev/null && pwd)" || { echo temper; return 0; }
    self="$(readlink "$self")" || { echo temper; return 0; }
    [[ "$self" == /* ]] || self="$link_dir/$self"
    hops=$((hops + 1))
  done
  here="$(cd "$(dirname "$self")" 2>/dev/null && pwd)" || { echo temper; return 0; }
  root="${here%/scripts/guards}"
  if [[ "$root" == "$here" ]]; then echo temper; return 0; fi
  printf '%q\n' "$root/scripts/temper"
}

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
def full(p):
    if not os.path.isabs(p):
        p = os.path.join(project_dir, p)
    return p
t, g = full(target), full(guarded)
try:
    same = os.path.samefile(t, g)
except OSError:
    same = os.path.normcase(os.path.realpath(t)) == os.path.normcase(os.path.realpath(g))
if same:
    print(guarded)
" "$state" "$dir" 2>/dev/null) || return 0

  if [[ -n "$verdict" ]]; then
    echo "BLOCK: '$verdict' is this fix run's recorded regression test — the proof the bug exists." >&2
    echo "Fix the code, not the test. If the test itself is wrong, that is a human's call:" >&2
    echo "  $(_cli_path) state set regression_test \"\"   # lifts the shield, deliberately" >&2
    return 2
  fi
  return 0
}

_main
