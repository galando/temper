# PR #115, the environment half: review against the owner's goal

Scope: `scripts/preflight.py`, `scripts/doctor.py`, `scripts/run_env.py`, `agents/env.md`, `scripts/maven_loop.py`,
ADR 0018, the related parts of `scripts/flow.py`, `scripts/temper`, `scripts/check_run.py`, `scripts/task_ops.py`,
`scripts/gate_rows.py`, the docs, the config template, and selftest cases 21 to 24, 26 (Q6) and 27.

All paths are relative to `/home/user/temper` at the PR head (`9a01eff`, branch `pr115`). Every fact is marked:
**[code]** read in the code, **[run]** measured or reproduced in a scratch clone or a throwaway project,
**[doc]** only a claim in a doc, **[inferred]** my reasoning.

Experiments live in
`/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-pr-env/` (`repo/` is the clone;
`expA` to `expN` are throwaway projects; `exp/classify.py` is the classifier table). Nothing was written in
`/home/user/temper`.

---

## 0. Verdict

**Not ready to merge as it is.** The single runner with a `setup:` block, the read-only `temper doctor` report, the
SETUP wording at Check and the Maven rows are sound and small. The preflight, the ENV verdict at the task gate and the
path that writes a setup block (`--propose --write`, `--candidate --write`, the environment agent) each have a defect
I could reproduce, and together they add about 1,170 lines of runtime code, 6 config keys, 4 new questions and one new
agent to fix three faults of one Maven project.

The four findings that matter most for the plan:

1. **The preflight runs after Plan, not first.** An environment fault exists before any plan is written, yet it is
   found only after Intent and Plan have been paid for (Plan is about 200 s of Opus, and Plan plus Design are 45% to
   83% of a run's cost, per the bench). The stack's test command is already known to the CLI
   (`scripts/check_run.py:76-144`), so the same check could run in the first seconds of the run.
2. **Outside Maven it protects almost nothing, by design.** Any failure that matches none of 15 text patterns (and is no time-out)
   is classed `needs new code`, which passes the row (`scripts/preflight.py:115`). 24 of 33 representative failures
   from npm, pnpm, Gradle, Go, Rust, .NET, pytest and plain shell pass silently; two were reproduced with real tools on
   this machine.
3. **It does not test the place Build runs in.** The preflight's worktree is under the system temp folder
   (`scripts/preflight.py:191-193`); Build's worktrees are inside the project (`scripts/temper:2380`, `:2957`), and
   Integration runs in the project folder itself (`scripts/temper:3408`). On a Node project the same `npm test` passes
   in Build's place and fails in the preflight's place.
4. **Three paths lead a run into a dead end or weaken a gate**: a code bug that prints `Connection refused` is judged
   ENV and can never be retried; a stored environment fault survives the repair and no option runs the check again; a
   setup block that replaces the test tool with a shell function passes the check and is written into the config the
   mod says only the person changes.

---

## 1. What each piece does, in the order of a run

### 1.1 The setup block and the one runner

| Fact | Evidence | Mark |
|---|---|---|
| `setup:` in `.claude/temper.config` has four keys: `run` (one shell line), `env`, `services`, `tools` | `scripts/run_env.py:76-93`, `templates/temper.config.default:162-171` | code |
| The CLI exports the config path as `TEMPER_SETUP_CONFIG`; the runner removes it from the command's environment | `scripts/temper:94`, `scripts/run_env.py:48` | code |
| `run_env.run_cmd` is the runner. It builds `bash -c "<setup script><command>"`: the run line, then `temper-setup: OK`, then the command, in one shell. A failing line prints `temper-setup: FAIL (exit N)` and exits 125 | `scripts/run_env.py:104-118`, `:183-205` | code, run (selftest 23 passes) |
| The environment is the process environment minus variables whose names look like credentials, plus `PYTHONPATH=<folder>` first, plus `setup.env` (credential names dropped and listed in `dropped`) | `scripts/run_env.py:33-53`, `:83-87`, `:188-189` | code |
| Callers: task tests, group checks, Integration (through `run_cached`), Check's suite and scenario commands, the Maven loop, the preflight | `scripts/task_ops.py:464`, `:488`; `scripts/check_run.py:693-720`; `scripts/maven_loop.py:105`; `scripts/preflight.py:200-202` | code |
| Every agent prompt gets one more line, `Environment setup (...)`, with the run line (masked) and the variables | `scripts/flow.py:443-456` | code |
| No block: the command and the prompt are as before | `scripts/run_env.py:112-113`, `scripts/flow.py:452-453` | code |

### 1.2 The preflight

**When.** It is one row of `temper gate plan`, computed whenever `tasks.md` exists, at every tier
(`scripts/temper:3580`, `:3600-3601`) **[code]**. The plan gate is called:

- by the Plan agent itself before it returns (`agents/plan.md:59-61`: "Run `temper gate plan` yourself before
  returning, and fix any FAIL it reports") **[code]**, so the first preflight runs inside the Opus agent's Bash call;
- as the last `after` call of the Plan agent and of each fresh reviewer (`scripts/flow.py:1382`, `:1307`);
- after the Context check answer (`scripts/flow.py:2311`);
- after "Add the proposed setup block" and after the environment agent (`scripts/flow.py:1199`, `:1220`).

It does **not** run again when Design changes the tasks (`scripts/flow.py:719-725` approves the changed tasks with no
plan gate) or when the person patches a command during Build (`scripts/plan_patch.py` has no reference to it)
**[code]**.

**What it runs.** Each distinct command text, in this order: every group's Validate, every non-manual task's Test, the
Integration line, every scenario `Test:` command of `intent.md` (`scripts/preflight.py:44-61`) **[code]**. A task Test
that starts with `mvn`, `mvnd` or `mvnw` is rewritten as Build rewrites it: offline, the check plugins and the enforcer
skipped, `-Dtest=` made from the task's declared test files (`scripts/preflight.py:199-200`,
`scripts/maven_loop.py:20-22`, `:63-80`) **[code]**. The acceptance tests are not in the list: they are written after
the plan is approved (`scripts/flow.py:1394-1420`) **[code]**.

**In which tree.** One detached worktree of HEAD at `$TMPDIR/temper-preflight-XXXX/base`, shared by all commands in
order, removed after (`scripts/preflight.py:189-210`) **[code]**. No dependency folder is linked into it.

**Limits.** `plan.preflight-timeout` seconds per command, default 300 (`scripts/preflight.py:31`, `:160-163`). There
is no limit on the total and no parallel run (`scripts/preflight.py:198-205`) **[code]**. Build's own limits are 600 s
for a task test and a group check and 3600 s for Integration and scenario tests (`scripts/temper:2441`, `:3053`,
`:3321`, `:3408`) **[code]**.

**Skip.** `plan.preflight-skip: "<reason>"` passes the row and writes one ledger row; `true` with no text fails the
row (`scripts/preflight.py:152-157`, `:128-140`) **[code]**. No commit: the row passes as skipped (`:158-159`).

**The stored result.** `.temper/preflight.json` holds the row, the environment faults and the limit under a key of
`sha256([HEAD sha, command texts, setup block, limit])` (`scripts/preflight.py:143-147`, `:165-182`). `gate plan`
returns the stored row, pass or fail, while the key holds; `temper plan preflight` runs it again
(`scripts/temper:4568-4571`) **[code]**, **[run]** (selftest 22).

### 1.3 How a result is classified: every pattern

`classify` (`scripts/preflight.py:99-115`) calls `env_fault` (`:73-96`). In order **[code]**:

| # | Test | Class and reason | Origin |
|---|---|---|---|
| 1 | exit 0 | passes | any |
| 2 | output has `temper-setup: FAIL` | environment fault: the setup block failed | Temper |
| 3 | exit 124 (the time limit) | environment fault: `time limit N s` (at the task gate and at Check a time-out is the code's: `timeout_is_env=False`) | any |
| 4 | a line ending `which is not in the allowed range <range>` | environment fault: `needs JDK <range> (found <version>)` | Maven enforcer |
| 5 | `Unsupported class file major version` | environment fault | JVM |
| 6 | `release version \d+ not supported` | environment fault | javac |
| 7 | `invalid target release` | environment fault | javac |
| 8 | `Connection refused` (case sensitive) | environment fault | any |
| 9 | `could not connect to server` | environment fault | psql, libpq |
| 10 | exit 127 and `<name>: command not found` where `<name>` is the first word of a segment of the command | environment fault | bash only |
| 11 | `in offline mode` and `Cannot access` | environment fault: a dependency is not cached | Maven |
| 12 | `Rule violated for bundle` | command fault | JaCoCo |
| 13 | `Coverage checks have not been met` | command fault | JaCoCo with Maven |
| 14 | `Unknown lifecycle phase` | command fault | Maven |
| 15 | `Unrecognized option` | command fault | JVM |
| 16 | `unrecognized arguments` | command fault | Python argparse, pytest |
| 17 | `Tests run: N, Failures: 0, Errors: 0 ... BUILD FAILURE` | command fault: the tests pass and the build fails | Maven |
| 18 | a declared file that is not in the worktree is named in the command or the output (or its stem of 4 or more letters is) | needs new code: `<file> is not on the base` | any |
| 19 | **anything else** | **needs new code**, no reason | any |

Only the two fault classes fail the row (`scripts/preflight.py:224`). The row quotes the last 20 lines of each faulty
command plus every `Failed to execute goal` and `Rule violated` line, 240 characters a line (`:118-121`).

Ten of the sixteen fault tests (rows 2 to 17) are Java, Maven or JaCoCo only (4 to 7, 11 to 15, 17). The same rule is used at the task
gate (`scripts/task_ops.py:758-767`) and at Check (`scripts/check_run.py:177-186`, which first reads a project marker
`<script>: SETUP: <reason>`).

### 1.4 An environment fault at the plan gate: propose, check, write

1. The question. When the failed row is `preflight`, its detail says `environment fault`, the config has no `setup:`
   block and `.temper/preflight.json` holds faults, the first option is made by `setup_offer`
   (`scripts/flow.py:693-699`, `:1183-1205`) **[code]**:
   - `Add the proposed setup block (Recommended)` when `doctor.propose` returns a block that did not fail before.
     Calls: `doctor --propose --write`, `plan preflight`, `gate plan`.
   - else `Let an agent find the setup (Recommended)`, once a run (`env_agent` not `tried`). Call:
     `state set env_agent requested`.
   - else nothing: the plain question `Fix the plan, or skip the check?` with Loop back to Intent, Override and
     continue, Grill Me, Save for later (`scripts/flow.py:700-701`).
2. The rules (`doctor.propose`, `scripts/doctor.py:237-383`, one function of 147 lines) **[code]**: the JDK from a
   Maven enforcer or `<java.version>` (root and one folder down), a Gradle toolchain, `.java-version`,
   `.tool-versions`; the project's CI (`ci_facts`, `:119-151`: GitHub Actions `java-version`, `node-version`, job
   services and the variables that point at them, GitLab image tags, devcontainer features); the JDK is set by
   `scripts/ensure-jdk*.sh --export` or a folder of `/usr/lib/jvm`; Compose services when `docker info` answers; CI
   services through `docker run`, else a local Postgres cluster, `redis-server` or `mysqld`; a variable whose name
   matches `*POSTGRES*PORT` found anywhere in the tree (`find_var`, `:73-87`); `. .venv/bin/activate`; Node from
   `/opt`; `nvm use` for an `.nvmrc`.
3. The agent (`agents/env.md`, Sonnet, tools Read, Glob, Grep, Bash, Write). `temper next` returns a `work` action
   with one agent whose `after` calls are `state set env_agent tried`, `usage add`,
   `doctor --candidate <spec>/setup-proposal.yaml --write`, `plan preflight`, `gate plan`
   (`scripts/flow.py:1207-1227`, `:2377-2379`) **[code]**, **[run]** (experiment C).
4. The check (`doctor.checked`, `scripts/doctor.py:457-483`; `preflight.verify`, `scripts/preflight.py:227-243`)
   **[code]**: refuse a block with ` #`; rerun each stored failing command under the candidate on a new worktree of
   HEAD; the block is good when **none of them is an environment fault any more** (a pass, or any other failure). A
   bad block's hash goes into `.temper/setup-tried.json` and is not offered again. A good block is appended to
   `.claude/temper.config` with the comment `added by the person's choice` (`:444-454`); never over an existing block.

### 1.5 During Build and at Check

- **ENV at the task gate.** When the attempt's last run is a failing GREEN, a RED came before, nothing else is wrong
  and `env_fault` finds a reason (a time-out excluded), the verdict is `ENV`: exit 0, no attempt spent, the worktree
  kept, `env_fault` set in `groups.json` (`scripts/task_ops.py:758-767`, `scripts/temper:3128-3132`). `temper next`
  then asks, in every mode, `Check it again (Recommended)` or `Save for later` and nothing else
  (`scripts/flow.py:1729-1731`, `:1857-1871`) **[code]**, **[run]** (selftest 24).
- **A reused pass.** A group check or the Integration suite that passed with the same command and setup on the same
  clean tree is not run again (`scripts/run_env.py:121-180`, `scripts/task_ops.py:464`, `:488`). The store is
  `temper-results.json` in the git folder. No selftest covers it: `grep` finds `run_cached`, `reused` and
  `temper-results` in no case file, although the CHANGELOG says each change has its cases **[run]**.
- **SETUP at Check.** A red suite or acceptance run whose output has the project marker or an environment pattern
  gets a second row `setup fault: <reason>`; the question says SETUP, recommends `Repair the environment and run
  again`, and never recommends a loop back (`scripts/check_run.py:177-186`, `:700-703`, `:728-731`;
  `scripts/flow.py:837-851`, `:1229-1234`). An armed policy run parks (`scripts/flow.py:1176-1177`) **[code]**.

### 1.6 `temper doctor`

`temper doctor` prints three parts and writes nothing (`scripts/doctor.py:504-526`, `scripts/temper:5025`, `:5110`)
**[code]**, **[run]**:

```
Toolchain:   the first version line of each tool of setup.tools, else java, mvn, python3, node, git
Setup block: none | the run line (masked, not run), each variable, each credential name left out
Services:    each setup.services entry: answering | not answering (a TCP connect, 2 s)
```

The default tool list does not follow the stack: on this repository (bash, Python, TypeScript) it lists java and mvn
**[run]**. `--propose` prints `found:` facts and a block; `--propose --write` and `--candidate FILE --write` run the
check of 1.4 and write the config and `.temper/setup-tried.json`, although the help line says "only reads"
(`scripts/temper:5093`).

---

## 2. Correctness and robustness

### 2.1 The pattern classes on other stacks

`exp/classify.py` feeds 33 failure outputs to `preflight.classify`. Rows marked **real** were produced by the real tool
on this machine; the rest are the tools' usual messages typed from memory, so treat those rows as **[inferred]** input
with a **[run]** classification.

| Stack | Failure | What the preflight says | Right answer |
|---|---|---|---|
| npm | no `node_modules` in the worktree: `sh: 1: jest: not found`, exit 127 (**real**, expA) | needs new code, row passes | environment |
| npm | `Cannot find module 'express'` | needs new code | environment |
| npm | `EBADENGINE` (Node too old) | needs new code | environment |
| npm | `Missing script: "tset"` | needs new code | command |
| npm | `connect ECONNREFUSED 127.0.0.1:6379` | needs new code | environment |
| pnpm | `Command "vitest" not found`; `ERR_PNPM_UNSUPPORTED_ENGINE` | needs new code | environment |
| Gradle | `No matching toolchains found` | needs new code | environment |
| Gradle | `No cached version ... available for offline mode` | needs new code | environment |
| Gradle | `Task 'verify' not found` | needs new code | command |
| Gradle | JaCoCo `Rule violated for bundle` | command fault | command (ok) |
| Go | `go.mod requires go >= 1.25 (running go 1.24.7)` | needs new code | environment |
| Go | module proxy not reachable; `connect: connection refused` (lower case) | needs new code | environment |
| Rust | `requires rustc 1.99 or newer`; `--offline` with no cached crate | needs new code | environment |
| Rust | `unexpected argument '--no-such'` | needs new code | command |
| .NET | `A compatible .NET SDK was not found` (exit 145) | needs new code | environment |
| .NET | `dotnet: command not found` (bash, exit 127) | environment fault | environment (ok) |
| pytest | `/usr/local/bin/python3: No module named pytest` (**real**, expK: 12 of 12 task tests) | needs new code, row passes | environment |
| pytest | `ModuleNotFoundError: No module named 'sqlalchemy'` | needs new code | environment |
| pytest | `unrecognized arguments: --cov=src` | command fault | plugin missing (fails the row, wrong word) |
| pytest | psycopg `Connection refused` | environment fault | environment (ok) |
| pytest | asyncpg `[Errno 111] Connect call failed` | needs new code | environment |
| JVM | `PSQLException: Connection to localhost:5432 refused` (first line) | needs new code | environment |
| any | an old test fails on HEAD (the base is red) | needs new code | the person must know |
| Maven | one old class passes, another fails on HEAD | command fault: "the tests pass and the build fails" | red base; the reason is wrong |
| any | `./gradlew: Permission denied` (126), `./x.sh: No such file or directory` (127) | needs new code | command |
| any | `make: *** No rule to make target` | needs new code | command |
| any | a new test file is missing and the log also holds `Connection refused` | environment fault | needs new code (false positive) |
| any | a command over 300 s | environment fault: time limit | slow command, not the environment |

Counts over the 33 inputs of `exp/classify.py` (the table above merges some): 24 are faults that pass the row, 2 are
false positives, 7 are right.

Why: the design uses "positive patterns only" (ADR 0018, decision 2) and the default is the passing class
(`scripts/preflight.py:115`). The ADR rejects the opposite default because "the tests of new code fail on the base by
design" (`docs/decisions/0018-one-declared-environment-and-a-preflight.md:41-44`). That is true of a task's Test and
not of the Integration line, which is the whole suite (`reference/plan.md:331-333`) and must pass on the base. The
code makes no difference between the kinds of command.

### 2.2 The detached worktree

| Question | Finding | Mark |
|---|---|---|
| Where is it? | Under the temp folder, outside the project (`scripts/preflight.py:191-193`). Build's task and group worktrees are at `<project>/.claude/worktrees/...` (`scripts/temper:2380`, `:2957`); Integration and Check run in the project folder (`scripts/temper:3408`, `scripts/check_run.py:693`). | code |
| Node | In Build's place `npm test` passes, because npm and Node look for `node_modules` in the parent folders; in the preflight's place it fails with `jest: not found`. Same commit, same command. | run (expA) |
| Does it fail or take minutes? | Node: it fails in about a second per command and is classed `needs new code`, so the row passes and says nothing (expA: 12.9 s for two commands; I did not split the time, `npx` with no local jest is the likely part). Python with a global pytest: about 0.4 s a command. Maven with an empty local repository: 13.7 s for two commands, online for the plain command and offline for the task test (expD). | run |
| Cold build output | The worktree has no `target/`, `build/`, `obj/` or Cargo `target/`. A Rust, Gradle or large Maven project compiles from nothing; over 300 s that is an "environment fault: time limit". Not measured here (no project of that size on this machine). | inferred |
| A Python `.venv` | Not in the worktree. The rule proposes the relative line `. .venv/bin/activate`, which fails in every worktree, the preflight's and Build's (`scripts/doctor.py:354-358`). | run (expB) |
| Submodules, LFS files, ignored `.env` files | A git worktree has none of them. Build's worktrees have the same gap, and the preflight would show it only through a pattern. | inferred |
| An ended gate call | Ending the gate at 3 s (as a tool time limit does) left the worktree registered, the plan's command still running (it has its own session, `scripts/run_env.py:191-192`), and no stored result. | run (expJ) |
| Cost when nothing is wrong | Every distinct command runs once more on a cold tree: the whole suite (Integration), each group check, each task test, each scenario test. 14 trivial commands took 0.27 s (expK); the worst case is the number of commands times 300 s with no total limit. | run, code |

The ADR's reason for the worktree is that "a dirty-folder pass can hide a Build failure"
(`docs/decisions/0018-...md:46-49`). The price is that the check runs in a place no later stage uses.

### 2.3 The cache key

Key: HEAD sha, the command texts, the setup block, the limit (`scripts/preflight.py:143-147`) **[code]**.

- **A failure is stored like a pass** (`scripts/preflight.py:167-171` returns `kept["row"]` whatever it holds). After
  the person starts the database, `gate plan` still returns the stored fault; only `temper plan preflight` runs it
  again **[run]** (expE). `run_cached` does the opposite and keeps only passes (`scripts/run_env.py:164`, `:168`).
- **One key for the whole list.** Changing one task's Test line runs every command again, the Integration suite
  included. Each Plan pass that edits a command pays the whole preflight (a bad run had 5 Plan passes) **[code]**.
- **HEAD, not the tree.** Temper's own commits of the spec move HEAD (`scripts/flow.py:567-571`), so a plan gate after
  a loop back runs everything again even when only spec files changed **[code]**.
- **Not in the key:** the toolchain and the services (the doc says so: `docs/commands.md:262-263`), a task's declared
  files (they shape the Maven `-Dtest=` list), the plugin version (the patterns) **[code]**.
- **The reused pass** (`run_cached`) keys on the tree hash, the command and the setup, and skips a dirty tree. It does
  not see git-ignored inputs: after an ignored dependency folder broke, the command was reported as passed without
  running, while a real run failed **[run]** (expH). Check runs the suite for real (`scripts/check_run.py:693`), which
  bounds the harm.
- `.temper/preflight.json` and `.temper/setup-tried.json` are not removed by `state init` or archive
  (`scripts/temper:733`, `:1448`), so a block that failed once is never offered again in that project **[code]**.

### 2.4 Trust: the project's commands run before the person approved the plan

- The ADR lists it as a negative consequence (`docs/decisions/0018-...md:60`) **[doc]**.
- The commands are text the Plan agent wrote in `tasks.md` and `intent.md`; `gate plan` runs them through `bash -c`
  with the person's rights. The worktree is no sandbox: the selftest's own command writes outside it
  (`scripts/selftest/temper-cases-22.sh:59`) **[code]**.
- What limits the harm: credential-named variables are not in the command's environment
  (`scripts/run_env.py:43-53`). Files (`~/.ssh`, `.env`) are readable as before.
- The Plan agent already has Bash (`agents/plan.md:1-5` has no `tools:` line), so this is not a new power for that
  agent. What is new: the CLI, whose verdicts are meant to be deterministic, now runs model-written lines before any
  person saw them, and any caller of `temper gate plan` or `temper plan preflight` runs them **[inferred]**.
- The setup block is the larger trust matter. It is one shell line that runs before every command of every gate, and
  it can be added without the person seeing it (5.2 and 5.3 below).

### 2.5 Secrets

| Fact | Evidence | Mark |
|---|---|---|
| A credential-named variable in `setup.env` is dropped, but the same value set in the `run:` line reaches the command (`password=hunter2` printed) | `scripts/run_env.py:83-87`, `:104-118` | run |
| The run line is stored as plain text in `.claude/temper.config`, a file projects usually commit | `scripts/doctor.py:444-454` | code |
| `mask()` works on names only: `mysql -uroot -psecret` and `DATABASE_URL=postgres://app:hunter2@...` are shown whole in every agent prompt and in `doctor` | `scripts/run_env.py:96-99`, `scripts/flow.py:455-456` | run |
| A masked assignment is handed to agents as a line to run: `export PGPASSWORD=<left out> && ...`, which bash reads as a redirect from a file named `left` | `scripts/flow.py:455-456` | run (the text), inferred (the effect) |
| The name rule also drops harmless names (`PRIMARY_KEY_COLUMN` counts as a credential) | `scripts/run_env.py:33` | run |
| Up to 20 output lines of every faulty command go into `gates.json`, `view.json`, `preflight.json` and the question text; a connection string in an error would be there too | `scripts/preflight.py:118-121`, `:213-224` | code |

### 2.6 Shell quoting

- The `image:` text of a CI service goes into the proposed run line unquoted (`scripts/doctor.py:178`, `:314-315`). A
  workflow with `image: postgres:16;touch${IFS}INJECTED` gave a run line that created the file when run **[run]**
  (expG). The person sees the line in the option's description; the severity is low, the fix is one `shlex.quote`.
- `JAVA_HOME=%s`, the `ensure-jdk` path and the Compose path are unquoted too (`scripts/doctor.py:278`, `:285`,
  `:300`); a space in a path breaks the line **[code]**.
- ` #` in a block is refused because the config reader cuts there (`scripts/doctor.py:461-463`); `true # note` was read
  as `true` **[run]**.
- The config reader turns number-like values into numbers and back: `PYTHON_VERSION: 3.10` reaches the command as
  `3.1`, `GO_VERSION: 1.20` as `1.2`, `APP_PORT: 08080` as `8080` (`scripts/config_yaml.py:38-41`,
  `scripts/run_env.py:72-73`, `:87`) **[run]**.
- The flow quotes the draft path with `shlex.quote` (`scripts/flow.py:1225`) **[code]**.

---

## 3. Does it close the class "found only after agent work"?

For the three faults of the measured Maven run, yes: the JDK range (pattern 4, plus a proposed block), the filtered
`verify` under a JaCoCo bundle rule (patterns 12, 13 and the static row `maven filtered verify`,
`scripts/gate_rows.py:158-191`), and Maven after `cd backend &&` (`scripts/maven_loop.py:36-50`) **[code]**,
**[run]** (selftest 21, 22).

For the class as a whole, no. What it still misses before Build:

| Fault that exists before Build | Caught? | Why |
|---|---|---|
| A toolchain of the wrong version outside the JVM (Node, Go, Rust, Python, .NET) | no | no pattern; the default class passes |
| Dependencies not installed (node_modules, a Python package, Go modules, crates) | no | same; and the worktree is in another place than Build's |
| A database or cache that is down, when the client words it otherwise (`ECONNREFUSED`, `connection refused`, asyncpg, the JDBC first line) | no | pattern 8 is one case-sensitive phrase |
| A misspelled script, target, task or flag outside Maven and argparse | no | no pattern |
| A suite that is already red on HEAD | no (Maven: yes, with the wrong reason) | the default class |
| A slow suite | partly | caught as an "environment fault", against 300 s, while Build allows 600 s and 3600 s; the remedy offered is a setup block or the environment agent (expC) |
| A flaky test | no | one run; a failure is then stored, a pass is later reused |
| A wrong acceptance test | no | written after the plan gate (`scripts/flow.py:1394-1420`), not in the command list |
| An interface no task builds, a scenario traced to the wrong task | no | not run-time faults of the base; outside this half |
| A command changed after the plan gate (by Design, by `plan patch`) | no | no preflight after those (`scripts/flow.py:719-725`, `scripts/plan_patch.py`) |
| A fault that shows only with the new code (a task test that names the wrong path, a missing fixture) | no | a task's Test cannot pass on the base, so its run says nothing but "needs new code" |

On the last row: for N tasks the preflight spends N runs whose result is known in advance. An environment fault is a
property of the toolchain, not of a command, so the first command shows it.

---

## 4. What it adds, and a simpler design

### 4.1 Size

| Kind | Amount | Evidence |
|---|---|---|
| Runtime code | about 1,170 lines: `preflight.py` 255, `doctor.py` 530, `run_env.py` +151, `gate_rows.py` +39, `maven_loop.py` +27, `check_run.py` +25, about 110 in `flow.py`, about 20 in `scripts/temper`, about 10 in `task_ops.py` | `git diff --numstat origin/main...HEAD` |
| Agent text | `agents/env.md` 70 lines; `agents/plan.md` +8; `agents/build-task.md` +3 | same |
| Tests | 338 lines in cases 21, 22, 23, 24, 27 (79 assertions with case 26; all pass in 43 s in the clone) | run |
| Config keys | 6: `plan.preflight-timeout`, `plan.preflight-skip`, `setup.run`, `setup.env`, `setup.services`, `setup.tools` | `templates/temper.config.default:108-110`, `:162-171` |
| CLI | 2 commands in 5 forms: `temper doctor`, `doctor --propose`, `--propose --write`, `--candidate FILE [--write]`, `temper plan preflight` | `scripts/temper:4568-4571`, `:5025` |
| State | `.temper/preflight.json`, `.temper/setup-tried.json`, `<spec>/setup-proposal.yaml`, `<git folder>/temper-results.json`, the state key `env_agent`, `env_fault` in `groups.json`, the ledger rows `preflight skipped:` and `setup fault:` | sections 1.2 to 1.5 |
| Questions | 4 new: add the proposed block; let an agent find the setup; ENV at a task (check it again); SETUP at Check | `scripts/flow.py:693-699`, `:1200-1204`, `:1857-1871`, `:837-851` |
| Agents | 1 new (temper-env, Sonnet) | `agents/env.md:1-6` |
| Words a user meets | setup block, preflight, four classes, doctor, propose, candidate, environment agent, ENV, SETUP, skip reason, reused | docs |

No number exists for what it costs or saves: `docs/evidence/` has no line about the preflight, doctor or the
environment agent, and all 13 commits of the PR are dated 2026-11-15 **[run]** (`grep`, `git log`).

### 4.2 A simpler design with the same protection

1. **One baseline run, at the start of the run, not at the plan gate.** Run the project's whole test command once on
   HEAD (the command `check_run.detect` already finds, or `check.commands.test`), while the Intent and Plan agents
   work, in the place Build uses. The rule is binary: exit 0 or not. On a failure, show the tail and ask once. This
   needs no pattern, works on every stack, also catches a red base, and gives a measured time for the time limits.
   Store it by tree hash, setup block and tool versions, so a second run on the same base costs nothing.
2. **No run of a task's Test on the base.** Check only that the first word of each plan command resolves in the setup
   shell (`command -v`), which takes under a second in total. Keep the static Maven row for the filtered `verify`.
3. **The setup block is found once a project, at `/temper:init` or at the first baseline failure**, shown in the
   question, and written only by the person's answer. No environment agent in the run; when no rule fits, say what
   is missing in plain words.
4. **ENV at a task gate only on a sure sign** (exit 125 from the setup line, a `setup.services` entry that does not
   answer at that moment, the command's own program missing), and always with the option "It is the code: run the
   task again".

This keeps the single runner, the setup block, `temper doctor` and SETUP at Check, and drops the four-class
classifier, the per-command preflight, `--candidate`, `setup-tried.json` and the agent: roughly 500 to 700 lines
less, 3 questions less, 0 new agents **[inferred]**.

---

## 5. Defects I can show

Severity: **A** blocks the merge, **B** should be fixed in this PR, **C** small.

| # | Sev | Defect | Where | Reproduction |
|---|---|---|---|---|
| 5.1 | A | **A code bug judged ENV, with no way out.** A task whose own server never starts fails its GREEN with `Connection refused`. The gate says "failed on the environment, not on the code", spends no attempt, and the only options are `Check it again (Recommended)` and `Save for later`. After "Check it again": the same verdict, 0 attempts spent, status `running`. An armed run stops for the person here too. Before the PR this was a FAIL and a retry. | `scripts/task_ops.py:758-767`, `scripts/preflight.py:34-35`, `scripts/flow.py:1857-1871` | Experiment F, run through the selftest harness in the clone: a RED on an assertion, then a GREEN that prints `[Errno 111] Connection refused` and exits 1. |
| 5.2 | A | **A setup block that fakes the tool passes the check and is written.** "Fixed" means "no longer an environment fault", so any other outcome counts. A draft with `run: toolx() { echo "all good"; }` turned `toolx: command not found` into `passes` and was written with the comment `added by the person's choice`. From then on every CLI-run command that names the tool passes. | `scripts/preflight.py:241-243`, `scripts/doctor.py:467-483`, `:444-454` | expI: `temper doctor --candidate .temper/specs/demo/setup-proposal.yaml --write` printed `check: ok ... now passes` and `OK: the setup block is in .../.claude/temper.config`. |
| 5.3 | A | **The config the mod reserves for the person can be changed through the CLI by anyone.** `doctor ... --write` is not in the mod's person-only list (`hooks/temper-mod/core/rules.ts:476-498`), and the fault list it checks against is an unprotected file. With a hand-written `.temper/preflight.json` (`cmd: false`) a block that replaces `pytest` and `npm` with shell functions was written. The mod's own text says "Only the user changes it while a run is active" (`rules.ts:170-176`). In the agent path the person clicks before the draft exists and never sees it (`scripts/flow.py:1224-1225`), while `agents/env.md:11-12` says a good draft "is offered to the person". No mod test names `doctor`. | `scripts/doctor.py:496-503`, `scripts/preflight.py:231-238` | expM. In the same session a `printf` into `.temper/gates.json` was refused by the mod's hook, and the write of `.temper/preflight.json` was not. Whether the mod lets the call through during a live run was not tried; the rule list is read in code. |
| 5.4 | A | **A slow command is an "environment fault", and the remedy offered is an agent.** With no setup block, a command over the limit leads to the question whose recommended option is `Let an agent find the setup`. That launches a Sonnet agent, then runs the slow command again (verify) and the whole preflight again. The limit is 300 s for every command, while Build allows the Integration suite 3600 s; the Integration line is the whole suite by definition. The plan brief asks for commands under 300 s (`agents/plan.md:103-104`) and also asks a Maven group to validate with a full `mvn verify` (`agents/plan.md:95`). | `scripts/preflight.py:80-81`, `:31`; `scripts/flow.py:1200-1204`; `scripts/temper:3408` | expC: Validate `sleep 4`, `plan.preflight-timeout: 2`. `temper next` gave the agent option first; after `state set env_agent requested` the action was `work` with `temper:temper-env`. |
| 5.5 | A | **A stored fault outlives the repair, and no option checks again.** With a setup block in the config (or nothing to propose), the failed plan question offers Loop back to Intent, Override and continue, Grill Me, Save for later. The person must know `temper plan preflight`, or override the whole plan gate. | `scripts/preflight.py:167-171`, `scripts/flow.py:700-701` | expE (fault, then the marker file made, then the same failed row; `preflight.py run` passes) and expC, part 2 (the options). |
| 5.6 | A | **The preflight runs in another place than Build.** See 2.2: `npm test` passes under `.claude/worktrees/` and fails in the temp worktree. Today the result is hidden by the default class; with any better pattern it becomes a false failure of the plan gate. | `scripts/preflight.py:191-193` | expA. |
| 5.7 | B | **The default class passes real faults.** 12 task tests that fail with `No module named pytest` give `14 command(s): 2 passes, 12 needs new code`, row passes. | `scripts/preflight.py:115` | expK (real interpreter on this machine), expA. |
| 5.8 | B | **The `.venv` rule proposes a line that cannot work.** `. .venv/bin/activate` is relative; the folder is not in any worktree. The person clicks the recommended option, the check fails (`temper-setup: FAIL (exit 1)`), the mod hands the run back to the conversation because the answer's call exited 1 (`hooks/temper-mod/core/driver.ts:319`), and the next question recommends the agent. | `scripts/doctor.py:354-358` | expB. |
| 5.9 | B | **The agent's normal "no draft" result is a failed call.** `agents/env.md:48-50` tells the agent to write no draft when the environment cannot be made here. The `after` call `doctor --candidate <missing file> --write` then exits 1, and the mod's driver hands the run back to the conversation (`driver.ts:432`; the agent has no `gate` call set). | `scripts/doctor.py:499-502`, `scripts/flow.py:1223-1225` | code reading; the exit 1 on a file with no block is selftest 27's own case. |
| 5.10 | B | **The question carries the whole row.** Six commands that fail the same way gave a row detail of 26,010 characters in 127 lines. `flow.py` puts the first three failed rows whole into the question text with no cap; the Plan agent reads the same text when it runs the gate. The same cause is quoted once per command. | `scripts/preflight.py:118-121`, `:213-224`; `scripts/flow.py:583`, `:697-701` | expL. |
| 5.11 | B | **An ended gate call leaves a worktree and a running command, and stores nothing.** No handler for SIGTERM, the result is written only after the last command, and the child has its own session. A foreground Bash call in Claude Code has a 120 s default and a 600 s maximum (the tool's own description in this session); one command may take 300 s. | `scripts/preflight.py:174-182`, `:189-210`; `scripts/run_env.py:191-192` | expJ. |
| 5.12 | B | **The wrong reason on a red Maven base.** One passing class line followed by `BUILD FAILURE` is "the tests pass and the build fails", also when another class failed. | `scripts/preflight.py:109-110` | `classify` on a surefire output with one passing and one failing class. |
| 5.13 | B | **`find_var` calls any mention "the code reads".** On this repository `doctor --propose` proposes to start a local Postgres cluster and set `IT_POSTGRES_PORT`, because a test fixture names that variable. A block is written whole, so one wrong line rides along with a right one, or sinks it. | `scripts/doctor.py:73-87`, `:337-344` | `python3 scripts/doctor.py <clone> .claude/temper.config --propose` in the clone. |
| 5.14 | C | Number-like `setup.env` values are changed (`3.10` to `3.1`). | `scripts/config_yaml.py:38-41`, `scripts/run_env.py:72-73` | section 2.6. |
| 5.15 | C | Shell text from a CI file's `image:` reaches the run line unquoted. | `scripts/doctor.py:178`, `:314-315` | expG. |
| 5.16 | C | The question text is wrong for the agent option: "The project's own files say what it needs: add the proposed setup block (An agent reads ...)". | `scripts/flow.py:697-699` | expC output. |
| 5.17 | C | Doc and code disagree. (a) The docstring of `checked` says that with no stored fault the block "is written, and the output says it was not checked"; the code refuses (`scripts/doctor.py:458-460` against `:474-478`). (b) The help line calls doctor "only reads" (`scripts/temper:5093`); `--write` writes two files. (c) `agents/env.md:44` says `--candidate` without `--write` "prints the block as the CLI reads it"; it prints the raw lines (`scripts/doctor.py:464-466`). (d) The CHANGELOG says each change has cases in files 21 to 30; the reused pass has none. | as cited | reading, `grep`. |
| 5.18 | C | At Check the offer reads the plan stage's stored faults, so it appears only after an overridden plan gate, and then checks the plan's commands, not Check's suite. | `scripts/flow.py:844`, `:1189-1191`, `:1211-1214` | code. |
| 5.19 | C | `setup-tried.json` and `preflight.json` survive `state init`; `env_agent` is tried once a run. A block or an agent that failed for a passing reason is never offered again. | `scripts/temper:733`, `:1448`; `scripts/doctor.py:400-429` | code. |
| 5.20 | C | The skip row is written into the plan ledger outside the CLI's lock, not atomically. | `scripts/preflight.py:128-140` | code. |

---

## 6. Is this half ready to merge?

No. What must change first, in order of weight:

1. **Give the ENV question a way out and narrow the rule** (5.1): add "It is the code: run the task again", and judge
   ENV only on a sure sign.
2. **Make every write of a setup block the person's** (5.2, 5.3): show the exact block in the question, put
   `doctor ... --write` in the mod's person-only list with a test, count a candidate as good only when the command
   passes or fails in a way the base run already showed, and do not read the fault list from a file a session can
   write.
3. **Take the time limit out of the environment class** (5.4): a class of its own, measured against Build's own
   limits, with the remedies "raise the limit", "skip this command", "change the command".
4. **Do not store a failure, and offer "Check again"** (5.5).
5. **Run where Build runs** (5.6): task and group commands in a worktree under `.claude/worktrees/`, Integration and
   scenario commands where integrate runs them.
6. **Make an unexplained failure of the Integration line visible** (5.7): it must pass on the base or the person is
   told once.
7. The small ones that cost a click or an agent: the `.venv` line (5.8), the agent's no-draft exit (5.9), the size of
   the question (5.10), an ended call (5.11).

What can merge as it is: the runner and the setup block (`scripts/run_env.py`; the reused pass says `reused` in its
row, and Check still runs the suite for real), plain `temper doctor`, the banner filter, SETUP at Check, the Maven
rows.

What I would not merge in this form even after the fixes, because a smaller design does the same (4.2): the
four-class classifier, the per-task preflight runs, `--candidate`, the environment agent.

---

## 7. Proposals for the plan, most valuable first

| # | Change | Effect on the goal | Risk | Effort |
|---|---|---|---|---|
| 1 | Check the environment in the first seconds of a run (and at `/temper:init`): one baseline run of the project's own test command on HEAD, in Build's place, while Intent and Plan work; binary result; stored by tree, setup block and tool versions | An environment fault costs seconds instead of Intent plus Plan (about 240 s and most of the run's dollars); no pattern list; a red base is found too; a second run on the same base costs nothing | The baseline costs one suite run per new base; a suite longer than Plan delays the plan question, so it needs a limit and a "go on without it" answer | M |
| 2 | Drop the per-command preflight and the four classes; check only that each plan command's program resolves in the setup shell; keep the static Maven row | Removes N runs whose result is known in advance and about 250 lines; no false "environment fault" on a slow suite | A misspelled flag is found at the first task instead of at the plan gate | S |
| 3 | Make the setup block the person's: shown in the question, written only by their answer, `doctor --write` person-only in the mod; no fault list read from an unprotected file; fix the `.venv` line | Closes 5.2 and 5.3; one question in place of up to three | One more line of text in the question | S |
| 4 | Remove the environment agent from the run; when no rule fits, say what is missing | One agent launch and one question less; removes `--candidate`, `env_agent`, `setup-proposal.yaml` | A project no rule describes needs the person to write three lines once | S |
| 5 | ENV at a task gate only on a sure sign, with the option "It is the code: run the task again" | Removes the dead end of 5.1; an armed run does not stop on a code bug | Some real environment faults spend an attempt again | S |
| 6 | Never store a failed check; add "Check again" to the failed plan question; store per command; end the child on SIGTERM | Removes the dead end of 5.5 and the lost work of 5.11 | none known | S |
| 7 | Decide how Build's worktrees get dependencies (a link to `node_modules`, a shared build cache), then run every check in that same place | Node, Rust and Gradle projects stop paying a cold build per worktree; the baseline means what Build will see | A shared folder can let one task's install change another's | M |
| 8 | Cap and de-duplicate failure text in a row (one quote per cause, 10 lines) | A question of 300 characters instead of 26,000; less Opus input when the Plan agent reads the gate | none known | S |

## 8. Open questions

1. How long does the full suite of the Java project that started this PR take, and did the preflight fit 300 s there?
   The run's spec folder is not in the repository (`docs/decisions/0018-...md:67`).
2. Does the mod let the main session call `temper doctor --candidate FILE --write` during a live run? The rule list
   says it is not person-only; no test covers it; I did not try it in a live run.
3. What does Claude Code do to a subagent's foreground `temper gate plan` that runs past the Bash time limit: end it or
   move it to the background? Either way 5.11 holds, but the cost differs.
4. Has the environment agent run on a real project? There is no time or cost for it in `docs/evidence/`.
5. Should Build's worktrees get the project's dependency folders (a link to `node_modules`, a shared Cargo target
   folder)? The preflight cannot be right before that is decided, and the answer changes Build's own time.
6. Is `.claude/temper.config` meant to be committed? If yes, a machine-specific run line (`/usr/lib/jvm/...`, a
   local Postgres cluster) and any secret in it reach every clone.
