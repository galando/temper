# Wiring smoke test — not a seeded-defect fixture

Unlike `evals/fixtures/*`, this project has no planted bug and `run-wiring-smoke.sh`
reports no CAUGHT/MISSED verdict. Its only job: prove that when a real model runs
`/temper:plan`, `/temper:build`, and `/temper:eval` standalone, each stage actually
calls `temper evidence add` / `temper gate <stage>` for real — not that the CLI's own
gate logic is correct (`scripts/tests/test-temper.sh` already proves that in isolation),
but that the *prompts* actually drive the model to invoke it.

This exists because the exact failure mode it guards against already happened once:
verification pass 3 of v7.0.0 found the standalone `/temper:plan`/`/temper:build`/
`/temper:review`/`/temper:check`/`/temper:eval` commands never called the CLI at all —
and only running them for real, not synthetic unit tests, surfaced it.
`review`/`check` are already covered live by `evals/fixtures/{orders-api,notifications,
password-reset}`; this fixture covers what was left: `plan`, `build`, `eval`.

Run: `bash evals/run-wiring-smoke.sh`. Full explanation: `evals/README.md`.
