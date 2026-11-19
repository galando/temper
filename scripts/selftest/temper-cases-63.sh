# Case file 63 (WP22): one digest, the reuse store and the flaky recheck. The same command on the same tree runs once:
# one digest says what "the same tree" is (the work tree as it is, without .temper/, .claude/ and the byproducts of a
# run), the store keeps a pass and a failure per key in the git common folder, every row and verdict names the tree it
# judged, a failure that is not the change's is run once more at once, and `--fresh` is the person's counted way to run
# a check whatever the store holds. Sourced by test-temper.sh; its helpers (fresh, gpass, gfail, _at) are used here,
# and the builders below are this file's own. Token: w22. Every command of this file counts its runs in a file of the
# git folder (outside every work tree, so a count never changes a digest), and every baseline call runs in the
# foreground. A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the file always runs to its
# end. The runner is called the way a gate calls it, `run_env.run_cached(folder, limit, [command])`, whose three
# values (output, exit, the date of a reused result or '') stay as they are (spec trap 6).

# --- the helpers of this file ---
_x63() { # _x63 <python code over d, the JSON of temper next>: prints r. opts(d) is every option of the question and of
         # its More question, opt(d, i) the one with that id, short(c) a call without the path of the CLI
  python3 -B - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
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
def short(c):
    return re.sub(r"^\S*/temper ", "", str(c))
r = None
exec(sys.argv[1])
print(r)
PY
}
_clean63() { # the files of this file's projects taken out of the case folder
  rm -rf src unit a b __pycache__ .claude/worktrees
  rm -f ./*63.sh ./*63.txt .coverage
}
_scripts63() { # the commands of this file's projects: each appends a line to .git/count63 when it starts
  local c="$WORKDIR/.git/count63"
  printf 'echo run >> "%s"\necho ok\n' "$c" > pass63.sh
  printf 'echo run >> "%s"\nsleep 2\necho ok\n' "$c" > slow63.sh
  # a run that leaves a byte compiled file and a coverage file in its folder, neither ignored by the project
  printf 'echo run >> "%s"\nmkdir -p __pycache__\necho x > __pycache__/by63.cpython-313.pyc\necho x > .coverage\necho ok\n' \
    "$c" > by63.sh
  # passes or fails as .git/flip63 says: a fact outside the tree, as a service started by hand is
  printf 'echo run >> "%s"\nif [ "$(cat "%s" 2>/dev/null)" = fail ]; then echo "FAIL: test_flip"; exit 1; fi\necho ok\n' \
    "$c" "$WORKDIR/.git/flip63" > flip63.sh
  # fails once on a tree that holds changed63.txt (its first run there), then passes: a flaky test the change met.
  # FLAKY63_LINE is its fail line; BASE63_LINE, when set, is a fail line it prints on every tree (red on the base)
  printf 'echo run >> "%s"\nbad=""\n[ -n "${BASE63_LINE:-}" ] && { echo "$BASE63_LINE"; bad=1; }\n' "$c" > flaky63.sh
  printf 'if [ -f changed63.txt ] && [ ! -f "%s" ]; then : > "%s"; echo "${FLAKY63_LINE:-FAIL: test_clock}"; bad=1; fi\n' \
    "$WORKDIR/.git/flaky63.done" "$WORKDIR/.git/flaky63.done" >> flaky63.sh
  printf '[ -n "$bad" ] && exit 1\necho ok\n' >> flaky63.sh
}
_repo63() { # the case folder as a git repository on main with one commit of every file but the run's own (.temper/ is
            # excluded); the count of runs starts at 0
  rm -rf .git; git init -q . 2>/dev/null; git checkout -q -B main 2>/dev/null
  git config user.email t@example.com; git config user.name T
  printf '/.temper/\n' >> .git/info/exclude
  git add -A >/dev/null 2>&1; git commit -q -m base
  : > .git/count63
}
_files63() { # a tracked source file, and the folders a and b with the same content
  mkdir -p src a b
  echo 'echo a' > src/a63.sh
  echo same > a/same63.txt; echo same > b/same63.txt
}
_cmd63() { printf 'check:\n  commands:\n    test: "%s"\n' "$1" >> .claude/temper.config; }   # the config's test command
_runs63() { if [[ -f .git/count63 ]]; then grep -c . .git/count63 | tr -d ' '; else echo 0; fi; }
_rc63() { # _rc63 <command> [folder]: one call of the CLI's runner in the folder (the case folder by default); prints the
          # exit and whether the result was run or reused
  python3 -B - "$REPO_ROOT/scripts" "${2:-$WORKDIR}" "$1" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import run_env
out, rc, reused = run_env.run_cached(sys.argv[2], 60, [sys.argv[3]])
print("%s:%s" % (rc, "reused" if reused else "ran"))
PY
}
_store63() { # _store63 <python expression over s, the store temper-results.json of the git folder ({} when absent);
             # entries are its dict values, lists the keys of its list values>
  python3 -B - "$1" <<'PY'
import json, sys
try:
    s = json.load(open(".git/temper-results.json"))
except (OSError, ValueError):
    s = {}
s = s if isinstance(s, dict) else {}
entries = [v for v in s.values() if isinstance(v, dict)]
lists = [k for k, v in s.items() if isinstance(v, list)]
print(eval(sys.argv[1]))
PY
}
_row63() { # _row63 <ledger> <claim start> <python expression over x, the last row of that ledger whose claim starts so>;
           # V63 in the environment is v there
  python3 -B - "$1" "$2" "$3" <<'PY'
import json, os, sys
v = os.environ.get("V63", "")
try:
    rows = [x for x in json.load(open(sys.argv[1])) if str(x.get("claim", "")).startswith(sys.argv[2])]
except (OSError, ValueError, AttributeError):
    rows = []
x = rows[-1] if rows else {}
print(eval(sys.argv[3]))
PY
}
_suite63() { # _suite63 <test command>: a fresh run at Check in a repository of this file's scripts whose config names it
  fresh; _clean63; _scripts63; _files63; _cmd63 "$1"; _repo63
  gpass intent plan build review; _at check
}
_check63() { "$TEMPER" check run "$@" >/dev/null 2>&1; }
_approved63() { # _approved63 <path>...: the files the person approved, in the run state, as the approval records them
  python3 -B - "$@" <<'PY'
import json, sys
p = ".temper/build-state.json"
d = json.load(open(p))
d["approved_files"] = sys.argv[1:]
json.dump(d, open(p, "w"), indent=2)
PY
}
_used63() { python3 -B -c "import json; print(len(json.load(open('.temper/budget.json')).get('used') or []))" 2>/dev/null || echo 0; }

# --- w22 one tree, two places: the group worktree and the project folder with the same content share one run ---
fresh; _clean63; _scripts63; _cmd63 "bash pass63.sh"
cat > .temper/specs/demo/tasks.md <<'TASKS'
# Tasks: demo

**Integration:** `true`

## Group G1: Core
**Depends:** none
**Validate:** `bash pass63.sh`
**Context:**
The core.

### Task 1: first
**File:** `src/a63.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- a holds
- [ ] done
TASKS
_repo63; git checkout -q -B feature/demo
printf '{"plan":{"verdict":"PASS"},"intent":{"verdict":"PASS"}}\n' > .temper/gates.json
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
"$TEMPER" group start G1 >/dev/null 2>&1
python3 -B - <<'PY'
import json
d = json.load(open(".temper/groups.json"))
d.setdefault("tasks", {})["1"] = {"status": "passed", "group": "G1"}
json.dump(d, open(".temper/groups.json", "w"))
for f in (".temper/groups.json", ".temper/build-state.json"):
    d = json.load(open(f)); d.pop("plan_hash", None); json.dump(d, open(f, "w"))
PY
"$TEMPER" group gate G1 >/dev/null 2>&1
_o63="group=$(_row63 .temper/evidence/build.json "Group G1 validate" "'%s,%s' % (x.get('exit_code'), 'reused' if x.get('reused') else 'ran')"):$(_runs63)"
_t63="$(_row63 .temper/evidence/build.json "Group G1 validate" "x.get('tree') or ''")"
_check63
_o63+="|project=$(_row63 .temper/evidence/check.json tests "'%s,%s' % (x.get('exit_code'), 'reused' if x.get('reused') else 'ran')"):$(_runs63)"
_o63+="|tree=$(V63="$_t63" _row63 .temper/evidence/check.json tests "'same' if v and x.get('tree') == v else 'group %s, project %s' % (v or None, x.get('tree'))")"
assert_eq "w22 one tree, two places: the Validate of a group and Check's suite of the same text on the same content run once; the second row says reused and names the same tree" \
  "group=0,ran:1|project=0,reused:1|tree=same" "$_o63"
_clean63

# --- w22 byproducts: a command that leaves __pycache__ and .coverage (not ignored) is reused on its second call ---
fresh; _clean63; _scripts63; _repo63
_b63="first=$(_rc63 "bash by63.sh")"
_b63+="|left=$([[ -f .coverage && -d __pycache__ && -z "$(git check-ignore .coverage __pycache__/by63.cpython-313.pyc)" ]] && echo 'not ignored' || echo 'no byproducts')"
_b63+="|second=$(_rc63 "bash by63.sh")|runs=$(_runs63)"
assert_eq "w22 byproducts: a command that leaves __pycache__ and a .coverage file the project does not ignore is reused on its second call" \
  "first=0:ran|left=not ignored|second=0:reused|runs=1" "$_b63"
_clean63

# --- w22 what ends a pass: each change below runs the command again; the same call after it is reused again ---
_ends63() { # _ends63 <kind> <command> <shell code of the change> [command after the change]: a fresh repository, then
            # four calls of the runner, the change between the second and the third; prints kind=<runs after each call>
  local r
  fresh; _clean63; _scripts63; _files63; _repo63
  _rc63 "$2" >/dev/null; r="$(_runs63)"
  _rc63 "$2" >/dev/null; r+=",$(_runs63)"
  eval "$3"
  _rc63 "${4:-$2}" >/dev/null; r+=",$(_runs63)"
  _rc63 "${4:-$2}" >/dev/null; r+=",$(_runs63)"
  echo "$1=$r"
}
_e63="$(_ends63 tracked "bash pass63.sh" "echo 'echo b' > src/a63.sh")"
_e63+="|$(_ends63 untracked "bash pass63.sh" "echo new > src/new63.sh")"
_e63+="|$(_ends63 removed "bash pass63.sh" "rm src/a63.sh")"
_e63+="|$(_ends63 command "bash pass63.sh" ":" "bash pass63.sh again")"
_e63+="|$(_ends63 setup "bash pass63.sh" "printf 'setup:\n  env:\n    X63: \"1\"\n' >> .claude/temper.config")"
# another folder of the same repository with the same content: the command run from a, then from b
_folder63() {
  local r
  fresh; _clean63; _scripts63; _files63; _repo63
  _rc63 "bash $WORKDIR/pass63.sh" "$WORKDIR/a" >/dev/null; r="$(_runs63)"
  _rc63 "bash $WORKDIR/pass63.sh" "$WORKDIR/a" >/dev/null; r+=",$(_runs63)"
  _rc63 "bash $WORKDIR/pass63.sh" "$WORKDIR/b" >/dev/null; r+=",$(_runs63)"
  _rc63 "bash $WORKDIR/pass63.sh" "$WORKDIR/b" >/dev/null; r+=",$(_runs63)"
  echo "folder=$r"
}
_e63+="|$(_folder63)"
# another first version line of the program the command starts: a fake tool63 on the PATH reads its version from a file
_version63() {
  local r
  fresh; _clean63; _scripts63; _files63; _repo63
  mkdir -p .git/bin63; echo 1.0 > .git/ver63
  printf '#!/bin/sh\nif [ "$1" = --version ]; then echo "tool63 $(cat "%s")"; exit 0; fi\necho run >> "%s"\necho ok\n' \
    "$WORKDIR/.git/ver63" "$WORKDIR/.git/count63" > .git/bin63/tool63
  chmod +x .git/bin63/tool63
  PATH="$WORKDIR/.git/bin63:$PATH" _rc63 "tool63 run" >/dev/null; r="$(_runs63)"
  PATH="$WORKDIR/.git/bin63:$PATH" _rc63 "tool63 run" >/dev/null; r+=",$(_runs63)"
  echo 2.0 > .git/ver63
  PATH="$WORKDIR/.git/bin63:$PATH" _rc63 "tool63 run" >/dev/null; r+=",$(_runs63)"
  PATH="$WORKDIR/.git/bin63:$PATH" _rc63 "tool63 run" >/dev/null; r+=",$(_runs63)"
  echo "version=$r"
}
_e63+="|$(_version63)"
# the acceptance command: its tests live under .temper/, outside the digest, so the lock's file digests are in its key.
# The lock is written as `temper acceptance lock` writes it (the spec folder, the command, the digest of each file).
_lock63() { python3 -B - <<'PY'
import hashlib, json, os
spec = ".temper/specs/demo"
files = {}
for f in sorted(os.listdir(os.path.join(spec, "acceptance"))):
    p = os.path.join(spec, "acceptance", f)
    files[p] = hashlib.sha256(open(p, "rb").read()).hexdigest()
os.makedirs(".temper/evidence", exist_ok=True)
json.dump({"spec": spec, "cmd": "bash %s/acceptance/test_acc63.sh" % spec, "files": files, "launches": 0,
           "ts": "2026-11-19T00:00:00Z"}, open(".temper/evidence/acceptance-lock.json", "w"), indent=2)
PY
}
_acc63() { if [[ -f .git/acc63 ]]; then grep -c . .git/acc63 | tr -d ' '; else echo 0; fi; }
_lockrun63() {
  local r
  _suite63 "true"; mkdir -p .temper/specs/demo/acceptance
  printf 'echo run >> "%s"\necho ok\n' "$WORKDIR/.git/acc63" > .temper/specs/demo/acceptance/test_acc63.sh; _lock63
  _check63; r="$(_acc63)"
  _check63; r+=",$(_acc63)"
  printf '# corrected\n' >> .temper/specs/demo/acceptance/test_acc63.sh; _lock63
  _check63; r+=",$(_acc63)"
  _check63; r+=",$(_acc63)"
  echo "lock=$r"
}
_e63+="|$(_lockrun63)"
assert_eq "w22 what ends a pass: an edit of a tracked file, a new untracked file, a removed file, another command text, a changed setup block, another folder, another first version line and a changed lock digest each run again" \
  "tracked=1,1,2,2|untracked=1,1,2,2|removed=1,1,2,2|command=1,1,2,2|setup=1,1,2,2|folder=1,1,2,2|version=1,1,2,2|lock=1,1,2,2" "$_e63"
rm -rf .git/bin63; rm -f .git/ver63 .git/acc63; _clean63

# --- w22 a byproduct is never a tracked file: entries edited into the list by hand are ignored ---
fresh; _clean63; _scripts63; _files63; mkdir -p unit; echo 'echo n' > src/new63.sh; echo 'pass' > unit/test_new63.py
_repo63
git rm -q --cached src/new63.sh unit/test_new63.py; git commit -q -m 'two files the change adds'
_approved63 src/a63.sh src/new63.sh
_rc63 "bash by63.sh" >/dev/null
_n63="list=$(_store63 "'yes' if len(lists) == 1 and '.coverage' in s[lists[0]] else 'no list of byproducts (lists %s)' % lists")"
python3 -B - <<'PY'
import json
p = ".git/temper-results.json"
try:
    s = json.load(open(p))
except (OSError, ValueError):
    s = {}
for k, v in s.items():
    if isinstance(v, list):
        v.extend(["src/a63.sh", "src/new63.sh", "unit/test_new63.py"])
json.dump(s, open(p, "w"))
PY
_rc63 "bash by63.sh" >/dev/null
_n63+="|unchanged=$(_rc63 "bash by63.sh")"
_r0=$(_runs63); echo 'echo a2' > src/a63.sh; _rc63 "bash by63.sh" >/dev/null
_n63+="|tracked=$([[ $(_runs63) -gt $_r0 ]] && echo ran || echo 'not run')"
_r0=$(_runs63); echo 'echo n2' > src/new63.sh; _rc63 "bash by63.sh" >/dev/null
_n63+="|declared=$([[ $(_runs63) -gt $_r0 ]] && echo ran || echo 'not run')"
_r0=$(_runs63); echo 'fail' > unit/test_new63.py; _rc63 "bash by63.sh" >/dev/null
_n63+="|test=$([[ $(_runs63) -gt $_r0 ]] && echo ran || echo 'not run')"
assert_eq "w22 a byproduct is never a tracked file: a list edited by hand to hold a tracked file, a declared file and a test file ignores them; an edit of each ends the pass" \
  "list=yes|unchanged=0:reused|tracked=ran|declared=ran|test=ran" "$_n63"
_clean63

# --- w22 a failure is not a pass: kept beside the pass, never returned as one, not run again on the same key ---
_suite63 "bash flip63.sh"
echo pass > .git/flip63; _check63
_f63="pass=$(_runs63):$(_row63 .temper/evidence/check.json tests "x.get('exit_code')")"
echo fail > .git/flip63; _check63 --fresh
_f63+="|fresh=$(_runs63):$(_row63 .temper/evidence/check.json tests "x.get('exit_code')")"
_f63+="|kept=$(_store63 "'both' if any(isinstance(e.get('pass'), dict) and isinstance(e.get('fail'), dict) for e in entries) else 'not both'")"
_fts63="$(_store63 "next((str(e['fail'].get('ts')) for e in entries if isinstance(e.get('fail'), dict)), '')")"
_check63
_f63+="|again=$(_runs63):$(_row63 .temper/evidence/check.json tests "x.get('exit_code')")"
_f63+="|date=$(V63="$_fts63" _row63 .temper/evidence/check.json tests "'named' if v and v in json.dumps({k: w for k, w in x.items() if k != 'ts'}) else 'not named (%s)' % (v or 'no failure kept')")"
assert_eq "w22 a failure is not a pass: a failed run is kept beside the pass; the next call on the same key runs nothing and returns the failure, not the pass, and its row names when it failed" \
  "pass=1:0|fresh=2:1|kept=both|again=2:1|date=named" "$_f63"
rm -f .git/flip63; _clean63

# --- w22 flaky: a failure that is not the change's runs once more at once, inside the same call ---
_flaky63() { # _flaky63 [declared file]: a run at Check whose suite is flaky63.sh; the baseline ran it on the base, then the
             # change adds changed63.txt (and the declared file, when given, is approved)
  _suite63 "bash flaky63.sh"; rm -f .git/flaky63.done
  [[ -z "${1:-}" ]] || _approved63 "$1"
  rm -f .temper/evidence/baseline.json; TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline start >/dev/null 2>&1
  TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline clean >/dev/null 2>&1 || true
  echo changed > changed63.txt
}
_base63() { python3 -B -c "import json; print(json.load(open('.temper/evidence/baseline.json')).get('result'))" 2>/dev/null; }
_flaky63
_l63="base=$(_base63)"
_r0=$(_runs63); _check63
_l63+="|one call=$(( $(_runs63) - _r0 )) runs"
_l63+="|row=$(_row63 .temper/evidence/check.json tests "'%s,%s' % ('flaky' if x.get('flaky') else 'not flaky', x.get('exit_code'))")"
_l63+="|store=$(_store63 "'flaky' if any(e.get('flaky') for e in entries) else 'not flaky'")"
_flaky63 src/clock63.sh
_r0=$(_runs63); FLAKY63_LINE='FAIL: src/clock63.sh:3 expected the final value' _check63
_l63+="|declared=$(( $(_runs63) - _r0 )) run,$(_row63 .temper/evidence/check.json tests "'flaky' if x.get('flaky') else 'not flaky'")"
assert_eq "w22 flaky: a command that passed on the base, fails once and then passes runs twice in one call (no agent between), and the row and the store entry say flaky; a failure that names a declared file runs once" \
  "base=green|one call=2 runs|row=flaky,0|store=flaky|declared=1 run,not flaky" "$_l63"
# The base itself fails one test (a red base the person went on with, as in the scenario broken-flaky): a failure known
# at the base counts as the base's pass. The change meets a flaky test once; the second run fails like the base.
_suite63 "bash flaky63.sh"; rm -f .git/flaky63.done
rm -f .temper/evidence/baseline.json
BASE63_LINE='FAIL: test_legacy' TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline start >/dev/null 2>&1
TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline accept-red --reason 'the base was red before this run' >/dev/null 2>&1 || true
TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline clean >/dev/null 2>&1 || true
echo changed > changed63.txt
_k63="base=$(_base63)"
_r0=$(_runs63); BASE63_LINE='FAIL: test_legacy' _check63
_k63+="|one call=$(( $(_runs63) - _r0 )) runs"
_k63+="|row=$(_row63 .temper/evidence/check.json tests "'flaky' if x.get('flaky') else 'not flaky'")"
_k63+="|store=$(_store63 "'flaky' if any(e.get('flaky') for e in entries) else 'not flaky'")"
"$TEMPER" gate check >/dev/null 2>&1
_k63+="|tests pass=$(python3 -B -c "
import json
e = json.load(open('.temper/gates.json')).get('check') or {}
r = next((x for x in e.get('requirements') or [] if x.get('name') == 'tests pass'), None)
print('absent' if r is None else '%s:%s' % (r.get('pass'), r.get('state')))" 2>/dev/null)"
assert_eq "w22 flaky: a failure known at the base counts as the base's pass: a new fail line that is gone on the second run in the same call is flaky, and tests pass skips the base's lines" \
  "base=red|one call=2 runs|row=flaky|store=flaky|tests pass=None:skipped" "$_k63"
rm -f .git/flaky63.done; _clean63

# --- w22 two at once: one key runs once and the second call reads the first one's entry; two keys lose no entry ---
fresh; _clean63; _scripts63; _repo63
_rc63 "bash slow63.sh" > .git/one63 & _p1=$!
_rc63 "bash slow63.sh" > .git/two63 & _p2=$!
wait "$_p1" "$_p2"
_w63="same=$(_runs63):$(sort .git/one63 .git/two63 | paste -sd, -)"
_rc63 "bash slow63.sh first" > .git/one63 & _p1=$!
_rc63 "bash slow63.sh second" > .git/two63 & _p2=$!
wait "$_p1" "$_p2"
_w63+="|different=$(_runs63)"
_w63+="|again=$(_rc63 "bash slow63.sh first"),$(_rc63 "bash slow63.sh second"):$(_runs63)"
assert_eq "w22 two at once: two calls for one key at the same moment give one run, the second reads the first one's entry; two calls for different keys lose no entry" \
  "same=1:0:ran,0:reused|different=3|again=0:reused,0:reused:3" "$_w63"
rm -f .git/one63 .git/two63; _clean63

# --- w22 run it anyway: --fresh runs although a pass is kept, marks the row forced, spends one repeat; at the limit
#     the call is refused and runs nothing ---
_suite63 "bash pass63.sh"
_check63; _check63
_a63="kept=$(_runs63)"
_check63 --fresh
_a63+="|fresh=$(_runs63):$(_row63 .temper/evidence/check.json tests "'forced' if x.get('forced') else 'not forced'")"
_n0="$(_used63)"
_ok63=1; _once63=yes; _refused63="never refused"
for _i63 in 2 3 4 5 6 7 8; do
  _r0=$(_runs63)
  if "$TEMPER" check run --fresh >/dev/null 2>&1; then
    _ok63=$((_ok63 + 1)); [[ $(_runs63) -eq $((_r0 + 1)) ]] || _once63="no ($_i63)"
  else
    _refused63="refused with $(( $(_runs63) - _r0 )) runs"; break
  fi
done
_a63+="|spent=$([[ "$_n0" == 1 && "$(_used63)" == "$_ok63" ]] && echo 'one each' || echo "$_n0 after the first, $(_used63) for $_ok63")"
_a63+="|each ran once=$_once63|limit=$_refused63"
assert_eq "w22 run it anyway: check run --fresh runs although a pass is kept, its row is forced and it spends one repeat; at the limit the call is refused and runs nothing" \
  "kept=1|fresh=2:forced|spent=one each|each ran once=yes|limit=refused with 0 runs" "$_a63"
_anyway63() { _x63 "a = d.get('ask') or {}; o = opt(d, 'run-anyway') or {}
r = '%s:%s' % (a.get('id'), 'fresh' if any(' check run --fresh' in ' ' + short(c) for c in o.get('calls') or []) else 'no run-anyway')"; }
fresh; gpass intent plan build review; gfail check "tests pass" "FAIL: test_a"; _at check
_y63="$(_anyway63)"
fresh; gpass intent plan build review check; _at check
_y63+="|$(_anyway63)"
assert_eq "w22 run it anyway: the failed Check question and the passed Check question offer run-anyway, whose call is check run --fresh" \
  "check.fail:fresh|check.pass:fresh" "$_y63"
_clean63

# --- w22 run it anyway is the person's: a run that goes on by itself never takes it; at a stop the answer runs it ---
_suite63 "bash pass63.sh"; _check63
_armed63() { # _armed63 <stop>: the run goes on by itself from Build (WP11), parked at <stop> when given
  python3 -B - "${1:-}" <<'PY'
import json, sys
p = ".temper/build-state.json"
d = json.load(open(p))
d.update(run_mode="autonomous", unattended_from="build")
d.pop("parked", None)
if sys.argv[1]:
    d["parked"] = sys.argv[1]
json.dump(d, open(p, "w"), indent=2)
PY
}
_armed63
_r0=$(_runs63); _n0="$(_used63)"
_out63="$("$TEMPER" check run --fresh 2>&1)"; _rc=$?
_p63="armed=$_rc:$(head -1 <<<"$_out63" | cut -d: -f1):$(( $(_runs63) - _r0 )) runs:$(( $(_used63) - _n0 )) spent"
_out63="$("$TEMPER" integrate --fresh 2>&1)"
_p63+="|integrate=$(head -1 <<<"$_out63" | cut -d: -f1):$(( $(_used63) - _n0 )) spent"
_armed63 check; _r0=$(_runs63)
_check63 --fresh; _rc=$?
_p63+="|parked=$_rc:$(( $(_runs63) - _r0 )) run:$(( $(_used63) - _n0 )) spent"
assert_eq "w22 run it anyway is the person's: in a run that goes on by itself check run --fresh and integrate --fresh are refused, run nothing and spend nothing; at a stop the person's answer runs it" \
  "armed=1:BLOCKED:0 runs:0 spent|integrate=BLOCKED:0 spent|parked=0:1 run:1 spent" "$_p63"
_clean63

# --- w22 the store does not grow without bound: a lock file goes with its entry, a byproduct that is gone leaves the list ---
fresh; _clean63; _scripts63; _repo63
_s63="$(python3 -B - "$REPO_ROOT/scripts" "$WORKDIR" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1])
import run_env
wt = sys.argv[2]
locks = os.path.join(wt, ".git", "temper-locks")
def lists():
    s = json.load(open(os.path.join(wt, ".git", "temper-results.json")))
    keys = {k for k, v in s.items() if isinstance(v, dict)}
    files = {f[:-5] for f in os.listdir(locks) if f.endswith(".lock")}
    return keys, files, s.get("byproducts") or []
run_env.KEEP = 1
run_env.run_cached(wt, 60, ["bash pass63.sh one"])
run_env.run_cached(wt, 60, ["bash pass63.sh two"])
keys, files, _ = lists()
out = ["locks=%s" % ("one each entry" if files == keys else "%d for %d entries" % (len(files), len(keys)))]
run_env.KEEP = 200
run_env.run_cached(wt, 60, ["bash by63.sh"])
run_env.run_cached(wt, 60, ["bash pass63.sh three"])
out.append("present=%d" % len(lists()[2]))
os.remove(os.path.join(wt, "__pycache__", "by63.cpython-313.pyc")); os.rmdir(os.path.join(wt, "__pycache__"))
os.remove(os.path.join(wt, ".coverage"))
run_env.run_cached(wt, 60, ["bash pass63.sh four"])
out.append("gone=%d" % len(lists()[2]))
print("|".join(out))
PY
)"
assert_eq "w22 the store does not grow without bound: past the store's limit a dropped entry takes its lock file along, and a byproduct no worktree holds leaves the list" \
  "locks=one each entry|present=2|gone=0" "$_s63"
_clean63

# --- w22 every verdict names its tree: the digest of the project folder when the verdict was computed ---
fresh; _clean63; _scripts63; _files63; _repo63; gpass intent plan build review; _at check
"$TEMPER" gate build >/dev/null 2>&1; "$TEMPER" gate check >/dev/null 2>&1
_tree63() { python3 -B -c "import json; print(json.load(open('.temper/gates.json')).get('$1', {}).get('tree'))" 2>/dev/null; }
_head63="$(git rev-parse 'HEAD^{tree}')"
_v63="build=$([[ "$(_tree63 build)" == "$_head63" ]] && echo 'HEAD tree' || echo "$(_tree63 build)")"
_v63+="|check=$([[ "$(_tree63 check)" == "$_head63" ]] && echo 'HEAD tree' || echo "$(_tree63 check)")"
_t63="$(_tree63 check)"
echo 'echo edited' > src/a63.sh; "$TEMPER" gate check >/dev/null 2>&1
_v63+="|edited=$([[ "$(_tree63 check)" != None && "$(_tree63 check)" != "$_t63" && "$(_tree63 check)" != "$_head63" ]] && echo changed || echo "same ($(_tree63 check))")"
assert_eq "w22 every verdict names its tree: after gate build and gate check each entry of gates.json holds the tree of the clean project, and an edit of a tracked file changes it" \
  "build=HEAD tree|check=HEAD tree|edited=changed" "$_v63"
_clean63; rm -f .git/count63
