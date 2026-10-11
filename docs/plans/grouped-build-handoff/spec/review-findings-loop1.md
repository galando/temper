# Review findings, loop 1 (Opus review of d6fd10a..HEAD)

The review ledger was cleared by `temper state loop review build`; this file carries the
findings to Build. The user chose: fix everything (high, medium and low). Each fix needs a
deterministic regression case written first (real RED), except doc-only wording fixes.

## HIGH

- H1 scripts/temper:2559 (task gate verdict): task gate takes the FIRST green row of the
  attempt; a later failing green run (the REFACTOR re-run) is ignored and the broken state is
  committed. The verdict must use the LAST run of the attempt: PASS needs a red run, then a
  green run after it, and the final run of the attempt must be green.
- H2 scripts/temper:2565 (changed set): changed files are computed as dirty/untracked vs the
  start snapshot only, never `start_sha..HEAD` of the worktree. A commit made inside the
  worktree hides undeclared files and the gate PASSes. Include committed changes since the
  task's start_sha (minus files of siblings that passed since, as today), and treat any
  commit in the worktree not made by the CLI as a FAIL reason.
- H3 scripts/temper:1756 (plan freshness): tasks.md is re-read live after plan approval; no
  plan-freshness check exists (design.md cites one), and the mod guards Write/Edit only, so a
  Bash edit can swap **Test:** or widen **File:**. Record a hash of the approved grouped plan
  (task blocks: File, Depends, Test; group Validate/Interfaces/Context; Integration) when the
  grouped run starts (first `group start`), and refuse task start/test/gate, group gate and
  integrate when it changed (checkbox ticks by the CLI must not count as a change). Also
  extend the mod's Bash write detection to the run's tasks.md during a grouped run if it is
  a simple, pure-rule change.
- H4 scripts/temper:3038 (glob paths): overlap and schedule compare exact strings while the
  gates use fnmatch (`*` crosses `/`), so `src/*.ts` and `src/a.ts` run in parallel, and a
  glob counts as 1 file for the group blast radius (AC-03, D-01). Decide one rule and apply
  it everywhere: simplest is the plan gate refuses glob characters in **File:** in grouped
  mode (reference/plan.md already says exact paths), and every check compares exact paths.
- H5 scripts/temper:2791 (CLI task commit in the worktree): the commit runs the native
  pre-commit hook in the worktree, which writes an untracked `.temper/gates.json` there
  (probed); the verdict does not skip `.temper/`, so running siblings FAIL as undeclared.
  Make the verdict ignore the worktree's `.temper/` (and `.claude/worktrees/`), and/or keep
  the hook from writing run state inside a worktree; add a case with two parallel tasks
  where one passes and commits first.

## MEDIUM

- M1 scripts/temper:2791: the task-gate commit and the tasks.md tick/untick run outside the
  lock, and the tick is not atomic; parallel gates race on index.lock and can lose a tick.
  Hold the lock around commit + tick, and write tasks.md atomically.
- M2 scripts/temper:2753: FAIL restore leaves undeclared changes in the shared tree; the
  retry snapshot absorbs them, so cleaning them up later FAILs and ignoring them PASSes.
  On FAIL, also remove/restore the undeclared changes the verdict named (only those).
- M3 scripts/temper:2176: group reopen restores Task N's files to its start_sha, which
  reverts a later Depends-ordered task's edits to the same file while that task stays
  passed. Also reopen (or refuse with a clear message naming) the dependent tasks that
  touched the same files after Task N.
- M4 scripts/selftest/temper-cases-5.sh:22: the "Parallel evidence writes lose no rows"
  scenario names task test, but the case runs `evidence add`. Add a case with parallel
  `task test` calls.

## LOW

- L1 scripts/temper:303: lock stale-break race lets two holders in; no trap frees the lock
  on interrupt. Make stale-break safe (e.g. rename-then-remove with an owner token check)
  and add a trap that releases a held lock on EXIT/INT/TERM.
- L2 scripts/temper:1163: evidence resolve/accept and gate verdict writes are still unlocked
  and non-atomic (ADR 0011 says every write). Route them through the locked atomic writers.
- L3 scripts/temper:2639: task start's ready check is outside the lock; concurrent starts
  can exceed max-parallel or overlap. Do the ready check and the start write under one lock.
- L4 scripts/temper:2899: after a suite/interface FAIL in integrate the worktrees are gone
  and group start cannot recreate them (branch exists). Make group start reuse an existing
  group branch, or keep worktrees until integrate PASSes.
- L5 commands/temper.md:336: AC-14 wording; the file gained per-stage usage-add lines (D-07)
  and invariant text (Resolution 1) beyond the launch loop. No code change needed beyond
  keeping it minimal; update intent AC-14 wording note is the orchestrator's job.
- L6 templates/temper.config.default:136: "the only commits it allows" contradicts "always
  checkpoints a wip: commit" in the same block. Reword consistently (also in
  .claude/temper.config, reference/autonomy.md, commands/temper.md if the same phrase).

## Added by the orchestrator during loop 1

- A1 (from the batch A fix of H2): a commit counts as the CLI's when its subject matches
  `feat(slug): Task N … [G]`. A task agent can make a commit with that subject and hide
  undeclared files again. Remove the subject match; trust only shas the CLI recorded, and
  close the gap between the CLI's commit and recording its sha by holding the lock across
  commit + record (with M1) and reading the recorded shas under the same lock in the verdict.
- P1 (pre-existing, found while committing): `temper state loop review build` does not set
  next_stage back to build, so the build-checkpoint commit carve-out of gate commit does not
  apply during a Review->Build loop and Build's fix commits are refused. Make state loop set
  next_stage to the loop's target stage (selftest case).
- P2 (pre-existing): the build-checkpoint carve-out only accepts a green row whose claim
  contains "test"; document this in agents/build.md's evidence example or relax it to any
  green row with a --cmd. Pick the smaller, safer change.
