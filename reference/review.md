---
description: "Technical code review with confidence scoring and intent validation"
---

# Review: Confidence-Scored Code Review

**Goal:** High signal-to-noise review — parallel subagents, confidence scoring, intent
validation. The review brief (`${CLAUDE_PLUGIN_ROOT}/agents/review.md`) carries the exact
`${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add --severity` invocation the gate needs; this doc is the policy behind
what to look for and how to score it. It states rules a strong reviewer would not derive alone —
severity floors, filter bypasses — not review technique.

**Do not run if** code doesn't compile or tests are failing — run only after Build
succeeds. Each finding carries a confidence from 0.0 to 1.0: how sure you are that it is a real defect, not how
severe it is. Below 0.7 a finding is dropped (Step 4), save the categories that bypass the filter.

**Mode:** Review runs as a stage of `/temper`, in a clean subprocess that never shows an
`AskUserQuestion`: return the summary, the orchestrator owns the gate. Load the changed files (`${CLAUDE_PLUGIN_ROOT}/scripts/temper review files` prints them) plus
`{spec}/intent.md` (if it exists),
`build-context.json` (if it exists).

## Step 1: Gather Context

`git diff --stat` + changed files; `${CLAUDE_PLUGIN_ROOT}/scripts/temper config get review.block-on` for the levels
that block (default `[critical, high]`); the pack files your prompt lists on its `Packs:` line (the CLI chose those
of Review); the active `intent.md` (in the spec folder your launch prompt's `Spec path:` line names).

**`REVIEW.md` at the repo root (optional org review policy):** apply it layered on top
of the packs — its passes/emphases steer subagent attention; its Important-vs-Nit
definitions map to severities (nit caps at LOW, Important floors at HIGH); its nit cap
bounds how many LOWs the summary lists (excess summarized as a count, not dropped); its do-not-report list suppresses
matches — but never a pack **BLOCK** rule, a `review.block-on` severity, or a security finding: those bypass every
filter, REVIEW.md included. Policy can re-aim the review; only config + packs can lower the
gate. Absent → skip silently.

## Step 1.5: Diff-Aware Fingerprinting

Classify each changed hunk — change type (LOGIC/STRUCTURE/CONFIG/TEST/IMPORT) and risk
signals (SECURITY, DATA_MUTATION, ERROR_HANDLING, CONCURRENCY, EXTERNAL_API,
MIDDLEWARE) — into an ephemeral (not persisted) fingerprint passed to every subagent,
so review effort concentrates where the risk actually is.

## Step 2: Parallel Review Subagents

Split the changed files across subagents when the diff is large enough that parallel
reading pays for each subagent's context setup; a small diff is reviewed inline. One
hard constraint, because it bounds recursion: a review subagent never spawns subagents
of its own (say so in its prompt). Each subagent gets the pack rules, the fingerprint, its file list, and this prompt
shape (write the plugin folder in place of the CLAUDE_PLUGIN_ROOT variable in its first line):

```
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with
/scripts/temper taken off); wherever the brief or a reference page writes the
CLAUDE_PLUGIN_ROOT variable, use this folder.

For each issue: Severity (CRITICAL/HIGH/MEDIUM/LOW), Confidence (0.0-1.0), Category
(logic/security/performance/quality/standards/architecture/test-gap), file:line,
Description, Suggestion.

Read the ENTIRE file (not just the diff) — the changed lines are what you judge, the
rest of the file is how you judge them. Report every issue you find, including ones
you are uncertain about or consider low-severity; do not filter for importance or
confidence here. The confidence you attach is what Step 4 filters on, so a real finding
reported at 0.4 costs less than a dropped one. Omit only pure style or naming
preferences that violate no pack rule. Classify each finding REGRESSION (was working,
now broken — highest priority) / NEW ISSUE / PRE-EXISTING (lower priority).
```

**Performance severity floors:** N+1 query, missing pagination on an unbounded list,
sync I/O in a hot path, non-atomic shared-state mutation in a concurrent handler →
HIGH; unbounded recursion, O(n²) membership scan in a loop, concurrent access with no
sync primitive at all → MEDIUM.

**Security (MCP-first):** semgrep MCP available → `security_check` on changed files, error→CRITICAL, warning→HIGH,
info→MEDIUM, label `[PROVEN]`. Else review heuristically, label `[HEURISTIC]`. For
files the fingerprint flagged: trace call chains to the changed function and check each
boundary — unauthenticated code needs rate limiting, authenticated needs an
ownership/authorization check, admin needs a role check, input needs validation, output
must not leak sensitive data — and verify a test exists per boundary. CRITICAL:
reachable from unauthenticated input, missing authz on a privileged op, sensitive data
in errors/logs. HIGH: untested boundary, missing input validation, error handler
exposing internals, HTTP server with neither security middleware nor an error handler.
MEDIUM: a public API missing CORS/security headers.
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

- **a. BDD (mechanical):** each `Scenario:` → the test its `Test:` line names → it passes.
- **b. IDD (structured):** per Success Criterion, read the row of its `Validate:` method:
  `scenario`, and `code` or `metric` with a command in backticks → the row the CLI ran of that command
  (✅ exit 0, ❌ otherwise, or no row yet); `code` or `metric` with no command, and `manual` → 🔍 the person
  confirms it at the Check question. Verdict: satisfied / partially satisfied (name the gaps) / not satisfied, plus
  "{N} mechanical, {N} for the person". No intent.md → same verdict against the
  linked ticket.
- **c. Test quality (per covered scenario):** judge each test against the scenario's `Then` line and the Cases of the
  task that owns it. Zero assertions → **TRIVIAL**; no asserted variable appears in the Then line's keywords → **WEAK**
  (mechanical); otherwise judge whether the assertions check the Then and the Cases, and how deeply; accept
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

Automatically for a large/CRITICAL blast radius (3+ modules or a CRITICAL security hunk).
Run it in your own context: never launch another agent for it. Extract every claim the diff makes; read only the logic (not comments);
attack each claim. Classify **contract-misread** (CRITICAL, bypasses confidence
filtering) / **actionable** (HIGH) / **trade-off** (MEDIUM) / **noise** (suppress). Max
3 cycles; stop early on an all-noise cycle; one more cycle after a real finding, then
stop. `[DOUBT]` prefix.

## Step 3.55: Stale CLAUDE.md Check (LOW, informational)

Diff invalidates something `CLAUDE.md`/`AGENTS.md` states → LOW finding naming the
stale line; queue a `config-update` suggestion (`${CLAUDE_PLUGIN_ROOT}/reference/config-suggestions.md`) —
never edit the file from review.

## Step 3.6: Cross-File Pattern Consistency

Per changed file, compare its error-handling / API-response / validation / async
pattern against same-type files. A new pattern not documented as intentional in
`intent.md`/`tasks.md` → MEDIUM "pattern drift", confidence 0.6.

## Step 3.7: API Contract Validation

When a changed file is a controller/route/DTO/shared type or an OpenAPI/GraphQL schema:
diff old vs. new contract per endpoint — ADDITIVE (LOW) / MODIFIED (type or
required↔optional change, HIGH) / BREAKING (removed/renamed/incompatible, CRITICAL).
Grep for consumers; BREAKING with any consumer not updated → BLOCK; MODIFIED with no
consumer tests → WARN; ADDITIVE → INFO. Report per endpoint with consumer status. CRITICAL/HIGH contract
findings bypass confidence filtering.

## Step 3.8: Architecture Depth (optional, gate-offered)

Not part of this stage: the Review question offers "Architecture Depth Review" (under More
options), and the orchestrator then runs `${CLAUDE_PLUGIN_ROOT}/reference/architecture-depth.md`'s
5-dimension analysis on the changed modules (`[ARCH-DEPTH]` prefix, standard filtering).

## Step 4: Confidence Filtering

Pack-rule findings override the threshold (BLOCK→CRITICAL, WARN→HIGH/MEDIUM,
SUGGEST→LOW — always shown). Otherwise: below a confidence of 0.7 → discard entirely (not shown, not counted, not
stored).

## Summary + Gate

The base summary box format is owned by the review brief (`${CLAUDE_PLUGIN_ROOT}/agents/review.md`) — render it, appending a
line per step that actually ran (fingerprint, security hot paths, cross-file
consistency, contract changes, mutation spot-check {N} PROVEN/{N} UNVERIFIED) and the
top issues as `[{severity}] {file}:{line} — {one-liner}`.

**Accepting a finding.** A person can keep a finding as it stands with
`${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence accept --stage review --id <n> --reason '<why>'`. The row stays in the
ledger with the reason, the author (`the person`; Temper reads no name or email from git) and the time; `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate review`
stops counting it and its detail names the accepted count. The reason is required, an
empty one exits 1 and writes nothing, and a finding already resolved or accepted cannot
be accepted again. Resolve means fixed, in a commit the CLI made after Review; accept means
a person chose to keep it. The review stage never accepts a finding on its own.

**The completion row.** `temper evidence add --stage review --claim 'review completed' --exit 0`
takes one `--read <file>` for each changed file read whole; the gate fails it while a file of
`temper review files` is not named.

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

When fixable issues remain, write them to `review-context.json`. A blocking finding is repaired in
the stage first (ADR 0021): the CLI's own `temper repair start`, a fresh Build agent, the CLI's
commit and checks, a recheck (`Re-check:` in the brief), and `temper repair close`, which alone
resolves a finding. Record each finding whole (`--detail`, `--fix`, `--proof test|none`). The CLI's
Review question then offers "Repair again" once, and "Loop back to Build" while the budget lasts;
once it is spent, it asks `run.budget`.

## Answering a finding without fixing it (9.7.6)

The fix pass of Build (or the person) can answer a finding it believes is wrong instead of fixing it, in one of two ways.
Neither closes it: the gate still counts it, and the person decides at the Review question, where the accept question
lists escalated and contested findings first.

- **Contest**, with evidence the reviewer could have read:
  `temper evidence contest --stage review --id N --cite <file>[:<line>|:<symbol>] --quote '<the text there>' --reason '<why>'`.
  The CLI checks that the file is inside the project, holds the line or symbol, and holds the quote (within 3 lines of a
  cited line). The gate row names the citation, and the accept question offers it and the quote as reasons.
- **Escalate**, when the evidence is outside every file (a team rule, a decision someone said):
  `temper evidence escalate --stage review --id N --reason '<what only the person knows>'`.

"This was intentional" is not evidence. A Review agent never contests or accepts its own finding.

## Multi-Agent Severity Consensus

Same severity everywhere → keep. Mixed → highest wins. A lone CRITICAL no other
subagent saw on that code → downgrade to HIGH. Category disagreement → `quality`.
