---
description: "Manage quality packs: view, toggle, quick-create launchers, configure links & phases"
---

# Pack: Quality Pack Manager

## Step 1: Discover Packs

Read `.claude/temper.config` packs section. Scan three tiers:
- `.claude/packs/{name}/rules.md` (project-local, highest priority)
- `~/.claude/packs/{name}/rules.md` (global)
- Built-in packs shipped with the plugin (lowest priority)

Deduplicate by name (highest tier wins). For each pack: read rules.md header, check enabled status, read `phases` and `link` from config.

## Step 2: Display Pack Table

Build the table dynamically from discovered packs. Do NOT use hardcoded example rows.

Format each row using actual data:
- **NAME** — pack name from config
- **STATUS** — `ON` if in packs list, `OFF` if not
- **PHASES** — from config (show `all` if not specified)
- **LINK** — from config (show `—` if none)
- **CONNECTED** — check if link target actually exists on filesystem

Example structure (populate with real data only):

```
┌──────────────────────────────────────────────────────────────────────────┐
│ PACK — Quality Pack Manager                                      v4.4.0 │
├──────────────────────────────────────────────────────────────────────────┤
│  NAME            STATUS  PHASES     LINK                CONNECTED        │
│  ────────────── ─────── ────────── ─────────────────── ──────────────── │
│  {name}           {on}    {phases}   {link}              {found/missing} │
│  ...                                                                     │
│  N packs total (X enabled, Y disabled)                                   │
└──────────────────────────────────────────────────────────────────────────┘
```

## Step 3: Present Options (max 4 options)

```
**What would you like to do?**

1. **Toggle packs on/off** — Select packs to enable or disable.
2. **Quick-create launcher pack** — Wrap a plugin or skill as a BLOCK-level pack.
3. **Configure pack (link, phases)** — Set link target or phase scoping for an existing pack.
4. **Done** — Exit. Use 'Other' for full interactive pack builder.
5. Type your own response

Ask the user to choose by number or type their response.
```

## Step 4: Toggle Packs

Multi-select numbered options with all packs. Update `.claude/temper.config` `packs:` list. Return to Step 3.

## Step 5: Quick-Create Launcher Pack

**5a: Discover ALL linkable targets.** Run this unified discovery scan:

### Single unified scan — classify everything correctly
```bash
python3 -c "
import json, os, glob

path = os.path.expanduser('~/.claude/plugins/installed_plugins.json')
if not os.path.exists(path):
    exit()
with open(path) as f: data = json.load(f)
plugins = data.get('plugins', {})

for key, entries in plugins.items():
    pkg_name = key.split('@')[0]
    if pkg_name == 'temper': continue
    latest = entries[-1] if entries else {}
    ipath = latest.get('installPath', '')
    if not ipath or not os.path.exists(ipath): continue

    # Read plugin description
    pj = os.path.join(ipath, '.claude-plugin/plugin.json')
    desc = ''
    if os.path.exists(pj):
        with open(pj) as f: pd = json.load(f)
        desc = pd.get('description', '')

    # Find skills: skills/*/SKILL.md or .claude/skills/*/SKILL.md
    skills = glob.glob(os.path.join(ipath, '**/SKILL.md'), recursive=True)
    # Find commands: commands/*.md or .claude/commands/*.md
    cmds = glob.glob(os.path.join(ipath, '**/commands/*.md'), recursive=True)

    # Classify: if plugin has skills, list skills; if commands, list commands
    # If neither, list the plugin package itself
    has_output = False

    for s in skills:
        skill_dir = os.path.basename(os.path.dirname(s))
        print(f'SKILL|{pkg_name}:{skill_dir}|{os.path.dirname(s)}|{desc}')
        has_output = True

    for c in cmds:
        cmd_name = os.path.splitext(os.path.basename(c))[0]
        print(f'CMD|{pkg_name}:{cmd_name}|{os.path.dirname(c)}|{desc}')
        has_output = True

    if not has_output:
        print(f'PLUGIN|{pkg_name}|{ipath}|{desc}')
"
```

Then supplement with project-local and global commands:
```bash
# Project-local commands
ls .claude/commands/*.md 2>/dev/null | while read f; do
  echo "LOCAL_CMD|$(basename "$f" .md)|.claude/commands/"
done
# Global commands
ls ~/.claude/commands/*.md 2>/dev/null | while read f; do
  echo "GLOBAL_CMD|$(basename "$f" .md)|~/.claude/commands/"
done
```

### Deduplicate & filter
Combine all scan results. Remove targets already linked to existing packs (check `link:` values in temper.config).

**Exclude** temper's own commands (build, check, design, fix, pack, plan, review, status, temper, temper-core) — they're already built-in, no launcher needed.

Use these display labels by TYPE prefix:
- `SKILL|` → `Skill`
- `CMD|` → `Command`
- `PLUGIN|` → `Plugin`
- `LOCAL_CMD|` → `Project Command`
- `GLOBAL_CMD|` → `Global Command`

Group and display by type:
```
Skills:
  1. frontend-design:frontend-design — Frontend design skill for UI/UX
  ...

Commands:
  5. commit-commands:commit — Create a git commit
  ...

Plugins:
  8. context7 — Up-to-date library docs
  ...

Project Commands:
  9. ...
```

**Important:** Only show targets that actually appeared in scan output. Do NOT fabricate entries.

Show via numbered options (max 4 at a time, use "More targets..." to paginate).

**5b:** User picks target, types pack name via "Other". Generate `.claude/packs/{name}/rules.md` with BLOCK-level enforcement. Update `temper.config`. Return to Step 3.

## Step 6: Configure Pack

Select pack → choose "Set link" or "Set phases" or both.

**Set link:** Run same discovery scans as Step 5a. Show targets. Update config.
**Set phases:** Show phase options (all, build, review+check, or type custom via "Other"). Update config.

Return to Step 3.

## Step 7: Full Interactive Pack Builder

> The reference docs loaded via the `temper-ref-pack` rule contain the "Step 7: Add New Pack" section for the codebase scan + interview + generation methodology.

This is the ONLY step that requires loading the reference doc. All other steps are self-contained above.
