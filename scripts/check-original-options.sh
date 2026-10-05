#!/usr/bin/env bash
# check-original-options.sh: every question option of the original orchestrator
# (commands/temper.md) must still exist there AND have a button in the Temper bar's action
# table (hooks/temper-mod/core/actions.ts), with the same words. Case does not matter.
#
# Two options are carried by a button with other words, on purpose:
#   Override and continue -> "Skip with a reason"      (key 9)
#   Other                 -> "Discuss"                 (key 4)
# A new option in commands/temper.md is added to the table below, and to the action table.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MD="$ROOT/commands/temper.md"
ACTIONS="$ROOT/hooks/temper-mod/core/actions.ts"

# option in commands/temper.md | label in the action table
TABLE='
Continue to|Continue to
Save for later|Save for later
Grill Me|Grill me
Teach Me|Teach me
Walk through step by step|Walk through step by step
Open HTML review|Open HTML review
Loop back|Loop back to
Override and continue|Skip with a reason
Architecture Depth Review|Architecture depth review
Review config suggestions|Review config suggestions
Change|Change
Stop|Stop
Commit|Commit
Other|Discuss
'

FAIL=0
PASS=0
while IFS='|' read -r option label; do
  [[ -n "$option" ]] || continue
  if ! grep -qiF -- "$option" "$MD"; then
    echo "FAIL: \"$option\" is no longer in commands/temper.md (update scripts/check-original-options.sh)"
    FAIL=$((FAIL+1)); continue
  fi
  if ! grep -qiF -- "'$label" "$ACTIONS" && ! grep -qiF -- "\`$label" "$ACTIONS"; then
    echo "FAIL: the original option \"$option\" has no action labelled \"$label\" in hooks/temper-mod/core/actions.ts"
    FAIL=$((FAIL+1)); continue
  fi
  PASS=$((PASS+1))
done <<< "$TABLE"

echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
