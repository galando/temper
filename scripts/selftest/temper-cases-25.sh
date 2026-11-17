# Release 9.8.5 case file 25: sourced by test-temper.sh after temper-cases-24.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5 (Q1, F2 of WP08): a Design answer that comes after the plan passes its row with a note and reaches every task ---
_dq() { # _dq: a run at Design with a plan, design.md and one Blocking Design question open
  fresh; f9_tasks > .temper/specs/demo/tasks.md
  printf '# Design\n\n## Areas of Concern\n\n### Which schedule does a job use\n\nThe plan says 24 hours.\n\nowner: the person\n' > .temper/specs/demo/design.md
  python3 - <<'PY'
p = '.temper/specs/demo/intent.md'
s = open(p).read()
s = s.replace('### Open Questions\n', '### Open Questions\n\n- Blocking: Design: Which schedule does a job use? choices: its own | 24 hours\n', 1)
open(p, 'w').write(s)
PY
}
_dq; gpass intent plan
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete design >/dev/null 2>&1
"$TEMPER" intent answer 'Design: Which schedule does a job use?' 'its own' >/dev/null 2>&1
assert_eq "9.8.5 decisions: the answer is kept with the hash tasks.md has now" "1" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/decisions.json'))))")"
"$TEMPER" gate design >/dev/null 2>&1
assert_eq "9.8.5 decisions: a Design answer newer than the tasks passes its row with a note" \
  "row=True|names the answer|Continue to Build (Recommended)" \
  "row=$(python3 -c "
import json
r = [x for x in (json.load(open('.temper/gates.json')).get('design') or {}).get('requirements') or [] if x.get('name') == 'tasks agree with decisions']
print('%s|%s' % (bool(r) and all(x.get('pass') is True for x in r), 'names the answer' if any('Which schedule does a job use?' in str(x.get('detail')) for x in r) else 'no note'))")|$(nx "(d.get('ask') or {}).get('question', {}).get('options', [{}])[0].get('label', 'none')")"
echo "- the job uses its own schedule" >> .temper/specs/demo/tasks.md
assert_eq "9.8.5 decisions: once tasks.md changed, the row passes" "PASS" "$("$TEMPER" gate design 2>&1 | grep -q -- '-> PASS' && echo PASS || echo FAIL)"
assert_eq "9.8.5 decisions: a build task prompt carries the Design decisions" "True" \
  "$(python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import decisions; print('Design: Which schedule does a job use? -> its own' in decisions.prompt('.temper/specs/demo'))" "$REPO_ROOT/scripts")"
fresh
assert_eq "9.8.5 decisions: with no Design answer the row passes and the prompt adds nothing" "True|" \
  "$(python3 -I -c "import sys, json; sys.path.insert(0, sys.argv[1]); import decisions; print(str(decisions.row('.', '.temper/specs/demo')['pass']) + '|' + decisions.prompt('.temper/specs/demo'))" "$REPO_ROOT/scripts")"

# --- 9.8.5 (Q2): a High finding blocks by default; the question counts the open findings and recommends the repair ---
setup; sed -i '/block-on/d' .claude/temper.config
"$TEMPER" evidence add --stage review --claim "review completed" --exit 0 --cmd "review panel" >/dev/null
"$TEMPER" evidence add --stage review --claim "src/a.ts:3 breaks a constraint of the intent" --severity high >/dev/null
assert_exit "9.8.5 review: an open High finding fails the gate with no block-on in the config" 1 "$TEMPER" gate review
assert_eq "9.8.5 review: the template blocks on critical and high" "1" "$(grep -c '^  block-on: \[critical, high\]' "$REPO_ROOT/templates/temper.config.default")"
fresh; _walk_to_commit >/dev/null 2>&1; fresh
gpass intent plan build
for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
"$TEMPER" evidence add --stage review --claim 'src/a.ts:3 a missing null check' --severity medium --label HEURISTIC >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'src/a.ts:9 a name that misleads' --severity low --label HEURISTIC >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1
gpass review
assert_eq "9.8.5 review: a passed Review with an open Medium names the counts and recommends Continue to Check" \
  "True|Continue to Check (Recommended)|Loop back to Build|more=Accept a finding,Grill Me,Make a small change,Save for later" \
  "$(nx "a = d['ask']; q = a['question']; more = [o['label'] for o in (a.get('more') or {}).get('options') or []]; '|'.join([str('open findings: 1 medium, 1 low' in q['question'])] + [o['label'] for o in q['options'][:2]] + ['more=' + ','.join(x for x in ['Accept a finding', 'Grill Me', 'Make a small change', 'Save for later'] if x in more)])")"
assert_eq "9.8.5 review: no fixture view holds a More question with a More options entry" "none" "$(python3 - "$REPO_ROOT/scripts/selftest" <<'PY2'
import json, os, sys
found = []
def walk(o, path):
    if isinstance(o, dict):
        m = o.get("more")
        if isinstance(m, dict) and any(x.get("label") == "More options" or x.get("kind") == "more" for x in m.get("options") or [] if isinstance(x, dict)):
            found.append(path)
        for k, v in o.items():
            walk(v, path + "/" + k)
    elif isinstance(o, list):
        for i, v in enumerate(o):
            walk(v, "%s/%d" % (path, i))
for f in ("view-fixtures.ts", "view-fixtures-2.ts"):
    d = json.loads(open(os.path.join(sys.argv[1], f)).read().split("= ", 1)[1])
    for k, v in d.items():
        walk(v, f + ":" + k)
print(" ".join(found) or "none")
PY2
)"
_ckmed() { # a run at Check with Review and Check passed and one long Medium finding open
  fresh; gpass intent plan build
  for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
  "$TEMPER" evidence add --stage review --claim "$_ckclaim" --severity medium --label HEURISTIC >/dev/null 2>&1
  "$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1
  gpass review; "$TEMPER" state advance review_complete check >/dev/null 2>&1; gpass check
}
_ckclaim='src/a.ts:3 the retry loop reads the token from the shared cache without a lock, so two workers that start at once can both refresh it and the second write wins'
_ckmed
assert_eq "9.8.5 review: the Check question at a pass lists the open findings" "check.pass|True|True" \
  "$(nx "q = d.get('ask') or {}; t = q.get('question', {}).get('question', ''); '%s|%s|%s' % (q.get('id'), 'open findings: 1 medium' in t, '''${_ckclaim:0:120}''' in t)")"

# --- 9.8.5 (Q7): integrate runs the Integration suite again when HEAD moved since the last integrate ---
printf '%s\n' '# Tasks: demo' '' '**Integration:** `echo ran >> .git/integ-count`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
  '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/a.sh`' '**Depends:** none' '**Test:** `true`' '**Cases:**' '- a holds' '- [ ] done' | m_setup
python3 - <<'PY'
import json, subprocess
head = subprocess.run(['git', 'rev-parse', 'HEAD'], stdout=subprocess.PIPE).stdout.decode().strip()
d = json.load(open('.temper/groups.json'))
d['integration'] = {'verdict': 'PASS', 'reason': '', 'group': None, 'files': [], 'ts': 'x', 'head': head}
json.dump(d, open('.temper/groups.json', 'w'))
PY
"$TEMPER" integrate >/dev/null 2>&1
assert_eq "9.8.5 integrate: the same HEAD does not run the suite again" "0" "$(cat .git/integ-count 2>/dev/null | wc -l | tr -d ' ')"
echo more > more.txt; git add more.txt; git commit -q -m more
OUT="$("$TEMPER" integrate 2>&1)"
assert_eq "9.8.5 integrate: a new commit runs the Integration suite again and records the new HEAD" "1|True|$(git rev-parse HEAD)" \
  "$(cat .git/integ-count 2>/dev/null | wc -l | tr -d ' ')|$(grep -q 'Integration suite ran again' <<<"$OUT" && echo True || echo False)|$(python3 -c "import json; print(json.load(open('.temper/groups.json'))['integration']['head'])")"
rm -f more.txt

# --- WP08 (M1): after a pass, a commit that breaks the Integration suite is recorded and asked; a repair passes ---
printf '%s\n' '# Tasks: demo' '' '**Integration:** `test ! -e broken.txt`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
  '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/a.sh`' '**Depends:** none' '**Test:** `true`' '**Cases:**' '- a holds' '- [ ] done' | m_setup
python3 - <<'PY'
import json, subprocess
head = subprocess.run(['git', 'rev-parse', 'HEAD'], stdout=subprocess.PIPE).stdout.decode().strip()
d = json.load(open('.temper/groups.json'))
for g in d.get('groups', {}).values():
    g['status'] = 'passed'; g['gate'] = {'verdict': 'PASS'}; g['confirmed'] = 't'
for t in d.get('tasks', {}).values():
    t['status'] = 'passed'
d['integration'] = {'verdict': 'PASS', 'reason': '', 'group': None, 'files': [], 'ts': 'x', 'head': head}
json.dump(d, open('.temper/groups.json', 'w'))
PY
# as a PASS of integrate leaves the run: the group worktree removed and the group branch deleted
for _wt in $(git worktree list --porcelain | sed -n 's/^worktree //p' | tail -n +2); do git worktree remove --force "$_wt" >/dev/null 2>&1; done
git branch -D temper/demo/G1 >/dev/null 2>&1
echo x > broken.txt; git add broken.txt; git commit -q -m "a fix that breaks the suite"
O1="$("$TEMPER" integrate 2>&1)"; rc1=$?
REC="$(python3 -c "import json; i = json.load(open('.temper/groups.json'))['integration']; print('%s|%s' % (i.get('verdict'), i.get('merged')))")"
O2="$("$TEMPER" gate build 2>&1)"
NX="$(nx "d['action'] + '|' + str(d.get('stage'))")"
git rm -q broken.txt; git commit -q -m "the repair"
O3="$("$TEMPER" integrate 2>&1)"; rc3=$?
assert_eq "m1 integrate: a suite broken after a pass fails, is repaired, and passes again" \
  "0|FAIL|True|True|ask|build|0|PASS|False" \
  "$rc1|$REC|$(grep -q -- '-> FAIL' <<<"$O2" && grep -q '^ *\[x\] integration ' <<<"$O2" && echo True || echo False)|$NX|$rc3|$(python3 -c "import json; print(json.load(open('.temper/groups.json'))['integration']['verdict'])")|$(grep -q 'not something we can merge' <<<"$O1$O2$O3" && echo True || echo False)"
