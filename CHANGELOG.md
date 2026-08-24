# Changelog

All notable changes to Temper are documented here. The plugin version lives in
`.claude-plugin/plugin.json`.

## v8.1.0 — AI-native SDLC alignment, two-step install, and a simplification pass

Three threads: align temper with Anthropic's [AI-native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook),
cut install to two steps, and remove duplicated machinery. Net prompt-surface change
from the simplification alone: **−9.2%** (266KB → 242KB), with `reference/fix.md`
down 64% (517 → 143 lines). 170 CLI assertions green (up from 106); all validators pass.
Full play-by-play: `docs/ai-native-sdlc.md`.

### Install is two steps

`/plugin marketplace add` + `/plugin install`, then just `/temper "…"` — the first run
in an un-set-up project bootstraps itself (config, `.temper/` scaffold, and the native
commit gate). `/temper:init` is now that whole one-command setup (it installs the
commit hook too), kept for an explicit re-run. The old third manual step
(`bash scripts/hooks/install.sh`) is gone from the quick-start.

### New capabilities (playbook alignment)

- **Intent is the pipeline's own first gated stage.** `/temper` now runs
  intent → plan → design? → build → review → check → commit: a cheap Intent pass
  states the Problem, criteria, and constraints (no exploration, no architecture) and
  a human accepts or corrects it at the intent gate BEFORE the expensive stages spend
  tokens — an intent correction at this gate costs words; after Plan it costs the
  plan. `temper gate intent` is the deterministic floor (Problem stated, ≥1
  criterion, Status header); the commit gate requires an intent verdict whenever the
  artifact exists; trivial requests skip the stage automatically.
- **`/temper:intent`** — capture an idea (from anyone) as a committed `Status: draft`
  intent.md without starting the pipeline; the pipeline's Intent gate later presents
  exactly that draft. The intent lifecycle (`draft` → `accepted` → `completed`) has
  named owners and is recorded (`Accepted-by:` at the intent gate).
- **`temper bands`** — deterministic control-band drift detection (rolling mean ± kσ +
  a same-side-run rule, no model) over `.temper/metrics.json`; a 2σ+ breach exits 1 and
  a 3σ breach is drafted as the next intent.md. **`temper metrics append`** feeds any
  series, including external production metrics. Closes the Maintain loop.
- **A real design gate** — `temper gate design` now requires an Areas-of-Concern
  section; the commit gate requires a design verdict when `design.md` exists.
- **`temper evidence run`** (CLI executes the command and records the exit code —
  PROVEN means machine-observed), **`temper state archive`** (a durable
  `gate-ledger.json` committed with the diff), and **overrides that record the approver**.
- **New hooks** — the fix-loop regression-test write shield, edit-time protected paths
  (`protect.paths`), auto-format (`format.cmd`), and an ASK-tier confirm-override gate.
- **REVIEW.md** repo policy support; an approval-gate example hook. Automation is
  **deliberately host-agnostic**: temper ships no CI-platform files — the review and
  closing-the-loop arcs wire into ANY CI/scheduler (GitHub Actions, GitLab, Jenkins,
  cron) as plain commands and exit codes; `examples/workflow/README.md` documents the
  contract.

### Simplification (subtraction)

- **Four memory systems → one.** The adaptive-learning subsystem (`learning.json`,
  `packs/adaptive-learning/`, `reference/learning.md`, the `suggestion_queue`,
  `learning_curve`, and `.temper/learning/suggestions/`) is removed; its promotion and
  suppression thresholds were already `review-memory.json`'s, and now live only there.
  See ADR-0006 (supersedes ADR-0001).
- **`reference/fix.md` dieted** from a v6-style 517-line step script to outcome briefs,
  keeping the debugging floor, RED-first + the write shield, lessons read/write, and the
  gate calls.
- **OCR moved behind the MCP pattern** — the inline engine section in `reference/review.md`
  is now a probe + one merge rule, with the mechanics in `docs/recommended-setup.md`,
  matching how semgrep is handled.
- **`source-driven-development`** (previously loaded by no prompt) is wired into Build —
  it catches a hallucinated API while writing, before Review has to.
- **One front door** — the README leads with the three commands you actually type
  (`/temper`, `/temper:fix`, `/temper:intent`); the standalone stage commands move to a
  collapsed "granular control" section.
- **Retired-system docs** (`tokenomics.md`, `pricing.md`) moved out of the live
  methodology dir to `docs/history/`; the orphaned `templates/spec.md` +
  `quickstart.md` (which the three-artifact rule forbids) are deleted.

### Adversarial review

The branch diff was reviewed by a multi-agent workflow (4 dimensions, adversarial
verification); all 16 confirmed findings were fixed with regression tests — among them a
command-injection hole in the first cut of `temper metrics append` (a metric value was
interpolated into Python source; now parsed across the argv boundary).

## v8.0.0 — shorter prompts, no Eval stage, leaner pipeline

Breaking: the Eval stage and its config key are removed. The prompt surface was written
for an older model generation — long, prescriptive, step-numbered. It is now outcome
briefs, 43.7% smaller, which a measured A/B shows cuts the cost of a Plan run roughly in
half while holding quality.

- **The Eval stage is gone** — agent, command, reference doc, `skills/eval-judge/`,
  `templates/evalset.json`, and the `eval:` config block, deleted rather than disabled.
  `temper gate eval` exits non-zero; Check advances straight to the commit gate.
  **Migration: nothing to do.** A stale `eval:` config block and a stale `"eval"` key in
  `gates.json` are both inert, and an in-flight run's `build-state.json` is healed in
  place on the first CLI call. Temper's own `evals/` regression harness is a different
  thing with the same name and is untouched, except that `run-wiring-smoke.sh` drops its
  probe of the removed stage.
- **Review and Check run on Sonnet**, not Haiku — the two gates carrying the most
  judgment. `haiku` no longer appears in the prompt surface.
- **The prompt surface is down 43.7%** (372,967 → 209,863 bytes); `reference/plan.md`
  alone goes from 1,086 to 224 lines, with nothing a gate checks losing its prompt-side
  instruction. **Measured, not asserted** (6 runs per arm on Opus 5, same fixture):
  a Plan run costs **$1.74 median instead of $3.37, −48%**, with equal blast-radius
  recall, slightly more scenarios, and exactly the three artifacts the gate reads in 3
  of 3 runs where the old prompt always wrote 6. It is **not** faster — 384s vs 388s.
  Data: `docs/evidence/opus5-plan-prompt-ab.md`.
- **Evidence is cleared when a stage is redone** — new `temper evidence clear`, wired
  into `temper state loop`. Fixes a long-standing bug: evidence was append-only, so
  stale rows from an abandoned run still counted toward the next gate. (A parallel
  Review+Check launch was built and reverted before release — it left Check's results
  stale when a human requested changes at the Review gate. The two stages remain
  sequential, each with its own gate.)
- **`/temper:pack` discovery is fixed and extracted** to `scripts/pack-discover.py`:
  deduplicated targets, per-command descriptions, deterministic install-path selection,
  bounded globs. The documented-but-never-written `.temper/pack-manifest.json` cache is
  removed from the docs rather than built.
- **Cursor support is removed** — the `.cursor/` export and its two scripts. A generator
  bug had silently frozen it at v6.0.1, three major versions behind; shipping it
  misrepresented what Cursor users got. It will return in a better form.

### Deterministic standalone-stage gate enforcement

Re-running `evals/run-wiring-smoke.sh` (skipped in the original v8 verification)
found that the standalone commands invoked the deterministic spine in only **1 of 3
live runs** — Plan never called `temper gate plan`, Build wrote no evidence at all, and
`temper gate commit` cannot distinguish that from a repo that never ran Temper. For a
release whose headline is "gate verdicts are computed, never asserted", that was a
release blocker, fixed in the layer where the commit gate already lives:

- **New hook pair** — `scripts/hooks/stage-marker.sh` (UserPromptSubmit) records which
  gate a `/temper:{plan,build,review,check}` session owes; `scripts/hooks/verify-stage-gate.sh`
  (Stop) refuses to end the session until `.temper/gates.json` carries a verdict for it.
  Any verdict satisfies it — PASS or FAIL — because the guarantee is that the gate *ran*.
  Fail-open everywhere except that one path, with a 2-refusal loop guard.
- **Shipped with the plugin** via `hooks/hooks.json` (new) — fires for `--plugin-dir`
  and marketplace installs with no settings merge — and via the hooks pack's
  `settings.hooks.json` for the copy-paste path.
- **Gate calls moved into each command's numbered steps** (they sat in a trailing
  section the model demonstrably didn't reach) — kept as defense-in-depth so the hook
  rarely fires.
- **Proven live**: `.temper/hooks.log` from an end-to-end run shows the hook blocking a
  real skip and the model then running the gate 10 seconds later. Full record:
  `docs/decisions/0005-deterministic-stage-gate-enforcement.md`.

### Context engineering (second pass)

The prompt diet above cut length. This pass closes four places where Temper still spent
context the way a pre-Claude-5 plugin would — measured against Anthropic's
[new rules of context engineering](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models).
New doc: `docs/context-hygiene.md`.

- **The generated `TOKENOMICS` block is out of `.claude/CLAUDE.md`** — standing advice
  ("prefer Sonnet for simple tasks", "run `/compact` after turn 28", "Grep first, saves
  ~1%") re-injected into every session, for a saving smaller than the block describing
  it, duplicating judgment the model already applies. Tokenomics has been a retired
  system since v7; `validate-docs.sh` now fails if the block regenerates.
- **Pack `phases:` is real, not just documented.** No built-in pack had ever declared
  one, so every enabled pack loaded into all five stages regardless. Each now declares
  its scope in `rules.md` frontmatter, with the project's `packs:` entry still winning
  and `all` still the default when neither says. `packs/hooks/rules.md` declares `[]` —
  ~140 lines of install-and-behaviour documentation for self-enforcing bash hooks, which
  no stage agent can act on, previously loaded by all of them. Narrowing is evidence-based
  and deliberately conservative: `performance` and `api-design` keep `check` because
  `reference/check.md` runs a performance-regression gate (4.9) and an API contract check
  (4.85); `tdd` and `performance` keep `fix` because `/temper:fix` loads packs and writes
  a RED regression test. `validate-plugin.sh` validates every pack's declaration against
  the real phase vocabulary — it cannot tell you a pack was narrowed too far, which stays
  a reading of the stage docs.
- **`packs/tdd/rules.md` is 207 → 69 lines.** The cut is 106 lines of the same test
  written three times (Spring Boot, React, Express) plus step-numbered RED/GREEN/REFACTOR
  procedure. The rules, the scenario-driven mapping, and the test-location table stay.
  `reference/review.md` loses its subagent arithmetic (">20 files → groups of ~10, max 3
  parallel", "spend 80% of attention on flagged hunks", "weight 80% changed lines") in
  favour of the grouping judgment plus the one constraint that actually bounds recursion,
  the depth budget.
- **New `temper model <stage> | --all`, and an optional `models.{stage}` config key.**
  v7 was right to delete `models.routing`/`models.tiers` — a resolution algorithm a
  prompt had to execute correctly every run — but collapsing it to frontmatter meant a
  project could not change a stage's model without editing plugin-owned files, which
  comes up every time a model generation ships. Defaults still live in
  `agents/{stage}.md` frontmatter (one source of truth, read directly, nothing to drift);
  config overrides one; the lookup is bash. The orchestrator makes one `temper model
  --all` call per run. No tiers, no routing table, no algorithm in prose.

## v7.0.1 — Fixes

Fix bash 3.2 override crash + state CLI correctness bugs (#69); v7.0.0: The Deterministic Spine — CLI-enforced gates, agents/, prompt diet, self-evals (#68); link Privacy Policy from landing page and README (#67); ci,docs: plugin-directory submission kit + official strict manifest validation in CI (#66)

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

**Self-verification pass (same release):** re-checked against the design doc's own
acceptance criteria and closed the real gaps that turned up:
- `temper gate check` now traces every `intent.md` scenario to a test by name
  (`--scenario` on `temper evidence add`) and names the uncovered ones in its FAIL
  detail — this is the mechanism that makes the README's rate-limiting story literally
  true, not just illustrative. It was missing at first pass; `agents/check.md` and
  `scripts/tests/test-temper.sh` updated with it.
- `temper gate plan` now requires a `## Blast Radius` section in `plan.md` for
  `medium`/`complex` changes (`temper state set complexity` records the tier).
- `.github/workflows/eval-fixtures.yml` gained a `pull_request` trigger (one fixture,
  path-filtered to `commands/`/`reference/`/`agents/`/`skills/`/`scripts/temper`) — the
  design doc called for per-PR + nightly; only nightly + on-demand shipped at first pass.
- `/temper:init` now actually greps an existing config for retired `tokens:`/`models:`/
  `observability:`/`capabilities:` blocks and reports them, instead of only describing
  that behavior in prose.
- The design doc's per-fixture "autonomy tripwire" was deliberately not added to the
  three eval fixtures — `park-on-touch` is a pure CLI property with zero model
  judgment involved, already covered by `scripts/tests/test-temper.sh` without spending
  tokens on a live run to re-prove it. Reasoning: `evals/README.md`.
- **Known gap, not closed in this pass:** the design doc's reference/ line-count target
  (~10,700 → ~1,500 total) was not hit — `commands/temper.md` (1,353→363) and
  `reference/orchestrator-patterns.md` (979→327) got the deep rewrite; the other
  reference files (`plan.md`, `review.md`, `check.md`, `build.md`, `pack.md`, `fix.md`,
  and others) only got targeted edits removing dangling references to retired config
  keys, not a line-count-reducing rewrite. Current `reference/` total: ~6,500 lines.
  This is real, disclosed scope not yet done, not a silently-missed target.

**Third pass — live baseline run, and a critical bug it found:**

- **Ran the eval suite for real** against a `v6.0.1` worktree and against this branch
  (`TEMPER_PLUGIN_DIR` override in `evals/run-fixture.sh`, `IS_SANDBOX=1` to unblock
  `--dangerously-skip-permissions` under root). Both catch **3/3**; v7's catches are
  confirmed via the evidence ledger (`temper gate` mechanically FAILing with the defect
  named), not just a transcript grep — a strictly stronger guarantee than v6.0.1 had.
  Full numbers: `evals/README.md`.
- **That live run found a real, severe bug: the standalone `/temper:plan`,
  `/temper:build`, `/temper:review`, `/temper:check`, `/temper:eval` commands never
  recorded evidence or ran gates at all.** Only `agents/*.md` (used by the unified
  `/temper` orchestrator) had the `temper evidence add`/`temper gate` instructions —
  the standalone commands, a fully documented and supported entry point, were left
  running the old prose-only methodology with no CLI involvement. Concretely: running
  `/temper:check` standalone, then `git commit`, would have hit `temper gate commit`
  seeing zero evidence for every stage and wrongly blocking the commit (or, worse,
  once `.temper/gates.json` had *some* stale PASS in it, wrongly letting a broken
  change through). Fixed: `commands/{plan,build,review,check,eval}.md` each gained a
  "Deterministic Gate" step pointing at the matching `agents/*.md` steps, with an
  explicit `--spec-path` (standalone use doesn't necessarily call `temper state init`,
  so `temper state get spec_path` can be empty — passing it explicitly was required,
  not optional, to stop the scenario-tracing check from silently skipping instead of
  failing loudly). Verified with fresh live runs before and after the fix.
- Collapsed a genuinely duplicated ~13-line "load packs via the cached manifest" block
  — repeated near-verbatim across `plan.md`/`design.md`/`build.md`/`check.md`/
  `review.md` — down to a one-line pointer at `pack.md`'s already-canonical
  documentation of the same mechanism. ~55 lines, zero methodology lost.
- Fixed a dormant shell/Python interpolation bug in `evals/run-fixture.sh` (same class
  already fixed once in `scripts/temper`) and a join-with-comma ambiguity + a subtler
  IFS-first-character-only bug in `temper gate check`'s scenario-tracing detail line.
- Investigated further reference/ line-count reduction beyond the pack-manifest dedup
  and made a deliberate call not to force it: the remaining size in `review.md`/
  `plan.md`/`pack.md`/`check.md` is genuine, load-bearing methodology (confidence
  scoring, diff fingerprinting, Deep Doubt Mode, progressive-loading navigation maps
  that are themselves a token-efficiency mechanism) — not plumbing. Cutting it to hit
  the plan's ~1,500-line target would violate v7's own design rule (delete mechanism,
  keep judgment) for the sake of a number. The gap is real and stays open by design.

**Fourth pass — the eval harness's own "caught" signal was weaker than claimed:**

Asked directly whether the eval suite is actually correct, not just useful — re-read
`evals/run-fixture.sh` cold rather than re-stating the third pass's claims. Found: the
"evidence-ledger" match only checked whether *any* evidence entry's free-text `claim`
matched a keyword regex. It never inspected `severity` (what `temper gate review`
actually checks) or `exit_code`/`scenario` (what `temper gate check` actually checks),
and never ran `temper gate <stage>` or read `.temper/gates.json`. So "confirmed via
evidence-ledger" was true only in the sense that matching text existed — not that the
gate would have mechanically blocked a commit, the actual claim made in this
CHANGELOG's third-pass entry above. That distinction had only been checked by hand
during debugging, never by the automated script CI runs.

- **Fixed:** a three-tier signal, strongest first — `gate-blocking-evidence` (the
  matching entry also carries the specific property that drives the real gate:
  `severity == 'critical'` for review, a `--scenario` row with nonzero `exit_code` for
  check), `evidence-non-blocking` (text matches, wouldn't fail the gate), and
  `transcript-fallback` (only the raw transcript mentions it; no evidence recorded at
  all). Pass bar is now **strict by default** — only tier 1 counts, matching what CI
  should enforce; `TEMPER_EVAL_ACCEPT_ANY_TIER=1` is the explicit override needed only
  for the v6.0.1 comparison (tier 1 is structurally unreachable there — v6.0.1 has no
  CLI at all).
- **Verified live, both directions:** v6.0.1's `orders-api`, run *without* the
  override, correctly reports MISSED — the first real negative-path confirmation this
  harness has ever produced (every prior run had only ever shown CAUGHT). v6.0.1's
  `password-reset`, run *with* the override, correctly passes. All three v7 fixtures
  re-confirmed at the strict `gate-blocking-evidence` tier. Full writeup:
  `evals/README.md`.
- **Known, disclosed limitations that remain:** only `review`/`check` are exercised by
  a live fixture — `plan`, `build`, `eval`, and `commit` gates are only tested by
  synthetic CLI unit tests, the same class of gap that hid the third-pass bug. Tiers
  2-3 still use fuzzy keyword matching. Both documented in `evals/README.md` under
  "Known limitations", not hidden.

**Fifth pass — closed the tier 2/3 fuzzy-keyword-matching gap:**

The fourth pass's remaining item: tiers 2/3 matched on a single flat `catch_keywords`
list, `OR`ed together — a generic word alone (`"missing"`, `"unused"`) could
false-positive on unrelated text with no connection to the seeded defect.

- **Fixed:** each fixture's `expect.json` now splits `catch_keywords` into
  `anchor_keywords` (specific identifiers — exact scenario names, code symbols,
  component names) and `signal_keywords` (generic descriptive terms). Every tier now
  requires **both** an anchor match and a signal match, not either alone — including
  tier 1's text-matching component, not just tiers 2/3. `evals/run-fixture.sh` passes
  both patterns as `argv` into its `python3 -c` checks (not spliced into source, per
  the same fix already applied once in `scripts/temper` and once earlier in this same
  file), and the transcript-fallback tier now requires both patterns to appear in
  `run.log`, not just one.
- **Also fixed:** `scripts/validate-plugin.sh`'s fixture-schema check, which still
  asserted the old `catch_keywords` key — would have failed CI against every fixture's
  new `expect.json` had it been left as-is.
- **Verified live:** all three `expect.json` files re-validated as well-formed JSON
  carrying both keys; `evals/run-fixture.sh` re-run live against this branch, still
  reporting `CAUGHT` at the strict `gate-blocking-evidence` tier with the new
  anchor+signal logic. Full rationale: `evals/README.md`.
- **Residual, disclosed limitation:** anchor and signal only need to appear *somewhere*
  in the same claim/transcript, not adjacent or about the same clause — narrower than
  before, but still weaker than tier 1's gate-property check. Tiers 2/3 remain
  non-authoritative for CI regardless.

**Sixth pass — closed the `plan`/`build`/`eval` live-coverage gap:**

The remaining disclosed limitation from the fourth pass: only `review`/`check` were
exercised by a live fixture. `plan`, `build`, and `eval` were only tested by
`scripts/tests/test-temper.sh` — real for the CLI's own gate *logic*, but blind to
whether a real model, following the actual prompt, calls `temper evidence add`/
`temper gate` at all. That's not a hypothetical concern — it's exactly the bug class
the third pass found for the standalone commands, just not yet re-checked for these
three specific stages.

- **Added `evals/wiring-smoke/` + `evals/run-wiring-smoke.sh`** — a fourth fixture,
  differently shaped from the other three: no seeded defect, no `expect.json`, no
  catch/miss verdict. It chains three real headless invocations
  (`/temper:plan` → `/temper:build` → `/temper:eval`) against one small, deliberately
  trivial feature, then checks — by reading `.temper/gates.json` and
  `.temper/evidence/*.json` directly, the same files `temper gate commit` itself
  reads — whether each stage actually got called for real, not by matching keywords in
  a transcript.
- **Verified live, first run:** clean pass — `plan: PASS`, `build: PASS`, `eval: PASS`;
  `build` evidence 2 entries, `eval` evidence 1 entry; `temper state get complexity`
  correctly returned `trivial`. No wiring gap found in any of the three previously
  untested stages.
- **Wired into CI:** `.github/workflows/eval-fixtures.yml` runs it alongside
  `evals/run-all.sh` on the nightly + full on-demand paths (not the per-PR smoke
  check, to keep PR cost down); `scripts/validate-plugin.sh` checks the new fixture's
  required files and that `run-wiring-smoke.sh` is executable.
- **Narrowed, not closed at first: `commit` gate aggregation.** `temper gate commit`
  isn't invoked by a model that could forget a prompt instruction — the native
  pre-commit hook and the in-agent PreToolUse hook both call it unconditionally. The
  risk class that justified the rest of this pass doesn't apply the same way there;
  its aggregation logic was already unit-tested, but nothing had ever proven the real
  *mechanism* — the actual git hook `scripts/hooks/install.sh` writes — really
  installs, really fires, and really blocks (or allows) a real `git commit`, as
  opposed to just the function it calls.

**Then closed for real, same pass:** asked directly "will it actually work?" instead
of leaving the narrowed gap as a documented tradeoff. Answered it by testing the real
mechanism — installed the hook into a scratch repo, set a red gate, ran a real `git
commit`: blocked (exit 1, nothing landed in `git log`). Flipped the gate green, ran it
again: succeeded (exit 0, commit landed). Both directions needed no live model call,
only real git — so both are now permanent assertions in
`scripts/tests/test-temper.sh` (27 → 31 tests), not a one-off manual check. All five
pre-commit gate stages plus the commit gate's own installation mechanism are now
verified for real, live or deterministic as appropriate; no known gap remains.

Full writeup: `evals/README.md`.

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