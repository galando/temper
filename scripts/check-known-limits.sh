#!/usr/bin/env bash
# check-known-limits.sh: the README limits paragraph must say, in plain words, what the Bash
# reader cannot do. The mod's known limits test holds the table of attempts that stay possible;
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
need "$README" "builds the" "a program that builds the script name or a path at run time is a known limit"
need "$README" "inside a patch or an archive" "a patch or an archive hides the names it writes"
need "$README" "session's own picture" "the staged set is the session's own picture"
need "$README" "PowerShell" "MCP and PowerShell file tools are not evaluated"
need "$PLAN" "builds the" "mods-plan states that a run time path is a known limit"
need "$PLAN" "a staging made by a script" "mods-plan states the staging limit"
need "$PLAN" "shell tricks" "mods-plan 3.4 states the limit"
need "$PLAN" "one time decision token" "mods-plan 3.4 records the future hardening"
need "$PLAN" "Known limits, on purpose" "mods-plan 3.4 names the known limits section"
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
