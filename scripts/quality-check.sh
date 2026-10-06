#!/usr/bin/env bash
# quality-check.sh — Master validation script for Temper
# Runs all validation checks. Offline-safe, no network calls.
# Must complete in under 30 seconds.
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required but not found in PATH"; exit 1; }

# With CDPATH set, cd prints the folder it enters, and the path below would hold it twice.
unset CDPATH
# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${HERE%/scripts}"
[[ "$REPO_ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
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
# Each reference must be a plain name directly in its folder (no '/', no '..'): a .md file in
# commands or agents, a folder in skills. Anything else is reported, never looked up.
if [[ -f "$PJ" ]]; then
  MISSING=$(python3 -c "
import json, sys, os, re
d = json.load(open(sys.argv[1]))
root = sys.argv[2]
missing = []
for key, prefix, pattern, isfile in (('commands', './commands/', r'[a-z0-9-]+\.md', True),
                                     ('skills', './skills/', r'[a-z0-9-]+', False),
                                     ('agents', './agents/', r'[a-z0-9-]+\.md', True)):
    for ref in d.get(key, []):
        name = ref[len(prefix):] if isinstance(ref, str) and ref.startswith(prefix) else ''
        if not re.fullmatch(pattern, name):
            missing.append(str(ref) + ' (not a plain name in the ' + key + ' folder)')
            continue
        path = os.path.join(root, key, name)
        if (isfile and not os.path.isfile(path)) or (not isfile and not os.path.isdir(path)):
            missing.append(ref)
for m in missing:
    print(m)
" "$PJ" "$REPO_ROOT" 2>/dev/null || echo "(the reference check could not run)")

  if [[ -z "$MISSING" ]]; then
    echo "[PASS] All plugin.json references resolve"
    PASS=$((PASS+1))
  else
    echo "[FAIL] Missing references in plugin.json:"
    echo "$MISSING" | sed 's/^/  /'
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

# --- README version badge ---
if [[ -f "$README" && -f "$PJ" ]]; then
  PLUGIN_VER=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$PJ")
  if grep -qF "img.shields.io/badge/version-v${PLUGIN_VER}-" "$README"; then
    echo "[PASS] README version badge shows v$PLUGIN_VER"
    PASS=$((PASS+1))
  else
    echo "[FAIL] README version badge does not show v$PLUGIN_VER (scripts/version-bump.sh updates it)"
    FAIL=$((FAIL+1))
  fi
fi

# --- Panel validation (every stage brief: the one-closed-panel rule; every brief and
# command file listed in plugin.json) ---
if python3 "$REPO_ROOT/scripts/validate-panels.py" >/dev/null 2>&1; then
  echo "[PASS] Every stage brief shows one closed panel, and plugin.json lists every brief and command"
  PASS=$((PASS+1))
else
  echo "[FAIL] Panel or plugin.json listing violations:"
  python3 "$REPO_ROOT/scripts/validate-panels.py" 2>/dev/null | grep '^FAIL' | sed 's/^/  /'
  FAIL=$((FAIL+1))
fi

# --- Directory readiness (README without raw HTML, no assets folder path, manifests) ---
if bash "$REPO_ROOT/scripts/validate-directory.sh" >/dev/null 2>&1; then
  echo "[PASS] Directory readiness (scripts/validate-directory.sh)"
  PASS=$((PASS+1))
else
  echo "[FAIL] Directory readiness:"
  bash "$REPO_ROOT/scripts/validate-directory.sh" 2>&1 | sed 's/^/  /'
  FAIL=$((FAIL+1))
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
