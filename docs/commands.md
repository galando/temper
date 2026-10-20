---
title: Commands Reference
nav_order: 3
---

# Commands Reference

## `/temper` (Unified Command)

**The one command for the full SDLC.**

```text
/temper:temper "add login feature"
/temper:temper "JIRA-123"
/temper:temper                        # Resume or continue the current run
```

> **The short form.** `/temper` is an interactive shortcut that may not resolve in every
> surface: in `claude -p` and CI it does not. Type the full name `/temper:temper`, for
> example `claude -p '/temper:temper "add login feature"'`. All other commands
> (`/temper:plan`, `/temper:build`, etc.) already use their full form. With the mod loaded
> and enforcement on, such a headless run stops at the first gate, because only a person in
> an interactive session can approve; with enforcement off it runs on (see [Subcommands](#subcommands)).

**What it does:**

Runs the full software development lifecycle with stage gates:

```
INTENT → (gate) → PLAN → (gate) → BUILD → (gate) → REVIEW → (gate) → CHECK → (gate) → COMMIT
```

The **Intent gate comes first and is deliberately cheap**: you approve (or correct) the
Problem, success criteria, and constraints before any exploration or architecture work
spends tokens — an intent correction at this gate costs words; the same correction
after Plan costs the whole plan, because every downstream artifact is derived from the
intent. Trivial requests (a typo, a one-liner) skip it automatically.

**Stage Gates:**

At each gate Claude asks one question in Claude Code's own dialog, header `Temper gate`, with the
options `temper next --json` gives for that gate. After the plan:

```text
Temper gate
Plan: the check passed. Approve the plan and continue to Build?
  1. Continue to Build (Recommended)   Approve the plan, commit it, and start Build.
  2. Open HTML review                  Open the plan as a page to comment on.
  3. Share HTML review                 Publish the plan as a private Claude artifact others can comment on.
  4. More options                      Grill Me, Teach Me, Save for later
```

| Response | Action |
|----------|--------|
| **Continue to Build** | Approve the plan, commit it, and start Build |
| **Grill Me** | Socratic challenge mode — adversarial questions that stress-test your plan |
| **Open HTML review** | Browser-based review with inline comments (Google Doc-style) |
| **Share HTML review** | Publish the same review as a Claude artifact so other people can comment by link, and their comments come back automatically. Without the Artifact tool it offers Open HTML review instead. Asks before anything leaves your machine |
| **Save for later** | Stop, save state, resume later with `/temper:temper` |
| **Other** | Type a change request: Claude makes it, the gate runs again, and the question comes back. It is not a move. |

**Review Gate Additional Options:**

| Response | Action |
|----------|--------|
| **Loop back to Build** | Build fixes the open findings, then Review runs again |
| **Accept a finding** | Keep one finding as it stands, with your reason |
| **Architecture Depth Review** | Module-depth analysis: seams, adapters, locality, leverage, deletion test |

**Check Gate Additional Options:**

| Response | Action |
|----------|--------|
| **Commit** | Commit with conventional message |
| **Review config suggestions** | Review CLAUDE.md/AGENTS.md suggestions based on what was built |

**Context Management:**

Each stage gate clears context and loads only what's needed:

| Stage | What's Loaded | Size |
|-------|---------------|------|
| PLAN | Full codebase (via subagent) | Large (temp) |
| BUILD | tasks.md + intent.md | ~5-10KB |
| REVIEW | Changed files only | ~20-50KB |
| CHECK | Nothing new | 0KB |

### Subcommands

The short form `/temper` is an interactive shortcut that may not resolve in every surface;
`/temper:temper` always works, and the mod's own messages use it. When the first word
after the command is one of these, Temper handles it instead of starting a run. Any other first word is a feature description, as before.

| Subcommand | What it does |
|---|---|
| `/temper:temper status` | Where the run stands: stage, task, criteria passed, loop count |
| `/temper:temper timeline` | Your decisions in this run |
| `/temper:temper approve`, `next`, `back`, `override`, `accept`, `drift` | Your wish, not a move: Claude runs the loop and asks the gate question exactly as the CLI gives it. You choose there. |
| `/temper:temper report` | The run report: verdicts, skips with their reasons, loops, usage. Without the mod it is `temper report`; with it, the mod's report from `view.json` and your decisions, kept in its plugin store. The page to share is `report.html` (below). |
| `/temper:temper pr` | Ask Claude for a pull request description from the report |
| `/temper:temper mode` | Say how much Temper draws, and that you change it in `/config` (Temper UI mode) |
| `/temper:temper enforcement` | Say whether denials are on, and that you change it in `/config` (Temper enforcement) |
| `/temper:temper pane` | Open or close the pane (in full mode it also opens by itself when a run starts; see [the mod](mod.md)) |
| `/temper:temper discuss <text>` | Send a message about the step you are at. It changes no stage. |
| `/temper:temper help` | List these |

A word that names a move (`approve`, `next`, `back`, `override`, `accept`, `drift`) is your wish, not
your decision: you decide in the question dialog that follows, with one click. Claude cannot decide for
you. With the mod loaded it answers the words that only show something (`status`, `timeline`,
`report`, `help`, `pane`, `mode`, `enforcement`) itself; every other word goes to the prompt
based command, so it works the same on every surface.

With the mod loaded and enforcement on, a headless `claude -p` run stops at the first gate, because
only a person can answer the gate question. With enforcement off a headless run goes on.

### Modes

With Claude Code 2.1.287 or later, the Temper mod draws the run (a stage bar, a pane and a few other
elements) and refuses writes that do not belong to the current stage. Two plugin options control it.
You change both in `/config`; the mod never changes them itself:

| Setting | Values | Effect |
|---|---|---|
| `uiMode` (Temper UI mode) | `full`, `minimal`, `off` | `full` draws the bar, the pane, toasts, the spinner text, the turn line, the hint and the question header. `minimal` draws the stage timeline only. `off` draws nothing. The mode changes only what is drawn: the questions and the rules are the same in every mode. |
| `enforcement` (Temper enforcement) | `on`, `off` | `on` refuses writes outside the stage, `--no-verify`, a changed hooks path, and a step only you may take without your answer. `off` keeps the drawing only. |

Denials and subcommands work in every mode. `/temper:temper mode` and `/temper:temper enforcement`
say what is set and where to change it. [Where enforcement works](mod.md#where-enforcement-works)
shows what is covered and what is not.

### The stage bar

In `full` mode the bar above the prompt shows `TEMPER`, the run's title, the step in plain words
("Step 2 of 6: Plan"), the stages as chips (green with a check for passed, red with a cross for a failed
check, yellow for a stage you skipped, a filled chip for the stage you are at, plain chips for the stages
to come), the loops back with their reasons, the time and tokens of the run, one sentence of status
("Plan: waiting for your answer to the Temper gate question.") and the details of the stage: the groups and tasks of Build, the open findings of Review,
the failed checks. Under about 100 columns (for example while the pane is docked) the bar uses a compact
form without borders. `minimal` shows the chips only.

The bar has no button and decides nothing. To take a run up again, type `/temper:temper`: Claude asks
the gate question again. The pane repeats the
run on one card: the plan's files by group, the Build grid with each task's state, model and retries, the
Review findings, the Check markers, the acceptance criteria ("what must be true") with their evidence,
the loops with their reasons and your decisions; it has no button. At the commit, the report is printed in
the terminal, and on your answer `temper report --html` writes the same as one page, `report.html` in the
spec folder, to share with the change
([The mod](mod.md#the-bar)).

### One flow

Every gate is a question in Claude Code's own dialog, header `Temper gate`, with the options that
`temper next --json` gives for the step the run is at (Continue to {next}, Loop back to {stage},
Override and continue, Save for later, Grill Me, Teach Me and the stage's own). Claude asks it exactly
as given. This is the same with the mod and without it, in every mode.
The orchestrator still runs every stage with its own brief and the CLI still judges every check. With
the mod loaded, the mod reads your answer from the dialog's result, counts it only when the header,
the question and the label are exactly what the CLI wrote, and lets through the calls of that option,
at the step the run is at; a step back or a skip needs your reason, and the dialog asks for it
when your answer has none. Once the run moves on, the answer is spent.

### Each stage

| Stage | Writes allowed |
|---|---|
| Intent | `intent.md` only |
| Plan, Design | `intent.md`, `plan.md`, `tasks.md`, `design.md` and new decision records |
| Build | The files in the plan, test files and the spec folder |
| Review | The spec folder only |
| Check | The spec folder only |
| Done | Nothing is blocked |

A plain `git commit` goes to the native `pre-commit` hook in every stage, and the hook decides: it
lets a spec only commit and a Build checkpoint through, and every other commit only when every gate
passed or was skipped with a reason. A commit the hook does not check (a merge, a cherry-pick, a revert,
a commit of named paths) is not refused by the mod either; [Trust](trust.md) lists it. Save for later
stops the run and lifts no rule.

A file outside the Build plan is never written first. Build lists it with why it is needed and the
change, and Claude asks you the Scope drift question: add the file to the plan, revert (go on
without it), or allow it once (Claude's why becomes the recorded reason). Each choice is logged.
This works the same with and without the mod; the mod also refuses the write until you answer.
A failed Review or Check loops back to Build when you choose so, as many times as the loop budget
(`loops.max-per-type`, and `fix.max-loops` for Check) allows.

### Stage commands are doors

`/temper:plan`, `/temper:design`, `/temper:build`, `/temper:review` and `/temper:check` start or
take up a `/temper` run at their stage, so there is one flow to keep right:

- With a run active, they take it up where the CLI says it is. A door never moves a run: when the
  run is at another stage, Claude says so and goes on from there.
- With no run active, `/temper:plan` starts one at Intent. The later doors start a run for the
  spec folder that holds the feature's `plan.md` and `tasks.md`, ask each earlier gate in turn
  (the same `Temper gate` question, Override and continue with your reason when a gate fails),
  then run their own stage. The earlier stages are checked, not run again, against what the
  run still has: their evidence went to the archive with the run that made it, so a check that
  reads evidence (Plan's search record, Review's completion) fails, the question names the
  failed rows, and you choose: **Run** that stage now (it and every stage after it run), or
  skip it with your reason. Build at a Review or Check door passes on the newest Build PASS that
  the spec folder's committed `gate-ledger.json` records, while no file of the plan changed since
  that commit; when one did, the question names it, and Run Build is the fix pass on that code. A
  loop back from such a run runs the stage it goes back to; Build's fix pass then mends the code
  the earlier run built.

`/temper:intent` stays on its own: it captures a draft intent and builds nothing.

---

## `/temper:intent`

Capture an idea as a draft `intent.md` — the artifact that starts the pipeline —
without starting the pipeline.

```bash
/temper:intent "handlers spend a third of call time on status-only queries"
/temper:intent "JIRA-4521"
/temper:intent                # interview from scratch
```

**What it does:**

- Interviews the originator the way an analyst would (scope, affected users,
  constraints, what better looks like) — no formal language required of them
- Writes `.temper/specs/{slug}/intent.md` with `Status: draft`, the author (a name you
  typed, else `the person`; never from git), Problem, measurable Success Criteria, Constraints, Target Users, and Open
  Questions — **no scenarios and no architecture**; those are Plan's job, derived from
  the measured blast radius later
- Keeps criteria and constraints firm: `temper gate intent` fails a draft that uses
  should, may, might, or possibly in one, unless the line carries a `(source: ...)`
  marker (the hedge belongs to the source). A source "should" or "may" is never turned
  into "must" without asking the originator; the answer goes into `### Decisions`
- Offers to commit the draft, so author, timestamp, and revision history live in
  version control from the moment the idea is real

**Who flips `Status:`** — `draft` (this command) → `accepted` (the human's Continue at
`/temper`'s **Intent gate**, also when a stage command started the run) → `completed` (the
commit step).
A later `/temper:temper "{slug}"` presents the draft at its Intent gate and builds on it,
never overwrites it. A `temper bands` breach drafts intents in exactly the same shape
(see `/temper:status`).

---

## `/temper:check`

Stack validation of a planned and built feature.

A door into `/temper`: it starts a run at Check, or takes up the run that is active, and from
there everything happens as `/temper` does it ([Entering at a stage](#stage-commands-are-doors)).

```bash
/temper:check
```

**What it does:**

- Auto-detects your tech stack
- Finds test, build, and lint commands
- Reports current quality status

**Output:**

```
🔍 Detecting stack...
✅ Detected: React + TypeScript
   • Build: npm run build
   • Test: npm test
   • Lint: npm run lint

📊 Quality Status:
   • Coverage: 78%
   • TypeScript errors: 0
   • Lint warnings: 2
```

---

## `/temper:plan`

Plan with blast radius analysis, mermaid diagrams, and interactive walkthrough.

A door into `/temper`: with no run active it starts one for the feature, and the Intent gate
comes first, because the plan is derived from the accepted intent. With a run active it takes
that run up ([Entering at a stage](#stage-commands-are-doors)).

```bash
/temper:plan "feature description"
```

**What it does:**

- Analyzes which files will be affected
- Identifies dependencies and risk areas
- Generates mermaid architecture diagrams (flowchart, sequenceDiagram, etc.)
- Derives BDD scenarios from requirements + blast radius — **before architecture**
- Builds architecture from scenarios — every file traces to a behavior or infrastructure need
- Generates intent.md with structured success criteria + Gherkin scenarios (medium+ complexity)
- Detects parallel tasks for optimized ordering
- Offers interactive step-by-step plan walkthrough with Q&A at each section

**Example:**

```bash
/temper:plan "add password reset"
```

**Output:**

```
🔍 Blast Radius Analysis

📦 Affected Files: 8
   • src/auth/PasswordResetService.ts (CREATE)
   • src/auth/AuthController.ts (MODIFY)
   • src/email/EmailService.ts (MODIFY)

🔗 Dependencies: 4
   • Email delivery
   • Token generation
   • Rate limiting

⚠️  Risk Areas: 2
   • Token expiration handling
   • Email delivery failures

📝 Generated: intent.md
   Success criteria (3):
     ✓ Users can reset password without support → validate: scenario
     ✓ Reset completes in under 2 minutes       → validate: manual
     ✓ Support tickets decrease 30%              → validate: metric

   Scenarios (5): 3 happy, 1 error, 1 edge case
     Scenario: Successful password reset
     Scenario: Expired token rejected
     Scenario: Rate limiting enforced
     ...

📋 tasks.md: 2 groups, 4 tasks

## Group G1: Reset tokens
### Task 1: Create PasswordResetService
  **File:** src/auth/PasswordResetService.ts, unit/PasswordResetService.test.ts
  **Depends:** none
  **Cases:** a fresh token resets the password; an expired token is refused
### Task 2: Add the reset endpoint
  **Depends:** Task 1

## Group G2: Mail and limits (depends on G1)
### Task 3: Update the email template
### Task 4: Add rate limiting
...
```

**Note:** tasks with no dependency between them, and with files that do not overlap, run at the same
time, each as its own Haiku task agent in its own worktree ([Haiku Build](grouped-build.md)).

---

## `/temper:design`

System design for complex/medium features. Auto-skipped for simple or trivial features.

A door into `/temper`: it starts a run at Design, or takes up the run that is active, and from
there everything happens as `/temper` does it ([Entering at a stage](#stage-commands-are-doors)).

```bash
/temper:design
```

**What it does:**

Produces a system design document (`design.md`) with:

- **Architecture overview** — System components and data flow
- **API contracts** — Request/response shapes, endpoint changes
- **Database changes** — Schema changes, migration strategy
- **Integration points** — External system connections, error handling
- **Decision log** — Architectural decisions with rationale (ADRs)

**When it runs:**

Automatically included in the `/temper` pipeline when:
- `phases.design: true` in temper.config (default)
- AND complexity is `medium` or `complex`

**Config:**

```yaml
phases:
  design: true    # Set false to always skip design stage
```

---

## `/temper:build`

Build with TDD + quality gates.

A door into `/temper`: it starts a run at Build, or takes up the run that is active, and from
there everything happens as `/temper` does it ([Entering at a stage](#stage-commands-are-doors)).

```bash
/temper:build
```

**What it does:**

Build runs the plan's groups ([Haiku Build](grouped-build.md)). `temper next --json` drives it:

- It starts each group whose dependencies passed, in its own worktree.
- It hands out the ready tasks; each runs as a small Haiku task agent in its own worktree, writes the
  test of each listed case first (RED), then the code (GREEN).
- The CLI gates each task from its own recorded test runs, commits it on the task branch and merges it
  into the group branch. A failed task is retried, then escalated, then parks its group.
- You review each group once, in the `Build group` question (Continue, Change or Stop).
- The CLI merges the groups into the feature branch and gates Build.

**What you see:** the bar shows the step and the groups; the pane shows the Build grid, one row per
task with its state (waiting, running, RED, GREEN, PASS, FAIL, parked), model and retries.

**Resume:** the run's state is the CLI's, so `/temper:temper` with no arguments takes Build up where it
stopped: `temper next` hands out the tasks that are still to do, or waits for the agents still running.

---

## `/temper:review`

Code review with confidence scoring.

A door into `/temper`: it starts a run at Review, or takes up the run that is active, and from
there everything happens as `/temper` does it ([Entering at a stage](#stage-commands-are-doors)).

```bash
/temper:review
```

**What it does:**

- Analyzes changed files
- Checks against enabled packs
- Validates intent: success criteria (IDD) + scenario coverage (BDD)
- Scores confidence of findings
- Suggests improvements
- Diff-aware: focuses on changed lines
- Catches N+1 queries and performance issues

**Output:**

```
📊 Review Results

Files reviewed: 6
Issues found: 4
Confidence: 91%

🔴 HIGH (Confidence: 96%) [REGRESSION]
   Missing rate limiting on password reset endpoint
   └─ AuthController.ts:89 (CHANGED)
   → Suggestion: Add rate limiting middleware

🔴 HIGH (Confidence: 89%) [NEW ISSUE]
   N+1 query pattern: DB call inside loop
   └─ UserRepository.java:45 (CHANGED)
   → Suggestion: Use batch fetch or JOIN query

🟡 WARN (Confidence: 78%) [NEW ISSUE]
   Method 'processReset' exceeds 30 lines
   └─ PasswordResetService.ts:112 (CHANGED)
   → Suggestion: Extract helper methods

🟢 INFO (Confidence: 65%) [PRE-EXISTING]
   Consider extracting magic number to constant
   └─ TokenService.ts:23 (UNCHANGED)
   → Suggestion: EXPIRATION_HOURS = 24

📊 Intent Validation (IDD): 2/3 mechanically validated
   Problem: Users unable to reset passwords without support
   ✅ Users can reset password → validate: scenario → test_successful_reset PASS
   ✅ Reset completes in < 2 min → validate: manual → requires human review
   📊 Support ticket reduction → validate: metric → post-deploy monitoring required

📊 Scenario Coverage (BDD): 5/5 ✅
   ✅ Successful password reset → test_successful_reset (PASS)
   ✅ Expired token rejected → test_expired_token (PASS)
   ✅ Rate limiting enforced → test_rate_limiting (PASS)
   ✅ Invalid email format → test_invalid_email (PASS)
   ✅ Non-existent user → test_nonexistent_user (PASS)

✅ All tests passing
✅ No security pack violations
```

**Issue Classifications:**

- **REGRESSION** — Code that was working, now broken by your change
- **NEW ISSUE** — Problem introduced by this change
- **PRE-EXISTING** — Issue existed before (lower priority)

**External Engine: open-code-review:**

OCR is off by default. When you set `tools.ocr.mode` to `auto` or `require` and the `ocr` CLI is on your `PATH`, `/temper:review` runs a second defect-detection pass (probed in Step 1, merged in Step 2). OCR handles line-level defects; Temper keeps intent validation, security analysis, and architecture depth.

| Config Key | Default | Description |
|------------|---------|-------------|
| `tools.ocr.mode` | `off` | `off` (never invoke), `auto` (use if available), `require` (block if missing) |
| `tools.ocr.replace-defect-subagent` | `true` | Drop generic defect hunting from Temper subagents when OCR is active |
| `tools.ocr.timeout` | `10` | Minutes before OCR invocation is killed |

**Evidence labels:**

- `[OCR]` — Finding from the OCR engine alone
- `[OCR+TEMPER]` — Both engines independently found the same issue (file + line +/-2 + category match). Confidence boosted: min(0.95, max(a,b) + 0.15)

**Modes:**

| Mode | OCR available | OCR missing | OCR fails at runtime |
|------|--------------|-------------|---------------------|
| `auto` | Run + dedupe | Skip with a one-line notice | Warn + degrade |
| `require` | Run + dedupe | BLOCK, saying where to find OCR's install steps | Warn + degrade |
| `off` (default) | Never invoke | Never invoke | Never invoke |

---

## `/temper:fix`

Root cause analysis + structured fix.

```bash
/temper:fix "issue description"
```

**What it does:**

- Analyzes root cause of the issue
- Creates fix plan
- Implements with tests

**Example:**

```bash
/temper:fix "JIRA-123: Users can't reset password"
```

**Output:**

```
🔍 Root Cause Analysis

Issue: Password reset emails not being sent

Investigation:
  1. Checked email service logs → No errors
  2. Checked token generation → Working
  3. Checked queue → Messages stuck

Root Cause: Queue consumer crashed at 2:34 AM
  → Consumer not auto-restarting

📋 Fix Plan:
  1. Add health check to queue consumer
  2. Implement auto-restart on failure
  3. Add alerting for queue depth

🔧 Implementing...

✅ Fix applied
   • Files changed: 3
   • Tests added: 2
   • Regression risk: Low
```

---

## `/temper:init`

One-command project setup. It is idempotent, so it is safe to re-run. It never overwrites an existing config. It never writes into a folder named `hooks`, so it never writes over a git hook of yours or of another tool: when pointing git at the Temper hook would switch such a hook off, it keeps the Temper hook in the repository's git folder and shows you one line to add to your hook, with a one line hint (see "When you already have a pre-commit hook" below).

```bash
/temper:init
```

**What it does:**

- Seeds `.claude/temper.config` from the bundled default (if absent; an existing config is left untouched, with a note about any retired blocks in it)
- Scaffolds `.temper/` (the gate ledger, overrides log, feedback-loop registry)
- Writes the **native commit gate**, the pre-commit hook that blocks `git commit` while any gate is red, to `temper-gate/pre-commit` in the repository's git folder (the folder `git rev-parse --git-common-dir` names, which git never commits and every linked worktree shares), and points the repository's `core.hooksPath` at that folder, so git runs it in every worktree. A submodule's hook goes in its own git folder. When `.git/hooks` holds hooks git would then stop running, or `core.hooksPath` already names another tool's folder, setup still writes the Temper hook to `temper-gate/pre-commit` but leaves `core.hooksPath` as it is, shows you the line to add and the hint, and goes on without the commit gate until you add it.
- Opens no Claude Code settings file, the project's or your home folder's. Guard commands you added for the guardrails pack stay as you left them; `/temper:pack enable guardrails` prints the current ones after a plugin upgrade.

**Where the hook lives.** The installer writes the Temper hook to `temper-gate/pre-commit` in the repository's git folder, through a new file moved into place, and runs `git config --local core.hooksPath` with that folder's absolute path. Git then runs that hook in every worktree, and `git rev-parse --git-path hooks/pre-commit` names it. The installer never writes into a folder named `hooks`: not `.git/hooks`, not the folder `git rev-parse --git-path hooks` names, and not a `core.hooksPath` folder that is not Temper's. It reads the hooks there only to decide. Once `core.hooksPath` is set, git runs the hooks of that folder and no longer those in `.git/hooks`, so the installer sets it only when `.git/hooks` holds no hook git would then stop running: no executable hook under one of git's hook names (an older Temper `pre-commit` does not count, and the installer then says you can delete it) and no `pre-commit.bak.<timestamp>` that an older installer set aside. When `core.hooksPath` already points at the folder, running the installer again makes the hook current, for example after a plugin upgrade moves the plugin folder. When it holds Temper's older folder (`.git/hooks-temper`, which `--global` set from 5.5.0 to 9.6.4, `.git/temper-git-hooks`, which it set in 9.6.5, or the `temper-gate` folder of where the repository used to be before it was moved or renamed), the installer points it at `temper-gate` and prints a note, unless that folder holds other hooks git runs (`git lfs install` writes its hooks into the folder `core.hooksPath` names); then it leaves the value, as it does for `.git/hooks`, and the `pre-commit` there needs the line below. The `--global` option is still accepted and now does what the default does, with a note.

**After you move the repository.** `core.hooksPath` holds an absolute path, so every worktree finds the folder. Moving or renaming the repository, or a folder above it, leaves it naming the old place, and git runs no pre-commit hook until the installer runs again. Your next `/temper:temper` checks the hook and runs the installer, which points `core.hooksPath` at the new place; you can also run `/temper:init`.

**When you already have a pre-commit hook.** When `.git/hooks` holds hooks git would stop running (yours, a `commit-msg` hook, git-lfs's `pre-push`, the pre-commit framework's or lefthook's), or `core.hooksPath` names another tool's folder (husky's `.husky/_`, lefthook, a team's folder), the installer leaves `core.hooksPath` and every one of those hooks as they are. It writes only the Temper hook to `temper-gate/pre-commit` in the repository's git folder and prints this line between its BEGIN and END lines:

```sh
_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"; _temper_hook="$(git rev-parse --git-common-dir)/temper-gate/pre-commit"; [ ! -f "$_temper_hook" ] || bash "$_temper_hook" || exit 1
```

The line holds no path of this machine, so it is safe to commit, and it keeps your hook's own result wherever it sits: when the command before it failed, it exits with that status, and otherwise it runs the Temper hook and fails only when that hook blocks. Its FAIL line says why the installer did not point git at the Temper hook (for hooks in `.git/hooks`, it names them), and its hint says where the line goes:

| Your hook | Where the line goes |
|---|---|
| husky (a hooks folder in `.husky`) | `.husky/pre-commit`, which is safe to commit |
| the pre-commit framework | a local hook in `.pre-commit-config.yaml` (repo: local, language: system, pass_filenames: false, always_run: true) with the entry `sh -c '<the line>'`, which the hint prints in full; the framework runs that entry with no shell |
| lefthook, which writes its hook again | a pre-commit command in `lefthook.yml` that runs the line |
| a `pre-commit` from an older Temper (in `.git/hooks` next to other hooks, in Temper's older folder, or in a team folder) | in place of all of its lines, after `#!/bin/sh`; git still runs that hook, so the installer warns about it and shows its stale plugin path |
| any other hook | its start or its end; create the file, executable, if it does not exist |

Once your hook holds the line, with no line before it that starts with `exit` or `exec`, and git can run it (it is executable; for husky v9, husky's own hook in `.husky/_` must be there and executable instead, so run `npx husky` in a fresh clone), running the installer again makes the Temper hook current, says your hook calls it, and exits 0. For the pre-commit framework and lefthook, their config file at the repository's top holding the line outside a comment counts the same way; the installer reads only its text, so a `stages` or `skip` setting there can still keep the line from running. The line that 9.6.5 printed, which runs `temper-pre-commit` in the git folder, still counts: the installer then makes that file current too. When an `exit` or `exec` line comes first, the line never runs, and the installer refuses and says to move it above that line. When the installer refuses before it knows the git folder, it writes nothing and prints the Temper hook's own lines instead, in a subshell, so that their exits end only the subshell and your hook's own result is kept.

**Adding a hook tool later.** The pre-commit framework refuses to install while `core.hooksPath` is set, and lefthook installs into the folder it names, which is Temper's, so run `git config --unset core.hooksPath` before you install one. If a tool has already written its `pre-commit` into Temper's folder, the installer never writes over it: it refuses and says how to move it out. The next `/temper:temper` or `/temper:init` then finds that tool's hook, keeps the Temper hook and prints the line to add, with the hint for that tool.

An older Temper version may have left a hook that was not its own as `pre-commit.bak.<timestamp>` in `.git/hooks`. When one is there, the installer warns, names it and says how to get it back: move it back to `pre-commit` in git's own hooks folder and add the line between BEGIN and END in the installer's output to it (when a `pre-commit` of yours is there now, it says to add the old hook's lines to that file instead).

**To remove the hook**, run `git config --unset core.hooksPath` when it points at the `temper-gate` folder, remove the Temper line from your own hook if you added one, and delete the `temper-gate` folder in the git folder (and any `temper-pre-commit` that 9.6.5 left there). The installer prints these steps.

**You usually don't run it by hand.** Your first `/temper:temper "…"` in a project that is not set up does all of this automatically. The optional edit-time guardrails are a separate step: `/temper:pack enable guardrails` (see [Guardrails](#guardrails)).

---

## `/temper:pack`

Manage quality packs: view, toggle, quick-create a launcher pack, configure links and phases, or build a new pack.

```text
/temper:pack
/temper:pack enable guardrails
/temper:pack disable guardrails
```

**What it does:**

- Shows every pack it finds, from three places: the project's `.claude/packs` folder, your global
  pack folder `~/.claude/packs`, and the 8 built-in packs. A project pack shadows a global one of
  the same name, and a global one shadows a built-in one.
- Lets you toggle packs on/off, quick-create a launcher pack, set a pack's link and phases, or build a new pack
- Prints the guardrails pack's guard hooks for you to add, or says which to remove (see [Guardrails](#guardrails)).
  It opens no Claude Code settings file.

**Output:** a Quality Pack Manager panel (its exact shape is in `reference/pack.md`, under
"Step 1: Discover + Display") with one row per pack, filled from what it found, and a last line
`N packs total (X enabled, Y disabled)`. The columns:

| Column | What it shows |
|--------|---------------|
| NAME | The pack's name |
| STATUS | `ON` when the pack is in `packs:`, otherwise `OFF` |
| PHASES | The phases that load the pack (`all` when none are set) |
| LINK | The pack's `plugin://` or `skill://` link, if it has one |
| CONNECTED | Whether that link target was found |

**Options:**

| Option | What it does |
|--------|-------------|
| **Toggle packs on/off** | Select packs to enable or disable. Turning `guardrails` on prints its hook entries for you to add; turning it off says which to remove. Temper opens no settings file. |
| **Quick-create launcher pack** | Wrap a skill or command as a BLOCK-level pack in the project's `.claude/packs` folder. |
| **Configure pack (link, phases)** | Set the link target or the phases of an existing pack. |
| **Done** | Exit. To open the full pack builder instead, choose **Other** and describe the pack. |

**Link targets.** A launcher pack or a link points at a skill or command. The choices are the
skills and commands this Claude session lists (a plugin's show as `plugin:item`) and the
project's own commands and skills in `.claude/commands` and `.claude/skills`. A
`plugin://name` link counts as connected when the session lists a skill or command of that
plugin, and a `skill://name` link when the session lists that skill or the project has it.
Temper reads no Claude Code file to find them.

**The full pack builder** (choose **Other**, then describe the pack):

```
🔍 Scanning codebase...

Found patterns:
  • Constructor injection (92% of classes)
  • DTO pattern (100% of APIs)
  • Structured logging (78% of services)

Questions:

1. I see you use DTOs for all API responses.
   Should this be a BLOCK rule?
   [Yes/No/Skip] > Yes

2. Constructor injection is common but not universal.
   Make it mandatory?
   [Yes/No/Skip] > Yes

Generating pack...

✅ Created: .claude/packs/company/rules.md

   • BLOCK rules: 2
   • WARN rules: 3
   • SUGGEST rules: 4
   • Status: ENABLED
```

### Guardrails

The guardrails pack adds edit-time guard hooks: secret blocking, protection of the regression test
and of frozen paths, the in-agent commit gate, an approval prompt before an override, a forbidden
import check and auto-format. They are off until you turn them on.

The secret check scans only what a call adds: the content of a Write, the new text of an Edit
(each new text of a MultiEdit) and the command of a Bash call. So an edit that removes a secret,
or the command that unstages one, is not refused. The staged files are scanned only by the native
`pre-commit` hook, at commit time.

`/temper:pack enable guardrails`:

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

`/temper:pack disable guardrails` removes the `guardrails` entry from `packs:` and says which
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
folder that is gone or out of date. Run `/temper:pack enable guardrails` again to print the current
commands, and put them in place of the old ones.

The pack does not print the stage gate pair (`stage-marker.sh` and `verify-stage-gate.sh`): the
plugin's own hooks already run them. `/temper:pack` and `/temper:init` never open a Claude Code
settings file, the project's or your home folder's. The commit-time layer is the native `pre-commit` hook, which
`/temper:init` installs.

---

## `/temper:status`

Quality metrics dashboard.

```bash
/temper:status
```

**What it does:**

- Shows current quality metrics
- Tracks trends over time
- Highlights hotspots

**Output:**

```
📊 Temper Status Dashboard

Project: my-service
Stack: Spring Boot
Packs: quality, tdd, security, company

📈 Metrics (Last 30 days)
   • Reviews run: 47
   • Issues found: 23
   • Auto-fixed: 18
   • Coverage: 78% → 84% ↑

🔥 Hotspots
   • UserService.java — 4 issues (complexity)
   • OrderProcessor.java — 3 issues (coupling)

📚 Learning (planned)
   • Pattern detected: "Missing null check"
   → Suggestion: Add to company pack

⏱️ Technical Debt
   • Coverage gaps: 2 modules
   • TODOs: 12 (3 critical)
   • Deprecated: 1 dependency
```

**Control bands (closing the loop):** the dashboard also runs `temper bands` — a
deterministic drift check of the metric history against rolling mean ± k·sigma bands
(config: `bands:` in `.claude/temper.config`). `1sigma` logs, `2sigma` means
diagnose, and a `3sigma`/`propose`-tier breach offers to draft the breach as a
Stage-1 `intent.md` for `/temper` to pick up — evidence in, ordinary gates out.
Dismissals are the tuning signal (3+ on one metric → widen the window or retire the
metric). `temper bands` is also runnable headless with no dashboard at all — exit 1 on
a breach — from **any** scheduler (cron, Jenkins, GitLab CI, GitHub Actions; temper
ships no platform-specific wiring on purpose, see `examples/workflow/README.md`),
which is what lets the loop begin and end without a person starting it.
