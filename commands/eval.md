---
description: "Behavioral verification — LM-judge + trajectory eval against an eval set"
argument-hint: "[--create] [--trajectory] [<spec>]"
---

# Eval: Behavioral Verification

**Goal:** Judge whether a produced change satisfies its intent, and measure the quality of the tool-call trajectory that produced it.

## Feature: $ARGUMENTS

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/reference/eval.md`

### Quick Reference

1. **Resolve spec + mode** from `$ARGUMENTS`:
   - `--create` → scaffold mode (see below)
   - `--trajectory` → trajectory eval (score the agent's tool-call sequence)
   - default → output eval (score the produced change against the eval set)
   - `<spec>` → `.temper/specs/{spec}/`; omitted → resolve from `.temper/build-state.json`
2. **Load** `{spec_path}/evals/evalset.json` (if absent → emit one-line skip notice, exit 0 — graceful degradation)
3. **Resolve config** from `.claude/temper.config` → `eval:` block (defaults: `enabled: true`, `pass-threshold: 0.75`, `judge-model: tier-fast`, `block-on: [task_success]`)
4. **Dispatch judge** → `eval-judge` skill (cheaper model tier); per-dimension score 0..1 + justification
5. **Fallback** → if judge unavailable/errors, deterministic string/regex over `expected`/`must_not`; mark unscored dimensions `"unscored"` (never zero, never hard-error)
6. **Write** `evals/results/results-{timestamp}.json` + `.temper/eval-context.json`
7. **Report** score table (grouped ARTIFACT/PROCESS, per-row recommended action, partial-aggregate caveat when dims unscored) + aggregate vs `pass_threshold`

### `--create` (scaffold mode)

1. Read `{spec_path}/intent.md` scenarios
2. Derive one eval case per Gherkin scenario (id, input, expected, labels, must_not)
3. Write `evalset.json` from `templates/evalset.json` (5 default rubric dimensions + weights + `category`)
4. Scaffold `evals/results/` dir + `evals/README.md`
5. Mark evalset `"draft": true`

### Modes

| Mode | Flag | Scores | Source |
|------|------|--------|--------|
| Scaffold | `--create` | — (writes evalset) | intent.md scenarios |
| Output eval | (default) | task_success, hallucination, response_quality | produced change vs evalset |
| Trajectory | `--trajectory` | tool_use_quality, trajectory | build-state.json + observability.json |

### Active Skills

- **Eval Judge** — LM-judge per-dimension scoring + deterministic fallback (`$CLAUDE_PLUGIN_ROOT/skills/eval-judge/SKILL.md`)
- **Context Engineering** — load hierarchical context at stage start
- **Temper Core** — config resolution, quality gates

**Graceful degradation:** Missing evalset, disabled config, or unavailable judge model → one-line skip/fallback notice, never a hard error.
