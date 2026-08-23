#!/usr/bin/env bash
#
# block-protected-paths.sh — PreToolUse (Edit|Write) protected-path guardrail.
#
# The build-time counterpart of the commit gate's park-on-touch: paths listed in
# `protect: paths:` in .claude/temper.config (generated classes, a frozen package,
# migrations) are blocked at EDIT time, for every mode — not discovered at the commit
# gate after the tokens were spent, and not only in autonomous runs. Patterns use the
# same **/segment/** shape as autonomy.park-on-touch.
#
#   protect:
#     paths: ["**/src/gen/**", "**/v1/**"]
#
# Default is an empty list => no-op. The config is read via `temper config get`, the
# same parser every gate uses.
#
# DEGRADATION CONTRACT:
#   - Edited file matches a protect.paths pattern => exit 2 (BLOCK — the one
#     fail-closed path); the message names the pattern and the config route.
#   - Empty/absent list, other files, no python3, unparseable stdin, missing CLI
#     => exit 0 (fail-open)
set -uo pipefail

_main() {
  command -v python3 >/dev/null 2>&1 || return 0

  local dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  local temper_cli
  temper_cli="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/temper"
  [[ -x "$temper_cli" ]] || return 0

  local patterns
  patterns=$(TEMPER_CONFIG="$dir/.claude/temper.config" "$temper_cli" config get protect.paths "" 2>/dev/null) || return 0
  [[ -n "$patterns" ]] || return 0

  local target=""
  target=$(python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('file_path', '') or '')
except Exception:
    print('')
" 2>/dev/null) || return 0
  [[ -n "$target" ]] || return 0

  # Same core-segment matching as gate_commit's _glob_touch_match.
  local -a pats=()
  IFS=$'\x1f' read -r -a pats <<< "$patterns"
  local p core
  for p in "${pats[@]}"; do
    [[ -z "$p" ]] && continue
    core="${p#\*\*/}"; core="${core%/\*\*}"
    case "$target" in
      *"$core"*)
        echo "BLOCK: '$target' matches protected path pattern '$p' (protect.paths in .claude/temper.config)." >&2
        echo "This path is frozen at edit time. If the change is intended, a human removes or narrows the pattern — that edit is the approval." >&2
        return 2
        ;;
    esac
  done
  return 0
}

_main
