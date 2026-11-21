# A/B replay: 9.8.4, the base and 9.8.5 on the measured run's faults

The replay of one measured bad run, on three versions of Temper: 9.8.4 (`7c7a1c1`, what users have), the base of the
9.8.5 build (`10e965a`, the head of the unmerged pull request #115) and the result, 9.8.5. Printed on 2026-11-21 by
the build of 9.8.5, from the tree of its last package before the final verification.

| | 9.8.4 (`7c7a1c1`) | the base (`10e965a`) | the result (9.8.5) |
|---|---:|---:|---:|
| shipped (committed) | yes | yes | yes |
| the High defect in the commit | **yes** | no | no |
| questions to the person | 10 | 9 | **3** |
| repairs of the shell by hand | 2 | 0 | 0 |
| setup clicks | 0 | 1 | 1 |
| agent launches | 10 | 7 | 7 |
| agent minutes (estimate) | 191 | 92 | 92 |
| loops recommended | 1 | 1 | **0** |
| build tool runs (printed only) | 30 | 36 | 16 |
| CLI seconds with the fake tools (printed only) | 56 | 42 | 46 |

The agent launches by type. 9.8.4: Intent 1, Plan 2, Acceptance 1, a Build task 3, a Build fix pass 2, Review 1. The
base and the result: Intent 1, Plan 1, Acceptance 1, a Build task 1, a Build fix pass 1, Review 2 (the second reads
the repair of the High finding).

Against 9.8.4, one counted number of the result is above it: the setup click, 1 against 0. 9.8.4 has no setup block,
so its person repaired the shell twice by hand instead; every other counted number of the result is at or under 9.8.4.

## Where each column comes from

- The first column is the column `base` of `bash scripts/e2e/ab-replay.sh 7c7a1c1`. It was run with the harness of
  this tree, and its numbers agree with the column of 9.8.4 on this page as the base had it.
- The second column is the column `base` of `bash scripts/e2e/ab-replay.sh 10e965a`. It equals the entry
  `replay_base` of `scripts/e2e/floor.json`, which the script checks itself when its base is `10e965a`.
- The third column is the column `this` of the same call. Its counted numbers equal the entry `replay` of the floor.

Only the compare against the base is a gate (`docs/plans/one-go/done.md`, row D59): `scripts/e2e/replay_compare.py`
exits 1 when a counted number of the result is above the base, when the change was not committed, or when the High
defect is in the commit. The counted numbers are the questions, the repairs by hand, the setup clicks, the agent
launches, the agent minutes and the loops recommended. The build tool runs and the CLI seconds are printed and never
compared: the baseline of the suite adds a run of the build tool on purpose, and the seconds are machine time, which
follow the load of the machine. The column of 9.8.4 is printed and is no gate.

## What is replayed

`scripts/e2e/replay.ts` builds a mock project with the faults of the measured run (a Java 24 Maven backend, 12 tasks,
3.2 hours of agent time), with fake `mvn`, `java` and Postgres programs that log every call:

- the Maven enforcer needs JDK `[24,)`; the shell has 21;
- `backend/pom.xml` binds a JaCoCo `check` with a BUNDLE rule, and the plan's group Validate is a filtered verify
  (`mvn verify -Dtest='*Test' -DskipITs`), which can never meet it;
- the integration tests need Postgres, which is down at the start;
- Review finds one High defect that breaks a constraint of the intent;
- the project ships `scripts/ensure-jdk24.sh --export` and a test that reads `IT_POSTGRES_PORT`, as the real one does.

The real CLI of each version runs, from a throwaway work tree of its commit; the harness, the scripted agents and the
scripted person are those of this tree for every column, so only the CLI under test differs. The agents write what a
stage agent writes. The person takes the recommended option of every question. Before each answer and each agent
launch the person reads what ran since they last looked; when a run failed on the environment and the version offers
no repair, they repair the shell by hand (export the JDK, start the database), as the person and the orchestrator did
in the measured run. Agent minutes are estimated from the measured run's own agent times per launch (Plan 12, a Build
task 25, a Build fix pass 40, Review 3, Intent 1, Acceptance 8).

## How to run it again

```bash
bash scripts/e2e/ab-replay.sh 10e965a              # the base against this tree: exits 1 when this tree is worse
bash scripts/e2e/ab-replay.sh --base-only 10e965a  # the same table; only the base column against the floor counts
bash scripts/e2e/ab-replay.sh 7c7a1c1              # 9.8.4 against this tree, for the first column
```

Each call needs bun, both commits in the clone and a free work tree entry, and takes about a minute. Run one at a
time. `bash scripts/verify.sh full` makes the second call and `bash scripts/verify.sh final` the first.

## What this does not show

- The agents are scripted. A real model can do better or worse at each step; the replay measures what Temper itself
  decides, recommends, launches and checks, on the same agent behaviour.
- Agent time is an estimate from one measured run's averages, not a measurement of this replay.
- The person is scripted too and takes the recommended option of every question, so the count of questions holds for
  that person only.
- It is one fixture: one Maven project with its faults. Another stack, or a fault the mock project lacks, can go
  another way.
