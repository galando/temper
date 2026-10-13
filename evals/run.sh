#!/usr/bin/env bash
#
# run.sh <review fixture> [--plugin DIR] [--out DIR] [--label TEXT] [--append]
#
# The unattended measurement of Review and Check on one review fixture (evals/README.md). It needs
# the `claude` CLI, logged in; every run is billed to that login. Nothing asks a gate question
# here: the fixture starts at Review (make-fixture.sh --at-review), each stage brief runs as its
# own `claude -p` session with this plugin loaded (the same clean context a stage subprocess
# gets), and the CLI computes each verdict. A Review FAIL is skipped with a recorded reason so
# Check runs too. Then score.py scores the run.
#
#   --plugin DIR  the Temper checkout to load (default: the one this script is in)
#   --out DIR     where the fixture project goes (default: a new temporary folder); kept after
#   --label TEXT  a note for the results row (for example "baseline")
#   --append      add the row to evals/results.md
set -euo pipefail

EVALS="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="${EVALS%/evals}"
usage() { echo "usage: run.sh <review fixture> [--plugin DIR] [--out DIR] [--label TEXT] [--append]" >&2; exit 2; }
[[ $# -ge 1 ]] || usage
NAME="$1"; shift
OUT="" LABEL="" APPEND=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin) PLUGIN="$(cd -P "${2:?}" && pwd)"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    --append) APPEND=(--append "$EVALS/results.md"); shift ;;
    *) usage ;;
  esac
done
command -v claude >/dev/null || { echo "FAIL: the claude CLI is not on PATH" >&2; exit 2; }
TEMPER="$PLUGIN/scripts/temper"
[[ -n "$OUT" ]] || OUT="$(mktemp -d)/$NAME"
bash "$EVALS/make-fixture.sh" "$NAME" "$OUT" --at-review
cd "$OUT"
SPEC="$("$TEMPER" state get spec_path)"
LINE="Plugin folder: $PLUGIN; wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder."

stage() { # stage <name>: runs that stage's brief as one claude -p session, then its gate
  local name="$1" model
  model="$("$TEMPER" model "$name")"
  echo "== $name (model ${model:-default})"
  # A session started from inside another one would share its id; this one is its own.
  # The prompt goes in on standard input: --allowedTools takes every word after it.
  printf 'Follow %s/agents/%s.md exactly. Spec: %s.\n%s\n' "$PLUGIN" "$name" "$SPEC" "$LINE" |
    env -u CLAUDE_CODE_SESSION_ID timeout 1800 claude -p \
      --plugin-dir "$PLUGIN" ${model:+--model "$model"} --output-format json \
      --allowedTools Bash Read Write Edit MultiEdit Glob Grep Agent TodoWrite \
      > "$OUT/.temper/eval-$name.json" || echo "WARN: the $name session ended with an error" >&2
  "$TEMPER" gate "$name" | tail -n 3 || true
}

stage review
if [[ "$(python3 -c 'import json; print(json.load(open(".temper/gates.json")).get("review", {}).get("verdict", ""))' 2>/dev/null)" != PASS ]]; then
  "$TEMPER" override review --reason "measurement: run Check on the same change" >/dev/null
fi
"$TEMPER" state advance review_complete check >/dev/null
stage check

python3 "$EVALS/score.py" run "$NAME" "$OUT" --result "$OUT/.temper/eval-review.json" --result "$OUT/.temper/eval-check.json" \
  --label "$LABEL" "${APPEND[@]}"
echo "The run is kept in $OUT"
