#!/bin/bash
set -e

git init -q
git config user.name "Eval"
git config user.email "eval@example.com"

echo "hello" > README.md
git add -A
git commit -q -m "Initial commit"
