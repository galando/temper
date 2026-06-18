#!/usr/bin/env bash
#
# verify-tests-ran.sh — pre-commit check-green gate.
#
# Refuses a commit if the latest build state is not check_complete (i.e. /temper:check
# has not passed for the staged change). The check sentinel is the `stage` field in
# .temper/build-state.json equal to "check_complete" (or "eval_complete").
#
# DEGRADATION CONTRACT (the two paths are distinct — do not conflate):
#   - .temper/build-state.json present AND stage not green => exit 2 (BLOCK — the one
#     fail-closed path. This is the entire point of the hook.)
#   - .temper/build-state.json MISSING or UNREADABLE       => exit 0 (DEGRADE. Do NOT
#     block on missing state — that would block every commit in repos that don't run
#     Temper. Missing state is fail-open by design.)
#   - Internal error                                        => exit 0 (FAIL-OPEN)
set -uo pipefail

_main() {
  local state="${TEMPER_BUILD_STATE:-.temper/build-state.json}"

  # Missing or unreadable state => degrade (fail-open). This is intentional and distinct
  # from the "present but not green" block below.
  if [[ ! -f "$state" ]]; then
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    # Cannot parse JSON reliably => fail-open rather than risk a false block.
    return 0
  fi

  local stage
  stage=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print('__unreadable__'); sys.exit(0)
print(d.get('stage', '__missing__'))
" "$state" 2>/dev/null || true)

  case "$stage" in
    check_complete|eval_complete)
      # Green: Check (or Eval) has run. Allow the commit.
      return 0
      ;;
    __unreadable__|__missing__|'')
      # State present but unreadable/missing field => fail-open (degrade).
      return 0
      ;;
    *)
      # State present but stage is not green (e.g. build_complete, plan_complete).
      # This is the fail-closed path.
      echo "BLOCK: latest Temper stage is '${stage}', not check_complete." >&2
      echo "Run /temper:check before committing." >&2
      return 2
      ;;
  esac
}

_main "$@"
