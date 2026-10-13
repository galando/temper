#!/usr/bin/env bash
#
# make-fixture.sh <fixture> <dest> [--at-review] [--autonomy]
#
# Builds one measurement fixture (evals/fixtures/<fixture>) as a git project in <dest>, a folder
# that must not exist yet. The answer key (fixture.json) and the hidden test never go into <dest>:
# the agent has to find the defect itself.
#
#   full fixture    the base commit only; you start the run with the fixture's feature text.
#   review fixture  the base commit, a commit with the accepted spec, and a commit with the change
#                   that holds the planted defect.
#   --at-review     (review fixtures) also starts a Temper run and moves it to Review with the CLI:
#                   the gates of Intent and Plan are run, Build is skipped with a recorded reason
#                   (the change is given). This is what evals/run.sh starts from.
#   --autonomy      writes autonomy.enabled: true, so the plan gate offers the arming choice.
set -euo pipefail

EVALS="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="${EVALS%/evals}"
TEMPER="$PLUGIN/scripts/temper"

usage() { echo "usage: make-fixture.sh <fixture> <dest> [--at-review] [--autonomy]" >&2; exit 2; }
[[ $# -ge 2 ]] || usage
NAME="$1" DEST="$2"; shift 2
AT_REVIEW=0 AUTONOMY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --at-review) AT_REVIEW=1; shift ;;
    --autonomy) AUTONOMY=1; shift ;;
    *) usage ;;
  esac
done

FIX="$EVALS/fixtures/$NAME"
[[ -f "$FIX/fixture.json" ]] || { echo "FAIL: no fixture named '$NAME' (see evals/fixtures)" >&2; exit 2; }
[[ ! -e "$DEST" ]] || { echo "FAIL: $DEST exists; give a folder that does not exist yet" >&2; exit 2; }
key() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$FIX/fixture.json" "$1"; }
KIND="$(key kind)" SLUG="$(key slug)" TITLE="$(key title)" TEST_CMD="$(key test)"
[[ "$AT_REVIEW" == 0 || "$KIND" == review ]] || { echo "FAIL: --at-review is for review fixtures; $NAME is a $KIND fixture" >&2; exit 2; }

mkdir -p "$DEST"
DEST="$(cd -P "$DEST" && pwd)"
cp -R "$FIX/base/." "$DEST/"
cd "$DEST"
git init -q
git config user.name "Fixture Person"
git config user.email "fixture@example.com"
printf '__pycache__/\n*.pyc\n' > .gitignore
mkdir -p .claude
{
  echo "# Temper settings of the $NAME fixture (evals/README.md)."
  echo "stack: auto"
  echo "packs: [quality, tdd, security, git]"
  echo "review:"
  echo "  block-on: [critical]"
  echo "check:"
  echo "  # No coverage tool is assumed on the machine: a recorded 0 passes, so the verdict is about the defect."
  echo "  coverage-threshold: 0"
  echo "  commands:"
  echo "    test: $TEST_CMD"
  echo "phases:"
  echo "  design: true"
  echo "feedback:"
  echo "  enabled: true"
  echo "loops:"
  echo "  max-per-type: 2"
  if [[ "$AUTONOMY" == 1 ]]; then echo "autonomy:"; echo "  enabled: true"; fi
} > .claude/temper.config
git add -A
git commit -qm "base: the $NAME fixture"

if [[ "$KIND" == review ]]; then
  mkdir -p ".temper/specs/$SLUG"
  cp -R "$FIX/spec/." ".temper/specs/$SLUG/"
  git add -A
  git commit -qm "docs(plan): $TITLE"
  BASE_SHA="$(git rev-parse HEAD)"
  cp -R "$FIX/change/." "$DEST/"
  git add -A
  git commit -qm "feat: $TITLE"
fi

if [[ "$AT_REVIEW" == 1 ]]; then
  "$TEMPER" init >/dev/null
  "$TEMPER" state init "$SLUG" --command temper >/dev/null
  "$TEMPER" state set base_sha "$BASE_SHA" >/dev/null
  "$TEMPER" state set complexity simple >/dev/null
  for pair in intent:plan plan:build; do
    stage="${pair%%:*}" next="${pair##*:}"
    if ! "$TEMPER" gate "$stage" >/dev/null 2>&1; then
      "$TEMPER" override "$stage" --reason "fixture: the $stage of the given change is accepted as written" >/dev/null
    fi
    "$TEMPER" state advance "${stage}_complete" "$next" >/dev/null
  done
  "$TEMPER" gate build >/dev/null 2>&1 || true
  "$TEMPER" override build --reason "fixture: the change under review is given, Build did not run" >/dev/null
  "$TEMPER" state advance build_complete review >/dev/null
fi

echo "OK: the $NAME fixture ($KIND) is in $DEST"
