---
description: "Manage quality packs: view, enable/disable, or create new ones"
---

# Pack: Quality Pack Manager

**Goal:** Show all defined packs with enable/disable status, let users toggle them, or create new packs interactively.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/pack.md`

### Quick Reference

1. Discover all packs (built-in + custom) from `.claude/packs/`
2. Read `.claude/temper.config` for enabled status
3. Display pack list with status
4. User chooses: toggle packs or add new pack
5. On "add new pack" → run interactive pack builder (scan + interview + generate)
