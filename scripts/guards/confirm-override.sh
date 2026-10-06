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

  # Match a `temper override` invocation robustly: tokenize the command (shlex, so a
  # quoted path unquotes) and look for a token whose basename is `temper` immediately
  # followed by the `override` subcommand. A naive `*temper override*` glob is bypassed
  # by a quoted path (`"…/temper" override`), a tab, or doubled spaces — all of which
  # reach the same command. Decided in python; the value crosses as stdin only.
  # (python3 -c, NOT a heredoc: the hook's JSON arrives on stdin, and a `python3 <<PY`
  # heredoc would own stdin and discard it — see test-temper.sh's stop_hook_active note.)
  local decision
  decision=$(python3 -c '
import json, os, shlex, sys
try:
    cmd = json.load(sys.stdin).get("tool_input", {}).get("command", "") or ""
except Exception:
    sys.exit(0)
try:
    toks = shlex.split(cmd)
except ValueError:
    toks = cmd.split()
for i, t in enumerate(toks[:-1]):
    if os.path.basename(t) == "temper" and toks[i + 1] == "override":
        print("ask"); break
' 2>/dev/null) || return 0

  [[ "$decision" == "ask" ]] || return 0

  printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "temper override clears a FAIL gate — a human approves this, not the agent. Approve only if YOU chose Override at the gate."}}'
  return 0
}

_main
