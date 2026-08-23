#!/usr/bin/env bash
#
# run-formatter.sh — PostToolUse (Edit|Write) formatter, so drift never accumulates.
#
# Runs the project's own formatter on each file the agent edits, driven by config —
# never a guessed command:
#
#   format:
#     cmd: "npx prettier --write {file}"     # {file} is replaced with the edited path
#
# Absent key => no-op (the default). A formatter FAILURE never blocks anything —
# formatting is hygiene, not a gate; a warning goes to stderr and the edit stands.
#
# DEGRADATION CONTRACT:
#   - Always exit 0. There is no fail-closed path in this hook — the only effects are
#     an in-place format or a stderr warning.
set -uo pipefail

_main() {
  command -v python3 >/dev/null 2>&1 || return 0

  local dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  local temper_cli
  temper_cli="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/temper"
  [[ -x "$temper_cli" ]] || return 0

  local fmt
  fmt=$(TEMPER_CONFIG="$dir/.claude/temper.config" "$temper_cli" config get format.cmd "" 2>/dev/null) || return 0
  [[ -n "$fmt" ]] || return 0

  local target=""
  target=$(python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('file_path', '') or '')
except Exception:
    print('')
" 2>/dev/null) || return 0
  [[ -n "$target" && -f "$target" ]] || return 0

  local cmd="${fmt//\{file\}/$target}"
  if ! bash -c "$cmd" >/dev/null 2>&1; then
    echo "WARN: format.cmd failed on '$target' (ran: $cmd) — edit stands, formatting skipped." >&2
  fi
  return 0
}

_main
exit 0
