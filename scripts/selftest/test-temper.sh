#!/usr/bin/env bash
#
# test-temper.sh — unit tests for scripts/temper (the deterministic spine).
#
# Plain-bash assertions, no test framework dependency (consistent with the rest of
# Temper's tooling). Runs entirely in a throwaway tmp dir; never touches the repo.
set -uo pipefail

# The repo root: this script's folder with the literal suffix /scripts/selftest removed.
unset CDPATH
TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${TESTS_DIR%/scripts/selftest}"
[[ "$REPO_ROOT" != "$TESTS_DIR" && -x "$REPO_ROOT/scripts/temper" ]] || { echo "FAIL: cannot find the repo root from $TESTS_DIR"; exit 1; }
TEMPER="$REPO_ROOT/scripts/temper"
WORKDIR="$(mktemp -d)" || exit 1
WORKDIR="$(cd -P "$WORKDIR" && pwd)" || exit 1   # physical, as the scripts see their own folders
trap 'rm -rf "$WORKDIR"' EXIT

PASS=0
FAIL=0

assert_eq() { # assert_eq <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $1 — expected '$2', got '$3'"
  fi
}

assert_exit() { # assert_exit <name> <expected-code> <cmd...>
  local name="$1" expected="$2"; shift 2
  local actual out
  out="$(mktemp "$WORKDIR/assert-out.XXXXXX")"
  "$@" >"$out" 2>&1; actual=$?
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $name — expected exit $expected, got $actual"
    sed 's/^/    /' "$out"
  fi
  rm -f "$out"
}

setup() {
  cd "$WORKDIR" || exit 1   # never run the deletes below anywhere but the throwaway folder
  rm -rf .temper .claude
  mkdir -p .claude .temper/specs/demo
  git init -q . 2>/dev/null || true
  cat > .claude/temper.config <<'EOF'
stack: auto
packs: [quality, tdd, security, git]
review:
  block-on: [critical]
check:
  coverage-threshold: 80
eval:
  enabled: true
  pass-threshold: 0.75
loops:
  max-per-type: 2
autonomy:
  enabled: false
  max-blast-radius: 15
  park-on-touch: ["**/auth/**", "**/payment/**"]
  budget:
    max-total-loops: 4
    max-stages: 12
EOF
  cat > .temper/specs/demo/intent.md <<'EOF'
**Author:** Demo Author <demo@example.com>
**Status:** accepted
**Created:** 2026-01-01
**Reviewer:** Demo Reviewer <rev@example.com>
**Complexity:** simple

## Problem
Users cannot do the demo thing today.

### Success Criteria
- [ ] AC-01 [required]: demo criterion one
  Why: keeps the demo flow honest
  Validate: scenario — traced to a test below
- [ ] AC-02 [required]: demo criterion two
  Why: second criterion for scenario parity
  Validate: scenario — traced to a test below

### Constraints
- keep the demo self-contained (proposed)

### Scope and Non-goals
- In scope: the demo
- Out of scope: production behavior
- Must keep working: the existing suite

### Target Users
- developer: runs the demo → sees the output

### Open Questions

### Decisions

## Scenarios (BDD)
#### Happy Path
```gherkin
Scenario: first
  Given a demo
  When it runs
  Then it works
  Note: unit
  Covers: AC-01
```
```gherkin
Scenario: second
  Given a demo
  When it runs again
  Then it still works
  Note: unit
  Covers: AC-02
```

## Scenario Coverage Checklist

## Source Traceability
### Context Sources
- none: description only — nothing linked
EOF
  cat > .temper/specs/demo/tasks.md <<'EOF'
- [x] done task
EOF
  "$TEMPER" init >/dev/null
  "$TEMPER" state init demo --command temper >/dev/null
}

# No case writes into a folder named hooks. While core.hooksPath is unset, git runs the hooks in
# the hooks folder of a repository's git folder, and install.sh reads that folder to decide. A case
# that needs hooks of the user's there makes a throwaway plugin with _dg_plugin: its install.sh is
# install.sh with the one HOOKS_DIR line naming the folder default-gate in the git folder instead,
# so the case puts those hooks in <git folder>/default-gate and every other line that runs is
# install.sh's own. Git itself never runs that folder, so a case that needs git to run a hook of
# the user's (a real commit) sets core.hooksPath to a folder of its own instead.
_git_list() { # _git_list <git folder>: every file and folder in it, sorted, but for Temper's own
              # temper-gate folder and temper-pre-commit file and git's index and logs (which git
              # itself rewrites), so a case can show the installer wrote nothing else there
  (cd "$1" && find . \( -path ./temper-gate -o -path ./temper-pre-commit -o -path ./logs -o -name 'index*' -o -name '*.lock' \) -prune -o -print | LC_ALL=C sort)
}
_dg_plugin() { # _dg_plugin <folder>: makes that throwaway plugin there (the CLI, acceptance.py, the
               # guard scripts the hook runs, and the changed install.sh)
  local g
  rm -rf "$1"
  mkdir -p "$1/scripts/guards"
  cp "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$1/scripts/"
  for g in block-secrets.sh verify-tests-ran.sh block-uncommitted-gate.sh; do
    cp "$REPO_ROOT/scripts/guards/$g" "$1/scripts/guards/$g"
  done
  sed 's|^HOOKS_DIR=.*$|HOOKS_DIR="$COMMON_REAL/default-gate"|' "$REPO_ROOT/scripts/guards/install.sh" \
    > "$1/scripts/guards/install.sh"
}

# The cases live in four files next to this one, sourced in order so they share the helpers,
# the counters and the state each case leaves for the next. Each stays well under the size a
# reader takes in at once.
source "$TESTS_DIR/temper-cases-1.sh"
source "$TESTS_DIR/temper-cases-2.sh"
source "$TESTS_DIR/temper-cases-3.sh"
source "$TESTS_DIR/temper-cases-4.sh"

echo ""
echo "=== test-temper.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
