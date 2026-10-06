#!/usr/bin/env bash
# check-original-options.sh: every question option of the original orchestrator
# (commands/temper.md) must still exist there, with the same words. Case does not matter.
#
# The other half lives in the mod's own action test, which imports the action table: "every
# original option maps to a button" checks that each option below has a button with its label, and
# "only the original options, plus Discuss, Play and Skip" checks that no button carries any other
# label. This script reads only commands/temper.md.
#
# Two options are carried by a button with other words, on purpose:
#   Override and continue -> "Skip with a reason"      (key 9)
#   Other                 -> "Discuss"                 (key 4)
# A new option in commands/temper.md is added to the table below, and to the action test's table.
set -uo pipefail
# With CDPATH set, cd prints the folder it enters, and the path below would hold it twice.
unset CDPATH
# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts}"
[[ "$ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
MD="$ROOT/commands/temper.md"

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
  if grep -qiF -- "$option" "$MD"; then
    PASS=$((PASS+1))
  else
    echo "FAIL: \"$option\" (button \"$label\") is no longer in commands/temper.md (update this table and the mod's action test)"
    FAIL=$((FAIL+1))
  fi
done <<< "$TABLE"

echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
