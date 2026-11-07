# Review: Confidence-Scored Code Review

**Goal:** high signal, low noise: every finding carries a severity and a confidence, findings
below the threshold are dropped, security findings never are, and the implementation is
checked against the intent. Review runs only after Build, on code that compiles.

Review never changes code. A finding goes back to Build when the person loops back.

## Step 1: Gather context

- **The changed files:** `git diff --name-only {base_sha}` (from `state.json`) plus the paths
  `git status --porcelain` lists. Read each whole file: the changed lines are what you judge,
  the rest is how you judge them.
- `.claude/temper.config` for `review.block-on` (default `[critical]`) and
  `review.confidence-threshold` (default 0.7).
- The enabled packs' `rules.md` (rules whose `phases` is `all` or names `review`) and the
  stack file.
- `.temper/review-memory.json` when it exists.
- `intent.md` and `evidence.md` of the run.

**`REVIEW.md` at the repository root** (optional team policy): apply it on top of the packs.
Its "nit" caps at LOW, its "important" floors at HIGH, its do-not-report list suppresses
matches, but never a pack BLOCK rule, a `review.block-on` severity or a security finding.

## Step 2: Look for defects

Classify each changed hunk (LOGIC, STRUCTURE, CONFIG, TEST, IMPORT) and its risk signals
(SECURITY, DATA_MUTATION, ERROR_HANDLING, CONCURRENCY, EXTERNAL_API, MIDDLEWARE), and spend
your effort where the risk is. For a large diff, split the files across review agents; a
review agent never starts agents of its own. Report every issue with severity (CRITICAL, HIGH,
MEDIUM, LOW), confidence (0.0 to 1.0), category (logic, security, performance, quality,
standards, architecture, test-gap), `file:line`, description and suggestion. Mark each
REGRESSION, NEW ISSUE or PRE-EXISTING.

**Performance floors:** an N+1 query, an unbounded list without pagination, sync I/O on a hot
path, a non-atomic shared state change in a concurrent handler: HIGH. Unbounded recursion, an
O(n²) scan in a loop, shared access with no lock at all: MEDIUM.

**Security.** With a semgrep MCP server, run it on the changed files (error CRITICAL, warning
HIGH, info MEDIUM, `[PROVEN]`); otherwise review by reading, `[HEURISTIC]`. For flagged files,
trace each call chain to its entry point and check each boundary: unauthenticated code needs
rate limiting, authenticated code an ownership check, admin code a role check, input
validation, no sensitive data in output, a test per boundary. **Security findings bypass the
confidence filter.**

**AI-written code:**

| Pattern | How to detect | Severity |
|---|---|---|
| Hallucinated API | the definition is not in the project or its dependencies | HIGH |
| Plausible but wrong | the call does not match the real signature | MEDIUM |
| Missing integration | new code never imported, registered, routed or rendered | HIGH |
| Over-engineering | an abstraction used once | LOW |
| Copy-paste drift | near-identical blocks with one subtle difference | MEDIUM |
| Incomplete error path | a catch that only logs or rethrows | MEDIUM |

## Step 3: Intent and tests

- **Scenarios:** each `Scenario:` has a test, and its `scenario` row in `evidence.md` passed.
- **Criteria:** run each `Validate:` (`scenario`, `code` by grep); `metric` is deferred,
  `manual` is flagged for the person. Verdict: `satisfied`, `partial` (name the gaps) or
  `not_met`.
- **Test quality:** a test with no assertion is TRIVIAL (LOW finding); a test whose assertions
  do not touch the Then clause is WEAK (MEDIUM finding); otherwise STRONG.
- **Problem traceback:** does the code solve the stated Problem? Take the more cautious of
  this and the criteria verdict.
- **Mutation spot check:** for up to 3 CRITICAL or HIGH security files with tests, make one
  minimal change to the logic and run the tests. They fail: PROVEN. They still pass:
  UNVERIFIED (a finding). Always restore the original code at once.

## Step 4: Adversarial pass (large or CRITICAL changes)

For a change across 3 or more modules or with a CRITICAL hunk: list every claim the diff
makes, read only the logic, attack each claim. A misread contract is CRITICAL and bypasses the
filter; an actionable flaw is HIGH; a trade-off is MEDIUM; noise is dropped. At most 3 rounds.

## Step 5: Consistency and contracts

- A new error handling, response, validation or async pattern unlike the same kind of file
  elsewhere, not called intentional in the plan: MEDIUM "pattern drift", confidence 0.6.
- For a changed route, DTO, shared type or schema: ADDITIVE (LOW), MODIFIED (HIGH), BREAKING
  (CRITICAL). Grep for consumers; a breaking change with a consumer not updated is CRITICAL.
- A change that makes a line of `CLAUDE.md` or `AGENTS.md` wrong: a LOW finding naming the
  line. Review never edits those files.

## Step 6: Filter

Pack rule findings override the threshold (BLOCK is CRITICAL, WARN is HIGH or MEDIUM, SUGGEST
is LOW; always shown). Otherwise a finding below `review.confidence-threshold` is dropped:
not shown, not counted. From `review-memory.json`: 5 or more past dismissals of the same
pattern suppress it; 3 or 4 lower it one severity.

## Writing review.md

Write the findings table of `reference/run-state.md`, each finding `open`, and the
`Review completed:` line even when there are no findings: an empty table is not a review.

## Review memory

Update `.temper/review-memory.json` `patterns[{key}]` (key: category, path prefix, first
keywords) with `total_shown`, `accepted`, `dismissed` and `last_seen`. A pattern accepted 3 or
more times at 70% or more is a candidate WARN rule; 5 or more at 80% in security or
architecture, a BLOCK rule. `/temper:status` lists candidates; the person decides, and an
accepted rule goes into the project's `.claude/packs/{name}/rules.md`, never into the plugin.
