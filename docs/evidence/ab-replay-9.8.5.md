# A/B replay: 9.8.4 against 9.8.5 on the measured run's faults

**Reproduce:** `bash scripts/e2e/ab-replay.sh` (base `7c7a1c1`, 9.8.4). It needs bun and takes about two minutes.

## What is replayed

`scripts/e2e/replay.ts` builds a mock project with the faults of the measured run (a Java 24 Maven backend, 12 tasks,
3.2 hours of agent time), with fake `mvn`, `java` and Postgres programs that log every call:

- the Maven enforcer needs JDK `[24,)`; the shell has 21;
- `backend/pom.xml` binds a JaCoCo `check` with a BUNDLE rule, and the plan's group Validate is a filtered verify
  (`mvn verify -Dtest='*Test' -DskipITs`), which can never meet it;
- the integration tests need Postgres, which is down at the start;
- Review finds one High defect that breaks a constraint of the intent;
- the project ships `scripts/ensure-jdk24.sh --export` and a test that reads `IT_POSTGRES_PORT`, as the real one does.

The real CLI of each version runs. The agents are scripted (they write what a stage agent writes, and follow their own
version's brief); the person takes the recommended option of every question. Before each answer and each agent launch
the person reads what ran since they last looked; when a run failed on the environment and the version offers no fix,
they repair the shell by hand (export the JDK, start the database), as the person and the orchestrator did in the
measured run. The same rule holds for both versions. Agent minutes are estimated from the measured run's own agent
times per launch (Plan 12, a Build task 25, a Build fix pass 40, Review 3, Intent 1, Acceptance 8).

## Result

|                          | 9.8.4 | 9.8.5 | 9.8.5 with `autonomy.policy: decide` |
|--------------------------|------:|------:|------:|
| shipped (committed)      | yes   | yes   | yes   |
| the High defect in the commit | **yes** | no | no |
| questions to the person  | 8     | 8     | **4** |
| repairs of the shell by hand | 2 | 0     | 0     |
| setup block, one click   | -     | 1     | 1     |
| agent launches           | 10    | 7     | 7     |
| agent minutes (estimate) | 191   | **92** | 92   |
| loops recommended        | 1 (back to Plan) | 1 (back to Build, the repair) | 0 |

**More accurate.** 9.8.4 committed the High defect: it blocks only on critical findings and recommended "Continue to
Check". 9.8.5 blocks on High, recommends the repair, and the fix pass mends it before the commit.

**Faster.** 9.8.4 found the JDK and the coverage rule only after agent work: a task failed three attempts on the JDK,
two fix agents changed nothing, and a loop back to Plan redid the plan and the tasks. 9.8.5 found both at the plan gate,
before any code: the plan's own gate named the filtered verify, the preflight named the JDK and the database, and one
click added the setup block (checked first on the failing commands). That is 3 fewer agent launches and about half the
agent time.

**Less back and forth.** The question count is the same with the default settings, but the questions differ: 9.8.4's
person also had to find two environment faults in the logs and repair the shell by hand, and saw two group failures
that recommended a fix that could not work. With the policy on, 9.8.5 asks 4 questions: Intent, the setup click, the
plan (where the run is armed), the commit.

## What this does not show

- The agents are scripted. A real model can do better or worse at each step; the replay measures what Temper itself
  decides, recommends and checks, on the same agent behaviour.
- Agent time is an estimate from one measured run's averages, not a measurement of this replay.
- 9.8.5 runs the build tool a few more times (36 against 30): the preflight runs each command once before Build, and
  the setup block is checked on the failing commands. Each of those runs takes seconds; each agent launch it saves takes
  minutes.

## Bugs the replay found in 9.8.5, fixed with cases before this page was written

- `maven filtered verify` told a group's Validate to use `test` or `-Djacoco.skip=true`, both of which the
  `maven group verify` row rejects; it now says to drop the filter (case 21).
- `maven group verify` rejected a pom that binds JaCoCo's check to `verify` with no flag (case 21).
- "Run Build again" stayed recommended forever when the failure text held a growing count (`green=1`, `green=2`):
  failures are now compared without their numbers (case 26). 9.8.4 has the same loop.
