# Proposal: Autonomous Continuation for `/temper`

**Status:** Draft / Plan
**Scope:** `/temper` unified command (extensible to `/temper:fix` later)
**Default behavior:** unchanged — autonomy is opt-in and armed by a human at the plan gate.

---

## 1. Motivation

Temper is human-in-the-loop by design: every stage (`plan → design → build → review →
check → eval → commit`) stops at an `AskUserQuestion` gate. That is the right default, but
it forbids the "approve the plan, then let the rest run while I'm away" workflow that a
fixed 4-agent pipeline offers.

This proposal adds **Autonomous Continuation**: after the human reviews and approves the
**plan**, they may let the *remaining* stages run unattended. Every quality gate, feedback
loop, and circuit breaker stays intact; the run **parks before commit** and on any
decision a human should own.

> **Guarantees.** Autonomy never pushes, never merges, never re-plans unattended, and
> always lets you review the plan first.

### Design stance

- **The plan stage is always human-gated.** `/temper` always runs Plan first and stops at
  the plan gate. Autonomy is *armed there*, never at invocation. The model never
  auto-approves its own plan — the highest-leverage, highest-risk judgment stays with the
  human. (The article's own thesis: "the plan sets the ceiling for everything after it.")
- **Autonomy governs post-plan stages only:** `design? → build → review → check → eval`,
  then parks at commit.
- **Autonomy within a safety envelope, not "fully autonomous."** It runs unattended until
  it hits a decision a human should own — a budget ceiling, a blast-radius trip, an
  unfixable BLOCK, or the commit — then parks with a report and degrades into the existing
  save-state/resume path.
- **Any complexity.** Autonomy is not clamped to small features. Complexity is orthogonal;
  the blast-radius envelope decides when it parks.

---

## 2. How it surfaces — the plan-gate choice

There is **no invocation-time mode**. The user runs `/temper "..."` exactly as today. Plan
runs, the plan gate appears, and the human reviews/edits/approves the plan as always. The
plan gate gains a continuation choice:

```
AskUserQuestion (at the plan gate, after the plan is approved):
  question: "The plan is approved. How should the remaining stages run?"
  options:
    - label: "Stage by stage (Recommended)"
      description: "Stop at each gate for your decision. (current behavior)"
    - label: "Autonomous — run the rest unattended"
      description: "Auto-resolve design→build→review→check→eval per policy; park before
                    commit and on anything needing a human. Read the report when you're back."
  multiSelect: false
```

- The existing plan-gate options (`Grill Me`, `Teach Me`, walkthrough, `Escalate to full
  pipeline`, `Save for later`, `Other`) are unchanged; the two continuation options above
  replace the single "Continue to Build/Design".
- **Interactive gates are annotated, not duplicated.** When `autonomy.enabled`, every
  *stage-by-stage* gate additionally shows the decision autonomy *would* take, its
  confidence, and whether the park policy would have continued or stopped — as an
  annotation above the usual options. This gives the trust-building / calibration value
  ("watch it make the right calls before going unattended") without a separate mode. The
  human still decides. When `autonomy.enabled` is false, no annotation is shown.
- `default-choice` config decides which continuation option is pre-highlighted. There is
  **one entry point** — the plan gate. No invocation flag; the choice always happens here.
- On a Build→Plan feedback loop (infeasible design), control returns to the plan gate —
  i.e. back to a human — and the continuation choice is offered again. Autonomy never
  re-plans unattended.

### What each mode means

| Mode | Does real work? | Gate behavior |
|------|-----------------|---------------|
| Stage by stage (interactive) | yes | stops at every gate; human decides. When `autonomy.enabled`, each gate is **annotated** with the decision autonomy would take + confidence + would-it-park — calibration without ceding control |
| Autonomous | yes | auto-resolves each gate per policy; only pauses to **park** |

There are exactly **two** modes. The interactive-gate annotation is the trust on-ramp (the
article's "start small, build trust"): watch the autonomy policy propose the right calls a
few times — while you still click every gate — then choose Autonomous when you trust it. A
separate "supervised" mode was considered and dropped: it duplicated interactive (both stop
at every gate and require a human click), so its only real value — surfacing the autonomy
decision + confidence — was folded into the interactive gate annotation instead.

---

## 3. Core mechanic — auto-resolve gates (post-plan only)

Autonomy is **not** a parallel pipeline. For each post-plan gate it replaces the
`AskUserQuestion` call with a decision that selects the gate's existing "Recommended"
option **unless a park condition fires**. Feedback loops, circuit breakers, loop cost
tiers, observability, and save-state are reused verbatim. In interactive mode the same
decision is computed and shown as a gate annotation, but the human still chooses.

| Gate | Auto-action (no park) | Park condition (halt + report) |
|------|----------------------|--------------------------------|
| **Plan** | — | **Always human** (the arming point; never auto-resolved) |
| **Design** | "Continue to Build" | Design surfaces an unresolved trade-off / open question (subject to the confidence rule, §4) |
| **Build** | "Continue to Review" | Build hits infeasibility → returns to the **plan gate** (human); autonomy never loops Build→Plan unattended |
| **Review** | "Fix all & continue to Check", running the Review→Build auto-fix loop bounded by `feedback.max-loops` — but applying only `auto-fix-severity` levels (§7) | A `critical`/BLOCK-class finding remains after max loops, or a non-auto-fixable critical exists |
| **Check** | On test failures, run Check→Build loop bounded by `feedback.max-loops`; else advance | Tests still failing after max loops, or same failure twice (existing circuit-breaker rule 3) |
| **Eval** | On `eval.block-on` failure, run Eval→Build loop bounded by `feedback.max-loops`; else advance | A `block-on` dimension still below `pass-threshold` after max loops |
| **Commit** | **Never auto-commit** | Always parks with a SHIP-pending report (unless `stop-before-commit: false` is explicitly set) |

A tripped circuit breaker becomes a **park**, never an infinite loop. The global budget
(§5) bounds the run regardless of per-type loop counts.

---

## 4. Self-judgment safeguards (the core risk)

Most park conditions are *LLM judgments*, not deterministic checks — and the same model
that might misbuild is the one deciding whether to stop. Three structural mitigations,
none of which adds a new mechanism:

1. **Plan is always human-reviewed (§2).** The single most dangerous autonomous judgment —
   "is this the right thing to build?" — is removed from autonomy entirely.
2. **Conservative bias (`conservative-bias: true`, default):** when a proceed/park signal
   is *uncertain*, park. Default-to-stop, not default-to-proceed.
3. **Confidence threshold:** a "continue" decision whose confidence falls below the
   **existing** `review.confidence-threshold` (default 0.7) is downgraded to a park. One
   threshold, one meaning — no new config key.

*Deferred to a future iteration (not v1):* an isolated `tier-fast` gate-judge that sees
only the artifact + policy (mirroring the article's read-only reviewer). The three
mitigations above cover the core risk without the extra agent.

---

## 5. Run budget — hard ceiling

Per-type loop limits do not bound a whole overnight run (Review + Check + Eval loops
compound). A global budget forces a park when exceeded:

```yaml
budget:
  max-total-loops: 4        # across ALL feedback types in one run
  max-stages: 12            # stage executions incl. loop re-entries
  max-wall-clock-min: 60
```

Park verdict `BUDGET-EXCEEDED`, preserving whatever stages completed. This is the
guardrail against waking to a run that churned all night. (Limits are the three we can
actually measure; a token/cost cap is deferred until the harness exposes usage reliably.)

---

## 6. Operational safety

Autonomy edits files unattended for a long time, so tree hygiene is mandatory:

- **Clean-start (`require-clean-tree: true`):** refuse to begin autonomous continuation if
  the working tree is dirty — or auto-stash and note it in the report. Never build on top
  of unknown local changes.
- **Recoverable checkpoints (`checkpoint: wip-commit | none`):** by default, commit a
  `wip:` checkpoint after each green stage so a crash or container reclaim mid-run loses at
  most one stage, and the human can see incremental diffs.
- **Single-run lock (`lock: true`):** a `.temper/autonomy.lock` with a run-id prevents a
  concurrent `/temper` from corrupting the singleton `build-state.json`.
- **One-command abandon:** with `stop-before-commit: true` (default) the branch is never
  committed, so `git branch -D` discards the night. Documented in the report's footer; if
  `stop-before-commit: false`, the report prints the exact `git reset` to undo.

---

## 7. Unattended command execution (security)

Build/Check run Bash (test runners, linters) with **no human approval** during an
autonomous run — a real surface (e.g. a malicious dependency's test script). The fix is to
**reuse the harness's existing permission system, not invent an allowlist**:

- Autonomy runs under Claude Code's configured `settings.json` allow/deny permissions. A
  command that isn't already permitted **parks** for human approval instead of running.
- The report records every command executed, so the night is auditable.
- This is called out so `/security-review` has something concrete to assess rather than
  discovering silent unattended execution. No new mechanism — the platform already gates
  commands; autonomy just treats a denied/unpermitted command as a park signal.

---

## 8. Conservative fix policy under autonomy

Interactive "Fix all" includes low-severity findings. Applying those across many files
overnight is unreviewed churn. Under autonomy:

- `auto-fix-severity: [critical, high]` (default) — auto-apply only these; lower-severity
  findings are **listed in the report, not applied**.
- Loop budget per feedback type defers to `feedback.max-loops` (single source of truth);
  the global cap is `budget.max-total-loops`. There is no separate `autonomy.max-loops`.

---

## 9. Config block

```yaml
# ============================================================
# Autonomous Continuation
# Armed by a human at the PLAN GATE, never at invocation. /temper always
# runs Plan first and stops for human review; after approval the human may
# let the remaining stages run unattended. Default behavior is unchanged:
# with this block absent, the plan gate offers only the usual stage-by-stage
# continuation (byte-identical to v5.9.0).
# ============================================================
autonomy:
  enabled: true              # false => plan gate offers only stage-by-stage; no gate annotation
  default-choice: interactive # plan-gate continuation pre-highlighted: interactive | auto

  # --- Self-judgment safeguards (§4) ---
  conservative-bias: true    # uncertain proceed/park signal => park. Confidence reuses review.confidence-threshold.

  # --- Safety envelope ---
  stop-before-commit: true   # NEVER auto-commit/merge. Human is always the merge gate.
                             # Escape hatch (kept by design): set false to auto-commit a
                             # fully-clean run (acceptance checklist all green). Even then
                             # autonomy NEVER pushes or merges — push stays a human action.
  max-blast-radius: 15       # park (back to plan gate) if blast radius exceeds N files
  park-on-touch:
    - "**/auth/**"
    - "**/payment/**"
    - "**/billing/**"
  respect-escalation: true   # park on a models.escalate-on trigger (architecture-finding, correctness-risk)

  # --- Run budget, hard ceiling (§5) ---
  budget:
    max-total-loops: 4
    max-stages: 12
    max-wall-clock-min: 60

  # --- Fix policy under autonomy (§8) ---
  auto-fix-severity: [critical, high]   # per-type loop count defers to feedback.max-loops

  # --- Operational safety (§6) ---
  require-clean-tree: true
  checkpoint: wip-commit     # none | wip-commit
  lock: true

  # --- Handoff (§10) ---
  report: ".temper/autonomy-report.md"
  notify: push-on-park       # none | push-on-park (default) | push-on-finish
```

Command execution (§7) reuses the harness `settings.json` permissions — no autonomy keys.

**Graceful-degradation contract:** with the `autonomy` block absent or `enabled: false`,
the plan gate offers only the existing stage-by-stage continuation and no gate ever
auto-resolves — byte-identical to v5.9.0. Disabling autonomy never affects adaptive-depth,
cache, loops, or model routing. Autonomy does **not** read `adaptive-depth.floor` and is
not clamped by complexity tier.

---

## 10. Park artifact (morning handoff)

**A park is just the existing "Save for later" path plus one markdown file** — not a new
state machine. Two things happen:

1. **State is saved** exactly like "Save for later" — `build-state.json` with the parked
   `stage`/`next_stage` plus `run_mode: autonomous`. Resume is free: `/temper` lands back at
   the parked gate, interactively.
2. **One human-readable report is written** (`autonomy-report.md`). The few machine-readable
   fields `/temper:status` needs go into the existing `observability.json` (§11) — no
   separate JSON file.

`autonomy-report.md`:

```markdown
# Autonomy Report — {feature slug}

**Verdict:** SHIP-PENDING-COMMIT | PARKED-NEEDS-DECISION | BLOCKED | BUDGET-EXCEEDED
**Parked at:** {stage} gate     **Reason:** {one-line}
**Branch:** feature/{slug}   **Checkpoints:** {N wip commits}   **Finished:** {ISO ts}

## Acceptance checklist (all must hold for SHIP-PENDING-COMMIT)
- [x] all tasks complete (6/6)
- [x] review clean or auto-fixed (2 high fixed; 1 low deferred — see below)
- [x] check pass, coverage 86% ≥ 80%
- [x] all scenarios covered
- [x] eval aggregate 0.82 ≥ 0.75

## What ran
| Stage | Result | Auto-decision | Confidence | Loops |
|-------|--------|---------------|-----------|-------|
| Design| skipped (simple) | — | — | — |
| Build | 6/6 tasks, 5 tests | continued | 0.91 | — |
| Review| 2 high auto-fixed | fix → continued | 0.84 | 1 |
| Check | tests pass, cov 86% | continued | 0.95 | 1 (Check→Build) |
| Eval  | aggregate 0.82 | continued | 0.88 | — |
| Commit| — | PARKED (stop-before-commit) | — | — |

## Your next action
{Exact instruction + the file:line context that triggered any park.}

## Deferred (not applied autonomously)
- low-severity findings: {list}
- config suggestions (generated, not applied): {list}

## Audit
- commands executed: {list}     - budget used: 3/12 stages, 2/4 loops, 18 min
- abandon this run: `git branch -D feature/{slug}`
```

`SHIP-PENDING-COMMIT` requires the **explicit acceptance checklist above** to all hold —
otherwise the verdict is PARKED/BLOCKED. Verdict mapping to the article: SHIP-PENDING-COMMIT
≈ SHIP, PARKED-NEEDS-DECISION ≈ NEEDS WORK, BLOCKED ≈ BLOCK.

---

## 11. Observability

Additions to `observability.json`:

- `run_mode: "interactive" | "autonomous"` (per run).
- `gate_decisions: []` — `{ stage, decision, auto, confidence, reason, ts }` per gate.
- `park: { stage, reason, verdict, ts }` on park.
- `budget_used: { stages, loops, wall_clock_min, tokens }`.

`/temper:status` gains an **Autonomous runs** panel: last run mode, park point, gates
auto-resolved vs. parked, loop/budget consumption.

---

## 12. Files to change

| File | Change |
|------|--------|
| `.claude/temper.config` | Add the `autonomy:` block (§9), defaulted safe. |
| `.claude-plugin/reference/orchestrator-patterns.md` | New canonical **"Autonomous Continuation"** section: plan-gate arming, post-plan auto-resolve policy table (§3), self-judgment safeguards (§4), run budget (§5), operational safety (§6), command policy (§7), fix policy (§8), park report + acceptance checklist schema (§10), observability fields (§11), graceful-degradation contract. Shared home; `temper.md` references it (single-read contract). |
| `.claude/commands/temper.md` | (a) Plan gate: add the two-way continuation choice (§2) and arm `run_mode`; (b) each post-plan Stage Gate: when autonomous, evaluate the park policy and auto-resolve instead of calling `AskUserQuestion`; when interactive + `autonomy.enabled`, render the would-be decision as a gate annotation; (c) Commit stage: never auto-commit under autonomy — write report + park; (d) suppress teach-me/grill-me/walkthrough/config-prompts when `run_mode == autonomous`; (e) clean-start + lock + checkpoint hooks. |
| `.claude-plugin/reference/status.md` | Add the "Autonomous runs" panel (§11). |
| `.claude-plugin/reference/plan.md` | Note that the plan gate now offers the continuation choice. |
| `.claude/CLAUDE.md` | Document the plan-gate continuation choice and the autonomy config. |
| `README.md` | New "Autonomous Continuation" subsection: plan-gate-armed, safety envelope, parks before commit, any complexity. |
| `CHANGELOG.md` | Add a changelog entry for the feature (version is set separately via the release/version-bump process — not part of this change). |

**Out of scope (future):** extending autonomy to `/temper:fix` (shares
`orchestrator-patterns.md`, would inherit with a thin hook); a true background/scheduled
runner.

---

## 13. Test / verification plan

1. **Degradation:** `autonomy.enabled: false` (and block-absent) → plan gate offers only
   stage-by-stage; no gate auto-resolves; diff against v5.9.0 must be byte-identical.
2. **Plan always gates:** `/temper "x"` → Plan runs and **stops** at the plan gate; the
   "Autonomous" option is offered (pre-highlighted per `default-choice`) but requires an
   explicit click.
3. **Happy path:** approve plan → choose Autonomous → small change runs to the Commit gate,
   parks SHIP-PENDING-COMMIT with a fully-ticked acceptance checklist; `/temper` resume
   lands at Commit.
4. **Interactive annotation:** with `autonomy.enabled` and "Stage by stage" chosen, each
   gate shows the would-be autonomy decision + confidence; the human still clicks. With
   `autonomy.enabled: false`, no annotation appears (byte-identical to v5.9.0).
5. **Blast-radius park:** change touching `>max-blast-radius` files or a `park-on-touch`
   path → after plan approval, parks back at the plan gate / before build.
6. **Loop-then-park:** persistent test failure → Check→Build loops to the limit → circuit
   breaker trips → parks BLOCKED with the failing test in the report.
7. **Budget park:** force `max-stages`/`max-wall-clock-min` low → parks BUDGET-EXCEEDED with
   partial progress preserved.
8. **No-merge guarantee:** assert no autonomous path calls `git commit` (default) or
   `git push`/merge under any setting.
9. **Command permission:** a command not permitted by the harness `settings.json` → the
   stage parks for approval instead of executing it (no bespoke allowlist).
10. **Complex feature:** a complex-tier feature runs autonomously after plan approval (not
    clamped by adaptive-depth) and parks per the envelope, not the tier.
11. **Crash recovery:** kill the run mid-build with `checkpoint: wip-commit` → at most one
    stage of work lost; resume continues.
12. **Quality parity (dogfood):** `/temper:eval` comparison of autonomous vs. interactive
    outcomes on a small benchmark set, to validate the "same quality" claim rather than
    assert it.

---

## 14. Recommendation

Ship it **opt-in**, plan-gate-armed, default continuation `interactive`, with
`stop-before-commit: true`, the blast-radius envelope, the run budget, and clean-start +
checkpoints all on by default. Lead users in via the **interactive gate annotation** (watch
the autonomy policy propose calls while you still click each gate), then Autonomous. This
captures the overnight-batch value while keeping the human exactly where the human adds
value: the plan, high blast radius, and the merge. Keep teach-me/grill-me interactive-only —
they are the heart of Temper's "stay in command of the change" promise and have no meaning
unattended.
```
