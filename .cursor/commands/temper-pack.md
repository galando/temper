---
description: "Manage quality packs: view, toggle, quick-create launchers, configure links & phases"
---

# Pack: Quality Pack Manager

**Goal:** Show all defined packs with enable/disable status, link targets, phase scoping, and connection health. Let users toggle, create, quick-create launchers, and configure packs.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/pack.md`

### Quick Reference

1. **Discover packs** (three-tier: project > global > built-in) — cached in `.temper/pack-manifest.json`
2. Read `.claude/temper.config` for enabled status, links, and phase scoping
3. Display pack table with all columns: NAME, STATUS, PHASES, LINK, CONNECTED
4. User chooses via AskUserQuestion (max 4 options):
   - **Toggle packs on/off** — multi-select to enable/disable
   - **Quick-create launcher pack** — wrap a plugin or skill as BLOCK-level pack (v4.4.0)
   - **Configure pack** — set link target or phase scoping (v4.3.0)
   - **Done** — exit (use "Other" to request full interactive pack builder)

### Three-Tier Resolution

```
Priority 1 (highest) → .claude/packs/{name}/rules.md           (project-local)
Priority 2           → ~/.claude/packs/{name}/rules.md          (global / user-wide)
Priority 3 (lowest)  → $CLAUDE_PLUGIN_ROOT/.claude/packs/{name}/rules.md  (built-in)
```

### Cached Manifest

Results cached in `.temper/pack-manifest.json`. Rebuilt when config changes, packs added/removed, or schema mismatch.

### Phase Scoping

Packs can be restricted to specific phases: `plan`, `design`, `build`, `review`, `check`, `fix`. Only matching packs load during each phase.

### Pack-Plugin/Skill Linking

Packs link to plugins (`plugin://name`) or skills (`skill://name`). Linked context injected alongside pack rules. Connection health validated at load time.

### Quick-Create Launcher — Discovery (CRITICAL: Must Execute Bash Scans)

When quick-create is selected, you MUST run these bash commands to discover ALL linkable targets before showing options. Do NOT guess or skip scans.

**Scan 1 — Installed plugins:**
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.claude/plugins/installed_plugins.json')
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
    plugins = data.get('plugins', data)
    for key, entries in (plugins.items() if isinstance(plugins, dict) else []):
        name = key.split('@')[0]
        latest = entries[-1] if entries else {}
        ipath = latest.get('installPath', '')
        if name != 'temper':
            print(f'PLUGIN|{name}|{ipath}')
"
```

**Scan 2 — Project skills:**
```bash
find .claude/skills -name "SKILL.md" 2>/dev/null
```

**Scan 3 — Global skills:**
```bash
find ~/.claude/skills -name "SKILL.md" 2>/dev/null
```

**Scan 4 — Project commands (fallback):**
```bash
ls .claude/commands/*.md 2>/dev/null | xargs -I{} basename {} .md
```

**Scan 5 — Global commands (fallback):**
```bash
ls ~/.claude/commands/*.md 2>/dev/null | xargs -I{} basename {} .md
```

**Scan 6 — Plugin skills and commands** (run for each plugin installPath found in Scan 1):
```bash
find {installPath}/skills -name "SKILL.md" 2>/dev/null
find {installPath}/commands -name "*.md" -maxdepth 1 2>/dev/null
```

After collecting all results:
1. Build deduplicated list of `{type}://{name}` targets
2. Remove targets already linked to a pack in `temper.config`
3. Show remaining targets in AskUserQuestion (max 4 per page, paginate with "More targets...")
