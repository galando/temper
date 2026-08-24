---
description: "Technical code review with confidence scoring, review memory, and intent validation"
---

# Review: Confidence-Scored Code Review

**Goal:** High signal-to-noise review — parallel subagents, confidence scoring, review
memory, intent validation. `agents/review.md` carries the exact `temper evidence add
--severity` invocation the gate needs; this doc is the policy behind what to look for
and how to score it. It states rules a strong reviewer would not derive alone —
severity floors, filter bypasses, memory thresholds — not review technique.

**Do not run if** code doesn't compile or tests are failing — run only after Build
succeeds. Confidence scoring and review memory follow the temper-core skill's
definitions.

**Modes:** Standalone (`/temper:review`) owns its human gate. Agent subprocess (from
`/temper`, or from a standalone command running with `stages.subprocess: true`) starts
clean and never shows an `AskUserQuestion` — return the summary, the caller owns the
gate. Load: `git diff --name-only`, `{spec}/intent.md` (if it exists),
`build-context.json` (if it exists).

## Step 1: Gather Context

`git diff --stat` + changed files; `.claude/temper.config` for `review.block-on` /
`review.confidence-threshold` / auto-fix; the enabled packs' `rules.md` (project
`.claude/packs/` shadows global `~/.claude/packs/` shadows built-in
`$CLAUDE_PLUGIN_ROOT/packs/`, kept where `phases` is `all` or contains `review`);
`.temper/review-memory.json`; the active `intent.md` (from build-context if chained,
else the single spec present, else ask).

**`REVIEW.md` at the repo root (optional org review policy):** apply it layered on top
of the packs — its passes/emphases steer subagent attention; its Important-vs-Nit
definitions map to severities (nit caps at LOW, Important floors at HIGH); its nit cap
bounds how many LOWs the summary lists (excess summarized as a count, not dropped from
metrics); its do-not-report list suppresses matches — but never a pack **BLOCK** rule,
a `review.block-on` severity, or a security finding: those bypass every filter,
REVIEW.md included. Policy can re-aim the review; only config + packs can lower the
gate. Absent → skip silently.

**OCR (external review engine, optional):** if `tools.ocr.mode` isn't `off`,
`command -v ocr` then probe `ocr review --preview`; ready → record `ocr_status = ready`
(merge mechanics in `docs/recommended-setup.md`). Absent/failing: `require` blocks with
the install command, `auto` skips with a one-line notice.

## Step 1.5: Diff-Aware Fingerprinting

Classify each changed hunk — change type (LOGIC/STRUCTURE/CONFIG/TEST/IMPORT) and risk
signals (SECURITY, DATA_MUTATION, ERROR_HANDLING, CONCURRENCY, EXTERNAL_API,
MIDDLEWARE) — into an ephemeral (not persisted) fingerprint passed to every subagent,
so review effort concentrates where the risk actually is.

## Step 2: Parallel Review Subagents

Split the changed files across subagents however the diff suggests. One hard
constraint, because it bounds recursion: `depth_remaining <= 1` → review inline, no
subagents. Each subagent gets the pack rules, the stack pattern file, the fingerprint,
its file list, and this prompt shape:

```
For each issue: Severity (CRITICAL/HIGH/MEDIUM/LOW), Confidence (0.0-1.0), Category
(logic/security/performance/quality/standards/architecture/test-gap), file:line,
Description, Suggestion.

Read the ENTIRE file (not just the diff) — the changed lines are what you judge, the
rest of the file is how you judge them. Report what you'd defend in review: findings
below the confidence threshold are discarded later, so a genuine low-confidence finding
costs nothing, but style preferences that violate no pack rule are noise either way.
Classify each finding REGRESSION (was working, now broken — highest priority) /
NEW ISSUE / PRE-EXISTING (lower priority).
```

If `ocr_status == ready`, OCR owns line-level defect detection; the subagent covers
pack rules, security, AI-code detection, architecture drift, test gaps, and intent
validation, folding in OCR's `[OCR]` findings.

**Performance severity floors:** N+1 query, missing pagination on an unbounded list,
sync I/O in a hot path, non-atomic shared-state mutation in a concurrent handler →
HIGH; unbounded recursion, O(n²) membership scan in a loop, concurrent access with no
sync primitive at all → MEDIUM.

**Security (MCP-first):** semgrep MCP available and `tools.mode` isn't
`heuristic-only` → `security_check` on changed files, error→CRITICAL, warning→HIGH,
info→MEDIUM, label `[PROVEN]`. Else review heuristically, label `[HEURISTIC]`. For
files the fingerprint flagged: trace call chains to the changed function and check each
boundary — unauthenticated code needs rate limiting, authenticated needs an
ownership/authorization check, admin needs a role check, input needs validation, output
must not leak sensitive data — and verify a test exists per boundary. CRITICAL:
reachable from unauthenticated input, missing authz on a privileged op, sensitive data
in errors/logs. HIGH: untested boundary, missing input validation, error handler
exposing internals, HTTP server with neither security middleware nor an error handler.
**Security findings always bypass confidence filtering** — the one category that must
never go silent because of a threshold.

**AI-code detection** (apply to every file):

| Pattern | Detect by | Severity |
|---|---|---|
| Hallucinated API | grep the function definition in the project/deps; not found → flag | HIGH |
| Plausible but wrong | compare call against the library's real signature, or the project's existing usage of it | MEDIUM |
| Over-engineering | count usages; an abstraction used once | LOW |
| Copy-paste drift | near-identical blocks with a subtle inconsistency | — |
| **Missing integration** | new class/component/route never imported/registered/mounted anywhere | HIGH |
| Stale pattern | new code uses what old code used before a migration | — |
| Incomplete error path | catch block that only logs/rethrows generically | — |

## Step 3: Intent + Test Validation (if `intent.md` exists)

Every verdict is labeled **mechanical** (provable by tools) or **semantic** (judgment —
directional, not proof).

- **a. BDD (mechanical):** each `Scenario:` → a corresponding test → it passes.
  Checklist.
- **b. IDD (structured):** per Success Criterion, run its `Validate:` method —
  `scenario` / `code` (grep) → ✅/❌, `metric` → 📊 deferred, `manual` → 🔍 flagged.
  Verdict: satisfied / partially satisfied (name the gaps) / not satisfied, plus
  "{N} mechanical, {N} deferred, {N} manual". No intent.md → same verdict against the
  linked ticket.
- **c. Test quality (per covered scenario):** zero assertions → **TRIVIAL**; no
  asserted variable appears in the Then clause's keywords → **WEAK** (mechanical);
  otherwise judge Given→setup/When→action/Then→assertion alignment and depth — accept
  indirect assertions that semantically cover the Then; unsure → don't flag. STRONG
  counts full, WEAK half, TRIVIAL zero toward the verdict's evidence ratio; WEAK is a
  MEDIUM issue, TRIVIAL a LOW.
- **d. Problem-statement traceback (semantic):** does the implementation solve the
  stated Problem — flag drift or gaps. Reconcile with (b) by taking the more
  conservative verdict.
- **e. Decision-point coverage (LOW, informational):** business-logic branches in
  changed files with no matching scenario → suggested addition, never a blocker.
- **f. Live mutation spot-check** — the only step that proves a test catches a bug: for
  up to 3 CRITICAL/HIGH security-sensitive files with tests, confirm green → one
  minimal mutation → re-run. Fails → **PROVEN**; still passes → **UNVERIFIED** (flag
  CRITICAL if security-critical, else HIGH). Always restore the original code
  immediately, whatever the outcome. Skip if tests aren't runnable here.

## Step 3.5: Deep Doubt Mode (adversarial pass)

On `--doubt`, automatically for a large/CRITICAL blast radius (3+ modules or a CRITICAL
security hunk), or on request. Main orchestrator only — a subagent never spawns its own
doubt mode. Extract every claim the diff makes; read only the logic (not comments);
attack each claim. Classify **contract-misread** (CRITICAL, bypasses confidence
filtering) / **actionable** (HIGH) / **trade-off** (MEDIUM) / **noise** (suppress). Max
3 cycles; stop early on an all-noise cycle; one more cycle after a real finding, then
stop. `[DOUBT]` prefix.

## Step 3.55: Stale CLAUDE.md Check (LOW, informational)

Diff invalidates something `CLAUDE.md`/`AGENTS.md` states → LOW finding naming the
stale line; queue a `config-update` suggestion (`reference/config-suggestions.md`) —
never edit the file from review.

## Step 3.6: Cross-File Pattern Consistency

Per changed file, compare its error-handling / API-response / validation / async
pattern against same-type files. A new pattern not documented as intentional in
`intent.md`/`tasks.md` → MEDIUM "pattern drift", confidence 0.6. Track dominant
pattern + exceptions in `review-memory.json.patterns`; 3+ dismissals of the same drift
type → auto-suppress.

## Step 3.7: API Contract Validation

When a changed file is a controller/route/DTO/shared type or an OpenAPI/GraphQL schema:
diff old vs. new contract per endpoint — ADDITIVE (LOW) / MODIFIED (type or
required↔optional change, HIGH) / BREAKING (removed/renamed/incompatible, CRITICAL).
Grep for consumers; BREAKING with any consumer not updated → BLOCK; MODIFIED with no
consumer tests → WARN. Report per endpoint with consumer status. CRITICAL/HIGH contract
findings bypass confidence filtering.

## Step 3.8: Architecture Depth (optional, gate-offered)

`architecture-depth` pack enabled and selected at the gate → run
`reference/architecture-depth.md`'s 5-dimension analysis on changed modules; `[ARCH-DEPTH]`
prefix, standard filtering.

## Step 4: Confidence Filtering

Pack-rule findings override the threshold (BLOCK→CRITICAL, WARN→HIGH/MEDIUM,
SUGGEST→LOW — always shown). Otherwise: below `review.confidence-threshold` (default
0.7) → discard entirely (not shown, not counted, not stored). From
`review-memory.json`: 5+ prior dismissals of the pattern → suppress; 3-4 → downgrade
one severity level.

## Summary + Gate

The base summary box format is owned by `agents/review.md` — render it, appending a
line per step that actually ran (fingerprint, security hot paths, cross-file
consistency, contract changes, mutation spot-check {N} PROVEN/{N} UNVERIFIED) and the
top issues as `[{severity}] {file}:{line} — {one-liner}`.

`AskUserQuestion` (standalone mode only): "Fix all & continue to Check (Recommended)"
(apply every fix including LOW, re-run review once — single pass, no subagents — then
proceed) / "Save for later". A change typed via "Other" is never approval — make the
edit, re-show this same gate.

## Auto-Fix (only from the "Fix all" flow, never standalone)

Apply each HIGH+ auto-fixable fix, run the relevant tests, re-run review once. Total
auto-fix loops across the gate + this step: max 2; still open after that → show the
user rather than looping again.

## Context Output

Write `review-context.json`:

```json
{ "version": 1, "stage": "review", "timestamp": "{ISO timestamp}",
  "findings_summary": { "critical": {N}, "high": {N}, "medium": {N}, "low": {N}, "auto_fixed": {N} },
  "intent_verdict": "satisfied|partial|not_met",
  "security_hot_paths": [], "contract_changes": [],
  "scenario_coverage": { "total": {N}, "strong": {N}, "weak": {N}, "trivial": {N}, "uncovered": {N} } }
```

## Feedback Loop to Build

`feedback.enabled: true` and auto-fixable issues persist after auto-fix → loop to Build
with `review-context.json` while `iteration < loops.max-per-type` (default 2); at the
budget, stop and show the user. The same issue surviving 2 consecutive loops stops
immediately.

## Metrics + Memory

Append to `.temper/metrics.json`: `reviews.total += 1`, `issues_found`, per-severity
and per-category counts, `auto_fixed`, `confidence_avg`. Then update the single finding
memory, `.temper/review-memory.json.patterns[{key}]` (key = category + file-path prefix
+ first description keywords): `total_shown`/`accepted`/`dismissed`, `last_seen`,
`acceptance_rate = accepted/total_shown`. This one store drives both promotion and
suppression — there is no separate learning file:

- **Promote** (surfaced at `/temper:status`, never auto-applied): 3+ accepted at
  acceptance_rate ≥ 70% → suggest a **WARN** rule; 5+ at ≥ 80% in security or
  architecture → suggest a **BLOCK** rule. The human picks BLOCK / WARN /
  keep-advisory; an accepted rule is written into the active pack's `rules.md`.
- **Suppress**: 3+ dismissals at acceptance_rate < 30% → downgrade one severity level;
  5+ at < 10% → auto-suppress (Step 4 then drops it).

Context-specific dismissals (`config/` paths, test fixtures, DTOs, listed legacy
modules, `@generated` headers) are tracked per context — dismissed in `auth/` doesn't
suppress the pattern in `payments/`; ask "this file only, or all {context} files?" on
dismissal.

## Multi-Agent Severity Consensus

Same severity everywhere → keep. Mixed → highest wins. A lone CRITICAL no other
subagent saw on that code → downgrade to HIGH. Category disagreement → `quality`.

## Automatic Next Step

CRITICAL/HIGH remain after auto-fix → show the report, ask. All clean and chained from
Build → auto-chain to `/temper:check`. Invoked manually → always show the report and
ask, regardless of findings.
