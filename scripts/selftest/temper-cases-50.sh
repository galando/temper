# Case file 50 (WP09): a verdict is a verdict for every carrier. Sourced by test-temper.sh; its helpers (fresh, gpass,
# nx, _ev, second_group) are used here. `gate`, `task gate`, `group gate` and `integrate` print one line on stdout once
# they recorded a verdict, `VERDICT: <scope> <PASS or FAIL or PARKED>`, and `temper go` reads that line, and nothing
# else, to tell a recorded verdict from a call that broke. A case that checks that a call prints no marker also checks
# that a call of the same run that recorded a verdict prints one, so it cannot pass while no call prints a marker.

# --- the helpers of this file ---
_v50run() { # _v50run <Validate of G1> <Integration> [G2]: a run at Build whose plan (the tasks.md of setup with these
            # two commands, and the group of second_group when the third argument is G2) the person approved, with the
            # folder w for the worktree of group G1
  fresh
  python3 - "$1" "$2" <<'PY'
import sys
p = ".temper/specs/demo/tasks.md"
t = open(p).read().replace("**Validate:** `true`", "**Validate:** `%s`" % sys.argv[1], 1)
open(p, "w").write(t.replace("**Integration:** `true`", "**Integration:** `%s`" % sys.argv[2], 1))
PY
  [[ "${3:-}" == G2 ]] && second_group
  gpass intent plan
  "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  mkdir -p w
}
_v50g() { # _v50g <group G1 fields> <status of Task 1>: groups.json as _polg of temper-cases-28.sh writes it
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"worktree": "w", "branch": "temper/demo/G1", %s}}, ' "$1" \
    > .temper/groups.json
  printf '"tasks": {"1": {"status": "%s", "group": "G1"}}}\n' "$2" >> .temper/groups.json
}
_v50branch() { # _v50branch <branch>: the run's folder holds one commit and is on that branch; the run's branch is
               # feature/demo
  git config user.email t@example.com; git config user.name T
  git rev-parse -q --verify HEAD >/dev/null || git commit -q --allow-empty -m base
  git checkout -q -B "$1" 2>/dev/null
  "$TEMPER" state set branch feature/demo >/dev/null 2>&1
}
_v50n() { # _v50n <text> <line>: how many lines of the text are exactly that line
  printf '%s\n' "$1" | grep -cxF -- "$2"
}
_v50go() { # _v50go <code>: one value of the JSON object that `temper go` prints last (its stdout only)
  _ev "$1" "$("$TEMPER" go 2>/dev/null | tail -1)"
}
_v50gate() { # _v50gate <field>: that field of the gate of group G1 in groups.json
  python3 -c "import json, sys
g = json.load(open('.temper/groups.json'))['groups']['G1']
print((g.get('gate') or {}).get(sys.argv[1]))" "$1"
}

# --- the marker of `temper gate` ---
fresh
_v50pass="$("$TEMPER" gate intent 2>/dev/null)"
fresh; sed -i '/^Users cannot do the demo thing today\.$/d' .temper/specs/demo/intent.md
_v50fail="$("$TEMPER" gate intent 2>/dev/null)"
assert_eq "verdict: gate prints the marker as its last line" "VERDICT: gate:intent PASS|VERDICT: gate:intent FAIL" \
  "$(printf '%s\n' "$_v50pass" | tail -1)|$(printf '%s\n' "$_v50fail" | tail -1)"
# five case files, one helper file and scripts/e2e/loop.ts read the old line: it stays, beside the marker
assert_eq "verdict: the line temper gate <stage> -> <verdict> is still printed" "1|1|1|1" \
  "$(_v50n "$_v50pass" 'temper gate intent -> PASS')|$(_v50n "$_v50pass" 'VERDICT: gate:intent PASS')|$(
    _v50n "$_v50fail" 'temper gate intent -> FAIL')|$(_v50n "$_v50fail" 'VERDICT: gate:intent FAIL')"

# --- the marker of `group gate` ---
_v50run true true; _v50g '"status": "running"' running
_v50out="$("$TEMPER" group gate G1 2>/dev/null)"; _v50rc=$?
assert_eq "verdict: group gate prints it after a recorded FAIL" "1|1|FAIL" \
  "$_v50rc|$(_v50n "$_v50out" 'VERDICT: group:G1 FAIL')|$(_v50gate verdict)"
# G9 is in no group of the plan, G2 is in the plan and not started, and a bad flag stops before anything is read
_v50run true true G2; _v50g '"status": "running"' running
_v50g9="$("$TEMPER" group gate G9 2>&1)"; _v50g2="$("$TEMPER" group gate G2 2>&1)"
_v50flag="$("$TEMPER" group gate G1 --bogus 2>&1)"; _v50kept="$(_v50gate verdict)"
_v50out="$("$TEMPER" group gate G1 2>/dev/null)"
assert_eq "verdict: a group gate that recorded nothing prints no marker" "0|0|0|None|1" \
  "$(grep -c '^VERDICT:' <<<"$_v50g9")|$(grep -c '^VERDICT:' <<<"$_v50g2")|$(grep -c '^VERDICT:' <<<"$_v50flag")|$(
    printf '%s' "$_v50kept")|$(_v50n "$_v50out" 'VERDICT: group:G1 FAIL')"

# --- the marker of `integrate` ---
_v50run true true; _v50g '"status": "running"' running; _v50branch feature/demo
_v50out="$("$TEMPER" integrate 2>/dev/null)"; _v50rc=$?
assert_eq "verdict: integrate prints it for a recorded FAIL" "1|1|FAIL" \
  "$_v50rc|$(_v50n "$_v50out" 'VERDICT: integrate FAIL')|$(python3 -c \
    "import json; print((json.load(open('.temper/groups.json')).get('integration') or {}).get('verdict'))")"
_v50run true true; _v50g '"status": "running"' running; _v50branch master
_v50prot="$("$TEMPER" integrate 2>&1)"; _v50rc=$?
_v50kept="$(python3 -c "import json; print(json.load(open('.temper/groups.json')).get('integration'))")"
_v50branch feature/demo
_v50out="$("$TEMPER" integrate 2>/dev/null)"
assert_eq "verdict: integrate on a protected branch prints no marker" "3|0|None|1" \
  "$_v50rc|$(grep -c '^VERDICT:' <<<"$_v50prot")|$_v50kept|$(_v50n "$_v50out" 'VERDICT: integrate FAIL')"

# --- the marker of `task gate` ---
_v50run true true; _v50g '"status": "running"' running
_v50out="$("$TEMPER" task gate 1 --model haiku 2>/dev/null)"; _v50rc=$?
assert_eq "verdict: a failed task gate prints it" "1|1" "$_v50rc|$(_v50n "$_v50out" 'VERDICT: task:1 FAIL')"
_v50run true true; _v50g '"status": "parked", "parked": "Task 1 failed 3 attempts"' running
_v50out="$("$TEMPER" task gate 1 --model haiku 2>/dev/null)"; _v50rc=$?
assert_eq "verdict: a task gate refused for a parked group prints group:<G> PARKED" "1|1" \
  "$_v50rc|$(_v50n "$_v50out" 'VERDICT: group:G1 PARKED')"

# --- `temper go` reads the marker ---
# every task of G1 passed and its Validate fails: the next action is the group gate call, which records FAIL
_v50run false true; _v50g '"status": "running"' passed
_v50next="$(nx "d['action'] + ':' + ' '.join(c.split('/scripts/')[-1] for c in d.get('calls') or [])")"
assert_eq "verdict: temper go goes on after a failed group gate" \
  "work:temper group gate G1|ask|group.fail|['temper group gate G1']|True" \
  "$_v50next|$(_v50go "d['action'] + '|' + str((d.get('ask') or {}).get('id')) + '|' + str(d.get('ran')) + '|' + str(
    {'scope': 'group:G1', 'verdict': 'FAIL'} in (d.get('verdicts') or []))")"
# G1 passed and was confirmed, its branch is the run's head, and the Integration suite fails
_v50run true false; _v50g '"status": "passed", "gate": {"verdict": "PASS"}, "confirmed": true' passed
_v50branch feature/demo; git branch -f temper/demo/G1 >/dev/null 2>&1
_v50next="$(nx "d['action'] + ':' + ', '.join(c.split('/scripts/')[-1] for c in d.get('calls') or [])")"
_v50want="work:temper integrate, temper gate build|ask|build.fail|['temper integrate', 'temper gate build']"
assert_eq "verdict: temper go goes on after a failed integrate" "$_v50want|integrate FAIL, gate:build FAIL" \
  "$_v50next|$(_v50go "d['action'] + '|' + str((d.get('ask') or {}).get('id')) + '|' + str(d.get('ran')) + '|' + (
    ', '.join('%s %s' % (v.get('scope'), v.get('verdict')) for v in d.get('verdicts') or []))")"
# a tasks.md changed after the approval: group gate refuses in _plan_fresh, records nothing and prints no marker
_v50run true true; _v50g '"status": "running"' passed
sed -i 's/^\*\*Test:\*\* `true`$/**Test:** `true # changed`/' .temper/specs/demo/tasks.md
assert_eq "verdict: a call that broke is still an error" "error|['temper group gate G1']|[]|None" \
  "$(_v50go "d['action'] + '|' + str(d.get('ran')) + '|' + str(d.get('verdicts'))")|$(_v50gate verdict)"

# --- recorded() of scripts/go.py: only the call's own marker, of a call of the CLI that records a verdict ---
assert_eq "verdict: text alone is no verdict" "set|set|None|None|None|None|None" \
  "$(python3 -I - "$REPO_ROOT/scripts" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import go
cli = "/p/scripts/temper"
fail = "FAIL: group G1 Validate failed (exit 1): make test\n"
cases = [
    (cli + " group gate G1", fail + "VERDICT: group:G1 FAIL"),                              # its own scope
    (cli + " task gate 2 --model haiku", "FAIL: group G1 is parked\nVERDICT: group:G1 PARKED"),  # any group
    (cli + " group gate G1", fail + "VERDICT: group:G2 FAIL"),                              # another group
    (cli + " task gate 2 --model haiku", "VERDICT: task:3 FAIL"),                           # another task
    (cli + " state advance plan_complete build", "VERDICT: gate:plan PASS"),                  # no verdict call
    ("/other/scripts/temper gate plan", "temper gate plan -> FAIL\nVERDICT: gate:plan FAIL"), # not the CLI
    (cli + " gate plan", "temper gate plan -> FAIL\nthe test said VERDICT: gate:plan FAIL"),  # not alone on its line
]
print("|".join("None" if go.recorded(c, cli, o) is None else "set" for c, o in cases))
PY
)"
assert_eq "verdict: only the marker tells a verdict" "0" "$(grep -c -- '-> FAIL' "$REPO_ROOT/scripts/go.py")"
