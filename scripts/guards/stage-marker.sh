#!/usr/bin/env bash
#
# stage-marker.sh — UserPromptSubmit half of the standalone-stage gate guarantee.
#
# When the submitted prompt invokes a standalone stage command (/temper:intent, :plan,
# :design, :build, :review, :check), record which gate that session now owes in
# .temper/pending-stage.json. The Stop half (verify-stage-gate.sh) refuses to let the
# session end until .temper/gates.json carries a verdict for that stage — any verdict,
# PASS or FAIL; what's enforced is that `temper gate <stage>` actually ran, not that it
# passed. Together the pair closes the wiring gap measured at v8 (the model skipped the CLI
# in 2 of 3 live runs — see docs/decisions/0005-deterministic-stage-gate-enforcement.md).
#
# /temper (unified) is deliberately NOT marked: its orchestrator runs each gate at the
# stage boundary, and a session legitimately ends mid-pipeline at any human gate.
# /temper:fix is not marked either — its RCA phase can legitimately end a session
# before any build evidence exists.
#
# The marker is a fixed name in the project's .temper folder: the hook changes into the
# project folder first. A project folder that lies inside this plugin's own folder is
# skipped (exit 0): the hook never writes inside the plugin. The plugin folder itself is a
# project only when it is a git work tree whose top level is that folder (developing Temper
# on its own repository), so an installed copy is skipped too. Inside or equal is decided
# by identity (device and inode), not by comparing path text. A .temper folder or a marker
# file that is a symlink is skipped too, because writing through it would land outside the
# project's .temper folder, and so is a .temper folder that holds a symlink anywhere.
#
# DEGRADATION CONTRACT:
#   - Prompt is not a marked stage command  => exit 0 (no-op)
#   - python3 absent / unparseable input    => exit 0 (fail-open)
#   - Any internal error                    => exit 0 (fail-open; never blocks a prompt)
set -uo pipefail
# An exported CDPATH makes `cd` print the folder it enters, which would double every folder
# worked out below with "$(cd ... && pwd)". It is never used here.
unset CDPATH

# This script's folder, resolved, and the plugin folder: that folder with the literal suffix
# /scripts/guards removed. Worked out once, before the hook changes into the project folder.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || HERE=""
ROOT="${HERE%/scripts/guards}"

_git_toplevel_is() { # _git_toplevel_is <folder> -> 0 when <folder> is a git work tree whose top
                      # level is <folder> itself (every GIT_* variable dropped first)
  local top
  top="$(
    while IFS= read -r v; do unset "$v"; done < <(compgen -e | grep '^GIT_')
    git -C "$1" rev-parse --show-toplevel 2>/dev/null
  )" || return 1
  [[ -n "$top" && "$top" -ef "$1" ]]
}

_under_folder() { # _under_folder <path> <folder> -> 0 when <path> is <folder> or lies inside it,
                  # decided by identity: each ancestor of the resolved path is compared with
                  # <folder> by device and inode ([[ -ef ]]), never by text, so another case on
                  # a file system that does not tell case apart, or a second mount, is seen
  local d
  d="$(cd -P "$1" 2>/dev/null && pwd)" || return 1
  while [[ -n "$d" ]]; do
    [[ "$d" -ef "$2" ]] && return 0
    [[ "$d" != "/" ]] || return 1
    d="${d%/*}"
    [[ -n "$d" ]] || d="/"
  done
  return 1
}

_project_dir() { # prints the resolved project folder; fails when it lies inside this plugin's
                 # folder, or is the plugin folder and that folder is not its own git
                 # repository (an installed copy)
  local proj
  [[ -n "$HERE" ]] || return 1
  proj="$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && pwd -P)" || return 1
  if [[ -n "$ROOT" && "$ROOT" != "$HERE" ]]; then
    if [[ "$proj" -ef "$ROOT" ]]; then
      _git_toplevel_is "$ROOT" || return 1
    elif _under_folder "$proj" "$ROOT"; then
      return 1
    fi
  fi
  printf '%s\n' "$proj"
}

_main() {
  command -v python3 >/dev/null 2>&1 || return 0

  local prompt=""
  prompt=$(python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('prompt', ''))
except Exception:
    print('')
" 2>/dev/null) || return 0

  # Match only at the start of the prompt: a *mention* of a command mid-sentence is
  # not an invocation.
  local stage=""
  case "$prompt" in
    /temper:intent*) stage="intent" ;;   # intent gained its own gate in v9 (fail-fast artifact)
    /temper:plan*)   stage="plan" ;;
    /temper:design*) stage="design" ;;   # design gained a real gate in v9 (Areas of Concern)
    /temper:build*)  stage="build" ;;
    /temper:review*) stage="review" ;;
    /temper:check*)  stage="check" ;;
    *) return 0 ;;
  esac

  local proj; proj="$(_project_dir)" || return 0
  cd "$proj" 2>/dev/null || return 0
  [[ ! -L .temper ]] || return 0
  # A .temper folder that holds a symlink anywhere is one the CLI refuses (exit 3), so the
  # gate this marker would ask for could never run: no debt is recorded there.
  [[ -z "$(find -P .temper -type l -print -quit 2>/dev/null)" ]] || return 0
  mkdir -p .temper 2>/dev/null || return 0
  [[ ! -L .temper/pending-stage.json ]] || return 0
  # "since" scopes the debt in time: verify-stage-gate.sh accepts only a verdict whose
  # ts is >= this moment, so a verdict left in gates.json by a PREVIOUS run cannot
  # satisfy THIS session's guarantee. Same format as scripts/temper's _now.
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || now=""
  printf '{"stage": "%s", "blocks": 0, "since": "%s"}\n' "$stage" "$now" \
    > .temper/pending-stage.json 2>/dev/null || true
  return 0
}

_main
exit 0
