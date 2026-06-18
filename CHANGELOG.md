# Changelog

All notable changes to Temper are documented here. The plugin version lives in
`.claude-plugin/plugin.json`.

## v5.4.0 — Release Bump Automation

Adds a one-button release workflow (`release-bump.yml`): a manual `workflow_dispatch` that bumps all version stamps, regenerates the derived `.cursor/` export, inserts a CHANGELOG entry, runs the full validator gate, and opens a release PR — removing the manual, error-prone bump-and-regenerate steps. Also ships the Phase 0 implementation-gap fixes from v5.3.0 (version single-source-of-truth, regenerable Cursor export, phase-filtered pack loading, honest observability labels) which had landed on `main` without a tag.

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