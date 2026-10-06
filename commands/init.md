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
1. Paths. Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that
   path with /scripts/temper taken off); wherever a reference page writes the
   CLAUDE_PLUGIN_ROOT variable, use this folder. If that file does not exist, stop and
   say "Cannot locate the Temper plugin folder. Reinstall the plugin." Never search the
   disk for another copy. Every path below that is not in the plugin folder is in the
   user's project, the current directory. Nothing here writes into the plugin folder.

2. Config — .claude/temper.config:
   a. EXISTS → report "Temper config already present" and do NOT overwrite it (it's the
      user's). Check for retired blocks and keys and report what's now ignored:
        grep -nE '^(tokens|observability|capabilities|eval):' .claude/temper.config
      then, as two separate calls:
        ${CLAUDE_PLUGIN_ROOT}/scripts/temper config get models.routing
        ${CLAUDE_PLUGIN_ROOT}/scripts/temper config get models.tiers
      Print one "NOTE: '{key}:' block found, retired, now ignored" line per grep match,
      and one "NOTE: 'models.routing' found (the v6 routing table), retired, now
      ignored" line (or 'models.tiers') for each of the two calls that prints anything.
      A flat models: block (models.plan, models.build and so on) is the live per-stage
      model override, so it is never flagged. If nothing matches, print nothing.
      Read-only: never edits the file.
   b. MISSING → mkdir -p .claude, copy
      ${CLAUDE_PLUGIN_ROOT}/templates/temper.config.default → .claude/temper.config,
      report "Created .claude/temper.config from the default template."

3. Scaffold — run `${CLAUDE_PLUGIN_ROOT}/scripts/temper init` (creates .temper/: gates
   ledger, overrides log, feedback-loops registry). Idempotent.

4. Commit gate — the headline guarantee. Run:
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/guards/install.sh
   It installs a native git pre-commit hook that runs `temper gate commit` (and the
   secret scan) on every commit, fails open if temper isn't in use for a commit, and
   backs up any existing non-Temper pre-commit hook first. It writes the project's
   `.git/hooks/pre-commit`, or the `pre-commit` file in the folder an existing
   `core.hooksPath` names (husky and lefthook set one) when that folder is inside the
   repository, so the gate isn't written where git would ignore it. Re-running is
   idempotent: it rewrites a Temper hook in place with the current plugin paths, and it
   warns when the old hook pointed at a different plugin path (a stale hook, as after a
   plugin upgrade, whose checks were failing open).
   Report by how it ended:
   a. Exit 0 → the gate is installed; carry its "Installed ..." line into the report.
   b. Exit 1 with "FAIL: not inside a git repository" → report "not a git repo yet; run
      /temper:init again after `git init` to install the commit gate" and continue (the
      config + scaffold still succeeded).
   c. Exit 1 with any other FAIL line → nothing was written. install.sh prints the
      lines to add to a pre-commit hook by hand and exits 1 when core.hooksPath is
      outside the repository, contains '..', '~' or other unusual characters, or names
      a folder that holds a JSON file (`.git/hooks` gets the same JSON check), when the
      hooks folder (or `.git/config`, or a backup path) leads outside the repository or
      into the plugin's own folder once symlinks are followed, when the repository lies
      inside the plugin's own folder, and when core.hooksPath is not set and the
      checkout's .git is not a folder (a linked worktree or a submodule). It ignores
      GIT_DIR, GIT_WORK_TREE and GIT_CONFIG, so it always works on the repository that
      holds the current folder. Report "commit gate not installed: {the FAIL reason}",
      show the user the lines it printed, and say they can add those lines to their own
      pre-commit hook, or point core.hooksPath at a plain folder inside the repository
      and run /temper:init again. Continue (the config + scaffold still succeeded).

5. Guardrails hooks. Look in the project settings files that exist,
   .claude/settings.json and .claude/settings.local.json (never the user's home
   settings), for a stale Temper guard command, as defined in
   ${CLAUDE_PLUGIN_ROOT}/reference/pack.md → "Guardrails Hooks": a guard command whose
   script file does not exist, such as one naming the old scripts/hooks folder or the
   folder of an earlier plugin version. When there is one, offer in one line to rewrite
   it with the current plugin folder; on yes, follow that section's Enable steps 1 and 3
   to 7 for that file (they show the change before writing). When there is none, print
   nothing.

6. Report done, and name the one optional add-on in a single line:
   "Set up. Optional: `/temper:pack enable guardrails` adds edit-time guardrails (secret
   blocking, frozen-path protection, auto-format, an approval prompt before overrides)
   to a project settings file you pick. The commit gate above works without it."
```

## What this deliberately does NOT do

- It does **not** add hooks to a settings file. The stage-gate hooks ship with the plugin
  (in its own hooks file) and work on install with no merge. The fuller edit-time
  guardrail set is the opt-in `/temper:pack enable guardrails` above, because merging
  hooks into a project settings file is a change the user should choose. The one
  settings change step 5 can make, rewriting a stale guard command, waits for the
  user's yes, and Temper never reads or writes the user's home settings.
- It does **not** overwrite an existing config, and it never destroys an existing
  non-Temper git hook: install.sh copies that hook to `pre-commit.bak.<timestamp>` next
  to it before writing the Temper hook.

## Migrating from an older version

A pre-v7 config (`tokens:`, `observability:` or `capabilities:` blocks, or the v6
`models.routing` and `models.tiers` keys) or a v7 `eval:` block still parses: the CLI
ignores keys it doesn't use. Nothing breaks; step 2 just reports what's now inert. A
flat `models:` block is not retired: it is the per-stage model override. Guard hooks an
earlier version merged into a project settings file, pointing at the old scripts/hooks
folder, are what step 5 finds. See `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` for the mapping.
