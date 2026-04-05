---
description: "Shared patterns for orchestrator commands (temper.md, fix.md)"
---

# Orchestrator Shared Patterns

**Used by:** `.claude/commands/temper.md`, `.claude/commands/fix.md`

This file contains shared orchestration patterns. Both `/temper` and `/temper:fix` delegate to these patterns instead of duplicating them.

---

## $CLAUDE_PLUGIN_ROOT Resolution

All references use `$CLAUDE_PLUGIN_ROOT` to locate plugin files. Resolve it as follows:

1. If `$CLAUDE_PLUGIN_ROOT` is set and points to an existing directory → use it
2. If unset → walk up from the command file location looking for `.claude-plugin/manifest.json`
3. If still not found → fall back to `~/.claude/plugins/temper` (default install location)
4. If fallback doesn't exist → warn user: "Cannot locate Temper plugin. Set CLAUDE_PLUGIN_ROOT or reinstall."

The resolved path is used as `$CLAUDE_PLUGIN_ROOT` throughout the command.

---

## Gate Options Pattern

Every stage gate uses exactly 2 explicit options plus the built-in "Other" free-text input:

```
AskUserQuestion:
  question: "What would you like to do with this {stage}?"
  options:
    - label: "{continue_label} (Recommended)"
      description: "{continue_description}"
    - label: "Save for later"
      description: "Save state and stop. Run {command} later to continue."
  multiSelect: false
```

**Users type change requests directly via the "Other" option.** AskUserQuestion always provides an "Other" free-text input. When a user selects "Other" and types a change request:
1. Make the requested change
2. **STOP** — re-show the AskUserQuestion gate with the same options
3. Do NOT interpret the change input as approval to proceed

---

## Gate Enforcement Rules

After handling a change request (via "Other" free-text input), you **MUST** re-show the AskUserQuestion gate before proceeding:

1. User selects "Other" and types their change request
2. You make the requested change
3. **STOP HERE** — re-show the AskUserQuestion gate with the same 2 options
4. Do NOT interpret the user's change input as approval to proceed to the next stage

The user must **explicitly select the "Continue" option** from the gate to proceed.

---

## Resume Validation

Before showing the saved state, validate `.temper/build-state.json`:

1. **Parseable JSON** — if malformed, show error and ask user
2. **Valid stage** — must be one of the stages defined by the command
3. **Spec directory exists** — `.temper/specs/{spec}/` must exist on disk
4. **Artifacts exist** — all files listed in `artifacts` array must exist
5. **Timestamp** — if `updated` > 30 days ago, warn user about staleness

If any check fails:
- Show what's wrong: "Saved state is invalid: {reason}"
- Ask user: "Start over / Delete saved state / Cancel?"

---

## Nested Invocation Protection

When `{command} "{new item}"` is called while `.temper/build-state.json` already exists for a different item:

```
┌─────────────────────────────────────────────────────────────┐
│ SAVED STATE FOUND                                           │
├─────────────────────────────────────────────────────────────┤
│ {Item type}: {name}                                         │
│    Stopped: After {stage}                                   │
│    Files: {N} changed                                       │
│                                                             │
│ Starting '{new item}' will overwrite this session.          │
└─────────────────────────────────────────────────────────────┘
```

Use AskUserQuestion:
```
AskUserQuestion:
  question: "A saved session exists for '{existing}'. What would you like to do?"
  options:
    - label: "Resume existing session (Recommended)"
      description: "Continue from {next_stage} stage."
    - label: "Overwrite and start new"
      description: "Delete existing session, start from scratch."
  multiSelect: false
```

---

## Agent Failure Handling

If an agent subprocess returns a failure or blocker:
1. Show the failure details to the user
2. Ask: "Retry / Save for later?" (user can type changes via "Other")
3. Do NOT silently proceed to the next stage

---

## Context Efficiency Table

Each subprocess starts genuinely clean. No theater.

| Transition | Method | Context Loaded | Size |
|-----------|--------|----------------|------|
| Stage 1 → 2 | New Agent subprocess | spec artifacts + related files | ~5-15KB |
| Stage 2 → 3 | New Agent subprocess | changed files (git diff) | ~20-50KB |
| Stage 3 → 4 | New Agent subprocess | methodology + spec context | ~5KB |
| Stage 4 → Commit | Direct (no subprocess) | Nothing | 0KB |
