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
Share HTML review|Share HTML review
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

# Second check: the other way round. Every button label in actions.ts must be an original option
# (the first column above, or its label), with a suffix allowed after "Continue to", "Loop back to"
# and "Continue with task", or one of the explicit extras. Anything else fails with its name.
ALLOWED_LABELS="Continue to|Continue with task|Loop back to|Save for later|Grill me|Teach me|Walk through step by step|Open HTML review|Share HTML review|Architecture depth review|Review config suggestions|Change|Stop|Commit|Start Intent|Run Phase|Discuss|Play while you wait|Skip with a reason|Resume|Fix the failures|Fix the findings|Fix|Accept|Explain"
# Labels written as the third argument of prompt(), command(), launch() or draft().
LABELS="$(grep -oE "(prompt|command|launch|draft)\((key|'[0-9]'), (id|'[^']+'|\`[^\`]+\`), '[^']+'" "$ACTIONS" | sed -E "s/.*, '([^']+)'$/\1/" | sort -u)"
# Labels written as template strings: `Continue to ${next}`, `Loop back to ${...}`, `Run ${...}`.
LABELS="$LABELS"$'\n'"$(grep -oE "\`(Continue to|Continue with task|Loop back to|Run) " "$ACTIONS" | tr -d '`' | sed -E 's/ $//; s/^Run$/Run Phase/' | sort -u)"
while IFS= read -r label; do
  [[ -n "$label" ]] || continue
  if printf '%s\n' "$label" | grep -qiE "^(${ALLOWED_LABELS})( |$)"; then
    PASS=$((PASS+1))
  else
    echo "FAIL: the button label \"$label\" in actions.ts is not an original option of commands/temper.md and is not an explicit extra"
    FAIL=$((FAIL+1))
  fi
done <<< "$LABELS"

echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
