# Release 9.8.5 case file 25: sourced by test-temper.sh after temper-cases-24.sh; its helpers (nx, vw, fresh, gpass, gfail, labels, m_setup) are used here.

# --- 9.8.5 (Q1): a Design answer that comes after the plan holds Build until tasks.md follows it ---
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
OUT="$("$TEMPER" gate design 2>&1)"
assert_eq "9.8.5 decisions: the Design gate fails while tasks.md is unchanged, naming the answer" "FAIL|True" \
  "$(grep -q -- '-> FAIL' <<<"$OUT" && echo FAIL || echo PASS)|$(grep -q 'tasks agree with decisions.*Which schedule does a job use? -> its own' <<<"$OUT" && echo True || echo False)"
assert_eq "9.8.5 decisions: the Design question recommends Loop back to Plan; the override can say the tasks already agree" \
  "Loop back to Plan (Recommended)|Override and continue|Save for later|The tasks already agree" \
  "$(nx "q = d['ask']; '|'.join([o['label'] for o in q['question']['options']] + [q['options'][1]['reason_question']['options'][0]['label']])")"
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
assert_eq "9.8.5 review: a passed Review with an open Medium names the counts and recommends the repair" \
  "True|Loop back to Build (Recommended)|Continue to Check" \
  "$(nx "q = d['ask']['question']; '|'.join([str('open findings: 1 medium, 1 low' in q['question'])] + [o['label'] for o in q['options'][:2]])")"

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
