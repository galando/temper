# Progress of the one pass build

- Branch: `claude/fervent-shannon-gtbnuf`
- Pull request: not opened yet
- Made of: `7c7a1c1` (main, 9.8.4), `10e965a` (pull request 115, the base), `e88f105` (tip of ccr-88156f39-u643ta, plan and kit)
- Watch: one check is scheduled; the next is due 2026-11-16 14:54 UTC
- Bench: allowed by the owner's first message, on this session's own model access; the live smoke too

## Baseline

Tools: bun 1.4.4, node 22.23.4, Python 3.13.18, tsc 6.0.2, Claude Code 2.1.325 (types made with 2.1.287), 4 CPUs.

| Check | Result | Seconds |
|---|---|---|
| `quality-check.sh` | All checks passed | 6 |
| `validate-docs.sh` | PASS 10, FAIL 0 | 0 |
| `validate-readme.sh` | PASS 5, FAIL 0 | 0 |
| `validate-plugin.sh` | PASS 31, FAIL 0 | 1 |
| `validate-panels.py` | pass | 0 |
| `validate-directory.sh` | OK | 4 |
| `selftest/test-validate-directory.sh` | PASS 77, FAIL 0 | 22 |
| `check-mod-calls.sh` | OK, 20 calls | 4 |
| `selftest/test-check-mod-calls.sh` | PASS 24, FAIL 0 | 2 |
| `check-known-limits.sh` | PASS 20, FAIL 0 | 1 |
| `claude plugin test .` | 1774 tests across 40 files, all pass | 37 |
| `claude plugin validate --strict .` | Validation passed | 5 |
| `tsc -p tsconfig.mod.json` (types made with 2.1.287) | no output | 3 |
| `e2e/ab-replay.sh` | 9.8.4 against the base: questions 8, 8, 4; launches 10, 7, 7; agent minutes 191, 92, 92 | 51 |
| selftest, parallel (`run-selftest.sh`) | PASS 2879, FAIL 0 | 882 |
| end to end, `run.ts all` (one process) | 69 mode lines PASS, 23 flows identical, e2e: all passed | 2498 |
| after WP01: case file 6 alone | PASS 114, FAIL 0 (no assertion of case file 5 runs twice) | 278 |
| after WP01: `verify.sh quick` with case file 5 touched | PASS | 811 |
| after WP01: bytes | `view-fixtures.ts` 187,069; `view-fixtures-2.ts` 57,975; `CHANGELOG.md` 109,834; `scripts/temper` and `scripts/flow.py` unchanged | |
| after WP02: `scripts/temper` | 214,545 bytes (45,959 freed); one quoted heredoc left; the capture of 43 states equal to the base | |
| bytes | `scripts/temper` 260,504; `scripts/flow.py` 205,631; `CHANGELOG.md` 246,956; `view-fixtures.ts` 259,060; `view-fixtures-2.ts` 78,629 | |

## Packages

| Id | State | Commit | Date | Note |
|---|---|---|---|---|
| WP00 | done | `2992cad` | 2026-11-16 | baseline green, every number as the kit says |
| WP01 | done | `3f8a47e` | 2026-11-16 | CI in shards with cancel and one gate job, verify.sh, fixtures one view a line, older changelog moved |
| WP02 | done | `a6c5708` | 2026-11-16 | seven modules out of the CLI, output byte equal to the base by the capture of 43 states |
| WP03 | todo | | | |
| WP04 | todo | | | |
| WP05 | todo | | | |
| WP06 | todo | | | |
| WP07 | todo | | | |
| WP08 | todo | | | |
| WP09 | todo | | | |
| WP10 | todo | | | |
| WP18 | todo | | | |
| WP14 | todo | | | |
| WP11 | todo | | | |
| WP12 | todo | | | |
| WP13 | todo | | | |
| WP15 | todo | | | |
| WP16 | todo | | | |
| WP17 | todo | | | |
| WP19 | todo | | | |
| WP20 | todo | | | |
| WP21 | todo | | | |
| WP22 | todo | | | |
| WP23 | todo | | | |
| WP24 | todo | | | |
| WP25 | todo | | | |
| WP26 | todo | | | |
| WP27 | todo | | | |
| WP28 | todo | | | |
| WP29 | todo | | | |
| WP30 | todo | | | |
| WP31 | todo | | | |
| WP32 | todo | | | |

## Phase gates

| Phase | Commit | Date | Result of `full` | Seconds | Expected to fail |
|---|---|---|---|---|---|

## Blockers

None.

## Found on the way

- 2026-11-16 WP00: the first merge of `10e965a` went as a fast forward; both merges were made again with `--no-ff` before any push, so the history shows two merge commits.
- 2026-11-16 WP01: CI check names change: six checks `temper CLI selftest (shard K of 6)`, four `End to end (shard K of 4)`, and two new jobs `Changed files` and `Gate`; a branch rule should require `Gate` alone (for the owner).
- 2026-11-16 WP01: `quick` runs case files 5, 6 and 31 when case file 5 changed, so it takes about 13 minutes then, as contracts section 10 warns.
- 2026-11-16 WP01: the spec gave 259,060 bytes for the two fixture files together; that is `view-fixtures.ts` alone (the two were 337,689). `check-names.py` reads 51 tracked Python files, not 49.
- 2026-11-16 WP01: `run.ts` now exits 2 for an unknown flag or scenario name; before, an unknown name was a FAIL inside the run.
- 2026-11-16 WP02: the capture also differed between runs on the key of `.temper/preflight.json`, a hash over the fixture's HEAD; the capture writes it as fixed text.
- 2026-11-16 WP02: the optional docstrings of step 4 were not written; the room target was met without them.
- 2026-11-16 WP00: the clone was shallow; `git fetch --unshallow origin` made `7c7a1c1` reachable for the replay.
