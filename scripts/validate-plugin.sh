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

# --- Cursor surface (v9.2.0): .cursor-plugin/ manifests over the SAME source tree ---
# Temper shipped a generated `.cursor/` export once; a generator bug froze it three
# majors behind and it was removed rather than keep misrepresenting what Cursor users
# got (CHANGELOG v9.0.0). The replacement is a second MANIFEST, not a second copy — so
# the check that matters here is parity: every command, agent and skill the Claude
# manifest declares must be reachable through the Cursor manifest's paths, and both
# manifests must carry the same version. Drift is a FAIL, not a warning.
CPJ="$REPO_ROOT/.cursor-plugin/plugin.json"
CMJ="$REPO_ROOT/.cursor-plugin/marketplace.json"
if [[ ! -f "$CPJ" ]]; then
  fail ".cursor-plugin/plugin.json not found (Cursor surface)"
elif ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$CPJ" 2>/dev/null; then
  fail ".cursor-plugin/plugin.json is not valid JSON"
else
  ok
  # Cursor's schema: name is required and kebab-case; components are path/glob strings
  # or arrays of them (not the Claude manifest's per-file arrays).
  CURSOR_ERR=$(python3 -c "
import json, os, re, sys
root = sys.argv[3]
c = json.load(open(sys.argv[1]))
errs = []
name = c.get('name', '')
if not re.fullmatch(r'[a-z0-9]([a-z0-9.-]*[a-z0-9])?', name or ''):
    errs.append(f'name {name!r} is not kebab-case (Cursor plugin schema)')
for key in ('version', 'description'):
    if not c.get(key):
        errs.append(f'missing {key}')
def paths(v):
    if v is None: return []
    return [v] if isinstance(v, str) else list(v)
for key in ('commands', 'agents', 'skills'):
    vals = paths(c.get(key))
    if not vals:
        errs.append(f'declares no {key}')
    for v in vals:
        p = os.path.join(root, v.lstrip('./'))
        if '*' not in v and not os.path.exists(p):
            errs.append(f'{key} path does not exist: {v}')
h = c.get('hooks')
if isinstance(h, str) and not os.path.isfile(os.path.join(root, h.lstrip('./'))):
    errs.append(f'hooks path does not exist: {h}')
# Version agreement with the Claude manifest — one plugin, one version.
cl = json.load(open(sys.argv[2]))
if c.get('name') != cl.get('name'):
    errs.append(f\"name {c.get('name')!r} != .claude-plugin/plugin.json {cl.get('name')!r}\")
# PARITY: every Claude-declared component is reachable through a Cursor path.
def covered(ref, decl):
    target = os.path.normpath(os.path.join(root, ref.lstrip('./')))
    for v in decl:
        base = os.path.normpath(os.path.join(root, v.split('*')[0].lstrip('./')))
        if target == base or target.startswith(base + os.sep):
            return True
    return False
for key in ('commands', 'agents', 'skills'):
    decl = paths(c.get(key))
    for ref in cl.get(key, []):
        if not covered(ref, decl):
            errs.append(f'{key} parity: {ref} is not reachable from the Cursor manifest')
print('; '.join(errs))
" "$CPJ" "$PJ" "$REPO_ROOT" 2>&1)
  if [[ -z "$CURSOR_ERR" ]]; then ok; else fail "cursor plugin.json: $CURSOR_ERR"; fi
fi

if [[ ! -f "$CMJ" ]]; then
  fail ".cursor-plugin/marketplace.json not found"
else
  CURSOR_MP_ERR=$(python3 -c "
import json, os, sys
m = json.load(open(sys.argv[1]))
errs = []
if not m.get('name'): errs.append('missing name')
if not isinstance(m.get('plugins'), list) or not m['plugins']:
    errs.append('missing or empty plugins array')
else:
    # Cursor's marketplace pluginEntry is additionalProperties:false — name, source,
    # description and minClientVersions only. Extra keys fail validation at install.
    allowed = {'name', 'source', 'description', 'minClientVersions'}
    for e in m['plugins']:
        extra = set(e) - allowed
        if extra: errs.append(f\"plugin entry {e.get('name')!r} has unsupported keys {sorted(extra)}\")
        for k in ('name', 'source'):
            if not e.get(k): errs.append(f'plugin entry missing {k}')
        src = e.get('source', '')
        if src and not src.startswith(('http://', 'https://')):
            if not os.path.isdir(os.path.join(sys.argv[2], src.lstrip('./') or '.')):
                errs.append(f'plugin source does not exist: {src}')
print('; '.join(errs))
" "$CMJ" "$REPO_ROOT" 2>&1)
  if [[ -z "$CURSOR_MP_ERR" ]]; then ok; else fail "cursor marketplace.json: $CURSOR_MP_ERR"; fi
fi

# Cursor hook configs: valid JSON, version 1, only real Cursor events, and every
# referenced hook script exists. A typo'd event name is silently ignored by Cursor —
# exactly the class of bug that froze the old export, so it fails here instead.
CURSOR_EVENTS="sessionStart sessionEnd preToolUse postToolUse postToolUseFailure subagentStart subagentStop beforeShellExecution afterShellExecution beforeMCPExecution afterMCPExecution beforeReadFile afterFileEdit beforeSubmitPrompt preCompact stop afterAgentResponse afterAgentThought"
for ch in hooks/cursor-hooks.json packs/hooks/cursor.hooks.json; do
  p="$REPO_ROOT/$ch"
  if [[ ! -f "$p" ]]; then
    fail "$ch missing (Cursor hook surface)"
    continue
  fi
  CH_ERR=$(CURSOR_EVENTS="$CURSOR_EVENTS" python3 -c "
import json, os, re, sys
valid = set(os.environ['CURSOR_EVENTS'].split())
errs = []
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f'not valid JSON: {e}'); sys.exit(0)
if d.get('version') != 1: errs.append(f\"version must be 1, got {d.get('version')!r}\")
hooks = d.get('hooks', {})
if not hooks: errs.append('declares no hooks')
for event, entries in hooks.items():
    if event not in valid: errs.append(f'unknown Cursor event {event!r}')
    for e in entries:
        cmd = e.get('command', '')
        if not cmd: errs.append(f'{event}: entry has no command')
        for ref in re.findall(r'scripts/hooks/[\w.-]+\.sh', cmd):
            if not os.path.isfile(os.path.join(sys.argv[2], ref)):
                errs.append(f'{event}: missing script {ref}')
        # Every rule must route through the adapter — a rule invoked directly would be
        # handed a Cursor payload it cannot read, and would answer with an exit code
        # Cursor ignores. Silent no-op, which is worse than a crash.
        if 'scripts/hooks/' in cmd and 'cursor-adapter.sh' not in cmd:
            errs.append(f'{event}: hook script invoked without cursor-adapter.sh')
print('; '.join(errs))
" "$p" "$REPO_ROOT" 2>&1)
  if [[ -z "$CH_ERR" ]]; then ok; else fail "$ch: $CH_ERR"; fi
done

# The adapter itself, and the portability contract every surface points at.
CURSOR_ADAPTER="$REPO_ROOT/scripts/hooks/cursor-adapter.sh"
if [[ ! -f "$CURSOR_ADAPTER" ]]; then
  fail "scripts/hooks/cursor-adapter.sh missing (Cursor hook translation)"
elif [[ ! -x "$CURSOR_ADAPTER" ]]; then
  fail "scripts/hooks/cursor-adapter.sh not executable (chmod +x)"
else
  ok
fi
for f in reference/portability.md templates/AGENTS.temper.md; do
  if [[ -f "$REPO_ROOT/$f" ]]; then ok; else fail "$f missing (multi-agent contract)"; fi
done

# --- Multi-agent surface (v9.3.0) ---
# Temper ships manifests for several agents over ONE source tree. Two failure modes are
# invisible without a check: a manifest left at an old version, and a per-agent surface
# that stops covering a command/skill someone added. Both are how the old generated
# `.cursor/` export rotted three majors deep before anyone noticed.
MANIFESTS="plugin.json .claude-plugin/plugin.json .cursor-plugin/plugin.json .codex-plugin/plugin.json .agents/plugins/marketplace.json"
for m in $MANIFESTS; do
  mp="$REPO_ROOT/$m"
  if [[ ! -f "$mp" ]]; then
    fail "$m missing (multi-agent manifest set)"
  elif ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$mp" 2>/dev/null; then
    fail "$m is not valid JSON"
  else
    MV=$(python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
print(d.get('version') or (d.get('plugins') or [{}])[0].get('version') or '')
" "$mp" 2>/dev/null)
    if [[ "$MV" == "$PLUGIN_VER" ]]; then ok; else fail "$m version ($MV) != .claude-plugin/plugin.json ($PLUGIN_VER)"; fi
  fi
done

# Every skill must carry BOTH name: and description:. The `skills` CLI that installs
# Temper into ~77 agents SILENTLY SKIPS a skill missing either — no error, the skill
# just never appears. Three of Temper's skills shipped that way until v9.3.0.
SKILL_FM_ERR=$(python3 -c "
import glob, os, re, sys
errs = []
paths = sorted(glob.glob(os.path.join(sys.argv[1], 'skills', '*', 'SKILL.md')))
if not paths:
    errs.append('no skills/*/SKILL.md found')
for path in paths:
    slug = os.path.basename(os.path.dirname(path))
    m = re.match(r'---\n(.*?)\n---\n', open(path).read(), re.DOTALL)
    if not m:
        errs.append(f'{slug}: no frontmatter'); continue
    fm = m.group(1)
    for key in ('name', 'description'):
        v = re.search(rf'^{key}:[ \t]*(.+)\$', fm, re.MULTILINE)
        if not v or not v.group(1).strip().strip('\"\\''):
            errs.append(f'{slug}: frontmatter missing {key}: (the skills CLI skips this skill silently)')
    n = re.search(r'^name:[ \t]*(.+)\$', fm, re.MULTILINE)
    if n and n.group(1).strip().strip('\"\\'') != slug:
        errs.append(f'{slug}: frontmatter name ({n.group(1).strip()}) != directory name')
print('; '.join(errs))
" "$REPO_ROOT" 2>&1)
if [[ -z "$SKILL_FM_ERR" ]]; then ok; else fail "skill frontmatter: $SKILL_FM_ERR"; fi

# OpenCode discovers .opencode/skills; it must be a SYMLINK to skills/, never a copy.
OC="$REPO_ROOT/.opencode/skills"
if [[ ! -L "$OC" ]]; then
  fail ".opencode/skills must be a symlink to ../skills/ (a copy would drift)"
elif [[ ! -d "$OC" ]]; then
  fail ".opencode/skills symlink is broken"
else
  ok
fi

# Gemini CLI command parity. Each commands/*.md needs a .gemini/commands shim whose
# description matches its frontmatter — and the shim must POINT at the .md, never
# restate it. A shim that grew a prompt body is a second copy waiting to drift.
GEMINI_ERR=$(python3 -c "
import glob, os, re, sys
root = sys.argv[1]
errs = []

def md_desc(path):
    m = re.match(r'---\n(.*?)\n---\n', open(path).read(), re.DOTALL)
    if not m: return None
    d = re.search(r'^description:[ \t]*(.+)\$', m.group(1), re.MULTILINE)
    return d.group(1).strip().strip('\"\\'') if d else None

def toml_desc(text):
    d = re.search(r'^description\s*=\s*\"((?:[^\"\\\\]|\\\\.)*)\"', text, re.MULTILINE)
    return d.group(1).replace('\\\\\"', '\"') if d else None

for path in sorted(glob.glob(os.path.join(root, 'commands', '*.md'))):
    stem = os.path.basename(path)[:-3]
    shim = os.path.join(root, '.gemini', 'commands', 'temper.toml') if stem == 'temper' \
        else os.path.join(root, '.gemini', 'commands', 'temper', stem + '.toml')
    rel = os.path.relpath(shim, root)
    if not os.path.isfile(shim):
        errs.append(f'{stem}: no Gemini shim at {rel}'); continue
    text = open(shim).read()
    want, got = md_desc(path), toml_desc(text)
    if want is None:
        errs.append(f'{stem}: commands/{stem}.md has no description frontmatter')
    elif got != want:
        errs.append(f'{rel}: description drifted from commands/{stem}.md')
    if f'commands/{stem}.md' not in text:
        errs.append(f'{rel}: does not point at commands/{stem}.md (a shim must reference, never restate)')
    if len(text) > 3000:
        errs.append(f'{rel}: {len(text)} bytes — too long for a shim; it is restating the command')

# ...and no orphan shims for commands that no longer exist.
for shim in sorted(glob.glob(os.path.join(root, '.gemini', 'commands', '**', '*.toml'), recursive=True)):
    stem = os.path.basename(shim)[:-5]
    if not os.path.isfile(os.path.join(root, 'commands', stem + '.md')):
        errs.append(f'{os.path.relpath(shim, root)}: no matching commands/{stem}.md')
print('; '.join(errs))
" "$REPO_ROOT" 2>&1)
if [[ -z "$GEMINI_ERR" ]]; then ok; else fail "gemini command parity: $GEMINI_ERR"; fi

for f in AGENTS.md docs/agents.md skills/temper/SKILL.md; do
  if [[ -f "$REPO_ROOT/$f" ]]; then ok; else fail "$f missing (multi-agent entry point)"; fi
done

# --- Pack `phases:` frontmatter (v8) ---
# Every built-in pack declares which stages load it. This validates the declaration is
# present and its values are real phases; it cannot tell you a pack was narrowed too far
# — that's a reading of the stage docs, not a property of the file. `all` loads
# everywhere, `[]` loads nowhere (packs/hooks, whose content is install documentation).
PACK_PHASES_ERR=$(python3 -c "
import glob, os, re, sys
VALID = {'plan', 'design', 'build', 'review', 'check', 'fix'}
errs = []
for path in sorted(glob.glob(os.path.join(sys.argv[1], 'packs', '*', 'rules.md'))):
    name = os.path.basename(os.path.dirname(path))
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

# --- Phase 1 Verification (v5.5.0): hooks assertions ---
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

# Plugin-level hooks/hooks.json (v8.0.1): ships the standalone-stage gate guarantee
# with the plugin itself, so --plugin-dir and marketplace installs get it without a
# settings.json merge. Must be valid JSON and reference only hook scripts that exist.
PLUGIN_HOOKS="$REPO_ROOT/hooks/hooks.json"
if [[ -f "$PLUGIN_HOOKS" ]]; then
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PLUGIN_HOOKS" 2>/dev/null; then
    ok
  else
    fail "hooks/hooks.json is not valid JSON"
  fi
  MISSING_HOOK_SCRIPTS=$(python3 -c "
import json, re, sys, os
d = json.load(open(sys.argv[1]))
missing = []
for event in d.get('hooks', {}).values():
    for matcher in event:
        for h in matcher.get('hooks', []):
            for m in re.findall(r'scripts/hooks/[\w.-]+\.sh', h.get('command', '')):
                if not os.path.isfile(os.path.join(sys.argv[2], m)):
                    missing.append(m)
print('; '.join(missing))
" "$PLUGIN_HOOKS" "$REPO_ROOT" 2>/dev/null)
  if [[ -z "$MISSING_HOOK_SCRIPTS" ]]; then ok; else fail "hooks/hooks.json references missing scripts: $MISSING_HOOK_SCRIPTS"; fi
else
  fail "hooks/hooks.json missing (plugin-level stage-gate guarantee)"
fi

# Hook scripts: exist and are executable
for sh in block-secrets.sh block-forbidden-imports.sh block-uncommitted-gate.sh verify-tests-ran.sh install.sh stage-marker.sh verify-stage-gate.sh; do
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

# --- pack-discover.py (v8): /temper:pack's Step 5a discovery scan, extracted from a
# prompt-embedded script into a testable one ---
PACK_DISCOVER="$REPO_ROOT/scripts/pack-discover.py"
if [[ ! -f "$PACK_DISCOVER" ]]; then
  fail "scripts/pack-discover.py missing"
elif ! python3 -c "import ast; ast.parse(open('$PACK_DISCOVER').read())" 2>/dev/null; then
  fail "scripts/pack-discover.py has a syntax error"
else
  ok
fi

# --- Eval fixtures (v7 — Move 3, docs/plans/v7-deterministic-spine.md) — this is
# Temper's OWN seeded-defect regression harness (evals/), unrelated to the removed
# /temper:eval stage despite the name collision. It stays exactly as it was.
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
