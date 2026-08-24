---
description: "One-command setup: config + .temper/ scaffold + the commit gate (idempotent)"
---

# Temper: Set Up This Project

**Goal:** get a project fully set up in one command. Seeds `.claude/temper.config`,
scaffolds `.temper/`, and installs the native commit gate — the one control that
physically blocks `git commit` while a gate is red. Idempotent: safe to run any number
of times; an existing config is never overwritten.

`/temper` runs this automatically the first time it's used in an un-set-up project, so
most people never call `/temper:init` by hand — it's here for an explicit re-run.

## Steps

```
1. Resolve $CLAUDE_PLUGIN_ROOT (orchestrator-patterns.md → "$CLAUDE_PLUGIN_ROOT Resolution").

2. Config — .claude/temper.config:
   a. EXISTS → report "Temper config already present" and do NOT overwrite it (it's the
      user's). Check for retired v6.x blocks and report what's now ignored:
        grep -nE '^(tokens|models|observability|capabilities|eval):' .claude/temper.config
      Print one "NOTE: '{key}:' block found — retired, now ignored" line per match; if
      none, print nothing. Read-only — never edits the file.
   b. MISSING → mkdir -p .claude, copy
      $CLAUDE_PLUGIN_ROOT/templates/temper.config.default → .claude/temper.config,
      report "Created .claude/temper.config from the default template."

3. Scaffold — run `$CLAUDE_PLUGIN_ROOT/scripts/temper init` (creates .temper/: gates
   ledger, overrides log, feedback-loops registry). Idempotent.

4. Commit gate — the headline guarantee. Run:
      bash $CLAUDE_PLUGIN_ROOT/scripts/hooks/install.sh
   It installs a native git pre-commit hook that runs `temper gate commit` (and the
   secret scan) on every commit, fails open if temper isn't in use for a commit, and
   backs up any existing non-Temper pre-commit hook first. It installs into the active
   hooks dir — respecting an existing `core.hooksPath` (husky/lefthook) so the gate
   isn't written where git would ignore it. Re-running is idempotent. If the project
   isn't a git repo yet, install.sh exits non-zero — report "not a git repo yet; run
   /temper:init again after `git init` to install the commit gate" and continue (the
   config + scaffold still succeeded).

5. Report done, and name the one optional add-on in a single line:
   "Set up. Optional: `/temper:pack enable hooks` adds edit-time guardrails (secret
   blocking, frozen-path protection, auto-format, an approval prompt before overrides).
   The commit gate above works without it."
```

## What this deliberately does NOT do

- It does **not** edit `settings.json`. The stage-gate hooks ship with the plugin
  (`hooks/hooks.json`) and work on install with no merge; the fuller edit-time guardrail
  set is the opt-in `/temper:pack enable hooks` above, because merging into a user's
  `settings.json` is a change they should choose.
- It does **not** overwrite an existing config or an existing non-Temper git hook
  (that one is backed up, never destroyed).

## Migrating from an older version

A pre-v7 config (`tokens:`/`models:`/`observability:`/`capabilities:` blocks) or a v7
`eval:` block still parses — the CLI ignores keys it doesn't use. Nothing breaks; step 2
just reports what's now inert. See `CHANGELOG.md` for the mapping.
