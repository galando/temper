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

  # Check agent paths resolve + carry required frontmatter (name, model)
  AGENT_COUNT=$(python3 -c "
import json, sys, os, re
d = json.load(open(sys.argv[1]))
agents = d.get('agents', [])
for a in agents:
    path = os.path.join(sys.argv[2], a.replace('./', ''))
    if not os.path.isfile(path):
        print(f'FAIL: agent path does not exist: {a}', file=sys.stderr)
        continue
    text = open(path).read()
    if not re.match(r'^---\n.*?\bname:.*?\bmodel:.*?\n---', text, re.S):
        print(f'FAIL: agent missing name/model frontmatter: {a}', file=sys.stderr)
print(len(agents))
" "$PJ" "$REPO_ROOT" 2>&1)

  AGENT_ERRORS=$(echo "$AGENT_COUNT" | grep "^FAIL:" || true)
  if [[ -n "$AGENT_ERRORS" ]]; then
    fail "agent paths/frontmatter invalid"
    echo "$AGENT_ERRORS"
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

  # --- Version-agreement checks (G-1, G-2) ---
  # plugin.json is the single source of truth; every other LIVE stamp must agree.
  # .cursor/ is archived (v7+, see .cursor/README.md) — no longer regenerated per
  # release, so it is intentionally NOT version-checked against plugin.json here.

  # .claude/CLAUDE.md  **Version:** X.Y.Z  == plugin.json (G-1 guard, SC-1)
  CLAUDE_MD="$REPO_ROOT/.claude/CLAUDE.md"
  if [[ -f "$CLAUDE_MD" ]]; then
    CLAUDE_VER=$(grep -m1 -E '^\*\*Version:\*\*' "$CLAUDE_MD" | sed -E 's/^\*\*Version:\*\* ([0-9][0-9.]*(\.[0-9]+)*).*/\1/')
    if [[ -z "$CLAUDE_VER" ]]; then
      fail ".claude/CLAUDE.md has no '**Version:**' stamp"
    elif [[ "$CLAUDE_VER" != "$PLUGIN_VER" ]]; then
      fail ".claude/CLAUDE.md Version ($CLAUDE_VER) != plugin.json ($PLUGIN_VER)"
    else
      ok
    fi
  else
    fail ".claude/CLAUDE.md missing"
  fi

  # commands/temper.md title header (vX.Y.Z) == plugin.json (G-1 guard)
  TEMPER_CMD="$REPO_ROOT/commands/temper.md"
  if [[ -f "$TEMPER_CMD" ]]; then
    TEMPER_VER=$(grep -m1 -E '^# Temper:.*\(v[0-9]' "$TEMPER_CMD" | sed -E 's/.*\(v([0-9][0-9.]*(\.[0-9]+)*)\).*/\1/')
    if [[ -z "$TEMPER_VER" ]]; then
      fail "commands/temper.md has no title-line '(vX.Y.Z)' header"
    elif [[ "$TEMPER_VER" != "$PLUGIN_VER" ]]; then
      fail "commands/temper.md header ($TEMPER_VER) != plugin.json ($PLUGIN_VER)"
    else
      ok
    fi
  else
    fail "commands/temper.md missing"
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

# --- Phase 1 Verification (v5.5.0): eval + hooks assertions ---
# These cover the new files added by docs/plans/phase-1-verification.md.

# Hooks pack: rules.md present + settings.hooks.json valid JSON
HOOKS_RULES="$REPO_ROOT/packs/hooks/rules.md"
if [[ -f "$HOOKS_RULES" ]]; then ok; else fail "packs/hooks/rules.md missing"; fi

HOOKS_JSON="$REPO_ROOT/packs/hooks/settings.hooks.json"
if [[ -f "$HOOKS_JSON" ]]; then
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$HOOKS_JSON" 2>/dev/null; then
    ok
  else
    fail "packs/hooks/settings.hooks.json is not valid JSON"
  fi
  # Regression guard (C-1): Claude Code has NO PreCommit event — a PreCommit key is
  # silently ignored and defeats the deterministic commit guarantee. The commit gate
  # must be the native git pre-commit hook installed by scripts/hooks/install.sh.
  if python3 -c "import json,sys; assert 'PreCommit' not in json.load(open(sys.argv[1])).get('hooks', {})" "$HOOKS_JSON" 2>/dev/null; then
    ok
  else
    fail "packs/hooks/settings.hooks.json uses invalid 'PreCommit' key (use scripts/hooks/install.sh for commit-time enforcement)"
  fi
else
  fail "packs/hooks/settings.hooks.json missing"
fi

# Hook scripts: exist and are executable
for sh in block-secrets.sh block-forbidden-imports.sh block-uncommitted-gate.sh verify-tests-ran.sh install.sh; do
  p="$REPO_ROOT/scripts/hooks/$sh"
  if [[ ! -f "$p" ]]; then
    fail "scripts/hooks/$sh missing"
  elif [[ ! -x "$p" ]]; then
    fail "scripts/hooks/$sh not executable (chmod +x)"
  else
    ok
  fi
done

# --- The temper CLI (v7): the deterministic spine every gate resolves through ---
TEMPER_CLI="$REPO_ROOT/scripts/temper"
if [[ ! -f "$TEMPER_CLI" ]]; then
  fail "scripts/temper missing"
elif [[ ! -x "$TEMPER_CLI" ]]; then
  fail "scripts/temper not executable (chmod +x)"
else
  ok
fi
if [[ -f "$REPO_ROOT/scripts/tests/test-temper.sh" ]]; then ok; else fail "scripts/tests/test-temper.sh missing"; fi

# Evalset template
if [[ -f "$REPO_ROOT/templates/evalset.json" ]]; then
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$REPO_ROOT/templates/evalset.json" 2>/dev/null; then
    ok
  else
    fail "templates/evalset.json is not valid JSON"
  fi
else
  fail "templates/evalset.json missing"
fi

# Cursor parity: derived eval command + rules + hooks pack rule exist (generator output)
for cf in .cursor/commands/temper-eval.md .cursor/rules/temper-ref-eval.mdc .cursor/rules/temper-pack-hooks.mdc; do
  if [[ -f "$REPO_ROOT/$cf" ]]; then ok; else fail "$cf missing (run scripts/generate-cursor.sh)"; fi
done

# Cursor parity: the eval reference rule carries the current version in its frozen-note
# source path (extends the G-2 derived-content pattern to the new reference).
EVAL_RULE="$REPO_ROOT/.cursor/rules/temper-ref-eval.mdc"
if [[ -f "$EVAL_RULE" ]]; then
  if grep -q "Source: reference/eval.md" "$EVAL_RULE" 2>/dev/null; then
    ok
  else
    fail ".cursor/rules/temper-ref-eval.mdc source path mismatch"
  fi
fi

# --- Eval fixtures (v7 — Move 3, docs/plans/v7-deterministic-spine.md) ---
for h in evals/run-fixture.sh evals/run-all.sh evals/run-wiring-smoke.sh; do
  p="$REPO_ROOT/$h"
  if [[ ! -f "$p" ]]; then fail "$h missing"
  elif [[ ! -x "$p" ]]; then fail "$h not executable (chmod +x)"
  else ok; fi
done
FIXTURE_COUNT=0
for fdir in "$REPO_ROOT"/evals/fixtures/*/; do
  [[ -d "$fdir" ]] || continue
  name="$(basename "$fdir")"
  FIXTURE_COUNT=$((FIXTURE_COUNT + 1))
  for required in expect.json SEEDED_DEFECT.md; do
    if [[ -f "$fdir$required" ]]; then ok; else fail "evals/fixtures/$name/$required missing"; fi
  done
  if [[ -f "$fdir/expect.json" ]]; then
    if python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert 'stage' in d and 'command' in d and 'anchor_keywords' in d and 'signal_keywords' in d
" "$fdir/expect.json" 2>/dev/null; then ok; else fail "evals/fixtures/$name/expect.json missing required keys (stage/command/anchor_keywords/signal_keywords)"; fi
  fi
done
if [[ "$FIXTURE_COUNT" -ge 1 ]]; then ok; else fail "no eval fixtures found under evals/fixtures/"; fi

# wiring-smoke is a different fixture shape (no seeded defect, no expect.json) —
# checked separately rather than folded into the loop above.
WIRING_DIR="$REPO_ROOT/evals/wiring-smoke"
if [[ -d "$WIRING_DIR" ]]; then
  for required in package.json src/app.js test/app.test.js WIRING_CHECK.md; do
    if [[ -f "$WIRING_DIR/$required" ]]; then ok; else fail "evals/wiring-smoke/$required missing"; fi
  done
else
  fail "evals/wiring-smoke/ missing"
fi

echo ""
echo "=== validate-plugin.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
