#!/usr/bin/env bash
# validate-plugin.sh — Validate plugin.json and marketplace.json structure
# Offline-safe, no network calls, completes in seconds.
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required but not found in PATH"; exit 1; }

# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${HERE%/scripts}"
[[ "$REPO_ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
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

  # Check command paths resolve. Each entry must name one .md file directly in the commands
  # folder by a plain name (no '/', no '..'), so nothing outside that folder is opened.
  CMD_COUNT=$(python3 -c "
import json, sys, os, re
d = json.load(open(sys.argv[1]))
cmds = d.get('commands', [])
PRE = './commands/'
bad = [c for c in cmds if not (isinstance(c, str) and c.startswith(PRE) and re.fullmatch(r'[a-z0-9-]+\.md', c[len(PRE):]))]
missing = [c for c in cmds if c not in bad and not os.path.isfile(os.path.join(sys.argv[2], 'commands', c[len(PRE):]))]
print(len(cmds) - len(missing) - len(bad))
for b in bad:
    print(f'FAIL: command path is not a plain .md name in the commands folder: {b}', file=sys.stderr)
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

  # Check skill paths resolve. Each entry must name one folder directly in the skills folder.
  SKILL_COUNT=$(python3 -c "
import json, sys, os, re
d = json.load(open(sys.argv[1]))
skills = d.get('skills', [])
PRE = './skills/'
bad = [s for s in skills if not (isinstance(s, str) and s.startswith(PRE) and re.fullmatch(r'[a-z0-9-]+', s[len(PRE):]))]
missing = [s for s in skills if s not in bad and not os.path.isdir(os.path.join(sys.argv[2], 'skills', s[len(PRE):]))]
print(len(skills) - len(missing) - len(bad))
for b in bad:
    print(f'FAIL: skill path is not a plain folder name in the skills folder: {b}', file=sys.stderr)
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

  # Check agent paths resolve + carry required frontmatter (name, model; effort valid if set) + a Gotchas section.
  # Each entry must name one .md file directly in the agents folder, so only a stage brief is opened.
  AGENT_COUNT=$(python3 -c "
import json, sys, os, re
d = json.load(open(sys.argv[1]))
agents = d.get('agents', [])
PRE = './agents/'
for a in agents:
    if not (isinstance(a, str) and a.startswith(PRE) and re.fullmatch(r'[a-z0-9-]+\.md', a[len(PRE):])):
        print(f'FAIL: agent path is not a plain .md name in the agents folder: {a}', file=sys.stderr)
        continue
    path = os.path.join(sys.argv[2], 'agents', a[len(PRE):])
    if not os.path.isfile(path):
        print(f'FAIL: agent path does not exist: {a}', file=sys.stderr)
        continue
    text = open(path).read()
    if not re.match(r'^---\n.*?\bname:.*?\bmodel:.*?\n---', text, re.S):
        print(f'FAIL: agent missing name/model frontmatter: {a}', file=sys.stderr)
    # effort (optional) must be a level Claude Code accepts; every brief carries Gotchas
    m = re.match(r'^---\n(.*?)\n---', text, re.S)
    e = re.search(r'^effort:\s*(\S+)\s*$', m.group(1), re.M) if m else None
    if e and e.group(1) not in ('low', 'medium', 'high', 'xhigh', 'max'):
        print(f'FAIL: agent has invalid effort {e.group(1)!r}: {a}', file=sys.stderr)
    if '**Gotchas**' not in text:
        print(f'FAIL: agent has no **Gotchas** section: {a}', file=sys.stderr)
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

  # commands/temper.md no longer carries a version tag in its title — prompt
  # files hold rules, not version history (the tag was removed with the rest of
  # the version-relative prompt text), so there is no stamp left to compare.
  # plugin.json and .claude/CLAUDE.md remain the live stamps.
  TEMPER_CMD="$REPO_ROOT/commands/temper.md"
  [[ -f "$TEMPER_CMD" ]] || fail "commands/temper.md missing"
fi

# --- Mods support (v9.5): the module is additive and must never stop the plugin loading ---
# A userConfig field that declares "options" stops the WHOLE plugin loading on Claude Code before
# 2.1.271, so fields stay plain strings and the module validates values in code. The plugin's hook
# wiring and the module it loads are checked by `claude plugin validate --strict` (CI runs it); this
# block opens only plugin.json, and the types entry is compared as text with its one fixed path.
if [[ -f "$PJ" ]]; then
  MOD_ERRS=$(python3 -c "
import json, sys, os
root = sys.argv[1]
pj = json.load(open(os.path.join(root, '.claude-plugin', 'plugin.json')))
errs = []
for name, field in (pj.get('userConfig') or {}).items():
    if 'options' in field:
        errs.append('userConfig.' + name + ' declares options (breaks loading before 2.1.271)')
t = pj.get('types')
if t is not None and t != './types/index.d.ts':
    errs.append('plugin.json types is not ./types/index.d.ts: ' + str(t))
elif t is not None and not os.path.isfile(os.path.join(root, 'types', 'index.d.ts')):
    errs.append('plugin.json types path does not exist: ' + t)
print('; '.join(errs))
" "$REPO_ROOT" 2>/dev/null || echo "mods check could not run")
  if [[ -z "$MOD_ERRS" ]]; then ok; else fail "mods support: $MOD_ERRS"; fi
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

# --- Pack `phases:` frontmatter (v8) ---
# Every built-in pack declares which stages load it. This validates the declaration is
# present and its values are real phases; it cannot tell you a pack was narrowed too far
# — that's a reading of the stage docs, not a property of the file. `all` loads
# everywhere, `[]` loads nowhere (packs/guardrails, whose content is install documentation).
# The built-in packs are named once in PACKS below. git ls-files only tells which packs carry a
# rules.md, so a new pack that is missing from PACKS fails instead of going unchecked.
PACK_PHASES_ERR=$( (cd "$REPO_ROOT" && git ls-files -- packs 2>/dev/null || true) | python3 -c "
import os, re, sys
PACKS = ('api-design', 'architecture-depth', 'git', 'guardrails', 'performance', 'quality', 'security', 'tdd')
VALID = {'plan', 'design', 'build', 'review', 'check', 'fix'}
errs = []
tracked = set()
for line in sys.stdin:
    parts = line.rstrip('\n').split('/')
    if len(parts) == 3 and parts[0] == 'packs' and parts[2] == 'rules.md':
        tracked.add(parts[1])
for name in sorted(tracked - set(PACKS)):
    errs.append(f'{name}: has a rules.md but is not in the PACKS list of scripts/validate-plugin.sh')
for name in PACKS:
    path = os.path.join(sys.argv[1], 'packs', name, 'rules.md')
    if not os.path.isfile(path):
        errs.append('the ' + name + ' pack has no rules.md')
        continue
    m = re.match(r'---\n(.*?)\n---\n', open(path).read(), re.DOTALL)
    if not m:
        errs.append(f'{name}: no frontmatter (expected a phases: block)')
        continue
    pm = re.search(r'^phases:[ \t]*(.+)$', m.group(1), re.MULTILINE)
    if not pm:
        errs.append(f'{name}: frontmatter has no phases: key')
        continue
    raw = pm.group(1).strip()
    if raw == 'all':
        continue
    if not (raw.startswith('[') and raw.endswith(']')):
        errs.append(f'{name}: phases must be \'all\' or a [list], got {raw!r}')
        continue
    bad = [p for p in (x.strip() for x in raw[1:-1].split(',')) if p and p not in VALID]
    if bad:
        errs.append(f'{name}: unknown phase(s) {bad} (valid: {sorted(VALID)})')
print('; '.join(errs))
" "$REPO_ROOT" 2>/dev/null)
if [[ -z "$PACK_PHASES_ERR" ]]; then ok; else fail "pack phases: $PACK_PHASES_ERR"; fi

# --- Phase 1 Verification (v5.5.0): guard script assertions ---
# These cover the new files added by docs/plans/phase-1-verification.md.

# guardrails pack: rules.md present + settings-guardrails.json valid JSON
GUARDRAILS_RULES="$REPO_ROOT/packs/guardrails/rules.md"
if [[ -f "$GUARDRAILS_RULES" ]]; then ok; else fail "packs/guardrails/rules.md missing"; fi

GUARDRAILS_JSON="$REPO_ROOT/packs/guardrails/settings-guardrails.json"
if [[ -f "$GUARDRAILS_JSON" ]]; then
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$GUARDRAILS_JSON" 2>/dev/null; then
    ok
  else
    fail "packs/guardrails/settings-guardrails.json is not valid JSON"
  fi
  # Regression guard (C-1): Claude Code has NO PreCommit event — a PreCommit key is
  # silently ignored and defeats the deterministic commit guarantee. The commit gate
  # must be the native git pre-commit hook installed by scripts/guards/install.sh.
  if python3 -c "import json,sys; assert 'PreCommit' not in json.load(open(sys.argv[1])).get('hooks', {})" "$GUARDRAILS_JSON" 2>/dev/null; then
    ok
  else
    fail "packs/guardrails/settings-guardrails.json uses invalid 'PreCommit' key (use scripts/guards/install.sh for commit-time enforcement)"
  fi
else
  fail "packs/guardrails/settings-guardrails.json missing"
fi

# The standalone-stage gate guarantee (v8.0.1) ships with the plugin, so --plugin-dir and
# marketplace installs get it without a settings.json merge. `claude plugin validate --strict`
# checks that wiring in CI; the two scripts it runs (stage-marker.sh and verify-stage-gate.sh) are
# in the list below.

# Guard scripts: exist and are executable. Each path is written out in full.
for p in \
  "$REPO_ROOT/scripts/guards/block-secrets.sh" \
  "$REPO_ROOT/scripts/guards/block-forbidden-imports.sh" \
  "$REPO_ROOT/scripts/guards/block-uncommitted-gate.sh" \
  "$REPO_ROOT/scripts/guards/verify-tests-ran.sh" \
  "$REPO_ROOT/scripts/guards/install.sh" \
  "$REPO_ROOT/scripts/guards/stage-marker.sh" \
  "$REPO_ROOT/scripts/guards/verify-stage-gate.sh"; do
  name="scripts/guards/$(basename "$p")"
  if [[ ! -f "$p" ]]; then
    fail "$name missing"
  elif [[ ! -x "$p" ]]; then
    fail "$name not executable (chmod +x)"
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

# --- pack-discover.py (v8): /temper:pack's Step 5a discovery scan, extracted from a
# prompt-embedded script into a testable one ---
PACK_DISCOVER="$REPO_ROOT/scripts/pack-discover.py"
if [[ ! -f "$PACK_DISCOVER" ]]; then
  fail "scripts/pack-discover.py missing"
elif ! python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" "$PACK_DISCOVER" 2>/dev/null; then
  fail "scripts/pack-discover.py has a syntax error"
else
  ok
fi

echo ""
echo "=== validate-plugin.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
