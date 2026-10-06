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
# project like any other (developing Temper on its own repository), so its .temper folder
# is written. A .temper folder or a marker file that is a symlink is skipped too, because
# writing through it would land outside the project's .temper folder.
#
# DEGRADATION CONTRACT:
#   - Prompt is not a marked stage command  => exit 0 (no-op)
#   - python3 absent / unparseable input    => exit 0 (fail-open)
#   - Any internal error                    => exit 0 (fail-open; never blocks a prompt)
set -uo pipefail

_project_dir() { # prints the resolved project folder; fails when it is a subfolder of this
                 # plugin's folder (this script's folder with the literal suffix
                 # /scripts/guards removed)
  local proj here root
  proj="$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && pwd -P)" || return 1
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || return 1
  root="${here%/scripts/guards}"
  if [[ "$root" != "$here" && "$proj" != "$root" && "${proj#"$root"/}" != "$proj" ]]; then
    return 1
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
