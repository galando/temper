#!/usr/bin/env bash
#
# production-gate.sh — EXAMPLE approval gate (copy into your project; not wired into
# any temper pack by default).
#
# Temper's own fence ends at `git commit` — it never pushes, merges, or deploys. Past
# that fence, the same hook mechanism that blocks a red-gate commit can hold a release
# until a NAMED human authorization exists. This is the deploy-stage counterpart to the
# build-stage guardrails in scripts/hooks/: a guardrail allows or blocks with no human
# involved; an approval gate asks — and "asks" deterministically, by refusing until the
# approval artifact is present.
#
# Wire it as a PreToolUse (Bash) hook in the project's .claude/settings.json — or, for
# a gate individual engineers must not be able to switch off, in managed settings
# (the settings file an org admin owns; a repo-level hook can be edited by anyone who
# can commit). A block explains itself: the reason and the route to approval go to
# stderr, which the agent sees and relays.
#
# DEGRADATION CONTRACT (same as scripts/hooks/*.sh):
#   - A production deploy command with no release authorization => exit 2 (BLOCK —
#     the one fail-closed path)
#   - Anything else, including internal errors                  => exit 0 (fail-open)
#
# Approval convention here: RELEASE_APPROVAL names the approver + ticket (e.g.
# "jane.d CHG-4412"), set in the environment by your release process — swap in
# whatever your change management actually checks (a ticket API call, a signed file).
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
  [[ -n "$cmd" ]] || return 0

  # Match your real deploy entry points; keep patterns narrow — a broad match that
  # blocks unrelated commands is a workflow DoS (same rule as block-secrets.sh).
  case "$cmd" in
    *deploy*production*|*production*deploy*|*"helm upgrade"*prod*|*"terraform apply"*prod*) ;;
    *) return 0 ;;
  esac

  if [[ -z "${RELEASE_APPROVAL:-}" ]]; then
    echo "BLOCK: production deploys need a named release authorization." >&2
    echo "Route: have the release manager set RELEASE_APPROVAL='<approver> <change-ticket>'" >&2
    echo "for this session (or satisfy your change-management check), then re-run." >&2
    return 2
  fi
  echo "Release authorized by: $RELEASE_APPROVAL" >&2
  return 0
}

_main
