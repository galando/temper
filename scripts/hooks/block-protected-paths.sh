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

  # Proper glob matching (not substring): the value arrives on stdin, patterns are
  # \x1f-joined in $patterns. A pattern like **/gen/** must match the `gen` path
  # SEGMENT, never the substring `gen` inside `oxygen` or `agent`; **/migrations/*.sql
  # must honor the interior `*`. Translation: **/ -> optional path prefix, /** ->
  # optional path suffix, * -> within a segment. All matching runs in python (argv +
  # stdin only — no value is interpolated into source); the hook prints the matched
  # pattern to stderr and this function maps a match to exit 2.
  local matched
  matched=$(TEMPER_PROTECT_PATTERNS="$patterns" python3 -c '
import json, os, re, sys
try:
    target = json.load(sys.stdin).get("tool_input", {}).get("file_path", "") or ""
except Exception:
    sys.exit(0)
if not target:
    sys.exit(0)
target = target.lstrip("./")
def glob_to_re(pat):
    out, i, n = [], 0, len(pat)
    while i < n:
        if pat[i:i+3] == "**/":
            out.append("(?:.*/)?"); i += 3
        elif pat[i:i+3] == "/**":
            out.append("(?:/.*)?"); i += 3
        elif pat[i:i+2] == "**":
            out.append(".*"); i += 2
        elif pat[i] == "*":
            out.append("[^/]*"); i += 1
        elif pat[i] == "?":
            out.append("[^/]"); i += 1
        else:
            out.append(re.escape(pat[i])); i += 1
    return re.compile("^" + "".join(out) + "$")
for pat in os.environ.get("TEMPER_PROTECT_PATTERNS", "").split("\x1f"):
    if pat and glob_to_re(pat).match(target):
        print(pat); break
' 2>/dev/null) || return 0

  if [[ -n "$matched" ]]; then
    echo "BLOCK: this edit matches protected path pattern '$matched' (protect.paths in .claude/temper.config)." >&2
    echo "This path is frozen at edit time. If the change is intended, a human removes or narrows the pattern — that edit is the approval." >&2
    return 2
  fi
  return 0
}

_main
