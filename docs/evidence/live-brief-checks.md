# The 9.8.4 brief instructions with live models (2026-11-12)

The CLI side of every 9.8.4 change has unit and end to end tests with scripted agents. These runs check the other side:
that real agents follow the new brief instructions. The 18 runs of `haiku-sonnet-task-agents.md` never reached them
(the simulated person never asked for a fresh review, and no group failed its check), so these runs force each path.

## Setup

- `bench/run.mjs` through the Agent SDK, the simulated person of `bench/person.mjs` (the recommended option, never a skip,
  an override or Save for later).
- **Fresh review:** `partial-payments`, 2 runs, `--config-yaml 'plan:\n  fresh-review: always'`. Plan rated it risk H,
  so two reviewers (A and B) ran each round, on Sonnet.
- **Group fix and blocked task:** a prepared pyjokes project entered at `/temper:build` with an accepted intent and an
  approved plan that holds two defects: G1's Validate runs a test that every public name of `pyjokes.core` is exported,
  which no task's cases mention (the group check fails after its tasks pass), and Task 2 of G2 needs the category lookup
  in `pyjokes/core.py`, a file only Task 1 declares. 2 runs, task agents on Haiku (`--task-model haiku`).

## What the agents did

| Path | Run | What happened |
|---|---|---|
| Fresh review, round 1 | both | Every reviewer ran the four lenses (`tests` included) and recorded the four completion rows. |
| A high finding | run 2 | Reviewer A raised one high readiness finding; the plan gate failed and recommended Revise the plan; the Plan agent got the finding in its prompt. |
| Recheck round | both | Round 2 was a recheck: the prompt listed the earlier findings (7 and 6) and the changed blocks; the reviewers recorded `fresh review completed: recheck` with that count, raised no new high finding, and re-recorded the medium and low ones they did not see fixed. Run 2's recheck found the high fixed and the gate passed. |
| Task blocked | pyjokes run 1 | Task 2's Haiku agent ran `temper task blocked 2 --needs pyjokes/core.py --reason ...`, gated the task and stopped. The group parked at once (no retry, no escalation), and the question named the file, the task that declares it and why, with Loop back to Plan recommended. |
| Loop back to Plan | pyjokes run 1 | The Plan agent got the loop back and its reason, and replanned. |
| Group fix | pyjokes run 1 | After the replan, G1 failed its check after every task passed. The question showed the FAIL line and recommended Fix the group's merged work; one Sonnet fix agent worked in the group's worktree, the CLI committed its work, and the group passed. |
| A dodge | pyjokes run 2 | Task 2's Haiku agent kept to its file and made the joke table itself case and space insensitive, so it needed no block. Legal, and the hidden tests pass. |

Every run passed every hidden test (26 of 26 in both `partial-payments` runs; the pyjokes hidden tests 4 of 4 in both,
checked by hand: the grader's hidden runner did not load the prepared task's folder, and its "original suite" check runs
the old empty list test that this feature changes on purpose).

## What it found

**An empty recheck round.** In both `partial-payments` runs a recheck round was launched with "Changed task blocks: none",
once with no earlier finding at all to check. The cause: the person's answer to the Context check writes `reviewed:
human` and the answer into plan.md's Context Map, and that changed the digest the fresh review compares. Fixed: the
digest leaves out plan.md's Context Map section (an answer that changes the plan sends Plan back, which changes the
task blocks). Case: `temper-cases-20.sh`, "the person's Context check answer does not make the fresh review stale".

## A second pass: the paths the first one did not reach

- **A task that cannot dodge the block** (2 runs, Haiku): a prepared pyjokes plan whose Task 2 needs a `limit` keyword on
  `get_jokes` in `pyjokes/core.py`, which only Task 1 declares. In both runs Task 2's Haiku agent ran `temper task
  blocked 2 --needs pyjokes/core.py` with the reason, gated once and stopped: no retry, no escalation. The group parked,
  the question named the file, Task 1 and the reason, and recommended Loop back to Plan; Plan replanned, Build finished,
  and the hidden tests passed 4 of 4 in both runs.
- **The Intent agent on a loop back** (live Sonnet, `temper:temper-intent`, the CLI's prompt after `state loop plan intent`
  with a reason). It revised AC-01 for exactly that reason, recorded a Decision and kept the rest. It also set the Status
  back to draft, removed the old Accepted-by line and removed Plan's scenarios (a draft holds none), where the brief said
  to leave the Status as it was. Its way is the honest one: the old acceptance was of other wording, the person accepts
  the revision at the Intent question (the CLI's `intent accept` then wrote a new Accepted-by), and Plan, which runs
  again, writes the scenarios again. The brief now says so. The run then went on: the Intent question, Continue, and a
  Plan agent prompt with `Earlier loop back from Plan to Intent` and the reason.

## The lost ledger rows on CI (L1, M4)

A synthetic case reproduces a way to lose a row: a lock folder with no owner line yet (a holder stalled between its
`mkdir` and its owner line) is written past after the wait, while that holder is alive. Closing it (wait for an
ownerless lock until it is stale) broke six cases that state the CLI's design on purpose: an ownerless lock is a
foreign one, the CLI fails open after the wait with a WARN and never releases it, so a stuck holder never wedges a run.
That is a decision for the owner, not for this change, so the change was reverted. Two ways out keep fail open for a
foreign lock: write the owner line before the lock folder appears (make the folder under another name with its owner
inside, then rename it into place), so a Temper holder is never ownerless; or wait longer than 2 s before treating an
ownerless lock as foreign. Neither is proven to be the CI cause.
