---
description: "Technical code review with confidence scoring, review memory, and intent validation"
---

# Review: Confidence-Scored Code Review

**Goal:** High signal-to-noise review — parallel subagents, confidence scoring, review
memory, intent validation. `agents/review.md` carries the exact `temper evidence add
--severity` invocation the gate needs; this doc is the methodology behind what to look
for and how to score it.

**Do not run if** code doesn't compile, tests are failing, or the build is broken — run
only after Build succeeds (or auto-chained from `/temper:build`, which already verified
this). Confidence scoring and review memory follow the temper-core skill's definitions.

**Modes:** Standalone (`/temper:review`) runs in the current context, own gate. Agent
subprocess (from `/temper`) starts clean, no `AskUserQuestion` — return the summary, the
orchestrator owns it. Load: `git diff --name-only`, `.temper/specs/{feature}/intent.md`
(for intent validation, if it exists), `build-context.json` (if it exists).

## Step 1: Gather Context

`git diff --stat` + changed files; `.claude/temper.config` for `review.block-on` /
`review.confidence-threshold` / auto-fix; the enabled packs' `rules.md` (project
`.claude/packs/` shadows global `~/.claude/packs/` shadows built-in
`$CLAUDE_PLUGIN_ROOT/packs/`, kept where `phases` is `all` or contains `review`);
`.temper/review-memory.json` (dismissed/accepted patterns, auto-rules); the active
`intent.md` (from build-context if chained, else the single spec present, else ask).

**OCR (external review engine, optional):** read `tools.ocr.mode` (default `auto`). Not
`off` → `command -v ocr`; missing + `require` → BLOCK with the install command, missing +
`auto` → skip silently. Found → `ocr --version`, then probe readiness with `ocr review
--preview --from <base> --to <head>`; failure + `require` → BLOCK, failure + `auto` →
one-line notice and proceed heuristically. Record `ocr_status` for Steps 2/2.5.

## Step 1.5: Diff-Aware Fingerprinting

Before launching subagents, classify each changed hunk so review energy goes where it
matters. For each hunk: change type (LOGIC/STRUCTURE/CONFIG/TEST/IMPORT) and risk signals
— SECURITY (password, token, jwt, encrypt, auth, secret, api-key, session), DATA_MUTATION
(insert/update/delete/save), ERROR_HANDLING (throw/catch/reject), CONCURRENCY
(async/thread/mutex/lock), EXTERNAL_API (fetch/http/client/grpc), MIDDLEWARE (app.use,
cors, rate-limit). Build an ephemeral (not persisted) fingerprint — files/hunks by type,
high-risk regions, security sensitivity counts — and pass it to every subagent in Step 2
so review effort concentrates where the risk actually is.

## Step 2: Parallel Review Subagents

Split the changed files across subagents however the diff suggests — by domain, by
module, by whatever grouping means each subagent can hold its slice in one context. One
hard constraint, because it's what bounds recursion: check the depth budget first —
`depth_remaining <= 1` → review inline, no subagents. Each subagent gets the active pack
rules, the stack-specific pattern file, its file list, and this prompt shape:

```
For each issue: Severity (CRITICAL/HIGH/MEDIUM/LOW), Confidence (0.0-1.0), Category
(logic/security/performance/quality/standards/architecture/test-gap), file:line,
Description, Suggestion.

Read the ENTIRE file (not just the diff) for context — the changed lines are what you
judge, the rest of the file is how you judge them. Report what you'd defend in review:
Step 4 discards anything below the configured confidence threshold, so a genuine
low-confidence finding costs nothing, but style preferences that violate no pack rule and
patterns consistent with the rest of the codebase are noise either way. Classify each
finding REGRESSION (was working, now broken — highest priority) / NEW ISSUE /
PRE-EXISTING (lower priority).
```

**If `ocr_status == ready` and `tools.ocr.replace-defect-subagent: true`:** OCR owns
line-level defect detection — the subagent skips the Performance sections below and
focuses on pack rules, security hot paths, AI-code detection, architecture drift, test
gaps, intent validation. Otherwise it runs everything below too.

**Performance patterns to flag:** N+1 queries (loop body calling db/API, unbounded count,
no batching → HIGH), missing pagination (list endpoint with no limit/offset/cursor and
unbounded growth → HIGH), unbounded recursion/operations (no depth limit or timeout →
MEDIUM), sync I/O in a request handler / hot path (→ HIGH), `O(n²)` `Array.includes`/
`find` in a loop over >10 items (→ MEDIUM, suggest Set/Map), and shared mutable state
mutated non-atomically in a concurrent handler (counter++, push() with no lock → HIGH; no
sync primitive at all → MEDIUM).

**Security (MCP-first):** if the semgrep MCP server is available and `tools.mode` isn't
`heuristic-only`: `security_check` on changed files, map error→CRITICAL, warning→HIGH,
info→MEDIUM, label `[PROVEN]`, always shown (bypasses confidence filtering). No semgrep →
run the checklist below, label `[HEURISTIC]`.

**Security hot path review** (files the fingerprint flagged CRITICAL/HIGH): trace every
call chain to the changed function (grep all usages, classify each as an entry point —
HTTP handler / background job / library call — and whether it's auth-gated); check
boundaries (unauthenticated code needs rate limiting, authenticated code needs an
ownership/authorization check, admin code needs a role check, input needs
validation/sanitization, output needs escaping of sensitive data); verify a test exists
for each boundary (unauthorized access, boundary violation, no stack-trace leakage).
CRITICAL: reachable from unauthenticated input, missing authorization on a privileged op,
sensitive data leaked in errors/logs. HIGH: an untested boundary, missing input
validation, an error handler exposing internals. Also check the app entry point for
security middleware (cors/helmet/rate-limit) and an error handler — HIGH if an HTTP
server has neither, MEDIUM if a public API is missing CORS/security headers. **Security
findings always bypass confidence filtering — this is the one category that must never
go silent because of a threshold.**

**AI-code detection** (apply to every file — this is what the notifications and
orders-api fixtures actually depend on, keep it real):

| Pattern | Detect by | Severity |
|---|---|---|
| Hallucinated API | grep the function definition in the project/deps; not found → flag | HIGH |
| Plausible but wrong | compare call against the library's real signature, or the project's existing usage of it | MEDIUM |
| Over-engineering | count usages; an abstraction used once | LOW |
| Copy-paste drift | near-identical blocks with a subtle inconsistency | — |
| **Missing integration** | new class/component/route never imported/registered/mounted anywhere | HIGH |
| Stale pattern | new code uses what old code used before a migration | — |
| Incomplete error path | catch block that only logs/rethrows generically | — |

## Step 2.5: OCR Engine (only if `ocr_status == ready`)

Determine the diff range (committed: `--from <base> --to <head>`; PR mode: `--from
origin/main --to <branch>`; uncommitted → skip with a notice). Run `ocr review --from X
--to Y --format json --audience agent --concurrency {tools.ocr.concurrency}` under a
`tools.ocr.timeout + 2min` bash timeout. Parse `comments[]` (file/line/description/
suggestion), map severity from the prose ("Critical Bug"/"Vulnerability"→CRITICAL 0.85,
"Security Issue"/"Bug"→HIGH 0.80, "Warning"/"Performance"→MEDIUM 0.75, else→LOW 0.70) and
category (SQLi/XSS/secret→security, NPE/null→logic, N+1/query→performance, else→quality),
label `[OCR]`. Deduplicate against Step 2's findings (same file, line ±2, same category
family) → merge to `[OCR+TEMPER]`, confidence `min(0.95, max(both)+0.15)`, higher
severity. JSON parse failure → raw-text appendix, both modes. OCR exits non-zero/timeout
→ `auto` discards and continues with Temper's own review, `require` degrades (warns, does
not block — a runtime failure isn't the same as unavailability).

## Step 3: Intent + Test Validation (if `intent.md` exists)

**Method disclaimer, stated once for the whole section:** this step has a mechanical
layer (provable by tools — a test exists, it passes, a grep matches) and a semantic layer
(Claude's judgment — does this assertion actually cover the Then clause, does this
implementation really solve the stated problem). Label every verdict with which kind it
is; semantic labels are directional, not proof, and no amount of reading code replaces
running it.

**a. BDD (mechanical):** each `Scenario:` → a corresponding test → the test passes.
Report as a checklist.

**b. IDD (structured):** for each Success Criterion, run its `Validate:` method — `scenario`
(linked scenario's test passes, ✅/❌) / `code` (grep for the named endpoint/config, ✅/❌) /
`metric` (can't verify pre-deploy, 📊 deferred) / `manual` (🔍 flagged for a human). Check
each constraint was respected. Overall verdict: satisfied / partially satisfied (name the
gaps) / not satisfied, plus "{N} mechanical, {N} deferred, {N} manual". No `intent.md` →
fall back to the linked issue/ticket, same three-way verdict.

**c. Semantic test quality (per scenario with a passing test):** locate its test (from
the Scenario Coverage Checklist, or grep the scenario name/annotation). Mechanical
sub-checks first — zero assertions → **TRIVIAL** (proven, no judgment needed); does any
asserted variable name appear in the Then clause's keywords → if not, **WEAK**
(mechanical mismatch). Otherwise, judge structural alignment (Given→setup, When→action,
Then→assertion) and assertion depth — flag an assertion that checks less than the Then
clause claims, accept indirect assertions (helper/matcher) that semantically cover it,
and when unsure, don't flag. Label **STRONG** (meaningful, specific assertions covering
Then) / **WEAK** (incomplete — MEDIUM issue) / **TRIVIAL** (always-passes — LOW issue).
STRONG counts full and TRIVIAL counts zero toward the Intent Verdict's evidence ratio;
WEAK counts half.

**d. Problem-statement traceback (semantic, the big picture):** re-read the Problem
field, read the implementation, ask "does this actually solve the stated problem" —
flag drift (problem says X, code does a different Y) or a gap (problem says multi-user,
code handles one). This produces its own semantic verdict; **reconcile** with (b)'s
mechanical verdict by taking the more conservative of the two (any "not satisfied" wins;
all "satisfied" wins; otherwise "partially satisfied").

**e. Decision-point coverage (LOW, informational):** scan changed files for business-
logic branches (if/else outcomes, multi-type catch blocks, switch/case, early returns
with different results) — excluding null-guards, logging branches, and framework
boilerplate. No matching scenario for a branch → flag it as a suggested addition, not a
blocker. Scoped to changed files only.

**f. Live mutation spot-check — the only step that actually proves a test catches a bug**
(everything else above is reading code and forming an opinion): for up to 3
CRITICAL/HIGH security-sensitivity files with tests — run the target test once to
confirm it's green; make one minimal mutation (flip a comparison, drop a required side
effect, change an error code); re-run the same test; **fails → PROVEN** (restore the
code); **still passes → UNVERIFIED** (restore the code, flag: CRITICAL if the function is
security-critical, else HIGH — "strengthen this test"). Always restore the original code
immediately, whatever the outcome. Skip if the test command isn't runnable in this
environment.

## Step 3.5: Deep Doubt Mode (adversarial pass)

Activate on `--doubt`, automatically for a large/CRITICAL blast radius (3+ modules or a
CRITICAL security hunk), or on request. Main orchestrator only — a subagent may not spawn
its own doubt mode (no recursive adversarial loops). Extract every claim the diff makes
("handles all errors", "thread-safe", "backward-compatible"); strip author intent and
comments, read only the logic; attack each claim (what input breaks it, what race
violates the invariant, what depends on the old behavior). Classify **contract-misread**
(violates its own documented contract, CRITICAL) / **actionable** (real bug, HIGH) /
**trade-off** (non-obvious downside, MEDIUM) / **noise** (suppress). Max 3 cycles; stop
early on an all-noise cycle; one more cycle after a real finding, then stop. Findings get
a `[DOUBT]` prefix; contract-misread bypasses confidence filtering.

## Step 3.6: Cross-File Pattern Consistency

For each changed file, extract its error-handling / API-response / validation / async
pattern and grep the same-type files (services, controllers, tests) for the established
pattern. A genuinely new pattern that isn't documented as an intentional improvement in
`intent.md`/`tasks.md` → MEDIUM "pattern drift" finding, confidence 0.6 (heuristic).
Track dominant pattern + exceptions in `.temper/review-memory.json`'s `patterns` key;
3+ dismissals of the same drift type → auto-suppress it.

## Step 3.7: API Contract Validation

Triggers when a changed file matches a controller/route/DTO/request/response/shared-type
path, or an OpenAPI/GraphQL schema. Diff old (removed) vs. new (current) contract shape
per endpoint — ADDITIVE (new field/endpoint/optional param, LOW risk) / MODIFIED
(type change, required↔optional, HIGH risk) / BREAKING (required field removed, endpoint
renamed, incompatible type, CRITICAL). Grep tests/frontend/type-imports/event-subscribers
for consumers; BREAKING with any consumer not updated → BLOCK; MODIFIED with no consumer
tests → WARN; ADDITIVE → INFO. Report per endpoint with consumer status. CRITICAL/HIGH
contract findings bypass confidence filtering.

## Step 3.8: Architecture Depth (optional, gate-offered)

When the `architecture-depth` pack is enabled and the user selects it at the review gate:
read `reference/architecture-depth.md` and run its 5-dimension analysis (seams, adapters,
locality, leverage, deletion test) on changed modules, ADR compliance included. Findings
get a `[ARCH-DEPTH]` prefix, folded into the main list, standard confidence filtering.

## Step 4: Confidence Filtering

Pack-rule findings (BLOCK/WARN/SUGGEST) override the confidence threshold — a BLOCK rule
finding is always shown. Otherwise: below `review.confidence-threshold` (default 0.7) →
discard entirely (not shown, not counted, not stored). Check `review-memory.json`: 5+
prior dismissals of this pattern → suppress; 3-4 → downgrade severity one level. Severity
from pack rules: BLOCK→CRITICAL, WARN→HIGH/MEDIUM, SUGGEST→LOW.

## Summary + Gate

```
+-----------------------------------------------------------+
| REVIEW — {Feature Name}                                   |
+-----------------------------------------------------------+
| Fingerprint: {N} files, {N} hunks, {N} CRITICAL/{N} HIGH security |
| Issues: Critical {N} High {N} Medium {N} Low {N}  Auto-fixable {N} |
| Security hot paths / Cross-file consistency / Contract changes    |
|   (sub-panels shown only when each step actually ran)             |
| Scenario coverage: {X}/{Y} (STRONG + 1/2 WEAK per Step 3c)         |
| Top issues: [{severity}] {file}:{line} — {one-liner}               |
| Intent verdict (if intent.md): {satisfied/partial/not met}         |
|   Evidence {X}/{Y} scenarios; mutation spot-check {N} PROVEN/{N} UNVERIFIED |
+-----------------------------------------------------------+
```

`AskUserQuestion`: "Fix all & continue to Check (Recommended)" (apply every fix including
LOW, re-run review once — single pass, no subagents, max 1 more loop — then proceed) /
"Save for later". A change typed via "Other" is never approval — make the edit, re-show
this same gate; the user must explicitly pick "Fix all & continue" to advance.

## Auto-Fix (Step 6 — only from the "Fix all" flow above, never standalone)

Apply each HIGH+ auto-fixable issue's suggested fix, run the relevant tests. Re-run
review once (single pass) to verify. Total auto-fix loops across the gate + this step:
max 2; issues still open after that → show them to the user rather than looping again.

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

`feedback.enabled: true` and auto-fixable issues persist after Step 6: write
`review-context.json` with what's left, loop to Build while `iteration <
loops.max-per-type` (default 2); at the budget, stop and show the user instead. The same
issue surviving 2 consecutive loops stops immediately rather than looping again.

## Metrics + Memory

Append to `.temper/metrics.json`: `reviews.total += 1`, `issues_found`, per-severity and
per-category counts, `auto_fixed`, `confidence_avg`. Update
`.temper/review-memory.json.patterns[{key}]`: `total_shown`/`accepted`/`dismissed`,
`last_seen`. 3+ accepted → suggest an auto-rule at `/temper:status`. 5+ dismissed →
auto-suppress. Context-specific dismissals (`config/` paths, test fixtures, DTOs, listed
legacy modules, `@generated` headers) are tracked and suppressed **independently per
context** — dismissed in `auth/` doesn't suppress the same pattern in `payments/`; ask
"this file only, or all {context} files?" on dismissal.

**Post-review learning hook** (no-op if `.temper/learning.json` doesn't exist): cluster
this review's findings by (category, file-path prefix, description keywords), match
against `learning.json.detected_patterns`, run the promotion criteria (3+ accepted @70%
→ suggest WARN; 5+ accepted @80% → suggest BLOCK, security/architecture only) and the
suppression criteria (3+ dismissed @<30% → downgrade a level; 5+ dismissed @<10% →
auto-suppress). Full algorithm: `reference/learning.md`.

## Multi-Agent Severity Consensus

Same severity from every subagent → keep it. Mixed → take the highest (conservative). One
agent alone finds CRITICAL and every other agent found nothing on that code → downgrade
to HIGH (a lone CRITICAL is unreliable). Category disagreement → default to `quality`.

## Automatic Next Step

CRITICAL/HIGH remain after auto-fix → show the report, ask the user. All clean → auto-
chain to `/temper:check`. Invoked manually (not chained from Build) → always show the
report and ask, regardless of findings.
