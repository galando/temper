---
title: AI-Native SDLC Alignment
nav_order: 6
---

# Temper and the AI-Native SDLC

A play-by-play map of Temper against Anthropic's
[AI-Native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook)
(Aug 2026): where Temper already implements a play, where this release closed a gap,
what stays deliberately different, and what remains open. Items marked **[NEW]**
landed with this alignment pass.

The playbook's spine is a **loop of committed artifacts**: each stage ends by
committing one (`intent.md` → `spec.md` → `plan.md` → diff + tests → PR with findings
→ incident record → the next `intent.md`), the commit triggers the next stage, and the
chain of commits is the audit trail. Temper's spine is the same loop with one
sharpening: every gate between arcs is **computed by a CLI from an evidence ledger**
(`temper gate`), never asserted by a model.

## The loop, mapped

| Playbook stage | Playbook artifact | Temper |
|---|---|---|
| Plan | `intent.md` | `/temper:intent` **[NEW]** → `.temper/specs/{slug}/intent.md`, `Status: draft` |
| Design | `spec.md` | `intent.md` (criteria + scenarios) + `plan.md` + `design.md` — see [Deliberate divergences](#deliberate-divergences) |
| Build | `plan.md`, the diff | plan gate → `plan.md`/`tasks.md`; Build's RED→GREEN evidence |
| Test | tests + eval results | check gate: scenario-traced tests, coverage, live verification |
| Deploy | PR + review findings | review gate pre-commit; `examples/workflow/temper-review.yml` **[NEW]** for the PR loop |
| Maintain | incident → next intent | `temper bands` **[NEW]** → breach drafted as the next `intent.md` |

## Play-by-play

### Stage 1 — Plan

**Capture as intent.md.** The playbook wants anyone — not just engineers — able to
turn an idea into a committed, reviewable proto-spec. Temper wrote `intent.md` only
inside the engineer-driven Plan pass. **[NEW]** `/temper:intent` captures an idea as a
draft with author, status, and Open Questions; committing it puts the author,
timestamp, and revision history in git from the moment the idea is real. The
lifecycle has named owners: `draft` (capture) → `accepted` (a human approving the
plan gate) → `completed` (the commit step). Plan builds on a draft, never overwrites
it.

### Stage 2 — Design

**Requirements and design spec.** The playbook's spec pass applies org policy while
writing and *flags areas of concern* for named owners. Temper's packs are that policy
(applied at plan/build/review/check), and **[NEW]** `design.md` now carries an
**Areas of Concern** section: a policy conflict is flagged while designing and
resolved by a human at the design gate — not discovered by Review after Build spent
the tokens. What Temper does not have is the org-side flow around the artifact
(product-owner review queues, Claude Design mocks) — that lives outside a plugin.

### Stage 3 — Build

**Plan mode as the default starting point.** Aligned and mechanically enforced
beyond the playbook: the plan isn't just reviewed before code, `temper gate plan`
computes whether its artifacts exist, every criterion has a scenario, and
medium/complex changes documented a blast radius. Grill Me / walkthrough / HTML
review are the playbook's "interrogate the plan" made concrete.

**Auto mode.** Aligned, more conservative than the playbook: Autonomous Continuation
is armed by a human at the plan gate only, checkpoints after each green stage, and
always parks before commit — it never commits, pushes, or merges. The playbook's
"auto-accept becomes the default for routine work" is a posture a project can adopt
by arming it per-run; the fence stays hardcoded.

**CLAUDE.md.** Aligned, with the feedback arc automated: Check writes
`config-suggestions.json` and offers each suggestion at the gate (accept → written
into CLAUDE.md/AGENTS.md), which is the playbook's "mistake made twice goes in
CLAUDE.md" with a mechanical carrier. Context hygiene (`docs/context-hygiene.md`)
covers the keep-it-lean rule.

**Skills as institutional knowledge.** Aligned: packs are versioned policy with
three-tier resolution (project → global → built-in), BLOCK/WARN/SUGGEST semantics,
and stage scoping (`phases:`). The playbook's layering rule — advisory control needs
a deterministic backstop — is Temper's founding design: packs advise, `temper gate` +
hooks enforce.

**Hooks as build-time guardrails.** Aligned: secrets, forbidden imports, the
in-agent commit gate, the stage-gate pair — all fail-open except the one detected
violation, exactly the playbook's fast-and-scoped rule.

**Parallel sessions and subagents.** Subagents were already core (review fan-out,
Explore RCA, depth budgets). **[NEW]** `docs/getting-started.md` documents the
worktree pattern: `.temper/` state is per-checkout, so parallel sessions cannot
collide, and the controls travel with the repo.

### Stage 4 — Test

**Give Claude a feedback loop.** Aligned and beyond: the loop is evidence-carrying
(RED-then-GREEN rows the build gate requires), scenarios are executed individually
(live verification), and the review stage's mutation spot-check *proves* a test
catches the bug rather than assuming it. **[NEW]** The playbook's protect-the-loop
hook now exists: `protect-regression-test.sh` blocks the fixing agent from editing
the regression test it recorded at RED — lifting the shield is a human's state edit.

**Continuous evals in CI.** Aligned for Temper itself: seeded-defect fixtures run
headlessly through the real pipeline, asserting the gate would have blocked — and
**[NEW]** the suite now fires on the *full* agent-configuration surface (packs,
hooks, templates), not just prompts. Open: Temper doesn't yet scaffold an eval
harness for a *user project's* own agent config (their CLAUDE.md, their packs) — see
[Remaining gaps](#remaining-gaps).

### Stage 5 — Deploy

**AI in the PR review loop.** Temper's review runs pre-commit — earlier than the
playbook's PR review, with confidence scoring, review memory, intent validation.
**[NEW]** Two bridges to the PR loop: `reference/review.md` reads a repo-root
`REVIEW.md` as org review policy (passes, Important-vs-Nit, nit caps,
do-not-report — which can re-aim the review but never lower the gate), and
`examples/workflow/temper-review.yml` runs the review headlessly on PRs with the
merge check being `temper gate review` — the deterministic verdict as the
machine-readable tally, branch protection and a human code owner still owning
approval. The @claude comment-fix loop and babysit-to-merge remain Claude Code
platform features, not plugin surface — Temper composes with them rather than
reimplementing them.

**Hooks as approval gates.** Temper's fence deliberately ends at `git commit`
(see divergences), and its commit gate is already an approval gate: a human override
is recorded, never erased. **[NEW]** For past-the-fence release gating,
`examples/hooks/production-gate.sh` + `packs/hooks/rules.md` document the
allow/ask/block pattern with the two placement rules: approval gates at the release
boundary only (a human prompt mid-build puts a person back on every parallel
session's critical path), and non-negotiable gates in managed settings, not the repo.

**CI/CD integration.** The plugin runs headlessly (`claude -p "/temper:temper ..."` —
the eval harness is the existence proof). **[NEW]** The two workflow templates give
projects the playbook's pattern: agent work arrives as a PR through branch
protection, detection steps spend no tokens, and nothing the agent does can pass the
production gate. MCP-scoped deploy tools and rollback rehearsal are a project's
pipeline concern; the templates leave that boundary explicit.

### Stage 6 — Maintain

**Closing the loop.** This was Temper's largest gap — `/temper:status` was a
dashboard with, as its own doc said, "no separate alerting system". **[NEW]**
`temper bands`: a deterministic control-band check (rolling mean ± k·sigma + a
same-side-run drift rule) over the metric histories Temper already accumulates,
with the response tiered in version-controlled config — 1σ logs, 2σ diagnoses, 3σ
proposes — and the proposal is exactly the playbook's move: the breach is drafted as
a Stage-1 `intent.md` (evidence verbatim, criteria with `Validate: metric`) that
rides the ordinary pipeline through every gate. `examples/workflow/temper-bands.yml`
is the trigger layer: scheduled, stateless, token-free until a breach — the loop
begins and ends with no one starting it, and lands in the review gate, never around
it. Dismissals tune the bands.

**Claude on call (Claude Tag).** Out of scope for a plugin: channel-resident
incident response is a platform capability. The seam is designed, though — an
incident write-up dropped into `/temper:intent` (or a bands breach) enters the same
loop, and the post-mortem's regression test is the fix flow's existing requirement.

## Deliberate divergences

These are design decisions, not gaps — each traded the playbook's letter for its
intent:

1. **No `spec.md`.** `reference/plan.md`'s hard rule: exactly three artifacts.
   Temper folds requirements (criteria with `Validate:` types) and behavior
   (Gherkin scenarios) into `intent.md`, architecture into `plan.md`/`design.md`.
   The playbook's intent→spec pair is Temper's intent(draft)→intent(accepted) +
   design — same audit chain, fewer files for a gate to check.
2. **Scenarios before architecture.** The playbook orders intent → spec → plan.
   Temper derives BDD scenarios from the *measured* blast radius before committing
   to an architecture, so the file list is justified by behavior — its structural
   defense against over-engineering. The order differs; the "design review before
   any code" control is the same, enforced by the plan gate.
3. **The fence ends at commit.** Temper never pushes, merges, or deploys — the
   strongest possible reading of "the agent may act up to the production gate and
   cannot pass it." Deploy-stage controls are documented patterns (templates,
   example hooks) for the project's own pipeline, not plugin behavior.
4. **Review runs pre-commit, PR review is a bridge.** Catching findings before the
   commit exists is cheaper than at the PR; the CI template adds the PR-time pass
   for the org-visible audit record rather than replacing the local one.

## Remaining gaps

Honest list, in adoption order:

- **Org flow around intent** — product-owner review queues, an "intent home" for
  non-git contributors, Claude Design mock handoff. Route: repository conventions +
  claude.ai connectors; the artifact shape is ready for it.
- **@claude fix loop / babysit-to-merge** — platform features Temper composes with;
  a `/temper:babysit` sweeping unresolved comments + red checks through the existing
  gates would be the native version.
- **Project-side agent evals** — `/temper` could scaffold a starter eval (prompt +
  expected gate outcome) per shipped feature, giving user projects the
  incident-gets-an-eval rule Temper applies to itself.
- **Richer bands sources** — today `temper bands` watches Temper's own metric
  histories (coverage, test count); production metrics (5xx rates, cycle time)
  arrive by the project appending to those arrays or a `bands.metrics` extension.
- **Managed-settings distribution** — the enterprise guide covers fork-and-own;
  per-org managed settings for non-negotiable hooks is documented but not tooled.

## Adoption order (the playbook's arrows, in Temper commands)

1. `/temper:init` → config, `.temper/` scaffold, the pre-commit gate.
2. `/temper` → plan-gated pipeline (plan mode + CLAUDE.md + feedback loop plays).
3. Packs + hooks pack → skills-with-deterministic-backstops.
4. `/temper:intent` → capture-first flow; commit the spec artifacts.
5. `examples/workflow/temper-review.yml` → the PR review loop.
6. `autonomy:` block → longer unattended arcs, parked before commit.
7. `bands:` + `examples/workflow/temper-bands.yml` → the loop closes itself.
