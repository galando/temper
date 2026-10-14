# ADR-0013: The CLI says what comes next, the guard claims only what it can enforce, the mod only draws

**Status:** Accepted
**Date:** 2026-10-13
**Amends:** ADR-0012 (decisions 1, 5, 6 and 7; see "What changes in ADR-0012")

## Context

ADR-0012 made the CLI the only run state and the question dialog the only place the person decides.
Three things it left in place kept the cost of the flow high:

1. **Two copies of the same logic.** The mod parsed the intent, the plan and the tasks with its own
   code (`criteria.ts` says it follows "the same rules as scripts/acceptance.py"; `clifiles.ts`,
   `planfiles.ts`), and it read each gate answer by parsing the words of option labels that Claude
   wrote from the page text (`gateanswer.ts`). `scripts/check-original-options.sh` existed only to
   keep the pages and the parser in step; an apostrophe broke it twice.
2. **The "what next" lived in prose.** `commands/temper.md` was 6,913 words (about 46,000
   characters), read in the main conversation on every run. Each gate's options, each "On
   Continue" sequence, the autonomy rules and the doors were prose the model had to follow.
3. **A guard that could not be finished.** `core/bash.ts` (1,591 lines) tried to read shell
   commands well enough to stop a model that wanted to get around a gate. Its own header said Bash
   can write files in ways no classifier catches. About two fifths of the mod's 7,851 test lines
   were in files named hardening, security rounds 2 and 3, review exploits 1 to 3, bash,
   structural bash, commit hook and known limits.

The failures that happen in practice are different from the one the guard raced: Claude forgets a
step, words a gate differently, or talks a failed gate away. Four things catch those: the CLI
computes every verdict; the git hook blocks a commit while a gate fails; the gate question goes to
the person; and the mod checks that the person answered before a step only the person may take.

## Decision

1. **`temper next --json` is the one source of "what comes next".** It reads the run and prints
   one action: `none` (no run), `work` (CLI calls to make, stage briefs to launch with their agent
   type, model, prompt and the calls to make before and after each, and the commit steps), `ask` (a
   question with its exact header, question and options; each option names its move, whether it
   needs the person's reason, the reason question, and the exact CLI calls and steps it maps to),
   `wait` (Build tasks still running), `auto` (an armed run's own move) or `broken` (the run state
   does not fit its spec folder). A park is an `auto` call (`temper park`), after which `next` asks
   the gate question again. The orchestrator copies the question and the options exactly as given.
   The page no longer lists any gate's options. The schema is in `docs/flow.md`.
2. **`.temper/view.json` is the one thing the mod reads of the CLI.** The CLI writes it after
   every command that changes the run: a version field, the run, each stage and its mark (passed,
   failed, skipped, here, to come), the status line, the current question (the same `ask` as
   `next`), the plan's files by Build group, the groups and tasks, the findings, the failed checks,
   the acceptance criteria with their evidence, the loops with their reasons, the skips, and time
   and tokens. Its schema is versioned and documented in `docs/flow.md`; a mod that reads an
   unknown version draws nothing and enforces nothing it cannot read (it fails open).
3. **The CLI refuses what it can.** `state advance` refuses to leave a stage whose verdict is a
   FAIL the person did not skip, or one with no verdict, and refuses a next stage that is not the
   run's next. "Talking a failed gate away" then needs an `override`, which the report shows with
   its reason, with the mod or without it. The plan's files are kept by the CLI when the plan is
   approved (`state advance plan_complete ...`), so a `plan.md` edited during Build does not widen
   what Build may write.
4. **The orchestrator is a loop.** `commands/temper.md` runs `temper next --json` and does what it
   says, then asks again. What each stage does stays in its brief in `agents/`. The doors stay doors.
5. **The guard claims only what it can enforce.** It keeps three jobs:
   - a CLI call that only the person may cause (leaving Intent or Plan, a skip, a step back,
     accepting a finding, arming autonomy, keeping an agent's commits, overriding the commit gate,
     starting over during a run) needs the person's answer at the current run and step. The answer
     counts only when it matches, exactly, the header, the question and one option label that the
     CLI wrote for that step; a typed message is never a move. A simple matcher finds the CLI call
     in the command text (the words after `scripts/temper` or `temper`), and the call passes only
     when it is one of the calls that option maps to, word for word (a `{reason}` placeholder stands
     for the person's reason), or one of the calls of the CLI's own action in `view.json` (an armed
     run's move, the commit steps);
   - the file path rules for Write, Edit, MultiEdit and NotebookEdit (the run's own files, the
     config and the git hooks during a run, the plugin data folder, and each stage's writes);
   - a short Bash list: `--no-verify` and `-n` on a commit, a changed `core.hooksPath`, and a write
     into `.temper/`. A Bash write is a redirect, or a program that writes the files it names (`rm`,
     `mv`, `cp`, `tee`, `sed -i` and the like), written out in the command. It is held to the same list
     of protected files as the editing tools: the CLI's files in `.temper/` (a spec file stays
     Claude's to write), and during a run the config and the git hooks.
   `core/shell.ts` reads a command for these: it splits the text into statements and words and
   honours quotes, and follows no variable, substitution output, `cd` or link.
   `core/bash.ts` as a shell parser is deleted, with the lists of git plumbing, aliases and exec
   forms and the tests that existed only for them. Temper is not a sandbox: it keeps a cooperating
   Claude on the path and makes a skip visible; a Claude set on getting around a gate through Bash
   can do it (`docs/trust.md`). The native `pre-commit` hook and the Stop hook stay.
6. **One Build mode: grouped, with Haiku task agents.** `build.mode: per-task` and its loop are
   removed; `agents/build.md` stays as the fix pass when Review or Check loops back to Build. The
   baseline runs (`evals/results.md`, runs A and B) found the Haiku task agents 14 times cheaper
   than the Sonnet agent of per task Build, both first try, and the grouped Build no cheaper in total only
   because the main loop spent about $0.10 more driving the group loop from prose. `temper next`
   computes that loop: it starts the groups whose dependencies passed, hands out the ready tasks
   (`schedule`), gates each task, asks the group question, integrates and gates Build. A group's
   Continue answer is recorded (`temper group continue G`), so `next` knows it was given.
7. **The CLI records what the person approved.** When the run enters Build, `state advance
   plan_complete build` records `base_sha` (the commit the diff is read against) and the plan's
   files. A door into a later stage starts its run with `state init <slug> --enter <stage>`: the
   stages before it are gated and asked, not run again.
8. **The mod reads `view.json` and its own store, and draws.** It parses no file of the CLI's,
   keeps the person's answers stamped with the run and step, and draws the band and the pane from
   `view.json`. The end of run report page is the CLI's (`temper report --html`, written to the spec
   folder before the commit), made from the same file. No drawing decides anything; `uiMode` sets only how much is
   drawn. The game is removed (the person chose to delete it).

## What changes in ADR-0012

- Decision 1 ("the mod reads where the run is ... from the .temper files"): the mod reads only
  `.temper/view.json`. The CLI composes it from those files.
- Decision 5 ("the mod reads the person's answer from the dialog's result"): it still does, but it
  matches the answer exactly against the options the CLI wrote for that step instead of parsing
  words. A move needing a reason counts once the reason is known: the person's note on the option,
  or their answer to the reason question the CLI wrote.
- Decision 6 ("the guard has three jobs, and `core/bash.ts` is frozen"): replaced by decision 5
  above. The jobs "a commit never goes around the native hook" through git exec forms, aliases,
  plumbing and the commits the hook does not check are dropped; they are listed as limits.
  "Every other advance follows the stage's own verdict" moves from the mod to the CLI (decision 3).
- Decision 7 ("every drawing is a plain function of the CLI's files"): every drawing is a plain
  function of `view.json`.

## Consequences

- One parser of each spec file (the CLI's), one list of each gate's options (the CLI's), and no
  sync script between pages and code. `scripts/check-original-options.sh` is removed; the self test
  checks `temper next --json` for every gate instead.
- A question Claude rewords is not an answer: the call it would allow is refused, and the refusal
  says to ask the question exactly as `temper next --json` gives it. This is the failure "Claude
  words a gate differently", caught.
- Without the mod, nothing checks that the person answered, but the CLI still refuses to advance
  past a failed gate without a recorded override, and the native hook still blocks the commit.
- What the guard no longer catches through Bash (a hidden call, a variable, an alias, a git command
  that runs a command, a commit the hook does not see) is listed in `docs/trust.md` and checked by
  `scripts/check-known-limits.sh`, so the docs cannot claim more than the code does.
- The orchestrator page is short enough to read on every run without crowding the work, and the
  main loop's share of a run's tokens (2.57 of 4.34 million cache reads in run A) is the number the
  final measurement compares.
- A plan with one task still runs as a group of one, in its own worktree; there is no lighter path.
