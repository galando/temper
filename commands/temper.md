---
description: "Unified SDLC: intent → plan → design? → build → review → check → commit, each gate a question you answer"
argument-hint: "<feature-description> | status | report | help"
---

# Temper (Markdown edition)

**First output, once per conversation:** "Temper Markdown edition: Claude walks each gate's
checklist and asks you; no program enforces the gates here. The full edition on GitHub
(galando/temper) adds the CLI that computes every verdict, the commit hook and the mod." Then
carry on. Never repeat it, and never treat it as an error.

**Plugin folder:** `${CLAUDE_PLUGIN_ROOT}`. Stage agents, reference pages, templates and packs are
read from there. Every path below that is not in the plugin folder is in the project (the
current directory). Nothing writes into the plugin folder.

## What is and is not enforced

Nothing in this edition is enforced deterministically. The gates are checklists Claude applies
by reading files (`reference/gates.md`), the state is Markdown and JSON Claude writes
(`reference/run-state.md`), and no hook stops a `git commit`. What holds the run together is the
rule below and the person's answers. For the CLI gates, the evidence ledger, the native commit
hook and the mod's write guards, install the full edition from github.com/galando/temper.

## The rules of every run

- **The person decides every gate**, in an AskUserQuestion dialog, and only there. Never choose
  for them, never answer a question for them, never treat a typed change as approval.
- **This conversation writes no project source during a run.** It writes only the run's files
  under `.temper/` and runs `git` at the branch and commit steps; code changes are the stage
  agents' work.
- **Never push, never merge, never `--no-verify`, never `git add -A`, `git add .` or
  `git add -f`.**
- **Never skip a stage the run has**, and never move `stage` in `state.json` without the
  person's answer.
- Say plainly when a checklist row is something you could not verify.

## Arguments

When the first word is one of these, do this and start no run. Any other first word begins a
feature description.

| Word | What to do |
|---|---|
| `status` | Read `.temper/run.json` and the run's `state.json`; say the stage, the gates so far with their decisions, and what comes next. No run: say so. |
| `report` | Print the run's report (see "The report") without ending the run. |
| `help` | List these words and the stage commands with one line each. |
| `--enter <stage> [args]` | From a stage command (a door): enter at that stage, as "Entering at a stage" says. |
| `discard` | Ask "Discard the run {slug}? Its spec folder stays." with "Discard the run" and "Cancel". On "Discard the run", delete `.temper/run.json`. |

## Start

1. **Scaffold.** When `.temper/specs/` does not exist, create it. Never write
   `.claude/temper.config` here; `/temper:init` seeds it.
2. **A run is active** (`.temper/run.json` exists):
   - with no feature in the arguments, or the same feature: go on with the loop;
   - with a different feature: ask header `Temper`, question "A run for {slug} is at {stage}.
     Start over with the new feature?", options "Start over" (the run's spec folder stays;
     delete `run.json`, then start the new run) and "Cancel" (go on with the active run).
     Never choose "Start over" yourself.
3. **No run, no feature:** say "No run is active. Start one with `/temper:temper "<feature>"`."
   and stop.
4. **No run, a feature:** pick the slug (a folder of `.temper/specs` that already holds an
   `intent.md` for this feature keeps its name; else a short name of letters, digits, `.`, `_`
   or `-`; a ticket key keeps its case). Write `.temper/run.json` and
   `.temper/specs/{slug}/state.json` (stage `intent`, `base_sha` from `git rev-parse HEAD`, the
   current branch from `git branch --show-current`) and an empty `evidence.md` with its header.
   Go on with the loop.

## The loop

Read `state.json` and do the step of its `stage`. After each gate answer, update `state.json`
(the gate, the decision word for word, the reason, the time, one `history` row), then read it
again and go on. Stop only at "Save for later", the end of the run, or a question the person has
not answered.

**Launching an agent.** Use the Agent tool with `subagent_type` `temper:temper-{stage}` (when that
type is not offered, the general purpose agent, with the first line
`Follow {plugin folder}/agents/{stage}.md exactly.`) and `run_in_background: false`. The prompt:

```
Spec path: .temper/specs/{slug}
Feature: {the feature as the person typed it}
Plugin folder: {plugin folder}
{the stage's own lines below}
{Person's note: {text}, when the person asked for a change}
```

When it returns, print its panel verbatim. Then **confirm the checklist**: re-read the files for
each row of the panel's CHECKLIST that you can confirm cheaply (`reference/gates.md` lists the
rows): a heading, a count, an exit code in `evidence.md`. Where your reading differs from the
agent's, say so in one line and count the row as FAIL. The stage's checklist is PASS only when
every row is PASS.

| Stage | Agent and its own lines | Then |
|---|---|---|
| `intent` | `temper-intent` | TRIVIAL: "Trivial". Else the blocking questions, then the Intent gate. |
| `plan` | `temper-plan` | The blocking questions, then the Plan gate. |
| `design` | `temper-design` | The blocking questions, then the Design gate. |
| `build` | `temper-build` with `Group: G<n>`, one launch per group of `tasks.md` in dependency order; then one launch with `Scenario tests: all` | Drift questions after any launch with a DRIFT section; the group question between groups; the Build gate after the scenario tests. |
| `review` | `temper-review` with `Base: {base_sha}` | The Review gate. |
| `check` | `temper-check` | Each manual criterion's question, then the Check gate. |
| `commit` | none | The commit steps. |

**Which stages a run has.** Design runs when the tier is `complex`, or `medium` with risk `H`,
and `phases.design` in `.claude/temper.config` is not `false`, or when the spec folder already
holds `design.md`. Otherwise Plan's gate goes to Build.

## Every question

- **Header** `Temper gate` for a gate, as written below. The question names the stage, the
  checklist result (`checklist 9/9 PASS` or the failing rows by name) and what the answer does.
  Four options at most, in the order given. Never add a word such as "(Recommended)" that is not
  written here.
- **Typed text.** An answer typed in "Other", or a message the person writes at a question, is a
  question or a change request. Record it first as a `note` row in `evidence.md`. A question:
  answer it and ask the same question again. A change request at Intent, Plan, Design or Build:
  launch that stage's agent again with `Person's note: {the text}`, then ask its gate again. At
  Review, Check or Commit: ask the same question again; its options say how a change is made
  there (a loop back to Build).
- **"Teach Me" and "Grill Me" typed or chosen:** run the `teach-me` or `grill-me` skill on the
  stage's artifact, then ask the same question again. Neither moves the run.
- **Reasons.** An option marked *(reason)* needs the person's reason: their note on the option,
  or else ask header `Reason`, question "Why {the option, in lower case}?", options "Type the
  reason below" and "Cancel". Any typed answer is the reason; "Type the reason below" asks
  again; "Cancel" asks the first question again. Write the reason into `state.json`.
- **Walk through.** Present the artifact one section at a time, each with a question offering
  "Next section" and "Ask a question"; after the last section, ask the gate again.
- **Save for later** ends the turn: say "Run saved at {stage}. `/temper:temper` takes it up."

## Blocking questions

Before the Intent, Plan and Design gates, read the `- Blocking:` lines of `intent.md`'s Open
Questions. Ask them in one AskUserQuestion call (four at most per call; the rest in a second
call), each with header `Decide`, the question as written, and its ready choices as options
(the first one as written first) plus "Carry forward" when there are fewer than four. For each
answer, move the question from Open Questions to Decisions as
`- {question} -> {answer} (the person, {date})`; for "Carry forward", relabel it `Deferred:`.
A `Design:` question's answer also goes into that concern's `resolved:` line in `design.md`.
Then ask the gate.

## The gates

### Intent

Checklist PASS: "Continue to Plan" (accept the intent and plan it), "Walk through the intent",
"Grill Me", "Save for later". Checklist FAIL: "Run Intent again", "Continue anyway"
*(reason)*, "Walk through the intent", "Save for later".

**Continue:** set the intent header to `**Status:** accepted`. When the current branch is `main`,
`master` or the default branch, ask header `Branch`, question "Where should this run's work
go?", options "Continue on a new branch temper/{slug}" and "Continue on {branch}"; on the first,
run `git checkout -b temper/{slug}`. Record the branch. Stage `plan`.

**Trivial.** Ask header `Temper`, question "Intent says this is trivial: {its reason}. How
should it be handled?", options "Handle it directly" (no pipeline: make the change, run the
project's tests, then ask before committing) and "Run the full pipeline" (launch Intent again
with `Person's note: not trivial, write the intent`). On "Handle it directly", delete
`run.json`, make the change, run the tests, and ask header `Commit`, options "Commit" and
"Leave uncommitted".

### Plan

The question names what the Context Map leaves out and could not find (its `ignore` and `gap`
lines) so the person reads them. Checklist PASS: "Approve the plan" (start Design or Build, as
the run has), "Walk through the plan", "Grill Me", "Save for later". Checklist FAIL: "Run Plan
again", "Override and continue" *(reason)*, "Walk through the plan", "Save for later".

**Approve:** copy the tier and the risk from `plan.md` into `state.json`; stage `design` or
`build`.

### Design

The question names each open concern first. Checklist PASS: "Continue to Build" (open concerns
are accepted as written), "Walk through the design", "Grill Me", "Save for later". Checklist
FAIL: "Run Design again", "Override and continue" *(reason)*, "Walk through the design", "Save
for later".

**Continue:** add `resolved: accepted as written at the Design question ({date})` to each open
concern of `design.md`. Stage `build`.

### Build

**Drift.** For each row of a panel's DRIFT section, ask header `Scope drift`, question
`Outside the plan: {path}` with `Why: {why}` and `Change: {change}` lines, options "Add to
plan", "Revert", "Allow once". Record each answer in `state.json`'s `drift`, then launch the
same agent again with one `Drift decision: {path}: {add|revert|allow-once}` line per answer. A
drift is never answered for the person.

**Between groups** (only when `tasks.md` has more than one group): ask header `Temper`,
question "Group G<n> is done, checklist {result}. Go on to G<m>?", options "Continue to G<m>",
"Walk through the changes", "Run the group again", "Save for later".

**The Build gate.** Checklist PASS: "Continue to Review", "Walk through the changes", "Loop
back to Plan", "Save for later". Checklist FAIL: "Run Build again", "Override and continue"
*(reason)*, "Loop back to Plan", "Save for later". "Loop back to Plan" counts against the
`plan` loop budget and launches Plan with `Person's note:` naming the blocker.

### Review

When the checklist FAILs (an open finding at a `review.block-on` severity) or other findings
are open, the question lists them by id and severity.

Checklist PASS: "Continue to Check", "Walk through the findings", "Architecture Depth Review",
"More options". "More options" asks header `Temper gate`, options "Loop back to Build" (while
the budget lasts), "Accept a finding" *(reason)*, "Save for later".

Checklist FAIL: "Loop back to Build" (while the budget lasts), "Accept a finding" *(reason)*,
"Override and continue" *(reason)*, "Save for later".

- **Loop back to Build:** add one to `loops.review`; when it reaches `loops.max-per-type`
  (default 2), the option is no longer offered. Launch `temper-build` with
  `Feedback re-entry: review.md`, then Review again.
- **Accept a finding:** ask which (header `Finding`, one option per open finding, contested and
  escalated ones first, at most four per question), then its reason; mark it
  `accepted: {reason}` in `review.md`. Then ask the Review gate again.
- **Architecture Depth Review:** apply `reference/architecture-depth.md` to the changed modules
  and the `architecture-depth` pack, print the findings with an `[ARCH-DEPTH]` prefix, then ask
  again.

### Check

**Manual criteria first.** For each criterion the Check panel lists as manual, ask header
`Confirm`, question "AC-NN: {criterion}. {what to confirm}", options "Confirmed" and "Not met".
Record each answer in `check.md` and `evidence.md`. A "Not met" makes the Criteria row FAIL.

Checklist PASS: "Commit" (commit the change with its spec files), "Walk through the changes",
"Loop back to Build" (while the budget lasts), "Save for later". Checklist FAIL: "Loop back to
Build" (while the budget lasts), "Run Check again", "Override and commit" *(reason)*, "Save for
later". A loop back adds one to `loops.check` and launches `temper-build` with
`Feedback re-entry: check.md`, then Review and Check again.

### Commit

Only after the person chose "Commit" or "Override and commit":

1. Set the intent header to `**Status:** completed` and record the gate in `state.json`.
2. List the changed files: `git diff --name-only {base_sha}` and `git status --porcelain`. A file
   that is in neither the plan's files, an allowed drift, a test file nor the spec folder: ask
   its drift question first.
3. `git add` the run's files by name, and the spec folder unless the project ignores `.temper/`
   (then say in one line that the spec stays local). Then, in a separate Bash call,
   `git commit -m '{type}({slug}): {what the feature does}'` with a body line per criterion
   (`AC-NN: {criterion}`). Never `--no-verify`.
4. Print the report, delete `.temper/run.json`, and say "Committed: {hash} / Branch: {branch}.
   Temper does not push."

## The report

A code block built from `state.json` and `evidence.md`: the feature, the tier and risk, one row
per gate (`{stage}: {PASS|FAIL} -> {decision}{ (reason) }`), the loops, the drift decisions, the
accepted findings with their reasons, the RED and GREEN row counts, the coverage and the
scenario result. Then one line: "Gates in this edition are Claude's checklist and your answer;
nothing here was verified by a program."

## Entering at a stage (the stage commands)

`/temper:plan`, `/temper:design`, `/temper:build`, `/temper:review` and `/temper:check` are
doors into this flow, never flows of their own. They arrive here as `--enter {stage} {args}`.

1. **A run is active:** a door never moves it. When it is at another stage, say in one line
   where it is ("The run is at Review."). Then run the loop.
2. **No run, the Plan door:** start a run for the feature in the arguments, as Start says;
   Intent comes first.
3. **No run, a later door:** the run is for the folder of `.temper/specs` that holds `plan.md`
   and `tasks.md` (the one the arguments name, the only one, or else ask the person which; with
   none, say that this stage needs a planned feature and that `/temper:temper "<feature>"`
   starts one, and stop). Write `run.json` and `state.json` at the door's stage, with the tier
   from the `Complexity:` line of `plan.md`. The Design door enters at Build when the run has no
   Design stage, and says so. **The stages before the door are checked, not run again:** walk
   each one's checklist from `reference/gates.md`; for one that fails, ask its gate question
   with the FAIL options before going on.
