#!/bin/bash
# Seeds /tmp/pr-demo for the demo: the fixture project plus a Temper run. Run it from the root of
# a Temper clone.
#
#   bash demo/demo-seed.sh          the run sits in the Intent phase (a draft intent)
#   bash demo/demo-seed.sh plan     the run sits in the Plan phase: the intent is accepted, plan.md
#                                   and tasks.md are written, and both checks (gate intent, gate plan)
#                                   already pass, so the first key press is "1 Continue to Build"
set -e
MODE="${1:-intent}"
case "$MODE" in intent | plan) ;; *) echo "usage: demo-seed.sh [intent|plan]"; exit 1 ;; esac

ROOT="${TEMPER_CLONE:-$PWD}"
DEMO=/tmp/pr-demo
# A fixed path in /tmp is never removed blind. It is created when it is absent, and replaced only
# when it holds the marker file this script writes. A symlink is never followed or removed.
if [ -L "$DEMO" ]; then
  echo "$DEMO is a link, not a demo folder. Delete $DEMO by hand, then run this again."
  exit 1
fi
if [ -e "$DEMO" ]; then
  if [ ! -f "$DEMO/.temper-demo" ]; then
    echo "$DEMO exists and is not a demo folder. Delete $DEMO by hand, then run this again."
    exit 1
  fi
  rm -rf "$DEMO"
fi
cp -R "$ROOT/demo/password-reset" "$DEMO"
touch "$DEMO/.temper-demo"
cd "$DEMO"
git init -q
echo .temper-demo >> .git/info/exclude
git add -A && git commit -qm start
"$ROOT/scripts/temper" init >/dev/null 2>&1 || true
"$ROOT/scripts/temper" state init pwreset --command temper >/dev/null
mkdir -p .temper/specs/pwreset

if [ "$MODE" = "intent" ]; then
  cp "$ROOT/demo/pr-intent.md" .temper/specs/pwreset/intent.md
  exit 0
fi

cp "$ROOT/demo/plan-seed/intent.md" "$ROOT/demo/plan-seed/plan.md" "$ROOT/demo/plan-seed/tasks.md" .temper/specs/pwreset/
# The intent check passes, the CLI moves on to Plan, and the plan check passes.
"$ROOT/scripts/temper" gate intent >/dev/null
"$ROOT/scripts/temper" state advance intent_complete plan >/dev/null
"$ROOT/scripts/temper" gate plan >/dev/null
