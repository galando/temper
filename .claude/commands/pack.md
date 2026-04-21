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
   - **Quick-create launcher pack** — wrap a plugin/skill as BLOCK-level pack (v4.4.0)
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
