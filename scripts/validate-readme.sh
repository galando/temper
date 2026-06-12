#!/usr/bin/env bash
# validate-readme.sh — Validate README.md structure and size
# Offline-safe, no network calls.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

README="$REPO_ROOT/README.md"

if [[ ! -f "$README" ]]; then
  echo "FAIL: README.md not found"
  exit 1
fi

# 1. Line count <= 300
LINES=$(wc -l < "$README" | tr -d ' ')
if [[ "$LINES" -le 300 ]]; then
  ok
else
  fail "README is $LINES lines (max 300)"
fi

# 2. Required sections exist
for section in "Quick Start\|Installation\|Install" "What It Does\|Overview\|How it works\|How It Works"; do
  if grep -qi "$section" "$README"; then
    ok
  else
    fail "README missing section matching: $section"
  fi
done

# 3. Internal markdown links resolve
# Extract [text](./relative/path) or [text](relative/path) links (not http/https)
BROKEN=$(grep -oE '\]\([^)]+\)' "$README" | grep -vE 'http|mailto' | \
  sed 's/\](//;s/)//' | while read -r link; do
    # Strip anchor
    FILE=$(echo "$link" | sed 's/#.*//')
    [[ -z "$FILE" ]] && continue
    TARGET="$REPO_ROOT/$FILE"
    [[ ! -e "$TARGET" ]] && echo "$link"
  done || true)

if [[ -z "$BROKEN" ]]; then
  ok
else
  fail "Broken internal links in README:"
  echo "$BROKEN" | sed 's/^/  /'
fi

# 4. First 50 lines contain problem statement and quick start
HEAD50=$(head -50 "$README")
if echo "$HEAD50" | grep -qi "install\|quick start\|get started\|usage"; then
  ok
else
  fail "First 50 lines missing install/quick start instruction"
fi

echo ""
echo "=== validate-readme.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
