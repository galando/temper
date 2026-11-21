---
description: "Root cause analysis + structured fix"
argument-hint: "<bug-description-or-JIRA-123>"
model: sonnet
---

# Fix: RCA → Fix → Review → Check

**Goal:** find the root cause, make the smallest fix with a regression test, then Review and Check:
the pipeline of `/temper`, with RCA in place of Intent and Plan, and Fix in place of Build.

**First output.** Look at your system prompt for a line that starts with `Temper enforcement:`. With
none, your first line is exactly `Temper enforcement is off here (no mods support); continuing with
prompt based stages.` With `Temper enforcement: off (UI only)`, it is exactly `Temper enforcement is
off (turned off by the user); continuing with prompt based stages.` With `active`, say nothing about
it. Say it once per conversation. With the Temper mod, the mod stands aside in a `/temper:fix` run:
it draws nothing for it and judges none of its moves, but nothing goes around the native commit hook.
With the mod off, every stage works the same; the mod adds the bar, the pane and its write guards. Nothing falls back silently.

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

First run `${CLAUDE_PLUGIN_ROOT}/scripts/temper next --json`; when its `say` starts with `Temper 9.8.5 asks twice`,
say that one sentence first, as it is. When it lists `setup`, run those calls
first, each once, as the Start section of `${CLAUDE_PLUGIN_ROOT}/commands/temper.md` says: they
install the native commit hook, without which nothing gates the fix's commit.

With no arguments and a fix run active (`${CLAUDE_PLUGIN_ROOT}/scripts/temper state get command`
prints `fix`), skip to step 2. With the mod loaded, the mod carries a fix itself (the run driver, `docs/mod.md`), and
`/temper:fix` with no words takes an active fix run up there; it hands one step here as `step <kind> <option id>`: do
that one step as the Arguments of `${CLAUDE_PLUGIN_ROOT}/commands/temper.md` say, then end the turn with the line
`Type /temper:fix to go on.` A `/temper` run that is active is not this command's: say so in one
line and ask its `restart` question from `temper next --json`.

Pick the bug's slug first (letters, digits, `.`, `_` or `-`; a ticket key keeps its case, as in
`JIRA-123-checkout-500`). Launch the root cause stage with the Agent tool, `subagent_type`
`temper:temper-rca` (or the general purpose agent), `model` from
`${CLAUDE_PLUGIN_ROOT}/scripts/temper model rca`, and the prompt:

```
Follow ${CLAUDE_PLUGIN_ROOT}/agents/rca.md exactly. Bug: $ARGUMENTS.
RCA file: .temper/specs/{bug-slug}/rca.md
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.
```

The agent writes its findings to that file and returns one line. Then run, in one Bash call:

```
${CLAUDE_PLUGIN_ROOT}/scripts/temper state init {bug-slug} --command fix --feature '{the bug as the person typed it}'
${CLAUDE_PLUGIN_ROOT}/scripts/temper usage add --stage rca --model {model} --ms {ms}
```

`{ms}` is filled as `/temper:temper`'s agent bullet says; the bug is one shell quoted word, each `'` in it written as
`'\''`. Print no panel and make no branch: the card of the first question shows what `rca.md` says, and the answer
that approves the fix makes the branch (off main or master only).

## 2. The loop

From here `${CLAUDE_PLUGIN_ROOT}/scripts/temper go` (the compact form of `temper next --json`) drives the run. A clean
bug run asks twice: the root cause with the fix it proposes (the approval: Approve and fix lets the run go on by
itself to the commit), then the commit. Follow the sections "The loop", "Every question" and "Agents" of
`${CLAUDE_PLUGIN_ROOT}/commands/temper.md` (read them now; that file was not filled in when you read
it: wherever it writes the CLAUDE_PLUGIN_ROOT variable, use the folder that holds
${CLAUDE_PLUGIN_ROOT}/scripts/temper). A call that prints a `VERDICT:` line recorded a verdict, whatever its exit code:
it is no failure. A change typed at the root cause question is the question's `typed` calls, as everywhere: the CLI
then launches the root cause agent again with it. The commit is the commit question's: its card shows the message the
CLI drafted from `rca.md`. After the commit say "Committed: {hash} / Branch: {branch}. Temper does not push."
