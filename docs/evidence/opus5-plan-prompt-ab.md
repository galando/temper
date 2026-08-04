# A/B: old vs new Plan prompt on Opus 5

Controlled comparison, 2026-08-02/03. Same model (Opus 5), same fixture
(`evals/fixtures/password-reset`), same feature string, standalone `/temper:plan` via
`claude -p --plugin-dir` against frozen git worktrees. Two rounds, 6 runs per arm total;
round 2 added `--output-format json` for real token and cost accounting.

- **Old prompt:** `reference/plan.md` @ v7.0.1 — 1,086 lines.
- **New prompt:** `reference/plan.md` @ v8.0.0 — 224 lines.

## Cost and tokens (round 2, 3 runs per arm)

| | New (224 ln) | Old (1,086 ln) | Delta |
|---|---|---|---|
| Cost per run, median | **$1.74** | **$3.37** | **−48%** |
| Cost per run, mean | $1.81 | $3.09 | −41% |
| Cost, 3 runs total | $5.43 | $9.27 | −$3.84 |
| Output tokens, median | 24,617 | 28,139 | −13% |

Per-run cost: new `$1.74 / $1.66 / $2.04`, old `$2.06 / $3.37 / $3.84`.

Input tokens are dominated by cache reads (~1M per run in both arms) and are not a clean
signal — the prompt-size difference shows up in **cost** and in **output tokens**, since
the shorter methodology also produces less padding in the artifacts.

## Quality and behaviour (both rounds, 6 runs per arm)

| Metric | New | Old | Verdict |
|---|---|---|---|
| `gate plan` verdict | PASS ×6 | PASS ×6 | equal |
| Blast-radius recall | 3/3 files, every run | 3/3 files, every run | equal |
| Scenarios in intent.md | 13 / 15 / 13 | 12 / 11 / 13 | new slightly better |
| Seeded rate-limit topic found | every run | every run | equal |
| Artifacts emitted | 3,6,3 (round 1) → **3,3,3 (round 2)** | 6 every run | **new correct after hardening** |
| Wall-clock, median of 6 | 384s | 388s | **no change (1%)** |

Round-1 wall-clock: new `377/391/455`, old `414/364/379`. Round-2: new `342/303/434`,
old `409/340/397`.

## Conclusions

1. **The diet does not make Plan faster.** 384s vs 388s across 6 runs per arm. Wall-clock
   is dominated by the model exploring the repo and writing artifacts, not by reading the
   methodology doc. The ">10 minutes" figure in `intent.md` was a user report from full
   `/temper` runs on a real repo and was never a baseline of this fixture — SC6's target
   was set against a number that did not describe what was measured.
2. **The diet does save real money: ~41–48% per Plan run**, on top of holding quality.
   That is the claim the cuts actually support, and it compounds across every stage of
   every run.
3. **Quality held or improved.** Equal blast-radius recall and seeded-defect attention,
   slightly more scenarios, at a fifth of the prompt length.
4. **Artifact determinism is fixed.** Round 1 (pre-hardening) emitted the intended three
   files in 2 of 3 runs; round 2, after the "never a fourth file" rule was made explicit,
   emitted exactly `intent.md` + `plan.md` + `tasks.md` in 3 of 3. The old prompt always
   wrote 6, three of which no gate reads.

## SC6, resolved

SC6 ("Plan completes in under 4 minutes") was carried through the release as an unmet
criterion under a human override. It should not have been: **the criterion was invalid,
not the result.** Its 4-minute target was derived by halving a ">10 minutes" figure that
came from a user report about full `/temper` runs on a real repository — a different
command on different code. Nothing ever measured this fixture before the target was
written, so there was no baseline to improve on by 50%.

The measurement now exists: **384s median (6.4 min) over 6 runs**, range 303–455s, and
the old prompt was 388s on the same fixture. A Plan run on `password-reset` takes about
six and a half minutes on Opus 5 regardless of prompt length, because wall-clock is
dominated by repo exploration and artifact writing.

Anyone re-deriving a Plan timing target should set it against that 384s figure and state
the fixture it applies to. The spec that carried SC6 was a run-local `.temper/specs/`
artifact and is not in version control; this section is the durable record.

## What this changed in the release

`faster pipeline` was withdrawn from the v8.0.0 headline — it is not supported for the
Plan stage. The defensible claims are the cost reduction, the quality hold, the artifact
discipline, and one fewer stage in the pipeline.
