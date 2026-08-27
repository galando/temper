#!/usr/bin/env bash
# quality-check.sh — Master validation script for Temper
# Runs all validation checks. Offline-safe, no network calls.
# Must complete in under 30 seconds.
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required but not found in PATH"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

echo "=== Temper Quality Check ==="
echo "Repo: $REPO_ROOT"
echo ""

# --- plugin.json validation ---
PJ="$REPO_ROOT/.claude-plugin/plugin.json"
if [[ ! -f "$PJ" ]]; then
  echo "[FAIL] plugin.json not found"
  FAIL=$((FAIL+1))
else
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PJ" 2>/dev/null; then
    echo "[PASS] plugin.json is valid JSON"
    PASS=$((PASS+1))
  else
    echo "[FAIL] plugin.json is not valid JSON"
    FAIL=$((FAIL+1))
  fi
fi

# --- marketplace.json validation ---
MJ="$REPO_ROOT/.claude-plugin/marketplace.json"
if [[ ! -f "$MJ" ]]; then
  echo "[FAIL] marketplace.json not found"
  FAIL=$((FAIL+1))
else
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MJ" 2>/dev/null; then
    echo "[PASS] marketplace.json is valid JSON"
    PASS=$((PASS+1))
  else
    echo "[FAIL] marketplace.json is not valid JSON"
    FAIL=$((FAIL+1))
  fi
fi

# --- Referenced files exist ---
if [[ -f "$PJ" ]]; then
  MISSING=$(python3 -c "
import json, sys, os
d = json.load(open(sys.argv[1]))
root = sys.argv[2]
missing = []
for ref in d.get('commands', []) + d.get('skills', []) + d.get('agents', []):
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
    PASS=$((PASS+1))
  else
    echo "[FAIL] Missing references in plugin.json:"
    echo "$MISSING" | sed 's/^/  /'
    FAIL=$((FAIL+1))
  fi
fi

# --- Multi-agent surface (v9.3.0) ---
# Manifests for several agents over ONE source tree. The only thing that can rot here
# is agreement, so that is what this checks; validate-plugin.sh carries the full
# parity assertions (component coverage, Gemini shims, skill frontmatter).
for m in plugin.json .claude-plugin/plugin.json .cursor-plugin/plugin.json \
         .codex-plugin/plugin.json .agents/plugins/marketplace.json; do
  MP="$REPO_ROOT/$m"
  if [[ ! -f "$MP" ]]; then
    echo "[FAIL] $m not found"
    FAIL=$((FAIL+1))
  elif ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MP" 2>/dev/null; then
    echo "[FAIL] $m is not valid JSON"
    FAIL=$((FAIL+1))
  else
    PASS=$((PASS+1))
  fi
done
echo "[PASS] All agent manifests are valid JSON"

if [[ -f "$PJ" ]]; then
  DRIFT=$(python3 -c "
import json, sys
root = sys.argv[1]
def ver(p):
    d = json.load(open(f'{root}/{p}'))
    return d.get('version') or (d.get('plugins') or [{}])[0].get('version')
base = ver('.claude-plugin/plugin.json')
bad = [p for p in ['plugin.json', '.cursor-plugin/plugin.json', '.codex-plugin/plugin.json',
                   '.agents/plugins/marketplace.json'] if ver(p) != base]
print(' '.join(bad))
" "$REPO_ROOT" 2>/dev/null)
  if [[ -z "$DRIFT" ]]; then
    echo "[PASS] All agent manifests agree on the version"
    PASS=$((PASS+1))
  else
    echo "[FAIL] Manifest version drift in:$DRIFT"
    FAIL=$((FAIL+1))
  fi
fi

# --- README line count ---
README="$REPO_ROOT/README.md"
if [[ -f "$README" ]]; then
  LINES=$(wc -l < "$README" | tr -d ' ')
  if [[ "$LINES" -le 300 ]]; then
    echo "[PASS] README is $LINES lines (<= 300)"
    PASS=$((PASS+1))
  else
    echo "[FAIL] README is $LINES lines (max 300)"
    FAIL=$((FAIL+1))
  fi
else
  echo "[FAIL] README.md not found"
  FAIL=$((FAIL+1))
fi

# --- CHANGELOG version ---
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
if [[ -f "$CHANGELOG" && -f "$PJ" ]]; then
  PLUGIN_VER=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$PJ")
  CHANGELOG_VER=$(grep -m1 '## v' "$CHANGELOG" | sed 's/## v\([0-9.]*\).*/\1/')
  if [[ "$PLUGIN_VER" == "$CHANGELOG_VER" ]]; then
    echo "[PASS] Version match: plugin.json=$PLUGIN_VER changelog=$CHANGELOG_VER"
    PASS=$((PASS+1))
  else
    echo "[FAIL] Version mismatch: plugin.json=$PLUGIN_VER changelog=$CHANGELOG_VER"
    FAIL=$((FAIL+1))
  fi
fi

# --- Summary ---
echo ""
echo "=== Summary ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks failed. Fix above issues before committing."
  exit 1
fi
