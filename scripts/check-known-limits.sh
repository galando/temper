#!/usr/bin/env bash
# check-known-limits.sh: the README limits paragraph must say, in plain words, what the Bash
# reader cannot do. tests/mod/known-limits.test.ts holds the table of attempts that stay possible;
# a plugin test cannot read the README, so this script checks the text.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT/README.md"
PLAN="$ROOT/docs/mods-plan.md"
PASS=0; FAIL=0
need() { # need <file> <fixed text> <what>
  if grep -qiF -- "$2" "$1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $(basename "$1") does not say: $3 (\"$2\")"; fi
}
need "$README" "shell tricks" "the Bash reader cannot see shell tricks"
need "$README" "pre-commit" "the native pre-commit hook is a hard guarantee"
need "$README" "editing tools" "the editing tools are a hard guarantee"
need "$README" "earlier call" "a link or script made in an earlier call is a known limit"
need "$README" "can only hide a question" "an injected marker copy can only hide a question"
need "$README" "model \`git commit\` is" "a model commit at Done is allowed"
need "$PLAN" "shell tricks" "mods-plan 3.4 states the limit"
need "$PLAN" "one time decision token" "mods-plan 3.4 records the future hardening"
need "$PLAN" "known-limits.test.ts" "mods-plan 3.4 points at the table"
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
