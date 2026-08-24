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
(`temper gate`), never asserted by a model — and **[NEW]** the run's decision record
now survives the run: `temper state archive` writes verdicts, overrides (with the
approver's identity), and evidence counts into the spec dir as `gate-ledger.json`,
committed with the diff, so what the gates verified is part of the same audit chain
as what was asked and what was built.

## The loop, mapped

| Playbook stage | Playbook artifact | Temper |
|---|---|---|
| Plan | `intent.md` | Intent stage + gate **[NEW]** → `.temper/specs/{slug}/intent.md`, accepted by a human before anything else runs (`/temper:intent` for capture-only) |
| Design | `spec.md` | `intent.md` (criteria + scenarios) + `plan.md` + `design.md` — see [Deliberate divergences](#deliberate-divergences) |
| Build | `plan.md`, the diff | plan gate → `plan.md`/`tasks.md`; Build's RED→GREEN evidence |
| Test | tests + eval results | check gate: scenario-traced tests, coverage, live verification |
| Deploy | PR + review findings | review gate pre-commit; `temper gate review`'s exit code is the merge check under any CI |
| Maintain | incident → next intent | `temper bands` **[NEW]** → breach drafted as the next `intent.md` |

## Play-by-play

### Stage 1 — Plan

**Capture as intent.md.** The playbook wants anyone — not just engineers — able to
turn an idea into a committed, reviewable proto-spec, and the intent to be the
artifact the whole loop starts from. **[NEW]** Intent is now `/temper`'s own first
*gated stage*: a cheap pass states the Problem, success criteria, and constraints —
no exploration, no architecture — and a human accepts or corrects it at the intent
gate **before the expensive stages spend anything**. The reasoning is the playbook's
own: every downstream artifact is derived from the intent, so an intent correction at
this gate costs words, and the same correction after Plan costs the plan.
`temper gate intent` is the deterministic floor (Problem stated, ≥1 criterion, Status
header), and the commit gate requires an intent verdict whenever the artifact exists.
`/temper:intent` remains the capture-only entry (an idea, a ticket, a bands breach —
possibly from someone who will never run the build); its draft is exactly what the
pipeline's intent gate later presents. The lifecycle has named owners: `draft`
(capture or the Intent stage) → `accepted` (the human's Continue at the intent gate,
recorded as `Accepted-by:` and committed) → `completed` (the commit step).

### Stage 2 — Design

**Requirements and design spec.** The playbook's spec pass applies org policy while
writing and *flags areas of concern* for named owners. Temper's packs are that policy
(applied at plan/build/review/check), and **[NEW]** `design.md` now carries an
**Areas of Concern** section — always present, with an explicit `None flagged — why`
when nothing conflicts: a policy conflict is flagged while designing and resolved by
a human at the design gate, not discovered by Review after Build spent the tokens.
**[NEW]** The design gate is no longer vacuous: `temper gate design` mechanically
requires that section whenever `design.md` exists, and the commit gate requires a
design verdict whenever the design artifact does — so an unattended design→build
crossing can no longer skip the one check that stage owes. What Temper does not have
is the org-side flow around the artifact (product-owner review queues, Claude Design
mock handoff for front-end intents) — that lives outside a plugin.

### Stage 3 — Build

**Plan mode as the default starting point.** Aligned and mechanically enforced
beyond the playbook: the plan isn't just reviewed before code, `temper gate plan`
computes whether its artifacts exist, every criterion has a scenario, and
medium/complex changes documented a blast radius. Grill Me / walkthrough / HTML
review are the playbook's "interrogate the plan" made concrete. **[NEW]** Each
acceptance is a recorded, committed event: intent acceptance at the intent gate
(`Accepted-by:` + a committed `docs(intent)` commit), plan approval at the plan gate
(a committed `docs(plan)` commit — the commit gate passes artifact-only commits by
design), so the diff has a committed baseline from the moment build starts; at the
end, recorded deviations are written into plan.md as a `## Deviations` section in the
same commit as the code. One honest residual: nothing deterministically blocks
*source edits* before plan acceptance — that control is prompt-level (the hooks block
commits, protected paths, and regression-test edits, not arbitrary pre-acceptance
edits).

**Auto mode.** Aligned, more conservative than the playbook: Autonomous Continuation
is armed by a human at the plan gate only, checkpoints after each green stage, and
always parks before commit — it never commits, pushes, or merges. The playbook's
"auto-accept becomes the default for routine work" is a posture a project can adopt
by arming it per-run; the fence stays hardcoded.

**CLAUDE.md.** Aligned, with the feedback arc automated: Check writes
`config-suggestions.json` and offers each suggestion at the gate (accept → written
into CLAUDE.md/AGENTS.md), which is the playbook's "mistake made twice goes in
CLAUDE.md" with a mechanical carrier. Context hygiene (`docs/context-hygiene.md`)
covers the keep-it-lean rule. **[NEW]** Review now flags stale CLAUDE.md lines the
diff invalidates (queued through the same accept gate), and temper's own CLAUDE.md
carries the contributor day-one block the play asks for (test command, layout,
known-mistakes list).

**Skills as institutional knowledge.** Aligned: packs are versioned policy with
three-tier resolution (project → global → built-in), BLOCK/WARN/SUGGEST semantics,
and stage scoping (`phases:`). The playbook's layering rule — advisory control needs
a deterministic backstop — is Temper's founding design: packs advise, `temper gate` +
hooks enforce.

**Hooks as build-time guardrails.** Aligned: secrets, forbidden imports, the
in-agent commit gate, the stage-gate pair — all fail-open except the one detected
violation, exactly the playbook's fast-and-scoped rule. **[NEW]** Three additions
complete the playbook's own examples: `block-protected-paths.sh` freezes
`protect: paths:` globs at *edit* time in every mode (generated code, legacy
packages — previously enforced only at the autonomous commit gate);
`run-formatter.sh` runs the project's configured formatter after each edit so drift
never accumulates; and the forbidden-imports hook was fixed to read the edited file
from the hook's stdin payload (it previously read an env var hook events never set —
inert in-agent).

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
**[NEW]** `temper evidence run` closes the trust gap in the ledger itself: the CLI
executes the command and records the exit code it observed, so a PROVEN row can mean
machine-observed rather than agent-reported. One whole clause has no counterpart:
the play's **UI feedback loop** (screenshot-vs-mock iteration for front-end work) —
temper's verification is tests, coverage, and scenarios only.

**Continuous evals in CI.** Aligned in kind for Temper itself, honest about scale:
seeded-defect fixtures run headlessly through the real pipeline, asserting the gate
*would have mechanically blocked* (answer keys stripped, transcript matching
distrusted) — a stronger pass bar than the play's — but the suite is 4 cases against
the play's 20–50, and the PR job runs one smoke fixture (it skips cleanly without
the API secret, so it cannot hard-gate merges). **[NEW]** The suite now fires on the
*full* agent-configuration surface (packs, hooks, templates), not just prompts.
Open: per-pack fixtures, model/CLI pinning, and scaffolding an eval harness for a
*user project's* own agent config — see [Remaining gaps](#remaining-gaps).

### Stage 5 — Deploy

**AI in the PR review loop.** Temper's review runs pre-commit — earlier than the
playbook's PR review, with confidence scoring, review memory, intent validation.
**[NEW]** Two bridges to the review loop, both host-agnostic: `reference/review.md`
reads a repo-root `REVIEW.md` as org review policy (passes, Important-vs-Nit, nit
caps, do-not-report — which can re-aim the review but never lower the gate), and the
review is runnable headlessly under **any** CI with `temper gate review`'s exit code
as the merge check — the deterministic verdict as the machine-readable tally
(`examples/workflow/README.md` gives the command contract; temper deliberately ships
no CI-platform files). Branch/merge protection and a human code owner still own
approval; @claude-style comment loops remain the host platform's feature — Temper
composes with them rather than reimplementing them.

**Hooks as approval gates.** Temper's fence deliberately ends at `git commit`
(see divergences), and its commit gate is already an approval gate: a human override
is recorded, never erased. **[NEW]** The separation-of-duties seam is now enforced at
its weakest point: every override entry records *who* approved (`by:` from git
identity), and `confirm-override.sh` emits the ASK permission tier for any
`temper override` command — a deterministic human click between an agent and the one
command that clears a FAIL gate. **[NEW]** For past-the-fence release gating,
`examples/hooks/production-gate.sh` + `packs/hooks/rules.md` document the
allow/ask/block pattern with the two placement rules: approval gates at the release
boundary only (a human prompt mid-build puts a person back on every parallel
session's critical path), and non-negotiable gates in managed settings, not the repo.

**CI/CD integration.** The plugin runs headlessly (`claude -p "/temper:temper ..."` —
the eval harness is the existence proof), and its whole automation surface is
**commands and exit codes, deliberately host-agnostic**: the same wiring works under
GitHub Actions, GitLab CI, Jenkins, or plain cron, and temper ships no
platform-specific pipeline files (`examples/workflow/README.md` documents the
contract). The playbook's pattern still holds wherever you wire it: agent work
arrives through your host's review flow, detection steps spend no tokens, and nothing
the agent does can pass the production gate. MCP-scoped deploy tools and rollback
rehearsal are a project's pipeline concern.

### Stage 6 — Maintain

**Closing the loop.** This was Temper's largest gap — `/temper:status` was a
dashboard with, as its own doc said, "no separate alerting system". **[NEW]**
`temper bands`: a deterministic control-band check (rolling mean ± k·sigma + a
same-side-run drift rule) over the metric histories, with the response tiered in
version-controlled config — 1σ logs, 2σ diagnoses, 3σ proposes — and the proposal is
exactly the playbook's move: the breach is drafted as a Stage-1 `intent.md`
(evidence verbatim, criteria with `Validate: metric`) that rides the ordinary
pipeline through every gate. **[NEW]** Ingestion is CLI-owned and open-ended:
`temper metrics append <series> <value>` feeds any series — the pipeline's own
(coverage, tests, lint) or external production metrics (CI failure rate, post-deploy
5xx appended by a pipeline step) — and bands watches any appended series by name.
The trigger layer is **any scheduler you already run** (cron, a pipeline schedule):
`temper bands` is stateless and token-free until a breach, exits 1 when one exists,
and the breach is drafted into the ordinary pipeline — the loop begins and ends with
no one starting it, and lands in the review gate, never around it. Dismissals tune
the bands.

**Claude on call (Claude Tag).** Channel-resident incident response is a platform
capability, out of scope for a plugin — but the plugin-shaped half is now in:
**[NEW]** `/temper:fix` writes each incident to a committed `.temper/lessons.md`
(root cause, trigger, fix, regression test, the generalized failure shape) and every
future RCA *reads it first* — the playbook's "post-mortem to a version-controlled
lessons file that future investigations can read", verbatim. An incident write-up
dropped into `/temper:intent` (or a bands breach) enters the same loop.

## Deliberate divergences

These are design decisions, not gaps — each traded the playbook's letter for its
intent:

1. **No `spec.md`.** `reference/plan.md`'s hard rule: exactly three artifacts.
   Temper folds requirements (criteria with `Validate:` types) and behavior
   (Gherkin scenarios) into `intent.md`, architecture into `plan.md`/`design.md`.
   The playbook's intent→spec pair is Temper's intent(draft)→intent(accepted) +
   design — same audit chain, fewer files for a gate to check.
2. **Scenarios after intent, from the measured blast radius.** The pipeline now runs
   the playbook's literal order — intent (gated) → plan — but *within* Plan, temper
   still derives BDD scenarios from the measured blast radius before committing to
   an architecture, so the file list is justified by behavior: its structural
   defense against over-engineering. The intent gate reviews the WHY cheaply; the
   plan gate reviews the WHAT/HOW it was derived into.
3. **The fence ends at commit.** Temper never pushes, merges, or deploys — the
   strongest possible reading of "the agent may act up to the production gate and
   cannot pass it." Deploy-stage controls are documented command contracts and an
   example hook for the project's own pipeline, not plugin behavior.
4. **Review runs pre-commit; PR-time review is your CI's one-liner.** Catching
   findings before the commit exists is cheaper than at the PR; wiring
   `temper gate review` as a pipeline check adds the org-visible audit record
   without replacing the local pass.
5. **No CI-platform files, on purpose.** Temper's automation surface is commands
   and exit codes (`temper bands`, `temper gate review`, `temper metrics append`),
   equally at home under GitHub Actions, GitLab CI, Jenkins, or cron — shipping any
   one host's workflow files would couple a host-agnostic spine to a vendor.

## Remaining gaps

Honest list, in rough adoption order:

- **Commit-triggered stage handover** — inside a run, handover is state-file-driven
  in one session; a committed `Status: draft` intent triggers nothing by itself. The
  artifact chain + artifact-only commits make the trigger buildable in any host's
  automation (fire headless `/temper` when an accepted intent lands), but temper
  ships no such wiring — by the no-CI-platform-files rule, that hookup is the
  project's.
- **Org flow around intent** — product-owner review queues, an "intent home" for
  non-git contributors, Claude Design mock handoff for front-end intents. Route:
  repository conventions + connectors; the artifact shape is ready for it.
- **Review-comment loops** — host-platform features (comment-driven fixes,
  babysit-to-merge) Temper composes with; human review comments never feed
  review-memory today.
- **Server-side gate verification** — the pre-commit hook is per-clone, so
  `git commit --no-verify` bypasses the spine locally; re-verifying the gates where
  your host's merge protection lives (e.g. from the committed `gate-ledger.json`)
  is wiring the project adds, not shipped.
- **Eval scale and reach** — 4 self-eval cases vs the play's 20–50; no per-pack
  seeded fixtures; no model/CLI pinning; nothing scaffolds an eval harness for a
  user project's own agent config (their CLAUDE.md, their packs).
- **Parallel-session execution** — tasks.md computes `[PARALLEL]` groups and the
  worktree pattern is documented, but nothing spawns per-worktree sessions from
  those groups; stage agents carry no `tools:` restrictions (report-only roles are
  prompt-enforced).
- **UI feedback loop** — no screenshot-vs-mock iteration path for front-end work.
- **Managed-settings distribution** — the enterprise guide covers fork-and-own;
  per-org managed settings for non-negotiable hooks is documented but not tooled.

## Adoption order (the playbook's arrows, in Temper commands)

1. `/temper "…"` → sets itself up on first run (config, scaffold, commit gate) and
   runs the intent-gated pipeline.
2. Packs + hooks pack → skills-with-deterministic-backstops.
3. `/temper:intent` → capture-first flow; commit the spec artifacts.
4. Wire `temper gate review` into whatever CI you run → the review loop, org-visible.
5. `autonomy:` block → longer unattended arcs, parked before commit.
6. `bands:` + `temper bands` on any scheduler → the loop closes itself.
