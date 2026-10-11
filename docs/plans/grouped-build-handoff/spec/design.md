# Design: Grouped Build with Haiku task agents (Temper 9.7.0)

**Created:** 2026-10-10
**Complexity:** complex
**Based on:** intent.md (AC-01..AC-15, D-01..D-06), plan.md, tasks.md (Tasks 1-20)

---

## Areas of Concern

Three points need a human call before Build spends anything. Each one names the
conflict, the options and who owns the decision. The design below follows the plan's
current reading (option (a) in each case) so Build can run, but none of these is
decided until the owner confirms it at this gate.

1. **The autonomy invariant says "NEVER commits, pushes, or merges". The plan has the
   CLI make local commits and merges during autonomous runs.**
   `templates/temper.config.default:124` and the shipped `.claude/temper.config` say
   autonomy "NEVER commits, pushes, or merges". intent.md (Constraints) restates this as
   "never commits, pushes, merges to a remote branch". plan.md (Blast Radius, `[warn]`
   row) adds CLI pathspec commits on `temper/{slug}/G{n}` branches (Task 6) and
   `git merge --no-ff` of those branches into the run's feature branch (Task 9), and
   both run unattended when autonomy is armed. ADR 0009 already makes an exception for
   `wip:` checkpoint commits, but it covers no merges.
   Options: (a) change the invariant text to "never pushes, never merges into a remote
   or default branch, never makes the final feature commit". Local commits and merges
   into the run's own feature branch become part of Build, and ADR 0011 records this as
   a second exception next to ADR 0009. (b) Keep the literal invariant: under
   `run_mode autonomous`, `temper integrate` refuses (exit 3, `NEXT: park before
   integration`), so the run parks for a human to run integration. Task commits on
   group branches are allowed either way, because they never touch the feature branch.
   **Owner:** galando (maintainer, owns the autonomy safety invariants in
   `templates/temper.config.default` and `reference/autonomy.md`).

2. **Pack rules apply in the build phase, but the slim task agent loads none of them.**
   `reference/pack.md` says every stage reads the enabled packs whose `phases` include
   the current phase (quality, tdd, security and performance include `build`), and a
   project's own `.claude/packs/` override the built-in ones. AC-05 keeps the task brief
   at 6144 bytes or less and the group context at 4096 bytes or less, so the task agent
   reads no pack files. Plan (Opus) is expected to condense the relevant rules into each
   group's `**Context:**` block (Task 13, Task 14). As a result, a project-local security
   or quality rule reaches a Haiku task only if Plan copied it into the context. The
   group gate, Review and Check still apply the full packs afterwards.
   Options: (a) accept this. The condensed rules go in Context, and Review is where the
   full packs are enforced. reference/plan.md, "Grouped tasks", says Plan MUST copy
   every `security` rule that applies to the group's files. (b) The CLI appends a fixed
   per-task pack digest (rule IDs and one-line summaries, filtered by the task's file
   types) within a new byte budget. This adds a second budget and a parser for the
   pack rules. (c) Grouped mode refuses to start when a project-local pack in `.claude/packs/`
   is enabled for `build`.
   **Owner:** galando (pack policy, `reference/pack.md`), with the security pack's
   owner for project-local security packs.

3. **Running tasks in parallel in one group worktree weakens AC-07's "own RED/GREEN,
   only declared files" claim.** AC-04 lets independent tasks of a group run at the
   same time in the group's shared worktree. The plan chose one tree per group so that
   tasks see each other's committed work. AC-07 requires each task's verdict to rest on
   its own evidence. In a shared tree a task's `task test` can run while a sibling has a
   file half-edited. A sibling's syntax error can then make a correct task's GREEN fail
   (and use up one of its 3 attempts), or let a RED "fail" for the wrong reason. A
   change to a file that a running sibling declared is charged to that sibling
   (plan.md, Risk areas). The disjoint-files rule stops two tasks from writing the same
   file. It does not stop one task's test run from reading another task's unfinished
   file.
   Options: (a) accept it and reduce the risk. reference/plan.md requires each task's
   test to be scoped to the task (its own test file or filter, never the whole suite),
   the whole suite runs only at the group gate and at integration, and the attempt
   record keeps the failure output so a contaminated failure can be seen in
   `group report`. (b) `build.grouped.max-parallel-per-group` defaults to 1: tasks in a
   group run one after another and only groups run in parallel. This is the safest
   choice, but most of the wall-time saving inside a group is lost. (c) Give each task
   its own worktree. The plan rejected this, because sibling tasks would no longer see
   each other's work.
   **Owner:** galando (accepted AC-04 and AC-07 at the intent gate; owns the trade-off).

### Resolutions (user at design gate, 2026-10-10)

- Concern 1 (autonomy invariant): option (a). The invariant is narrowed: autonomy may let the CLI make local commits of a task's declared files on `temper/{slug}/{G}` group branches and the local `temper integrate` merge into the feature branch; it still never pushes, never merges to a remote, never re-plans, and never makes the final feature commit (it always parks). Recorded in ADR 0011 and reference/autonomy.md.
- Concern 2 (packs): option (a). Plan MUST distil the pack rules that apply to each group into that group's Context block, security rules always; Review still checks the full packs.
- Concern 3 (parallel tasks in one worktree): option (a). Each task declares its own scoped test command; the CLI runs it, records its output, and the task gate judges only that; parallelism inside a group stays; the residual attribution risk is documented.

## System Architecture

### Shape of a grouped run

```
 Plan (Opus) ──writes──> tasks.md (groups → Context → tasks with File/Depends)
      │
 temper gate plan  ── grouped rows (parse, budgets, overlap, per-group blast radius)
      │
 Design / approval as today
      │
 Orchestrator loop (commands/temper.md, Stage 2 "Grouped mode", relay only):
   ┌──────────────────────────────────────────────────────────────────────┐
   │ temper group start G   (each group whose Depends groups passed)      │
   │ temper schedule        → JSON lines: ready tasks + model + attempt   │
   │ launch ALL printed tasks as Agent calls in ONE turn (parallel)       │
   │   └ build-task agent (Haiku): task show → edit → task test red/green │
   │ temper task gate N --model --tokens --ms → PASS | FAIL + NEXT: line  │
   │ group complete → temper group gate G → Continue / Change / Stop      │
   │ all groups PASS → temper integrate → temper gate build               │
   └──────────────────────────────────────────────────────────────────────┘
      │
 Review → Check → commit gate (grouped blast-radius row) as today
```

The CLI decides everything that has exactly one correct answer. The orchestrator only
relays: it never computes a ready set, a retry count or a verdict. A task agent never
commits, never edits tasks.md and never runs `task gate`.

### Components

| # | Component | Status | Location | Responsibility | AC |
|---|---|---|---|---|---|
| 1 | Grouped config + model resolution | modified | `scripts/temper` `_grouped_on`, `cmd_model` | `build.mode`, `build.grouped.*`; `model task`, `model task-escalation` | 01, 06 |
| 2 | Write lock + atomic JSON writes | new | `scripts/temper` `_with_lock`, `_json_append`, `_json_set_path` | serialize every `.temper/` write; tmp + `os.replace` | 04 |
| 3 | Grouped parser `_grouped_parse` | new | `scripts/temper` (embedded python) | tasks.md → one JSON model used by every grouped command | 02, 03 |
| 4 | Plan gate grouped rows | modified | `gate_plan` | presence, budgets, Depends graph, overlap, per-group blast radius | 02, 03, 05, 11 |
| 5 | Run store `groups.json` | new | `.temper/groups.json` | groups, tasks, attempts, usage, integration result | 07-12 |
| 6 | Scheduler `temper schedule` | new | `scripts/temper` | ready set | 03, 04 |
| 7 | Group lifecycle `temper group start/gate/reopen/report` | new | `scripts/temper` | worktrees, group verdict, Change, measurement | 04, 09, 12 |
| 8 | Task lifecycle `temper task start/show/test/gate` + retry chain | new | `scripts/temper` | snapshot, payload, CLI-run RED/GREEN, verdict, NEXT | 05, 07, 08 |
| 9 | Integration `temper integrate` + build-gate row | new + modified | `scripts/temper`, `gate_build` | merge, suite, interface check, cleanup | 10 |
| 10 | Commit gate grouped blast radius | modified | `gate_commit` | declared-union rule replaces the count | 11 |
| 11 | Mod: PROTECTED + worktree mapping | modified | `hooks/temper-mod/core/bash.ts`, `rules.ts` | groups.json CLI-only; worktree writes judged by the relative path | 04 |
| 12 | Slim task brief | new | `agents/build-task.md` | Haiku agent ≤ 6144 bytes | 05, 13 |
| 13 | Plan brief / reference / templates | modified | `agents/plan.md`, `reference/plan.md`, `templates/tasks.md`, `templates/temper.config.default` | grouped output format | 02 |
| 14 | Orchestrator launch loop | modified | `commands/temper.md` Stage 2 | relay loop only | 13, 14 |
| 15 | Autonomy + state-schema docs | modified | `reference/autonomy.md`, `reference/orchestrator-patterns.md` | grouped auto-continue, park rules, groups.json schema | 09, 11 |
| 16 | Evidence ledger (`build.json`) | existing | `cmd_evidence_add` | stores CLI-run task rows (extra fields only) | 07 |
| 17 | Checkpoint conditions (ADR 0009) | existing | `gate_commit` carve-out | reused as the CLI's pre-commit check | 07, 10 |
| 18 | Native pre-commit hook | existing | `scripts/guards/install.sh` | unchanged; fails open in worktrees (no run state) | — |
| 19 | Mod plan-file readers | existing | `planfiles.ts` taskBlocks / parseTaskFiles | read grouped tasks.md unchanged (same `### Task N:` / `**File:**`) | 02 |
| 20 | `state clear` / `state archive` | existing (extended) | `scripts/temper` | clear groups.json; archive a `grouped` block | 12 |
| 21 | Docs + ADR | new | `docs/grouped-build.md`, `docs/decisions/0011-grouped-build.md` | guide, AC-12 procedure, decision record | 12 |

Count: **9 new** (2, 3, 5, 6, 7, 8, 9, 12, 21), **8 modified** (1, 4, 10, 11, 13, 14,
15, 20), **4 existing** reused unchanged (16, 17, 18, 19). Test files
(`scripts/selftest/temper-cases-5.sh`, `tests/mod/worktree.test.ts`) are not counted
as components.

### Data flow for one task

1. `temper schedule` reads tasks.md (via `_grouped_parse`) + groups.json, prints the
   task line, and (under the lock) marks nothing. Only `task start` changes state.
2. The orchestrator runs `temper task start N` (status `running`, attempt k,
   `start_sha` = group branch HEAD, snapshot = sha256 of every dirty/untracked path in
   the worktree, `started_at`). It then launches the agent on the `model` field the
   schedule printed.
3. The agent runs `temper task show N` from the **project** folder and edits files under
   the **worktree** path. It records RED and then GREEN with
   `temper task test N --phase red|green -- <cmd>`. The CLI runs `<cmd>` with
   cwd = worktree and appends a ledger row.
4. The agent returns its panel. The orchestrator runs
   `temper task gate N --model M --tokens T --ms D`.
5. The CLI computes the verdict. On PASS it ticks the box, makes a pathspec commit and
   sets status `passed`. On FAIL it restores the files, increments the attempt and
   prints `NEXT:`.

## API Contracts (CLI subcommands)

All new subcommands run `_grouped_on` first. When grouped mode is off they print
`FAIL: grouped mode is off (build.mode)` to stderr, exit 1 and write nothing. Exit codes
follow the CLI convention: 0 = PASS/ok, 1 = FAIL/usage, 3 = refused by a safety check
(`_unsafe_temper_refuse`, a protected branch, a refusal under autonomy).

### temper model task | task-escalation

```
temper model task             → stdout: build.grouped.task-model
                                        else agents/build-task.md frontmatter model
                                        (claude-haiku-5-5)
temper model task-escalation  → stdout: build.grouped.escalation-model else "sonnet"
temper model --all            → the 8 existing lines; + "task=…", "task-escalation=…"
                                 only when grouped is on
Errors: grouped off + `model task` → still resolves (read-only, harmless); never empty
```

`build-task` is NOT added to `AGENT_STAGES`. The task model is resolved by a separate
`_resolve_task_model`, so `model --all` keeps exactly 8 lines when grouped is off
(cases-1:668-670). Task 1's notes say the default is a constant, and Task 13's notes say
it is read from the brief's frontmatter. **The frontmatter is the single source.**
`claude-haiku-5-5` appears in the CLI only as a fallback for when the brief cannot be
read.

### temper gate plan (grouped rows, only when grouped is on)

```
Requirement rows appended (each its own _req):
  "grouped plan"        PASS "2 groups: G1 (4 tasks), G2 (3 tasks)"
  "declared files"      FAIL "Task 2: no declared files"
  "group context"       FAIL "G2: no group context"
  "context budget"      FAIL "G1: context 4210 bytes > 4096"
  "task block budget"   FAIL "Task 5: block 1601 bytes > 1536"
  "dependencies"        FAIL "Depends cycle: Task 3 -> Task 4 -> Task 3" |
                              "Task 6 depends on unknown Task 9"
  "file ownership"      FAIL "file ownership overlap: scripts/a.sh in Task 1 and Task 3"
  "group blast radius"  FAIL "G1 declares 4 files > autonomy.max-blast-radius=3: split the group"
  "integration command" FAIL "no **Integration:** line"
With grouped off: no row added; output byte-identical to 9.6.7.
```

Overlap rule: two tasks *can run together* when neither is a transitive Depends ancestor
of the other. This covers tasks in different groups too, unless one group transitively
depends on the other. Each such pair must declare disjoint file sets. Paths are
compared after normalization (no leading `./`, lower-cased only on case-insensitive file
systems, as `_under_folder` does).

### temper schedule [--json]

```
stdout (one JSON object per line, possibly none):
  {"task":3,"group":"G1","title":"…","worktree":".claude/worktrees/temper-demo-G1",
   "project":"/abs/project","model":"claude-haiku-5-5","attempt":1}
trailing line when nothing is ready but work remains:
  {"waiting":["Task 2 (depends on Task 1)"],"parked":["G2"],"done":false}
when every group has passed its group gate:
  {"done":true,"next":"temper integrate"}
exit 0 always when grouped is on (an empty ready set is not an error)
```

A task is ready when all of these hold:
- its status is `pending`;
- every Depends task has status `passed`;
- its group has a worktree (`group start` has run);
- every Depends group has a PASS group gate;
- its group is not parked;
- its declared files are disjoint from those of every `running` task;
- fewer than `build.grouped.max-parallel` tasks (default 4) are running.

The result is ordered by group, then task number, so it is deterministic.

### temper group start G

```
creates .claude/worktrees/temper-{slug}-{G} on branch temper/{slug}/{G}
base = run feature branch HEAD, with the branches of every Depends group merged in
       (--no-ff; a conflict here → exit 1 "merge conflict: G1 into G3 base in {files}")
writes "/.claude/worktrees/" to $(git rev-parse --git-common-dir)/info/exclude once
groups.json: groups[G] = {status:"running", worktree, branch, base_sha, started_at}
idempotent: existing worktree on the right branch → reused, exit 0
refuses (exit 3): feature branch is main/master/the default branch (git pack rule);
                  a pre-existing path at the worktree location that is not this worktree
```

### temper task start N | show N | test N | gate N

```
task start N
  pre: schedule would offer N. Else exit 1 "Task N is not ready: {reason}"
  sets status running, attempt k, start_sha, snapshot, started_at

task show N  → stdout (≤ 6000 bytes, asserted by cases-5):
  TASK N (group G1, attempt k): {title}
  WORKTREE: /abs/.claude/worktrees/temper-demo-G1     ← edit files here
  PROJECT:  /abs/project                              ← run temper here
  DECLARED FILES: scripts/a.sh, tests/a_test.sh
  --- TASK ---   {verbatim task block}
  --- GROUP CONTEXT ---   {verbatim Context block}
  --- PREVIOUS ATTEMPT ---  {last FAIL reason + first 20 lines of its output, if k > 1}

task test N --phase red|green -- <cmd…>
  runs <cmd> with cwd = worktree, timeout = 600 s; stdout+stderr tee'd, last 4 KB kept
  appends to .temper/evidence/build.json (under lock):
    {stage:"build", kind:"test", phase, exit, claim:"Task N {phase}", task:N,
     group:"G1", attempt:k, executed_by:"cli", ts}
  exit = the command's exit (so the agent sees red as nonzero and green as 0)

task gate N --model M [--tokens T] [--ms D]
  PASS when: a red row (exit≠0) then a later green row (exit 0) exist for (N, attempt k),
             AND changed(N) ⊆ declared(N)
  changed(N) = paths whose hash differs from the snapshot, or that are new since
               start_sha, MINUS paths declared by other tasks that are `running` now
  PASS → tick "- [ ]" under "### Task N" in tasks.md, then
         git -C worktree commit -m "feat({slug}): Task N {title} [{G}]" -- {declared}
         (only after checking the ADR 0009 upstream-gate condition: plan, intent if
         present, design if present all satisfied; else exit 3)
         stdout: "PASS: Task N"  then  "NEXT: schedule"
  FAIL → restore declared(N) from start_sha (checkout tracked; delete new files),
         record the attempt, stdout: "FAIL: {reason}" then exactly one of
           "NEXT: retry Task N on {task model}"        (after attempt 1)
           "NEXT: escalate Task N on {escalation model}" (after attempt 2)
           "NEXT: park group {G}"                       (after attempt 3; group parked)
  exit 0 on PASS, 1 on FAIL
```

FAIL reasons are fixed strings so selftests can match them:
`need a failing run before a passing run for this task and attempt`,
`undeclared change: {path}`, `no green run for this task and attempt`.

### temper group gate G | reopen G --task N… | report [--json]

```
group gate G
  PASS when every task of G is `passed` AND the group's **Validate:** command,
  run by the CLI in the worktree, exits 0 (recorded as a build row tagged group:G)
  stdout "PASS: group G" | "FAIL: {reason}"; groups[G].gate = {verdict, ts}
  sets groups[G].finished_at on PASS (wall time = finished_at − started_at)

group reopen G --task N [--task M] [--feedback ID]
  for each N: in the worktree, git checkout {N's start_sha} -- declared(N), then
      commit "revert({slug}): reopen Task N" (only N's files change)
  untick N, status pending, attempts cleared (history moved to attempts_prior)
  group gate cleared; other tasks untouched

group report [--json]
  {tokens_by_model:{…}, attempts:{"1":[…]}, escalations:n, parked:[…],
   wall_ms_by_group:{…}, build_wall_ms, review_findings_open:n}
```

### temper integrate

```
pre: every group gate PASS; feature branch == run branch; not main/master (exit 3)
1. for G in topological group order: git merge --no-ff temper/{slug}/{G}
     -m "merge({slug}): group {G}"
   conflict → git merge --abort; groups.integration = {verdict:FAIL, group, files};
             exit 1 "merge conflict: {G} in {files}" (feature branch left at last
             clean merge; worktrees KEPT for diagnosis)
2. git worktree remove each group worktree (before any test run: no runner sees copies)
3. run tasks.md **Integration:** command in the project (recorded build row,
   tagged integration)
4. each **Interfaces:** entry `path` — `literal`: fixed-string search in path at HEAD
   missing → FAIL "interface missing: {literal} in {path}"
5. PASS → delete merged branches temper/{slug}/* (git pack: delete after merge);
   groups.integration = {verdict:PASS, ts}
exit 0 PASS, 1 FAIL
```

`gate_build` gains one row when grouped is on: `"integration"`, PASS only when
`groups.integration.verdict == PASS`.

### temper gate commit (grouped, autonomous only)

The `"blast radius"` row is replaced when `_grouped_on`. The rest of the gate is
unchanged.
`changed = base_sha..HEAD ∪ status` (existing computation). Then:
`undeclared = changed − ∪declared − spec-folder paths`.
- PASS `"{n} changed, all declared"`
- FAIL `"changed outside declared files: {first 5}"`

park-on-touch is unchanged.

## Database Changes (run-state files; no SQL)

### `.temper/groups.json` (new, CLI-owned, mod-PROTECTED, cleared by `state clear`)

```json
{
  "version": 1,
  "slug": "demo",
  "feature_branch": "feature/demo",
  "groups": {
    "G1": {
      "status": "pending|running|passed|parked",
      "worktree": ".claude/worktrees/temper-demo-G1",
      "branch": "temper/demo/G1",
      "base_sha": "…", "started_at": "ISO", "finished_at": "ISO|null",
      "gate": {"verdict": "PASS|FAIL", "reason": "…", "ts": "ISO"},
      "parked_reason": "Task 3 failed 3 attempts"
    }
  },
  "tasks": {
    "1": {
      "group": "G1", "status": "pending|running|passed|failed",
      "attempt": 1, "start_sha": "…", "snapshot": {"path": "sha256"},
      "commit": "sha|null",
      "attempts": [
        {"n": 1, "model": "claude-haiku-5-5", "outcome": "FAIL",
         "reason": "undeclared change: scripts/z.sh", "tokens": 2100, "ms": 41000,
         "ts": "ISO"}
      ],
      "attempts_prior": [],
      "feedback": []
    }
  },
  "integration": {"verdict": "PASS|FAIL|null", "group": "G2", "files": [], "ts": "ISO"}
}
```

### Evidence ledger rows (`.temper/evidence/build.json`)

Additive fields only: `task`, `group`, `attempt`, `executed_by: "cli"`. Existing readers
ignore unknown keys. The per-task `gate_build` path does not read them.

### `gate-ledger.json` (state archive)

When groups.json exists, `state archive` adds a `"grouped"` block: the
`group report --json` output plus `task_model` and `escalation_model`.

### Config keys (`.claude/temper.config`)

```yaml
build:
  mode: grouped              # absent | per-task | grouped  (only "grouped" turns it on)
  grouped:
    task-model: claude-haiku-5-5
    escalation-model: sonnet
    max-parallel: 4
```

## Integration Points

| System | Direction | Protocol | Purpose |
|---|---|---|---|
| git (worktree, branch, merge, commit) | outbound from CLI | git CLI, local only | group isolation, task commits, integration; never `push` |
| Claude Code Agent tool | orchestrator → task agent | subagent launch, `model` param | one Haiku launch per scheduled task, all ready tasks in one turn |
| Claude Code `.claude/worktrees/` | shared folder | filesystem | `temper-` prefix avoids collision with `isolation: worktree` copies |
| temper-mod PreToolUse (Write/Edit/Bash) | inbound to every tool call | hook | groups.json protected; worktree writes judged by the relative path |
| Native pre-commit hook | git → CLI | `temper gate commit` | runs on CLI task commits in worktrees: no run state there → fails open (unchanged). Merge commits run no pre-commit hook. The CLI's own ADR 0009 check before every commit and merge replaces it. |
| Agent usage (tokens, duration) | task agent result → orchestrator → CLI | `task gate --tokens --ms` | AC-12 measurement; absent values are recorded as null, never blocking |

## Error Handling Strategy

| Failure | Detected by | Effect | Recovery |
|---|---|---|---|
| Task gate FAIL | `task gate` | files restored to start_sha; attempt++ | NEXT retry → escalate → park (D-03) |
| Group parked | `task gate` attempt 3 | schedule skips the group; other groups continue | interactive: human; autonomy: run parks when nothing else is ready |
| Group gate FAIL (Validate) | `group gate` | group stays `running` | human gate shows the reason; Change → `group reopen` |
| Merge conflict at group start (dependent base) | `group start` | exit 1, no worktree | human; re-plan the group boundary |
| Integration conflict | `integrate` | abort, feature branch at last clean merge, worktrees kept | stops before Review (AC-10); human |
| Integration suite / interface FAIL | `integrate` | gate build FAIL "integration" | Review→Build loop is not entered; human |
| Lock holder crashed | `_with_lock` | stale (> 30 s) lock dir removed | automatic |
| Lock not acquired within 10 s | `_with_lock` | WARN to stderr, write proceeds (fail open) | atomic replace keeps the file valid JSON |
| Agent returns without RED/GREEN | `task gate` | FAIL with fixed reason | normal retry chain |
| Test command hangs | `task test` | killed at 600 s, exit 124 recorded | counts as a red/failed green |

## Decision Log

| Decision | Options Considered | Chosen | Rationale |
|---|---|---|---|
| Who launches task agents | group agent launches its tasks / orchestrator launches all | orchestrator, CLI picks the order | AC-13 (nesting off), AC-03 (scheduling in CLI), bounded orchestrator context (D-05) |
| Worktree management | `isolation: worktree` / CLI-managed per group | CLI per group under `.claude/worktrees/temper-{slug}-{G}` | base must be feature branch; group tasks share a tree; temper must run from main checkout |
| Group context location | separate file / block in tasks.md | `**Context:**` block in tasks.md | three-file spec folder rule; one source for `task show` (D-06) |
| Who commits a task | agent / CLI after verdict | CLI pathspec commit at task-gate PASS | serialized by lock, contains only declared paths, no `index.lock` races |
| Gate for CLI-made commits | rely on native hook / CLI checks itself | CLI checks the ADR 0009 upstream-gate condition before every commit and merge | the native hook fails open in worktrees and does not run on merges; the guardrail invariant "no commit while a gate is FAIL and unoverridden" still holds |
| Concurrency of `.temper/` writes | flock / mkdir lock / none | `mkdir .temper/.lock`, stale after 30 s, fail open after 10 s, tmp + `os.replace` | macOS has no flock; hooks fail open; atomic replace means a reader never sees a truncated file |
| Lock scope | whole command / write only | write only (never while `task test` runs a test) | otherwise parallel tests serialize and the wall-time saving disappears |
| Restore on task FAIL | snapshot contents / git | `git checkout start_sha -- declared`, delete new declared files | declared files are clean at start (previous tasks committed), so git is the store; no content copy |
| Integration order of steps | suite before cleanup / cleanup first | merge → remove worktrees → suite → interfaces | test runners that recurse into `.claude/worktrees/` (plan.md Risk) never see the copies |
| Group branches after merge | keep / delete | delete on integration PASS, keep on FAIL | git pack "Delete branches after merging"; kept for diagnosis on failure |
| Protected branches | allow / refuse | `group start` and `integrate` refuse main/master/default branch | git pack "Never commit directly to main/master" |
| Task model default | CLI constant / brief frontmatter | brief frontmatter (`claude-haiku-5-5`), config overrides | one source, same as `_resolve_model` for stages; resolves the Task 1 vs Task 13 wording |
| `build-task` in `AGENT_STAGES` | add / separate resolver | separate `_resolve_task_model` | keeps `model --all` at 8 lines when grouped is off (AC-01) |
| Ownership overlap scope | within group only / any pair that can run together | any pair not ordered by transitive Depends (tasks or groups) | groups run in parallel too; a cross-group overlap is a guaranteed integration conflict |
| Retry context | fresh / with previous failure | `task show` adds a PREVIOUS ATTEMPT section (≤ 20 lines) | a blind retry repeats the same failure; still inside the budget |
| Commit message format | free / conventional | `feat({slug}): Task N {title} [{G}]`, `merge({slug}): group {G}` | git pack Conventional Commits |

ADR: `docs/decisions/0011-grouped-build.md` was written with this design (Status:
Proposed). It records the architectural choices: orchestrator-launched agents,
CLI-managed worktrees and CLI-made local commits and merges, and the write lock. Task 16
**updates** it (adds D-01..D-06 and sets it to Accepted after the concern 1 decision).
Task 16 does not create it.

## Security Considerations

- **Forged verdicts:** groups.json holds every task verdict. The mod's PROTECTED list
  gains it (`'state'` kind), so a model's Write/Edit or Bash redirect to it is denied. The
  CLI also adds it to `_unsafe_temper_refuse` (symlink refusal), as it already does for
  gates.json.
- **Worktree write mapping (mod, HIGH):** only the prefix
  `.claude/worktrees/temper-{run slug}-G{n}/` is mapped, and the mapped path goes through
  the **same** phaseWriteRule (spec, tests, plan files, added paths). Any other worktree
  prefix, or another run's slug, gets no special handling and is judged as an ordinary
  path, so it is denied as drift. A path containing `..` after the prefix is normalized
  first.
- **Commit gate (HIGH):** the grouped blast-radius row is computed only when
  `_grouped_on`. The declared union comes from tasks.md as approved at the plan gate.
  Declared paths are matched exactly, and the plan gate refuses glob characters in
  `**File:**`. A tasks.md edited after approval is caught by the plan digest the first
  `group start` records: every later grouped command (`group start|gate|reopen`, `task
  start|test|gate`, `integrate`) refuses a changed plan ("the approved plan changed").
  This replaces the earlier idea of reusing gate plan `fresh`.
- **Command execution:** `task test` and `group gate` run commands that come from the
  agent's own arguments or from the approved tasks.md `**Validate:**` and
  `**Integration:**` lines. They run with the developer's own rights in the worktree.
  This is the same exposure as `evidence add --run` today. Nothing reaches a shell
  through `eval`: commands are passed as an argv array after `--`.
- No push, no remote, no network. No secret or credential handling.

## Performance Considerations

- **Per-launch payload:** brief ≤ 6144 + `task show` ≤ ~6000 bytes, about 12 KB,
  instead of about 64 KB. This is the main cost lever (AC-05). It is enforced at plan
  time (budgets) and by selftest (brief size).
- **Parallelism:** bounded by `max-parallel` (default 4) across all groups. The lock is
  held only for JSON writes (milliseconds), never while a test runs.
- **Parser cost:** `_grouped_parse` runs once per CLI call (one python start, about
  50 ms). tasks.md is at most a few tens of KB. No cache: one source, no staleness.
- **Snapshot cost:** `task start` hashes only dirty and untracked paths in the worktree,
  not the whole tree.
- **Worktree cost:** one checkout per group. On a large repo this is disk and I/O
  heavy. docs/grouped-build.md warns about it. `git worktree add` shares the object
  store, so no object copy is made.
