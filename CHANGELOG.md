# Changelog

All notable changes to Temper are documented here. The plugin version lives in
`.claude-plugin/plugin.json`.

## v7.0.0 — The Deterministic Spine

Temper's guarantees moved out of prose and into a program. Through v6.x, gate logic,
model routing, prompt-cache ordering, and loop-cost tiering were ~9,000 lines of prompt
asking an LLM to act as a deterministic interpreter — the least trustworthy place to put
logic with exactly one correct output. v7 is a breaking release built around one rule,
applied everywhere: **no feature ships in prompt-space if it has exactly one correct
output.**

- **New `scripts/temper` CLI** — a single zero-dependency bash script that owns
  `state` (build-state.json, never hand-written again), `evidence` (every claim now
  carries a command, exit code, and artifact — `--label PROVEN` is mechanically
  re-checked, not taken on faith), `gate` (`plan`/`build`/`review`/`check`/`eval`/`commit`
  — each ~20-30 lines of readable shell, PASS/FAIL with named reasons), `override`
  (a human can always proceed past a FAIL, but it's recorded, never silently erased), and
  `report` (renders the ledger). Unit-tested: `scripts/tests/test-temper.sh`, wired into
  CI.
- **The commit gate is now a program, not a promise.** The native pre-commit hook
  (`scripts/hooks/install.sh`) and a new in-agent PreToolUse hook
  (`scripts/hooks/block-uncommitted-gate.sh`) both run `temper gate commit` — `git
  commit` is physically blocked while any upstream gate is FAIL and unoverridden. This
  is what "autonomy never commits without green gates" now *means*, mechanically, not
  just in the README.
- **New `agents/` directory** — `agents/{plan,design,build,review,check,eval}.md`, one
  file per stage with `model:` frontmatter (native, declarative) and a short contract
  (what to read, what `temper evidence`/`temper gate` calls to make). Replaces the
  Model Routing Resolution and Cache Routing Resolution algorithms.
- **Prompt diet:** `commands/temper.md` 1,353 → 363 lines; `reference/orchestrator-
  patterns.md` 979 → 327 lines — the two biggest single cuts. Both dropped only
  mechanism (routing/caching/gate-eval algorithms, the observability.json v3 telemetry
  schema, loop-cost tiering); judgment content (scenario derivation, TDD discipline,
  review taxonomy, the eval rubric, Grill Me/Teach Me) is untouched.
- **Config collapsed:** `.claude/temper.config` 211 → ~55 lines (most of it comments).
  `tokens.*`, `models.*`, `observability.*`, `capabilities.*`, and the nested-agent
  budget block are gone — replaced by either a CLI mechanism (gates, evidence) or a
  fixed good default (Grill Me/Teach Me/HTML review/Architecture Depth Review are now
  always offered at their gates; there's no toggle to turn them off, just don't pick
  them).
- **`/temper:status` drops the cost/latency/token "Economics" panel** (v6.x estimates
  with no mechanical backing) for a **Gate Ledger panel** reading `.temper/gates.json` +
  `.temper/evidence/`: only what was actually recorded.
- **Autonomous Continuation, simplified, not removed:** still opt-in, still armed only
  at the plan gate, still never commits/pushes/merges. The three-branch `gate-eval` hook
  and confidence-threshold machinery are gone — an autonomous run now just runs `temper
  gate {stage}` and auto-continues on PASS, parks on FAIL past budget. Blast-radius and
  park-on-touch checks are computed by `temper gate commit` itself.
- **`/temper:fix` updated to match:** Fix/Review/Check now record evidence and run
  `temper gate build/review/check/commit` — required so a `/temper:fix` commit isn't
  wrongly blocked by a commit hook that now checks for evidence on every commit.
- **Retired outright** (not degraded — deleted): the `tokens.*` runtime levers (prompt
  cache read-ordering, adaptive pipeline depth, loop-cost tiers), `models.*` routing
  config, the `observability.json` v2/v3 cost/latency/drift telemetry schema, the
  `capabilities.*` config toggles, and `scripts/validate-phase2.sh` /
  `scripts/validate-phase3.sh` (they asserted the byte-identity contracts this release
  retires). See `reference/tokenomics.md` and `reference/pricing.md` for what replaced
  each.
- **Cursor IDE export archived**, not regenerated per release. `.cursor/` stays at its
  v6.0.1 snapshot; `scripts/generate-cursor.sh` still runs by hand if you want it, but
  it's out of `version-bump.sh` and `release-bump.yml`. See `.cursor/README.md`.
- **Design doc:** `docs/plans/v7-deterministic-spine.md`.

## v6.0.1 — Standard Plugin Layout

Restructure to the standard Claude Code plugin layout in preparation for
plugin-directory submission. No behavior changes — every command, skill, pack,
and reference doc is byte-identical, only paths moved.

- **Standard layout:** `.claude/commands/` → `commands/`, `.claude/skills/` → `skills/`,
  `.claude/packs/` → `packs/`, `.claude-plugin/reference/` → `reference/`,
  `.claude-plugin/templates/temper.config.default` → `templates/`. `.claude-plugin/`
  now contains only `plugin.json` and `marketplace.json`, per plugin spec.
- **`$CLAUDE_PLUGIN_ROOT` references updated** across commands, skills, packs, and
  reference docs to the new paths. Bare `.claude/packs/` (project-local) and
  `~/.claude/packs/` (global) resolution paths are unchanged — only the built-in
  tier moved.
- **Session logs untracked:** `.claude/interactions.log` and `.claude/session.log`
  removed from git (already gitignored).
- **README:** new "Security & Trust" section documenting the trust contract
  (no network calls/telemetry, writes confined to the project, autonomy never
  commits/pushes/merges).
- **Cursor export unchanged in role:** `.cursor/` remains a derived, frozen-at-v5.1
  export regenerated by `scripts/generate-cursor.sh`, now reading the new source
  paths. It is outside the plugin's command/skill surface.
- Scripts (`generate-cursor.sh`, `install-cursor.sh`, `version-bump.sh`,
  `validate-*.sh`) updated to the new layout.
- **`validate-phase3.sh` version scenario no longer pinned to `5.9.0`:** it was
  asserting every version stamp equals the Phase 3 release version, so it began
  failing on v6.0.0 and every release after. It now checks lockstep agreement
  against `plugin.json` (the single source of truth) instead, so it keeps
  passing across releases. The CHANGELOG-has-a-v5.9.0-entry check is unchanged.
- **Documented headless invocation:** confirmed via an end-to-end pipeline run
  (real fixture project, all 6 stages, plan gate through commit-gate park) that
  the bare `/temper` alias only resolves in interactive sessions — `claude -p`
  and CI callers must use the fully-qualified `/temper:temper`. Noted in the
  README quick start and in `docs/commands.md`.

## v6.0.0 — New Features

Autonomous Continuation for /temper (#63)

## v5.9.0 — Phase 3: Token Efficiency & Loop Engineering

Three independent, composable levers layered on the v5.6.0 model-routing foundation.
Each is config-flagged under `tokens:` in `.claude/temper.config`, default-on, and
degrades **byte-identically** to v5.8.0 when its flag is off.

### D1 — Cache the static instruction mass
- **`tokens.cache`**: stage agents read the cacheable context (methodology ref,
  orchestrator-patterns, pack-manifest, stack-pack, config) FIRST in a byte-stable order,
  then the volatile delta. Maximizes platform cache hits on re-entry; the orchestrator
  cannot force a cache, only structure reads so the prefix is stable.
- **`tokens.cached_input{value, source}`**: new v3 observability field records what the
  platform reports as cache-served (source `measured`/`estimated`). G-5 source rule extended.
- **Cacheable vs. Volatile Context** + **Cache-Stable Re-Entry** sections in
  `reference/orchestrator-patterns.md`. Cache Routing Resolution block in `temper.md`.

### D2 — Complexity-adaptive pipeline depth
- **`tokens.adaptive-depth`**: the plan stage's existing complexity classification
  (trivial|simple|medium|complex) selects a reduced pipeline per the new **Pipeline Depth**
  table. `floor` clamps the effective tier UP (`floor: medium` kills the trivial fast-path).
- Replaces the 4 blanket enforcement overrides (temper.md:153, temper.md:173, plan.md:518,
  plan.md:983) with a **DEPTH CONTRACT** conditional on `adaptive-depth.enabled`. The
  standalone `/temper:plan` complexity-tiered rules are UNCHANGED.
- Plan gate shows the chosen depth tier with an **"Escalate to full pipeline"** option.

### D3 — Incremental feedback loops
- **`tokens.loops`**: every feedback loop resolves by a cheapest-first decision rule —
  **inline** micro-fix (no subprocess) when all findings auto-fixable AND
  `files_touched <= inline-threshold`; else **fix-mode** minimal-context Build Agent (fix
  list + changed files + fix-mode preamble, NOT full `build.md`); else **full** re-launch.
- New **Loop Cost Tiers** section + per-loop `mode` + `cost` in observability.json `loops[]`.

### Degradation contract
- With `cache.enabled: false` + `adaptive-depth.enabled: false` + `loops.fix-mode: false` +
  `inline-threshold: 0`, a `/temper` run is byte-identical to v5.8.0 (full pipeline, full
  re-launch, no cache prefix, no `cached_input` field). v3 observability is an additive
  superset of v2.

### Other
- `reference/pricing.md`: cache read (~0.1x) / write (~1.25x) multipliers; dropped the
  "excludes caching" note — `cost_usd` MAY now reflect cache savings.
- `reference/tokenomics.md`: canonical 3-lever token-efficiency guidance.
- `.cursor/` frozen at v5.1 (only `.cursor/VERSION` bumped to 5.9.0 via `generate-cursor.sh`).
- New `scripts/validate-phase3.sh` mechanical verifier.

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