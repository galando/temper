# Phase 3 — Token Efficiency & Loop Engineering

**Proposed release:** v5.9.0
**Current version:** v5.8.0
**Theme:** Cut the OpEx of a `/temper` run by eliminating repeated ingestion of static
instructions, right-sizing the pipeline to change complexity, and making feedback loops
cheap. Phase 2 routed each stage to the right *model*; Phase 3 stops paying full price to
re-read the same *context*, and stops running a frontier-tier pipeline on trivial changes.
**Status:** Planning · **Date:** 2026-06-24
**Depends on:** Phase 2 (model routing + observability) — the economics panel in
`/temper:status` is how we measure that these deliverables actually saved money.

---

## Why this phase

Phase 2 picked the right model per stage. The remaining waste is structural, not model
choice:

1. **Static instructions are re-ingested at full price.** A `/temper` run launches 6
   isolated Agent subprocesses, each with a clean context that re-reads its methodology
   fresh. The methodology references alone are large — `review.md` (1258 lines),
   `plan.md` (1083), `check.md` (674), `build.md` (450) — and the orchestrator
   (`temper.md`, 1093 lines) sits in the main context throughout. Feedback loops re-read
   `build.md`/`review.md` *again* at full price. Nothing is cached;
   `reference/pricing.md` even excludes caching from the cost model, so the dashboard
   can't see the waste.

2. **The pipeline ignores change complexity.** `temper.md:153`, `temper.md:173`, and
   `plan.md:518` enforce *"no shortcuts for Simple or Trivial features — full artifact
   set regardless of complexity."* A one-line fix therefore runs all 6 stages + 6 gates +
   mermaid + blast radius. The pipeline is provisioned for the worst case on every case.

3. **Feedback loops are full re-launches.** Per `orchestrator-patterns.md` Feedback Loop
   Patterns, a Review→Build loop to auto-fix 2 lint findings re-launches a *full* Build
   agent that re-reads `build.md` + tasks + intent. The circuit breaker (max 2) bounds
   the *count*; nothing bounds the *unit cost*.

**Deliverables:** (1) prompt-caching of static methodology/reference reads, (2)
complexity-adaptive pipeline depth, (3) incremental (minimal-context) feedback loops.

**Non-goals (this phase):** batch-mode dispatch, the per-capability cost panel, reference
file splitting, and orchestrator de-duplication. These are tracked for Phase 4 so this
phase stays shippable and measurable.

---

## Deliverable 1 — Cache the static instruction mass

The methodology/reference files are immutable during a session. Re-reading them per stage
and per feedback loop is the single largest pool of avoidable input tokens. Cached reads
bill at a fraction of base input; this is waste elimination with **no behavior change**.

### 1.1 Mark cacheable context in the launch template (`reference/orchestrator-patterns.md`)
- Extend the **Stage Agent Launch Template** so the "Full methodology: Read …" line and
  any always-on reference reads (orchestrator-patterns, pack manifest) are declared as a
  **cacheable context block** — i.e. loaded first, before the volatile per-stage deltas
  (spec artifacts, git diff), so the cacheable prefix is stable across launches.
- Add a **Cacheable vs. Volatile Context** subsection that classifies every read:
  - **Cacheable (stable for the session):** methodology reference, orchestrator-patterns,
    pack manifest, stack pack rules, `temper.config`.
  - **Volatile (per launch):** `build-state.json`, spec artifacts, `git diff`, context
    JSON files, feedback context.
- Ordering rule: cacheable reads first, volatile reads last, so the cache prefix never
  shifts between a stage and its feedback-loop re-entry.

### 1.2 Reuse the cache across feedback-loop re-entries
- A Review→Build / Check→Build / Eval→Build re-launch MUST read the *same* methodology
  file in the *same order* as the first launch, so the cached prefix hits. Document this
  as a **Cache-Stable Re-Entry** rule in the Feedback Loop Patterns section.

### 1.3 Config surface (`.claude/temper.config`)
```yaml
# Token efficiency (v5.9.0)
tokens:
  cache:
    enabled: true            # cache static methodology/reference reads across launches
    scope: [methodology, orchestrator-patterns, pack-manifest, stack-pack, config]
  # graceful degradation: when enabled is false, reads happen exactly as in v5.8.0
```

### 1.4 Observability + pricing
- `reference/pricing.md`: add advisory cache read/write multipliers per tier and a note
  that `cost_usd` MAY now reflect cache savings (drop the blanket "excludes caching").
- `orchestrator-patterns.md` observability schema: add `tokens.cached_input` (+ its
  `source`) per stage so `/temper:status` can show the cache hit rate and dollars saved.

**Graceful degradation:** `tokens.cache.enabled: false` ⇒ byte-identical to v5.8.0.

---

## Deliverable 2 — Complexity-adaptive pipeline depth

Stop running the worst-case pipeline on every case. The plan stage already classifies
complexity (`trivial | simple | medium | complex`); make that classification *drive* how
many stages and gates run, instead of being overridden.

### 2.1 Remove the blanket "no shortcuts" enforcement
- `temper.md:153`, `temper.md:173`, `plan.md:518`: replace the "full artifact set
  regardless of complexity" enforcement with a **complexity-tiered depth contract**
  (below). The full pipeline remains the default for `medium`/`complex`.

### 2.2 Depth tiers (`reference/orchestrator-patterns.md` — new "Pipeline Depth" section)

| Complexity | Stages run | Design | Eval | Gates |
|------------|-----------|--------|------|-------|
| `trivial`  | single combined plan+build agent → review | skip | skip | 1 (final) |
| `simple`   | plan → build → review → check | skip | skip | plan + final |
| `medium`   | plan → design? → build → review → check → eval | conditional | yes | all |
| `complex`  | full pipeline (current behavior) | yes | yes | all |

- "single combined agent" for `trivial`: one Agent loads a **lean** plan+build methodology
  (spine only) and returns a diff; no `design.md`, no mermaid, no blast radius, no eval.
- Artifact requirements scale with tier: `trivial`/`simple` produce `intent.md` +
  `tasks.md` only; mermaid + blast radius required only at `medium`+.

### 2.3 Config surface (`.claude/temper.config`)
```yaml
tokens:
  adaptive-depth:
    enabled: true            # let plan-stage complexity drive pipeline depth
    floor: simple            # never go below this tier's rigor (e.g. set 'medium' to disable trivial fast-path)
    # enabled: false ⇒ v5.8.0 "always full pipeline" behavior
```

### 2.4 Gate + override behavior
- The plan gate shows the chosen depth tier and an **"Escalate to full pipeline"** option,
  so a user can always opt back into the heavy flow for a change the classifier under-rated.
- `adaptive-depth.floor` is the safety rail for teams that want a minimum rigor.

**Graceful degradation:** `adaptive-depth.enabled: false` ⇒ full pipeline always (v5.8.0).

---

## Deliverable 3 — Incremental (minimal-context) feedback loops

A loop that auto-fixes 2 lint findings should not re-read the entire Build methodology.
Bound the *unit cost* of a loop, not just the loop count.

### 3.1 Loop cost tiers (`reference/orchestrator-patterns.md` — Feedback Loop Patterns)
- **Inline micro-fix:** when all loop findings are auto-fixable and touch ≤ N files
  (config `tokens.loops.inline-threshold`, default 3), the orchestrator applies the fix
  directly — **no Agent re-launch, no methodology re-read.**
- **Minimal-context fix agent:** when a re-launch is warranted, launch a Build agent in
  **fix mode**: it receives the fix list + only the specific changed files + the relevant
  context JSON — NOT the full `build.md`, NOT the full diff. A short "fix-mode" preamble
  replaces the full methodology read.
- **Full re-launch:** reserved for loops that change approach/scope (e.g. Build→Plan
  infeasibility), where the full methodology is genuinely needed.

### 3.2 Decision rule
```
if loop.findings all auto_fixable and files_touched <= inline-threshold:  inline micro-fix
elif loop.type in [review->build, check->build, eval->build]:             minimal-context fix agent
else:                                                                     full re-launch
```

### 3.3 Config surface (`.claude/temper.config`)
```yaml
tokens:
  loops:
    inline-threshold: 3      # <= this many auto-fixable files => fix inline, no subprocess
    fix-mode: true           # minimal-context fix agent for re-launched loops
    # fix-mode: false ⇒ full re-launch (v5.8.0 behavior)
```

### 3.4 Observability
- Record per-loop `mode` (`inline | fix-mode | full`) and its token cost in
  observability.json so `/temper:status` can show savings from cheaper loops and confirm
  the circuit breaker (max-loops) still holds.

**Graceful degradation:** `loops.fix-mode: false` + `inline-threshold: 0` ⇒ every loop is
a full re-launch (v5.8.0).

---

## Files touched (planning estimate)

| File | Change |
|------|--------|
| `.claude/temper.config` | new `tokens:` block (cache / adaptive-depth / loops) — all default-on, all degrade to v5.8.0 |
| `reference/orchestrator-patterns.md` | Cacheable/Volatile context rule; Cache-Stable Re-Entry; Pipeline Depth tiers; Loop Cost Tiers + decision rule; observability fields |
| `.claude/commands/temper.md` | replace blanket "no shortcuts" enforcement with depth contract; plan gate shows depth tier + escalate option |
| `reference/plan.md` | replace `:518` enforcement override with complexity-tiered artifact requirements |
| `reference/pricing.md` | cache multipliers; drop blanket "excludes caching" |
| `reference/tokenomics.md` | document the three levers as the canonical token-efficiency guidance |
| `CHANGELOG.md` / `plugin.json` / `CLAUDE.md` | v5.9.0 entry + version bump |
| `.cursor/**` | regenerate via `scripts/generate-cursor.sh` |

## Blast radius

- **Behavioral default change:** D2 changes what runs for trivial/simple features. This is
  the only user-visible behavior shift; gated behind `adaptive-depth.enabled` and an
  `Escalate to full pipeline` gate option, with a `floor` safety rail.
- **No-op-by-default risk:** D1 and D3 are pure cost optimizations — same artifacts, same
  gates, fewer/cheaper tokens. Each degrades byte-identically to v5.8.0 when disabled.
- **Validation:** extend `scripts/validate-phase2.sh` (or a new `validate-phase3.sh`) to
  assert the `tokens:` schema parses and the degradation flags exist. Run
  `scripts/validate-plugin.sh` + `scripts/validate-docs.sh`.

## Success criteria

1. A trivial change runs ≤ 2 stages and ≤ 1 gate (D2), measured in observability.json.
2. Re-running an unchanged stage / a feedback loop reports `cached_input > 0` (D1).
3. An auto-fix-only Review→Build loop completes with `mode: inline` and launches no
   subprocess (D3).
4. With all three flags disabled, a full run is byte-identical to v5.8.0 (degradation
   contract).
5. `/temper:status` economics panel shows dollars saved from cache + cheaper loops.
