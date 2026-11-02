#!/usr/bin/env bash
# ab-plan-gate.sh OLD_CLI NEW_CLI: the same plan states through two Temper CLIs (docs/evidence/fresh-review.md); one table row per state.
# Example: git worktree add /tmp/t975 f418c65 && bash scripts/e2e/ab-plan-gate.sh /tmp/t975/scripts/temper scripts/temper
OLD="$(realpath "$1")"; NEW="$(realpath "$2")"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; cd "$W" || exit 1
git init -q .; git config user.email t@example.com; git config user.name T
mk() { # a medium plan that passes every 9.7.5 row
  rm -rf .temper .claude; mkdir -p .claude .temper/specs/demo src unit
  printf 'stack: auto\n' > .claude/temper.config
  cat > .temper/specs/demo/intent.md <<'I'
**Status:** accepted
**Complexity:** medium

## Problem
Users cannot do the demo thing.

### Success Criteria
- [ ] AC-01 [required]: demo criterion
  Why: the demo
  Validate: scenario — the scenario below

### Constraints
- none

### Scope and Non-goals
- In scope: the demo
- Out of scope: the rest
- Must keep working: the suite

### Open Questions

### Decisions

## Scenarios (BDD)
```gherkin
Scenario: first
  Given a demo
  When it runs
  Then it works
  Note: unit
  Covers: AC-01
  Test: bash unit/a_test.sh
```

## Source Traceability
### Context Sources
- none: description only
I
  printf '## Context Map\n- use: intent.md - scope\n- reviewed: auto - ok\n\n## Blast Radius\n- none\n\n## Cross-Repo Search\n- not available: none\n' > .temper/specs/demo/plan.md
  cat > .temper/specs/demo/tasks.md <<'T'
# Tasks: demo

**Integration:** `bash unit/a_test.sh`

## Group G1: Demo
**Depends:** none
**Validate:** `bash unit/a_test.sh`
**Context:**
Use bash.

### Task 1: Demo
**File:** `src/a.sh`, `unit/a_test.sh`
**Depends:** none
**Test:** `bash unit/a_test.sh`
**Cases:**
- rejects too many attempts
- an empty input is refused
**Traced to:** Scenario: "first"
- [ ] done
T
  "$1" state init demo >/dev/null 2>&1; "$1" state set complexity medium >/dev/null 2>&1
}
ev() { "$C" evidence add --stage plan --phase fresh "$@" --artifact .temper/specs/demo/tasks.md >/dev/null 2>&1; }
done3() { for l in readiness zoom-out comprehension; do ev --exit 0 --label PROVEN --claim "fresh review completed: $l A"; done; ev --claim "paraphrase: a demo | bash"; }
verdict() { "$C" gate plan >/dev/null 2>&1 && echo PASS || echo FAIL; }
row() { printf '| %s | %s | %s |\n' "$1" "$2" "$3"; }
for C in "$OLD" "$NEW"; do
  mk "$C"; ev --severity high --claim "[readiness] Task 1: the case names no expected value"; done3; R1[${#R1[@]}]="$(verdict)"
  mk "$C"; for l in readiness zoom-out; do ev --exit 0 --label PROVEN --claim "fresh review completed: $l A"; done; R2[${#R2[@]}]="$(verdict)"
  mk "$C"; done3; echo "- an edit" >> .temper/specs/demo/tasks.md; R3[${#R3[@]}]="$(verdict)"
  mk "$C"; ev --severity high --claim "[zoom-out] a new helper"; done3
  "$C" evidence contest --stage plan --id 1 --cite '' --reason 'it was intentional' >/dev/null 2>&1 && R4[${#R4[@]}]="recorded" || R4[${#R4[@]}]="refused"
  mk "$C"; done3; R5[${#R5[@]}]="$(verdict)"
done
echo "| Plan state | 9.7.5 | 9.7.6 |"; echo "|---|---|---|"
row "a fresh reader found a task that leaves the expected value to the builder" "${R1[0]}" "${R1[1]}"
row "the reviewer stopped after two of three lenses" "${R2[0]}" "${R2[1]}"
row "tasks.md changed after the review" "${R3[0]}" "${R3[1]}"
row "the author contests a finding with no citation" "${R4[0]} (no such command)" "${R4[1]}"
row "a clean review of a good plan (control)" "${R5[0]}" "${R5[1]}"
