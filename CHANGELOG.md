# Changelog

All notable changes to Temper are documented here. The plugin version lives in
`.claude-plugin/plugin.json`.

## v5.1.0 — Token optimization

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

## v5.0.0 — Capabilities

Architecture depth review, grill-me challenge mode, config suggestions, interactive
HTML plan review.

## v4.6.0 — Adaptive Learning

Pattern detection, rule suggestions, noise reduction.

## v4.5.2

Deduplicate reference docs and Cursor rules — skills are the single source of truth,
docs delegate.

## v4.5.1

Fix skills loading — plugin.json skills paths must be directories, not SKILL.md file
paths.

## v4.5.0

7 imports from addyosmani/agent-skills — performance + api-design packs, debugging
procedure, Deep Doubt Mode, ADR generation, context engineering + source-driven skills.

## v4.4.1

Implementation alignment — Build→Plan feedback loop, cross-walkthrough navigation,
skip-to-build, doc accuracy.

## v4.4.0

Pack performance & discovery — cached manifest, quick-create launcher packs, filesystem
discovery, AskUserQuestion UX.
