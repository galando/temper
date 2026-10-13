#!/usr/bin/env bash
# check-known-limits.sh: the docs must say, in plain words, what the guard does not check (ADR 0013).
# The mod's known limits test holds the table of attempts that stay possible; a plugin test cannot read
# the docs, so this script checks the text of docs/mod.md (which the README links) and docs/trust.md.
set -uo pipefail
# With CDPATH set, cd prints the folder it enters, and the path below would hold it twice.
unset CDPATH
# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts}"
[[ "$ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
# The two files this script reads, each named once in full. Nothing else is opened.
MOD="$(cat "$ROOT/docs/mod.md")"
TRUST="$(cat "$ROOT/docs/trust.md")"
PASS=0; FAIL=0
need() { # need <MOD|TRUST> <fixed text> <what>
  local text name
  case "$1" in
    MOD) text="$MOD"; name="docs/mod.md" ;;
    TRUST) text="$TRUST"; name="docs/trust.md" ;;
    *) FAIL=$((FAIL+1)); echo "FAIL: unknown file key '$1' (use MOD or TRUST)"; return ;;
  esac
  if grep -qiF -- "$2" <<< "$text"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $name does not say: $3 (\"$2\")"; fi
}
need TRUST "Temper is not a sandbox" "Temper is not a sandbox"
need TRUST "a commit the hook does not check" "a commit the hook does not check gets through"
need MOD "Temper is not a sandbox" "Temper is not a sandbox"
need MOD "editing tools" "the editing tools are a hard guarantee"
need MOD "pre-commit" "the native pre-commit hook is a hard guarantee"
need MOD "does not follow variables" "a variable is a known limit"
need MOD "a string another program runs" "a call inside a program string is a known limit"
need MOD "earlier call" "a link or script made in an earlier call is a known limit"
need MOD "built at run time" "a program that builds the name or a path at run time is a known limit"
need MOD "a patch or an archive" "a patch or an archive hides the names it writes"
need MOD "A commit the native hook does not check" "a merge, a cherry-pick or git plumbing is a known limit"
need MOD "TEMPER_DIR" "TEMPER_DIR and TEMPER_CONFIG are a known limit"
need MOD "can only hide a question" "an injected marker copy can only hide a question"
need MOD "goes to the native \`pre-commit\` hook in every stage" "a plain commit is for the native hook, in every stage"
need MOD "Claude writes the question" "a decision is the option the person picks in a question Claude writes"
need MOD "PowerShell" "MCP and PowerShell file tools are not checked"
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
