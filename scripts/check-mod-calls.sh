#!/usr/bin/env bash
# check-mod-calls.sh: the Temper mod's `$` surface is a reviewed list, enforced here.
#
# Runs `claude plugin validate` on the manifest, takes the `calls:` line it prints for the
# hooks module, and FAILS when
#   - any call is in the process, http or env namespace (the mod never spawns, fetches or
#     reads the environment: tests, lint, git and CLI calls are prompts to Claude),
#   - any call is not on the reviewed list below, or
#   - a call on the list is not made any more (the list is exact: a stale line goes).
# A new call is a reviewed change: add it here with a one line reason. (docs/mods-plan.md 2.7 is the
# list as first built, kept as history.)
#
# Test hook: CHECK_MOD_CALLS_LINE="<a calls: line>" checks that line without running claude.
set -euo pipefail

# With CDPATH set, cd prints the folder it enters, and the path below would hold it twice.
unset CDPATH
# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${HERE%/scripts}"
[[ "$REPO_ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }

# The reviewed list: one `noun.method` per line, with why the mod needs it.
ALLOWED='
agent.list       the reviewerModel option: tells whether a subagent step belongs to the Temper review agent (read only; the spawn is never changed)
fs.read          reads .temper/view.json, the one file the mod reads of the CLI (ADR 0013)
fs.stat          resolves "." to the project root so absolute tool paths can be made relative
session.version  the version guard: the mod stays inert below 2.1.287
state.get        the drawing hooks read the run view and the mode, so a write redraws them
state.set        publishes the run view and the mode
store.delete     drops the oldest kept report and the oldest run of answers, so the store stays small
store.get        the gate answers of the person per run (dec:<run id>) and the kept report
store.set        records those (the mod writes no file)
ui.close         closes the pane (a toggle, a pane that would not dock)
ui.open          opens the pane
ui.resolve       the element table of the surface being drawn (Box, Text, Markdown)
ui.toast         one toast per stage change
'

allowed_names() { printf '%s\n' "$ALLOWED" | awk 'NF { print $1 }'; }

if [[ -n "${CHECK_MOD_CALLS_LINE:-}" ]]; then
  LINE="$CHECK_MOD_CALLS_LINE"
else
  command -v claude >/dev/null 2>&1 || { echo "FAIL: claude is not installed (need Claude Code 2.1.287 or later)"; exit 1; }
  OUT="$(claude plugin validate "$REPO_ROOT/.claude-plugin/plugin.json" </dev/null 2>&1)" || {
    echo "$OUT"
    echo "FAIL: claude plugin validate failed"
    exit 1
  }
  # Every calls: line counts, so a call in any hooks module the validator reports is checked.
  LINE="$(printf '%s\n' "$OUT" | grep -E ' calls: \$\.' || true)"
  [[ -n "$LINE" ]] || { echo "$OUT"; echo "FAIL: no 'calls:' line for the mod in the validate output"; exit 1; }
fi

# Claude Code cuts a long note ("… [+N chars]"): a cut line can hide a call, so it fails.
if printf '%s' "$LINE" | grep -qE '\[\+[0-9]+ chars\]'; then
  echo "FAIL: the calls: line is cut short by the validator, so a call could be hidden. Make the 'via' lists shorter (one helper per call)."
  exit 1
fi

# "...calls: $.fs.list (via makeIo), $.store.get (via a, b), ..." -> one name per line.
CALLS="$(printf '%s\n' "$LINE" \
  | sed -E 's/.*calls: //' \
  | sed -E 's/ \([^)]*\)//g' \
  | tr ',' '\n' \
  | sed -E 's/^[[:space:]]*\$\.//; s/[[:space:]]+$//' \
  | awk 'NF')"
[[ -n "$CALLS" ]] || { echo "FAIL: the calls: line names no calls (is the mod scanned?)"; exit 1; }

FAIL=0
while IFS= read -r call; do
  # The namespace is the part before the first dot, compared with three fixed words.
  case "${call%%.*}" in
    process|http|env)
      echo "FAIL: forbidden call \$.$call (the mod never spawns, fetches or reads the environment)"
      FAIL=1
      continue
      ;;
  esac
  if ! allowed_names | grep -qx -- "$call"; then
    echo "FAIL: \$.$call is not on the reviewed list (scripts/check-mod-calls.sh)"
    FAIL=1
  fi
done <<< "$CALLS"

# This script reads only the validator's output and never opens a file of the mod.

# The list is exact: every reviewed call is still made.
while IFS= read -r name; do
  if ! printf '%s\n' "$CALLS" | grep -qx -- "$name"; then
    echo "FAIL: \$.$name is on the reviewed list but the mod no longer makes it (remove its line)"
    FAIL=1
  fi
done < <(allowed_names)

if [[ $FAIL -eq 0 ]]; then
  echo "OK: $(printf '%s\n' "$CALLS" | wc -l | tr -d ' ') calls, exactly the reviewed list, none process/http/env"
fi
exit $FAIL
