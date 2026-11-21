# ADR-0022: The acceptance tests keep their own writer

**Status:** Accepted
**Date:** 2026-11-20
**Amends:** ADR-0013 (the actions of Build and Check: no record pass and no Check agent for a criterion with a command)

## Context

The tests that gate the code must be written by an agent that does not write it (rule 7 of the build). Since 9.8.0 an
agent that writes no code writes the acceptance tests from the approved intent and locks them, alone and before the
first builder. The plan of 9.8.5 asked whether that writer could run beside the first builder, to save its launch time,
and the evidence asked a second question: a criterion validated by `code` or `metric` was recorded by an agent. When the
Build gate failed only for such a row, a record pass of the Build agent was launched to write it, and at Check the
Check agent was launched to record those criteria after the CLI's own run. In both a model typed the row that passed
the criterion (finding M9 of the red team).

## Decision

1. **The acceptance writer stays its own agent, alone and first.** `temper:temper-acceptance` is launched before any
   group starts, and no task agent is launched until its lock or the recorded skip exists. Running it beside the first
   builder is not built: it needs a bench arm that shows it earns its place, and the first builders would lose the line
   that points them at the locked tests. A case pins the order.
2. **A `code` or `metric` criterion is a command the CLI runs.** Its Validate line carries, in backticks, a command that
   exits 0 when the criterion holds. The intent gate's row `criteria validate` fails a draft that has none (write the
   command, or use `manual`). The CLI runs the command of an accepted intent when Build ends (`temper integrate`, into
   the Build ledger) and at Check (`temper check run`, into the Check ledger), through the reuse store, as a row of
   phase `criterion` with `executed_by` cli. The gates pass such a criterion only from a row the CLI ran of its own
   command that exited 0.
3. **No record pass and no Check agent for a criterion.** The record pass of the Build agent and the state key
   `record_pass` are removed. With a test command the CLI finds, Check is always `check run` and the gate, with no
   agent. A criterion with no command, as a `manual` one, is the person's to confirm at the Check question.
4. **The approval is of every command a gate will run.** The approval card lists each criterion's command among the
   commands, and the approval binds the intent (ADR-0019), so a command changed after the approval fails the gates
   until it is approved again.

## Amendments

- **ADR-0013**: Build's record pass and the criteria branch of Check's work are gone from the flow; a gate that fails
  for a criterion row nobody ran asks its question.

## Alternatives Considered

### The writer beside the first builder
- **Pros:** less wall time before the first task.
- **Cons:** the first builders start before the tests exist and cannot read them; a builder could see a test change.
- **Why not chosen:** no bench arm has measured it, and the lock order is what shows the writer wrote the tests.

### Keep the record pass, with a stricter brief
- **Pros:** no change to how an intent is written.
- **Cons:** a model still types the row that passes a criterion.
- **Why not chosen:** rule 5: every verdict is computed by the CLI from runs the CLI made or the person confirmed.

## Consequences

- An intent writes a command where it used to write prose; a metric that can only be read after release is `manual`.
- A default run launches no record pass and no Check agent: the launches of a clean run are unchanged.
- With the mod off nothing stops another agent from typing the lock call: the launch order is what the case pins.
