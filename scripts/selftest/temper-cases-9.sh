# Round 4: the findings of the 9.7.0 release audit, each reproduced here before it was fixed.
# Sourced by test-temper.sh after temper-cases-8.sh (its helpers nx, vw, labels, gpass, gfail, fresh and
# _walk_to_commit are used here).

# --- 1. A verdict of the active run is computed from the run's own spec folder and the project's config ---
fresh; mkdir -p .temper/specs/other
cp .temper/gates.json r4-gates-before.json
OUT="$("$TEMPER" gate intent --spec-path .temper/specs/other 2>&1)"
assert_eq "round 4, 1: gate --spec-path of another folder prints its verdict and records nothing for the run" "1|same" \
  "$(grep -c 'not recorded: a run of .temper/specs/demo is active' <<<"$OUT")|$(cmp -s .temper/gates.json r4-gates-before.json && echo same || echo changed)"
"$TEMPER" gate intent --spec-path ./.temper/specs/demo/ >/dev/null 2>&1
assert_eq "round 4, 1: the run's own folder, however it is written, is recorded" "PASS" \
  "$(python3 -c "import json; print(json.load(open('.temper/gates.json')).get('intent', {}).get('verdict'))")"
rm -f r4-gates-before.json
printf 'check:\n  coverage-threshold: 1\n' > r4-low.cfg
"$TEMPER" evidence add --stage check --claim "coverage" --value 50 --exit 0 >/dev/null 2>&1
OUT="$(TEMPER_CONFIG=r4-low.cfg "$TEMPER" gate check 2>&1)"
assert_eq "round 4, 1: TEMPER_CONFIG is not followed by a gate while a run is active" "1|1" \
  "$(grep -c 'TEMPER_CONFIG is not followed' <<<"$OUT")|$(grep -c "recorded coverage '50.0' vs threshold 80" <<<"$OUT")"
assert_eq "round 4, 1: config get still reads the file TEMPER_CONFIG names (the guard scripts use it)" "1" \
  "$(TEMPER_CONFIG=r4-low.cfg "$TEMPER" config get check.coverage-threshold)"
rm -f r4-low.cfg

# --- 6. The digest of the tasks the person approved is recorded at the plan gate, not at the first group start ---
fresh; gpass intent plan; rm -f .temper/groups.json
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
assert_eq "round 4, 6: leaving Plan records the digest of the approved tasks.md" "64" \
  "$("$TEMPER" state get plan_hash | tr -d '\n' | wc -c | tr -d ' ')"
assert_exit "round 4, 6: the digest is the CLI's, never set by hand" 1 "$TEMPER" state set plan_hash x
python3 - <<'PY'
p = '.temper/specs/demo/tasks.md'
open(p, 'w').write(open(p).read().replace('**Test:** `true`', '**Test:** `echo nothing to test`'))
PY
OUT="$("$TEMPER" group start G1 2>&1)"; rc=$?
assert_eq "round 4, 6: a Test command changed after the plan gate stops the first group start" "1|1|0" \
  "$rc|$(grep -c 'changed since the person approved it at the plan gate' <<<"$OUT")|$([[ -f .temper/groups.json ]] && echo 1 || echo 0)"

# --- 7. A door into a later stage: the walked approvals commit only what changed, and a failed one can be run ---
setup; rm -f .temper/build-state.json   # the earlier run is over: its spec is committed, no run is active
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm "the spec of an earlier run" >/dev/null 2>&1
_b="$(git symbolic-ref -q HEAD)"; git branch -f temper-test-other HEAD >/dev/null 2>&1; git symbolic-ref HEAD refs/heads/temper-test-other   # on another branch than the run's, at the same commit
"$TEMPER" state init demo --enter check >/dev/null 2>&1; gpass intent
assert_eq "round 4, 7: a walked Intent whose spec is committed and accepted makes no empty commit" "git checkout feature/demo|intent accept|0|state advance intent_complete plan" \
  "$(nx "o = d['ask']['options'][0]; c = o['calls']; c[0].replace('checkout -b ', 'checkout ') + '|' + c[1].split('temper ', 1)[1] + '|' + str(sum(1 for x in c if x.startswith('git commit'))) + '|' + c[-1].split('temper ', 1)[1]")"
git symbolic-ref HEAD "$_b"
printf '\nA note.\n' >> .temper/specs/demo/intent.md
assert_eq "round 4, 7: with a change in the spec folder the approval commits it" "1" \
  "$(nx "sum(1 for x in d['ask']['options'][0]['calls'] if x.startswith('git commit'))")"
git checkout -q -- .temper/specs/demo/intent.md
assert_eq "round 4, 7: the view holds the same calls as next" "same" \
  "$([[ "$(nx "d['ask']['options'][0]['calls']")" == "$(vw "d['ask']['options'][0]['calls']")" ]] && echo same || echo differs)"
mv .temper/specs/demo/intent.md r4-intent.md
assert_eq "round 4, 7: with no intent.md the approval accepts nothing" "0" \
  "$(nx "sum(1 for x in d['ask']['options'][0]['calls'] if 'intent accept' in x)")"
mv r4-intent.md .temper/specs/demo/intent.md
_at build; gfail build "RED then GREEN" "have red=0 green=0"
assert_eq "round 4, 7: a walked stage whose check failed can be run now, or skipped" "Run Build (Recommended)|Override and continue|Save for later" "$(labels)"
CALL="$(nx "d['ask']['options'][0]['calls'][0]")"; eval "$CALL" >/dev/null 2>&1
assert_eq "round 4, 7: Run Build moves the door's entry to Build, so Build runs and is no longer walked" "build|work|1" \
  "$("$TEMPER" state get enter)|$(nx "d['action'] + '|' + str(int(not any('gate build' == c.split('temper ', 1)[-1] for c in d.get('calls', []))))")"

# --- 8. A commit the CLI did not make on a passed group's branch: the person takes it out or keeps it ---
r4_grouped() { # a real grouped run of one group and one task, built through the CLI up to the group's Continue
  cd "$WORKDIR" || exit 1
  rm -rf .git src tests stray.txt   # a repository of its own: no branch or worktree of an earlier case is left
  setup; rm -f .temper/groups.json
  git checkout -q -b feature/demo 2>/dev/null || git checkout -q feature/demo
  mkdir -p src tests; echo 'echo base' > src/parser.sh
  cat > .temper/specs/demo/tasks.md <<'TASKS'
# Tasks: demo

**Integration:** `bash tests/parser_test.sh`

## Group G1: Parser
**Depends:** none
**Validate:** `bash tests/parser_test.sh`
**Context:**
The parser group.

### Task 1: parse
**File:** `src/parser.sh`, `tests/parser_test.sh`
**Depends:** none
**Test:** `bash tests/parser_test.sh`
**Cases:**
- `parse` prints `two`
- nothing else is printed
- [ ] done
TASKS
  git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1
  gpass intent plan
  "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  "$TEMPER" group start G1 >/dev/null 2>&1; "$TEMPER" task start 1 >/dev/null 2>&1
  local wt; wt="$PWD/.claude/worktrees/temper-demo-T1"; mkdir -p "$wt/tests"
  printf 'out=$(bash src/parser.sh)\n[ "$out" = "two" ] || { echo "assert failed: $out"; exit 1; }\n' > "$wt/tests/parser_test.sh"
  echo 'echo one' > "$wt/src/parser.sh"; "$TEMPER" task test 1 --phase red >/dev/null 2>&1
  echo 'echo two' > "$wt/src/parser.sh"; "$TEMPER" task test 1 --phase green >/dev/null 2>&1
  "$TEMPER" task gate 1 --model haiku >/dev/null 2>&1; "$TEMPER" group gate G1 >/dev/null 2>&1; "$TEMPER" group continue G1 >/dev/null 2>&1
}
r4_grouped
GW="$PWD/.claude/worktrees/temper-demo-G1"; echo stray > "$GW/stray.txt"
git -C "$GW" add stray.txt >/dev/null 2>&1; git -C "$GW" -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm stray >/dev/null 2>&1
"$TEMPER" integrate >/dev/null 2>&1; "$TEMPER" gate build >/dev/null 2>&1
assert_eq "round 4, 8: integrate found a commit the CLI did not make: next asks to take it out or keep it" \
  "ask|Take the commits out (Recommended)|Keep the commits|Save for later" "$(nx "d['action'] + '|' + '|'.join(o['label'] for o in d['ask']['question']['options'])")"
CALLS="$(nx "'\n'.join(c.replace('{reason}', 'the stray file is wanted') for c in d['ask']['options'][1]['calls'])")"
while IFS= read -r c; do eval "$c" >/dev/null 2>&1; done <<<"$CALLS"
assert_eq "round 4, 8: Keep the commits records the person's reason, and the groups are merged" "PASS|PASS|1" \
  "$(python3 -c "import json; print(json.load(open('.temper/groups.json'))['integration']['verdict'])")|$(python3 -c "import json; print(json.load(open('.temper/gates.json'))['build']['verdict'])")|$(grep -c 'foreign-commit:G1:' .temper/overrides.json)"
r4_grouped
GW="$PWD/.claude/worktrees/temper-demo-G1"; echo stray > "$GW/stray.txt"
git -C "$GW" add stray.txt >/dev/null 2>&1; git -C "$GW" -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm stray >/dev/null 2>&1
"$TEMPER" integrate >/dev/null 2>&1; "$TEMPER" gate build >/dev/null 2>&1
CALLS="$(nx "'\n'.join(d['ask']['options'][0]['calls'])")"
while IFS= read -r c; do eval "$c" >/dev/null 2>&1; done <<<"$CALLS"
assert_eq "round 4, 8: Take the commits out removes them, and the groups are merged without them" "PASS|0|1" \
  "$(python3 -c "import json; print(json.load(open('.temper/groups.json'))['integration']['verdict'])")|$([[ -e stray.txt ]] && echo 1 || echo 0)|$(grep -c 'echo two' src/parser.sh)"
assert_exit "round 4, 8: a sha that is no such commit is refused" 1 "$TEMPER" group reopen G1 --accept-foreign 1234567 --reason x
# Re-audit: a Keep whose integrate did not run (the session ended) is no dead end: next merges the groups again
r4_grouped
GW="$PWD/.claude/worktrees/temper-demo-G1"; echo stray > "$GW/stray.txt"
git -C "$GW" add stray.txt >/dev/null 2>&1; git -C "$GW" -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm stray >/dev/null 2>&1
"$TEMPER" integrate >/dev/null 2>&1; "$TEMPER" gate build >/dev/null 2>&1
eval "$(nx "d['ask']['options'][1]['calls'][0].replace('{reason}', 'wanted')")" >/dev/null 2>&1
assert_eq "re-audit: after Keep with no integrate, next asks to merge the groups again (no question that only fails, no loop unasked)" \
  "ask|Merge the groups (Recommended)|Save for later|integrate|gate build" \
  "$(nx "o = d['ask']['options']; '|'.join([d['action']] + [x['label'] for x in d['ask']['question']['options']] + [c.split('temper ')[-1] for c in o[0]['calls']])")"
git checkout -q -b side >/dev/null 2>&1
"$TEMPER" integrate >/dev/null 2>&1; "$TEMPER" gate build >/dev/null 2>&1
assert_eq "second review: when integrate stops early (another branch), next asks again and says nothing runs unasked" "ask" "$(nx "d['action']")"
git checkout -q feature/demo >/dev/null 2>&1
# Re-audit: a commit the CLI did not make below one it made cannot be taken out by a rebase (the CLI's own commit would be
# written again as one it did not make): the question offers Keep and Save only
r4_grouped
GW="$PWD/.claude/worktrees/temper-demo-G1"; echo stray > "$GW/stray.txt"
git -C "$GW" add stray.txt >/dev/null 2>&1; git -C "$GW" -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm stray >/dev/null 2>&1
echo own > "$GW/own.txt"; git -C "$GW" add own.txt >/dev/null 2>&1; git -C "$GW" -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm own >/dev/null 2>&1
python3 -c "import json, sys; p='.temper/groups.json'; d=json.load(open(p)); d.setdefault('cli_commits', []).append(sys.argv[1]); json.dump(d, open(p, 'w'))" "$(git -C "$GW" rev-parse HEAD)"
"$TEMPER" integrate >/dev/null 2>&1; "$TEMPER" gate build >/dev/null 2>&1
assert_eq "re-audit: a commit below the CLI's own is not offered for a rebase" "ask|Keep the commits|Save for later" \
  "$(nx "d['action'] + '|' + '|'.join(o['label'] for o in d['ask']['question']['options'])")"

# --- 9 to 11: the commit steps, the Commit stage, base_sha; and the low findings ---
D9="$WORKDIR/r4-del"; rm -rf "$D9"; mkdir -p "$D9"
( cd "$D9" && git init -q . && echo 1 > keep.txt && echo 2 > gone.txt && echo 3 > local.txt && git add -A && git -c user.email=t@t -c user.name=t commit -qm A
  echo "$(git rev-parse HEAD)" > ../r4-base; git rm -q gone.txt; git -c user.email=t@t -c user.name=t commit -qm "a task deletes gone.txt"; rm local.txt; echo 4 > new.txt )
assert_eq "round 4, 9: a file deleted in a commit since base_sha is no name for git add; one deleted in the work tree is" '["local.txt", "new.txt"]' \
  "$(cd "$D9" && python3 "$REPO_ROOT/scripts/flow.py" changed "$(cat ../r4-base)" "2000-01-01T00:00:00Z")"
rm -rf "$D9" "$WORKDIR/r4-base"
fresh; "$TEMPER" state set base_sha 0123456 >/dev/null 2>&1
assert_exit "round 4, 11: base_sha is recorded once; a second one is refused" 1 "$TEMPER" state set base_sha 89abcde
setup
"$TEMPER" evidence add --stage build --phase green --exit 0 --claim "unit tests" >/dev/null 2>&1
"$TEMPER" evidence add --stage build --phase red --exit 1 --claim "unit tests" >/dev/null 2>&1
assert_eq "round 4, low: a passing run recorded before the failing one is no RED then GREEN" "FAIL" \
  "$("$TEMPER" gate build >/dev/null 2>&1; python3 -c "import json; print([r for r in json.load(open('.temper/gates.json'))['build']['requirements'] if r['name'] == 'RED then GREEN'][0]['pass'] and 'PASS' or 'FAIL')")"
"$TEMPER" evidence add --stage build --phase green --exit 0 --claim "unit tests" >/dev/null 2>&1
assert_eq "round 4, low: a passing run after the failing one is" "PASS" \
  "$("$TEMPER" gate build >/dev/null 2>&1; python3 -c "import json; print([r for r in json.load(open('.temper/gates.json'))['build']['requirements'] if r['name'] == 'RED then GREEN'][0]['pass'] and 'PASS' or 'FAIL')")"
fresh; gpass intent plan build; for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
gfail review "review completed" "no review completion evidence"
assert_eq "round 4, low: a review that did not finish is run again first" "Run Review again (Recommended)|state redo review" \
  "$(nx "o = d['ask']['options'][0]; o['label'] + '|' + ' '.join(o['calls'][0].split('temper ', 1)[1].split()[:3])")"

# --- 2, 3. A project below the top of its git repository (a package of a monorepo) ---
N="$WORKDIR/r4-nested"; rm -rf "$N"; mkdir -p "$N/packages/app/src" "$N/packages/app/tests"
(
  cd "$N" && git init -q . && echo r > README && echo 'echo base' > packages/app/src/parser.sh
  git add -A && git -c user.email=t@t -c user.name=t commit -qm init && git checkout -q -b feature/pw
  cd packages/app && mkdir -p .claude .temper/specs/pw && cp "$REPO_ROOT/templates/temper.config.default" .claude/temper.config
  "$TEMPER" init >/dev/null && "$TEMPER" state init pw >/dev/null
  cat > .temper/specs/pw/tasks.md <<'TASKS'
# Tasks: nested

**Integration:** `bash tests/parser_test.sh`

## Group G1: Parser
**Depends:** none
**Validate:** `bash tests/parser_test.sh`
**Context:**
The parser group.

### Task 1: parse
**File:** `src/parser.sh`, `tests/parser_test.sh`
**Depends:** none
**Test:** `bash tests/parser_test.sh`
**Cases:**
- `parse` prints `two`
- nothing else is printed
- [ ] done
TASKS
  echo '# Plan' > .temper/specs/pw/plan.md
  git add .claude .temper/specs && git -c user.email=t@t -c user.name=t commit -qm spec
) >/dev/null 2>&1
assert_eq "round 4, 2: in a package of a monorepo the run's own files stay out of git status" "0" \
  "$(git -C "$N" status --porcelain | grep -c '\.temper/')"
(
  cd "$N/packages/app" || exit 1
  "$TEMPER" override intent --reason r; "$TEMPER" state advance intent_complete plan
  "$TEMPER" override plan --reason r; "$TEMPER" state advance plan_complete build
  "$TEMPER" group start G1; "$TEMPER" task start 1
) >/dev/null 2>&1
WT="$(cd "$N/packages/app" && "$TEMPER" task show 1 2>/dev/null | sed -n 's/^WORKTREE: //p')"
assert_eq "round 4, 2: a task's WORKTREE line is the project folder inside the worktree" "1" \
  "$([[ "$WT" == */.claude/worktrees/temper-pw-T1/packages/app && -f "$WT/src/parser.sh" ]] && echo 1 || echo 0)"
mkdir -p "$WT/tests"; printf 'out=$(bash src/parser.sh)\n[ "$out" = "two" ] || { echo "assert failed: $out"; exit 1; }\n' > "$WT/tests/parser_test.sh"
echo 'echo one' > "$WT/src/parser.sh"
(cd "$N/packages/app" && "$TEMPER" task test 1 --phase red) >/dev/null 2>&1
echo 'echo two' > "$WT/src/parser.sh"
(cd "$N/packages/app" && "$TEMPER" task test 1 --phase green && "$TEMPER" task gate 1 --model haiku) >/dev/null 2>&1
assert_eq "round 4, 2: the task's commit holds the project's own files" "packages/app/src/parser.sh packages/app/tests/parser_test.sh" \
  "$(git -C "$N" show --name-only --format= temper/pw/G1 2>/dev/null | sort | paste -sd' ' -)"
(cd "$N/packages/app" && "$TEMPER" group gate G1 && "$TEMPER" group continue G1 && "$TEMPER" integrate) >/dev/null 2>&1
assert_eq "round 4, 2: integrate merges them into the project" "PASS|echo two" \
  "$(python3 -c "import json; print(json.load(open('$N/packages/app/.temper/groups.json'))['integration']['verdict'])")|$(cat "$N/packages/app/src/parser.sh")"
(cd "$N/packages/app" && bash "$REPO_ROOT/scripts/guards/install.sh") >/dev/null 2>&1
(cd "$N/packages/app" && "$TEMPER" state init pw2 && echo code > app.js && git add app.js) >/dev/null 2>&1
(cd "$N/packages/app" && git -c user.email=t@t -c user.name=t commit -qm "code while every gate fails") >/dev/null 2>&1; rc=$?
assert_eq "round 4, 3: the native hook gates the commit of a project below the top of its repository" "1|init" \
  "$rc|$(git -C "$N" log --format=%s -1 | sed 's/^Merge.*/init/; s/^merge.*/init/; s/^feat.*/init/; s/^spec$/init/')"
(cd "$N/packages/app" && git reset -q && mkdir -p .temper/specs/pw2 && echo '# x' > .temper/specs/pw2/intent.md && git add .temper/specs/pw2 \
  && git -c user.email=t@t -c user.name=t commit -qm "spec only") >/dev/null 2>&1; rc=$?
assert_eq "round 4, 3: and lets its spec only commit through" "0|spec only" "$rc|$(git -C "$N" log --format=%s -1)"
# Re-audit: a file moved out of the project below the top is a change of that project too (git reads a rename as one name)
mkdir -p "$N/lib"; git -C "$N" mv packages/app/src/parser.sh lib/parser.sh >/dev/null 2>&1
(cd "$N" && git -c user.email=t@t -c user.name=t commit -qm "move out") >/dev/null 2>&1; rc=$?
assert_eq "re-audit: the native hook gates a file moved out of a project below the top" "1|spec only" "$rc|$(git -C "$N" log --format=%s -1)"
git -C "$N" reset -q --hard >/dev/null 2>&1
rm -rf "$N"

# --- re-audit: a scenario's trace row is no test run ---
setup
"$TEMPER" evidence add --stage check --scenario first --claim 'scenario: first -> tests/test_a.py:test_first' --exit 0 >/dev/null 2>&1
assert_eq "re-audit: a scenario row that names its test does not count as a passing test run" "0" \
  "$("$TEMPER" gate check 2>/dev/null | grep -c '\[v\] tests pass')"
"$TEMPER" evidence add --stage check --claim "tests" --cmd "pytest" --exit 0 >/dev/null 2>&1
assert_eq "re-audit: the test run row does" "1" "$("$TEMPER" gate check 2>/dev/null | grep -c '\[v\] tests pass')"

# --- re-audit: a code file moved into the spec folder is no artifact only commit ---
setup
git init -q . 2>/dev/null; mkdir -p src; echo 'x' > src/x.ts
git add src/x.ts .temper/specs/demo/intent.md >/dev/null 2>&1; git -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm base >/dev/null 2>&1
git mv src/x.ts .temper/specs/demo/x.ts >/dev/null 2>&1
assert_eq "re-audit: a rename into the spec folder is a deletion of the code file, so every gate applies" "0" \
  "$("$TEMPER" gate commit 2>&1 | grep -c 'artifact-only commit')"
git reset -q --hard >/dev/null 2>&1; rm -rf .git src

# --- re-audit: a project folder whose name holds a glob character ---
P6="$WORKDIR/r6-prefix"; rm -rf "$P6"; mkdir -p "$P6/pk[1]/app"
( cd "$P6" && git init -q . && echo x > 'pk[1]/app/x.txt' && git add -A && git -c user.email=t@t -c user.name=t commit -qm base ) >/dev/null 2>&1
(cd "$P6/pk[1]/app" && "$TEMPER" init) >/dev/null 2>&1
assert_eq "re-audit: the run files of a project in pk[1]/app stay out of git status" "0" \
  "$(git -C "$P6" status --porcelain --untracked-files=all | grep -c '\.temper/')"
rm -rf "$P6"

# --- re-audit: leaving Intent commits the accept whenever it changes the Status line ---
setup; rm -f .temper/build-state.json
sed -i 's/^\*\*Status:\*\* accepted$/**Status:** accepted (pending review)/' .temper/specs/demo/intent.md
git init -q . 2>/dev/null; git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm "a committed spec" >/dev/null 2>&1
"$TEMPER" state init demo --enter check >/dev/null 2>&1; gpass intent
assert_eq "re-audit: a Status that is not exactly accepted is rewritten by the accept, so the approval commits it" "1" \
  "$(nx "sum(1 for c in d['ask']['options'][0]['calls'] if c.startswith('git commit'))")"
rm -rf .git

# --- live run of the release candidate: the first commit goes to the run's branch ---
setup; git init -q . 2>/dev/null; git checkout -q -B main 2>/dev/null
git config user.email t@t; git config user.name t   # the calls run git commit as printed: CI has no global identity
sed -i 's/^\*\*Status:\*\* accepted$/**Status:** draft/' .temper/specs/demo/intent.md   # a new intent: the accept changes it
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm base >/dev/null 2>&1
rm -f .temper/build-state.json; "$TEMPER" state init demo >/dev/null 2>&1; gpass intent
CALLS="$(nx "'\n'.join(d['ask']['options'][0]['calls'])")"
assert_eq "live run: Continue to Plan on main switches to the run's branch before the intent's commit" "git checkout -b feature/demo|1" \
  "$(head -1 <<<"$CALLS")|$(grep -c '^git commit' <<<"$CALLS")"
while IFS= read -r c; do eval "$c" >/dev/null 2>&1; done <<<"$CALLS"
assert_eq "live run: the intent's commit is on feature/demo, and main has none" "feature/demo|docs(intent): accept demo|base" \
  "$(git branch --show-current)|$(git log -1 --format=%s feature/demo)|$(git log -1 --format=%s main)"
gpass plan
assert_eq "live run: on the run's branch already, leaving Plan switches nothing" "0" \
  "$(nx "sum(1 for c in d['ask']['options'][0]['calls'] if c.startswith('git checkout'))")"
git checkout -q main 2>/dev/null; rm -rf .git

# --- live run: a group that builds on another starts after the person's Continue of it ---
r5_two_groups() { # r4_grouped with a second group G2 that depends on G1, through G1's group gate
  cd "$WORKDIR" || exit 1
  rm -rf .git src tests stray.txt
  setup; rm -f .temper/groups.json
  git checkout -q -b feature/demo 2>/dev/null || git checkout -q feature/demo
  mkdir -p src tests; echo 'echo base' > src/parser.sh; echo 'echo p' > src/printer.sh
  cat > .temper/specs/demo/tasks.md <<'TASKS'
# Tasks: demo

**Integration:** `bash tests/parser_test.sh`

## Group G1: Parser
**Depends:** none
**Validate:** `bash tests/parser_test.sh`
**Context:**
The parser group.

### Task 1: parse
**File:** `src/parser.sh`, `tests/parser_test.sh`
**Depends:** none
**Test:** `bash tests/parser_test.sh`
**Cases:**
- `parse` prints `two`
- nothing else is printed
- [ ] done

## Group G2: Printer
**Depends:** G1
**Validate:** `true`
**Context:**
The printer group.

### Task 2: print
**File:** `src/printer.sh`
**Depends:** none
**Test:** `true`
**Cases:**
- it prints
- it prints once
- [ ] done
TASKS
  git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1
  gpass intent plan
  "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  "$TEMPER" group start G1 >/dev/null 2>&1; "$TEMPER" task start 1 >/dev/null 2>&1
  local wt; wt="$PWD/.claude/worktrees/temper-demo-T1"; mkdir -p "$wt/tests"
  printf 'out=$(bash src/parser.sh)\n[ "$out" = "two" ] || { echo "assert failed: $out"; exit 1; }\n' > "$wt/tests/parser_test.sh"
  echo 'echo one' > "$wt/src/parser.sh"; "$TEMPER" task test 1 --phase red >/dev/null 2>&1
  echo 'echo two' > "$wt/src/parser.sh"; "$TEMPER" task test 1 --phase green >/dev/null 2>&1
  "$TEMPER" task gate 1 --model haiku >/dev/null 2>&1; "$TEMPER" group gate G1 >/dev/null 2>&1
}
r5_two_groups
assert_eq "live run: G1 passed its check: next asks the person about G1 and starts no G2" "ask|Group G1 (Parser) passed its check. Continue?|0" \
  "$(nx "d['action'] + '|' + d['ask']['question']['question'] + '|' + str(sum(1 for c in d.get('calls') or [] if 'group start G2' in c))")"
out="$("$TEMPER" group start G2 2>&1)"; rc=$?
assert_eq "live run: group start G2 before the Continue of G1 is refused" "1|1" "$rc|$(grep -c 'has not continued' <<<"$out")"
"$TEMPER" group continue G1 >/dev/null 2>&1
assert_eq "live run: after the Continue, next starts G2" "work|1" \
  "$(nx "d['action'] + '|' + str(sum(1 for c in d.get('calls') or [] if 'group start G2' in c))")"
rm -rf .git src tests

# --- live run: a passed Review with open findings below the blocking severity can loop them back to Build ---
fresh; _walk_to_commit >/dev/null 2>&1; fresh
gpass intent plan build
for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
"$TEMPER" evidence add --stage review --claim 'src/a.ts:3 a name that misleads' --severity low --label HEURISTIC >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1
gpass review
assert_eq "live run: the passed Review question offers Loop back to Build, and Accept a finding under More options" \
  "ask|Continue to Check (Recommended)|Loop back to Build|Architecture Depth Review|More options|Accept a finding|1" \
  "$(nx "q = d['ask']; '|'.join([d['action']] + [o['label'] for o in q['question']['options']] + [q['more']['question']['options'][0]['label'], str(len(q['accept']['question']['options']) - 1)])")"

# --- live run: the end of the run leaves the committed spec folder as it is, and the report prints first ---
setup; git init -q . 2>/dev/null; git checkout -q -B feature/demo 2>/dev/null
"$TEMPER" evidence add --stage build --claim "tests" --cmd "true" --exit 0 --phase green --label PROVEN >/dev/null 2>&1
"$TEMPER" evidence add --stage build --claim "lint" --cmd "true" --exit 0 --label HEURISTIC >/dev/null 2>&1
gpass commit; "$TEMPER" state archive >/dev/null 2>&1
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm "the change" >/dev/null 2>&1
# the commit hook runs the commit gate again: the same verdict, a new time
python3 -c "import json; p='.temper/gates.json'; d=json.load(open(p)); d['commit']['ts']='2099-01-01T00:00:00Z'; json.dump(d, open(p, 'w'))"
"$TEMPER" state clear >/dev/null 2>&1
assert_eq "live run: state clear after the commit leaves the committed gate ledger unchanged" "" \
  "$(git status --porcelain -- .temper/specs/demo/gate-ledger.json)"
rm -rf .git

# --- live run: a scenario's trace row is no Check marker of the tests ---
fresh
"$TEMPER" evidence add --stage check --scenario first --claim 'scenario: first -> tests/test_a.py:test_first (3 tests)' --exit 0 >/dev/null 2>&1
assert_eq "live run: the tests marker of the view reads no scenario row" "none" \
  "$(vw "next(m['state'] for m in d['check_markers'] if m['name'] == 'tests')")"

# --- your check: the last commit of a grouped Build holds only the run's record, and its message says so ---
setup; rm -rf .git bare   # a repository of its own: no file an earlier case left changes under it
git init -q . 2>/dev/null; git checkout -q -B feature/demo 2>/dev/null
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm base >/dev/null 2>&1
_walk_to_commit; gpass commit; printf '\nA note.\n' >> .temper/specs/demo/intent.md
assert_eq "check: with only the spec folder changed, the commit message names the run's record, not a feature" "1|0" \
  "$(nx "sum(1 for x in d['steps'] if x.startswith('git commit') and 'docs(demo): record the run' in x)")|$(nx "sum(1 for x in d['steps'] if 'conventional commit message for the feature' in x)")"
python3 -c "import json; p='.temper/build-state.json'; d=json.load(open(p)); d['enter']='review'; json.dump(d, open(p, 'w'))"
assert_eq "live run 6: a run that entered at Review says its code was committed before it" "1" \
  "$(nx "sum(1 for x in d['steps'] if x.startswith('git commit') and '(the code was committed before this run)' in x)")"
mkdir -p src; echo x > src/new.sh
assert_eq "check: with code changed too, the commit message is the feature's" "1" \
  "$(nx "sum(1 for x in d['steps'] if 'conventional commit message for the feature' in x)")"
rm -rf .git src

# --- live run 1: Loop back to Build keeps what Review found, so the fix pass reads it ---
fresh
gpass intent plan build
for s in intent_complete:plan plan_complete:build build_complete:review; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
printf '{"version": 1, "slug": "demo", "groups": {"G1": {"gate": {"verdict": "PASS"}, "confirmed": "x"}}, "tasks": {}, "integration": {"verdict": "PASS"}}\n' > .temper/groups.json
"$TEMPER" evidence add --stage review --claim 'src/a.ts:3 a name that misleads' --severity low --label HEURISTIC >/dev/null 2>&1
"$TEMPER" evidence add --stage review --claim 'review completed' --label HEURISTIC >/dev/null 2>&1
gpass review
"$TEMPER" state loop review build --reason 'fix them' >/dev/null 2>&1
assert_eq "live run 1: the loop keeps the open finding, while the review ledger is cleared" "1|0" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/feedback-loops.json'))['active_loops'][0].get('findings') or []))")|$(python3 -c "import json; print(len(json.load(open('.temper/evidence/review.json'))))" 2>/dev/null || echo 0)"
assert_eq "live run 1: the fix pass prompt names the finding, not only the person's reason" "1|1" \
  "$(nx "int('[low] src/a.ts:3 a name that misleads' in d['agents'][0]['prompt'])")|$(nx "int('Feedback re-entry: fix them' in d['agents'][0]['prompt'])")"

# --- live run 1: the commit's own hook records a spec only verdict; state clear keeps the ledger the commit carries ---
setup; rm -rf .git bare; git init -q . 2>/dev/null; git checkout -q -B feature/demo 2>/dev/null
git config user.email t@t; git config user.name t
gpass intent plan build review check commit; "$TEMPER" state archive >/dev/null 2>&1
git add -A >/dev/null 2>&1; git -c core.hooksPath=/dev/null commit -qm "the run's record" >/dev/null 2>&1
# what the hook's gate commit does at that commit: the spec only verdict over the run's commit verdict
python3 -c "import json; p='.temper/gates.json'; d=json.load(open(p)); d['commit']={'verdict':'PASS','requirements':[{'name':'artifact-only commit','pass':True,'detail':'x'}]}; json.dump(d, open(p, 'w'))"
assert_exit "live run 1: state set archived is the CLI's" 1 "$TEMPER" state set archived x
"$TEMPER" state clear >/dev/null 2>&1
assert_eq "live run 1: state clear keeps the ledger the commit carries, with the run's own commit verdict" "|0" \
  "$(git status --porcelain -- .temper/specs/demo/gate-ledger.json)|$(grep -c 'artifact-only commit' .temper/specs/demo/gate-ledger.json)"
rm -rf .git

# --- your question: which model runs each stage is shown before the launch and in the report ---
fresh
assert_eq "model: the line next gives before a stage runs names its model" "1" \
  "$(nx "int(d['say'] == 'Intent runs on %s.' % d['agents'][0]['model'] and bool(d['agents'][0]['model']))")"
"$TEMPER" usage add --stage intent --model opus --tokens 10 --ms 5 >/dev/null 2>&1
assert_eq "model: the report's stage table names the model each stage was launched on" "1|opus" \
  "$("$TEMPER" report 2>/dev/null | grep -cE '^  intent +1 +10 +5  opus$')|$(vw "','.join(d['usage']['by_stage']['intent']['models'])")"
"$TEMPER" usage add --stage plan --model claude-haiku-5-5 --tokens 7 --ms 3 >/dev/null 2>&1
assert_eq "live run 5: the model table names its rows column, and a long model id keeps the columns apart" "1|1" \
  "$("$TEMPER" report 2>/dev/null | grep -cE '^  model +rows +tokens +ms$')|$("$TEMPER" report 2>/dev/null | grep -cE '^  claude-haiku-5-5 +1 +7 +3$')"

# --- live run 3: a passed Design whose concern needs the plan changed can step back to Plan ---
fresh; gpass intent plan design
"$TEMPER" state set complexity medium >/dev/null 2>&1
for s in intent_complete:plan plan_complete:design; do "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1; done
assert_eq "live run 3: the passed Design question offers Loop back to Plan under More options" "design|1" \
  "$(nx "d['stage'] + '|' + str(sum(1 for o in d['ask']['more']['options'] if o['label'] == 'Loop back to Plan'))")"
"$TEMPER" state loop design plan --reason 'add the missing cases' >/dev/null 2>&1
assert_eq "live run 3: a loop back to Plan gives the Plan agent the person's reason" "plan|1" \
  "$(nx "d['stage'] + '|' + str(int('Loop back from Design: add the missing cases.' in d['agents'][0]['prompt']))")"

# --- live run 6: a door into Review reads the run's diff from where the feature started, and takes Plan's tier ---
setup; rm -rf .git bare; git init -q . 2>/dev/null; git checkout -q -B main 2>/dev/null
git config user.email t@t; git config user.name t; rm -f .temper/build-state.json
printf 'base\n' > r6-base.txt; git add r6-base.txt; git commit -qm base >/dev/null 2>&1; _r6b="$(git rev-parse HEAD)"
git checkout -q -b feature/demo; git add .temper/specs/demo/intent.md; git commit -qm "docs(intent): accept demo" >/dev/null 2>&1
printf '# Plan: demo\n\n**Complexity:** medium. Two modules.\n' > .temper/specs/demo/plan.md
printf 'code\n' > r6-code.txt; git add r6-code.txt .temper/specs/demo/plan.md .temper/specs/demo/tasks.md
git commit -qm "feat: the code" >/dev/null 2>&1
"$TEMPER" state init demo --enter review >/dev/null 2>&1
assert_eq "live run 6: a door takes the tier from plan.md's Complexity line, not from intent.md's first guess" "medium" \
  "$("$TEMPER" state get complexity)"
gpass intent plan
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete design >/dev/null 2>&1
assert_eq "live run 6: a Review door reads its diff from before the spec's first commit, so committed work is reviewed" "$_r6b|1" \
  "$("$TEMPER" state get base_sha)|$(git diff --name-only "$("$TEMPER" state get base_sha)" | grep -cx r6-code.txt)"
"$TEMPER" state init demo --enter build >/dev/null 2>&1; gpass intent plan
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete design >/dev/null 2>&1
assert_eq "live run 6: a Build door still reads its diff from HEAD (the work is still to come)" "$(git rev-parse HEAD)" \
  "$("$TEMPER" state get base_sha)"
git checkout -q main; git checkout -q -b feature/other; printf 'more\n' > r6-more.txt; git add r6-more.txt
git commit -qm "feat: more" >/dev/null 2>&1
git checkout -q feature/demo -- .temper/specs/demo; git rm -q --cached -r .temper/specs/demo >/dev/null 2>&1   # the spec, never committed here
"$TEMPER" state init demo --enter check >/dev/null 2>&1; gpass intent plan
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete design >/dev/null 2>&1
assert_eq "live run 6: with no spec commit, a Check door reads its diff from where the branch left main" "$_r6b" \
  "$("$TEMPER" state get base_sha)"
rm -rf .git r6-base.txt r6-code.txt r6-more.txt

# --- live run 5: an armed run parked before the commit says so, and its report is local run state ---
fresh; gpass intent plan build review check commit; _at commit
"$TEMPER" park --verdict SHIP-PENDING-COMMIT --reason 'every gate passed' >/dev/null 2>&1
assert_eq "live run 5: the parked commit question says the armed run parked there and names its report" "1|1" \
  "$(nx "int('the armed run parked here for you' in d['ask']['question']['question'])")|$(nx "int('.temper/autonomy-report.md' in d['ask']['question']['question'])")"
assert_eq "live run 5: the park report is in the clone's info/exclude, so it is never an untracked file" "1|0" \
  "$([[ -f .temper/autonomy-report.md ]] && echo 1 || echo 0)|$(git status --porcelain --untracked-files=all | grep -c 'autonomy-report')"

# --- live run 6: a door's walked Build counts the earlier run's committed Build PASS, and a loop back mends that code ---
setup; rm -rf .git bare; git init -q . 2>/dev/null; git checkout -q -B feature/demo 2>/dev/null
git config user.email t@t; git config user.name t; rm -f .temper/build-state.json
mkdir -p src; printf 'echo demo\n' > src/demo.sh
printf '{"gates": {"build": {"verdict": "PASS", "requirements": []}}, "overrides": []}\n' > .temper/specs/demo/gate-ledger.json
git add src .temper/specs/demo; git commit -qm "the earlier run" >/dev/null 2>&1
_r6door() { "$TEMPER" state init demo --enter "$1" >/dev/null 2>&1; gpass intent plan
  "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1; }
_r6door review; "$TEMPER" gate build >/dev/null 2>&1
assert_eq "live run 6: a Review door's Build passes on the Build PASS the committed ledger records" "PASS|built in an earlier run|1" \
  "$(python3 -c "import json; g=json.load(open('.temper/gates.json'))['build']; print(g['verdict'] + '|' + g['requirements'][0]['name'])")|$([[ "$("$TEMPER" state get built_before)" == "$(git rev-parse HEAD)" ]] && echo 1 || echo 0)"
assert_exit "live run 6: built_before is the CLI's" 1 "$TEMPER" state set built_before x
assert_exit "live run 6: a door's stage is the CLI's" 1 "$TEMPER" state set enter build
"$TEMPER" state advance build_complete review >/dev/null 2>&1; gpass review
"$TEMPER" state loop review build --reason 'mend it' >/dev/null 2>&1
assert_eq "live run 6: a loop back to Build from a door runs the fix pass on that code, with no integrate" "build|temper:temper-build|0" \
  "$("$TEMPER" state get enter)|$(nx "d['agents'][0]['type']")|$(nx "sum(1 for c in d['agents'][0]['after'] if c.endswith(' integrate'))")"
"$TEMPER" evidence add --stage build --phase red --claim 'test: the regression test fails' --exit 1 >/dev/null 2>&1
"$TEMPER" evidence add --stage build --phase green --claim 'test: the suite passes' --exit 0 >/dev/null 2>&1
assert_exit "live run 6: the fix pass passes Build with its own red and green runs" 0 "$TEMPER" gate build
gpass build review; "$TEMPER" state loop build plan --reason 'a case is missing' >/dev/null 2>&1
assert_eq "live run 6: a loop back to Plan drops what the earlier run built, so Build builds the plan again" "|plan" \
  "$("$TEMPER" state get built_before)|$("$TEMPER" state get next_stage)"
printf 'echo changed\n' > src/demo.sh
_r6door check
OUT="$("$TEMPER" gate build 2>&1)"
assert_eq "live run 6: a plan file changed since the ledger's commit keeps the walked Build failing" "1|0|" \
  "$(grep -c 'RED then GREEN' <<<"$OUT")|$(grep -c 'built in an earlier run' <<<"$OUT")|$("$TEMPER" state get built_before)"
git checkout -q -- src/demo.sh
printf '{"gates": {"build": {"verdict": "PASS", "requirements": []}}, "overrides": [{"stage": "build", "reason": "x"}]}\n' > .temper/specs/demo/gate-ledger.json
git add .temper/specs/demo/gate-ledger.json; git commit -qm "an earlier door's record" >/dev/null 2>&1
_r6door review
assert_exit "live run 8: a later door's skipped Build hides no earlier Build PASS of the same code" 0 "$TEMPER" gate build
printf 'echo other\n' > src/demo.sh; git add src/demo.sh; git commit -qm "a change after the earlier run" >/dev/null 2>&1
_r6door review
assert_exit "live run 8: a plan file changed since the newest Build PASS keeps the walked Build failing" 1 "$TEMPER" gate build
rm -rf .git src

# --- live run 7: each test command counts by its latest run, and a passed Check can still go back to Build ---
fresh
"$TEMPER" evidence add --stage check --claim 'unit tests' --exit 0 --label PROVEN >/dev/null 2>&1
"$TEMPER" evidence add --stage check --claim 'integration tests' --exit 1 --label PROVEN >/dev/null 2>&1
"$TEMPER" evidence add --stage check --claim coverage --value 90 --exit 0 >/dev/null 2>&1
OUT="$("$TEMPER" gate check 2>&1)"
assert_eq "live run 7: a failing integration run beside a passing unit run fails tests pass" "1" \
  "$(grep -c '\[x\] tests pass — the latest run of a test command failed: integration tests' <<<"$OUT")"
"$TEMPER" evidence add --stage check --claim 'Integration  tests' --exit 0 --label PROVEN >/dev/null 2>&1
assert_eq "live run 7: a later passing run of the same command clears it" "1" \
  "$("$TEMPER" gate check 2>&1 | grep -c '\[v\] tests pass')"
_at check; gpass check
assert_eq "live run 7: a passed Check offers Loop back to Build beside Commit" "Commit (Recommended)|Loop back to Build|Save for later" "$(labels)"
