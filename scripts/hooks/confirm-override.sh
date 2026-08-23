#!/usr/bin/env bash
#
# confirm-override.sh — PreToolUse (Bash) ask-gate for `temper override`.
#
# `temper override <stage>` clears a FAIL gate for the commit fence — a decision the
# rules reserve for a human at an AskUserQuestion gate. Nothing deterministic used to
# stand between an agent and running it on its own; this hook adds Claude Code's
# "ask" permission tier: when the Bash command contains a temper override invocation,
# it emits permissionDecision "ask", so the person at the terminal explicitly
# approves that one command before it runs. Combined with cmd_override recording the
# git identity, an override now carries both a human click and a name.
#
# This is an ASK, not a BLOCK: the orchestrator legitimately runs `temper override`
# after the human picks "Override and continue" at a gate — the permission prompt is
# a second, deterministic confirmation of exactly that, and costs one click.
# (In --dangerously-skip-permissions runs the prompt auto-approves; sandboxed eval
# harnesses stay unaffected.)
#
# DEGRADATION CONTRACT:
#   - Bash command contains `temper override`  => emit permissionDecision "ask", exit 0
#   - Anything else / no python3 / bad stdin   => exit 0 silently (fail-open)
set -uo pipefail

_main() {
  command -v python3 >/dev/null 2>&1 || return 0

  local cmd=""
  cmd=$(python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', '') or '')
except Exception:
    print('')
" 2>/dev/null) || return 0

  case "$cmd" in
    *temper\ override*|*temper' override'*) ;;
    *) return 0 ;;
  esac

  printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "temper override clears a FAIL gate — a human approves this, not the agent. Approve only if YOU chose Override at the gate."}}'
  return 0
}

_main
