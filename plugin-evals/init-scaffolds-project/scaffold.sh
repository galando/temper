#!/bin/bash
set -e

git init -q
git config user.name "Eval"
git config user.email "eval@example.com"

cat > README.md <<'EOF'
# Fresh project

No Temper config yet.
EOF

git add -A
git commit -q -m "Initial commit"
