#!/usr/bin/env bash
#
# block-uncommitted-gate.sh — PreToolUse in-agent commit gate.
#
# Fires on the Bash matcher. Only acts when the command being run is a `git commit`;
# every other Bash call passes straight through. When it IS a git commit, this defers
# to `temper gate commit` — the same deterministic verdict the native pre-commit hook
# (installed by scripts/guards/install.sh) enforces — so an agent-driven commit is
# blocked with a clear reason at the moment it's attempted, not just at the git layer.
# This does NOT replace the native git hook (a raw `git commit` outside the agent
# never reaches this PreToolUse event) — the two are complementary, per the guardrails
# pack's two-layer design (packs/guardrails/rules.md).
#
# DEGRADATION CONTRACT:
#   - Not a `git commit` command      => exit 0 (no-op; only commits are inspected)
#   - temper CLI or .temper/ absent   => exit 0 (fail-open; nothing to gate)
#   - repository inside the plugin folder => exit 0 (the CLI refuses to run there)
#   - the CLI refuses the project's .temper folder (exit 3: it or an entry in it is a
#     symlink)                        => exit 0 with a one-line warning (FAIL-OPEN)
#   - `temper gate commit` FAILs      => exit 2 (BLOCK)
#   - Internal error                  => exit 0 (FAIL-OPEN)
set -uo pipefail

# cd prints the folder it changes to when CDPATH is set, which would spoil the folders worked
# out below with cd and pwd.
unset CDPATH

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

  # The CLI of the plugin this script belongs to: the plugin folder is this script's
  # folder (its own file with every symlink followed, as the CLI finds itself) with the
  # literal suffix /scripts/guards removed. Never a copy at the project's root, and never
  # one named by an environment variable.
  local self="${BASH_SOURCE[0]}" hops=0 link_dir here root temper_bin
  while [[ -L "$self" && $hops -lt 40 ]]; do
    link_dir="$(cd -P "$(dirname "$self")" 2>/dev/null && pwd)" || return 0
    self="$(readlink "$self")" || return 0
    [[ "$self" == /* ]] || self="$link_dir/$self"
    hops=$((hops + 1))
  done
  here="$(cd "$(dirname "$self")" 2>/dev/null && pwd)" || return 0
  root="${here%/scripts/guards}"
  [[ "$root" != "$here" ]] || return 0
  temper_bin="$root/scripts/temper"
  [[ -x "$temper_bin" ]] || return 0
  # A repository inside the plugin's own folder (a second checkout or worktree placed in
  # it) is part of the plugin: the CLI refuses to run there, so there is nothing to gate.
  # Each folder above the repository is compared with the plugin folder by identity
  # (device and inode), so letter case and symlinks cannot hide it.
  local repo_real up
  repo_real="$(cd "$repo_root" 2>/dev/null && pwd -P)" || return 0
  if ! [[ "$repo_real" -ef "$root" ]]; then
    up="$repo_real"
    while [[ "$up" == /?* ]]; do
      up="${up%/*}"
      [[ "${up:-/}" -ef "$root" ]] && return 0
    done
  fi

  local rc
  ( cd "$repo_root" && "$temper_bin" gate commit )
  rc=$?
  [[ $rc -eq 0 ]] && return 0
  if [[ $rc -eq 3 ]]; then
    echo "Temper: the commit gate was skipped because the temper CLI refused this project's .temper folder (its reason is above)." >&2
    return 0
  fi
  echo "BLOCK: temper gate commit FAILed. To see which requirement is unmet, run: $(printf '%q' "$temper_bin") report" >&2
  return 2
}

_main "$@"
