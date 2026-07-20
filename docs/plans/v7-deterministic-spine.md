# v7 — The Deterministic Spine

**Proposed release:** v7.0.0
**Current version:** v6.0.1
**Theme:** Trust through determinism. Move everything with exactly one correct output out
of prompt-space and into a small, auditable CLI enforced by hooks; shrink the prompts to
judgment only; prove pipeline quality with a seeded-defect eval suite that runs in CI.
**Status:** Planning · **Date:** 2026-07-19
**Depends on:** nothing — this phase *removes* dependencies. It supersedes the
byte-identity compatibility contracts of v5.x/v6.x (see "Retired contracts").

---

## Thesis

Temper's guarantees today are written in English. The orchestrator (`commands/temper.md`,
1,353 lines) plus the reference files (~10,700 prompt lines total) ask an LLM to act as a
deterministic interpreter: model-routing resolution, cache-routing resolution, the
three-branch `gate-eval` algorithm, loop-cost tiers, JSON state bookkeeping, and a stack
of "byte-identical to v5.x when off" promises that no prompt can actually keep.

That is the most fragile possible substrate for logic that has exactly one correct
output. Every run re-rolls the dice on whether a 10k-line program-in-prose executes
correctly, and no claim in a summary box is stronger than the model's own narration.

**Trust doesn't come from more instructions. It comes from:**

1. **Gates that are programs** — a gate a confused model physically cannot bypass.
2. **Claims that carry evidence** — command, exit code, artifact; never narration.
3. **A test suite that proves the pipeline catches bugs** — publicly, in CI, every release.

The design rule this release establishes, permanently:

> **No feature ships in prompt-space if it has exactly one correct output.**
> Prompts hold judgment (planning, scenario derivation, review, teaching).
> Code holds mechanism (state, gates, budgets, evidence, resolution logic).

## Target architecture

```
  PROMPTS (judgment only, ~1,500 lines)     CODE (deterministic, testable)
  ┌──────────────────────────────┐          ┌────────────────────────────────┐
  │ plan.md    – derive scenarios│          │ temper CLI (one file, no deps) │
  │ build.md   – TDD discipline  │  calls   │  temper state    (read/write)  │
  │ review.md  – find + score    │ ───────► │  temper gate     (pass/fail)   │
  │ fix.md     – RCA             │          │  temper evidence (record claim)│
  │ skills: grill-me, teach-me   │          │  temper report   (render run)  │
  └──────────────────────────────┘          └───────────────┬────────────────┘
                                                            │ enforced by
                                            ┌───────────────▼────────────────┐
                                            │ hooks: block `git commit`      │
                                            │ unless `temper gate commit`    │
                                            │ exits 0                        │
                                            └────────────────────────────────┘
```

The model calls the CLI; the CLI decides. The user-facing flow — `/temper "..."` →
plan gate → build → review → check → eval → commit gate, with the same summary boxes,
AskUserQuestion gates, Grill Me / Teach Me, and the plan-gate autonomy choice — is
unchanged on the surface.

---

## Move 1 — One deterministic spine: the `temper` CLI + commit hook

A single zero-dependency script at `scripts/temper` (bash, same engineering standard as
the existing `scripts/hooks/*.sh` — explicit degradation contracts, fail-open on internal
error, fail-closed only on an explicit violation).

### 1.1 `temper state` — state becomes impossible to corrupt

- Owns `.temper/build-state.json`, `.temper/feedback-loops.json`,
  `.temper/observability.json`. Subcommands: `init`, `get <key>`, `set <key> <value>`,
  `advance <stage>`, `loop <from> <to>`, `clear`.
- The model **never hand-writes state JSON again**. Every transition is validated
  (unknown stage, illegal jump, loop budget exceeded → non-zero exit with a one-line
  reason the orchestrator surfaces verbatim).
- Loop budgets and circuit breakers (`max-loops`, same-issue-twice, autonomy
  `max-total-loops` / `max-stages` / `max-wall-clock-min`) move here from prose.

### 1.2 `temper evidence` — every claim gets a row

```
temper evidence add --stage check \
  --claim "tests pass" \
  --cmd "npm test" --exit 0 \
  --artifact coverage/lcov.info
```

- Appends to `.temper/evidence/<stage>.json`. Schema (v1):
  `{claim, cmd, exit_code, artifact, sha256, ts, label}`.
- `label` is the existing evidence vocabulary with a hardened meaning:
  **`PROVEN` is reserved for rows the CLI itself verified** (it re-checks the exit code
  and that the artifact exists and hashes clean). `HEURISTIC`/`SEMANTIC` remain for
  model-judged findings. A hallucinated "coverage 87%" becomes structurally impossible —
  the number is parsed from the artifact, not asserted.

### 1.3 `temper gate <stage>` — verdicts, not vibes

Reads the evidence ledger + config, checks the stage's requirement list, prints
`PASS`/`FAIL` with each requirement's status, exits 0/1. Target: each gate function is
~30 lines of shell a user can read in one sitting.

| Gate | Mechanical requirements (v1) |
|------|------------------------------|
| `plan` | `intent.md` + `tasks.md` exist; every success criterion in `intent.md` maps to ≥1 scenario; blast-radius section present for medium+ complexity |
| `build` | Evidence that tests **ran and failed first, then passed** (extends `verify-tests-ran.sh`); all tasks in `tasks.md` ticked |
| `review` | 0 open findings at or above `review.block-on` severity in the ledger |
| `check` | Test command exit 0; coverage parsed from the real report ≥ threshold; every scenario in `intent.md` traced to a test |
| `eval` | Aggregate score ≥ `pass-threshold` from the results file; `block-on` dimensions passed (unchanged rubric) |
| `commit` | All prior gates PASS or carry a recorded human override; clean autonomy budget |

**Override semantics:** a FAIL gate still offers "Override (recorded)" — the human is
always allowed to proceed, but the override lands in the ledger and the final report says
"committed with N overridden gates." Trust is transparency, not handcuffs.

### 1.4 The commit hook — the promise becomes a program

- PreToolUse hook (Bash matcher on `git commit`) runs `temper gate commit`; exit 2 blocks
  with the failed requirement named. Native `pre-commit` hook via the existing
  `scripts/hooks/install.sh` path covers raw commits outside the agent.
- **"Parks before commit" and "never commits without green gates" stop being README
  promises and become mechanical facts** — including under Autonomous Continuation, whose
  park conditions (blast radius, `park-on-touch` paths, budget trips) become CLI checks
  with exit codes instead of a three-branch prompt algorithm.

### 1.5 Tests

- `bats` (or plain-shell) unit tests for every subcommand and every gate function, plus
  the existing hook scripts (currently untested). Runs in `quality.yml` CI.

**Acceptance (M1):** all state transitions and gate verdicts produced by the CLI; commit
blocked on any red gate in a fixture run; unit tests green in CI; no user-visible flow
change.

---

## Move 2 — Delete aggressively: prompts, config, flags

Everything the CLI now owns comes out of the prompts; everything the platform now
provides natively replaces its hand-rolled equivalent.

### 2.1 Deletion table

| Delete | Replaced by |
|---|---|
| Model Routing Resolution + Cache Routing Resolution blocks (`temper.md`, `orchestrator-patterns.md`) | `agents/plan.md`, `agents/design.md`, `agents/build.md`, `agents/review.md`, `agents/check.md`, `agents/eval.md` with declarative `model:` frontmatter (new `agents/` directory, platform-native) |
| `gate-eval` three-branch algorithm, loop-cost tiers, save-state pattern, resume validation prose | `temper state` / `temper gate` |
| Observability capture algorithm + source-provenance rules | `temper evidence` / `temper report` (numbers only ever come from measured commands; anything else is labeled estimated by the CLI) |
| All "byte-identical to v5.x/v6.x when off" contracts | the eval suite (Move 3) guards behavior; contracts are retired |
| ~190 of 211 config lines (`tokens.*`, `models.*` resolution knobs, capability toggles kept only for freeze-compat) | ~20-line config (below) |
| Cursor export maintenance (`.cursor/`, `generate-cursor.sh`, `install-cursor.sh`) | archived at v5.1 with one README line; removed from the release process |

### 2.2 Target config (complete file, ~20 lines)

```yaml
stack: auto
packs: [quality, tdd, security, git]
review:
  block-on: [critical]
check:
  coverage-threshold: 80
eval:
  enabled: true
autonomy:
  enabled: false            # plan-gate-armed, as today
  park-on-touch: ["**/auth/**", "**/payment/**", "**/billing/**"]
  max-blast-radius: 15
```

Everything else becomes a fixed good default. Model routing is owned by `agents/`
frontmatter; token efficiency is owned by the prompt diet itself (the honest version of
`tokens.cache` — deleting 9k lines beats hinting at read ordering the API layer never
promised to honor).

### 2.3 Prompt diet

- `commands/temper.md`: 1,353 → ~250 lines (stage sequence, gate wiring via CLI calls,
  summary-box formats).
- `reference/`: keep the judgment methodology — scenario derivation, blast radius, TDD
  discipline, review taxonomy + confidence, eval rubric, fix RCA — delete every
  resolution algorithm and schema the CLI owns. Target ~10,700 → **~1,500 lines total**.
- Grill Me / Teach Me skills: unchanged (pure judgment; they're the differentiator).

### 2.4 Retired contracts

v7 is an explicit breaking release. The v5.x byte-identity guarantees are retired and
replaced by a stronger one: **behavioral equivalence proven by the eval suite** (Move 3
pins the v6 baseline first). `CHANGELOG.md` documents the mapping old-flag → new
behavior; `/temper:init` migrates an existing config and prints what it dropped.

**Acceptance (M2):** line counts hit targets; `agents/` directory drives model choice;
config file is one screen; a newcomer can read the entire plugin end-to-end in ~20
minutes; all M1 tests still green.

---

## Move 3 — Prove it works, publicly: self-evals in CI

Temper ships an eval stage for users' features but has no behavioral regression harness
for its own prompts — `validate-*.sh` checks structure, not behavior. Every prompt edit
is currently a blind change to a 10k-line program.

### 3.1 Fixture projects with seeded defects (`evals/fixtures/`)

| Fixture | Seeded defect | Must be caught by |
|---|---|---|
| `password-reset` (node-express) | No rate-limit scenario/test (the README story) | plan/check scenario-coverage gate |
| `orders-api` (fastapi) | Hallucinated API — code calls a method that doesn't exist | review + check gates |
| `notifications` (react-ts) | Missing wiring — component built, never mounted | review intent-validation + eval `task_success` |

Each fixture also plants one autonomy tripwire (a change touching `**/auth/**`) to assert
the park is mechanical.

### 3.2 CI harness

- Runs the real pipeline headless (`claude -p "/temper:temper ..."`) per fixture and
  asserts against the **machine-readable evidence ledger** — not transcript grep:
  gate verdicts, seeded-defect caught, commit blocked, autonomy parked.
- **Baseline pinning:** before any Move 2 deletion lands, run the suite against v6.0.1
  and record the baseline. The slimmed pipeline must match it phase by phase — "same
  quality" becomes a measured property, not a hope.
- Cadence: on every PR touching `commands/`, `reference/`, `agents/`, `skills/`,
  `scripts/temper`; nightly full run.

### 3.3 The badge

README badge + evidence-gallery page: **"Seeded-defect catch rate: 3/3."** No other SDLC
plugin can show that; it is the marketing and the QA in one artifact.

**Acceptance (M3):** suite green against v6 baseline and against v7; a deliberately
broken prompt (delete the coverage-gate paragraph) turns the suite red; badge wired to
the CI run.

---

## What the user sees (unchanged surface, stronger floor)

Same flow, same boxes, same gates. Three visible upgrades:

```
┌──────────────────────────────────────────────────────────┐
│ CHECK — Password Reset                                   │
├──────────────────────────────────────────────────────────┤
│ ✓ Tests pass        npm test · exit 0 · 24/24            │
│ ✓ Coverage 87%      lcov.info · threshold 80             │
│ ✓ Scenarios 6/6     rate-limit scenario → test L42       │
│ ✓ 0 CRITICAL open   review ledger clean                  │
├──────────────────────────────────────────────────────────┤
│ temper gate check → PASS (4/4, .temper/evidence/check.json) │
└──────────────────────────────────────────────────────────┘
```

1. Every summary row is a ledger entry (command + exit code + artifact), not narration.
2. Each gate shows a computed `PASS/FAIL`; "Continue (Recommended)" only appears on PASS;
   overrides are allowed and recorded.
3. `git commit` is physically blocked while anything is red; `/temper:status` renders the
   ledger — what passed, on what evidence, what was overridden.

## How each phase keeps its quality

None of the deleted lines are methodology — they are plumbing. The generative quality is
preserved because the judgment prompts are untouched; the enforcement quality **rises**
because it moves from model discipline to exit codes:

| Phase | Judgment kept (prompt) | Guard today | Guard in v7 |
|---|---|---|---|
| Plan | scenarios-before-architecture, blast radius | prompt asks | `temper gate plan` requires criterion→scenario mapping |
| Build | TDD, RED→GREEN | prompt + `verify-tests-ran.sh` | gate requires evidence tests failed first, then passed |
| Review | taxonomy, confidence, packs | self-reported severity | ledger findings; gate counts open CRITICALs; `PROVEN` = CLI-verified |
| Check | stack validation | narrated results | gate parses real reports and exit codes |
| Eval | LM-judge rubric | same | same rubric; scores in ledger; block-on enforced by gate |

And the proof is Move 3: if a prompt diet ever did drop quality, the catch-rate assertion
goes red before the release ships — a guarantee the current 10,700 lines cannot make
about themselves.

## Milestones & order

| Milestone | Scope | Size |
|---|---|---|
| **M1** | `temper` CLI (state/evidence/gate/report) + commit hook + unit tests | days — immediate trust win, zero UX change |
| **M2** | Prompt diet, `agents/` directory, config collapse, contract retirement (v7.0.0) | the breaking release, guarded by M3 baseline |
| **M3** | Eval fixtures + CI harness + baseline pinning + badge | lands *between* M1 and M2 in practice: pin v6 baseline before deleting anything |

Execution order: **M1 → M3 (baseline against v6) → M2 (cut over) → M3 (assert parity, wire badge).**

## Non-goals (explicitly deferred)

PR-lifecycle automation (issue → intent intake, PR watching, CI autofix), the
learning/review-memory flywheel, new packs, new stages, any new config flag. All good
ideas; all noise until the spine is deterministic.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| CLI portability (macOS bash 3.2, no GNU tools) | POSIX-sh target; CI matrix macOS + Linux; fail-open contract on internal error |
| Headless eval runs cost tokens / flake | small fixtures, `tier-fast` where possible, assertions on ledger JSON only, nightly full / per-PR smoke |
| Breaking-release migration pain | `/temper:init` config migration + printed diff; CHANGELOG flag mapping; v6 stays installable |
| Coverage-report parsing per stack | one tiny parser per supported stack (6), each with a fixture test; unparseable ⇒ labeled `HEURISTIC`, never fake-`PROVEN` |
| Over-deleting judgment along with plumbing | M3 baseline pinned *before* M2 deletions; per-phase parity required |
