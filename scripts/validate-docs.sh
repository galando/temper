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

# 1. docs/commands.md references match commands/ files
COMMANDS_MD="$REPO_ROOT/docs/commands.md"
COMMANDS_DIR="$REPO_ROOT/commands"

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
    fail "Commands in commands/ but missing from docs/commands.md:"
    echo "$MISSING_IN_MD" | sed 's/^/  /'
  else
    ok
  fi
else
  fail "docs/commands.md or commands/ not found"
fi

# 2. All markdown links in docs/ resolve to existing files.
# Resolve each link relative to the DIRECTORY OF THE FILE THAT CONTAINS IT — the way
# GitHub and Jekyll actually resolve a relative link. (Resolving from docs/ root instead
# passes a link that 404s in a subdirectory file, e.g. `decisions/x.md` written inside
# docs/decisions/y.md — the exact bug this check exists to catch.) Skip .html (Jekyll).
BROKEN_LINKS=$(
  find "$REPO_ROOT/docs" -name "*.md" -print | while read -r src; do
    grep -oE '\]\([^)]+\)' "$src" 2>/dev/null | grep -vE 'http|mailto|\.html' | \
    sed 's/\](//;s/)//' | while read -r link; do
      FILE=$(echo "$link" | sed 's/#.*//')
      [[ -z "$FILE" ]] && continue
      case "$FILE" in
        /*) TARGET="$REPO_ROOT/docs${FILE}" ;;          # absolute-from-docs-root
        *)  TARGET="$(dirname "$src")/$FILE" ;;         # relative to the containing file
      esac
      if [[ ! -e "$TARGET" && ! -e "${TARGET}.md" ]]; then
        echo "$link (in ${src#$REPO_ROOT/})"
      fi
    done
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

# 5. No token-optimization advice in the project CLAUDE.md's *rendered* text.
# Tokenomics is retired (docs/history/tokenomics.md); an external tool used to re-inject
# a TOKENOMICS block of standing advice into every session's context.
#
# This checks what the file actually contributes to context, i.e. after HTML comments are
# stripped — not the raw source. A raw grep passes a comment that quotes the marker
# syntax, because the quoted close-delimiter ends the comment early and spills the rest
# back into view. That exact bug shipped once. See docs/context-hygiene.md.
PROJECT_CLAUDE_MD="$REPO_ROOT/.claude/CLAUDE.md"
if [[ -f "$PROJECT_CLAUDE_MD" ]]; then
  TOKENOMICS_LEAK=$(python3 -c "
import re, sys
src = open(sys.argv[1]).read()
visible = re.sub(r'<!--.*?-->', '', src, flags=re.DOTALL)
# Anything a stray delimiter left behind is a leak by definition.
markers = ['TOKENOMICS:START', 'TOKENOMICS:END', '-->', '<!--']
advice = ['Token Optimization', 'prefer Sonnet', '/compact after turn', 'context snowballs']
hits = [m for m in markers + advice if m.lower() in visible.lower()]
print('; '.join(hits))
" "$PROJECT_CLAUDE_MD" 2>/dev/null)
  if [[ -n "$TOKENOMICS_LEAK" ]]; then
    fail ".claude/CLAUDE.md leaks token-optimization advice into rendered context ($TOKENOMICS_LEAK) — tokenomics is retired (docs/history/tokenomics.md)"
  else
    ok
  fi
else
  fail ".claude/CLAUDE.md not found"
fi

# 6. Regression guard: the choreography removed in v8's context pass stays removed.
# This does not judge prose quality — it cannot. It pins the specific micro-management
# patterns that were cut (fixed subagent arithmetic, attention-percentage budgets), so
# reintroducing one is a deliberate act with a failing check attached rather than a quiet
# drift back. See docs/context-hygiene.md.
CHOREO=$(grep -rnE 'groups of ~[0-9]+|max [0-9]+ parallel|[0-9]+% of attention|[Ww]eight [0-9]+% changed' \
  "$REPO_ROOT/reference" "$REPO_ROOT/packs" 2>/dev/null || true)
if [[ -z "$CHOREO" ]]; then
  ok
else
  fail "choreography patterns reintroduced (v8 context pass removed these):"
  echo "$CHOREO" | sed 's/^/  /'
fi

echo ""
echo "=== validate-docs.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
