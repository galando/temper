#!/usr/bin/env bash
# check-original-options.sh: every answer the Temper mod reads from a question dialog is written, with
# the same words, in the page that asks that question (ADR 0012: the person decides only in a dialog,
# and the mod reads the answer from its result). Case does not matter.
#
# The other half is the mod's own test of the gate answers, which pins how each of these words is read.
# This script reads only the pages that ask the questions. A new answer the mod reads is added to the
# table below, with the page that asks it.
set -uo pipefail
# With CDPATH set, cd prints the folder it enters, and the path below would hold it twice.
unset CDPATH
# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts}"
[[ "$ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
# the answer | the page that asks for it
TABLE='
Continue to|commands/temper.md
Save for later|commands/temper.md
Loop back to|commands/temper.md
Override and continue|commands/temper.md
Accept finding|commands/temper.md
Override and commit|commands/temper.md
Commit (Recommended)|commands/temper.md
Start over|commands/temper.md
Keep the agent|reference/build-groups.md
Stage by stage|reference/autonomy.md
Autonomous|reference/autonomy.md
Add to plan|commands/temper.md
Revert|commands/temper.md
Allow once|commands/temper.md
'

FAIL=0
PASS=0
while IFS='|' read -r option page; do
  [[ -n "$option" ]] || continue
  if grep -qiF -- "$option" "$ROOT/$page"; then
    PASS=$((PASS+1))
  else
    echo "FAIL: the answer \"$option\" is no longer in $page (the mod reads it; update this table and the mod's gate answer test)"
    FAIL=$((FAIL+1))
  fi
done <<< "$TABLE"

echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
