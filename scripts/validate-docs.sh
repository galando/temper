#!/usr/bin/env bash
# validate-docs.sh — Validate documentation consistency
# Offline-safe, no network calls.
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required but not found in PATH"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# 1. docs/commands.md references match .claude/commands/ files
COMMANDS_MD="$REPO_ROOT/docs/commands.md"
COMMANDS_DIR="$REPO_ROOT/.claude/commands"

if [[ -f "$COMMANDS_MD" && -d "$COMMANDS_DIR" ]]; then
  # Extract command names from commands.md (e.g., /temper, /temper:plan, etc.)
  MD_CMDS=$(grep -oE '/temper(:[a-z]+)?' "$COMMANDS_MD" | sort -u || true)
  # Extract command names from files
  FILE_CMDS=$(
    for f in "$COMMANDS_DIR"/*.md; do
      name=$(basename "$f" .md)
      if [[ "$name" == "temper" ]]; then
        echo "/temper"
      else
        echo "/temper:${name}"
      fi
    done | sort -u
  )

  MISSING_IN_MD=$(comm -23 <(echo "$FILE_CMDS") <(echo "$MD_CMDS") || true)
  if [[ -n "$MISSING_IN_MD" ]]; then
    fail "Commands in .claude/commands/ but missing from docs/commands.md:"
    echo "$MISSING_IN_MD" | sed 's/^/  /'
  else
    ok
  fi
else
  fail "docs/commands.md or .claude/commands/ not found"
fi

# 2. All markdown links in docs/ resolve to existing files
# Skip .html extensions (Jekyll-generated). Try bare path, then path.md.
# Links are resolved relative to the containing file's directory (so docs in
# subdirectories work), with a fallback to docs/ for backwards compatibility.
BROKEN_LINKS=$(
  grep -roE '\]\([^)]+\)' "$REPO_ROOT/docs" --include='*.md' 2>/dev/null | \
  grep -vE 'http|mailto|\.html' | while read -r match; do
    SRC=$(echo "$match" | cut -d: -f1)
    link=$(echo "$match" | sed 's/^[^:]*://;s/\](//;s/)//')
    FILE=$(echo "$link" | sed 's/#.*//')
    [[ -z "$FILE" ]] && continue
    SRC_DIR=$(dirname "$SRC")
    # Resolve relative to the file's own directory, then fall back to docs/.
    if [[ ! -e "$SRC_DIR/$FILE" && ! -e "$SRC_DIR/${FILE}.md" \
       && ! -e "$REPO_ROOT/docs/$FILE" && ! -e "$REPO_ROOT/docs/${FILE}.md" ]]; then
      echo "$link"
    fi
  done || true
)

if [[ -z "$BROKEN_LINKS" ]]; then
  ok
else
  fail "Broken internal links in docs/:"
  echo "$BROKEN_LINKS" | sort -u | sed 's/^/  /'
fi

# 3. getting-started.md contains installation instructions
GS="$REPO_ROOT/docs/getting-started.md"
if [[ -f "$GS" ]]; then
  if grep -qi "install\|setup\|getting started" "$GS"; then
    ok
  else
    fail "docs/getting-started.md missing install/setup instructions"
  fi
else
  fail "docs/getting-started.md not found"
fi

# 4. index.html contains basic structure tags
INDEX="$REPO_ROOT/docs/index.html"
if [[ -f "$INDEX" ]]; then
  for tag in "<html" "<head" "<body"; do
    if grep -q "$tag" "$INDEX"; then
      ok
    else
      fail "docs/index.html missing $tag tag"
    fi
  done
else
  fail "docs/index.html not found"
fi

echo ""
echo "=== validate-docs.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
