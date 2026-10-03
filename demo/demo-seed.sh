#!/bin/bash
# Seeds /tmp/pr-demo for demo/temper.tape: the fixture project plus a Temper run sitting in
# the Intent phase with a ready intent. Run it from the root of a Temper clone.
set -e
ROOT="${TEMPER_CLONE:-$PWD}"
rm -rf /tmp/pr-demo
cp -R "$ROOT/demo/password-reset" /tmp/pr-demo
cd /tmp/pr-demo
git init -q && git add -A && git commit -qm start
"$ROOT/scripts/temper" init >/dev/null 2>&1 || true
"$ROOT/scripts/temper" state init pwreset --command temper >/dev/null
mkdir -p .temper/specs/pwreset
cp "$ROOT/demo/pr-intent.md" .temper/specs/pwreset/intent.md
