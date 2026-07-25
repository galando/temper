---
description: "Initialize Temper config + CLI state scaffold for a project (idempotent)"
---

# Temper: Init Project Config

**Goal:** Ensure the current project has a `.claude/temper.config` and a `.temper/`
scaffold. Idempotent — safe to run any number of times; an existing config is never
overwritten.

## Resolution

```
1. Resolve $CLAUDE_PLUGIN_ROOT (orchestrator-patterns.md → "$CLAUDE_PLUGIN_ROOT Resolution").
2. Check whether .claude/temper.config exists in the current project:
   a. If it EXISTS:
        - Report: "Temper config already present: .claude/temper.config"
        - Do NOT overwrite it (idempotent — an existing config is the user's, never
          silently rewritten). But DO check it for retired v6.x blocks and report what's
          now ignored, so the user isn't left guessing:
            grep -nE '^(tokens|models|observability|capabilities):' .claude/temper.config
          For each top-level key matched, print one line: "NOTE: '{key}:' block found —
          retired in v7, now ignored (see CHANGELOG.md 'v7.0.0' for what replaced it)."
          If none matched, print nothing extra. This is a read-only report — it never
          edits the file. If the user wants those lines gone, that's their edit to make.
        - Stop (idempotent).
   b. If it does NOT exist:
        - Ensure the .claude/ directory exists (mkdir -p .claude).
        - Copy the default template into place:
            $CLAUDE_PLUGIN_ROOT/templates/temper.config.default
            -> .claude/temper.config
        - Report: "Created .claude/temper.config from the default template."
3. Run `$CLAUDE_PLUGIN_ROOT/scripts/temper init` — scaffolds `.temper/` (gates ledger,
   overrides log, feedback-loops registry). Also idempotent.
4. Lint the config — `$CLAUDE_PLUGIN_ROOT/scripts/temper config lint`. Print whatever
   it reports. A finding is never fatal (Temper still runs), but an unreadable setting
   silently falls back to its default, which is precisely the failure worth surfacing
   at init time rather than three gates later.
5. **Install the commit gate.** This is the flagship guarantee — until the native hook
   exists, `temper gate commit` only runs in-agent (PreToolUse), and a raw `git commit`
   outside the agent is completely ungated. Do not merely recommend it:
   a. Skip entirely if `TEMPER_INIT_NO_HOOK=1` is set — report "Commit hook skipped
      (TEMPER_INIT_NO_HOOK=1)." and move on.
   b. Check for a foreign hook first:
        test -f .git/hooks/pre-commit && ! grep -qF "installed by scripts/hooks/install.sh" .git/hooks/pre-commit
      If that's true, the project already has its own pre-commit hook (husky, lefthook,
      hand-rolled). **Do not run the installer** — it would back the hook up and replace
      it. Report: "Existing non-Temper pre-commit hook found — left untouched. To chain
      Temper's gate into it, add `bash $CLAUDE_PLUGIN_ROOT/scripts/hooks/block-uncommitted-gate.sh`
      to your hook, or run `bash $CLAUDE_PLUGIN_ROOT/scripts/hooks/install.sh` to replace
      it (your hook is backed up first)."
   c. Otherwise run `bash $CLAUDE_PLUGIN_ROOT/scripts/hooks/install.sh` and report what
      landed, plus the one-line opt-out: "Remove with `rm .git/hooks/pre-commit`."
   Re-running init stays idempotent — the installer overwrites only its own marked hook,
   in place.
6. Report where to edit the config: "Edit .claude/temper.config to tune packs, review/
   check/eval thresholds, and the autonomy block."
7. Note the fallback: if the plugin ships without the template, point the user at the
   shipped `.claude/temper.config` as the reference copy.
```

## Migrating from v6.x

A pre-v7 config (with `tokens:`, `models:`, `observability:`, or `capabilities:` blocks)
still parses — `temper` (the CLI) ignores keys it doesn't use, and the retired
capabilities (Grill Me, Teach Me, HTML review, Architecture Depth Review) are simply
always offered now instead of gated behind a toggle. Nothing breaks; there's just
nothing left to configure for them. See `CHANGELOG.md` → "v7.0.0" for the full mapping
of what replaced each retired block.

## Defaults

The default template is the plugin's own shipped `.claude/temper.config` — same packs,
same review/check/eval settings, and the same opt-in `autonomy:` block (armed at the
plan gate, parked before commit). New installs get a known-good starting point;
existing installs are untouched.
