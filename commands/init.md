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
   Before anything is written, check the project folder, in this order:
   a. When it is the home folder, stop and say in one line: "The project folder is your
      home folder, which holds Claude Code's own files and is never a project. Run
      /temper:init from a project folder."
   b. Run ${CLAUDE_PLUGIN_ROOT}/scripts/temper status. When it prints a line that starts
      with "FAIL: run temper from a project folder", the CLI refused this folder (the
      home folder, an installed copy of the plugin, or a folder inside the plugin
      folder): stop and show that line, and write nothing. Any other result, "FAIL: no
      intent.md to report on" among them, means go on.

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
      bash "${CLAUDE_PLUGIN_ROOT}/scripts/guards/install.sh"
   It installs a native git pre-commit hook that runs the secret scan and
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` on every commit, and fails open
   if Temper isn't in use for a commit. It asks git where hooks go (the file that
   `git rev-parse --git-path hooks/pre-commit` prints): the repository's hooks folder,
   or the folder an existing `core.hooksPath` names (husky and lefthook set one) when
   that folder is inside the repository or inside the repository's own git folder, so
   the gate isn't written where git would ignore it. In a linked worktree or a
   submodule, git names the hooks folder of the repository's own git folder, which the
   worktrees share: when that folder already holds a current Temper hook, install.sh
   says the hook is already installed for this worktree and exits 0; otherwise it
   installs there. It never writes over a pre-commit hook that is not Temper's, and it
   never writes a file git tracks (husky v5 to v8 keep `.husky/pre-commit` in git): it
   refuses instead, as in c below. Before it refuses for one of those two reasons, or
   because core.hooksPath lies outside the repository, it writes the full Temper hook
   to the file `temper-pre-commit` in the repository's own git folder (the folder
   `git rev-parse --git-common-dir` names; never committed, never in the plugin
   folder), so the user's own hook needs only one line, with no path of this machine in
   it, to run the Temper hook. A pre-commit hook of the user's own that holds that exact
   line, with no line before it that starts with `exit` or `exec`, calls the Temper
   hook: install.sh makes `temper-pre-commit` current, says so and exits 0. When an
   `exit` or `exec` line comes first, the Temper line never runs, so install.sh refuses
   and says to move it above that line. Re-running is idempotent: it
   replaces an older Temper hook with one that holds the current plugin paths, and it
   warns when the old hook pointed at another plugin path (a stale hook, as after a
   plugin upgrade; it says the old hook was failing open only when that old path no
   longer exists). When an older version set a hook that was not Temper's aside as
   `pre-commit.bak.<timestamp>`, it names that file in a warning and says how to bring
   it back: move it back to `pre-commit`, then add to it the line it prints between its
   BEGIN and END lines (it writes `temper-pre-commit` first, so that line works).
   Report by how it ended:
   a. Exit 0 → the gate is installed, was already installed for this worktree, or the
      user's own hook calls the Temper hook, which is now current; carry its line about
      that into the report. Carry each `Warning:` line it printed into the report too,
      with the restore steps and the line it printed after a warning about an old
      `pre-commit.bak.<timestamp>` file, in a fenced code block.
   b. Exit 1 with "FAIL: not inside a git repository" → report "not a git repo yet; run
      /temper:init again after `git init` to install the commit gate" and continue (the
      config + scaffold still succeeded).
   c. Any other non-zero exit → the commit gate is not installed. Report "commit gate
      not installed: {the FAIL reason}", or, when its output has no FAIL line, "commit
      gate not installed" followed by its whole output in a fenced code block. When its
      output says "The Temper hook is kept in {file}", say that install.sh kept the
      Temper hook in that file, in the repository's git folder (never committed), and
      wrote nothing else; otherwise say that it wrote nothing. Then, when it printed
      lines between its BEGIN and END lines, show them verbatim in a fenced code block,
      so the user has them to copy: one line that runs the Temper hook kept in the git
      folder, or, when it refused before it knew the git folder, the Temper hook's own
      lines in a subshell, so that their exits end only the subshell. Never only say
      that it printed them. Then give its `Hint:` line as it printed it. For a hook
      that is not Temper's, a hook file git tracks or a core.hooksPath outside the
      repository, the hint says where the line goes: husky: `.husky/pre-commit`, safe
      to commit because the line holds no path of this machine; the pre-commit
      framework: a local hook in `.pre-commit-config.yaml` whose entry runs the line;
      lefthook: a pre-commit command in `lefthook.yml`, because lefthook writes its
      hook again; any other hook: its start or its end, because the line keeps that
      hook's own result.
      install.sh refuses and exits 1 when the pre-commit file holds a hook that is not
      Temper's, or is tracked by git; when the user's hook holds the Temper line after
      an `exit` or `exec` line; when core.hooksPath is Temper's own `--global` folder
      from where this repository used to be (its hint says to run install.sh with
      `--global` to point it here, or to unset core.hooksPath); when core.hooksPath
      is outside the repository and its own git folder, contains '..', '~' or other
      unusual characters, names a folder that holds a JSON file (the default hooks
      folder gets the same JSON check), or is a relative path through `.git` in a linked
      worktree or a submodule (where that folder cannot exist); when the hooks folder
      leads anywhere but the repository and its own git folder, or into the plugin's
      own folder, once symlinks are followed; when the
      repository lies inside the plugin's own folder; and when a folder or file it needs
      cannot be made. It ignores GIT_DIR, GIT_WORK_TREE and GIT_CONFIG, so it always
      works on the repository that holds the current folder. Continue (the config +
      scaffold still succeeded).

5. Guardrails hooks. Run the stale guard check of
   ${CLAUDE_PLUGIN_ROOT}/reference/pack.md → "Guardrails Hooks" (it is skipped when the
   project folder is the home folder, so the user's home settings are never read). It
   runs, from the project folder:
      python3 "${CLAUDE_PLUGIN_ROOT}/scripts/guard-entries.py"
   which reads only .claude/settings.json and .claude/settings.local.json in the
   project and prints one FILE|EVENT|MATCHER|SCRIPT|STATUS line per Temper guard entry
   (a matcher can hold '|', so read FILE and EVENT from the left and SCRIPT and STATUS
   from the right). STATUS stale means the command runs a guard script outside the
   current plugin folder, whether it exists or not (the folder of an earlier plugin
   version, which Claude Code keeps for a while after an upgrade, or the guard scripts
   folder of versions before 9.6.5), a script that does not exist, or a path that still
   holds the CLAUDE_PLUGIN_ROOT variable. Decide from its output only, never from your
   own reading of the settings files. When no line says stale, or it exits 2, print
   nothing. When any line says stale, ask that section's question as an
   AskUserQuestion of its own, before step 6: "Replace them with the current
   guardrails set (shows the change first)" / "Not now". On the first, follow that
   section's Enable steps 1 and 3 to 7 with that file as the picked file (they show the
   change in both project settings files and ask again before writing). On "Not now",
   change nothing.

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
  settings change step 5 can make, replacing stale guard commands with the current
  guardrails set, waits for the user's answer, and Temper never reads or writes the
  user's home settings.
- It does **not** overwrite an existing config, and it never writes over a pre-commit
  hook that is not Temper's, or over a hook file git tracks: install.sh refuses, keeps
  the Temper hook in `temper-pre-commit` in the repository's git folder, and prints
  the one line to add to that hook yourself, with a hint for husky, lefthook and the
  pre-commit framework.

## Migrating from an older version

A pre-v7 config (`tokens:`, `observability:` or `capabilities:` blocks, or the v6
`models.routing` and `models.tiers` keys) or a v7 `eval:` block still parses: the CLI
ignores keys it doesn't use. Nothing breaks; step 2 just reports what's now inert. A
flat `models:` block is not retired: it is the per-stage model override. Guard hooks an
earlier version merged into a project settings file, pointing at the guard scripts
folder of versions before 9.6.5, are what step 5 finds. See `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` for the mapping.
