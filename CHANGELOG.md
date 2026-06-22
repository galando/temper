# Changelog

All notable changes to Temper are documented here. The plugin version lives in
`.claude-plugin/plugin.json`.

## v5.8.0 — New Features

Explain implementation-approach choices in plans (#59)

## v5.7.0 — Teach Me: comprehension companion across the teaching gates

Adds a sixth capability, **Teach Me** — a Socratic *teaching* companion (the
counterpart to Grill Me's *challenging*) that keeps the human engaged with every
change Temper makes. Where the walkthrough gives a one-shot tour and Grill Me
attacks assumptions, Teach Me confirms the user actually *understands* — phase by
phase — before the pipeline moves on. It maps to the three comprehension pillars:
**Problem** (Plan), **Solution** (Design, Build), **Impact** (Check, Eval).

### New skill
- `.claude/skills/teach-me/SKILL.md`: probe (user restates first) → teach the gaps
  incrementally with real code → quiz via `AskUserQuestion` (correct-answer
  position varied; answer never revealed until submit) → confirm mastery before
  ticking each item. Honors `eli5`/`eli14`/`elii` depth requests. Maintains a
  running `{spec_path}/comprehension.md` checklist organized under three pillars —
  **Problem (why)**, **Solution (what & how)**, **Impact** — that accumulates
  across phases and is never reset.
- Registered in `.claude-plugin/plugin.json` `skills[]`.

### Wired into the teaching stage gates
- `.claude/commands/temper.md`: a shared **"Teach Me (Comprehension Companion)"**
  handler plus a `Teach Me (Quiz me until I get it)` gate option on five gates
  (Plan, Design, Build, Check, Eval). Each phase teaches its own artifacts
  (Plan→intent/plan/tasks, Design→design.md, Build→the diff, Check→validation+coverage,
  Eval→score table) and returns to the same gate. Teach Me NEVER advances or blocks
  the pipeline — it only adds understanding. **Review is intentionally excluded** —
  its substance (the diff and its rationale) is already taught at Build, and its
  findings are usually minor or auto-fixed. The option label is distinct from the
  passive "Walk through … step by step" walkthrough to signal its active, quiz-driven nature.

### Config & docs
- New capability flag `capabilities.teach-me: true` in `.claude/temper.config`
  (default-on; graceful degradation — set `false` to hide the option everywhere).
- `temper-core` capabilities table gains a **Teach Me / Plan, Design, Build, Check, Eval** row.
- Version bump to `5.7.0` (`plugin.json`, `.claude/CLAUDE.md`).

> Cursor parity remains frozen at v5.1 (see v5.2.1 platform strategy) — this
> capability is Claude Code only and is not forward-ported to `.cursor/`.

## v5.6.0 — Phase 2: Harness Economics & Observability

Turns the paper's economic argument (high CapEx / low OpEx, intelligent model routing,
auditable observability) into measured, enforced harness behavior. Routing stops being
advisory; observability stops being self-estimated.

### Deliverable 1 — Intelligent model routing (enforced)
- New `models` block in `.claude/temper.config`: `enabled`, `tiers`
  (`tier-frontier` → opus, `tier-standard` → sonnet, `tier-fast` → haiku), `routing`
  per stage (plan/design→frontier, build→standard, review/check/eval→fast),
  `escalate-on` (`architecture-finding`, `correctness-risk`), `respect-user-override`,
  and `drift-threshold` (std-dev cutoff, default 2).
- `.claude/commands/temper.md`: each of the 6 stage Agent launches carries a `[MODEL:]`
  delta resolved from `models.routing.{stage}`. New "Model Routing Resolution" section:
  first-match-wins — disabled ⇒ no `model` param (v5.5.0 byte-identical), then
  user-override, then routing. Review escalates `escalate-on` findings from fast to
  frontier, reusing `review.md`'s confidence-scoring path.
- **Graceful degradation contract:** `models.enabled: false`/absent ⇒ no `model` param
  emitted, session model inherited — Scenario 1 enforces this.

### Deliverable 2 — Measured telemetry (not estimated)
- `.temper/observability.json` bumps to `version: 2` (schema documented in
  `reference/orchestrator-patterns.md`): per-stage `model_tier`, `model_source`,
  `tokens{input,output,source}`, `latency_ms`, `tool_calls`, `cost_usd`, `retries`,
  `eval_score`, plus `totals`. Extends the G-5 (v5.3.0) source-sibling rule to EVERY
  numeric leaf (`measured` | `estimated` | `user-override` | `pricing`).
- New `.claude-plugin/reference/pricing.md`: advisory, version-dated tier →
  `{input_per_1m, output_per_1m}` table; `cost_usd = (in/1e6)*in_price + (out/1e6)*out_price`.

### Deliverable 3 — Drift detection
- `.temper/metrics.json` extended (additive) with `stage_baseline` (rolling per-stage
  history) and `drift_flags[]`. A run deviating > `drift-threshold` std-dev from its
  baseline is flagged at severity `SUGGEST`. Drift flags NEVER auto-block a stage gate;
  surfaced in `/temper:status`.

### Deliverable 4 — Economics panel in `/temper:status`
- New ECONOMICS panel in `.claude/commands/status.md` + `reference/status.md`:
  per-stage cost/latency/tier (last run), rolling averages, eval-score trend, drift
  flags, and a CapEx vs OpEx summary. Absent/v1 observability ⇒ "No observability
  data yet" (graceful, no error). Source flags surfaced alongside every numeric.

### Cross-cutting
- `.claude-plugin/reference/tokenomics.md`: advisory "prefer Sonnet" replaced with a
  pointer to the enforced `models.routing`, so guidance and behavior agree.
- New `scripts/validate-phase2.sh`: one-shot bash+python mechanical verification for
  all 9 Phase 2 scenarios (config schema, routing conditionals, v2 source provenance,
  pricing parseable, drift flag, status panels, version lockstep, cursor freeze).
- `.cursor/` regenerated via `scripts/generate-cursor.sh`; FROZEN at the v5.1 feature
  set (no v5.6 routing/observability features leaked into frozen cursor commands).
- Version lockstep: `plugin.json` == `.cursor/VERSION` == `CLAUDE.md` == `temper.md` == 5.6.0.

## Unreleased — Eval Score-Table Readability

Improvements to the human-gate readability of the Eval stage score table (extends the v5.5.0
eval feature, same phase). No version bump — ships under v5.5.0.

- **Group dimensions by category:** every rubric dimension now carries a `category`
  (`artifact` = judges the produced code/output → "fix the code"; `process` = judges the run →
  "fix the run"). Score table rows are grouped under `ARTIFACT — fix the code` and
  `PROCESS — fix the run` headers instead of a flat, equally-weighted list. Added to
  `templates/evalset.json`, the rubric dimension table in `reference/eval.md`, and the
  `eval-judge` skill (with name-based defaults when a rubric omits `category`).
- **Recommended action per low row:** each row below `pass_threshold` is annotated with what to
  do — `→ Re-run (code defect)` (artifact-low), `→ Re-run (block-on failed)` (any block-on dim
  low), or `→ accept (process noise)` (process-low, not block-on). Actions computed by the
  `eval-judge` skill and stored in `recommended_actions`. Codified in `reference/eval.md` →
  "Reading the Score Table".
- **Surface partial aggregates loudly:** when any dimension is `"unscored"`, the aggregate is
  computed over the **scored subset only** (weights re-normalized), recorded as
  `aggregate_basis: "scored"` + `scored_weight`, and the table prints a caveat naming the count
  and the unscored dimensions — a 0.80 that's half-unscored no longer reads as a full 0.80.
- **"How to read this" legend:** a one-line legend prints above the table on every eval run
  ("0–1 scale, {pass_threshold} to pass. Low ARTIFACT-scores mean fix the code; low
  PROCESS-scores mean the run was messy.").
- **Schema additions:** `category` per dimension in the rubric + results; `aggregate_basis`,
  `scored_weight`, `recommended_actions` in `results-{ts}.json` and `eval-context.json`.
- **Surfaces kept in sync:** `.claude/commands/temper.md` + `.cursor/commands/temper.md` (Eval
  Summary Format + agent return contract), `.claude/commands/eval.md` +
  `.cursor/commands/temper-eval.md`, `reference/eval.md`, `reference/orchestrator-patterns.md`,
  `eval-judge` SKILL.md.

## v5.5.0 — Phase 1 Verification

Behavioral verification layer + deterministic safety net (PR #49,
`docs/plans/phase-1-verification.md`).

- **D1 — Eval command + skill:** `/temper:eval` command (default output eval, `--create`
  scaffold, `--trajectory` mode), `eval-judge` skill (LM-judge per-dimension scoring on a
  cheaper model tier with deterministic fallback), `reference/eval.md` methodology,
  `templates/evalset.json` schema (5 default rubric dimensions + weights + pass_threshold).
- **D2 — Eval stage in `/temper`:** new "Stage 4.5: Eval" between Check and commit (isolated
  Agent subprocess, score table + `eval-context.json`, gate {Continue, Re-run, View results,
  Save-for-later}, Eval→Build feedback loop). `eval-context.json` schema in
  `orchestrator-patterns.md`. Default-on config with one-line skip when evalset/config absent.
- **D3 — Plan-time evalsets:** Plan stage emits a draft `evalset.json` from intent.md scenarios;
  plan summary box shows an `EVALS: {N}` line.
- **D4 — Deterministic hooks pack:** `packs/hooks/` with `block-secrets.sh`,
  `block-forbidden-imports.sh`, `verify-tests-ran.sh` — deterministic, fail-closed on detected
  secrets, fail-open (no-op) on missing scripts/state. Install via `/temper:pack enable hooks`
  (merges `settings.hooks.json` into settings.json through the `update-config` skill).
- **Cross-cutting:** `eval` + `capabilities.evals` config (default-on, graceful degradation);
  `validate-plugin.sh` assertions for every new file; Cursor parity via `generate-cursor.sh`
  (`temper-eval.md`, `temper-ref-eval.mdc`, `temper-pack-hooks.mdc`); version bump to 5.5.0.

**Graceful degradation contract:** every new capability no-ops cleanly when its config flag,
supporting files, or judge model are absent — never hard-errors.

## v5.4.0 — CI / Tooling

Auto-generate concise CHANGELOG notes from commits (#53); add release-bump.yml — one-button version bump workflow (#51); phase 0 implementation gaps — close G-1..G-6 (v5.3.0) (#50)

## v5.3.0 — Phase 0 Implementation Gaps (Promise vs. Reality)

Closes the six drift findings from `docs/plans/implementation-gaps.md` (PR #49).
The plugin now does what its own docs/config/skills promise, before Phase 1
(verification) extends it.

- **G-1 — Single version source of truth:** `scripts/version-bump.sh` now
  rewrites every stamp (plugin.json, `.cursor/VERSION`, `.claude/CLAUDE.md`,
  `.claude/commands/temper.md` header). `scripts/validate-plugin.sh` gained
  three assertions so stamp drift fails CI. The `temper.md` header (v4.4.1)
  is no longer stale.
- **G-2 — Regenerable Cursor export:** new `scripts/generate-cursor.sh`
  transforms `.claude/` (packs, skills, capabilities, reference docs, commands)
  into `.cursor/` rules + commands as a pure, idempotent, offline function.
  `install-cursor.sh` now delegates to the generator inside a repo checkout.
  Cursor remains **frozen at the v5.1 feature set** — regeneration makes parity
  honest and consistent, not feature-advancing. `.cursor/` was regenerated.
- **G-3 — Phase-scoped pack loading wired in:** `review`, `build`, `check`,
  `plan`, and `design` stage docs now load only packs whose `phases` is `all`
  or contains the current stage, per the `pack.md` contract. The promised
  token/scoping benefit is now realized at the point of use.
- **G-4 — Manifest cache consumed:** the same block consults
  `.temper/pack-manifest.json` (rebuilt if stale) before loading packs,
  closing both G-3 and G-4 in one coherent change. `temper-core/SKILL.md`
  claim updated to match reality.
- **G-5 — Honest observability labels:** every value written to
  `.temper/observability.json` now carries a `source: measured|estimated`
  field; the misleading `track-tokens` config comment is clarified. Real
  measured telemetry is Phase 2 scope.
- **G-6 — Learning flywheel fixture:** redacted
  `.temper/fixtures/learning.sample.json` proves the adaptive-learning loop
  shape. Live dogfooding (enough review cycles to promote a rule) is deferred
  to a follow-up session; G-6 was non-blocking.

**Validation:** `validate-plugin.sh` 16/0, `validate-docs.sh` 6/0,
`validate-readme.sh` 5/0, `generate-cursor.sh` idempotent.

## v5.2.1 — Growth Plan & Benchmark Improvements

- **README rewrite:** 829 → 172 lines (79% reduction). First screen: problem → catch story → quick start.
- **CI quality gates:** 4 offline-safe validation scripts + GitHub Actions workflow (quality.yml).
- **Landing page refresh:** Open Graph tags, JSON-LD, evidence section, OCR card. All parity claims removed per §1 platform strategy.
- **Evidence documents:** Benchmark methodology, dogfooding case study, feature comparison matrix.
- **Benchmark results:** Temper catches 12/12 bug patterns in playground testing vs vanilla Claude Code's 8/12.
- **Race condition detection:** Performance pack now flags non-atomic mutations on shared state in concurrent contexts.
- **Middleware stack completeness:** Review checks for error middleware, CORS, helmet in app entry point.
- **Community infrastructure:** 4 issue templates, CONTRIBUTING.md and getting-started.md updates.
- **Playground repo:** [galando/temper-playground](https://github.com/galando/temper-playground) with 4 intentional flaws for demo.
- **Platform strategy:** Cursor support frozen at v5.1 feature set. New capabilities ship Claude Code-first.

## v5.2.0 — OCR Integration (External Review Engine)

- **open-code-review integration:** `ocr` CLI is now an optional external review
  engine inside `/temper:review`. When installed and configured, OCR takes over
  line-level defect detection (NPEs, injections, thread-safety). Temper keeps
  intent validation, security analysis, architecture depth, and review memory.
- **Auto-detection:** `ocr` is probed during Step 1 and enabled automatically
  when available (`tools.ocr.mode: auto`, the default). Missing OCR is silent
  in auto mode; blocks in require mode with install instructions.
- **Step 2.5:** New pipeline step runs OCR between subagent launch and intent
  validation. JSON output parsed, severity-mapped, labeled `[OCR]`, and
  deduplicated against Temper findings. Cross-validated findings are labeled
  `[OCR+TEMPER]` with boosted confidence (min(0.95, max + 0.15)).
- **Subagent takeover:** When `tools.ocr.replace-defect-subagent: true` (default),
  Temper subagents drop generic defect-hunting sections. OCR owns line-level
  defects; Temper keeps pack rules, security, AI-code detection, architecture.
- **Config block:** `tools.ocr` in `.claude/temper.config` with mode, timeout,
  concurrency, and extra-args settings.
- **Status dashboard:** `/temper:status` shows OCR availability and accept rate
  under renamed "EXTERNAL TOOLS" section (was "MCP TOOLS").
- **Evidence labels:** New `[OCR]` and `[OCR+TEMPER]` labels in review output.
- **Documentation:** Updated recommended-setup.md, README.md, commands.md, and
  schema fixture at `docs/plans/fixtures/`.
- **No breaking changes.** All changes are additive. Zero-config when OCR is not
  installed — review runs identically to v5.1.0.

## v5.1.0 — Nested Subagent Support

- **Nested agents config:** Added `agents` block to `.claude/temper.config` with
  `nested`, `max-depth`, `parallel-width`, and `on-budget-exhausted` settings.
  Defaults to `max-depth: 4`, `parallel-width: 3`, graceful inline fallback.
- **Depth budget governance:** Updated orchestrator-patterns.md to pass
  `depth_remaining` to stage agents. Stages check budget before spawning:
  `depth_remaining > 1` → spawn, `depth_remaining <= 1` → run inline.
- **Depth-2 helpers enabled:** Review parallel subagents, Plan Explore auto-prime,
  Fix Explore RCA, and architecture-depth Explore now work in the composed
  `/temper` pipeline (previously degraded when run through orchestrator).
- **Graceful degradation:** Depth exhaustion falls back to inline work instead
  of hard failure. Deterministic local budgeting; no global tree state needed.
- **ADR-0002:** Documented nested subagent support strategy in
  `docs/decisions/0002-nested-subagent-support.md`.

## v5.0.1 — Token optimization

- **Orchestrator dedup:** `temper.md` and `fix.md` now delegate repeated
  build-state schemas, gate-enforcement prose, context-file schemas, feedback-loop
  schemas, and stage-agent launch scaffolding to a single canonical definition in
  `reference/orchestrator-patterns.md` instead of re-inlining them per stage.
- **Single-load contract:** orchestrators read `orchestrator-patterns.md` once at
  start; all `→ pattern` references point into that already-loaded file (no re-reads).
- **Progressive loading:** `reference/review.md` and `reference/plan.md` gained a
  Progressive Loading Map so stage agents load core sections first and pull optional
  sections only when their trigger fires. Duplicated optional methodology (arch-depth,
  HTML review) trimmed to references.
- **Lean memory:** `.claude/CLAUDE.md` trimmed to the command table + pointers; version
  history moved here, token insights moved to `reference/tokenomics.md`.