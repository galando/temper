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
"$TEMPER" state init demo --enter check >/dev/null 2>&1; gpass intent
assert_eq "round 4, 7: a walked Intent whose spec is committed and accepted makes no empty commit" "intent accept|0|state advance intent_complete plan" \
  "$(nx "o = d['ask']['options'][0]; c = o['calls']; c[0].split('temper ', 1)[1] + '|' + str(sum(1 for x in c if x.startswith('git commit'))) + '|' + c[-1].split('temper ', 1)[1]")"
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
assert_eq "re-audit: after Keep with no integrate, next merges the groups again (no question that only fails)" "work|integrate|gate build" \
  "$(nx "d['action'] + '|' + '|'.join(c.split('temper ')[-1] for c in d['calls'])")"
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
