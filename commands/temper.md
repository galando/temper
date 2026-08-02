---
description: "Unified SDLC command: plan → design? → build → review → check → commit, gated by the temper CLI"
argument-hint: "<feature-description>"
---

# Temper: Unified SDLC Command (v8.0.0)

**Goal:** Run plan → design? → build → review+check → commit with a human gate at every
stage (or, if armed, unattended past the plan gate). Every gate verdict is computed by
the `temper` CLI from an evidence ledger — never asserted by a model.

## Usage

```
/temper "add login feature"    # Start new feature
/temper                        # Resume or continue
```

---

## Architecture

Each stage runs in an **isolated Agent subprocess** — genuine context clearing, not a
self-directed "clear your context" instruction (which is unenforceable). What each stage
must do lives in exactly one place: `agents/{stage}.md` (frontmatter declares its model;
the body points at `reference/{stage}.md` for methodology and tells it which `temper`
commands to run). This file does not repeat that contract per stage — read the agent
file once when you launch it.

```
ORCHESTRATOR (this file)
  |
  +-- Agent(agents/plan.md)    -> plan gate  -> temper gate plan
  +-- Agent(agents/design.md)  -> design gate (medium/complex only)
  +-- Agent(agents/build.md)   -> build gate  -> temper gate build
  +-- Agent(agents/review.md)  -> review gate -> temper gate review
  +-- Agent(agents/check.md)   -> check gate  -> temper gate check
  |
  +-- temper gate commit -> commit
```

`$CLAUDE_PLUGIN_ROOT` resolution: see `reference/orchestrator-patterns.md` →
"$CLAUDE_PLUGIN_ROOT Resolution". All paths below are relative to it. `$TEMPER` below
means `$CLAUDE_PLUGIN_ROOT/scripts/temper`.

## State

`$TEMPER state` owns `.temper/build-state.json` — never hand-write it. When a step calls
for more than one `$TEMPER` invocation in a row (state/evidence calls only, never `gate`),
batch them into a single Bash tool call, one shell command per line — they're sequential
anyway, and it's one round-trip instead of several.

- **Start:** `$TEMPER state init {slug} --command temper` (creates it, `stage: started`,
  branch `feature/{slug}`).
- **Advance:** after each gate's "Continue", `$TEMPER state advance {stage}_complete {next}`.
- **Resume:** if `.temper/build-state.json` exists, read `$TEMPER state get spec_path`
  and `$TEMPER state get stage` to find where you left off. If it exists for a
  **different** feature than `$ARGUMENTS`, ask the user: resume the existing one, or
  overwrite and start fresh (`$TEMPER state clear` then re-init).
- **On commit:** `$TEMPER state clear` (evidence, gates, loop counters — spec artifacts
  under `.temper/specs/` are untouched, they're the permanent record).

## Gates

Every stage gate follows the same shape. After a stage Agent returns:

1. Print its summary box (see per-stage format below).
2. Run `$TEMPER gate {stage}`. It prints PASS/FAIL with each requirement's status and
   writes the verdict to `.temper/gates.json`.
3. Show an `AskUserQuestion` gate:
   - **On PASS:** `"Continue to {next} (Recommended)"` / `"Save for later"` / free-text
     `"Other"` for a change request (make the edit, re-run the gate, re-show).
   - **On FAIL:** `"Loop back to {upstream stage}"` (if `feedback.enabled` and the loop
     budget allows — see Feedback Loops) / `"Override and continue"` (records
     `$TEMPER override {stage} --reason "<what the user typed>"`, which stays visible in
     the final report — it does not erase the FAIL) / `"Save for later"`.
4. Autonomous mode replaces step 3 — see Autonomous Continuation below.

Every gate also offers, unconditionally (no config toggle): **"Grill Me"** (skill
`grill-me`), **"Teach Me"** (skill `teach-me`), and at Plan: **"Walk through step by
step"** and **"Open HTML review"**. Each returns to the same gate — none advance or
block the pipeline.

Never re-derive gate logic here or in a stage prompt — a gate mechanics change is a
`scripts/temper` edit plus a `test-temper.sh` case, not a prompt edit.

## Feedback Loops

When a gate FAILs and the user selects "Loop back":

1. `$TEMPER state loop {from} {to} --reason "<why>"` — this enforces
   `loops.max-per-type` (default 2), prints `BLOCKED` (exit 1) once the budget is spent,
   and (as of v8) auto-clears evidence for `{to}` and every stage downstream of it in
   the sequence — a stale row from the stage being redone must not survive to inflate
   the next gate's count. If blocked, don't offer the loop option again this run; fall
   through to Override / Save.
2. Re-launch the upstream stage's Agent (same template as its first launch), adding one
   line to its prompt: *"Feedback re-entry: {reason}. Fix this, then continue."*
3. When it returns, re-run the downstream gate that triggered the loop.

That's the whole mechanism — there is no separate "loop cost tier" or context-size
branching in v7+. A loop is a normal stage re-launch. Build→Plan is the one exception:
it's human-driven only (max 1 per run, no circuit breaker) because it means the plan
itself was wrong, not the implementation.

## Autonomous Continuation

Opt-in, armed by the human at the **plan gate only** — never at invocation or mid-run.
`autonomy.enabled: false` or the block absent (default) → skip this whole section, every
gate is the ordinary interactive one above.

**Arming** (at the plan gate, after human review): replace "Continue to Build" with
"Stage by stage (Recommended)" (`run_mode: interactive`) / "Autonomous — run the rest
unattended" (`run_mode: autonomous`).

**While `run_mode == autonomous`, every post-plan gate:** run `$TEMPER gate {stage}` as
usual. **PASS** → auto-select Continue, no `AskUserQuestion` (but still print the summary
box — an unattended run must leave a scroll-back-readable record). **FAIL** → loop
automatically at the same budget as interactive mode, except Build→Plan (always returns
to a human, never auto-loops); budget exhausted → park instead of asking. **At commit:**
`$TEMPER gate commit` already checks blast radius + park-on-touch (autonomous-only) along
with every upstream gate — PASS or FAIL, **always park**, autonomy never auto-commits.

**Park:** `$TEMPER state set run_mode interactive` (so a plain resume lands here
normally), write `.temper/autonomy-report.md` (`**Verdict:**
SHIP-PENDING-COMMIT|PARKED-NEEDS-DECISION`, `**Parked at:**`/`**Reason:**` verbatim from
`temper gate`, `**Branch:**`, the `$TEMPER report` ledger, "Run /temper to resume").

**Operational safety (hardcoded — see `templates/temper.config.default`):** refuse a
dirty tree unless confirmed; `git commit -m "wip: {stage} passed"` after each PASS stage
(a crash loses at most one stage); `.temper/autonomy.lock` refuses a second concurrent run.

---

## Stage 1: Plan

Launch:

```
Use the Agent tool, model: opus, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/plan.md exactly. Feature: $ARGUMENTS.
Spec path: {from temper state get spec_path, or a new slug you choose}."
```

Summary box:

```
+-----------------------------------------------------------+
| PLAN — {Feature Name}                                     |
+-----------------------------------------------------------+
| INTENT: {one-line problem} -> {success criteria}           |
| SCENARIOS: {N} ({list})                                    |
| ARCHITECTURE: create {N} files, modify {N} files            |
| COMPLEXITY: {trivial|simple|medium|complex}  RISK: {L/M/H}  |
+-----------------------------------------------------------+
{ASCII art diagram — box-drawing characters, never raw mermaid source}
```

Gate: `$TEMPER gate plan` — see `reference/plan.md` → "Approval" for the walkthrough
mechanics. **"Open HTML review"** (in addition to reference/plan.md's options): render
`templates/plan-review.html` with the `plan.md`/`tasks.md` sections filled in, open it,
wait for the user, then look for `review-comments.json` in the spec dir and apply it
(task-change / scenario-change / plan-change / general-note, mapped to its artifact).

**On Continue:** `$TEMPER state advance plan_complete design-or-build` (pick `design` if
`phases.design: true` and complexity is medium/complex, else `build`). Create the feature
branch if not already on it (`git checkout -b feature/{slug}`), then launch that stage.

**On PASS at the plan gate, before showing options:** if `autonomy.enabled: true`, offer
the continuation choice described above instead of a single "Continue" option.

---

## Stage 1.5: Design (medium/complex only)

Skip straight to Build when `phases.design: false`, or complexity is trivial/simple.

Launch:

```
Use the Agent tool, model: opus, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/design.md exactly. Spec: {spec_path from state}."
```

Summary box: architecture overview, key decisions, what's new/modified/existing.

There is no `temper gate design` — this stage has no single-correct-output requirement
in v7; its quality shows up in whether Build can execute it and what Review finds. Gate
options: Continue / Grill Me / Teach Me / "Walk through step by step" (same shape as
Plan's — architecture overview, API contracts, database changes, integration points,
decision log; only sections `design.md` actually has) / Save / Other.

**On Continue:** `$TEMPER state advance design_complete build`, launch Build.

---

## Stage 2: Build

Launch:

```
Use the Agent tool, model: sonnet, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/build.md exactly. Spec: {spec_path from state}.
{If a review-context.json or check-context.json feedback file exists, name it here.}"
```

Summary box:

```
+-----------------------------------------------------------+
| BUILD — {Feature Name}                                    |
+-----------------------------------------------------------+
| Tasks: {N}/{N} complete   Tests: {N} added, all passing    |
| Files: {N} created, {N} modified                           |
+-----------------------------------------------------------+
```

Gate: `$TEMPER gate build` (RED-then-GREEN evidence recorded, no unchecked tasks).
Options: Continue to Review / Teach Me / "Loop back to Plan" (only if Build judges the
plan infeasible — human-driven, no circuit breaker, max 1 per run) / Override / Save.

**On Continue:** `$TEMPER state advance build_complete review`, launch Stage 3.

---

## Stage 3: Review

Launch:

```
Use the Agent tool, model: sonnet, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/review.md exactly. Spec: {spec_path from state}."
```

Summary box: files changed, findings by severity, security hot paths, intent-validation
verdict, scenario coverage.

Gate: `$TEMPER gate review` (zero open findings at or above `review.block-on`). An
**"Architecture Depth Review"** option is also always available — runs the 5-dimension
module-depth analysis (seams, adapters, locality, leverage, deletion test) on changed
files and folds `[ARCH-DEPTH]` findings into the summary before re-showing the gate.

**On Continue:** `$TEMPER state advance review_complete check`, launch Check.

---

## Stage 4: Check

Launch:

```
Use the Agent tool, model: sonnet, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/check.md exactly. Spec: {spec_path from state}."
```

Summary box: compile/test/lint/security results, coverage %, scenario verification.

Gate: `$TEMPER gate check` (tests pass, coverage >= threshold, every `intent.md` scenario
traced to a test by name — this is the gate that catches the README's rate-limiting
story). On a clean pass, Check may also have written `{spec_path}/config-suggestions.json`
— if present, offer a **"Review config suggestions"** option before Continue: show each,
Accept (write it into CLAUDE.md/AGENTS.md) / Reject / Defer, then re-show the gate.

**On Continue:** `$TEMPER state advance check_complete commit`, proceed to Commit.

---

## Commit

Run `$TEMPER gate commit`. It aggregates every upstream gate's last verdict (PASS or
overridden), and — only when `run_mode == autonomous` — blast radius and park-on-touch.

- **PASS (interactive):** `AskUserQuestion` — "Commit" / "Save for later" / "Other".
  On Commit: stage the diff, `git commit` (a conventional-commit message summarizing the
  feature), then `$TEMPER state clear`.
- **PASS (autonomous):** never auto-commits (see Autonomous Continuation) — park with a
  `SHIP-PENDING-COMMIT` report instead.
- **FAIL:** show `$TEMPER report`, offer "Override and commit" (records the override,
  re-run `$TEMPER gate commit`, it should now PASS) or "Save for later".

Print the final ledger (`$TEMPER report`) either way — the last thing the user sees is
what was actually verified, not a narrated summary.

---

## Resume

`/temper` with no arguments and `build-state.json` exists → validate per
`reference/orchestrator-patterns.md` → "Resume Validation", then launch `next_stage`.
`/temper "new feature"` while state exists for a **different** feature → follow
"Nested Invocation Protection" there (say "feature", not "item"). `/temper` (no args) for
the **same** feature already in progress → "Continue from {next_stage} (Recommended)" or
"Start over (replan)".

---

## Individual Commands Still Work

```
/temper:plan    → Just planning, stops at gate
/temper:design  → Just design (for complex features), stops at gate
/temper:build   → Just building, stops at gate
/temper:review  → Just review, stops at gate
/temper:check   → Just check, stops at gate
```

These run directly in the current context (no Agent subprocess) — use them for granular
control. They still call `$TEMPER gate {stage}` at their own gate.
