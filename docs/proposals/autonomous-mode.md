# Proposal: Autonomous Mode for `/temper`

**Status:** Draft / Plan
**Target version:** 5.10.0
**Scope:** `/temper` unified command (extensible to `/temper:fix` later)
**Default behavior:** unchanged — autonomous mode is strictly opt-in.

---

## 1. Motivation

Temper today is human-in-the-loop by design: every stage (`plan → design → build →
review → check → eval → commit`) stops at an `AskUserQuestion` gate that requires an
explicit human "Continue". That is the right default — it is where Temper's intent-
alignment value lives — but it forbids the "fire it before bed, read the verdict in the
morning" workflow that a fixed 4-agent pipeline (Planner → Coder → Tester → Reviewer)
offers.

This proposal adds an **Autonomous Mode**: an opt-in run mode that auto-resolves the
stage gates Temper already has, keeps every quality gate, feedback loop, and circuit
breaker intact, and **parks before commit** for the human — exactly the article's
morning-handoff model, but on top of Temper's stronger pipeline.

**Design stance:** *autonomy within a safety envelope*, not "fully autonomous." The
pipeline runs unattended **until it reaches a decision a human should own** — an open
question, a blast-radius trip, an unfixable BLOCK, or the commit itself — at which point
it parks with a report and degrades into the existing save-state/resume path.

**Per the user's requirement:** available for **any** feature, not clamped to
small/simple changes. Complexity is *not* the gatekeeper — the blast-radius safety
envelope is. Complex changes are allowed; they simply park more often (typically at the
plan gate), which is the correct behavior.

---

## 2. How it surfaces to the user

Three entry points, first-match-wins, all resolving to the same internal `run_mode`:

1. **Invocation arg** (highest precedence):
   `/temper --auto "add rate limiting to login"` → autonomous run.
   `/temper --interactive "..."` → force interactive even if config defaults to auto.
2. **Run Mode selector** at `/temper` start (when no arg given and `autonomy.prompt:
   true`): an `AskUserQuestion` shown once, before Stage 1, that governs **all** gates
   for the run:
   ```
   AskUserQuestion:
     question: "How should this run be driven?"
     options:
       - label: "Interactive (Recommended)"
         description: "Stop at every stage gate for your decision. (current behavior)"
       - label: "Autonomous (run unattended)"
         description: "Auto-resolve gates per policy; park before commit and on any
                       decision a human should own. Read the report when you're back."
   ```
3. **Config default** (lowest precedence): `autonomy.mode` in `.claude/temper.config`.

Resolution order: **arg → selector (if prompted) → config default → `interactive`.**
The selector is shown only for genuinely new runs; on resume the saved `run_mode` is
reused.

---

## 3. The core mechanic — auto-resolve gates

Autonomous mode does **not** add a parallel pipeline. It replaces each gate's
`AskUserQuestion` call with a deterministic **auto-resolve decision** that selects the
gate's existing "Recommended" option *unless* a park condition fires. Every other piece
(feedback loops, circuit breakers, loop cost tiers, observability, save-state) is reused
verbatim.

### Per-gate policy

| Gate | Auto-action (no park) | Park condition (halt + report) |
|------|----------------------|--------------------------------|
| **Plan** | Select "Continue to Build" | Plan has `OPEN QUESTIONS` / unresolved ambiguity, **OR** blast radius exceeds `autonomy.max-blast-radius`, **OR** an `models.escalate-on` trigger (`architecture-finding`, `correctness-risk`) is present, **OR** the change touches a `autonomy.park-on-touch` guard path (auth / money / shared interface) |
| **Design** | Select "Continue to Build" | Design surfaces an unresolved open question / undecided trade-off |
| **Build** | Select "Continue to Review" | Build hits infeasibility (would trigger Build→Plan). Plan revision is human-driven with no circuit breaker, so autonomy **never** loops Build→Plan unattended — it parks |
| **Review** | Select "Fix all & continue to Check"; run the Review→Build auto-fix loop, bounded by `feedback.max-loops` | Critical/BLOCK-class findings remain after max loops, **OR** a non-auto-fixable critical finding exists |
| **Check** | On test failures, run the Check→Build loop, bounded by `feedback.max-loops`; otherwise advance | Tests still failing after max loops, **OR** same failure twice in a row (existing circuit breaker rule 3) |
| **Eval** | On `eval.block-on` failure, run the Eval→Build loop, bounded by `feedback.max-loops`; otherwise advance | A `block-on` dimension still below `pass-threshold` after max loops |
| **Commit** | **Never auto-commit.** Always park with a SHIP-pending report | Always parks (this *is* the final human gate) unless `autonomy.stop-before-commit: false` is explicitly set |

This is a direct superset of the article's three stop conditions (open questions, failing
tests, BLOCK verdict) plus a blast-radius envelope and a hard no-merge rule.

### Interaction with circuit breakers

No new looping logic. Autonomy auto-*selects* the loop option that a human would select
interactively; the existing rules in `orchestrator-patterns.md → Circuit Breaker Rules`
(max 2 loops/type, same-issue-twice → stop, counter in `feedback-loops.json`) bound it
unchanged. **A tripped circuit breaker becomes a park**, not an infinite loop.

### Capabilities suppressed in autonomous mode

`teach-me`, `grill-me`, the HTML plan walkthrough, and config-suggestion prompts are
**skipped** when `run_mode == autonomous` — they are human-interactive and meaningless
unattended. (Config suggestions are still *generated* and listed in the report for later
review; they are just not prompted.) These suppressions are mode-scoped and do not touch
the capability flags.

---

## 4. Safety envelope (the part that makes "any feature" safe)

Because autonomy is allowed on complex changes, the guardrails — not the complexity tier
— are what keep it safe. New `autonomy` config block:

```yaml
# ============================================================
# Autonomous Mode (v5.10.0)
# Opt-in unattended runs. Default mode is `interactive`, which is
# byte-identical to v5.9.0 (no gate auto-resolves). Autonomy runs ANY
# complexity; the blast-radius envelope below — not the complexity tier —
# decides when it parks for a human.
# ============================================================
autonomy:
  mode: interactive          # interactive | auto. Default interactive (no behavior change).
  prompt: true               # show the Run Mode selector at /temper start when no --auto/--interactive arg

  # --- Safety envelope ---
  stop-before-commit: true   # NEVER auto-commit/merge. The human is always the merge gate.
                             # false => auto-commit on a clean pipeline (still NEVER pushes/merges).
  max-blast-radius: 15       # park at the plan gate if blast radius exceeds this many files
  park-on-touch:             # park at the plan gate if the change touches these (substring/glob match)
    - "**/auth/**"
    - "**/payment/**"
    - "**/billing/**"
  respect-escalation: true   # park when a models.escalate-on trigger appears
                             # (architecture-finding, correctness-risk)

  # --- Loop budget (reuses feedback.max-loops; listed here for discoverability) ---
  auto-fix: true             # allow Review→Build / Check→Build / Eval→Build auto-fix loops
  max-loops: 2               # alias of feedback.max-loops for autonomous runs

  # --- Handoff ---
  report: ".temper/autonomy-report.md"   # morning-handoff verdict file (see §5)
  notify: none               # none | push  (push => fire a PushNotification when the run parks)
```

**Graceful-degradation contract** (matches Temper's existing discipline): when
`autonomy.mode: interactive` **or the `autonomy` block is absent**, no gate auto-resolves
and the run is byte-identical to v5.9.0. Disabling autonomy never affects adaptive-depth,
cache, loops, or model routing.

**Complexity is orthogonal.** Autonomy does not read `adaptive-depth.floor` and is not
clamped by it. A complex feature runs autonomously; it will simply hit the plan-gate park
conditions (blast radius, escalation triggers, guard paths) more often and hand back to
the human there — which is the intended "autonomy within an envelope" behavior. Users who
want complex changes to sail through can raise `max-blast-radius` and empty `park-on-touch`.

---

## 5. The park artifact (morning handoff)

When the pipeline parks, it does two things:

1. **Saves state** exactly like the existing "Save for later" path — `build-state.json`
   with the parked `stage`/`next_stage`, plus `run_mode: autonomous`. This means *resume
   is free*: the human runs `/temper` and lands back at the parked gate, interactively.
2. **Writes `.temper/autonomy-report.md`** — the analogue of the article's
   `.pipeline/review.md`. Proposed schema:

```markdown
# Autonomy Report — {feature slug}

**Verdict:** SHIP-PENDING-COMMIT | PARKED-NEEDS-DECISION | BLOCKED
**Parked at:** {stage} gate
**Reason:** {one-line park reason}
**Branch:** feature/{slug}   **Run mode:** autonomous   **Finished:** {ISO ts}

## What ran
| Stage | Result | Auto-decision | Loops |
|-------|--------|---------------|-------|
| Plan  | depth=complex, blast=12 files | continued | — |
| Build | 6/6 tasks, 5 tests | continued | — |
| Review| 2 high auto-fixed | fix-all → continued | 1 |
| Check | tests pass, cov 86% | continued | 1 (Check→Build) |
| Eval  | aggregate 0.82 ≥ 0.75 | continued | — |
| Commit| — | PARKED (stop-before-commit) | — |

## Your next action
{Exact instruction: e.g. "Review the diff and run `/temper` to resume at the Commit gate,
or `git diff` then commit." For PARKED/BLOCKED: the precise question to answer, with the
file:line context that triggered the park.}

## Open questions / blockers
- {if any}

## Artifacts
- spec: .temper/specs/{slug}/  (intent.md, tasks.md, plan.md[, design.md])
- diff: `git diff`
- config suggestions (generated, not applied): {list or "none"}
```

`VERDICT` maps to the article's SHIP / NEEDS WORK / BLOCK trichotomy:
SHIP-PENDING-COMMIT ≈ SHIP, PARKED-NEEDS-DECISION ≈ NEEDS WORK, BLOCKED ≈ BLOCK.

---

## 6. Observability

Record the run so `/temper:status` can show what happened overnight. Additions to
`observability.json`:

- `run_mode: "autonomous" | "interactive"` (per run).
- `gate_decisions: []` — one entry per gate: `{ stage, decision, auto: true|false,
  reason, ts }`. Interactive runs leave `auto: false`; autonomous runs record the
  auto-resolved choice and its justification.
- `park: { stage, reason, verdict, ts }` when the run parks.

`/temper:status` gains an "Autonomous runs" section: last run mode, where it parked, how
many gates auto-resolved, loops consumed vs. budget.

---

## 7. Files to change

| File | Change |
|------|--------|
| `.claude/temper.config` | Add the `autonomy:` block (§4), defaulted to `interactive`. |
| `.claude-plugin/reference/orchestrator-patterns.md` | **New canonical section "Autonomy Mode"**: run_mode resolution, the per-gate auto-resolve policy table (§3), park conditions, park-report schema (§5), circuit-breaker interaction, capability suppression, observability fields, and the graceful-degradation contract. This is the shared home; `temper.md` references it (single-read contract). |
| `.claude/commands/temper.md` | (a) Resolve `run_mode` at entry + show the Run Mode selector; (b) at **every** Stage Gate, add an "Autonomous auto-resolve" branch that, when `run_mode == autonomous`, evaluates the park policy and either selects the Recommended option or parks (instead of calling `AskUserQuestion`); (c) Commit stage: never auto-commit under autonomy — write the report and park; (d) suppress teach-me/grill-me/walkthrough/config-prompts under autonomy. |
| `.claude-plugin/reference/status.md` | Add the "Autonomous runs" panel (run_mode, park point, gate auto-resolve count, loop budget used). |
| `.claude/CLAUDE.md` | Document `/temper --auto` and the autonomy config in the command table / notes. |
| `README.md` | New "Autonomous Mode" subsection: opt-in, safety envelope, parks before commit, "any complexity." |
| `CHANGELOG.md` | 5.10.0 entry. |
| `.claude-plugin/plugin.json` / version refs | Bump to 5.10.0. |

**Out of scope (future):** extending autonomy to `/temper:fix` (it already shares
`orchestrator-patterns.md`, so it would inherit the Autonomy Mode section with a thin
hook), and a true background/scheduled runner.

---

## 8. Test / verification plan

1. **Degradation:** with no `autonomy` block (and with `mode: interactive`), diff the
   gate behavior against v5.9.0 — must be byte-identical (no auto-resolve, selector not
   shown unless `prompt: true` and even then it defaults to interactive).
2. **Happy path:** `/temper --auto` on a small isolated change → runs to the Commit gate,
   parks, writes a SHIP-PENDING-COMMIT report; `/temper` resume lands at Commit.
3. **Open-question park:** a vague request → plan flags OPEN QUESTION → parks at plan with
   PARKED-NEEDS-DECISION.
4. **Blast-radius park:** a change touching `>max-blast-radius` files or a `park-on-touch`
   path → parks at plan even though the plan itself is clean.
5. **Loop-then-park:** seed a persistent test failure → Check→Build loops to `max-loops`,
   circuit breaker trips → parks BLOCKED with the failing test in the report.
6. **No-merge guarantee:** assert that no autonomous path ever calls `git commit`
   (with default `stop-before-commit: true`) or `git push`/merge under any setting.
7. **Complex feature:** a complex-tier feature runs autonomously (not clamped by
   adaptive-depth) and parks per the envelope, not per the tier.

---

## 9. Recommendation

Ship it **opt-in**, default `interactive`, with `stop-before-commit: true` and the
blast-radius envelope on by default. This captures ~80% of the overnight-batch value
(green check + SHIP verdict gates auto-resolve) while keeping the human exactly where the
human adds value: ambiguous intent, high blast radius, and the merge decision. Do not make
it the default, and keep teach-me/grill-me interactive-only — they are the heart of
Temper's "stay in command of the change" promise and have no meaning unattended.
