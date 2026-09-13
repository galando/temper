#!/bin/bash
set -e

git init -q
git config user.name "Eval"
git config user.email "eval@example.com"

mkdir -p src
cat > src/orders.js <<'EOF'
// TODO: implement firstNItems(items, n)
module.exports = {};
EOF
git add -A
git commit -q -m "scaffold: stub firstNItems"

# The "just written" change under review — left uncommitted so `git diff --name-only`
# picks it up as changed. Off-by-one: `i <= n` reads one element past the requested
# count, pushing `undefined` onto the result once `items` is exhausted.
cat > src/orders.js <<'EOF'
function firstNItems(items, n) {
  const out = [];
  for (let i = 0; i <= n; i++) {
    out.push(items[i]);
  }
  return out;
}

module.exports = { firstNItems };
EOF
