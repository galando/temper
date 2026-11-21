# ADR-0024: What 9.8.5 removed, and what a project that used it does

**Status:** Accepted
**Date:** 2026-11-21
**Amends:** ADR-0006 (review memory as the single finding memory)

## Context

Temper 9.8.4 shipped pieces that no default run reads: six stack packs, three skills no person can call
(`temper-core`, `context-engineering` and `source-driven-development`, each `user-invocable: false` or cited only by a
page), the text of an external review engine (open-code-review, OCR, off by default and read only by an agent through
`config get tools.ocr.mode`), the control bands (`temper bands`, `scripts/bands.py`), the metrics writes
(`temper metrics append`, and the page that told Review and Check to append to `.temper/metrics.json`), review memory
(`.temper/review-memory.json`, written and read only by instructions in the reference pages) and the key
`evidence.claimed-runs`. Each costs bytes in a prompt or lines in the CLI, and none is a step of a run. Before each was
deleted, a search of the agents, the reference pages, the commands and the scripts proved that no run needs it.

`evidence.claimed-runs` was added in 9.8.5 to keep the behaviour of 9.8.4, where a test run an agent only reported with
`temper evidence add --exit N` counted at the Build and Check gates. Its default was `ignore`; only the selftest's own
config set it to `count`.

## Decision

1. **The six stack packs are deleted.** The `Packs:` line the CLI writes into each agent's prompt is the whole list of
   rule files an agent follows. A project that wants stack rules writes a pack of its own in `.claude/packs/<name>` and
   lists it in `packs:`.
2. **Two skills stay listed: `grill-me` and `teach-me`.** A person can call them, and the options of the gates name
   them. The three others are deleted, and the few sentences the pages cited from them are written where they are used:
   the meaning of SUGGEST, WARN and BLOCK in `reference/build.md`, the confidence of a finding in `reference/review.md`,
   the order the stack is detected in in `reference/check.md`, and in the build and fix briefs one sentence: check a
   framework call against the version the project pins before you write it.
3. **No external review engine.** Review runs inside Claude Code, and no diff leaves the machine through Temper.
4. **No control bands and no metrics writes.** `temper bands` and `temper metrics append` are gone: the CLI answers
   either as an unknown command, names `temper --help` and exits 1.
5. **No review memory.** No page tells an agent to read or write `.temper/review-memory.json`. A rejected config
   suggestion is simply not written.
6. **A claim never counts.** A test run counts at a gate only when the CLI ran it (`temper evidence run`, a task test,
   a group check, integrate, Check) or the person confirmed it. `scripts/runs.py` takes no mode, and the key
   `evidence.claimed-runs` is gone: `temper config show` names it as not read.
7. **The eight packs stay shipped**, with the default packs `security` and `tdd`.

## What a project of 9.8.4 does

- A project that kept a stack file in the `stacks` folder of its `.claude/packs`: nothing loads it now. Move its rules into
  a pack of the project (`.claude/packs/<name>/rules.md`) and add the name to `packs:`.
- A test run an agent only claimed with `temper evidence add --exit N` no longer counts at the Build or Check gate,
  and no config key makes it count. Record the run with `temper evidence run --stage <stage> --claim <claim> -- <the
  test command>`, which runs it and records the exit code it saw.
- A config that holds `evidence:` with `claimed-runs`, a `bands:` block or `tools:` with `ocr:` keeps working: the
  lines are not read, `temper config show` names them, and the one time question offers to remove them.
- `.temper/metrics.json` and `.temper/review-memory.json` stay where they are: nothing reads them and nothing deletes
  them. Delete them when you like.
- A scheduler that ran `temper bands` now gets exit 1: remove the job.

## Consequences

- The plugin ships less text that an agent might load: the skills and packs fall from five skills to two, and the
  six stack files are gone.
- A gate counts only what the CLI saw. A selftest case that records a test run uses `ev_red` and `ev_green`
  (`scripts/selftest/case-helpers.sh`), which run `false` or `true` through `temper evidence run`.

## Amendments

- **ADR-0006**: review memory is gone, and with it the single finding memory this record chose. A finding is kept or
  dropped by the person at the Review question (`temper evidence accept`), and nothing learns from past dismissals.
