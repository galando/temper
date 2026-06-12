#!/usr/bin/env bash
# validate-plugin.sh — Validate plugin.json and marketplace.json structure
# Offline-safe, no network calls, completes in seconds.
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required but not found in PATH"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# --- plugin.json ---
PJ="$REPO_ROOT/.claude-plugin/plugin.json"
if [[ ! -f "$PJ" ]]; then
  fail "plugin.json not found at .claude-plugin/plugin.json"
else
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PJ" 2>/dev/null; then
    fail "plugin.json is not valid JSON"
  else
    ok
  fi

  # Check required keys
  for key in name version description commands skills; do
    if ! python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert '$key' in d, 'missing $key'" "$PJ" 2>/dev/null; then
      fail "plugin.json missing required key: $key"
    else
      ok
    fi
  done

  # Check command paths resolve
  CMD_COUNT=$(python3 -c "
import json, sys, os
d = json.load(open(sys.argv[1]))
cmds = d.get('commands', [])
missing = [c for c in cmds if not os.path.isfile(os.path.join(sys.argv[2], c.replace('./', '')))]
print(len(cmds) - len(missing))
for m in missing:
    print(f'FAIL: command path does not exist: {m}', file=sys.stderr)
" "$PJ" "$REPO_ROOT" 2>&1)

  CMD_ERRORS=$(echo "$CMD_COUNT" | grep "^FAIL:" || true)
  CMD_OK=$(echo "$CMD_COUNT" | head -1)
  if [[ -n "$CMD_ERRORS" ]]; then
    fail "command paths missing"
    echo "$CMD_ERRORS"
  else
    ok
  fi

  # Check skill paths resolve
  SKILL_COUNT=$(python3 -c "
import json, sys, os
d = json.load(open(sys.argv[1]))
skills = d.get('skills', [])
missing = [s for s in skills if not os.path.isdir(os.path.join(sys.argv[2], s.replace('./', '')))]
print(len(skills) - len(missing))
for m in missing:
    print(f'FAIL: skill path does not exist: {m}', file=sys.stderr)
" "$PJ" "$REPO_ROOT" 2>&1)

  SKILL_ERRORS=$(echo "$SKILL_COUNT" | grep "^FAIL:" || true)
  if [[ -n "$SKILL_ERRORS" ]]; then
    fail "skill paths missing"
    echo "$SKILL_ERRORS"
  else
    ok
  fi

  # Check version matches CHANGELOG latest
  PLUGIN_VER=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$PJ")
  CHANGELOG_VER=$(grep -m1 '## v' "$REPO_ROOT/CHANGELOG.md" | sed 's/## v\([0-9.]*\).*/\1/')
  if [[ "$PLUGIN_VER" != "$CHANGELOG_VER" ]]; then
    fail "plugin.json version ($PLUGIN_VER) != CHANGELOG latest ($CHANGELOG_VER)"
  else
    ok
  fi
fi

# --- marketplace.json ---
MJ="$REPO_ROOT/.claude-plugin/marketplace.json"
if [[ ! -f "$MJ" ]]; then
  fail "marketplace.json not found at .claude-plugin/marketplace.json"
else
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MJ" 2>/dev/null; then
    fail "marketplace.json is not valid JSON"
  else
    ok
  fi

  for key in name owner plugins; do
    if ! python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert '$key' in d, 'missing $key'" "$MJ" 2>/dev/null; then
      fail "marketplace.json missing required key: $key"
    else
      ok
    fi
  done
fi

echo ""
echo "=== validate-plugin.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
