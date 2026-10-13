# Measuring Temper

Temper claims that a run catches defects and that the person decides every gate. These fixtures
and this protocol measure both on real Claude Code sessions. The results are in
[results.md](results.md), one row per run; a run that did not happen has no row.

## Why it is built this way

The seeded defect evals of 7.0 were removed in 9.5.0 ([ADR 0010](../docs/decisions/0010-remove-eval-fixtures-and-share-plan-review.md))
because their CI job needed a repository secret nobody set, so it never ran and still looked like
assurance. This suite avoids that:

- **No job depends on a secret.** The runs are made on demand by a person with their own login.
  What CI can check with nothing to configure, it checks: the self test builds every fixture,
  proves each planted defect with its hidden test and its reference fix, and runs the scorer on a
  recorded run (`scripts/selftest/temper-cases-evals.sh`).
- **No answer in the project.** The answer key (`fixture.json`), the hidden test and the reference
  fix stay in this folder; `make-fixture.sh` never copies them, and no comment in a fixture names
  the defect. The 7.0 fixtures labeled their defect in comments the reviewer could read.
- **Caught means a test, not a word.** "Fixed at end" is the hidden test passing on the project as
  the run left it. Review and Check are scored from the ledger and the gate rows the CLI wrote.
- **Not `claude plugin eval`.** Claude Code's eval runner has no grader that runs code (so a hidden
  test cannot score a run without the agent seeing it), its scaffold script gets no plugin path,
  and its sessions cannot answer a gate dialog. The runs below use `claude` directly.

## The fixtures

| Fixture | Kind | The planted defect | Who should catch it |
|---|---|---|---|
| `jokes` | full run | `all_jokes()` in the base code drops the last joke; the feature (`list_jokes(n)`) is asked to build on it | Build's tests, Review, or Check |
| `orders` | review | `find_order` calls `orders.find(...)`, a method Python lists do not have; no test calls it | Review; Check (untraced scenarios) |
| `reset` | review | the hourly limit of the intent (AC-03) is not implemented and has no test | Check (untraced scenario); Review |
| `search` | review | `search_notes` builds its SQL with a Python f string (injection); the tests pass | Review only |

Each fixture folder holds `base/` (the project), for a review fixture `spec/` (the accepted
intent, plan and tasks) and `change/` (the change under review), `hidden/` (the hidden test),
`fix/` (the reference fix) and `fixture.json` (the answer key). The projects use Python's
standard library only (`unittest`), and set `check.coverage-threshold: 0` because no coverage
tool is assumed on the machine.

## Run 1: unattended Review and Check (the review fixtures)

```
bash evals/run.sh orders --label "what this run measures" --append
```

It builds the fixture with the run already at Review (`make-fixture.sh --at-review`: the CLI runs
the Intent and Plan gates, and Build is skipped with a recorded reason, since the change is
given), runs the Review brief and then the Check brief, each as its own `claude -p` session with
this checkout loaded, and runs each gate. A Review FAIL is skipped with a recorded reason, so
Check runs on the same change. No gate question is asked, so this run measures what Review and
Check find, not the flow. `--plugin DIR` loads another checkout, for example the commit before a
change, to compare.

## Run 2: the whole flow, a person answering (the `jokes` fixture)

1. Build the project, in a folder that does not exist yet:
   `bash <checkout>/evals/make-fixture.sh jokes ~/temper-try/jokes`
   (`--autonomy` writes `autonomy.enabled: true` into its `.claude/temper.config`).
2. Start Claude Code there with this checkout as the plugin:
   `cd ~/temper-try/jokes && claude --plugin-dir <checkout>`
   A synced or installed copy of Temper is shadowed by the `--plugin-dir` copy (Claude Code says
   so in its debug log).
3. Type the feature from `fixtures/jokes/fixture.json`:
   `/temper:temper "Add list_jokes(n) to jokes.py: it returns the first n jokes of all_jokes(), and every joke when n is larger than the list."`
4. Answer every dialog as you would on real work, with one rule for the end: at the Commit
   question choose **Save for later**, so the run's ledger stays for the scorer. Write down any
   gate you expected and did not get, and any answer that was not followed.
5. Quit Claude Code, then score the run with its transcript (Claude Code keeps it in
   `~/.claude/projects/<the project folder with each / as ->/<session id>.jsonl`):
   `python3 <checkout>/evals/score.py run jokes ~/temper-try/jokes --transcript <that file> --label "what this run measures" --append <checkout>/evals/results.md`

The scorer counts the `Temper gate` questions asked and every CLI call that moves the run or
decides for the person (`state advance`, `state loop`, `override`, `evidence accept`, keeping an
agent's commits), and reports each move that came with no gate answer since the move before. An
armed autonomous run makes its own moves after the plan gate; those are not counted.

## Comparing two versions

Run the same fixture on both checkouts (`--plugin` for Run 1, `--plugin-dir` for Run 2) and
compare the rows. One run per fixture is a sample of one: a difference smaller than the spread of
two runs of the same version is noise.
