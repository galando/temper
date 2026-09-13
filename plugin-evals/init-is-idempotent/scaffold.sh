#!/bin/bash
set -e

git init -q
git config user.name "Eval"
git config user.email "eval@example.com"

mkdir -p .claude
cat > .claude/temper.config <<'EOF'
# Temper Configuration (v7)
# EVAL-MARKER-DO-NOT-OVERWRITE-7f3a1c
stack: auto
packs: [quality, tdd, security, git, performance]
tools:
  mode: auto
review:
  block-on: [critical]
check:
  coverage-threshold: 80
EOF

git add -A
git commit -q -m "Already set up for Temper"
