# Temper, rebuilt: the specification

**Status:** Proposed (for the owner to accept, change or reject)
**Date:** 2026-11-27
**Base:** Temper 9.8.5 (`9a8b4b3`) and the directory's refusal report of that commit.
**License of the new repository:** Apache 2.0.

This page is the brief for a new repository in Booking's GitHub organisation. It is written so that an agent can
build from it without reading the old code. The old repository is the reference for behaviour, never a source to
copy from.

## 1. Why a rebuild

| Fact of 9.8.5 | What it costs |
|---|---|
| 838 files in the scanned branch | The directory holds a plugin above 512 files. |
| A mod (27 files, 49 test files) | Eight findings of the report stop the version because of the mod alone. One of them says the mod takes a permission decision out of the user's hands; that is what the mod's guard is for, so no wording in a README clears it. |
| Tests, bench, history and plans in the scanned branch | The findings on credentials, on download and run text, on a file that is not plain and on images all point at files a user never runs. |
| 81 gate rows, 38 question ids, 13 agent briefs, 250 KB of prompts, a CLI in bash and Python | A new reader, a person or an agent, cannot hold the product in mind. |

## 2. What must be true before any code is written

1. **Booking's Claude organisation is Verified.** The report says the directory accepts command hooks and script
   files only from Verified organisations. Temper's value is a CLI that computes each verdict, and a CLI is a script.
   Without Verified status only Markdown, text, JSON, YAML and images are accepted, and Temper would be prompts only.
   An Owner of the organisation asks for it in the developer portal (Help and appeals, Request verified), with a
   proven domain.
2. **The name.** The plugin name cannot change after publication. Ask directory@anthropic.com whether `temper` is
   free for Booking's organisation while the old submission (never live) still exists, and withdraw the old one.
3. **A walking skeleton passes the portal's Validate step.** The first commit of the new repository is the smallest
   plugin that has every risky part: one command page, the hooks file with one command hook that only denies, and a
   CLI of twenty lines. Validate that folder in the portal (nothing is submitted until you choose to). Build the rest
   only after it validates. This is the one way to learn what the directory's reader accepts, since
   `claude plugin validate` does not run the same checks.

## 3. Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | No mod. | See section 1. The enforcement that matters does not need it: the write hold is a command hook and the commit gate is git's own hook. The bar, the pane, the run driver and the answer audit go. |
| D2 | The plugin is the folder `plugin/` of the repository, and only that folder is submitted. | The report itself gives this advice. Tests, bench, docs and CI stay outside and are never scanned. |
| D3 | The CLI is Python 3, standard library only, started as `python3 -I "${CLAUDE_PLUGIN_ROOT}/scripts/temper.py"`. No bash. | One language. Every command in the hooks file and in the prompts is fixed text. No file starts with `#!`, and no file lacks an extension. |
| D4 | The CLI stays the only place where a verdict, a next step or a question's options are computed. | This is Temper. A prompt never decides a gate. |
| D5 | Groups stay, built one after another on the run's branch. Worktrees and tasks run at the same time are not in version 1. | Stacked pull requests are cut at the commit that ends each group, so they need groups and their order, not worktrees. This keeps the stacked pull requests and drops the merge of worktrees, about a quarter of the CLI. Parallel tasks can return later, measured against the bench. |
| D6 | Seven agents: intent, plan, acceptance, build, review, rca, fix. | Check is run by the CLI and needs no agent. Design is an optional section of the plan (accepted by the owner), with no stage or question of its own. The acceptance agent reads only the intent and writes no code, so the planner cannot shape the tests. |
| D7 | No migration code. The new Temper reads no state, config key or folder of an older version. | It is a new product in a new repository. |
| D8 | No HTML page, no image, no artifact. The report is text. | Each was a finding or a hold. |

Not in version 1, each a later change of its own: tasks built at the same time in worktrees, the Pipeline stage, the
fresh plan review, the model table, the budget of repeats, `doctor`, `drift`, the small change at a late stage.

## 4. Layout

```
LICENSE  NOTICE  README.md  CONTRIBUTING.md  CODEOWNERS
docs/                     the site, the decision records, this page
tests/                    unit cases and the end to end suite
bench/                    the measured tasks
plugin/                   the only folder the directory reads
  .claude-plugin/plugin.json
  README.md  LICENSE
  commands/temper.md  commands/fix.md
  agents/intent.md plan.md acceptance.md build.md review.md rca.md fix.md
  skills/grill-me/  skills/teach-me/
  hooks/hooks.json
  scripts/temper.py       the entry: parses the words, calls a module
  scripts/temper_lib/     state.py ledger.py gates.py flow.py questions.py
                          run.py check.py repair.py report.py config.py githook.py
  scripts/guard_hold.py   the write hold (PreToolUse)
  packs/<name>.md         tdd, security, quality, git, api-design, performance, architecture
  templates/intent.md plan.md temper.config.yaml
```

Rules of the `plugin/` folder, each from a finding of the report:

- Markdown, JSON, YAML and Python files only. No image, no HTML, no dot file, no package list, no `CLAUDE.md`.
- At most 100 files, and no file above 100 KB.
- `plugin.json` holds only: `name`, `displayName`, `version`, `description`, `author`, `homepage`, `repository`,
  `license`, `keywords`, `commands`, `agents`, `skills`.
- No text in any file reads a key, a token or a login, names an install command that downloads and runs, or changes
  a package manager's settings. Docs link to a tool's own install page.
- `plugin/README.md` has a section "What Temper runs and changes" that lists every hook, what it reads, the one
  answer it can give, and every program the CLI starts.

## 5. The product

### 5.1 The stages

Intent, Plan, Build, Review, Check, Commit. `/temper:fix` runs RCA, Fix, Review, Check, Commit.

The person decides twice in a normal run:

1. **The approval**, after Plan: the intent and the plan in one question. Options: Approve and build, Ask me at every
   stage, Change (typed text goes to the plan agent), Stop.
2. **The commit**: the report, then Commit, Change, Stop.

Between the two the run goes on by itself. It asks again only at a stop (5.5).

### 5.2 What each stage produces, and its gate

A gate is a list of rows. A row is a name, PASS or FAIL, and one line of detail. The verdict is FAIL when any row is
FAIL. `temper gate <stage>` computes it from files and the ledger; nothing else writes a verdict.

| Stage | Who | Produces | Gate rows |
|---|---|---|---|
| Intent | intent agent | `intent.md`: problem, success criteria, constraints, open questions with a recommended answer each | the four sections exist; no blocking question is open |
| Plan | plan agent, then acceptance agent | `plan.md`: tasks, each with its files, its test command and its scenarios, and an optional Design section; the acceptance tests, written from the intent only | every task names files and a test command; every success criterion has a scenario; each test command runs on the current code (red base is recorded); acceptance tests exist and fail |
| Build | build agent | code, one task after another, each with a failing test first | for each task, a red run then a green run of its test in the ledger; the acceptance tests pass; no changed file outside the plan |
| Review | review agent | findings, each with a level, a file and a line | Review read every changed file; no open finding at a level of `review.block-on` |
| Check | the CLI | runs the project's commands | each command of `check.commands` exits 0; coverage did not drop; `check.prove`, when set, exits 0 |
| Commit | the CLI | the commit | every earlier gate is PASS or skipped by the person with a reason |

`check.prove` is new. It is one project command that starts the product and uses the feature end to end, and its
output goes into the report. It answers the fault "the unit tests pass and the button does nothing".

### 5.3 The ledger and the state

All run files live in the project's `.temper/` folder.

- `state.json`: the run's slug, stage, mode, and one timestamp for every move and for every question asked and
  answered.
- `ledger.jsonl`: one line per piece of evidence: stage, claim, command, exit code, time. Only the CLI appends, and
  a command's evidence is written by the CLI running that command (`temper evidence run -- CMD`), never from an
  agent's word.
- `gates.json`: the last verdict of each stage with its rows.
- `overrides.json`: each skip, with the person's reason.
- `specs/<slug>/`: `intent.md`, `plan.md`, the acceptance tests, `report.md`.

### 5.4 One loop

`temper next` prints one JSON object, and the command page is a loop over it. The page holds no stage logic.

| `action` | What the conversation does |
|---|---|
| `agent` | Launches the named agent with the prompt as given, then runs the `after` calls. |
| `ask` | Asks the question exactly as given with AskUserQuestion, then runs the calls of the chosen option. |
| `done` | Says the one line and stops. |

Everything else (running a gate, running Check, moving a stage, a repair's bookkeeping) the CLI does inside `next`
before it prints. The target for the command page is 60 lines.

### 5.5 The run to the commit

Started only by "Approve and build". After it:

- A passed gate moves on.
- A failed Build, Review or Check gate gets one repair: the build agent with the failed rows as its input, the CLI's
  own run of the failed commands, then the gate again. A second failure is a stop.
- A stop is a question. The stops: a second failure, a changed file outside the plan, a plan that touches a path of
  `autonomy.park-on-touch`, a red base, a blocking question, an agent that returned nothing.
- It never pushes, never skips a check, never accepts a finding and never changes the intent, the plan's files or a
  gate's command. The commit always asks.

`run.default` keeps its three values. New: in an organisation config the default is `ask`, and `to-commit` is a
choice the project makes in its own config. Temper's hooks are not a sandbox, and the README says so.

### 5.6 Enforcement

Two mechanisms, and no third:

1. **The write hold.** A PreToolUse command hook on the tools that write a file. Before the approval of a run it
   answers deny for a project file outside `.temper/`. It only ever answers deny or nothing, never approves a call
   and never changes its input.
2. **The commit gate.** `temper init` installs a `pre-commit` hook that exits non zero while any gate is FAIL and
   not skipped by the person.

Rules both keep, each learned from a fault of the old version:

- A hook fails open on every path except its one detected violation.
- The installer never writes over a hook of the person's and never writes into a folder it did not create. It keeps
  its hook in a folder of its own inside the git folder and points `core.hooksPath` at it only when no other value is
  set; otherwise it prints one line for the person's hook to call.
- The CLI refuses to run when `.temper/` or a file in it is a symlink, and refuses the home folder as a project.
- A command the CLI runs gets an environment with the variables whose names look like credentials taken out.
- The CLI reads no git identity, no file outside the project, and makes no network call.

### 5.7 The report, with waiting time

`temper report` prints, for the run: each stage's verdict and rows, each skip with its reason, each accepted finding,
the output of `check.prove`, and two new lines computed from the timestamps of `state.json`:

```
Worked 41 min (Plan 6, Build 27, Review 5, Check 3)
Waited for you 3 h 12 min (approval 3 h 02, commit 10 min)
```

`temper report --all` adds the same two numbers summed over the finished runs of the project. This is the baseline a
team needs to say where its delivery waits, and it costs no new question, key or agent.

### 5.8 Config

`.claude/temper.config.yaml`, read by a small parser of the CLI's own (flat keys, lists, one level of nesting).

```
run.default            to-commit | ask | never-unattended
review.block-on        [critical, high]
autonomy.park-on-touch [globs]
packs                  [names]
check.commands         test, coverage, lint (each a command line)
check.prove            a command line, optional
```

Six keys. A new key needs a decision record.

### 5.9 Groups and stacked pull requests

The plan puts its tasks into ordered groups: G1, G2 and so on. A group is a part a reviewer can read alone.

- Build takes the groups in order on the run's branch. When the last task of a group is green, the CLI runs the
  group's test command and makes one commit, `group(<slug>): G<n>`. A failed group gets the one repair of 5.5.
- At the commit question, a run with two or more groups also offers "Commit and open stacked pull requests", and
  every run offers "Commit and open a pull request". Both are the person's choice there, and a run never pushes
  without it.
- Part k below the last gets the branch `<branch>-part-<k>` at the commit that ended group k; the last part is the
  run's branch. Part 1 targets the default branch and part k targets part k minus one. No commit is rewritten.
- Every pull request is a draft. With no `gh`, no login or no `origin`, the commit is kept and the commands are
  printed for the person.
- The README's "What Temper runs and changes" names `git push` and `gh pr create` and says when they run.

### 5.10 Packs

A pack is one Markdown file of rules, at most 4 KB, that the agents of its stages read. Seven ship: `tdd` and
`security` are on by default; `quality`, `git`, `api-design`, `performance` and `architecture` are there to turn on.
The old guardrails pack does not ship: it was 28 KB, and its extra hooks are a third enforcement mechanism (5.6).

### 5.11 The words

`/temper:temper <feature>` starts or continues a run. Alone: `status`, `report`, `init`. `draft <idea>` writes a
draft `intent.md` and starts no run. `/temper:fix <fault>` starts a fix run.

## 6. Budgets

A budget is checked by a test and is raised only in a pull request of its own.

| Measure | 9.8.5 | Budget |
|---|---|---|
| Files in `plugin/` | 838 scanned | 100 |
| CLI lines (Python) | about 29,000 with bash | 4,000 (3,500 for the core, 500 for groups and the stacked pull requests) |
| Agent briefs | 13 | 7 |
| Gate rows | 81 | 22 |
| Question ids | 38 | 8 |
| Bytes of prompts (commands, agents, skills, packs) | 250,858 | 80,000 |
| Config keys | 18 | 6 |

## 7. Tests

- `tests/unit/`: one file per CLI module. Every gate row has a case that passes and a case that fails.
- `tests/e2e/`: the real CLI in a throwaway git project, driven by a script that plays the conversation: it reads
  `next`, answers each question from a list, and replaces each agent by a fixture that writes that agent's files.
  One scenario each for: the clean run, the repair that passes, the repair that fails and stops, each stop of 5.5,
  the write hold, the commit gate, a skip with a reason, a fix run.
- `tests/plugin/`: the rules of section 4 as a script (file types, counts, sizes, manifest fields, fixed text
  commands), and `claude plugin validate --strict plugin`.
- CI runs all three on every pull request.

The old end to end scenarios are read as a list of behaviours to cover. A scenario for a part that is not in
version 1 is not carried over.

## 8. Build order

Each step is one pull request that ends green.

1. The walking skeleton of section 2, validated in the portal.
2. State, ledger, config, and `gates.py` with the Intent and Plan rows.
3. `next` and the questions; the command page; the intent, plan and acceptance agents; the write hold.
4. Build with the red then green evidence; the acceptance tests.
5. Review and Check, with `check.prove`.
6. The commit gate and its installer; the commit.
7. The run to the commit, the one repair, the stops; groups and the stacked pull requests.
8. The report with the waiting time.
9. `/temper:fix`.
10. Packs, skills, README, the privacy page, the site.
11. The bench against 9.8.5 on the same tasks. Release only when the new version is no worse on the tasks it covers.
12. Submit `plugin/` in the portal from Booking's organisation.

## 9. Answers of the owner (2026-11-27)

- D5: groups built one after another are enough for version 1.
- D6: Design is an optional section of the plan.
- Booking holds the copyright. `NOTICE` and the license headers carry Booking's legal name, as its open source
  office writes it.

Still open: does Booking ask contributors for an agreement?
