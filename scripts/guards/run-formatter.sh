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
# Only a file inside the project folder is formatted. A file outside it, or a file of
# this plugin's own folder (unless the project IS that folder, as when developing
# Temper), is left as it is.
#
# DEGRADATION CONTRACT:
#   - Always exit 0. There is no fail-closed path in this hook — the only effects are
#     an in-place format or a stderr warning.
set -uo pipefail

_main() {
  command -v python3 >/dev/null 2>&1 || return 0

  local dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  # The plugin folder is this script's folder with the literal suffix /scripts/guards
  # removed; the CLI is scripts/temper inside it.
  local here root temper_cli
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || return 0
  root="${here%/scripts/guards}"
  temper_cli="$root/scripts/temper"
  [[ -x "$temper_cli" ]] || return 0

  local fmt
  fmt=$(TEMPER_CONFIG="$dir/.claude/temper.config" "$temper_cli" config get format.cmd "" 2>/dev/null) || return 0
  [[ -n "$fmt" ]] || return 0

  # The edited file, resolved. Printed only when it is a file inside the project folder
  # and not a file of this plugin's folder (the project being that folder excepted).
  local target=""
  target=$(python3 -c "
import json, os, sys
project, plugin = sys.argv[1], sys.argv[2]
try:
    t = json.load(sys.stdin).get('tool_input', {}).get('file_path', '') or ''
except Exception:
    sys.exit(0)
if not t:
    sys.exit(0)
if not os.path.isabs(t):
    t = os.path.join(project, t)
t, proj, plug = os.path.realpath(t), os.path.realpath(project), os.path.realpath(plugin)
def inside(p, folder):
    return p.startswith(folder.rstrip(os.sep) + os.sep)
if not os.path.isfile(t) or not inside(t, proj):
    sys.exit(0)
if proj != plug and (inside(t, plug) or inside(proj, plug)):
    sys.exit(0)
print(t)
" "$dir" "$root" 2>/dev/null) || return 0
  [[ -n "$target" && -f "$target" ]] || return 0

  local cmd="${fmt//\{file\}/$target}"
  if ! bash -c "$cmd" >/dev/null 2>&1; then
    echo "WARN: format.cmd failed on '$target' (ran: $cmd) — edit stands, formatting skipped." >&2
  fi
  return 0
}

_main
exit 0
