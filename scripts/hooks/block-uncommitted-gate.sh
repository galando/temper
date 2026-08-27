#!/usr/bin/env bash
#
# block-uncommitted-gate.sh — PreToolUse in-agent commit gate.
#
# Fires on the Bash matcher. Only acts when the command being run is a `git commit`;
# every other Bash call passes straight through. When it IS a git commit, this defers
# to `temper gate commit` — the same deterministic verdict the native pre-commit hook
# (installed by scripts/hooks/install.sh) enforces — so an agent-driven commit is
# blocked with a clear reason at the moment it's attempted, not just at the git layer.
# This does NOT replace the native git hook (a raw `git commit` outside the agent
# never reaches this PreToolUse event) — the two are complementary, per the hooks
# pack's two-layer design (packs/hooks/rules.md).
#
# DEGRADATION CONTRACT:
#   - Not a `git commit` command      => exit 0 (no-op; only commits are inspected)
#   - temper CLI or .temper/ absent   => exit 0 (fail-open; nothing to gate)
#   - `temper gate commit` FAILs      => exit 2 (BLOCK)
#   - Internal error                  => exit 0 (FAIL-OPEN)
set -uo pipefail

_main() {
  local cmd=""
  if command -v python3 >/dev/null 2>&1; then
    cmd=$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null)
  fi
  [[ -z "$cmd" ]] && return 0
  echo "$cmd" | grep -qE '(^|[;&|]) *git +commit' || return 0

  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [[ -d "$repo_root/.temper" ]] || return 0

  local temper_bin="$repo_root/scripts/temper"
  # A project consuming Temper as an installed plugin (not the Temper repo itself)
  # won't have scripts/temper at its own root — fall back to the plugin's own copy.
  # Own location first: this file is $PLUGIN_ROOT/scripts/hooks/, so ../temper is the
  # CLI, and that resolution holds under every agent — Claude Code, Cursor, or none.
  [[ -x "$temper_bin" ]] || temper_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/temper"
  [[ -x "$temper_bin" ]] || temper_bin="${CLAUDE_PLUGIN_ROOT:-${CURSOR_PLUGIN_ROOT:-__none__}}/scripts/temper"
  [[ -x "$temper_bin" ]] || return 0

  if ( cd "$repo_root" && "$temper_bin" gate commit ); then
    return 0
  fi
  echo "BLOCK: temper gate commit FAILed — run 'temper report' to see which requirement is unmet." >&2
  return 2
}

_main "$@"
