#!/usr/bin/env bash
#
# run-formatter.sh — PostToolUse (Edit|Write) formatter, so drift never accumulates.
#
# Runs the project's own formatter on each file the agent edits, driven by config —
# never a guessed command:
#
#   format:
#     cmd: "npx --no-install prettier --write {file}"     # {file} stands for the edited path
#
# Absent key => no-op (the default). A formatter FAILURE never blocks anything —
# formatting is hygiene, not a gate; a warning goes to stderr and the edit stands.
#
# The edited path is never pasted into the command as text. {file} (also when written
# "{file}" or '{file}') becomes "$1", and the path is handed to the command as that
# argument, so a file name that holds shell syntax is only ever a name.
#
# Only a file inside the project folder is formatted. A file outside it, or a file of
# this plugin's own folder, is left as it is, whatever the project is: when the project
# IS the plugin folder (developing Temper), nothing is formatted.
#
# DEGRADATION CONTRACT:
#   - Always exit 0. There is no fail-closed path in this hook — the only effects are
#     an in-place format or a stderr warning.
set -uo pipefail
# An exported CDPATH makes `cd` print the folder it enters, which would double the folder
# worked out below with "$(cd ... && pwd)". It is never used here.
unset CDPATH

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
  # and not a file of this plugin's folder. Inside is decided by identity, not by text:
  # each ancestor of the resolved file is compared with the folder by device and inode
  # (os.path.samefile), so another case on a file system that does not tell case apart,
  # or a second mount of the same folder, is still seen.
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
t = os.path.realpath(t)
def same(a, b):
    try:
        return os.path.samefile(a, b)
    except OSError:
        return False
def under(p, folder):
    while True:
        if same(p, folder):
            return True
        parent = os.path.dirname(p)
        if parent == p:
            return False
        p = parent
if not os.path.isfile(t) or not under(os.path.dirname(t), project):
    sys.exit(0)
if under(t, plugin):
    sys.exit(0)
print(t)
" "$dir" "$root" 2>/dev/null) || return 0
  [[ -n "$target" && -f "$target" ]] || return 0

  # {file}, bare or inside one pair of double or single quotes, becomes "$1"; the path
  # travels as that argument and is never parsed as shell text.
  local arg='"$1"' cmd="$fmt"
  cmd="${cmd//\"\{file\}\"/$arg}"
  cmd="${cmd//\'\{file\}\'/$arg}"
  cmd="${cmd//\{file\}/$arg}"
  if ! bash -c "$cmd" run-formatter "$target" >/dev/null 2>&1; then
    echo "WARN: format.cmd failed on '$target' (format.cmd: $fmt). The edit stands; formatting was skipped." >&2
  fi
  return 0
}

_main
exit 0
