#!/usr/bin/env bash
# quality-check.sh — Master validation script for Temper
# Runs all validation checks. Offline-safe, no network calls.
# Must complete in under 30 seconds.
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required but not found in PATH"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
RESULTS=()

echo "=== Temper Quality Check ==="
echo "Repo: $REPO_ROOT"
echo ""

# --- plugin.json validation ---
PJ="$REPO_ROOT/.claude-plugin/plugin.json"
if [[ ! -f "$PJ" ]]; then
  echo "[FAIL] plugin.json not found"
  ((TOTAL_FAIL++))
  RESULTS+=("plugin.json: NOT FOUND")
else
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PJ" 2>/dev/null; then
    echo "[PASS] plugin.json is valid JSON"
    ((TOTAL_PASS++))
    RESULTS+=("plugin.json: valid")
  else
    echo "[FAIL] plugin.json is not valid JSON"
    ((TOTAL_FAIL++))
    RESULTS+=("plugin.json: INVALID JSON")
  fi
fi

# --- marketplace.json validation ---
MJ="$REPO_ROOT/.claude-plugin/marketplace.json"
if [[ ! -f "$MJ" ]]; then
  echo "[FAIL] marketplace.json not found"
  ((TOTAL_FAIL++))
  RESULTS+=("marketplace.json: NOT FOUND")
else
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MJ" 2>/dev/null; then
    echo "[PASS] marketplace.json is valid JSON"
    ((TOTAL_PASS++))
    RESULTS+=("marketplace.json: valid")
  else
    echo "[FAIL] marketplace.json is not valid JSON"
    ((TOTAL_FAIL++))
    RESULTS+=("marketplace.json: INVALID JSON")
  fi
fi

# --- Referenced files exist ---
if [[ -f "$PJ" ]]; then
  MISSING=$(python3 -c "
import json, sys, os
d = json.load(open(sys.argv[1]))
root = sys.argv[2]
missing = []
for ref in d.get('commands', []) + d.get('skills', []):
    path = os.path.join(root, ref.replace('./', ''))
    kind = 'file' if ref.endswith('.md') else 'dir'
    if kind == 'file' and not os.path.isfile(path):
        missing.append(ref)
    elif kind == 'dir' and not os.path.isdir(path):
        missing.append(ref)
for m in missing:
    print(m)
" "$PJ" "$REPO_ROOT" 2>/dev/null || true)

  if [[ -z "$MISSING" ]]; then
    echo "[PASS] All plugin.json references resolve"
    ((TOTAL_PASS++))
    RESULTS+=("references: all resolve")
  else
    echo "[FAIL] Missing references in plugin.json:"
    echo "$MISSING" | sed 's/^/  /'
    ((TOTAL_FAIL++))
    RESULTS+=("references: MISSING")
  fi
fi

# --- README line count ---
README="$REPO_ROOT/README.md"
if [[ -f "$README" ]]; then
  LINES=$(wc -l < "$README" | tr -d ' ')
  if [[ "$LINES" -le 300 ]]; then
    echo "[PASS] README is $LINES lines (<= 300)"
    ((TOTAL_PASS++))
    RESULTS+=("README: ${LINES} lines")
  else
    echo "[FAIL] README is $LINES lines (max 300)"
    ((TOTAL_FAIL++))
    RESULTS+=("README: ${LINES} lines (OVER LIMIT)")
  fi
else
  echo "[FAIL] README.md not found"
  ((TOTAL_FAIL++))
  RESULTS+=("README: NOT FOUND")
fi

# --- CHANGELOG version ---
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
if [[ -f "$CHANGELOG" && -f "$PJ" ]]; then
  PLUGIN_VER=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$PJ")
  CHANGELOG_VER=$(grep -m1 '## v' "$CHANGELOG" | sed 's/## v\([0-9.]*\).*/\1/')
  if [[ "$PLUGIN_VER" == "$CHANGELOG_VER" ]]; then
    echo "[PASS] Version match: plugin.json=$PLUGIN_VER changelog=$CHANGELOG_VER"
    ((TOTAL_PASS++))
    RESULTS+=("version: $PLUGIN_VER")
  else
    echo "[FAIL] Version mismatch: plugin.json=$PLUGIN_VER changelog=$CHANGELOG_VER"
    ((TOTAL_FAIL++))
    RESULTS+=("version: MISMATCH")
  fi
fi

# --- Summary ---
echo ""
echo "=== Summary ==="
echo "PASS: $TOTAL_PASS"
echo "FAIL: $TOTAL_FAIL"
echo ""

if [[ $TOTAL_FAIL -eq 0 ]]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks failed. Fix above issues before committing."
  exit 1
fi
