#!/usr/bin/env bash
#
# test-temper.sh — unit tests for scripts/temper (the deterministic spine).
#
# Plain-bash assertions, no test framework dependency (consistent with the rest of
# Temper's tooling). Runs entirely in a throwaway tmp dir; never touches the repo.
set -uo pipefail
# grep -q stops at the first match, so a command before it that writes again (echo and printf too) can die of
# SIGPIPE, and pipefail fails the pipe: a variable goes to grep as a here-string (`grep -q PATTERN <<<"$OUT"`), and
# after a command grep reads its whole input (`grep -c PATTERN >/dev/null`).
# No case reads the terminal: a hook a case runs with no input of its own reads an empty standard
# input, also when the suite itself is started with one left open.
exec </dev/null

# The repo root: this script's folder with the literal suffix /scripts/selftest removed.
unset CDPATH
TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${TESTS_DIR%/scripts/selftest}"
[[ "$REPO_ROOT" != "$TESTS_DIR" && -x "$REPO_ROOT/scripts/temper" ]] || { echo "FAIL: cannot find the repo root from $TESTS_DIR"; exit 1; }
TEMPER="$REPO_ROOT/scripts/temper"
# The Python modules the CLI runs, by name: a case that copies the CLI copies them too (_cli_files), and a case that
# proves a text is absent from the CLI reads them too (_cli_text)
CLI_MODULES="scripts/json_ops.py scripts/state_ops.py scripts/ledger_ops.py scripts/spec_text.py scripts/commit_rows.py
scripts/report_ops.py scripts/groups_ops.py"
WORKDIR="$(mktemp -d)" || exit 1
WORKDIR="$(cd -P "$WORKDIR" && pwd)" || exit 1   # physical, as the scripts see their own folders
# A CLI call from outside this folder is refused (exit 3), config and model included, and the real .temper is left as it was.
export TEMPER_SELFTEST_ROOT="$WORKDIR"
export TEMPER_BASELINE_FOREGROUND=1   # WP20: a case that starts the baseline runs its suite in the foreground
_REAL_TEMPER_BEFORE="$(find "$REPO_ROOT/.temper" -type f -printf '%p %s %T@\n' 2>/dev/null | LC_ALL=C sort | cksum)"
trap 'rm -rf "$WORKDIR"' EXIT

PASS=0
FAIL=0
XFAIL=0

# The expected to fail list (9.8.5, WP07): scripts/selftest/expected-fail.txt next to this file, read once a process. A
# line `selftest:<token> <package> <promise>` lists every assertion whose name starts with the token and a space; `#`
# starts a comment and the e2e lines are the scenario runner's. A listed assertion that fails counts in XFAIL, not in
# FAIL; one that passes counts in FAIL, as an unexpected pass. A token never hides an assertion that is not listed.
_XF_LIST=" $(sed 's/#.*//' "$TESTS_DIR/expected-fail.txt" 2>/dev/null | awk '$1 ~ /^selftest:/ { sub(/^selftest:/, "", $1); printf "%s ", $1 }')"
_XF_SEEN=" "
_xf_listed() { # _xf_listed <name>: 0 when the first word of the name is a token of the list (and marks it seen)
  local tok="${1%% *}"
  [[ "$tok" != "$1" && "$_XF_LIST" == *" $tok "* ]] || return 1
  [[ "$_XF_SEEN" == *" $tok "* ]] || _XF_SEEN="$_XF_SEEN$tok "
  return 0
}
_xf_pass() { # _xf_pass <name>: a pass, or an unexpected pass of a listed assertion
  if _xf_listed "$1"; then
    FAIL=$((FAIL+1))
    echo "UNEXPECTED PASS: $1 — take ${1%% *} off scripts/selftest/expected-fail.txt"
    return 0
  fi
  PASS=$((PASS+1))
}
_xf_fail() { # _xf_fail <name>: 0 when the failure was expected (counted and printed here), else 1
  _xf_listed "$1" || return 1
  XFAIL=$((XFAIL+1))
  echo "XFAIL: $1"
}

assert_eq() { # assert_eq <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    _xf_pass "$1"
  elif ! _xf_fail "$1"; then
    FAIL=$((FAIL+1))
    echo "FAIL: $1 — expected '$2', got '$3'"
  fi
}

assert_exit() { # assert_exit <name> <expected-code> <cmd...>
  local name="$1" expected="$2"; shift 2
  local actual out
  # Inside .git when there is one: an untracked file in the fixture would be a change outside the plan (the 9.8.0 scope row).
  if [[ -d "$WORKDIR/.git" ]]; then out="$(mktemp "$WORKDIR/.git/assert-out.XXXXXX")"; else out="$(mktemp "$WORKDIR/assert-out.XXXXXX")"; fi
  "$@" >"$out" 2>&1; actual=$?
  if [[ "$actual" == "$expected" ]]; then
    _xf_pass "$name"
  elif ! _xf_fail "$name"; then
    FAIL=$((FAIL+1))
    echo "FAIL: $name — expected exit $expected, got $actual"
    sed 's/^/    /' "$out"
  fi
  rm -f "$out"
}

setup() {
  cd "$WORKDIR" || exit 1   # never run the deletes below anywhere but the throwaway folder
  rm -rf .temper .claude .gitignore   # no case ignores .temper for the next one
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
evidence:
  claimed-runs: count   # 9.8.5: the cases simulate runs with evidence add; temper-cases-31.sh tests the strict default
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
  Test: true
```
```gherkin
Scenario: second
  Given a demo
  When it runs again
  Then it still works
  Note: unit
  Covers: AC-02
  Test: true
```

## Scenario Coverage Checklist

## Source Traceability
### Context Sources
- none: description only — nothing linked
EOF
  # Build runs in groups: the default run is one already built and integrated (one group, one
  # done task, groups.json with an integration PASS); a case about the grouped run writes its own
  cat > .temper/specs/demo/tasks.md <<'EOF'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `true`
**Context:**
The demo group.

### Task 1: done task
**File:** `src/demo.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- the demo runs
- a bad input is refused
- [x] done task
EOF
  "$TEMPER" init >/dev/null
  "$TEMPER" state init demo --command temper >/dev/null; _base_known
  printf '{"version": 1, "slug": "demo", "groups": {}, "tasks": {}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
}

# 9.7.5: a scenario criterion passes only from a row the CLI ran. _scen records one for each scenario of the demo intent, as
# `temper integrate` does; a case that needs the Build gate to pass calls it after its RED and GREEN rows.
_scen() {
  "$TEMPER" evidence run --stage build --scenario first --claim "scenario first" -- true >/dev/null
  "$TEMPER" evidence run --stage build --scenario second --claim "scenario second" -- true >/dev/null
}

# Test setup only (ADR 0013: the CLI leaves a stage only once its check passed or the person skipped it):
# _pass records a PASS verdict for each named stage; _at moves the run to a stage by hand.
_pass() {
  python3 - "$@" <<'PASSPY'
import json, sys
try:
    g = json.load(open('.temper/gates.json'))
except Exception:
    g = {}
for s in sys.argv[1:]:
    g[s] = {'verdict': 'PASS', 'requirements': []}
json.dump(g, open('.temper/gates.json', 'w'))
PASSPY
}
_at() { # _at <stage> [stage to pass...]
  local stage="$1"; shift
  python3 - "$stage" <<'ATPY'
import json, sys
d = json.load(open('.temper/build-state.json'))
d['next_stage'] = sys.argv[1]
json.dump(d, open('.temper/build-state.json', 'w'), indent=2)
ATPY
  [[ $# -eq 0 ]] || _pass "$@"
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
_cli_files() { # _cli_files <folder>: copies the CLI and the files it runs into a throwaway plugin's scripts folder
  local m
  cp "$TEMPER" "$REPO_ROOT/scripts/acceptance.py" "$REPO_ROOT/scripts/config_yaml.py" "$REPO_ROOT/scripts/tasks_md.py" \
    "$REPO_ROOT/scripts/flow.py" "$REPO_ROOT/scripts/repair_ops.py" "$REPO_ROOT/scripts/temper-help.txt" "$REPO_ROOT/scripts/cli_ctx.py" "$1"   # repair_ops: evidence add asks it of a Scope drift answer; cli_ctx: the models
  for m in $CLI_MODULES; do cp "$REPO_ROOT/$m" "$1"; done
}
_cli_text() { # the text of the CLI and of its Python modules
  local m
  cat "$TEMPER"
  for m in $CLI_MODULES; do cat "$REPO_ROOT/$m"; done
}
_dg_plugin() { # _dg_plugin <folder>: makes that throwaway plugin there (the CLI, acceptance.py, the
               # guard scripts the hook runs, and the changed install.sh)
  local g
  rm -rf "$1"
  mkdir -p "$1/scripts/guards"
  _cli_files "$1/scripts/"
  for g in block-secrets.sh verify-tests-ran.sh block-uncommitted-gate.sh; do
    cp "$REPO_ROOT/scripts/guards/$g" "$1/scripts/guards/$g"
  done
  sed 's|^HOOKS_DIR=.*$|HOOKS_DIR="$COMMON_REAL/default-gate"|' "$REPO_ROOT/scripts/guards/install.sh" \
    > "$1/scripts/guards/install.sh"
}

# The cases live in the files next to this one, sourced in order so they share the helpers and
# the counters. Each stays well under the size a reader takes in at once.
# 9.8.4: each case file starts from a clean fixture (_fresh_fixture): the work folder emptied, with
# no commit, file or folder an earlier case file left, as when it runs alone. Files 3, 6 and 9 go on
# from 2, 5 and 8 (run-selftest.sh runs each pair in one process), so they start where those ended.
_fresh_fixture() {
  cd "$WORKDIR" || exit 1
  find "$WORKDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  cd "$WORKDIR" || exit 1
}
source "$TESTS_DIR/case-helpers.sh"
# Every temper-cases-N.sh next to this file, in number order: a new case file is found by its name, with no list to
# change. The files in GOES_ON continue the one before them and are sourced without _fresh_fixture.
GOES_ON=" 3 6 9 "
for _n in $(cd "$TESTS_DIR" && for f in temper-cases-*.sh; do f="${f#temper-cases-}"; echo "${f%.sh}"; done | sort -n); do
  [[ -z "${TEMPER_CASES_ONLY:-}" || " $TEMPER_CASES_ONLY " == *" $_n "* ]] || continue
  [[ "$GOES_ON" == *" $_n "* ]] || _fresh_fixture
  source "$TESTS_DIR/temper-cases-$_n.sh"
done

# the suite leaves the real .temper folder as it was, and a CLI call outside its own folder is refused
assert_eq "selftest safety: the real .temper folder is as it was" "$_REAL_TEMPER_BEFORE" "$(find "$REPO_ROOT/.temper" -type f -printf '%p %s %T@\n' 2>/dev/null | LC_ALL=C sort | cksum)"
assert_exit "selftest safety: a CLI call from outside the self test folder is refused (exit 3), config included" 3 \
  bash -c "cd '$REPO_ROOT' && '$TEMPER' config get check.coverage-threshold"
assert_exit "selftest safety: model is refused there too" 3 bash -c "cd '$REPO_ROOT' && '$TEMPER' model plan"

# a line of the list that matches no assertion is stale and fails; only the whole suite can tell, so a run of some case
# files (TEMPER_CASES_ONLY, as run-selftest.sh runs each) leaves this to scripts/check_done.py
if [[ -z "${TEMPER_CASES_ONLY:-}" ]]; then
  for _xf_tok in $_XF_LIST; do
    [[ "$_XF_SEEN" == *" $_xf_tok "* ]] && continue
    FAIL=$((FAIL+1))
    echo "FAIL: selftest:$_xf_tok on scripts/selftest/expected-fail.txt matches no check: take its line off"
  done
fi

echo ""
echo "=== test-temper.sh ==="
echo "XFAIL: $XFAIL"
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
