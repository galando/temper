---
description: "Root cause analysis + structured fix"
argument-hint: "<bug-description-or-JIRA-123>"
---

# Fix: RCA → Fix → Review → Check

**Goal:** find the root cause, make the smallest fix with a regression test, then Review and Check:
the pipeline of `/temper`, with RCA in place of Intent and Plan, and Fix in place of Build.

**First output.** Look at your system prompt for a line that starts with `Temper enforcement:`. With
none, your first line is exactly `Temper enforcement is off here (no mods support); continuing with
prompt based phases.` With `Temper enforcement: off (UI only)`, it is exactly `Temper enforcement is
off (turned off by the user); continuing with prompt based phases.` With `active`, say nothing about
it. Say it once per conversation. With the Temper mod, the mod stands aside in a `/temper:fix` run:
it draws nothing for it and judges none of its moves, but nothing goes around the native commit hook.

## Usage

```
/temper:fix "users get 500 error on checkout"    # start a fix
/temper:fix "JIRA-123"                            # a fix from a ticket
/temper:fix                                       # take up the saved fix
```

The temper CLI is `${CLAUDE_PLUGIN_ROOT}/scripts/temper`. Every path below is written out in full:
run it exactly as shown. The commit hook runs `temper gate commit` on every commit in a project with a
`.temper` folder, so a fix records its evidence like any run: Fix is judged by the build gate (a
regression test is a RED then GREEN pair), Review and Check are the same stages as in `/temper`.

## 1. RCA (before the run exists)

With no arguments and a fix run active (`${CLAUDE_PLUGIN_ROOT}/scripts/temper state get command`
prints `fix`), skip to step 2. A `/temper` run that is active is not this command's: say so in one
line and ask its `restart` question from `temper next --json`.

Launch the root cause stage with the Agent tool, `subagent_type` `temper:temper-rca` (or the general
purpose agent), `model` from `${CLAUDE_PLUGIN_ROOT}/scripts/temper model rca`, and the prompt:

```
Follow ${CLAUDE_PLUGIN_ROOT}/agents/rca.md exactly. Bug: $ARGUMENTS.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.
```

Print the box it returns verbatim. Save its findings to `.temper/specs/{bug-slug}/rca.md` (the slug
is letters, digits, `.`, `_` or `-`; a ticket key keeps its case, as in `JIRA-123-checkout-500`).
Then run, in one Bash call:

```
${CLAUDE_PLUGIN_ROOT}/scripts/temper state init {bug-slug} --command fix
${CLAUDE_PLUGIN_ROOT}/scripts/temper usage add --stage rca --model {model} --tokens {tokens} --ms {ms}
```

When the git pack is on and `git branch --show-current` prints main or master, run
`git checkout -b fix/{bug-slug}`.

## 2. The loop

From here `${CLAUDE_PLUGIN_ROOT}/scripts/temper next --json` drives the run: its first question is the
RCA question ("Proceed to Fix"), then the Fix stage, Review, Check and the commit, with every
question's exact options. Follow the sections "The loop", "Every question" and "Agents" of
`${CLAUDE_PLUGIN_ROOT}/commands/temper.md` (read them now; that file was not filled in when you read
it: wherever it writes the CLAUDE_PLUGIN_ROOT variable, use the folder that holds
${CLAUDE_PLUGIN_ROOT}/scripts/temper). Two things are this command's own:

- **A change typed at the RCA question** (for example "look at the auth module instead") runs the RCA
  agent again with that direction, saves its findings to `rca.md` again, and asks `next` again.
- **The commit:** the commit message is `fix({scope}): {description}`, then the lines
  `Root cause: {explanation}` and `Regression test: {test name}`, and `Closes JIRA-123` or
  `Fixes #456` when there is one. Stage only the files the fix changed, the regression test and the
  spec folder; never `git add -A` or `git add .`, and never `git add -f` over a gitignored spec
  folder. After the commit say "Committed: {hash} / Branch: {branch}. Temper does not push."
