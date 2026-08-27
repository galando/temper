#!/usr/bin/env bash
#
# cursor-adapter.sh — run a Temper hook script under Cursor's hook contract.
#
# Usage (from hooks/cursor-hooks.json or packs/hooks/cursor.hooks.json):
#   bash "${CURSOR_PLUGIN_ROOT}"/scripts/hooks/cursor-adapter.sh <hook-script.sh>
#
# WHY THIS EXISTS. Temper's hook rules are implemented exactly once, in
# scripts/hooks/*.sh, against Claude Code's contract: Claude-shaped JSON on stdin,
# exit 2 == block, a `permissionDecision` object on stdout == ask. Cursor differs on
# both sides — different payload keys, and a JSON response on stdout instead of an
# exit code. This adapter translates in both directions so no rule is ever written
# twice. A second implementation is precisely what silently froze the old `.cursor/`
# export three majors behind (CHANGELOG v9.0.0); one implementation plus one
# translator cannot drift that way.
#
# TRANSLATION TABLE
#   Cursor event           stdin handed to the rule          exit 2 becomes
#   ---------------------  --------------------------------  ----------------------
#   beforeShellExecution   {"tool_input":{"command":...}}     {"permission":"deny"}
#   beforeMCPExecution     {"tool_input":{"command":...}}     {"permission":"deny"}
#   beforeSubmitPrompt     {"prompt":...}                     (advisory — see below)
#   afterFileEdit          {"tool_input":{"file_path":...}}   (advisory — post-event)
#   stop                   {"stop_hook_active":false}         (advisory — see below)
#
# Two Cursor events CANNOT block, by Cursor's own contract: `stop` and `afterFileEdit`
# both return void. A rule that exits 2 there is reported on stderr and appended to
# .temper/hooks.log, but the turn proceeds. That is a real capability gap, documented
# in reference/portability.md — not something this adapter can paper over.
# `beforeSubmitPrompt` can technically refuse a prompt (`{"continue": false}`), but no
# Temper rule ever should: refusing the user's prompt is not a gate, so this adapter
# always answers `{"continue": true}`.
#
# DEGRADATION CONTRACT (same spirit as every other hook here — fail OPEN):
#   - No script argument / script missing   => exit 0, permissive response
#   - python3 absent / stdin unparseable    => exit 0, permissive response
#   - Rule exits 0                          => exit 0, permissive response
#   - Rule exits 2 on a blocking event      => exit 0, deny response on stdout
#   - Any internal error                    => exit 0, permissive response
# The process always exits 0: Cursor treats a non-zero hook exit as a broken hook,
# so the verdict travels on stdout, never in the exit code.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

_permissive() { # _permissive <event> — the "nothing to say" response for this event
  case "$1" in
    beforeShellExecution|beforeMCPExecution) printf '%s\n' '{"permission": "allow"}' ;;
    beforeSubmitPrompt)                      printf '%s\n' '{"continue": true}' ;;
    *)                                       : ;;   # stop / afterFileEdit return void
  esac
  exit 0
}

_main() {
  local script="${1:-}"
  local raw; raw="$(cat 2>/dev/null || true)"

  command -v python3 >/dev/null 2>&1 || _permissive ""

  # One python pass: read the Cursor payload, emit three NUL-free lines —
  # event name, workspace root, and the Claude-shaped payload to hand the rule.
  local parsed
  parsed=$(printf '%s' "$raw" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
event = d.get("hook_event_name", "") or ""
roots = d.get("workspace_roots") or []
root = roots[0] if roots and isinstance(roots[0], str) else (d.get("cwd") or "")
if event in ("beforeShellExecution", "beforeMCPExecution"):
    payload = {"tool_input": {"command": d.get("command", "") or ""}}
elif event == "beforeSubmitPrompt":
    payload = {"prompt": d.get("prompt", "") or ""}
elif event == "afterFileEdit":
    payload = {"tool_input": {"file_path": d.get("file_path", "") or ""}}
else:
    payload = {"stop_hook_active": False}
print(event)
print(root)
print(json.dumps(payload))
' 2>/dev/null) || _permissive ""

  local event root payload
  event=$(printf '%s' "$parsed" | sed -n '1p')
  root=$(printf '%s' "$parsed" | sed -n '2p')
  payload=$(printf '%s' "$parsed" | sed -n '3p')
  [[ -n "$payload" ]] || _permissive "$event"

  # Resolve the rule only after the event is known, so a missing or unnamed script
  # still answers with the RIGHT permissive shape for that event rather than silence.
  local target="$HOOKS_DIR/$script"
  [[ -n "$script" && -f "$target" ]] || _permissive "$event"

  # The rules locate project state through CLAUDE_PROJECT_DIR (falling back to $PWD).
  # Cursor names the same thing workspace_roots[0]; hand it over under the name the
  # rules already read, rather than teaching seven scripts a second variable.
  [[ -n "$root" && -d "$root" ]] && export CLAUDE_PROJECT_DIR="$root"
  # Same for the plugin root: rules that need it read CLAUDE_PLUGIN_ROOT.
  [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] || [[ -z "${CURSOR_PLUGIN_ROOT:-}" ]] || \
    export CLAUDE_PLUGIN_ROOT="$CURSOR_PLUGIN_ROOT"

  local out err rc
  err="$(mktemp 2>/dev/null)" || _permissive "$event"
  out=$(printf '%s' "$payload" | bash "$target" 2>"$err"); rc=$?
  local reason; reason="$(cat "$err" 2>/dev/null || true)"
  rm -f "$err" 2>/dev/null

  # A Claude "ask" decision (confirm-override.sh) maps onto Cursor's own ask tier.
  if [[ "$rc" -eq 0 && "$out" == *'"permissionDecision"'* && "$out" == *'"ask"'* ]]; then
    case "$event" in
      beforeShellExecution|beforeMCPExecution)
        printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(json.dumps({"permission": "allow"})); sys.exit(0)
spec = d.get("hookSpecificOutput", {}) if isinstance(d, dict) else {}
print(json.dumps({
    "permission": "ask",
    "userMessage": spec.get("permissionDecisionReason", "Temper asks you to confirm this command."),
}))
' 2>/dev/null || printf '%s\n' '{"permission": "allow"}'
        exit 0
        ;;
    esac
  fi

  [[ "$rc" -eq 2 ]] || _permissive "$event"

  case "$event" in
    beforeShellExecution|beforeMCPExecution)
      REASON="$reason" python3 -c '
import json, os
msg = os.environ.get("REASON", "").strip() or "Blocked by a Temper hook rule."
print(json.dumps({"permission": "deny", "agentMessage": msg, "userMessage": msg}))
' 2>/dev/null || printf '%s\n' '{"permission": "deny", "agentMessage": "Blocked by a Temper hook rule."}'
      ;;
    *)
      # Advisory only — Cursor's stop/afterFileEdit responses are void, so the rule's
      # verdict cannot stop the turn. Say so plainly rather than pretending it blocked.
      local dir="${CLAUDE_PROJECT_DIR:-$PWD}"
      mkdir -p "$dir/.temper" 2>/dev/null || true
      printf '%s cursor-adapter advisory (%s, %s): %s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo -)" "$event" "$script" \
        "$(printf '%s' "$reason" | tr '\n' ' ')" >> "$dir/.temper/hooks.log" 2>/dev/null || true
      printf 'temper (advisory — Cursor cannot block on %s):\n%s\n' "$event" "$reason" >&2
      _permissive "$event"
      ;;
  esac
  exit 0
}

_main "$@"
exit 0
