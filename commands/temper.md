---
description: "Unified SDLC command: intent → plan → design? → build → review → check → commit, gated by the temper CLI"
argument-hint: "<feature-description>"
---

# Temper: Unified SDLC Command (v9.2.0)

**Goal:** Run intent → plan → design? → build → review+check → commit with a human gate
at every stage (or, if armed, unattended past the plan gate). Every gate verdict is
computed by the `temper` CLI from an evidence ledger — never asserted by a model. The
Intent gate comes first because intent errors are the most expensive kind: correcting
the Problem statement costs words at the intent gate and costs the whole plan after it.

## Usage

```
/temper "add login feature"    # Start new feature
/temper                        # Resume or continue
```

---

## Architecture

Each stage runs in an **isolated Agent subprocess** — genuine context clearing, not a
self-directed "clear your context" instruction (which is unenforceable). What each stage
must do lives in exactly one place: `agents/{stage}.md` (frontmatter declares its default
model; the body points at `reference/{stage}.md` for methodology, tells it which
`temper` commands to run, and defines the summary box it returns). This file does not
repeat that contract per stage — read the agent file once when you launch it, and print
the box the agent returns verbatim rather than reconstructing it.

```
ORCHESTRATOR (this file)
  |
  +-- Agent(agents/intent.md)  -> intent gate -> temper gate intent (the fail-fast gate)
  +-- Agent(agents/plan.md)    -> plan gate  -> temper gate plan
  +-- Agent(agents/design.md)  -> design gate -> temper gate design (medium/complex only)
  +-- Agent(agents/build.md)   -> build gate  -> temper gate build
  +-- Agent(agents/review.md)  -> review gate -> temper gate review
  +-- Agent(agents/check.md)   -> check gate  -> temper gate check
  |
  +-- temper gate commit -> commit
```

`$CLAUDE_PLUGIN_ROOT` resolution: see `reference/orchestrator-patterns.md` →
"$CLAUDE_PLUGIN_ROOT Resolution". All paths below are relative to it. `$TEMPER` below
means `$CLAUDE_PLUGIN_ROOT/scripts/temper`.

## Models

Run `$TEMPER model --all` **once**, at the same time as the first state call, and keep
its output for the run. It prints one `stage=model` line per stage, resolving a project's
optional `models.{stage}` config override against the `agents/{stage}.md` default. The
stage launches below say `model: {plan}`, `{build}` and so on — substitute the value for
that stage from this output verbatim. Don't re-run it per stage, and don't infer a model
from anywhere else: this command is the only thing that knows whether the project
overrode one.

## First-run bootstrap

Before Stage 1, ensure the project is set up — **per piece, not all-or-nothing**, so a
partially-set-up project (config copied but no git hook, `.temper/` present but no
config) still ends up with every piece. All three steps are idempotent, so this is
safe to run every time; do the ones that are missing, silently skip the ones already
in place:

1. **Config** — if `.claude/temper.config` is absent, copy the default template.
2. **Scaffold** — run `$CLAUDE_PLUGIN_ROOT/scripts/temper init` (idempotent).
3. **Commit gate** — this is the headline guarantee, and the easiest to leave missing.
   If it isn't installed yet — no `pre-commit` hook carrying the marker
   `installed by scripts/hooks/install.sh` in the active hooks dir (`git config
   core.hooksPath` if set, else `.git/hooks`) — run
   `bash $CLAUDE_PLUGIN_ROOT/scripts/hooks/install.sh`. Not a git repo yet → say so in
   one line and continue (config + scaffold still done); the gate installs on the next
   run after `git init`.

If a step ran, print a one-line "Set up." note naming what was done; if everything was
already in place, continue into Plan silently. This per-piece check is what makes
install two `/plugin` commands then just `/temper "…"` — and what stops a config that
arrived some other way (a copied `.claude/`, a re-run that failed mid-way) from
running the pipeline with no commit gate.

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

1. Print the summary box it returned, verbatim (each agent brief defines its format —
   not restated here).
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
   and auto-clears evidence for `{to}` and every stage downstream of it in
   the sequence — a stale row from the stage being redone must not survive to inflate
   the next gate's count. If blocked, don't offer the loop option again this run; fall
   through to Override / Save.
2. Re-launch the upstream stage's Agent (same template as its first launch), adding one
   line to its prompt: *"Feedback re-entry: {reason}. Fix this, then continue."*
3. When it returns, re-run the downstream gate that triggered the loop.

That's the whole mechanism: a loop is a normal stage re-launch. Build→Plan is the one
exception: it's human-driven only (max 1 per run, no circuit breaker) because it means
the plan itself was wrong, not the implementation.

## Autonomous Continuation

Opt-in. `autonomy.enabled: false` or the block absent (default) → this feature does not
exist for the run: don't read anything, every gate is the ordinary interactive one
above. When `autonomy.enabled: true`, read `reference/autonomy.md` **once, at the plan
gate on PASS** — its arming point, never at invocation or mid-run — and follow it for
every post-plan gate. Two invariants, restated here because they bound the whole
feature: autonomy **never auto-commits** (PASS or FAIL at commit, it always parks), and
the Intent gate is always interactive.

---

## Stage 0: Intent (the fail-fast gate)

Why this is its own gate: **everything downstream is derived from the intent** — a
wrong Problem or a missing criterion multiplies into wrong scenarios, a wrong plan,
and a wrong build. The intent is the cheapest artifact in the run, so the human
corrects it FIRST, before the expensive exploration/architecture work spends anything.

Launch:

```
Use the Agent tool, model: {intent}, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/intent.md exactly. Feature: $ARGUMENTS.
Spec path: {from temper state get spec_path}."
```

The agent returns `READY` (intent.md written, or an existing draft refined) or
`TRIVIAL` (a typo/one-liner with no product problem to state — nothing written).
**On TRIVIAL:** the change exits the gated pipeline honestly instead of limping
through gates built for artifacts it doesn't have (`gate plan` would FAIL forever on
"artifacts exist" with nothing fixable). Tell the user in one line ("trivial — handling
directly, no pipeline"), run `$TEMPER state clear`, make the change directly, run the
project's tests, and commit normally — with no active run state, `temper gate commit`
degrades open by design, so the commit hook doesn't block a run that never gated. If
mid-change it turns out NOT to be trivial, stop and restart `/temper` properly.

Gate: `$TEMPER gate intent` (Problem stated, >=1 criterion, Status header). Options:
**"Continue to Plan (Recommended)"** / Grill Me / Teach Me / "Save for later" / Other
(a correction — edit intent.md, re-run the gate, re-show; this is the whole point of
the gate: intent corrections here cost words, the same correction after Plan costs the
plan). Open Questions are presented FIRST — each is answered by the human here or
explicitly carried forward; an intent accepted with open questions records that
choice.

**On Continue:** flip intent.md's header `Status: draft → accepted` and add
`**Accepted-by:** {git config user.name} <{user.email}>` — this human Continue is the
acceptance the artifact records. Commit the accepted intent in two separate Bash calls
(`git add .temper/specs/{slug}/`, then `git commit -m "docs(intent): accept {slug}"` —
separate calls so the in-agent commit-gate hook sees it staged; artifact-only commits
pass the fence; skip with a one-line note if the project gitignores `.temper/specs/`).
Then `$TEMPER state advance intent_complete plan` and launch Stage 1.

The Intent gate is **always interactive** — autonomy is armed later, at the plan gate,
never here: no unattended run starts without a human having accepted the intent.

---

## Stage 1: Plan

Launch:

```
Use the Agent tool, model: {plan}, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/plan.md exactly. Feature: $ARGUMENTS.
Spec path: {from temper state get spec_path}. The accepted intent.md there is your
input — derive scenarios and architecture from it; refine it only with a stated
reason."
```

Gate: `$TEMPER gate plan` — see `reference/plan.md` → "Approval" for the walkthrough
mechanics. **"Open HTML review"** (in addition to reference/plan.md's options): render
`templates/plan-review.html` with the `plan.md`/`tasks.md` sections filled in, open it,
wait for the user, then look for `review-comments.json` in the spec dir and apply it
(task-change / scenario-change / plan-change / general-note, mapped to its artifact).

**On Continue:** `$TEMPER state advance plan_complete design-or-build` (pick `design` if
`phases.design: true` and complexity is medium/complex, else `build`). (Intent
acceptance — the Status flip and `Accepted-by:` — already happened at the Intent gate;
this gate approves the *plan*.) Create the feature branch if not already on it
(`git checkout -b feature/{slug}`), then **commit the approved plan artifacts** in two
separate Bash calls, staging first: `git add .temper/specs/{slug}/`, then
`git commit -m "docs(plan): approve plan — {slug}"`. They must be separate calls, not
`add && commit`: the in-agent commit-gate hook runs `temper gate commit` at the moment
the `git commit` call is submitted, and the artifact-only carve-out that lets this
pass mid-run inspects the *already-staged* set — so the `git add` has to have run in a
prior call. (Skip both with a one-line note if the project gitignores `.temper/specs/`
— never `git add -f`.) This gives the diff a committed baseline to be reviewed
against. Then launch that stage.

**On PASS at the plan gate, before showing options:** if `autonomy.enabled: true`, read
`reference/autonomy.md` now and offer the arming choice it describes instead of a
single "Continue" option.

---

## Stage 1.5: Design (medium/complex only)

Skip straight to Build when `phases.design: false`, or complexity is trivial/simple.

Launch:

```
Use the Agent tool, model: {design}, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/design.md exactly. Spec: {spec_path from state}."
```

Run `$TEMPER gate design` (one requirement: design.md carries an Areas of Concern
section — flagged conflicts with owners, or an explicit "None flagged — why"; design
*quality* still shows up in whether Build can execute it and what Review finds). Gate
options: Continue / Grill Me / Teach Me / "Walk through step by step" (same shape as
Plan's — architecture overview, API contracts, database changes, integration points,
decision log; only sections `design.md` actually has) / Save / Other.

**On Continue:** `$TEMPER state advance design_complete build`, launch Build.

---

## Stage 2: Build

Launch:

```
Use the Agent tool, model: {build}, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/build.md exactly. Spec: {spec_path from state}.
{If a review-context.json or check-context.json feedback file exists, name it here.}"
```

Gate: `$TEMPER gate build` (RED-then-GREEN evidence recorded, no unchecked tasks).
Options: Continue to Review / Teach Me / "Loop back to Plan" (only if Build judges the
plan infeasible — human-driven, no circuit breaker, max 1 per run) / Override / Save.

**On Continue:** `$TEMPER state advance build_complete review`, launch Stage 3.

---

## Stage 3: Review

Launch:

```
Use the Agent tool, model: {review}, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/review.md exactly. Spec: {spec_path from state}."
```

Gate: `$TEMPER gate review` (zero open findings at or above `review.block-on`). An
**"Architecture Depth Review"** option is also always available — runs the 5-dimension
module-depth analysis (seams, adapters, locality, leverage, deletion test) on changed
files and folds `[ARCH-DEPTH]` findings into the summary before re-showing the gate.

**On Continue:** `$TEMPER state advance review_complete check`, launch Check.

---

## Stage 4: Check

Launch:

```
Use the Agent tool, model: {check}, prompt:
"Follow $CLAUDE_PLUGIN_ROOT/agents/check.md exactly. Spec: {spec_path from state}."
```

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
  On Commit: set `intent.md`'s header to `**Status:** completed` + `**Completed:**
  {date}` — this orchestrated path owns the terminal state flip (the standalone
  `/temper:check` gate does it only when Check runs as its own command; here the
  subprocess never gates, so the orchestrator must). If `build-context.json` recorded
  deviations from the plan (unplanned files, approach changes), write them into
  `plan.md` as a `## Deviations` section — the committed plan describes what was
  actually built. Run `$TEMPER state archive`: it writes the run's decision record to
  `.temper/specs/{slug}/gate-ledger.json` (verdicts, overrides with approver,
  evidence counts) **without touching the live state**, so the pre-commit gate still
  verifies for real. Then stage the diff **and the spec artifacts**
  (`.temper/specs/{slug}/` — intent.md, tasks.md, plan.md, design.md,
  gate-ledger.json as present): the committed artifact chain is the audit trail —
  what was asked for, what was planned, what the gates verified, and the diff that
  answers them, in one commit. If the project gitignores `.temper/specs/` that's its
  explicit choice — never `git add -f` over it; note once that the artifacts stay
  local-only. Then `git commit` (a conventional-commit message summarizing the
  feature), then `$TEMPER state clear`.
- **PASS (autonomous):** never auto-commits — park with a `SHIP-PENDING-COMMIT` report
  instead (the Park step in `reference/autonomy.md`).
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

These run directly in the current context by default — use them for granular control —
or in the same per-stage subprocess as `/temper` when `stages.subprocess: true` is set.
They still call `$TEMPER gate {stage}` at their own gate either way.
