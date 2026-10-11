#!/usr/bin/env bash
# check-known-limits.sh: the limits section of the mod page (docs/mod.md, which the README links)
# must say, in plain words, what the Bash reader cannot do. The mod's known limits test holds the
# table of attempts that stay possible; a plugin test cannot read the docs, so this script checks the text.
set -uo pipefail
# With CDPATH set, cd prints the folder it enters, and the path below would hold it twice.
unset CDPATH
# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts}"
[[ "$ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
# The two files this script reads, each named once in full. Nothing else is opened.
MOD="$(cat "$ROOT/docs/mod.md")"
PLAN="$(cat "$ROOT/docs/mods-plan.md")"
PASS=0; FAIL=0
need() { # need <MOD|PLAN> <fixed text> <what>
  local text name
  case "$1" in
    MOD) text="$MOD"; name="docs/mod.md" ;;
    PLAN) text="$PLAN"; name="mods-plan.md" ;;
    *) FAIL=$((FAIL+1)); echo "FAIL: unknown file key '$1' (use MOD or PLAN)"; return ;;
  esac
  if grep -qiF -- "$2" <<< "$text"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $name does not say: $3 (\"$2\")"; fi
}
need MOD "shell tricks" "the Bash reader cannot see shell tricks"
need MOD "pre-commit" "the native pre-commit hook is a hard guarantee"
need MOD "editing tools" "the editing tools are a hard guarantee"
need MOD "earlier call" "a link or script made in an earlier call is a known limit"
need MOD "can only hide a question" "an injected marker copy can only hide a question"
need MOD "model \`git commit\` is" "a model commit at Done is allowed"
need MOD "builds the" "a program that builds the script name or a path at run time is a known limit"
need MOD "inside a patch or an archive" "a patch or an archive hides the names it writes"
need MOD "session's own picture" "the staged set is the session's own picture"
need MOD "PowerShell" "MCP and PowerShell file tools are not evaluated"
need PLAN "builds the" "mods-plan states that a run time path is a known limit"
need PLAN "a staging made by a script" "mods-plan states the staging limit"
need PLAN "shell tricks" "mods-plan 3.4 states the limit"
need PLAN "one time decision token" "mods-plan 3.4 records the future hardening"
need PLAN "Known limits, on purpose" "mods-plan 3.4 names the known limits section"
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
