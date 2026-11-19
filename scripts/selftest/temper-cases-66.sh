# Case file 66: the four parts of WP22 and WP23 the first build left out. The questions read the reuse store before they
# compare failure texts (WP22 step 8); a fix run's regression proof that fails twice the same way offers the person's
# "the regression test is wrong" (WP23 mechanism 9); check ahead of a feature run plants bugs only, timed by the store
# entry of the tree (WP23 mechanism 10, trap 9); a group's Validate in the owner's test text runs in the owner's run text
# (WP23 mechanism 2).
# Sourced by test-temper.sh. The helpers of temper-cases-64.sh are taken from that file as they are: its helper block
# (up to its first case), and the fix run builders by name. Token: p5gap.
source <(sed -n '1,/^# --- w23 what integrate runs/p' "$TESTS_DIR/temper-cases-64.sh")
for _f66 in _fix64 _fixafter64; do eval "$(sed -n "/^$_f66() {/,/^}/p" "$TESTS_DIR/temper-cases-64.sh")"; done
_why66() { python3 -B -c "
import json
e = json.load(open('.temper/gates.json')).get('$1') or {}
print('; '.join('%s: %s' % (x.get('name'), ' '.join(str(x.get('detail', '')).split())) for x in e.get('requirements') or [] if x.get('pass') is False))"; }
_tasks1_66() { python3 -B -c "
import json
d = json.load(open('.temper/groups.json')); d.setdefault('tasks', {})['1'] = {'status': 'passed', 'group': 'G1'}
json.dump(d, open('.temper/groups.json', 'w'))"; }

# --- p5gap the store first: a failure the store kept and gave back on the same tree is the same failure ---
# Build: a fix pass by rule (its reason starts "rule: ", so no text compare matches it) that changed nothing: integrate
# gets the kept failure back, and the question recommends Save for later
_run64; echo fail > "$P64/suite.mode"; _integ64; "$TEMPER" gate build >/dev/null 2>&1
"$TEMPER" state redo build --reason "rule: $(_why66 build)" >/dev/null 2>&1
_integ64; "$TEMPER" gate build >/dev/null 2>&1
_s1="build=$(_x64 "r = '%s:%s:%s' % (d.get('action'), rec(d), 'same' if 'failed the same way' in text(d) else 'not same')"):runs $(_n64 suite)"
# Check: a run nobody measured, asked again; the store kept the failure of the suite and gave it back
fresh; gpass intent plan build review; _at check
python3 -B - "$REPO_ROOT/scripts" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import run_env
key = "k66" * 8
run_env.store_change(run_env._store("."), lambda d: d.update({key: {"fail": {"ts": "2026-01-01T00:00:00Z", "rc": 5, "tail": "no tests ran",
                     "fail_lines": [], "class": "not measured", "limit": 60, "again": 2}, "last": "fail"}}))
json.dump([{"claim": "Integration suite", "cmd": "suite", "exit_code": 5, "executed_by": "cli", "key": key,
            "tree": "t", "reused": "2026-01-01T00:00:00Z", "ts": "2999-01-01T00:00:00Z"}], open(".temper/evidence/check.json", "w"))
PY
gfail check "tests pass" "no passing test-run evidence recorded"
"$TEMPER" state redo check --reason "the person installed the runner" >/dev/null 2>&1
gfail check "tests pass" "no passing test-run evidence recorded"
_s1+="|check=$(_x64 "r = '%s:%s' % (rec(d), 'same' if 'failed the same way' in text(d) else 'not same')")"
# a group: its check asked again on the same tree gets the kept failure; the code is not the cause
_tasks64 "$P64/suite" | m_setup; _progs64; _cmds64; echo fail > "$P64/suite.mode"; _tasks1_66
"$TEMPER" group gate G1 >/dev/null 2>&1; "$TEMPER" group gate G1 >/dev/null 2>&1
_s1+="|group=$(_x64 "r = '%s:%s' % (rec(d), 'same tree' if 'same tree' in text(d) else 'no word of the tree')"):runs $(_n64 suite)"
assert_eq "p5gap the store first: a failure the store kept and gave back on the same tree is the same failure after a fix pass by rule (Save for later), at a missing measurement asked again, and at a group's check (its command, not its code)" \
  "build=ask:save:same:runs 1|check=save:same|group=change-command:same tree:runs 1" "$_s1"

# --- p5gap the regression test is wrong: a proof that fails twice the same way offers the person's correction ---
_fix64
# the regression test passes on the code before the fix too: it proves nothing
printf 'echo total >> "%s/log"\n[ "$(bash src/other64.sh)" = a ] || { echo "FAIL: test_total expected a"; exit 1; }\n' "$P64" > unit/test_total64.sh
_after66="$(_fixafter64)"
_calls64 "$_after66"
_s2="first=$(_x64 "r = '%s:%s:%s' % (d.get('ask', {}).get('id'), rec(d), 'correct-test' if opt(d, 'correct-test') else 'no correct-test')")"
_opt64 redo; _calls64 "$_after66"
_s2+="|second=$(_x64 "o = opt(d, 'correct-test') or {}
r = '%s:%s:%s:%s' % (d.get('ask', {}).get('id'), rec(d), o.get('label'), 'the reason goes to Fix' if [short(c) for c in o.get('calls') or []] == [\"state redo fix --reason '{reason}'\", \"state set wrong_test '{reason}'\"] else o.get('calls'))")"
_opt64 correct-test
_s2+="|note=$(_x64 "a = (d.get('agents') or [{}])[0]
r = '%s:%s' % (a.get('type'), 'note' if 'the regression test is wrong: the test asks for what the intent does not say' in a.get('prompt', '') else 'no note')")"
assert_eq "p5gap the regression test is wrong: a fix run's regression proof that fails twice with the same text asks fix.fail with Correct the regression test (correct-test), whose reason the Fix agent gets as a note" \
  "first=fix.fail:redo:no correct-test|second=fix.fail:save:Correct the regression test:the reason goes to Fix|note=temper:temper-fix:note" "$_s2"

# --- p5gap check ahead: a feature run plants bugs only, timed by the store entry of the tree; a fix run warms the store ---
_ahead66() { # check ahead, then a wait for the planted bug file it writes last (no longer running); prints state and why
  local i
  rm -f .temper/evidence/mutation.json
  "$TEMPER" check ahead >/dev/null 2>&1
  for i in $(seq 1 300); do
    [[ -f .temper/evidence/mutation.json ]] && ! grep -q '"state": *"running"' .temper/evidence/mutation.json && break
    sleep 0.2
  done
  python3 -B -c "
import json
try:
    m = json.load(open('.temper/evidence/mutation.json'))
except (OSError, ValueError):
    m = {}
print('%s (%s)' % (m.get('state', 'no mutation.json'), m.get('why') or ''))"
}
_run64; _integ64
python3 -B - "$REPO_ROOT/scripts" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import run_env
def slow(d):   # the suite took 200 s on this tree, as the store says
    for v in d.values():
        if isinstance(v, dict) and isinstance(v.get("pass"), dict):
            v["pass"]["seconds"] = 200
run_env.store_change(run_env._store("."), slow)
PY
: > "$P64/log"
_s3="warm=$(_ahead66 | sed 's/ s, not under.*//'):runs $(grep -c . "$P64/log" | tr -d ' ')"
_run64
_s3+="|cold=$(_ahead66 | sed 's/(no run of the suite on this tree.*/(no run of the suite on this tree)/'):runs $(grep -c . "$P64/log" | tr -d ' ')"
_fix64
_ahead66 >/dev/null
_s3+="|fix=total $(_n64 total),other $(_n64 other)"
assert_eq "p5gap check ahead: a feature run runs no check, and plants bugs timed by the store entry of the tree; with no entry it does not run and says why; a fix run warms the store as before" \
  "warm=not run (three runs of the suite take 600.0:runs 0|cold=not run (no run of the suite on this tree):runs 0|fix=total 1,other 1" "$_s3"

# --- p5gap a group's Validate in the owner's test text runs in the owner's run text: one key with integrate ---
rm -rf src unit   # what the fix run left: untracked in the next repository, which the group's worktree would not have
_tasks64 "$P64/suite" | m_setup; _progs64; _cmds64; _tasks1_66
"$TEMPER" group gate G1 >/dev/null 2>&1
_passed64; _integ64
_s4="runs=$(_n64 suite)"
_s4+="|group=$(_ledger64 build "next(('owner' if __import__('shlex').split(str(x.get('cmd'))) == ['$P64/suite cov'] else 'not the owner (%s)' % x.get('cmd') for x in rows if x.get('claim') == 'Group G1 validate'), 'no row')")"
_s4+="|integrate=$(_ledger64 build "(lambda g, s: '%s,%s' % ('reused' if s.get('reused') else 'ran', 'one key' if s.get('key') and s.get('key') == g.get('key') else 'two keys'))(
  next((x for x in rows if x.get('claim') == 'Group G1 validate'), {}), next((x for x in rows if kind(x) == 'suite'), {}))")"
_s4+="|coverage=$(_gate64 build "'%s %s' % (row('coverage').get('pass'), row('coverage').get('detail', '')[:9])")"
assert_eq "p5gap one owner: a group's Validate whose text is the owner's test text runs in the owner's run text, so integrate reuses it on the same tree: one suite run, one key, coverage measured" \
  "runs=1|group=owner|integrate=reused,one key|coverage=True total 90%" "$_s4"

# --- p5fixf the owner's run text in a group worktree runs there as integrate runs it in the project folder ---
_cov66() { sed -i "s|^    coverage: .*|    coverage: \"$1\"|" .claude/temper.config; }   # the config's coverage command
_gv66() { python3 -B -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1'].get('gate', {}).get('verdict'))" 2>/dev/null; }
_group66() { # _group66 <coverage command>: a one group run whose Validate is the owner's test text, with that coverage
             # command in the config. $P64/covw is a coverage run that writes its profile under .temper/check (as Go's
             # does) and leaves .coverage where it runs (as coverage.py does)
  rm -rf src unit
  _tasks64 "$P64/suite" | m_setup; _progs64; _cmds64; _tasks1_66; _cov66 "$1"
  printf '#!/bin/sh\necho data > .coverage\necho x > .temper/check/cover66.out || exit 1\nexec "%s/suite" cov\n' "$P64" > "$P64/covw"
  chmod +x "$P64/covw"
}
# the folder the owner's coverage run writes into is there in the group worktree, as check run makes it in the project
_group66 "$P64/covw"; "$TEMPER" group gate G1 >/dev/null 2>&1
_s5="folder=$(_gv66):runs $(_n64 suite)"
# and in the baseline's worktree at HEAD, which holds no .temper either (a new repository: nothing is kept)
_group66 "$P64/covw"; rm -f .temper/evidence/baseline.json; TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline start >/dev/null 2>&1
TEMPER_BASELINE_FOREGROUND=1 "$TEMPER" baseline clean >/dev/null 2>&1 || true
_s5+="|base=$(python3 -B -c "import json; d = json.load(open('.temper/evidence/baseline.json')); print('%s %s' % (d.get('result'), d.get('why') or ''))" 2>/dev/null | cut -c1-80)"
# the coverage data a group check left is no part of a group fix: a fix agent that changed nothing commits nothing
_group66 "$P64/covw"; echo fail > "$P64/suite.mode"; "$TEMPER" group gate G1 >/dev/null 2>&1
_wt66="$(python3 -B -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1']['worktree'])")"
_c66="$(git -C "$_wt66" rev-list --count HEAD)"
"$TEMPER" group fix G1 >/dev/null 2>&1; "$TEMPER" group fix G1 --commit >/dev/null 2>&1
_s5+="|fix=empty $(python3 -B -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1'].get('fix_empty'))"),commits $(( $(git -C "$_wt66" rev-list --count HEAD) - _c66 ))"
# a check that failed of the environment and ran again on the same tree: the question does not say nothing ran
rm -rf src unit
_tasks64 "nosuchprog66" | m_setup; _progs64; _tasks1_66
"$TEMPER" group gate G1 >/dev/null 2>&1; "$TEMPER" group gate G1 >/dev/null 2>&1
_s5+="|again=$(_x64 "r = 'says nothing ran' if 'nothing ran' in text(d) else 'ran again' if 'ran it again' in text(d) else text(d)[:160]")"
assert_eq "p5fixf a group's Validate in the owner's run text: the coverage folder is made in its worktree, the coverage data it leaves is no part of a group fix, and a failure the store ran again is not called a run that did not happen" \
  "folder=PASS:runs 1|base=green |fix=empty 1,commits 0|again=ran again" "$_s5"

# --- p5fixf a coverage program that cannot start (exit 127): the group check, integrate and the planted bugs use the suite ---
_group66 "nosuchcov66 $P64/suite cov"; "$TEMPER" group gate G1 >/dev/null 2>&1
_s6="group=$(_gv66),$(_ledger64 build "next(('the test text' if __import__('shlex').split(str(x.get('cmd'))) == ['$P64/suite'] else str(x.get('cmd')) for x in rows if x.get('claim') == 'Group G1 validate'), 'no row')")"
_passed64; _integ64
_s6+="|runs $(_n64 suite)"
python3 -B - "$REPO_ROOT/scripts" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import run_env
def slow(d):   # the suite took 200 s on this tree, as the store says
    for v in d.values():
        if isinstance(v, dict) and isinstance(v.get("pass"), dict):
            v["pass"]["seconds"] = 200
run_env.store_change(run_env._store("."), slow)
PY
_s6+="|ahead=$(_ahead66 | sed 's/ s, not under.*//')"
assert_eq "p5fixf a coverage program that cannot start: the group's check runs the test text as check run does, integrate reuses it, and the planted bugs read the kept pass of the suite, not the kept exit 127" \
  "group=PASS,the test text|runs 1|ahead=not run (three runs of the suite take 600.0" "$_s6"
rm -rf "$P64" src unit
