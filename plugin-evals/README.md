# Native `claude plugin eval` suite

This directory is a `claude plugin eval` suite (`case.yaml` + `prompt.md` +
`graders/*.md` per case) — the built-in Claude Code plugin-eval mechanism, wired up
here via `.claude-plugin/plugin.json`'s `experimental.evals: "plugin-evals"`.

**This is not the same thing as `../evals/`.** `../evals/` is Temper's own bespoke
seeded-defect fixture harness (`run-fixture.sh`, `run-all.sh`) built specifically to
prove the deterministic gate ledger (`.temper/evidence/`, `.temper/gates.json`) catches
real regressions in this plugin's prompts. This directory instead runs through the
generic `claude plugin eval` CLI command, scored by its own graders — useful for
quick, ad-hoc runs (`claude plugin eval . --trust-plugin --scaffold`) and for the
ablation arm it gives for free (with-plugin vs. no-plugin). Keep both: they exercise
the same plugin from two independent harnesses, which is worth more than either alone.

## Cases

| Case | Command exercised | What it proves |
|---|---|---|
| `init-scaffolds-project` | `/temper:init` | A fresh project gets `.claude/temper.config`, `.temper/` state, and the commit-gate hook installed |
| `init-is-idempotent` | `/temper:init` | Re-running never overwrites an existing config, but still re-runs the (idempotent) scaffold + hook install steps |
| `review-catches-array-bug` | `/temper:review` | An off-by-one bug in an uncommitted diff is named specifically (not just narrated) and recorded in `.temper/evidence/review.json`, with `temper gate review` actually invoked |
| `status-no-gate-data-graceful` | `/temper:status` | A never-run project gets the documented graceful placeholder (`No gate data yet. Run /temper to populate it.`), not an error |

## Running

```bash
# Requires --scaffold to let each case's scaffold_script build its throwaway git repo,
# and --trust-plugin since this plugin directory hasn't been installed via a
# marketplace. First run: real graders cost real judge-model tokens.
claude plugin eval . --trust-plugin --scaffold

# One case:
claude plugin eval . --trust-plugin --scaffold --case init-is-idempotent

# Full JSON + HTML report:
claude plugin eval . --trust-plugin --scaffold --json plugin-evals/results/run.json \
  --report plugin-evals/results/run.html
```

`plugin-evals/results/` is gitignored — regenerate it, don't commit it.

## Adding a case

1. `plugin-evals/<name>/case.yaml` — `schema_version`, `name`, `tags`, `runs`,
   `execution:` (model/turns/timeout/allowed_tools), and `context.scaffold_script` if
   the case needs a throwaway git repo or fixture files.
2. `plugin-evals/<name>/prompt.md` — the literal message a user would send. For a
   slash command, that's just the bare command (`/temper:review`) — this mirrors how
   `../evals/fixtures/*/expect.json` invokes the same commands via `claude -p`.
3. `plugin-evals/<name>/scaffold.sh` (if referenced) — plain bash, runs once before
   Claude starts, only with `--scaffold`. Never trust one you didn't author yourself.
4. `plugin-evals/<name>/graders/*.md` — one grader per file. Prefer deterministic
   graders (`tool_used` on the actual `scripts/temper` Bash invocations, `regex` on
   `.temper/evidence/*.json` or the exact documented output strings) over `llm`
   graders wherever the plugin's own contract is exact text or a specific CLI call —
   only reach for `llm` to judge open-ended correctness (e.g., "did the review name
   the actual bug").
