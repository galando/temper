# Case file 65 (WP24): a finding is repaired in its stage. One High finding of Review, or one failed row of Check whose
# class is code, is repaired where it was found: `temper repair start` opens the window only when every condition of
# can_start holds, a fresh Build agent fixes and commits nothing, `temper repair commit` makes the CLI's own commit and
# runs the checks again on the new tree, a reader that did not write the fix confirms each finding in rows written after
# the commit and after its launch mark, and only then does `temper repair close` resolve it. A repair that made things
# worse is reverted and asked about (repair.stop).
# Sourced by test-temper.sh; its helpers (fresh, gpass, gfail, review_done) are used here, and the builders below are
# this file's own. Token: repair:. The programs of this file log their runs in a folder of the git folder (outside every
# work tree, so a log line never changes a digest). A call the CLI does not have yet stays inside $( ... ) or ends in
# || true, so the file always runs to its end.

# --- the helpers of this file ---
P65="$WORKDIR/.git/p65"   # the programs of this file; a new repository removes the git folder, so _review65 writes them after
T65="$(mktemp -d)"        # the folders of the fixtures this file builds most, kept as archives; removed at the end of the file
_save65() { tar -cf "$T65/$1.tar" -C "$WORKDIR" . 2>/dev/null; }
_load65() { # _load65 <name>: the case folder as _save65 kept it under that name (1 when none is kept)
  [[ -f "$T65/$1.tar" ]] || return 1
  cd "$WORKDIR" || return 1
  find "$WORKDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  tar -xf "$T65/$1.tar" -C "$WORKDIR"
}
_x65() { # _x65 <python code over d, the JSON of temper next (or of the second argument)>: prints r. opts(d) is every
         # option of the question and of its More question, opt(d, i) the one with that id, ids(d) their ids, calls(d)
         # every call of the action and of its agents, short(c) a call without the path of the CLI
  python3 -B - "$1" "${2:-$("$TEMPER" next --json 2>/dev/null)}" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def opts(d):
    a = d.get("ask") or {}
    return list(a.get("options") or []) + list((a.get("more") or {}).get("options") or [])
def opt(d, i):
    return next((o for o in opts(d) if o.get("id") == i), None)
def ids(d):
    return [o.get("id") for o in opts(d)]
def short(c):
    return re.sub(r"^\S*/temper ", "", str(c))
def calls(d):
    return [short(c) for c in list(d.get("calls") or []) + [c for x in d.get("agents") or [] for c in (x.get("before") or []) + (x.get("after") or [])]]
r = None
exec(sys.argv[1])
print(r)
PY
}
_st65() { # _st65 <python expression over s, the run state, and w, its open repair (s["repair"], {} when none)>
  python3 -B - "$1" <<'PY'
import json, sys
try:
    s = json.load(open(".temper/build-state.json"))
except (OSError, ValueError):
    s = {}
w = s.get("repair") if isinstance(s.get("repair"), dict) else {}
print(eval(sys.argv[1]))
PY
}
_progs65() { # the project's suite in $P65 (inside .git, so no file of the tree). It logs each run to $P65/log; as
             # $P65/suite.mode says it meets a setup line that fails (exit 125) or fails one test (exit 1); it fails
             # when src/lib.sh lost its line or src/demo.sh says BROKEN; with `cov` it prints a coverage total
             # ($P65/cov, 90 when absent)
  mkdir -p "$P65"; : > "$P65/log"; rm -f "$P65/suite.mode" "$P65/cov"
  cat > "$P65/suite" <<SH
#!/bin/sh
echo suite >> "$P65/log"
case "\$(cat "$P65/suite.mode" 2>/dev/null)" in
  env) echo "temper-setup: FAIL (exit 1)"; exit 125 ;;
  fail) echo "FAIL: test_total expected 3, got 4 (the whole kept output of the failed suite)"; exit 1 ;;
esac
grep -q 'lib ok' src/lib.sh || { echo "FAIL: test_lib expected the line lib ok in src/lib.sh"; exit 1; }
if grep -q BROKEN src/demo.sh; then echo "FAIL: test_demo src/demo.sh is BROKEN"; exit 1; fi
echo ok
[ "\${1:-}" = cov ] && echo "TOTAL 100 10 \$(cat "$P65/cov" 2>/dev/null || echo 90)%"
exit 0
SH
  chmod +x "$P65/suite"
}
_review65() { # _review65 [plan file...]: a feature run of a git repository at Review, every stage before it passed, Build
              # integrated: the base commit holds the config (its test command the suite), a CI file and a lockfile; the
              # Build commit adds src/demo.sh, its test src/demo_test.sh and src/lib.sh (and each plan file named). The
              # plan declares all of them; the Review snapshot names the Build commit; the tree is clean. The budget
              # allows four repeats a failure ($B65_BUDGET when set: build it with a plan file, so no kept fixture is read)
  local f extra=""
  [[ $# -eq 0 ]] && _load65 review && return 0
  fresh; rm -rf .git src unit .github package-lock.json README
  git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  sed -i '/block-on/d' .claude/temper.config   # the default: a critical or a high finding blocks
  _progs65
  python3 -B - "$P65" "${B65_BUDGET:-4}" <<'PY'
import sys
p = ".claude/temper.config"
s = open(p).read()
s = s.replace("  coverage-threshold: 80\n", '  coverage-threshold: 80\n  commands:\n    test: "%s/suite"\n' % sys.argv[1], 1)
open(p, "w").write(s + "budget:\n  per-failure: %s\n" % sys.argv[2])
PY
  mkdir -p .github/workflows; echo base > README; printf '{}\n' > package-lock.json; printf 'on: push\n' > .github/workflows/ci.yml
  git add -A -- . ':(exclude).temper'; git commit -q -m base
  local base; base="$(git rev-parse HEAD)"
  git checkout -q -B feature/demo; "$TEMPER" state set branch feature/demo >/dev/null 2>&1
  "$TEMPER" state set base_sha "$base" >/dev/null 2>&1
  for f in "$@"; do extra+=", \`$f\`"; done
  printf '%s\n' '# Tasks: demo' '' "**Integration:** \`$P65/suite\`" '' '## Group G1: Core' '**Depends:** none' \
    "**Validate:** \`$P65/suite\`" '**Context:**' 'The demo group.' '' '### Task 1: first task' \
    "**File:** \`src/demo.sh\`, \`src/demo_test.sh\`, \`src/lib.sh\`, \`package-lock.json\`, \`.github/workflows/ci.yml\`$extra" \
    '**Depends:** none' '**Test:** `sh src/demo_test.sh`' '**Cases:**' '- a holds' '- [x] done' > .temper/specs/demo/tasks.md
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  mkdir -p src; echo 'echo demo' > src/demo.sh; printf 'a=1\nb=2\nc=3\n' > src/demo_test.sh; echo 'lib ok' > src/lib.sh
  for f in "$@"; do mkdir -p "$(dirname "$f")"; echo "echo $f" > "$f"; done
  git add -A -- . ':(exclude).temper'; git commit -q -m 'build: the demo'
  python3 -B - "$(git rev-parse HEAD)" <<'PY'
import json, sys
d = {"version": 1, "slug": "demo", "cli_commits": [],
     "groups": {"G1": {"status": "passed", "worktree": "", "branch": "temper/demo/G1", "confirmed": True, "gate": {"verdict": "PASS"}}},
     "tasks": {"1": {"status": "passed", "group": "G1"}},
     "integration": {"verdict": "PASS", "reason": "", "group": None, "files": [], "ts": "x", "head": sys.argv[1], "merged": True}}
json.dump(d, open(".temper/groups.json", "w"))
PY
  # the tests Build ran first failing, then passing (a built run's ledger: Build's gate runs again on it after a repair)
  "$TEMPER" evidence run --stage build --claim 'the demo test' --phase red -- false >/dev/null 2>&1
  "$TEMPER" evidence run --stage build --claim 'the demo test' --phase green -- true >/dev/null 2>&1
  gpass build; "$TEMPER" state advance build_complete review >/dev/null 2>&1
  : > "$P65/log"
  [[ $# -eq 0 ]] && _save65 review
  return 0
}
_finding65() { # _finding65 <severity> <claim> [detail] [fix] [proof]: a finding of Review with its whole text (the
               # flags of WP24); where the CLI does not take them, or with no detail given, the claim alone (as 9.8.4
               # saved it)
  if [[ -n "${3:-}" ]]; then
    "$TEMPER" evidence add --stage review --severity "$1" --label PROVEN --claim "$2" --detail "$3" --fix "${4:-}" \
      --proof "${5:-none}" >/dev/null 2>&1 && return 0
  fi
  "$TEMPER" evidence add --stage review --severity "$1" --label PROVEN --claim "$2" >/dev/null 2>&1
}
CLAIM65='src/demo.sh:1 the demo prints nothing on error'
_open65() { # _open65 <proof|plain> [plan file...]: _review65, then one High finding on src/demo.sh (with its detail, fix
            # and proof field, or the claim alone with `plain`), Review's completion row naming the files read, and the
            # failed Review gate
  local proof="$1"; shift
  [[ $# -eq 0 ]] && _load65 "open-$proof" && return 0
  _review65 "$@"
  if [[ "$proof" == plain ]]; then _finding65 high "$CLAIM65"
  else _finding65 high "$CLAIM65" 'src/demo.sh exits 0 and writes nothing to stderr when its input is missing' \
         'print a line to stderr on error' "$proof"; fi
  review_done
  "$TEMPER" gate review >/dev/null 2>&1
  [[ $# -eq 0 ]] && _save65 "open-$proof"
  return 0
}
_start65() { "$TEMPER" repair start --stage "${1:-review}" "${@:2}" >/dev/null 2>&1 || true; }
_fix65() { printf 'echo demo\necho "demo: error" >&2\n' > src/demo.sh; }   # the fix the finding asks for
_commit65() { "$TEMPER" repair commit >/dev/null 2>&1 || true; }
_mark65() { # the before calls of the agents next launches (the recheck's launch mark among them), run as a launch runs them
  local c
  while IFS= read -r c; do [[ -n "$c" ]] && bash -c "$c" >/dev/null 2>&1; done \
    < <(_x65 "r = '\n'.join(c for a in d.get('agents') or [] for c in a.get('before') or [])")
}
_ids65() { _st65 "' '.join(str(i) for i in (w.get('findings') or [1]))"; }
_recheck65() { # _recheck65 <fixed|not fixed|none> [complete|incomplete]: the narrow recheck, as the section Re-check:
               # of agents/review.md has it: launched (its before calls run), one row a finding of the repair, and one
               # completion row that names the changed files and the count of ids checked
  local id ids n=0 f base args=()
  _mark65
  ids="$(_ids65)"
  for id in $ids; do
    n=$((n + 1))
    case "$1" in
      fixed) "$TEMPER" evidence add --stage review --claim "recheck #$id: fixed" --exit 0 --label PROVEN --cmd recheck >/dev/null 2>&1 ;;
      'not fixed') "$TEMPER" evidence add --stage review --claim "recheck #$id: not fixed" --exit 1 --label PROVEN --cmd recheck >/dev/null 2>&1 ;;
    esac
  done
  [[ "${2:-complete}" == complete ]] || return 0
  base="$(_st65 "w.get('base') or ''")"; [[ -n "$base" ]] || base="HEAD~1"
  while IFS= read -r f; do [[ -n "$f" ]] && args+=(--read "$f"); done < <(git diff --name-only "$base" HEAD 2>/dev/null)
  "$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC --cmd recheck --value "$n" \
    ${args[@]+"${args[@]}"} >/dev/null 2>&1 \
    || "$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC --cmd recheck \
      ${args[@]+"${args[@]}"} >/dev/null 2>&1
}
_close65() { # repair close, then the CLI's own repair call (a revert) when next names one as its action
  local c i
  "$TEMPER" repair close >/dev/null 2>&1 || true
  for i in 1 2; do
    c="$(_x65 "r = '\n'.join(c for c in d.get('calls') or [] if re.match(r'repair ', short(c))) if d.get('action') == 'auto' else ''")"
    [[ -n "$c" ]] || break
    while IFS= read -r i; do [[ -n "$i" ]] && bash -c "$i" >/dev/null 2>&1; done <<<"$c"
  done
}
_res65() { # _res65 <n>: the nth finding of Review: resolved:<the commit it names, its first 7>, accepted or open
  python3 -B - "$1" <<'PY'
import json, sys
try:
    rows = json.load(open(".temper/evidence/review.json"))
except (OSError, ValueError):
    rows = []
f = [e for e in rows if isinstance(e, dict) and e.get("severity")]
n = int(sys.argv[1])
e = f[n - 1] if len(f) >= n else {}
res = e.get("resolved") if isinstance(e.get("resolved"), dict) else {}
print("resolved:%s" % str(res.get("fixed_by") or "")[:7] if res else ("accepted" if e.get("accepted") else "open"))
PY
}
_subj65() { git log -1 --format=%s 2>/dev/null; }
_short65() { git rev-parse --short=7 HEAD 2>/dev/null; }
_tree65() { git rev-parse 'HEAD^{tree}' 2>/dev/null; }
_used65() { # the count of the entries of the budget record
  python3 -B -c "import json; print(len(json.load(open('.temper/budget.json')).get('used') or []))" 2>/dev/null || echo 0
}
_refused65() { # _refused65 <ERE of the reason> [stage] [flag...]: repair start, and what it did: refused (exit not 0, not as an
               # unknown word), no window (no repair in the run state, no adhoc), no budget entry spent, and the refusal
               # says why (the ERE, read without case)
  local out rc u0 u1
  u0="$(_used65)"
  out="$("$TEMPER" repair start --stage "${2:-review}" "${@:3}" 2>&1)"; rc=$?
  u1="$(_used65)"
  printf '%s|%s|%s|%s' "$([[ $rc -ne 0 ]] && ! grep -qi 'unknown subcommand' <<<"$out" && echo refused || echo "rc $rc: ${out:0:60}")" \
    "$(_st65 "'no window' if not w and not s.get('adhoc') else 'window'")" \
    "$([[ "$u0" == "$u1" ]] && echo 'not spent' || echo spent)" \
    "$(grep -qiE "$1" <<<"$out" && echo 'says why' || echo "says: ${out:0:80}")"
}
REFUSED65='refused|no window|not spent|says why'
_norepair65() { _x65 "r = 'no repair' if not any(re.match(r'repair start', c) for c in calls(d)) and not opt(d, 'repair-again') else 'repair'"; }
_follow65() { # the CLI's own actions until the first launch (at most three); prints what the first one was
  local first i c
  first="$(_x65 "r = 'auto repair start' if d.get('action') == 'auto' and any(re.match(r'repair start --stage (review|check)$', c) for c in calls(d)) else '%s %s' % (d.get('action'), calls(d)[:1])")"
  for i in 1 2 3; do
    [[ "$(_x65 "r = d.get('action')")" == auto ]] || break
    while IFS= read -r c; do [[ -n "$c" ]] && bash -c "$c" >/dev/null 2>&1; done < <(_x65 "r = '\n'.join(d.get('calls') or [])")
  done
  echo "$first"
}

# --- the window opens when every condition holds ---
# (a finding saved with no detail and no proof field, as 9.8.4 and the base saved one: a missing proof is none and the
# missing detail is the claim, trap 8; never a refusal)
_open65 plain
_c65_head="$(git rev-parse HEAD)"; _c65_tree="$(_tree65)"
"$TEMPER" repair start --stage review >/dev/null 2>&1; _c65_rc=$?
assert_eq "repair: start opens the window when every condition holds, records the repair and spends one step of the budget" \
  "rc=0|n=1 stage=review base=HEAD tree=HEAD findings=[1] blocking=1|window repair|spent gate:review" \
  "rc=$_c65_rc|$(_st65 "'n=%s stage=%s base=%s tree=%s findings=%s blocking=%s' % (w.get('n'), w.get('stage'), 'HEAD' if w.get('base') == '$_c65_head' else w.get('base'), 'HEAD' if w.get('base_tree') == '$_c65_tree' else w.get('base_tree'), w.get('findings'), (w.get('before') or {}).get('blocking'))")|$(_st65 "'window %s' % (s.get('adhoc') or {}).get('kind') if isinstance(s.get('adhoc'), dict) else 'no window'")|$(python3 -B -c "import json; u = json.load(open('.temper/budget.json')).get('used') or []; print('spent ' + ','.join(x.get('key', '') for x in u))" 2>/dev/null || echo 'nothing spent')"

# --- start is refused outside its conditions, one assertion each ---
_open65 none; gpass review
assert_eq "repair: start is refused outside its conditions: the gate passed" "$REFUSED65" "$(_refused65 'pass')"
_open65 none
python3 -B - <<'PY'
import json
p = ".temper/gates.json"
d = json.load(open(p))
d["review"].setdefault("requirements", []).append({"name": "no code changed at Review", "pass": False,
                                                   "detail": "Review changed src/lib.sh; Review writes no code"})
json.dump(d, open(p, "w"))
PY
assert_eq "repair: start is refused outside its conditions: a failed row is not on the repairable list" "$REFUSED65" \
  "$(_refused65 'no code changed at Review|repairable|row')"
_review65; _finding65 high "$CLAIM65" 'd' 'f' none; "$TEMPER" gate review >/dev/null 2>&1
assert_eq "repair: start is refused outside its conditions: no completion row" "$REFUSED65" "$(_refused65 'complet|unfinished')"
_open65 none; echo more >> README; git add README; git commit -q -m 'a commit by hand after the Review'
assert_eq "repair: start is refused outside its conditions: HEAD is not the reviewed HEAD" "$REFUSED65" "$(_refused65 'HEAD|reviewed')"
_open65 none; echo more >> README
assert_eq "repair: start is refused outside its conditions: the tree is dirty" "$REFUSED65" "$(_refused65 'clean|dirty|uncommitted|tree')"
_open65 none
"$TEMPER" override plan --reason 'skipped by the person' >/dev/null 2>&1 \
  || python3 -B -c "
import json
json.dump([{'stage': 'plan', 'reason': 'skipped by the person', 'by': 'the person', 'ts': 'x'}], open('.temper/overrides.json', 'w'))"
assert_eq "repair: start is refused outside its conditions: a stage of the run was skipped" "$REFUSED65" "$(_refused65 'skip|overrid')"
_open65 none
python3 -B - <<'PY'
import json
rid = json.load(open(".temper/build-state.json")).get("run_id")
u = [{"key": "gate:review", "kind": "step back", "stage": "review", "why": "an earlier repeat", "ts": "x"}] * 4
json.dump({"v": 1, "run": rid, "used": u, "grants": []}, open(".temper/budget.json", "w"))
PY
assert_eq "repair: start is refused outside its conditions: the budget has no room" "$REFUSED65" "$(_refused65 'budget|repeat|BLOCKED|limit')"
_open65 none
"$TEMPER" evidence contest --stage review --id 1 --cite src/demo.sh:1 --quote 'echo demo' --reason 'the demo prints its line' >/dev/null 2>&1 \
  || python3 -B -c "
import json
p = '.temper/evidence/review.json'; rows = json.load(open(p))
f = [e for e in rows if isinstance(e, dict) and e.get('severity')][0]
f['contested'] = {'cite': 'src/demo.sh:1', 'quote': 'echo demo', 'reason': 'the demo prints its line', 'ts': 'x'}
json.dump(rows, open(p, 'w'), indent=2)"   # the CLI takes a quote of 12 characters at least, and src/demo.sh holds 9
"$TEMPER" gate review >/dev/null 2>&1
assert_eq "repair: start is refused outside its conditions: a finding is contested" "$REFUSED65" "$(_refused65 'contest')"
_review65 src/auth/login.sh
_finding65 high 'src/auth/login.sh:1 the lockout is never reset' 'the counter of failed logins is never set back' 'reset it' none
review_done; "$TEMPER" gate review >/dev/null 2>&1
assert_eq "repair: start is refused outside its conditions: a finding's file is under a sensitive path" "$REFUSED65" \
  "$(_refused65 'sensitive|park-on-touch')"
_review65
_finding65 high 'lib/other.py:3 the fix needs a file outside the plan' 'lib/other.py is no file of the plan' 'change lib/other.py' none
review_done; "$TEMPER" gate review >/dev/null 2>&1
assert_eq "repair: start is refused outside its conditions: a finding's file is outside the plan" "$REFUSED65" \
  "$(_refused65 'outside|plan')"
_open65 none
python3 -B -c "
import json
p = '.temper/build-state.json'; d = json.load(open(p)); d['command'] = 'fix'; json.dump(d, open(p, 'w'), indent=2)"
assert_eq "repair: start is refused outside its conditions: the run is a fix run" "$REFUSED65" "$(_refused65 'fix')"
_open65 none; gpass review check
python3 -B -c "
import json
p = '.temper/build-state.json'; d = json.load(open(p)); d['next_stage'] = 'commit'; json.dump(d, open(p, 'w'), indent=2)"
gfail commit "review gate" "a test"
assert_eq "repair: start is refused outside its conditions: the stage is commit" "$REFUSED65" \
  "$(_refused65 'commit|review or check|review, check' commit)"

# --- the fixer gets the whole finding ---
_review65
_c65_detail="src/demo.sh exits 0 and writes nothing to stderr when its input is missing, so a caller that reads stderr to tell a failed demo from a quiet one never sees the failure; the loop of the base cut a finding to 300 characters and the fix prompt to 200, and this sentence is longer than both of them, so a cut shows: the end of it is here"
_finding65 high "$CLAIM65" "$_c65_detail" 'print the line demo: error to stderr and exit 1 when the input is missing' test
review_done; "$TEMPER" gate review >/dev/null 2>&1
_follow65 >/dev/null
assert_eq "repair: the launch holds the whole finding: a fresh Build agent, the claim, the detail uncut, the fix and the proof field" \
  "temper:temper-build|Repair in place:|claim|detail|fix|proof test|after repair commit" \
  "$(_x65 "a = (d.get('agents') or [{}])[0] if d.get('action') == 'work' else {}; p = str(a.get('prompt') or '')
r = '|'.join([str(a.get('type')), 'Repair in place:' if 'Repair in place:' in p else 'no line', 'claim' if '$CLAIM65' in p else 'no claim',
  'detail' if '''$_c65_detail''' in p else 'detail cut', 'fix' if 'print the line demo: error to stderr' in p else 'no fix',
  'proof test' if re.search(r'proof\W+test', p) else 'no proof',
  'after repair commit' if any(re.match(r'repair commit\b', short(c)) for c in a.get('after') or []) else 'after %s' % [short(c) for c in a.get('after') or []]])")"

# --- repair commit with no change ---
_open65 none; _c65_head="$(git rev-parse HEAD)"; _start65; _c65_open="$(_st65 "'opened' if w else 'not opened'")"
_commit65
assert_eq "repair: commit with no change records it and launches no recheck" \
  "opened|HEAD unchanged|changed 0|window closed|asks, no recheck" \
  "$_c65_open|$([[ "$(git rev-parse HEAD)" == "$_c65_head" ]] && echo 'HEAD unchanged' || echo "HEAD $(_subj65)")|$(_st65 "'changed 0' if '\"changed\": 0' in json.dumps(s) else 'no record of changed 0'")|$(_st65 "'window closed' if not s.get('adhoc') else 'window open'")|$(_x65 "r = 'asks, no recheck' if d.get('action') == 'ask' and not any('Re-check:' in str(a.get('prompt')) for a in d.get('agents') or []) else '%s %s' % (d.get('action'), [a.get('type') for a in d.get('agents') or []])")"

# --- repair commit refuses a file outside what a repair may change ---
_drift65() { # _drift65 <path> [line]: start, the fix, and a line added to the path; then repair commit. Prints: the window
             # opened, nothing committed, the change kept in the work tree, and the Scope drift question for that path
  local head opened; head="$(git rev-parse HEAD)"
  _start65; _fix65
  mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-changed by the repair}" >> "$1"
  opened="$(_st65 "'opened' if w else 'not opened'")"
  _commit65
  printf '%s|%s|%s|%s' "$opened" "$([[ "$(git rev-parse HEAD)" == "$head" ]] && echo 'not committed' || echo "committed $(_subj65)")" \
    "$(grep -q 'changed by the repair' "$1" 2>/dev/null && grep -q 'demo: error' src/demo.sh && echo kept || echo 'not kept')" \
    "$(_x65 "q = d.get('ask') or {}; r = 'scope.drift' if q.get('id') == 'scope.drift' and '$1' in json.dumps(q) else 'asked %s' % q.get('id')")"
}
DRIFT65='opened|not committed|kept|scope.drift'
_open65 none
assert_eq "repair: commit refuses a file outside the approved set" "$DRIFT65" "$(_drift65 src/other.sh)"
_open65 none
assert_eq "repair: commit refuses a file of the spec folder" "$DRIFT65" "$(_drift65 .temper/specs/demo/plan.md)"
_open65 none
assert_eq "repair: commit refuses the config" "$DRIFT65" "$(_drift65 .claude/temper.config '# changed by the repair')"
_open65 none; "$TEMPER" guards install >/dev/null 2>&1 || true
_c65_hooks="$(git config core.hooksPath 2>/dev/null)"; [[ -n "$_c65_hooks" ]] || _c65_hooks="$(git rev-parse --git-path hooks)"
assert_eq "repair: commit refuses a file under .git: nothing is committed, the change stays, and the run asks" \
  "opened|not committed|kept|asks" "$(_drift65 "$_c65_hooks/pre-commit" '# changed by the repair' | sed 's/|asked [a-z][^|]*$/|asks/; s/|scope.drift$/|asks/')"
_open65 none
mkdir -p .temper/specs/demo/acceptance; printf 'exit 0\n' > .temper/specs/demo/acceptance/test_acc65.sh
"$TEMPER" acceptance lock --cmd 'sh .temper/specs/demo/acceptance/test_acc65.sh' >/dev/null 2>&1 || true
assert_eq "repair: commit refuses a locked acceptance test" "$DRIFT65" "$(_drift65 .temper/specs/demo/acceptance/test_acc65.sh)"
_open65 none
assert_eq "repair: commit refuses a lockfile" "$DRIFT65" "$(_drift65 package-lock.json)"
_open65 none
assert_eq "repair: commit refuses a CI file" "$DRIFT65" "$(_drift65 .github/workflows/ci.yml)"
_open65 none
assert_eq "repair: commit refuses a sensitive path" "$DRIFT65" "$(_drift65 src/auth/token_test.sh)"
_open65 none
assert_eq "repair: commit refuses a shell file named like a test outside the plan, and so does the commit gate's scope row (the test pattern of the base)" \
  "$DRIFT65|FAIL changed outside declared files: src/other_test.sh" \
  "$(_drift65 src/other_test.sh)|$(printf 'src/other_test.sh\n' | python3 -I "$REPO_ROOT/scripts/commit_rows.py" blast-radius '{"tasks": []}' '' /dev/null 2>&1)"

# a lockfile and a file outside the plan both changed: the question names the file no answer can let through, and
# offers only what can end it (Add to plan or Allow once of the other file would meet the same question again)
_open65 none; _start65; _fix65; mkdir -p lib; echo 'echo other' > lib/other.sh
printf '{"changed": 1}\n' > package-lock.json; _commit65
assert_eq "repair: with a lockfile and a file outside the plan both changed, scope.drift names the lockfile and offers no answer that cannot end it" \
  "scope.drift|package-lock.json|revert,save" \
  "$(_x65 "q = d.get('ask') or {}; r = '%s|%s|%s' % (q.get('id'), 'package-lock.json' if 'Outside the plan: package-lock.json' in json.dumps(q) else 'names %s' % json.dumps(q)[:120], ','.join(ids(d)))")"

# --- a small change's close never closes a repair window ---
_open65 none; _start65; _fix65
_c65_out="$("$TEMPER" adhoc close 2>&1)"; _c65_rc=$?
assert_eq "repair: adhoc close inside a repair window is refused: the window stays open, nothing is committed, and the refusal names repair commit" \
  "refused|window repair 1 open|says repair commit|next fixer or recheck, no small change" \
  "$([[ $_c65_rc -ne 0 ]] && echo refused || echo "rc 0: ${_c65_out:0:60}")|$(_st65 "'window repair %s open' % w.get('n') if w and not w.get('commit') and (s.get('adhoc') or {}).get('kind') == 'repair' and not s.get('adhoc_done') else 'window %s adhoc %s done %s' % (w.get('n'), s.get('adhoc'), s.get('adhoc_done'))")|$(grep -q 'repair commit' <<<"$_c65_out" && echo 'says repair commit' || echo "says: ${_c65_out:0:80}")|$(_x65 "r = 'next fixer or recheck, no small change' if not any('Ad-hoc change' in str(a.get('prompt')) for a in d.get('agents') or []) else 'a small change review'")"

# --- the fixer's drift ask in a repair window (the mod's Build write rule names it): scope.drift, then the fixer again ---
_open65 none; _start65; _c65_head="$(git rev-parse HEAD)"
_c65_ask="$("$TEMPER" drift ask --path src/other.sh --why 'the fix needs a helper' --change 'one new line' 2>&1 && echo asked || echo refused)"
_commit65
_c65_q="$(_x65 "q = d.get('ask') or {}; r = '%s %s' % (q.get('id'), ','.join(i for i in ids(d) if i in ('add-to-plan', 'revert', 'allow-once'))) if 'src/other.sh' in json.dumps(q) else 'asked %s' % q.get('id')")"
_c65_kept="$([[ "$(git rev-parse HEAD)" == "$_c65_head" ]] && _st65 "'window open' if w and not w.get('commit') else 'window closed'" || echo "committed $(_subj65)")"
while IFS= read -r _c; do [[ -n "$_c" ]] && bash -c "$_c" >/dev/null 2>&1; done < <(_x65 "r = '\n'.join((opt(d, 'add-to-plan') or {}).get('calls') or [])")
_c65_again="$(_x65 "a = (d.get('agents') or [{}])[0] if d.get('action') == 'work' else {}; p = str(a.get('prompt') or ''); r = '%s|%s|%s' % (a.get('type'), 'Repair in place:' if 'Repair in place:' in p else 'no line', 'Drift decision: src/other.sh: add' if 'Drift decision: src/other.sh: add' in p else 'no decision')")"
_mark65 2>/dev/null; _fix65; echo 'echo other' > src/other.sh; _commit65
assert_eq "repair: a drift ask of the fixer in a repair window is taken, asked as scope.drift before any commit, and the fixer runs again with the answer; the CLI then commits the file" \
  "asked|window open|scope.drift add-to-plan,revert,allow-once|temper:temper-build|Repair in place:|Drift decision: src/other.sh: add|repair commit with src/other.sh" \
  "$(tail -1 <<<"$_c65_ask")|$_c65_kept|$_c65_q|$_c65_again|$([[ "$(_subj65)" == 'fix(demo): repair 1 at review' ]] && grep -qx src/other.sh <<<"$(git show --name-only --format= HEAD)" && echo 'repair commit with src/other.sh' || echo "HEAD $(_subj65)")"

# --- repair commit reads what is staged too: a staged rename does not hide a test file it removes ---
_open65 none; _c65_head="$(git rev-parse HEAD)"; _start65; _fix65
mkdir -p unit; git mv src/demo_test.sh unit/demo2_test.sh; printf 'a=1\n' > unit/demo2_test.sh
_commit65
assert_eq "repair: commit sees a test file a staged rename removes: nothing is committed, and the run asks with the file" \
  "not committed|repair.stop|names src/demo_test.sh" \
  "$([[ "$(git rev-parse HEAD)" == "$_c65_head" ]] && echo 'not committed' || echo "committed $(_subj65)")|$(_x65 "q = d.get('ask') or {}; r = '%s|%s' % (q.get('id'), 'names src/demo_test.sh' if 'src/demo_test.sh' in json.dumps(q) else 'names no file')")"

# --- repair revert of a repair not committed puts back what the repair changed, the files it may not change too ---
_open65 none; git rm -q --cached .claude/temper.config; git commit -q -m 'the config is no tracked file'
python3 -I "$(dirname "$TEMPER")/state_ops.py" review-code save .temper/build-state.json >/dev/null 2>&1
_c65_sums() { printf '%s' "$(cksum < .claude/temper.config 2>/dev/null)|$(cksum < .temper/specs/demo/tasks.md)|$(cksum < src/demo.sh)"; }
_c65_before="$(_c65_sums)"; _start65; _c65_open="$(_st65 "'opened' if w else 'not opened'")"; _fix65
echo '# changed by the repair' >> .claude/temper.config; echo '- a line of the fixer' >> .temper/specs/demo/tasks.md
_commit65
_c65_out="$("$TEMPER" repair revert 2>&1)"
assert_eq "repair: revert of a repair not committed puts back the config and the spec folder as they were, and deletes neither" \
  "opened|config kept|as before|reverted" \
  "$_c65_open|$([[ -f .claude/temper.config ]] && echo 'config kept' || echo 'config deleted')|$([[ "$(_c65_sums)" == "$_c65_before" ]] && echo 'as before' || echo 'not as before')|$(grep -qi 'reviewed tree again' <<<"$_c65_out" && echo reverted || echo "says: ${_c65_out:0:80}")"

# --- repair revert of a committed repair refuses when HEAD moved or the tree is dirty ---
_open65 none; _start65; _fix65; _commit65
echo more >> README; git add README; git commit -q --no-verify -m 'a commit by hand after the repair'
_c65_head="$(git rev-parse HEAD)"; "$TEMPER" repair revert >/dev/null 2>&1; _c65_rc=$?
_c65_moved="$([[ $_c65_rc -ne 0 ]] && echo refused || echo taken),$([[ "$(git rev-parse HEAD)" == "$_c65_head" ]] && grep -q more README && echo kept || echo undone)"
_open65 none; _start65; _fix65; _commit65
echo 'echo an edit after the repair' >> src/demo.sh
_c65_head="$(git rev-parse HEAD)"; "$TEMPER" repair revert >/dev/null 2>&1; _c65_rc=$?
_c65_dirty="$([[ $_c65_rc -ne 0 ]] && echo refused || echo taken),$([[ "$(git rev-parse HEAD)" == "$_c65_head" ]] && grep -q 'an edit after the repair' src/demo.sh && echo kept || echo undone)"
assert_eq "repair: revert of a committed repair refuses when HEAD is not the repair commit or the tree is dirty, and undoes nothing" \
  "moved=refused,kept|dirty=refused,kept" "moved=$_c65_moved|dirty=$_c65_dirty"

# --- repair commit refuses when HEAD moved since the window opened ---
_open65 none; _start65; _c65_open="$(_st65 "'opened' if w else 'not opened'")"; _fix65
echo more >> README; git add README; git commit -q -m 'a commit nobody made through the CLI'
_c65_out="$("$TEMPER" repair commit 2>&1)"; _c65_rc=$?
assert_eq "repair: commit refuses when HEAD moved since the window opened, and the run stops" \
  "opened|refused|says HEAD|no repair commit|asks" \
  "$_c65_open|$([[ $_c65_rc -ne 0 ]] && ! grep -qi 'unknown subcommand' <<<"$_c65_out" && echo refused || echo "rc $_c65_rc")|$(grep -qiE 'HEAD|moved|foreign|did not make' <<<"$_c65_out" && echo 'says HEAD' || echo "says: ${_c65_out:0:60}")|$([[ "$(_subj65)" == 'a commit nobody made through the CLI' ]] && echo 'no repair commit' || echo "HEAD $(_subj65)")|$(_x65 "r = 'asks' if d.get('action') == 'ask' else d.get('action')")"

# --- the commit hook passes exactly the commit the CLI staged ---
_open65 none; "$TEMPER" guards install >/dev/null 2>&1 || true
_start65; _fix65
git add src/demo.sh
_c65_hand="$(git commit -q -m 'the same files, by hand' >/dev/null 2>&1 && echo 'hand passed' || echo 'hand refused')"
git reset -q 2>/dev/null
_commit65
_c65_cli="$([[ "$(_subj65)" == 'fix(demo): repair 1 at review' ]] && echo 'CLI passed' || echo "CLI: $(_subj65)")"
echo 'echo more' >> src/demo.sh; git add src/demo.sh
_c65_second="$(git commit -q -m 'a second commit in the window' >/dev/null 2>&1 && echo 'second passed' || echo 'second refused')"
git reset -q 2>/dev/null; git checkout -q -- src/demo.sh 2>/dev/null
# at the commit stage a token written by hand, for exactly the staged tree, opens nothing: the final commit meets every
# gate
gpass review; gfail check "tests pass" "the latest run of a test command failed: the suite"
echo 'echo at the commit' >> src/demo.sh; git add src/demo.sh
python3 -B - <<'PY'
import json, subprocess
p = ".temper/build-state.json"
d = json.load(open(p))
d["next_stage"] = "commit"
out = lambda *a: subprocess.run(["git"] + list(a), stdout=subprocess.PIPE).stdout.decode().strip()
d["repair"] = dict(d.get("repair") or {}, token={"parent": out("rev-parse", "HEAD"), "tree": out("write-tree")})
json.dump(d, open(p, "w"), indent=2)
PY
_c65_final="$("$TEMPER" gate commit --from-hook >/dev/null 2>&1 && echo 'commit stage passed' || echo 'commit stage refused')"
git reset -q 2>/dev/null; git checkout -q -- src/demo.sh 2>/dev/null
assert_eq "repair: the hook passes exactly the commit the CLI staged: not a hand commit, not a second one, never at the commit stage" \
  "hand refused|CLI passed|second refused|commit stage refused" "$_c65_hand|$_c65_cli|$_c65_second|$_c65_final"

# --- trap 2: one repair with the guardrails pack's hooks: each PreToolUse hook of the pack, run as Claude Code runs it,
# on the run's own calls, on the fixer's edit and on a commit the fixer types; the CLI's own git commit is no tool call ---
_pack65() { # _pack65 <tool> <input JSON>: every PreToolUse hook of packs/guardrails/settings-guardrails.json whose matcher
            # takes the tool, with the plugin's folder in the place of its variable; prints the highest exit
  python3 -B - "$REPO_ROOT" "$1" "$2" <<'PY'
import json, re, subprocess, sys
root, tool, inp = sys.argv[1:4]
worst = 0
for e in json.load(open(root + "/packs/guardrails/settings-guardrails.json"))["hooks"]["PreToolUse"]:
    for h in e["hooks"] if re.fullmatch(e["matcher"], tool) else []:
        p = subprocess.run(["bash", "-c", h["command"].replace("${CLAUDE_PLUGIN_ROOT}", '"%s"' % root)], capture_output=True,
                           input=json.dumps({"tool_name": tool, "tool_input": json.loads(inp)}), text=True)
        worst = max(worst, p.returncode)
print(worst)
PY
}
_bash65() { _pack65 Bash "$(python3 -c 'import json, sys; print(json.dumps({"command": sys.argv[1]}))' "$1")"; }
_open65 none; "$TEMPER" guards install >/dev/null 2>&1 || true
_c65_pack=""
_run65() { # _run65 <python list of calls over d> [JSON of next]: each call checked by the pack's hooks (the exit added to
           # _c65_pack), then run as the orchestrator runs it
  local c
  while IFS= read -r c; do [[ -n "$c" ]] || continue; _c65_pack+="$(_bash65 "$c")"; bash -c "$c" >/dev/null 2>&1; done \
    < <(_x65 "r = '\n'.join($1)" "${2:-}")
}
_run65 "d.get('calls') or []"   # the CLI's own action: repair start
_c65_work="$("$TEMPER" next --json 2>/dev/null)"   # the fixer's launch
_c65_pack+="|"; _run65 "[c for a in d.get('agents') or [] for c in a.get('before') or []]" "$_c65_work"
_c65_pack+="|$(_pack65 Write "$(python3 -c 'import json, sys; print(json.dumps({"file_path": sys.argv[1], "content": "echo demo"}))' "$PWD/src/demo.sh")")"
_fix65
_c65_pack+="|$(_bash65 'git add src/demo.sh && git commit -m "fix: the demo"')|"
_run65 "[c for a in d.get('agents') or [] for c in a.get('after') or []]" "$_c65_work"   # its after calls: repair commit
assert_eq "repair: with the guardrails pack's hooks the run's calls and the CLI's commit pass, and a commit the fixer types is refused" \
  "temper:temper-build|0||0|2|00|fix(demo): repair 1 at review" \
  "$(_x65 "r = (d.get('agents') or [{}])[0].get('type')" "$_c65_work")|$_c65_pack|$(_subj65)"

# --- the checks ran again on the new tree ---
_open65 none; _start65; _fix65; _commit65
assert_eq "repair: the checks ran again on the new tree: the integration record names the repair commit, the Build verdict the new tree" \
  "repair commit|integrated at HEAD|build PASS of the new tree|suite ran" \
  "$([[ "$(_subj65)" == 'fix(demo): repair 1 at review' ]] && echo 'repair commit' || echo "HEAD $(_subj65)")|$(python3 -B -c "
import json, subprocess
h = subprocess.run(['git', 'rev-parse', 'HEAD'], stdout=subprocess.PIPE).stdout.decode().strip()
i = json.load(open('.temper/groups.json')).get('integration') or {}
print('integrated at HEAD' if i.get('head') == h else 'integrated at %s' % str(i.get('head'))[:7])" 2>/dev/null)|$(python3 -B -c "
import json, subprocess
t = subprocess.run(['git', 'rev-parse', 'HEAD^{tree}'], stdout=subprocess.PIPE).stdout.decode().strip()
b = json.load(open('.temper/gates.json')).get('build') or {}
print('build %s of the new tree' % b.get('verdict') if b.get('tree') == t else 'build %s of tree %s' % (b.get('verdict'), str(b.get('tree'))[:7]))" 2>/dev/null)|$([[ "$(grep -c suite "$P65/log" 2>/dev/null)" -ge 1 ]] && echo 'suite ran' || echo 'suite not run')"

# --- a behaviour finding needs a RED and a GREEN of the CLI on an unchanged test file ---
_err65() { mkdir -p unit; printf '%s\n' 'sh src/demo.sh 2>&1 >/dev/null | grep -q error' > unit/err_test.sh; }   # fails until the fix
_proof65() { # _proof65 <none|changed|order>: a repair of a finding marked proof: test, with no test run, with the test file
             # changed between the RED and the GREEN, or in order; the recheck says fixed. Prints the finding's state
  _open65 test; _start65
  case "$1" in
    changed|order) _err65; "$TEMPER" repair test 1 --phase red -- sh unit/err_test.sh >/dev/null 2>&1 || true ;;
  esac
  _fix65
  case "$1" in
    none) _err65 ;;
    changed) printf '%s\n' 'sh src/demo.sh 2>&1 >/dev/null | grep -q demo' > unit/err_test.sh ;;
  esac
  [[ "$1" == none ]] || "$TEMPER" repair test 1 --phase green -- sh unit/err_test.sh >/dev/null 2>&1 || true
  _commit65; _recheck65 fixed; _close65
  _res65 1 | sed 's/:.*//'
}
assert_eq "repair: a behaviour finding stays open without a RED and a GREEN on an unchanged test file" \
  "no test run=open|test changed=open|in order=resolved" \
  "no test run=$(_proof65 none)|test changed=$(_proof65 changed)|in order=$(_proof65 order)"

# --- close resolves only what a recheck row written after the commit confirms ---
_review65
_finding65 high "$CLAIM65" 'src/demo.sh writes nothing to stderr on error' 'print a line to stderr' none
_finding65 high 'src/demo.sh:1 the demo exits 0 on error' 'src/demo.sh exits 0 when its input is missing' 'exit 1 on error' none
review_done; "$TEMPER" gate review >/dev/null 2>&1
_start65; _fix65; _commit65; _c65_sha="$(_short65)"
_mark65
"$TEMPER" evidence add --stage review --claim 'recheck #1: fixed' --exit 0 --label PROVEN --cmd recheck >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'recheck #2: not fixed' --exit 1 --label PROVEN --cmd recheck >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC --cmd recheck --value 2 --read src/demo.sh \
  >/dev/null 2>&1 || "$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC --cmd recheck \
  --read src/demo.sh >/dev/null 2>&1
_close65
_c65_two="#1=$(_res65 1 | sed "s/^resolved:$_c65_sha\$/resolved by the repair/")|#2=$(_res65 2)"
_open65 none; _start65; _fix65
"$TEMPER" evidence add --stage review --claim 'recheck #1: fixed' --exit 0 --label PROVEN --cmd recheck >/dev/null 2>&1
_commit65; _recheck65 none; _close65
assert_eq "repair: close resolves only the ids a recheck row written after the commit confirms; a fixed row before it counts for nothing" \
  "#1=resolved by the repair|#2=open|a row before the commit=open" "$_c65_two|a row before the commit=$(_res65 1)"

# --- a worse result is reverted, one assertion each ---
_worse65() { # _worse65 <row|same|new|incomplete>: one repair that makes things worse, then close. Prints: the repair commit,
             # reverted to the reviewed tree (the tree of HEAD is the reviewed tree again, the repair commit kept in the
             # history), and the question repair.stop
  local tree repaired; _open65 none; tree="$(_tree65)"; _start65; _fix65
  [[ "$1" == row ]] && echo 'echo BROKEN' >> src/demo.sh
  _commit65
  repaired="$([[ "$(_subj65)" == 'fix(demo): repair 1 at review' ]] && echo repaired || echo 'no repair commit')"
  case "$1" in
    row) _recheck65 fixed ;;
    same) _recheck65 'not fixed' ;;
    new) _recheck65 fixed
         _finding65 high 'src/demo.sh:2 the error line goes to stdout when stderr is closed' 'the new line 2 breaks a caller' 'check fd 2' none ;;
    incomplete) _recheck65 fixed incomplete ;;
  esac
  _close65
  printf '%s|%s|%s' "$repaired" \
    "$([[ "$(_tree65)" == "$tree" ]] && git log --format=%s -3 | grep -c 'repair 1 at review' >/dev/null && echo 'reverted to the reviewed tree' || echo 'not reverted')" \
    "$(_x65 "q = d.get('ask') or {}; r = 'repair.stop' if q.get('id') == 'repair.stop' else 'asked %s' % q.get('id')")"
}
WORSE65='repaired|reverted to the reviewed tree|repair.stop'
_c65_got="$(_worse65 row)"
assert_eq "repair: a worse result is reverted: a row that passed fails, and the question names it" "$WORSE65|names the suite" \
  "$_c65_got|$(_x65 "r = 'names the suite' if re.search(r'test_demo|BROKEN|tests pass|suite|integrat', json.dumps(d.get('ask') or {})) else 'names nothing'")"
assert_eq "repair: a worse result is reverted: the open blocking findings are not fewer" "$WORSE65" "$(_worse65 same)"
assert_eq "repair: a worse result is reverted: the recheck names a new blocking finding" "$WORSE65" "$(_worse65 new)"
assert_eq "repair: a worse result is reverted: the recheck did not complete" "$WORSE65" "$(_worse65 incomplete)"

# --- a large diff, or one that touches a file no finding names, gets a full Review in the place of the recheck ---
_large65() { # _large65 <large|other>: a repair over 300 changed lines, or one that changes src/lib.sh too; then next
  local i; _open65 none; _start65; _fix65
  case "$1" in
    large) for i in $(seq 1 320); do echo "echo line $i >/dev/null"; done >> src/demo.sh ;;
    other) echo '# lib ok, and a note of the repair' >> src/lib.sh ;;
  esac
  _commit65
  printf '%s|%s' "$([[ "$(_subj65)" == 'fix(demo): repair 1 at review' ]] && echo 'kept, not reverted' || echo "HEAD $(_subj65)")" \
    "$(_x65 "a = [x for x in d.get('agents') or [] if x.get('type') == 'temper:temper-review']; r = 'full Review' if d.get('action') == 'work' and a and not any('Re-check:' in str(x.get('prompt')) for x in a) else 'next %s %s' % (d.get('action'), ['Re-check' if 'Re-check:' in str(x.get('prompt')) else x.get('type') for x in d.get('agents') or []])")"
}
assert_eq "repair: a large diff gets a full Review, not a revert; so does a diff that touches a file no finding names" \
  "large=kept, not reverted|full Review|other=kept, not reverted|full Review" "large=$(_large65 large)|other=$(_large65 other)"

# --- the budget: one by rule, one more on the click, then gone; the same finding is not recommended again ---
_round65() { # one repair that changes nothing the finding asks for: the recheck says not fixed, and the CLI reverts it
  echo '# a comment of the repair' >> src/demo.sh; _commit65; _recheck65 'not fixed'; _close65
}
# (the budget of the case config has room after both repairs, four repeats a failure, so what ends the repairs here is
# the repair's own rule, one by rule and one on the click)
_open65 none
_c65_first="$(_follow65)"
_round65
_c65_after1="$(_x65 "o = opt(d, 'repair-again') or {}; r = '%s, repair-again %s' % (d.get('action'), ('offered, %s' % ('recommended' if o.get('recommended') else 'not recommended')) if o else 'not offered')")"
_c65_again="$(_x65 "o = opt(d, 'repair-again') or {}; r = 'move %s, calls %s' % (o.get('move'), [short(c) for c in o.get('calls') or []][:1])")"
while IFS= read -r _c; do [[ -n "$_c" ]] && bash -c "$_c" >/dev/null 2>&1; done < <(_x65 "r = '\n'.join((opt(d, 'repair-again') or {}).get('calls') or [])")
_c65_click="$(_st65 "'window %s' % w.get('n') if w and s.get('adhoc') else 'no window'")"
_round65
_c65_after2="$(_x65 "r = '%s, repair-again %s, no repair start' % (d.get('action'), 'offered' if opt(d, 'repair-again') else 'gone') if not any(re.match(r'repair start', c) for c in calls(d)) else 'next runs %s' % calls(d)[:1]")"
assert_eq "repair: one by rule, one more on the click, then gone" \
  "auto repair start|ask|move repair, calls ['repair start --stage review --again']|window 2|ask, repair-again gone, no repair start" \
  "$_c65_first|$(sed 's/, repair-again.*//' <<<"$_c65_after1")|$_c65_again|$_c65_click|$_c65_after2"
assert_eq "repair: the same finding open after a repair is not recommended again" "ask, repair-again offered, not recommended" "$_c65_after1"
# the budget spent: the default of two repeats a failure, which the repair by rule and the one on the click use up
_ways65() { _x65 "r = ','.join(i for i in ('accept-finding', 'override', 'back', 'save') if i in ids(d) or (i == 'accept-finding' and (d.get('ask') or {}).get('accept')))"; }
B65_BUDGET=2 _open65 none src/b65.sh
_follow65 >/dev/null; _round65
while IFS= read -r _c; do [[ -n "$_c" ]] && bash -c "$_c" >/dev/null 2>&1; done < <(_x65 "r = '\n'.join((opt(d, 'repair-again') or {}).get('calls') or [])")
_round65
_c65_ways="$(_st65 "'%d repairs' % len({x.get('n') for x in s.get('repairs') or [] if isinstance(x, dict)})")|$("$TEMPER" budget 2>/dev/null | grep -o 'gate:review: [0-9]* of [0-9]*')|$(_x65 "r = (d.get('ask') or {}).get('id')")|$(_ways65)|$(_x65 "r = 'grant offered' if opt(d, 'grant-more') else 'no grant'")"
# rule 9 (D38): only the person grants more, so the step back, a repeat of the failed Review, waits for the grant
while IFS= read -r _c; do [[ -n "$_c" ]] && bash -c "$_c" >/dev/null 2>&1; done < <(_x65 "r = '\n'.join(c.replace('{reason}', 'The next try is different') for c in (opt(d, 'grant-more') or {}).get('calls') or [])")
assert_eq "repair: a spent budget still offers the four ways on: Accept a finding, Override and continue and Save for later, and Loop back to Build once the person grants more" \
  "2 repairs|gate:review: 2 of 2|run.budget|accept-finding,override,save|grant offered|accept-finding,override,back,save" "$_c65_ways|$(_ways65)"

# --- the question offers Repair again only where its call may start; a passed Review with an open High finding offers it ---
_open65 none; echo more >> README; git add README; git commit -q -m 'a commit by hand after the Review'
_c65_hand="$(_x65 "r = '%s %s' % ((d.get('ask') or {}).get('id'), 'offered' if opt(d, 'repair-again') else 'not offered')")"
_open65 none; echo more >> README
_c65_dirty="$(_x65 "r = '%s %s' % ((d.get('ask') or {}).get('id'), 'offered' if opt(d, 'repair-again') else 'not offered')")"
assert_eq "repair: Repair again is offered only where its call may start: not after a commit by hand, not on a dirty tree" \
  "hand commit=review.fail not offered|dirty=review.fail not offered" "hand commit=$_c65_hand|dirty=$_c65_dirty"
_open65 none; sed -i 's/^review:$/review:\n  block-on: [critical]/' .claude/temper.config; "$TEMPER" gate review >/dev/null 2>&1
_c65_pass="$(_x65 "o = ((d.get('ask') or {}).get('options') or [{}])[0]; r = '%s|%s|%s,%s|%s' % ((d.get('ask') or {}).get('id'), d.get('action'), o.get('id'), bool(o.get('recommended')), [short(c) for c in o.get('calls') or []][:1])")"
while IFS= read -r _c; do [[ -n "$_c" ]] && bash -c "$_c" >/dev/null 2>&1; done < <(_x65 "r = '\n'.join((opt(d, 'repair-again') or {}).get('calls') or [])")
assert_eq "repair: a passed Review with an open High finding offers Repair again first, on the click only, and the click opens the window" \
  "review.pass|ask|repair-again,True|['repair start --stage review --again']|window findings=[1]" \
  "$_c65_pass|$(_st65 "'window findings=%s' % w.get('findings') if w else 'no window'")"

# --- a failure at Check: one assertion a row of the table of mechanism 11 ---
_check65() { # _check65 [suite mode] [coverage total]: _review65 with Review passed and the run at Check; the suite in that
             # mode (and its coverage form, at the total given), then check run and gate check
  _review65; review_done; "$TEMPER" gate review >/dev/null 2>&1
  "$TEMPER" state advance review_complete check >/dev/null 2>&1
  if [[ -n "${2:-}" ]]; then
    sed -i "s|^    test: \"$P65/suite\"\$|&\n    coverage: \"$P65/suite cov\"|" .claude/temper.config
    echo "$2" > "$P65/cov"
  fi
  [[ -n "${1:-}" ]] && echo "$1" > "$P65/suite.mode"
  "$TEMPER" check run >/dev/null 2>&1 || true
  "$TEMPER" gate check >/dev/null 2>&1 || true
}
_check65 fail
_c65_first="$(_follow65)"
assert_eq "repair: at Check a red suite of class code is repaired once by rule; the fixer gets the whole kept output, and no new failing test is asked" \
  "auto repair start|temper:temper-build|Repair in place:|the kept output|no RED asked" \
  "$_c65_first|$(_x65 "a = (d.get('agents') or [{}])[0] if d.get('action') == 'work' else {}; p = str(a.get('prompt') or '')
r = '|'.join([str(a.get('type')), 'Repair in place:' if 'Repair in place:' in p else 'no line', 'the kept output' if 'FAIL: test_total expected 3, got 4 (the whole kept output of the failed suite)' in p else 'no output', 'no RED asked' if not re.search(r'--phase red|repair test', p) else 'a RED asked'])")"
_check65 '' 50
_c65_first="$(_follow65)"; _c65_cov="$(_x65 "r = d.get('action')")"
mkdir -p unit; printf 'sh src/demo.sh >/dev/null\n' > unit/demo_more_test.sh
_commit65
assert_eq "repair: at Check a measured coverage drop is repaired once by rule; a diff of test files alone needs no recheck" \
  "auto repair start|work|repair commit|no recheck" \
  "$_c65_first|$_c65_cov|$([[ "$(_subj65)" == 'fix(demo): repair 1 at check' ]] && echo 'repair commit' || echo "HEAD $(_subj65)")|$(_x65 "r = 'no recheck' if not any('Re-check:' in str(a.get('prompt')) for a in d.get('agents') or []) else 'a recheck'")"
_check65
python3 -B -c "
import json
json.dump({'score': 40, 'killed': 4, 'survived': 6, 'threshold': 80}, open('.temper/evidence/mutation.json', 'w'))"
assert_eq "repair: at Check the planted bug score is never repaired by rule: it is information" "no repair|$REFUSED65" \
  "$(_norepair65)|$(_refused65 'pass|mutation|planted' check)"
_acc65() { # _acc65 <code|test>: a locked acceptance test that fails at Check, and the triage's verdict
  _check65
  mkdir -p .temper/specs/demo/acceptance
  printf 'echo "FAIL: test_ac01 expected the field stage"; exit 1\n' > .temper/specs/demo/acceptance/test_acc65.sh
  "$TEMPER" acceptance lock --cmd 'sh .temper/specs/demo/acceptance/test_acc65.sh' >/dev/null 2>&1 || true
  "$TEMPER" check run >/dev/null 2>&1 || true
  gfail check "acceptance tests written before Build" "FAIL: test_ac01 expected the field stage"
  local stamp; stamp="$(_x65 "r = ((d.get('agents') or [{}])[0].get('after') or [''])[-1]")"   # the triage agent's last call
  "$TEMPER" acceptance triage --reason "$1: the $1 is wrong, as the triage of the case reads it" >/dev/null 2>&1
  [[ -n "$stamp" && "$stamp" != None ]] && bash -c "$stamp" >/dev/null 2>&1
  return 0
}
_acc65 code
assert_eq "repair: at Check a locked acceptance test the triage blames on the code is repaired once by rule" "auto repair start" "$(_follow65)"
_acc65 test
assert_eq "repair: at Check a locked acceptance test the triage does not blame on the code is never repaired by rule" "no repair|$REFUSED65" \
  "$(_norepair65)|$(_refused65 'triage|acceptance|code' check)"
_check65 env
_c65_env="$(_norepair65)|$(_refused65 'environment|setup|class' check)"
_check65; sed -i "\|^    test: \"$P65/suite\"\$|d" .claude/temper.config
python3 -B -c "import json; json.dump([], open('.temper/evidence/check.json', 'w'))"
gfail check "tests pass" "no passing test-run evidence recorded"
assert_eq "repair: at Check a fault of the environment or a check that was not measured is never repaired by rule" \
  "SETUP=no repair|$REFUSED65|not measured=no repair|$REFUSED65" \
  "SETUP=$_c65_env|not measured=$(_norepair65)|$(_refused65 'measur|evidence|class' check)"

# --- the commit gate and the tree of each verdict ---
_gates65() { # _gates65 <review tree> [repairs]: every gate PASS; Build and Check of HEAD's tree, Review of the given
             # tree, with the tree the full Review read and the repairs between; the run at the commit stage. Then gate
             # commit: prints whether its row checked tree passes, or fails naming both trees
  python3 -B - "$1" "${2:-}" <<'PY'
import json, subprocess, sys
head = subprocess.run(["git", "rev-parse", "HEAD^{tree}"], stdout=subprocess.PIPE).stdout.decode().strip()
g = {}
for s in ("intent", "plan", "build", "review", "check"):
    g[s] = {"verdict": "PASS", "requirements": [{"name": "all", "pass": True, "detail": "ok"}], "tree": head}
g["review"].update(tree=sys.argv[1], reviewed=sys.argv[1], repairs=[int(x) for x in sys.argv[2].split()] if sys.argv[2] else [])
json.dump(g, open(".temper/gates.json", "w"))
p = ".temper/build-state.json"
d = json.load(open(p))
d["next_stage"] = "commit"
json.dump(d, open(p, "w"), indent=2)
PY
  "$TEMPER" gate commit >/dev/null 2>&1
  python3 -B - "$1" <<'PY'
import json, subprocess, sys
head = subprocess.run(["git", "rev-parse", "HEAD^{tree}"], stdout=subprocess.PIPE).stdout.decode().strip()
rows = (json.load(open(".temper/gates.json")).get("commit") or {}).get("requirements") or []
x = next((r for r in rows if r.get("name") == "checked tree"), None)
if x is None or x.get("pass"):
    print("tree row passes")
else:
    det = str(x.get("detail"))
    print("tree row fails naming both trees" if sys.argv[1][:7] in det and head[:7] in det else "tree row fails: %s" % det[:80])
PY
}
_open65 none; _c65_tree="$(_tree65)"; _start65; _fix65; _commit65; _recheck65 fixed; _close65
_c65_pass="$([[ "$(_res65 1)" == resolved:* ]] && echo 'closed' || echo "not closed: $(_res65 1)")|$(_gates65 "$_c65_tree" 1)"
_open65 none; _c65_tree="$(_tree65)"; _start65; _fix65; _commit65
_c65_fail="$([[ "$(_subj65)" == 'fix(demo): repair 1 at review' ]] && echo 'repair commit' || echo "HEAD $(_subj65)")|$(_gates65 "$_c65_tree" 1)"
assert_eq "repair: the commit gate passes a Review verdict that differs from the commit by closed repairs only, and fails it when a repair between them has no completed recheck" \
  "closed|tree row passes|repair commit|tree row fails naming both trees" "$_c65_pass|$_c65_fail"
_open65 none; _c65_tree="$(_tree65)"; echo 'echo later' >> src/demo.sh; git commit -q -am 'a change after the Review, no repair'
assert_eq "repair: the commit gate fails a Review verdict of another tree in a run with no repair, naming both trees" \
  "tree row fails naming both trees" "$(_gates65 "$_c65_tree")"

# --- the leftovers of the phase 6 recheck (lane E) ---
# RE1: a small change of docs only at Check or at Commit, after an honest Review and the CLI's own Check, leaves the
# tree Review judged; the commit gate's row checked tree compares that tree in every run, so the change runs Review of
# its files again, then Check and the commit gate, and the commit gate passes (no dead end at commit.fail)
_small65() { # _small65 <check|commit>: prints the steps the close listed and the commit gate's verdict after them
  local i a c
  _review65 docs/guide.md; review_done; "$TEMPER" gate review >/dev/null 2>&1
  "$TEMPER" state advance review_complete check >/dev/null 2>&1
  "$TEMPER" check run >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
  [[ "$1" == commit ]] && "$TEMPER" state advance check_complete commit >/dev/null 2>&1
  "$TEMPER" adhoc open --stage "$1" --reason 'a line of the guide' >/dev/null 2>&1
  echo 'one more line' >> docs/guide.md
  c="$("$TEMPER" adhoc close 2>&1)"
  for i in 1 2 3 4 5 6; do
    a="$(_x65 "r = d.get('action') if d.get('action') == 'work' and (d.get('ask') is None) else 'stop'")"
    [[ "$a" == work ]] || break
    [[ "$(_x65 "r = any(x.get('type') == 'temper:temper-review' for x in d.get('agents') or [])")" == True ]] && review_done
    while IFS= read -r c2; do [[ -n "$c2" ]] && bash -c "$c2" >/dev/null 2>&1; done \
      < <(_x65 "r = '\n'.join(list(d.get('calls') or []) + [c for x in d.get('agents') or [] for c in x.get('after') or []])")
  done
  "$TEMPER" gate commit >/dev/null 2>&1
  printf '%s|%s' "$(sed -n 's/.*still to run: //p' <<<"$c")" \
    "$(python3 -B -c "import json; g = json.load(open('.temper/gates.json')).get('commit') or {}; print(g.get('verdict'), ','.join(x.get('name') for x in g.get('requirements') or [] if not x.get('pass')) or 'every row')")"
}
assert_eq "repair: a small change of docs only at Check after the Review runs Review of its files, Check and the commit gate again, and the commit gate passes" \
  "review, check, commit|PASS every row" "$(_small65 check)"
assert_eq "repair: a small change of docs only at Commit after the Review runs Review of its files, Check and the commit gate again, and the commit gate passes" \
  "review, check, commit|PASS every row" "$(_small65 commit)"

# RE2: inside a repair window the fixer cannot widen the approved set by writing the person's answer itself: an evidence
# add of a Scope drift answer that answers no question the CLI asked is refused, and a row written by hand (no mod) is
# no answer the CLI recorded, so repair commit still stops on the file and the run asks
_open65 none; _start65; _fix65; echo 'echo other' > src/other.sh
_c65_out="$("$TEMPER" evidence add --stage build --phase feedback --claim 'drift src/other.sh: Add to plan: the fixer' 2>&1)"; _c65_rc=$?
python3 -B - <<'PY'
import json
p = ".temper/evidence/build.json"
rows = json.load(open(p))
rows.append({"claim": "drift src/other.sh: Allow once: written by hand", "phase": "feedback", "label": "HEURISTIC", "ts": "2026-11-20T00:00:00Z"})
json.dump(rows, open(p, "w"))
PY
_c65_head="$(git rev-parse HEAD)"; _commit65
assert_eq "repair: the fixer cannot add a file to the plan by writing the answer row: evidence add refuses it, and a row by hand is no answer" \
  "refused|says the question|not committed|scope.drift" \
  "$([[ $_c65_rc -ne 0 ]] && echo refused || echo "rc 0: ${_c65_out:0:60}")|$(grep -qi 'question' <<<"$_c65_out" && echo 'says the question' || echo "says: ${_c65_out:0:80}")|$([[ "$(git rev-parse HEAD)" == "$_c65_head" ]] && echo 'not committed' || echo "committed $(_subj65)")|$(_x65 "q = d.get('ask') or {}; r = 'scope.drift' if q.get('id') == 'scope.drift' and 'src/other.sh' in json.dumps(q) else 'asked %s' % q.get('id')")"

# RE3: the fixer's drift ask of a file no answer lets a repair commit (a manifest, the config) is refused at the ask, so
# the person is never asked a question whose answer cannot take effect
_open65 none; _start65
_c65_a="$("$TEMPER" drift ask --path go.mod --why 'the fix needs a module' --change 'one require line' 2>&1)"; _c65_rc=$?
_c65_b="$("$TEMPER" drift ask --path .claude/temper.config --why 'the fix needs a key' --change 'one line' 2>&1)"; _c65_rc2=$?
assert_eq "repair: the fixer's drift ask of a manifest or the config is refused, says it needs a step back, and asks nothing" \
  "refused|step back|refused|step back|no drift asked" \
  "$([[ $_c65_rc -ne 0 ]] && echo refused || echo "rc 0")|$(grep -qi 'step back' <<<"$_c65_a" && echo 'step back' || echo "says: ${_c65_a:0:80}")|$([[ $_c65_rc2 -ne 0 ]] && echo refused || echo "rc 0")|$(grep -qi 'step back' <<<"$_c65_b" && echo 'step back' || echo "says: ${_c65_b:0:80}")|$(_x65 "r = 'no drift asked' if (d.get('ask') or {}).get('id') != 'scope.drift' else 'scope.drift asked'")"

# RE4 and RE10: a finding on a shell file named like a test outside the plan is outside the approved set for the commit
# (the gate's test pattern), so repair start refuses it as can_start's outside the plan test, with the same pattern
_review65; _finding65 high 'src/other_test.sh:3 the helper test asserts nothing' 'the test passes on any input' 'assert the output' none
review_done; "$TEMPER" gate review >/dev/null 2>&1
assert_eq "repair: start refuses a finding on a shell file named like a test outside the plan, as the commit would" "$REFUSED65" \
  "$(_refused65 'outside the plan')"

# RE9: the revert of a repair not committed removes a guarded file the fixer created (a new git hook, a new file of the
# spec folder), and says which file still differs when one does
_open65 none; _start65; _fix65
_c65_hook="$(python3 -B - <<'PY'
import os, subprocess
p = os.path.join(subprocess.run(["git", "rev-parse", "--git-path", "hooks"], stdout=subprocess.PIPE, text=True).stdout.strip(), "post-commit")
os.makedirs(os.path.dirname(p), exist_ok=True)
open(p, "w").write("#!/bin/sh\necho planted\n")
os.chmod(p, 0o755)
print(p)
PY
)"
echo 'a note of the fixer' > .temper/specs/demo/fixer-note.md
_commit65
_c65_out="$("$TEMPER" repair revert 2>&1)"
assert_eq "repair: revert of a repair not committed removes a new git hook and a new spec file of the fixer" \
  "hook gone|note gone|reverted" \
  "$([[ -e "$_c65_hook" ]] && echo 'hook left' || echo 'hook gone')|$([[ -e .temper/specs/demo/fixer-note.md ]] && echo 'note left' || echo 'note gone')|$(grep -qi 'reviewed tree again' <<<"$_c65_out" && echo reverted || echo "says: ${_c65_out:0:80}")"

# RE12: the staged list of repair commit and of the carve out is read with -z, so a planned file whose name git quotes
# (a double quote in it) is the approved file it is, and the repair is committed
_open65 none
python3 -B -c "
import json
p = '.temper/build-state.json'; d = json.load(open(p)); d['approved_files'] = list(d.get('approved_files') or []) + ['src/q\"x.sh']
json.dump(d, open(p, 'w'), indent=2)"
_start65; _fix65; echo 'echo q' > 'src/q"x.sh'; git add -- 'src/q"x.sh'
_commit65
assert_eq "repair: a staged planned file whose name git quotes is committed as the approved file it is" \
  "repair commit with the file" \
  "$([[ "$(_subj65)" == 'fix(demo): repair 1 at review' ]] && grep -qxF 'src/q"x.sh' <<<"$(git show --name-only --format= -z HEAD | tr '\0' '\n')" && echo 'repair commit with the file' || echo "HEAD $(_subj65)")"

# RE5 and RE11: the fixer's brief names the drift ask of a repair, and the doc of the passed Review says where Repair again
# stands first
assert_eq "repair: the fixer's brief sends a file outside the plan to temper drift ask and reads a Drift decision line in a repair" \
  "drift ask|Drift decision" \
  "$(awk '/A repair in place/,/A record pass/' "$REPO_ROOT/agents/build.md" | grep -c 'drift ask' >/dev/null && echo 'drift ask' || echo 'no drift ask')|$(awk '/A repair in place/,/A record pass/' "$REPO_ROOT/agents/build.md" | grep -c 'Drift decision' >/dev/null && echo 'Drift decision' || echo 'no Drift decision')"
assert_eq "repair: docs/flow.md says a passed Review with an open high finding offers Repair again first where it may start" \
  "Repair again first" \
  "$(grep -A2 'A passed Review with an open finding at high or above' "$REPO_ROOT/docs/flow.md" | tr '\n' ' ' | grep -c 'Repair again' >/dev/null && echo 'Repair again first' || echo 'Loop back only')"
cd "$WORKDIR" || true
rm -rf "$T65"
