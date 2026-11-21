---
title: Getting Started
nav_order: 2
---

# Getting Started

This page walks the first run of Temper on a project you already have. Every text quoted in a block below is what the
CLI prints, copied from a scripted run of a small project (a password reset by email, the folder `pw`).

## What you need

Claude Code, `bash`, `git` and `python3`. The CLI is a bash script with Python modules; without `python3` it stops at
once with `FAIL: python3 is required but not found in PATH`. The Temper mod, which draws the run and holds its
rules at the tool layer, needs Claude Code 2.1.287 or later; on an older version the plugin works without it.

## Install

```text
/plugin marketplace add galando/temper
/plugin install temper
```

On Claude Code 2.1.275 or later, one step: `/plugin install temper --marketplace galando/temper`. To try a clone of
the repository instead, start Claude Code with it loaded for one session: `claude --plugin-dir <path of the clone>`.

## The first run on an existing project

In your project, type the request:

```text
/temper:temper "Password reset by email"
```

**The setup.** The first run sets the project up by itself (the word `init` does the same with no run): the config,
the `.temper/` folder, and the commit gate, a native `pre-commit` hook that refuses `git commit` while a gate is red.

```text
OK: wrote /path/to/project/.claude/temper.config
OK: .temper/ scaffolded at /path/to/project/.temper
Installed Temper pre-commit hook -> /path/to/project/.git/temper-gate/pre-commit (core.hooksPath points at that folder, so every worktree of this repository runs it).
```

Temper never opens a Claude Code settings file, the project's or your home folder's.

**The baseline.** Before any agent, the CLI checks the tools and services the project names and runs your suite once
on the current code, in a worktree of its own:

```text
The environment is checked, and the project's suite runs once on the current code, before any agent.
```

When the suite already fails there, one question asks before any agent runs: run it again, go on anyway (the failures
it found are then a recorded skip), or save the run for later. Later limits of time are three times what the suite
took here.

**Intent.** The Intent agent turns your request into `intent.md`: what will be true when the work is done, one
criterion a line. It asks you only what the request left open (who, when, how much, exceptions), as questions with
ready answers, the first recommended. With nothing open the run goes on by itself:

```text
Intent: the check passed and nothing is open. The run goes on to Plan; you accept the intent with the plan, in one question.
```

**Plan.** The Plan agent writes `tasks.md`: groups of small tasks, each with its files, its test command and its cases.
Then the first question, with its card:

```text
APPROVE BEFORE ANY CODE IS WRITTEN                                        pw
You asked: "Password reset by email"

WHAT WILL BE TRUE (5 criteria; each gets a test written and locked first)
 AC-01 criterion 1
 AC-02 criterion 2
 AC-03 criterion 3
 AC-04 criterion 4
 AC-05 criterion 5

WHAT WILL CHANGE (3 files; any other file asks you first)
 G1 Tokens  + src/app.ts  + unit/app.test.ts
 G2 Mail    + src/mail.ts

THE CHECKS RUN
 G1: npm test
 G2: npm test
 all: npm test

LAUNCHES: 1 test writer (sonnet), 3 builders (sonnet), 1 reviewer (sonnet)
BASELINE: unknown: not run in the selftest [not measured]
You are asked again only if a check still fails after one repair, and at the
commit. Nothing is pushed.
```

```text
Temper gate
Plan: the check passed. Accept the intent, approve the plan and continue to Build?
  1. Approve and build (Recommended)
  2. Ask me at every stage
  3. Fresh review first
  4. More options
```

Approve and build accepts the intent and approves the plan; the run then goes on by itself. Ask me at every stage
approves the same and asks you at each later stage. Fresh review first has a reader with no context read the plan
before you decide. More options holds Open HTML review, Run Design first, Loop back to Intent and Save for later.
You choose in the dialog; a message you type there is a change for the agent, never a choice.

**Build, Review, Check.** First an agent that writes no code writes the acceptance tests from your intent, and they are
locked. Then each task runs as a small agent in its own worktree, its test first. When Build ends, the CLI runs your
suite, coverage and the acceptance tests once; Review reads the change; Check judges the rows on the same tree. Each
passed check moves on:

```text
Check passed; the run goes on to Commit.
```

**The commit.** The second question, with its card: what is true, the suite and coverage, the open findings, the
tree, and the commit the click makes. Part of it, from the same project:

```text
READY TO COMMIT                                                           pw

REVIEW (open: 1 critical, 1 low)
 [critical] src/app.ts:12 the token never expires                     [open]
 [low] src/mail.ts:4 the subject is not localized                     [open]

THE COMMIT
 docs(pw): record the run: spec, gate ledger and report (the code is in the
   commits before it)
 on feature/pw, not pushed
```

Its options are Commit, Loop back to Build, Commit and open PR, and More options. Temper never pushes by itself.

## What you can do in between

- **Ask me at every stage.** Pick it at the first question, or set `run.default: ask` in the config, and every stage
  asks its own question.
- **Stop the run.** Press Esc. Then type `/temper:temper` with no words: the run is taken up where it stopped, and the
  question of its stage is asked once.
- **Save for later.** Most questions offer it. The one time config question after the upgrade does not: each of
  its two answers is one call. `/temper:temper` with no words takes the run up again.
- **Several things at once.** A run owns the folder it is started in. Start other work in its own worktree
  (`claude --worktree <name>`), where `/temper:temper` is a run of its own. Build itself runs in groups of tasks, each
  task in its own worktree: `docs/grouped-build.md`.

## A failed check

A failed check gets one repair in the stage where it failed: a failed group gets its fix, a High or critical finding of
Review is fixed by a fresh agent, the CLI commits the fix and runs the checks again. When the check still fails, the run
stops and asks:

```text
Build: the check failed: tests pass: 2 tests fail: unit/app.test.ts. The run stops here and asks you.
```

```text
Temper gate
Build: the check failed (tests pass: 2 tests fail: unit/app.test.ts). Run Build again?
  1. Run Build again (Recommended)
  2. Loop back to Plan
  3. Override and continue
  4. More options
```

Every repeat is counted: 2 for one failure and 6 for one run. Past that, only you allow more.

## `/temper:fix`

For a bug: `/temper:fix "totals drop a cent on export"`. It asks twice too. The root cause and the proposed fix are on
the card of its first question (Approve and fix, Ask me at every stage, Save for later); then a regression test is
written and fails first, the fix makes it pass, and the commit question comes last. It is the cheapest way to try
Temper.

## The config

`.claude/temper.config` holds your choices only, about ten live lines:

```yaml
run:
  default: to-commit          # to-commit | ask (a question at every stage) | never-unattended
packs: [security, tdd]        # the rules the agents follow; more in docs/packs.md
review:
  block-on: [critical, high]  # finding levels that stop a run
autonomy:
  park-on-touch: ["**/auth/**", "**/payment/**", "**/billing/**"]  # sensitive paths
models:
  plan: opus                  # the planner
  task: sonnet                # the builders; haiku costs less and takes longer
```

Every other setting has its default in the CLI. `temper config show` prints each key, its value and where the value
comes from (`config`, `default`, or an old name). A plan that touches a sensitive path is rated high risk and named on
the approval card, and nothing there is repaired by rule.

## Without the mod

The run asks the same questions in the same dialog; only the bar, the pane and the refusals at the tool layer are
missing, and the commit hook still refuses a red commit. Claude Code may run a stage agent in the background, and a
session that sits idle can then leave the run waiting after the agent finished: send any message, such as "go on",
and the run goes on. With `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` set to `1`, Claude Code runs every agent in the
foreground, so a run never waits. Temper does not edit your settings: set it in the shell before `claude` starts, or
add it by hand to the `env` block of the project's `.claude/settings.json`:

```json
{ "env": { "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS": "1" } }
```

It turns off every background task of the session (background Bash commands and Ctrl+B too).

Claude Code's own permission prompts still come as your permission mode says: Temper neither answers nor changes them.

## When to use it, and when not

Use it when a wrong guess is expensive: the request leaves rules out, the change touches money, access or data, or
you need a record of who approved what.

Skip it for a quick script, a one line fix, or a change whose rules are already written down. Plain Claude Code is as
correct there and far cheaper. How Temper differs from Superpowers, Spec Kit, OpenSpec and BMAD Method, and where they
are ahead: `docs/evidence/comparison.md`.

## The words

| Word | What it means |
|---|---|
| run | one request, carried from your words to a commit |
| stage | one of the five steps every request goes through, in order; Build and Review are two of them |
| intent | what will be true when the work is done, from your request and your answers |
| criterion | one line of what will be true that a test or a command can prove |
| plan | the tasks and the files that will change |
| task | one small change with its own test, written first |
| gate | the question where you decide; its header is Temper gate |
| check | something the CLI runs and judges: your suite, coverage, the acceptance tests |
| finding | something Review found, with a level from low to critical |
| repair | one counted fix a rule makes after a failure, before anyone asks you |
| override | you let a failure pass, with a reason that is kept |
| loop back | the work goes to an earlier step and is done again from there |

## What changed from 9.8.4

- **The commands.** Two are listed, `/temper:temper` and `/temper:fix`. The commands of each stage are gone: a run
  starts at Intent, and `/temper:temper` with no words takes up the active run. Status, report, init and pack are
  words of `/temper:temper` now, and so is `draft <idea>`.
- **The default run.** It asks twice: the approval before any code, and the commit. Ask me at every stage keeps a
  question at every stage, and `run.default: ask` makes it the first option.
- **The config.** The template is about ten live lines. On the first run of a project whose config is an older
  template, one question offers to remove the lines that only repeat old defaults or are no longer read; a copy is kept
  as `.claude/temper.config.before-9.8.5`, and Keep my file keeps the old values. `autonomy.enabled: false` becomes
  `run.default: ask`.
- **The first run after the upgrade.** It says once, in one line before anything else, that a run now asks twice. The
  setup runs `temper init` and `temper guards install` once more, so git ignores the new run files and the commit hook
  is current. A run saved by 9.8.4 is taken up where it was, and asks at every stage.
