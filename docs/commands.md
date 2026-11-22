---
title: Commands Reference
nav_order: 3
---

# Commands Reference

Temper lists two commands: `/temper:temper`, the run and its words, and `/temper:fix`. What the other commands of
9.8.4 did is a word of `/temper:temper` (`draft`, `status`, `report`, `init`, `pack`) or gone: a run starts at Intent,
and `/temper:temper` with no words takes up the run that is active.

## `/temper:temper` (the run)

**The one command for a feature.**

```text
/temper:temper "add login feature"
/temper:temper "JIRA-123"
/temper:temper                        # take up the active run
```

> **The short form.** `/temper` is an interactive shortcut that may not resolve in every surface: in `claude -p` and
> CI it does not. Type the full name `/temper:temper`, for example `claude -p '/temper:temper "add login feature"'`.
> With the mod loaded and enforcement on, such a headless run stops at the first question, because only a person in
> an interactive session can approve; with enforcement off it runs on.

**What it does.** A run goes through five stages, Intent, Plan, Build, Review and Check, and ends at the commit:

```
INTENT -> PLAN -> (approval) -> BUILD -> REVIEW -> CHECK -> (commit question) -> COMMIT
```

By default it asks you twice: once before any code is written, and once at the commit.

- **Intent** asks you only what your request left open (who, when, how much, exceptions), as Blocking questions with
  ready answers. With nothing open the run goes on to Plan by itself; you accept the intent with the plan.
- **The approval** is one question with a card that shows the intent's criteria, the files by group, the commands the
  checks run, the launches and what the run does by itself after your click:

  ```text
  Temper gate
  Plan: the check passed. Accept the intent, approve the plan and continue to Build?
    1. Approve and build (Recommended)   Accept the intent. Approve the plan; the run goes on by itself ...
    2. Ask me at every stage             Accept the intent. Approve the plan; every later stage asks you.
    3. Fresh review first                A reviewer with no context reads the plan before you approve it ...
    4. More options                      Open HTML review, Run Design first, Loop back to Intent, Save for later
  ```

- **After Approve and build** the run goes on by itself: a passed check moves on, a failed check gets one counted
  repair by rule, and every other case stops and asks you. It never pushes, never opens a pull request by itself and
  never makes the final commit.
- **The commit question** always asks, with a card of what is true, the suite, coverage, the open findings and
  everything a rule decided since the approval: Commit, Loop back to Build, Commit and open PR, More options.

`run.default` in `.claude/temper.config` orders the first two options (`to-commit`, `ask` or `never-unattended`).
With Ask me at every stage, every later stage asks its own question, as below.

**The questions.** Each one is asked in Claude Code's own dialog, header `Temper gate`, with the options
`temper next --json` gives for the step the run is at; Claude asks it exactly as given, with the mod and without it.

| Answer | What happens |
|----------|--------|
| **Loop back to {stage}** | That stage runs again, and the stages after it are redone |
| **Override and continue** | Skip a failed check with your reason; the report shows it |
| **Accept a finding** | Keep one finding of Review as it stands, with your reason |
| **Grill Me**, **Teach Me** | Questions that stress test the work, or a walk through it |
| **Make a small change** | One small change with no loop back; only what it touches is checked again |
| **Save for later** | Stop and save the run; `/temper:temper` with no words takes it up again |
| **Other** | A change you type: the CLI records it as a note, the stage's agent runs again with it, and the question comes back. Claude never edits a file for it itself. It is not a move. |

At the Check question, **Commit and open PR** opens a draft pull request after the commit, and **Run it anyway** runs
the check once more whatever Temper kept of this tree.

**What each stage reads.** Each stage runs in an agent of its own, with only what it needs:

| Stage | What its agent reads |
|-------|---------------|
| Plan | the intent and the code, through its own agent |
| Build | `tasks.md` and `intent.md`, one task block a task agent |
| Review | the changed files |
| Check | nothing: the CLI runs the commands |

### Modes

With Claude Code 2.1.287 or later, the Temper mod draws the run (a stage bar, a pane and a few other
elements) and refuses writes that do not belong to the current stage. Two plugin options control it.
You change both in `/config`; the mod never changes them itself:

| Setting | Values | Effect |
|---|---|---|
| `uiMode` (Temper UI mode) | `full`, `minimal`, `off` | `full` draws the bar, the pane, toasts, the spinner text, the turn line, the hint and the question header. `minimal` draws the stage timeline only. `off` draws nothing. The mode changes only what is drawn: the questions and the rules are the same in every mode. |
| `enforcement` (Temper enforcement) | `on`, `off` | `on` refuses writes outside the stage, `--no-verify`, a changed hooks path, and a step only you may take without your answer. `off` keeps the drawing only. |

Denials and the words work in every mode. `/temper:temper mode` and `/temper:temper enforcement` say what is set and
where to change it. `docs/mod.md`, "Where enforcement works", shows what is covered and what is not.

### The stage bar

In `full` mode the bar above the prompt shows `TEMPER`, the run's title, the step in plain words
("Step 2 of 6: Plan"), the stages as chips (green with a check for passed, red with a cross for a failed
check, yellow for a stage you skipped, a filled chip for the stage you are at, plain chips for the stages
to come), the loops back with their reasons, the time of the run, one sentence of status
("Plan: waiting for your answer to the Temper gate question.") and the details of the stage: the groups and tasks
of Build, the open findings of Review, the failed checks. Under about 100 columns (for example while the pane is
docked) the bar uses a compact form without borders. `minimal` shows the chips only.

The bar has no button and decides nothing. To take a run up again, type `/temper:temper`: Claude asks
the question again. The pane repeats the run on one card: the plan's files by group, the Build grid with each task's
state, model and retries, the Review findings, the Check markers, the acceptance criteria ("what must be true") with
their evidence, the loops with their reasons and your decisions; it has no button. At the commit, the report is
printed in the terminal, and `temper report --html` writes the same as one page, `report.html` in the spec folder.

### One flow

The questions are the same with the mod and without it, in every mode. The CLI judges every check, and each stage
runs with its own brief. With the mod loaded, the mod reads your answer from the dialog's result, counts it only when
the header, the question and the label are exactly what the CLI wrote, and lets through the calls of that option, at
the step the run is at; a step back or a skip needs your reason, and the dialog asks for it when your answer has none.
Once the run moves on, the answer is spent.

### Each stage

| Stage | Writes allowed |
|---|---|
| Intent | `intent.md` only |
| Plan, Design | `intent.md`, `plan.md`, `tasks.md` and `design.md` (a decision record goes into `design.md`) |
| Build | The files in the plan, test files and the spec folder |
| Review | The spec folder only |
| Check | The spec folder only |
| Done | Nothing is blocked |

A plain `git commit` goes to the native `pre-commit` hook in every stage, and the hook decides: it lets a spec only
commit, a Build checkpoint and a repair commit of the CLI through, and every other commit only when every gate passed
or was skipped with a reason. A commit the hook does not check (a merge, a cherry-pick, a revert, a commit of named
paths) is not refused by the mod either; `docs/trust.md` lists it. Save for later stops the run and lifts no rule.

A file outside the plan is never written first. The agent records it with `temper drift ask`, and the CLI asks the
Scope drift question: add the file to the plan, revert (go on without it), or allow it once (the agent's why becomes
the recorded reason), in a run that goes on by itself too. Each choice is logged. Every repeat after a failed check
is counted against one budget: 2 repeats for one failure and 6 for the run, then one question where only you allow
more (ADR 0019).

## The stages

### Plan

Plan writes what a later step reads: `tasks.md` (groups of small tasks, each with its files, its test command and its
cases), the scenarios in `intent.md` (four lines each: its name, one Then line, `Covers:` and `Test:`) and, above the
simple tier, `plan.md` with a Context Map and a Blast Radius. A scenario is owed by the task that declares the file
its `Test:` command runs. The planner's last calls run each group's Validate and the Integration line once on the
current code, then the plan gate. A part of `tasks.md`:

```markdown
## Group G1: Reset tokens
**Depends:** none
**Validate:** `npm test`

### Task 1: Create PasswordResetService
**File:** `src/auth/PasswordResetService.ts`, `unit/PasswordResetService.test.ts`
**Depends:** none
**Test:** `npm test`
**Cases:**
- a fresh token resets the password
- an expired token is refused
```

Tasks with no dependency between them, and with files that do not overlap, run at the same time, each as its own task
agent in its own worktree (`docs/grouped-build.md`).

### Design

Design writes `design.md` (the components, the API contracts, the data changes, the decisions) only when you ask for
it: choose `Run Design first` under More options at the approval. No tier and no risk adds it. A question Design would
have asked is a Blocking question Plan writes, and you answer it before the approval.

### Build

Build runs the plan's groups (`docs/grouped-build.md`); the CLI drives it:

- First an agent that writes no code writes the acceptance tests from the intent, and they are locked.
- It starts each group whose dependencies passed, in its own worktree, and hands out the ready tasks; each runs as a
  small task agent (Sonnet) in its own worktree and writes the test of each listed case first (RED), then the code
  (GREEN).
- The CLI gates each task from the test runs it made itself, commits it on the task branch and merges it into the
  group branch. A failed task is retried, then escalated; after that its group stops and asks you.
- When Build ends, the CLI merges the groups and runs, once, the suite with its coverage, the scenario tests and the
  locked acceptance tests. Check reuses those runs on the same tree.

**What you see:** the bar shows the step and the groups; the pane shows the Build grid, one row a task with its state
(waiting, running, RED, GREEN, PASS, FAIL, stopped), model and retries.

**Taking it up again:** the run's state is the CLI's, so `/temper:temper` with no words takes Build up where it
stopped: the CLI hands out the tasks that are still to do, or waits for the agents still running.

### Review

Review reads the changed files against the intent, the enabled packs and the scenarios, and records each finding with
its level (low, medium, high, critical) and its file and line. It names the files it read; a changed file it did not
read fails its gate. Findings at a level of `review.block-on` (default `critical, high`) fail the Review gate. A High
or critical finding is repaired in the stage once by rule: a fresh Build agent fixes it, the CLI commits the fix and
runs the checks again, and a reader that did not write the fix confirms it. Only the CLI closes a finding. A Medium
finding goes on to Check and is listed at the commit question.

### Check

Check runs the project's own checks on the built tree: the suite and its coverage, the acceptance criteria with a
command, and the scenario tests, reusing what Build ran on the same tree. Coverage may not drop against the code before
the run; a missing coverage tool is shown as not measured, never as passed or failed. A criterion you validate by hand
is confirmed by you at the Check question. The CLI judges every row (`docs/flow.md`).

## Words of `/temper:temper`

`/temper:temper` takes a few words in place of a feature. A word counts only in its documented form: `status`,
`report`, `timeline`, `help`, `init`, `pack`, `mode`, `enforcement`, `pane`, `pr` and the wishes count only alone,
with nothing after them; `draft` takes the idea after it, and `pack` takes `enable guardrails` or `disable
guardrails`. Any other text is a request, a feature description, even when it starts with one of these words:
`/temper:temper status badge on the order page` starts a run for that feature. The short form `/temper` is an
interactive shortcut that may not resolve in every surface; `/temper:temper` always works, and the mod's own
messages use it.

| Word | What it does |
|---|---|
| `/temper:temper status` | Where the run stands: stage, task, criteria passed, loop count |
| `/temper:temper timeline` | Your decisions in this run |
| `/temper:temper approve`, `next`, `back`, `override`, `accept`, `drift` | Your wish, not a move: Claude runs the loop and asks the gate question exactly as the CLI gives it. You choose there. |
| `/temper:temper report` | The run report: verdicts, skips with their reasons, loops, usage. Without the mod it is `temper report`; with it, the mod's report from `view.json` and your decisions, kept in its plugin store. The page to share is `report.html` (below). |
| `/temper:temper pr` | Ask Claude for a pull request description from the report |
| `/temper:temper draft <idea>` | Capture an idea as a draft `intent.md`, with no run (below) |
| `/temper:temper init` | Set up this project: the config, `.temper` and the commit gate (below) |
| `/temper:temper pack` | The quality packs; `pack enable guardrails` and `pack disable guardrails` print the guard hooks to add or remove (below) |
| `/temper:temper mode` | Say how much Temper draws, and that you change it in `/config` (Temper UI mode) |
| `/temper:temper enforcement` | Say whether denials are on, and that you change it in `/config` (Temper enforcement) |
| `/temper:temper pane` | Open or close the pane (in full mode it also opens by itself when a run starts; see [the mod](mod.md)) |
| `/temper:temper help` | List these |

With the mod off, every stage works the same; the mod adds the bar, the pane and its write guards. Nothing falls back
silently.

A word that names a move (`approve`, `next`, `back`, `override`, `accept`, `drift`) is your wish, not
your decision: you decide in the question dialog that follows, with one click. Claude cannot decide for
you. With the mod loaded it answers the words that only show something (`status`, `timeline`,
`report`, `help`, `pane`, `mode`, `enforcement`) itself; every other word goes to the prompt
based command, so it works the same on every surface.

With the mod loaded and enforcement on, a headless `claude -p` run stops at the first gate, because
only a person can answer the gate question. With enforcement off a headless run goes on.

A run starts at Intent, and `/temper:temper` with no words takes up the active run where the CLI says it is. A folder an
earlier run planned, with no run active, is started from its `intent.md`: Plan runs again.

### `draft`

Capture an idea as a draft `intent.md` (the artifact that starts the pipeline) without starting a run. Claude reads
`reference/draft.md` and runs the interview in the main session.

```text
/temper:temper draft handlers spend a third of call time on status-only queries
/temper:temper draft JIRA-4521
```

- Interviews the originator the way an analyst would (scope, constraints, what better looks like), with no formal
  language required of them.
- Writes `.temper/specs/{slug}/intent.md` with `Status: draft`, the author (a name you typed, else `the person`;
  never from git), Problem, measurable Success Criteria, Constraints, Scope and Non-goals, and Open Questions, and
  no scenarios and no architecture: those are Plan's, derived from the measured blast radius later.
- Keeps criteria and constraints firm: `temper gate intent` fails a draft that uses should, may, might or possibly
  in one, unless the line carries a `(source: ...)` marker. The session that typed the word owes that gate: the
  stop hook holds it until the gate ran (ADR 0005).
- Offers to commit the draft, so its author, date and history live in version control.

`Status:` goes from `draft` (this word) to `accepted` (your approval of the plan) to `completed` (the commit step).
A later `/temper:temper "{slug}"` finds the folder by its `intent.md` and builds on the draft, never over it.

### `init`

Set up a project; the first `/temper:temper "..."` in a project that is not set up does the same by itself. Claude
runs three calls, each once, and shows what each printed:

- `temper config init` writes `.claude/temper.config` from the bundled default when it is missing; an existing config
  is never overwritten.
- `temper init` scaffolds `.temper/` (the gate ledger, the overrides log, the feedback loop registry).
- `temper guards install` (`scripts/guards/install.sh`) writes the native commit gate, the pre-commit hook that
  blocks `git commit` while a gate is red, to `temper-gate/pre-commit` in the repository's git folder (never
  committed, shared by every worktree), and points `core.hooksPath` there.

Temper opens no Claude Code settings file and never writes into a folder named `hooks`. When you already have a
pre-commit hook (in `.git/hooks`, husky, the pre-commit framework, lefthook or a team folder), the installer leaves
`core.hooksPath` and your hooks as they are, keeps the Temper hook in the git folder, and prints the one line to paste
into your hook between its BEGIN and END lines, with a hint that says where it goes for your tool. The line holds no
path of this machine, so it is safe to commit. Run the installer again after you move the repository or upgrade the
plugin; it makes the hook current. `temper guards uninstall` removes the Temper hook and its folder, unsets
`core.hooksPath` when it names that folder, and names a Temper line in your own hook for you to remove.

### `pack`

The quality packs: view, toggle, quick-create a launcher pack, configure links and stages, or build a new pack.

```text
/temper:temper pack
/temper:temper pack enable guardrails
/temper:temper pack disable guardrails
```

**What it does:**

- Shows every pack it finds, from two places: the project's `.claude/packs` folder and the built-in packs. A
  project pack takes the place of a built-in one of the same name. Nothing in your home folder is read (9.8.5).
- Lets you toggle packs on or off, quick-create a launcher pack, set a pack's link and stages, or build a new pack
- Prints the guardrails pack's guard hooks for you to add, or says which to remove (see [Guardrails](#guardrails)).
  It opens no Claude Code settings file.

**Output:** a Quality Pack Manager panel (its exact shape is in `reference/pack.md`, under
"Step 1: Discover + Display") with one row per pack, filled from what it found, and a last line
`N packs total (X enabled, Y disabled)`. The columns:

| Column | What it shows |
|--------|---------------|
| NAME | The pack's name |
| STATUS | `ON` when the pack is in `packs:`, otherwise `OFF` |
| STAGES | The stages that load the pack (`all` when none are set; the key is `phases`) |
| LINK | The pack's `plugin://` or `skill://` link, if it has one |
| CONNECTED | Whether that link target was found |

**Options:**

| Option | What it does |
|--------|-------------|
| **Toggle packs on/off** | Select packs to enable or disable. Turning `guardrails` on prints its hook entries for you to add; turning it off says which to remove. Temper opens no settings file. |
| **Quick-create launcher pack** | Wrap a skill or command as a BLOCK-level pack in the project's `.claude/packs` folder. |
| **Configure pack (link, stages)** | Set the link target or the stages of an existing pack. |
| **Done** | Exit. To open the full pack builder instead, choose **Other** and describe the pack. |

**Link targets.** A launcher pack or a link points at a skill or command. The choices are the
skills and commands this Claude session lists (a plugin's show as `plugin:item`) and the
project's own commands and skills in `.claude/commands` and `.claude/skills`. A
`plugin://name` link counts as connected when the session lists a skill or command of that
plugin, and a `skill://name` link when the session lists that skill or the project has it.
Temper reads no Claude Code file to find them.

**The full pack builder** (choose **Other**, then describe the pack): Claude reads the code base for its patterns
(constructor injection, data transfer objects, structured logging), asks you for each one whether it is a BLOCK, WARN
or SUGGEST rule, and writes `.claude/packs/<name>/rules.md`, which you then turn on in `packs:`.

### Guardrails

The guardrails pack adds edit-time guard hooks: secret blocking, protection of the regression test
and of frozen paths, the in-agent commit gate, an approval prompt before an override, a forbidden
import check and auto-format. They are off until you turn them on.

The secret check scans only what a call adds: the content of a Write, the new text of an Edit
(each new text of a MultiEdit) and the command of a Bash call. So an edit that removes a secret,
or the command that unstages one, is not refused. The staged files are scanned only by the native
`pre-commit` hook, at commit time.

`/temper:temper pack enable guardrails`:

1. Refuses, in one line, when the project folder is your home folder (its settings files would
   then be your user settings), or when the plugin folder's path holds a character that cannot sit
   safely in a quoted command: a quote, a backslash, a dollar sign, a backtick or a line break.
2. Prints the hook blocks of the pack's `settings-guardrails.json` as JSON, through
   `scripts/guardrails-snippet.py`, which reads that one file of the plugin and nothing else. A hook
   in a settings file gets no CLAUDE_PLUGIN_ROOT variable, so each command is written out in full:
   `bash`, a space, then in double quotes the plugin's absolute folder followed by
   `/scripts/guards/` and the guard's script name, such as `block-secrets.sh`.
3. Says where they go: you add them to the `hooks` object of `.claude/settings.local.json`
   (personal, recommended, because each command holds this machine's plugin folder; keep it out of
   git) or `.claude/settings.json` (shared with your team; a teammate whose plugin sits in another
   folder gets commands that point at a missing folder), and replace any earlier Temper guard
   entry there. Temper never opens either file.
4. Adds `guardrails` to `packs:` in `.claude/temper.config`.

`/temper:temper pack disable guardrails` removes the `guardrails` entry from `packs:` and says which
entries to remove from your settings files.

A Temper guard entry is a hook command that names one of the guard scripts (`block-secrets.sh`,
`protect-regression-test.sh`, `block-protected-paths.sh`, `block-uncommitted-gate.sh`,
`confirm-override.sh`, `block-forbidden-imports.sh`, `run-formatter.sh`, `stage-marker.sh` or
`verify-stage-gate.sh`) under the current plugin folder, under the guard scripts folder of
an older version or an older plugin folder outside the project, or through a path that starts with
the CLAUDE_PLUGIN_ROOT variable. A command that runs your own copy of one of these scripts (a
relative path, a path through `CLAUDE_PROJECT_DIR`, or a path inside the project) is yours, and
stays.

A plugin upgrade moves the plugin folder, and a guard command added before it then points at a
folder that is gone or out of date. Run `/temper:temper pack enable guardrails` again to print the current
commands, and put them in place of the old ones.

The pack does not print the stage gate pair (`stage-marker.sh` and `verify-stage-gate.sh`): the
plugin's own hooks already run them. The words `pack` and `init` never open a Claude Code
settings file, the project's or your home folder's. The commit-time layer is the native `pre-commit` hook, which
the word `init` installs.

### `status`

`/temper:temper status` prints `temper status` (each criterion, passed or open, with its evidence) and the one line
of `temper next --json` that says where the run is. The other read only calls stay calls of the CLI: `temper report`
(the gate ledger) and `temper drift` (each finished spec against the tree as it is now).

## `/temper:fix`

A bug: root cause, a regression test that fails first, a minimal fix.

```bash
/temper:fix "JIRA-123: users cannot reset their password"
```

It asks twice, as a feature run does. The root cause agent writes `rca.md`, and its question is the approval: its
card shows the bug as you typed it, the cause, the fix, the regression test, the files, the test command and the risk.

```text
Temper gate
RCA: the root cause and the proposed fix are on the card. Approve the fix?
  1. Approve and fix (Recommended)   Approve the fix; the run goes on by itself ...
  2. Ask me at every stage           Approve the fix; every later stage asks you.
  3. Save for later                  Stop here. The run is saved; /temper:fix takes it up again.
```

After Approve and fix, a passed Fix, Review and Check move on by rule, and the commit question offers Commit, Loop
back to Fix and Save for later, never a pull request. A change you type at the root cause question runs the root cause
agent again with it. `/temper:fix` with no words takes an active fix run up again.

## The config

A new project's `.claude/temper.config` is the template of 10 live lines (`run.default`, `packs`, `review.block-on`,
`autonomy.park-on-touch`, `models.plan` and `models.task` with their parents) and two commented blocks
(`check.commands` and `setup`). Every other setting has its default in one table of the CLI, `scripts/defaults.py`
(ADR 0023), and a line of your config wins over it.

```text
temper config show              each key, its value and where it comes from: config, default, or old name <key>
temper config show --markdown   the table below
temper config get <key>         one value; with no default given, the table's
temper packs --stage <stage>    the pack files the agent of that stage reads, as its prompt's Packs: line names them
```

`config show` also names each key of your file that is gone (with what replaced it) and each key it does not know
(`not read: <key>`); neither is an error. With no `run.default` line and `autonomy.enabled: false`, `run.default` is
`ask`, as the flow reads it: `config show` and `config get run.default` say so, with the source
`old name autonomy.enabled`. `scripts/check_config_keys.py` holds the table to the code: every key has a
reader, and no page names a key the table lacks.

The keys, as `temper config show --markdown` prints them:

| Key | Default | What it sets |
|---|---|---|
| `run.default` | `to-commit` | the approval's first option: to-commit (the run goes on by itself to the commit), ask, or never-unattended |
| `packs` | `[security, tdd]` | the packs whose rules the agents follow; the CLI names their files in each prompt (`temper packs`) |
| `review.block-on` | `[critical, high]` | the finding levels that fail the Review gate |
| `autonomy.park-on-touch` | `["**/auth/**", "**/payment/**", "**/billing/**"]` | sensitive paths: a plan that touches one is risk H, named at the approval, and nothing there is repaired by rule |
| `models.plan` | `opus` | the planner's model, over the table of `scripts/cli_ctx.py` |
| `models.task` | `sonnet` | the model of the Build task agents; haiku costs less and takes longer |
| `models.<agent>` | the table of `scripts/cli_ctx.py` | the model of one agent, over the table of `scripts/cli_ctx.py` |
| `models.high.<agent>` | the table of `scripts/cli_ctx.py` | the model of one agent in a run of tier complex or risk H |
| `check.commands.test` | none | the test command Check runs instead of the one it detects |
| `check.commands.coverage` | none | the coverage command Check runs instead of the one it detects |
| `check.coverage-threshold` | none | a coverage floor, read only when set; with none, coverage may not drop against the base |
| `setup.run` | none | one shell line the CLI runs before each command it runs |
| `setup.env` | none | variables set for each command; a credential name is never set or shown |
| `setup.services` | none | services that must answer (name: host:port) before the checks run |
| `setup.tools` | none | programs the commands need |
| `build.grouped.max-parallel` | `4` | Build tasks running at once |
| `build.grouped.max-groups` | `2` | groups working at once |
| `build.grouped.keep-days` | `30` | days an earlier attempt's work is kept (0: always) |
| `build.red-before-code` | `false` | true: a task's failing run counts only on the code as the attempt found it, with no stub |
| `autonomy.max-blast-radius` | `15` | the plan gate splits a group that declares more files than this |
| `budget.per-failure` | `2` | repeats for one failed check |
| `budget.per-run` | `6` | repeats in one run |
| `plan.context-check` | `auto` | auto: ask when the Context Map has an ignore or a gap; always; off |
| `plan.fresh-review` | `ask` | a reader with no context reads the plan: ask, auto, always or off |
| `plan.fresh-review-twice` | `true` | a risk H plan gets two fresh readers |
| `plan.fresh-review-rounds` | `3` | launches of the fresh review in one run, at most |
| `phases.pipeline` | `true` | false: no Pipeline stage after a commit that opened a pull request |
| `protect.paths` | none | paths no agent edit may change (the guardrails pack) |
| `format.cmd` | none | a formatter run on each agent edit, {file} for the file (the guardrails pack) |
| `upgrade.asked` | none | the version whose one time config question was answered Keep my file |

### The one time question

The first `/temper:temper` run of a project whose config is an older template (9.8.4 or before) asks
`config.tidy` before anything else: the config holds N lines that only repeat old defaults or are no longer read; the
question names at most eight of them with what changes (the coverage floor, `phases.design`, the five packs and
`block-on: [critical]` first) and says a copy is kept.

- `Remove them (Recommended)` runs `temper config tidy --apply`: the old file is copied to
  `.claude/temper.config.before-9.8.5`, and the file becomes the new template with the lines you changed, in place of
  its lines or after them; a `packs:` list in block form stays as you wrote it. `autonomy.enabled: false` becomes
  `run.default: ask`, never the new default. The copy is never overwritten: when it is there already with other text,
  the old file goes to `.claude/temper.config.before-9.8.5.2` (or the next free number). With nothing to remove the
  call changes nothing and writes no copy.
- `Keep my file` runs `temper config tidy --keep`: the file stays and gets `upgrade.asked`, so the question is not
  asked again and the old values still rule.

The question is asked only at Intent before the first agent of a `/temper:temper` run. The two calls exit 1 and change
nothing past Intent, in a fix run or in a run that goes on by itself; at Intent, or with no run active, they run, so a
person can also type them. Typed after `Keep my file`, `--apply` still removes the old lines: `upgrade.asked` stops
the question, not the call. A project made by `config init`, or a file `Remove them` wrote, is never asked: such a
file starts with the first line of the template, and a value set in it later is the person's own.

### What became of an old key

| Key | Now |
|---|---|
| `stack` | gone: the CLI detects the stack |
| `packs` | a live line, default `[security, tdd]`; the five packs of the old template are an old default |
| `review.block-on` | a live line; `[critical]` is an old default |
| `check.coverage-threshold` | read when set; `80` is an old default, and with none coverage may not drop |
| `check.environment`, `check.mutation-threshold` | gone: Check decides from file names; the planted bug score is information |
| `tools.mode` | gone: an agent uses a connected tool when there is one |
| `plan.context-check`, `plan.fresh-review`, `-twice`, `-rounds` | in the table; their old template values are old defaults |
| `plan.preflight-timeout`, `plan.preflight-skip` | gone: the plan's commands run once on the base |
| `phases.design` | gone: Design runs only when you ask for it |
| `phases.pipeline` | in the table; `true` is an old default |
| `feedback.enabled`, `loops.max-per-type`, `fix.max-loops` | gone: one budget of repeats (`budget.per-failure`) |
| `autonomy.enabled` | read as `run.default: ask` when false; the question writes that line |
| `autonomy.policy`, `autonomy.budget.max-total-loops`, `.max-stages` | gone: `run.default` and one budget (`budget.per-run`) |
| `autonomy.max-blast-radius` | in the table; `15` is an old default |
| `build.grouped.task-model`, `build.grouped.escalation-model` | read as the old names of `models.task` and `models.task-escalation` |
| `build.grouped.max-parallel`, `.max-groups`, `.keep-days`, `build.red-before-code` | in the table |
| the `evidence` block (claimed runs) | gone: a test run an agent only claimed counts at no gate (9.8.5) |
| the `bands` block | gone, with the control bands |
| `tools` (the external review engine) | gone: no diff leaves the machine through Temper |

## The CLI calls

### `temper doctor` (9.8.5)

`scripts/temper doctor` shows the environment a run will use, and changes nothing: it writes no file, ledger, state or
`view.json`. It prints three parts:

- **Toolchain:** the first line of each tool's version (`setup.tools`, else java, mvn, python3, node and git), or
  `not on PATH`. It reads the shell as it is.
- **Setup block:** `none`, or the run line with `(not run by doctor: it may start a service)`, each variable as
  `NAME=value`, and each credential name it left out.
- **Services:** for each `setup.services` entry, `answering` or `not answering` (a TCP connect, 2 seconds). With no
  such entry, the database and cache services the project's files ask for (a compose file in the root, the CI file),
  each with the file that names it. These are the services the environment check of a run tries; to say which
  services must answer on this machine, name them under `setup.services`.

The mod lets it run during a run, as any CLI call. Use it when a gate says `environment fault` or `ENV:`.

**How Temper finds the setup of a project it has never seen.** Two sources, one check:

1. **Rules, for common setups** (`temper doctor --propose`): the JDK a Maven enforcer, `<java.version>`, a Gradle
   toolchain, `.java-version` or `.tool-versions` asks for, set by the project's `scripts/ensure-jdk*.sh --export` (else
   a JDK of that version in `/usr/lib/jvm`); Docker Compose services (Postgres, MySQL, MariaDB, Redis) when a Docker
   daemon answers; a local Postgres cluster; a Python `.venv`; an `.nvmrc`.
2. **The project's CI and devcontainer** (the same command): GitHub Actions (`actions/setup-java` and `setup-node`
   versions, a job's `services:` with their images and ports, the variables that point at them, such as
   `IT_POSTGRES_PORT: ${{ job.services.postgres.ports['5432'] }}`), `.gitlab-ci.yml` image tags, and
   `.devcontainer/devcontainer.json` features. A CI service starts with Docker when its daemon answers, else with a
   local server of that kind. Only a database variable with a local port or host is taken from a CI `env:`; deploy
   targets and credentials never are.

No agent drafts a block: the environment agent and `temper doctor` with a draft file of its are gone.

**The block reaches the config only by your answer.** `temper doctor` and `temper doctor --propose` read;
`temper doctor --propose --write --expect <hash>` adds the block, and the mod lets it run only as the call of the option
you picked. When the environment check or Check fails on the environment and the project has no block, the question
offers `Add this setup block and run it again` (at the red base question `base.red` first, at Check first), and the
question shows every line of the block (the run line with its secrets masked). The call writes the block the question
showed, bound by its hash (refused when the proposal changed since, and never over a block that is there); `--write`
without `--expect` writes nothing. No command is run to check a block: the baseline that runs next (at `base.red`) or
Check run again is its check. A block that fakes a tool passes every check of the CLI, so your reading of it is the
control. When no rule proposes a block, the question says what is missing, in the words of the fault.
What no source can make (a missing licence, a secret, a VPN, a JDK the machine does not have and the project cannot
fetch) is said in plain words instead.

### `temper baseline`

`temper baseline start [--again] [--env-only]` checks the environment (the tools and services the project's files and
the config name, in under 5 s) and runs the project's suite once on the current code, in the detached worktree
`.claude/worktrees/temper-baseline`, in its own process; it writes `.temper/evidence/baseline.json` and always exits 0.
The flow calls it as its own first step of a run; `--again` runs it after a repair, `--env-only` checks the environment
and runs no suite (the flow no longer calls it, 9.8.5). `temper baseline clean` removes the worktree (`state clear` and
`state init` call it). `temper baseline accept-red --reason '<why>'` is your answer "Go on anyway" at the red base
question: the base's failures become a recorded skip (an override row `base-suite`); the mod lets it run only as the
call of that answer. `python3 scripts/check_run.py owner ROOT [SPEC]` prints who owns the suite command, as one JSON
line `{"test", "run", "source", "why"}`. See `docs/flow.md`, "The environment check and the baseline".

`temper baseline plan [--cmd C]` runs each group's Validate and the Integration line of the plan once on the
current code, in the same worktree, after the suite, in its own process, and keeps each result in `plan` of the same
file; only a command with no result runs, and `--cmd C` runs C again. The planner's last calls run it, before
`temper gate plan`, which runs no command. `temper baseline skip --cmd C --reason '<why>'` is your answer "Go on anyway"
at `plan.command`: the check of that command is skipped (an override row `plan-command`); the mod lets it run only as
the call of that answer. See `docs/flow.md`, "A command the plan wrote".

### `temper plan patch` (9.8.5)

`temper plan patch G1 --cmd 'bash scripts/selftest/run-selftest.sh --fast'` changes one command line of the approved
plan (`G<n>` a group's Validate, inserted after its Depends line, or after its head, when it has none; `task N` a task's
Test, which reopens the task when it passed, and is refused before anything is written when that reopen cannot run
(no worktree, a task it cannot reopen, a commit on the group's branch the CLI did not record, an upstream gate it
needs); `integration` the Integration line), keeps every other passed task, and spends one repeat.
`temper plan patch task N --add-file F` adds a file outside the approved set to Task N and to `approved_files` (a name
with no dot and no slash is written `./F`, so the plan reads it as a file). The static rows of the plan gate run on the
result first, and a row it newly fails refuses the patch. You give it as your answer to "Change the group's command" at
the group question, to "Add to plan" at a task blocked on a file no task declares, or to "Change the command" at
`plan.command` (there, before the approval, it changes the line of the plan, which is checked again).

### `temper plan amend`

`temper plan amend task N --add-file F [--failure ID]` is the amendment by rule: it adds to Task N a file a task of its
own group declares that precedes Task N or passed, and that task to its Depends line, and nothing else. The CLI writes
both lines, refuses every other change (see `docs/flow.md`, "A blocked task and the plan amendment"), spends one repeat
(`task:N`), appends to `.temper/evidence/amendments.json` and reopens the task. The flow calls it by itself when a task
is blocked on such a file; any caller may, because its whole effect is bounded by the CLI.

### `temper group keep`

`temper group keep` is the first Build action after a replan's approval: it restores the built tasks of the earlier
plan whose files, Depends and Test did not change, with their group branches (see `docs/flow.md`, "What a replan
keeps"). It runs once per replan and is a no op otherwise.

### New in 9.7.5

| Command | What it does |
|---|---|
| `temper plan review --answer '<text>' [--focus '<area>']...` | Writes the person's answer into the Context Map of `plan.md` and sets `- reviewed: human`. This is the Context check, not the HTML plan review (`Open HTML review`, `Share HTML review`), which is a different feature and works as before. |
| `temper risk [--raise L\|M\|H --reason '<why>']` | Computes the plan's rating from the blast radius; a raise needs a reason and never lowers it. |
| `temper adhoc open --stage S --reason '<why>'` / `temper adhoc close` | The small change window at Build, Review, Check, Commit or Pipeline. |
| `temper task confirm N --by '<name>'` | The person confirms a manual task (`**Test:** manual`). The name is the one they give, never read from git. |
| `temper task accept N --reason '<why>'` / `temper task retry N` | The person's answer for a task whose tests pass before any change. |
| `temper task gate N --model M --no-env` | 9.8.5: the person's answer "It is the code" at a task held on an environment fault: the gate reads the failed GREEN run it has and gives no ENV verdict, so the task fails and its attempt is spent. |
| `temper group gate G<n> --timeout-s N` | A limit for the group's own runs; a timed out gate offers a rerun at double. |
| `temper check run --fresh`, `temper group gate G<n> --fresh`, `temper integrate --fresh` | 9.8.5: the person's Run it anyway: the check runs whatever the reuse store keeps for this tree, its row is marked `forced`, and it spends one repeat of the budget. A run that goes on by itself is refused it (`BLOCKED`), and no environment variable stands in for the flag. |
| `temper evidence add --stage check --criterion AC-NN --claim '<text>' --cmd '<how>' --exit 0 --person` | 9.8.5: the person's Confirmed at the Check question: a row marked `executed_by: person`, the only row a criterion validated by hand (or by `code` or `metric` with no command in backticks) counts from at Check. The CLI takes the flag only with a criterion and exit 0, and refuses it (`BLOCKED`) in a run that goes on by itself with no stop open; only the mod ties it to the person's click. |
| `temper evidence add --phase note --kind input\|edit --claim '<text>'` | A note the next stage agent reads (`Task N:` and `Group G<n>:` prefixes scope it to Build tasks). |
| `temper evidence contest --stage S --id N --cite <file>[:<line>\|:<symbol>] --quote '<text>' --reason '<why>'` | 9.7.6: the author answers a finding with evidence the reviewer could read; the CLI checks the file, the line or symbol, and that the quote is there. A comprehension finding is never contested. The finding stays open for the person. |
| `temper evidence escalate --stage S --id N --reason '<why>'` | 9.7.6: the evidence is outside every file; the person decides. |
| `temper drift [--run] [--json]` | 9.7.6: each finished spec compared with the tree as it is now (a planned file gone, a scenario test gone, a planned file changed since). `--run` also runs each scenario's `Test:` command and names the ones that fail now (behavior drift). Never a gate. |
| `temper plan fresh request\|start\|again` | 9.7.6: the fresh review of the plan: the person asks for it (`plan.fresh-review: ask`), the orchestrator marks a launch (only rows recorded after it count), a reviewer that did not finish runs again. |
| `temper model --all --source` | 9.8.5: every agent's model from the one table of models (`scripts/cli_ctx.py`), and whether it comes from the `config` or the `table`. The table has two columns: `standard`, and `high` for a run of tier complex or of risk H; `plan`, `design` and `rca` are on Opus in both, every other agent and the task agents on Sonnet. The keys, in the order they win: `models.high.<agent>` (when the class is high), `models.<agent>`, for the task agents the old `build.grouped.task-model` and `build.grouped.escalation-model`, then the table. The first planner launch of a run has no risk and no final tier yet, so its class is `standard`: the `high` column decides later launches and every agent after the plan (`models.plan: sonnet` with `models.high.plan: opus` keeps Opus at risk H). `temper model <agent>` prints one. |
| `temper guards uninstall` | Removes the Temper commit hook and its folder; unsets `core.hooksPath` when it names that folder. |
| `temper gate commit --from-hook` | The hook's call: it gates a commit on the run's branch only. |
