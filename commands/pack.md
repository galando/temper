---
description: "Manage quality packs: view, toggle, quick-create launchers, configure links & phases"
---

# Pack: Quality Pack Manager

> **Plugin root & tool names.** Where this file says `$CLAUDE_PLUGIN_ROOT`, use the
> plugin's install directory: `$CLAUDE_PLUGIN_ROOT` under Claude Code,
> `$CURSOR_PLUGIN_ROOT` under Cursor, otherwise the directory holding `commands/`,
> `agents/`, and `scripts/temper` — `temper root` prints it. `Agent` and
> `AskUserQuestion` below are Claude Code's tool names; `reference/portability.md`
> defines the equivalent under every other agent. No gate is ever skipped for lack of
> a tool.

## Step 1: Discover Packs

Read `.claude/temper.config` packs section. Scan three tiers:
- `.claude/packs/{name}/rules.md` (project-local, highest priority)
- `~/.claude/packs/{name}/rules.md` (global)
- `$CLAUDE_PLUGIN_ROOT/packs/{name}/rules.md` (built-in)

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

## Step 3: AskUserQuestion (max 4 options)

```
AskUserQuestion:
  question: "What would you like to do?"
  options:
    - label: "Toggle packs on/off"
      description: "Select packs to enable or disable."
    - label: "Quick-create launcher pack"
      description: "Wrap a plugin or skill as a BLOCK-level pack."
    - label: "Configure pack (link, phases)"
      description: "Set link target or phase scoping for an existing pack."
    - label: "Done"
      description: "Exit. Use 'Other' for full interactive pack builder."
  multiSelect: false
```

## Step 4: Toggle Packs

Multi-select AskUserQuestion with all packs. Update `.claude/temper.config` `packs:` list. Return to Step 3.

## Step 5: Quick-Create Launcher Pack

**5a: Discover ALL linkable targets.** Run the discovery script — one correct output for
a given filesystem, so this is a script, not a prompt-embedded scan:

```bash
python3 "$CLAUDE_PLUGIN_ROOT/scripts/pack-discover.py"
```

Each line is `TYPE|name|path|description`, already deduplicated (one row per
plugin/skill/command, deterministic across marketplaces and reruns) with every row
carrying its *own* frontmatter description — never the parent plugin's description
repeated across every row. `temper`'s own plugin is excluded inside the script (there is
no separate exclusion list to keep in sync here).

**Filter:** remove any target already linked to an existing pack (check `link:` values
in `temper.config`).

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

Show via AskUserQuestion (max 4 at a time, use "More targets..." to paginate).

**5b:** User picks target, types pack name via "Other". Generate `.claude/packs/{name}/rules.md` with BLOCK-level enforcement. Update `temper.config`. Return to Step 3.

## Step 6: Configure Pack

Select pack → choose "Set link" or "Set phases" or both.

**Set link:** Run same discovery scans as Step 5a. Show targets. Update config.
**Set phases:** Show phase options (all, build, review+check, or type custom via "Other"). Update config.

Return to Step 3.

## Step 7: Full Interactive Pack Builder

> Read `$CLAUDE_PLUGIN_ROOT/reference/pack.md` → "Step 5: Full Interactive Pack Builder" section for the codebase scan + interview + generation methodology.

This is the ONLY step that requires loading the reference doc. All other steps are self-contained above.
