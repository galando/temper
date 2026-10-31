# Release 9.7.5, Phases D and E (F23 to F31). Sourced by test-temper.sh after temper-cases-11.sh (helpers: nx, vw, labels,
# gpass, gfail, fresh, setup, m_setup). The throwaway projects use the folder names unit and src.

# --- F24. Stacked pull request parts: one per Build group, cut at the group merge commits ---
_pr_repo() { # _pr_repo: a repository with a base commit
  rm -rf pr24; mkdir pr24; cd pr24 || return 1
  git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name T
  printf 'echo base\n' > app.sh; git add app.sh; git commit -qm base; git checkout -q -B feature/demo
  PR_BASE="$(git rev-parse HEAD)"
}
_pr_group() { # _pr_group <G> <file> <line...>: a group branch with one commit of those lines, merged with Build's message
  local g="$1" f="$2"; shift 2
  git checkout -q -b "temper/demo/$g" feature/demo
  printf '%s\n' "$@" >> "$f"; git add "$f"; git commit -qm "feat(demo): task in $g"
  git checkout -q feature/demo; git merge -q --no-ff -m "merge(demo): group $g" "temper/demo/$g"
}
_pr_parts() { python3 "$REPO_ROOT/scripts/pr_parts.py" parts "$PR_BASE" demo | python3 -c "
import json, sys
print(';'.join('%d:%s' % (p['part'], '+'.join(p['groups'])) for p in json.load(sys.stdin)))"; }
(_pr_repo; _pr_group G1 src.sh 'echo one'; _pr_group G2 src2.sh 'echo two'
 assert_eq "F24: two groups with code are two parts" "1:G1;2:G2" "$(_pr_parts)"
 cd ..; rm -rf pr24)
(_pr_repo; _pr_group G1 src.sh 'echo one'; _pr_group G2 notes.sh '# only a note' '' '# another'
 assert_eq "F24: a last group of # comments joins the part before" "1:G1+G2" "$(_pr_parts)"
 cd ..; rm -rf pr24)
(_pr_repo; _pr_group G1 notes.js '// a note' ''; _pr_group G2 code.js 'run();'
 assert_eq "F24: a first group of // comments joins the next part" "1:G1+G2" "$(_pr_parts)"
 cd ..; rm -rf pr24)
(_pr_repo; _pr_group G1 a.c '/* a block' ' * of notes' ' */'; _pr_group G2 b.c 'int x;'; _pr_group G3 c.c '// last'
 assert_eq "F24: a block comment counts, and the last comment group joins the part before" "1:G1+G2+G3" "$(_pr_parts)"
 cd ..; rm -rf pr24)
(_pr_repo; seq 1 40 | sed 's/^/int v/;s/$/;/' > a.c; git add a.c; git commit -qm "a.c"; PR_BASE="$(git rev-parse HEAD)"
 git checkout -q -b temper/demo/G1 feature/demo; sed -i '2i /* a block opened here' a.c; sed -i '$a int tail;' a.c; git add a.c; git commit -qm "feat(demo): hunks"
 git checkout -q feature/demo; git merge -q --no-ff -m "merge(demo): group G1" temper/demo/G1; _pr_group G2 b.c 'int y;'
 assert_eq "F24: a block comment left open at the end of a hunk says nothing about the next hunk (that one is code)" "1:G1;2:G2" "$(_pr_parts)"
 cd ..; rm -rf pr24)
(_pr_repo; _pr_group G1 a.c 'int a;'; git checkout -q -b extra; printf 'int tail;\n' >> a.c; git add a.c; git commit -qm tail; git checkout -q feature/demo; git merge -q --ff-only extra
 assert_eq "F24: a commit after the last group merge joins the last part, which then ends at HEAD" "1:G1|$(git rev-parse HEAD)" \
   "$(python3 "$REPO_ROOT/scripts/pr_parts.py" parts "$PR_BASE" demo | python3 -c "import json,sys; p=json.load(sys.stdin)[0]; print(str(p['part'])+':'+'+'.join(p['groups'])+'|'+p['merge'])")"
 cd ..; rm -rf pr24)

# --- F23. The Check question offers draft pull requests, opened by Temper's own steps (no outside skill) ---
fresh; gpass intent plan build review check; _at check
assert_eq "F23: the Check question offers Commit, Loop back, Commit and open PR, and More options" \
  "Commit (Recommended)|Loop back to Build|Commit and open PR|More options" "$(labels)"
assert_eq "F23: Commit and open PR sets pr one and advances, and sets nothing about a skill" \
  "state set pr one|state advance check_complete commit" \
  "$(nx "'|'.join(c.split('temper ', 1)[1] for c in d['ask']['options'][2]['calls'])")"
assert_eq "F23: view.json and next agree (same options)" "$(labels)" "$(vw "'|'.join(o['label'] for o in d['ask']['options'])")"
assert_eq "F23: no option installs, names or asks for a readiness skill" "0" \
  "$(nx "str(sum(1 for o in d['ask']['options'] + d['ask'].get('more', {}).get('options', []) if 'readiness' in (o['label'] + o['description']).lower()))")"
fresh; gpass intent plan build review check; _at check
printf '# Tasks: demo\n\n**Integration:** `true`\n\n## Group G1: A\n**Depends:** none\n**Validate:** `true`\n**Context:**\nx\n\n### Task 1: a\n**File:** `src/a.sh`\n**Test:** `true`\n**Cases:**\n- a\n- [x] done\n\n## Group G2: B\n**Depends:** none\n**Validate:** `true`\n**Context:**\nx\n\n### Task 2: b\n**File:** `src/b.sh`\n**Test:** `true`\n**Cases:**\n- b\n- [x] done\n' > .temper/specs/demo/tasks.md
NXS="$("$TEMPER" next --json 2>/dev/null)"
assert_eq "F23: with two or more Build groups the stacked option is offered too" "Commit and open stacked PRs" "$(_ev "d['ask']['more']['options'][0]['label']" "$NXS")"
printf 'autonomy:\n  enabled: true\n' > .claude/temper.config; "$TEMPER" state set run_mode autonomous >/dev/null 2>&1
assert_eq "F23: an armed run is never offered a pull request" "0" "$(nx "str(sum(1 for o in d.get('ask', {}).get('options', []) if 'open' in o['label'].lower()))")"
printf 'stack: auto\n' > .claude/temper.config

# --- F26. The Pipeline stage after Commit ---
_pl() { # _pl: a run at the Pipeline stage after a Commit that opened a pull request
  fresh; gpass intent plan build review check commit; "$TEMPER" state set pr one >/dev/null 2>&1; _at pipeline
}
_plctx() { printf '%s\n' "$1" > .temper/specs/demo/pipeline-context.json; }
_pl
assert_eq "F26: a run at Pipeline launches the Pipeline agent with the round only (no commit path), and nothing of the person's answer" \
  "work|temper:temper-pipeline|0|1|0" \
  "$(nx "a = d['agents'][0]; '|'.join([d['action'], a['type'], str(a['prompt'].count('Commit path')), str(a['prompt'].count('Round: 1.')), str(a['prompt'].count('reason'))])")"
assert_eq "F26: the agent's gate call is the last of its after calls" "gate pipeline" "$(nx "d['agents'][0]['after'][-1].split('temper ', 1)[1]")"
assert_eq "F26: the stage is in the CLI's models and its brief names sonnet" "sonnet" "$("$TEMPER" model pipeline)"
"$TEMPER" gate pipeline >/dev/null 2>&1
assert_eq "F26: no context file is a result that is not final, and the question offers to run Pipeline again" \
  "ask|Run Pipeline again (Recommended)|state redo pipeline --reason 'the Pipeline result is missing or not final'" \
  "$(nx "d['action'] + '|' + d['ask']['options'][0]['label'] + '|' + d['ask']['options'][0]['calls'][0].split('temper ', 1)[1]")"
_plctx '{"status": "green", "failed_jobs": [], "fix": [], "round": 1}'
"$TEMPER" gate pipeline >/dev/null 2>&1
assert_eq "F26: green asks to end the run" "Pipeline: every job passed. End the run?|End the run (Recommended)|Save for later" \
  "$(nx "d['ask']['question']['question'] + '|' + '|'.join(o['label'] for o in d['ask']['options'])")"
_plctx '{"status": "red", "failed_jobs": [{"name": "unit", "stage": "test", "id": "1", "error": "boom"}], "fix": ["unit/a.sh: the value is 4"], "round": 1}'
"$TEMPER" gate pipeline >/dev/null 2>&1
assert_eq "F26: red asks Apply the fix and push?, and the steps are the agreed ones in order" \
  "Apply the fix and push?|adhoc open --stage pipeline --reason 'CI fix round 1'|git push|adhoc close|state set pipeline_round 2|state redo pipeline --reason 'CI fix round 1 pushed; CI runs again'" \
  "$(nx "q = d['ask']; s = q['options'][0]['steps']; q['question']['question'].split('). ', 1)[1] + '|' + '|'.join([s[0].split('temper ', 1)[1], s[4], s[5].split('temper ', 1)[1], s[6].split('temper ', 1)[1], s[7].split('temper ', 1)[1]])")"
assert_eq "F26: the commit step stages by name and never with -A" "0" "$(nx "str(sum(1 for s in d['ask']['options'][0]['steps'] if 'git add -A' in s or 'git add .' == s.strip()))")"
"$TEMPER" state set pipeline_round 3 >/dev/null 2>&1
assert_eq "F26: past loops.max-per-type rounds the question says the fix limit is reached" "Pipeline: the fix limit is reached (round 3 of 2). End the run?" "$(nx "d['ask']['question']['question']")"
"$TEMPER" state set pipeline_round 1 >/dev/null 2>&1
"$TEMPER" state redo pipeline --reason "CI fix round 1 pushed; CI runs again" >/dev/null 2>&1
assert_eq "F26: a redo removes the old verdict and the context file, so CI is read again" "none|no|work" \
  "$(python3 -c "import json; print(json.load(open('.temper/gates.json')).get('pipeline', {}).get('verdict', 'none'))")|$([[ -f .temper/specs/demo/pipeline-context.json ]] && echo yes || echo no)|$(nx "d['action']")"
fresh; gpass intent plan build review check; "$TEMPER" state set pr one >/dev/null 2>&1; printf 'phases:\n  pipeline: false\n' > .claude/temper.config
"$TEMPER" next --json >/dev/null 2>&1
assert_eq "F26: with phases.pipeline false the sequence has no Pipeline stage" "0" "$(vw "str(sum(1 for s in d['stages'] if s.get('id') == 'pipeline'))")"
printf 'stack: auto\n' > .claude/temper.config
fresh; gpass intent plan build review check; "$TEMPER" state set pr one >/dev/null 2>&1; "$TEMPER" next --json >/dev/null 2>&1
assert_eq "F26: with a pull request opened the sequence ends with Pipeline" "1" "$(vw "str(sum(1 for s in d['stages'] if s.get('id') == 'pipeline'))")"
assert_eq "F26: gate pipeline is a gate stage of the CLI" "1" "$("$TEMPER" gate pipeline 2>&1 | grep -c 'temper gate pipeline ->')"

# --- F28. Leaving Intent when the run's branch exists from an earlier run with commits this checkout lacks ---
fresh; rm -rf .git; git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name T; git checkout -q -B main 2>/dev/null
echo base > README; git add README; git commit -qm base; gpass intent
git checkout -q -b feature/demo; echo old > old.txt; git add old.txt; git commit -qm "an earlier run's work"; git checkout -q main
assert_eq "F28: the question names the branch and its last commit, and offers both ways on" "1|Continue on feature/demo|Continue on a new branch feature/demo-2" \
  "$(nx "str(d['ask']['question']['question'].count('The branch feature/demo already exists from an earlier run')) + '|' + d['ask']['options'][0]['label'] + '|' + d['ask']['options'][1]['label']")"
assert_eq "F28: the first one carries the spec across with a temp folder, never git stash" "1|0" \
  "$(nx "c = d['ask']['options'][0]['calls'][0]; str(int('mktemp -d' in c and 'git checkout feature/demo' in c)) + '|' + str(c.count('git stash'))")"
assert_eq "F28: the new branch option checks it out and sets the state branch" "git checkout -b feature/demo-2|state set branch feature/demo-2" \
  "$(nx "o = d['ask']['options'][1]['calls']; o[0] + '|' + o[1].split('temper ', 1)[1]")"
git branch -q feature/demo-2 main 2>/dev/null
assert_eq "F28: the new number is the next free one" "Continue on a new branch feature/demo-3" "$(nx "d['ask']['options'][1]['label']")"
git branch -D feature/demo-2 >/dev/null 2>&1
git checkout -q feature/demo; git checkout -q -B plain main; git branch -f feature/demo main
assert_eq "F28: a branch with no extra commits keeps the plain switch" "Continue to Plan (Recommended)" "$(labels | cut -d'|' -f1)"
# the carry-across call really moves the new spec files across the switch
git branch -f feature/demo main; git checkout -q feature/demo; echo old > old.txt; git add old.txt; git commit -qm "earlier"; git checkout -q plain
mkdir -p .temper/specs/demo; echo "# new intent" > .temper/specs/demo/intent.md
CALL="$(nx "d['ask']['options'][0]['calls'][0]")"
bash -c "$CALL" >/dev/null 2>&1
assert_eq "F28: the carry call lands on the branch with the new spec file in place, and no temp folder is left" "feature/demo|# new intent|yes" \
  "$(git branch --show-current)|$(cat .temper/specs/demo/intent.md)|$([[ -f old.txt ]] && echo yes || echo no)"

# --- F29 and F30. The commit hook gates the run's branch only; turning Temper off fully ---
fresh; rm -rf .git; git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name T; git checkout -q -B main 2>/dev/null
echo base > README; git add README; git commit -qm base; "$TEMPER" state set branch feature/demo >/dev/null 2>&1
git checkout -q -b other
OUT="$("$TEMPER" gate commit --from-hook 2>&1)"; rc=$?
assert_eq "F29: a commit on another branch passes with one line, and records nothing" "0|1|none" \
  "$rc|$(grep -c 'the run demo is on feature/demo; this commit is on other, so the commit gate does not apply.' <<<"$OUT")|$(python3 -c "import json; print(json.load(open('.temper/gates.json')).get('commit', {}).get('verdict', 'none'))")"
git checkout -q -b feature/demo
"$TEMPER" gate commit --from-hook >/dev/null 2>&1
assert_eq "F29: on the run's branch the gate applies" "FAIL" "$(python3 -c "import json; print(json.load(open('.temper/gates.json')).get('commit', {}).get('verdict', 'none'))")"
git checkout -q --detach
assert_eq "F29: a detached HEAD keeps the gate" "FAIL" "$("$TEMPER" gate commit --from-hook 2>&1 | grep -o 'FAIL' | head -1)"
git checkout -q feature/demo
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
assert_eq "F30: the installer's hook runs the commit gate with --from-hook" "1" "$(grep -c 'gate commit --from-hook' "$(git rev-parse --git-common-dir)/temper-gate/pre-commit")"
assert_eq "F30: the hook passes, naming temper guards uninstall, when the plugin's CLI is gone" "0|1" \
  "$(sed "s|^TEMPER_CLI=.*|TEMPER_CLI=/nonexistent/scripts/temper|" "$(git rev-parse --git-common-dir)/temper-gate/pre-commit" > hookcopy.sh; bash hookcopy.sh >/dev/null 2>&1; echo $?)|$(sed "s|^TEMPER_CLI=.*|TEMPER_CLI=/nonexistent/scripts/temper|" "$(git rev-parse --git-common-dir)/temper-gate/pre-commit" > hookcopy.sh; bash hookcopy.sh 2>&1 | grep -c 'temper guards uninstall')"
rm -f hookcopy.sh
OUT="$("$TEMPER" guards uninstall 2>&1)"
assert_eq "F30: uninstall removes the hook and its folder and unsets core.hooksPath" "no|no|unset" \
  "$([[ -f "$(git rev-parse --git-common-dir)/temper-gate/pre-commit" ]] && echo yes || echo no)|$([[ -d "$(git rev-parse --git-common-dir)/temper-gate" ]] && echo yes || echo no)|$(git config --get core.hooksPath || echo unset)"
assert_eq "F30: a second run changes nothing" "1" "$("$TEMPER" guards uninstall 2>&1 | grep -c 'nothing to change')"
assert_eq "F30: install.sh --uninstall does the same" "1" "$(bash "$REPO_ROOT/scripts/guards/install.sh" --uninstall 2>&1 | grep -c 'nothing to change')"
assert_eq "F30: the installer's To uninstall line names the command" "1" "$(bash "$REPO_ROOT/scripts/guards/install.sh" 2>&1 | grep -c "temper guards uninstall")"
bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
mkdir -p userhooks; printf '#!/bin/sh\nbash "$(git rev-parse --git-common-dir)/temper-gate/pre-commit" || exit 1\n' > userhooks/pre-commit; chmod +x userhooks/pre-commit
git config core.hooksPath "$PWD/userhooks"
OUT="$("$TEMPER" guards uninstall 2>&1)"
assert_eq "F30: a Temper line in a hook of the user's own is named, and not changed; core.hooksPath that is not Temper's stays" "1|1|$PWD/userhooks" \
  "$(grep -c 'your hook .* runs the Temper hook' <<<"$OUT")|$(grep -c 'temper-gate/pre-commit' userhooks/pre-commit)|$(git config --get core.hooksPath)"
git config --unset core.hooksPath; rm -rf userhooks
assert_eq "F30: state init prints one Note line saying the run owns the folder and a worktree gives other work its own run" "1" "$(setup; "$TEMPER" state clear >/dev/null 2>&1; "$TEMPER" state init noteslug 2>&1 | grep -c '^Note: the run noteslug owns this folder; separate work goes in a worktree')"

# --- F30. A guard script passes at once, with one line naming temper guards uninstall, when the plugin's CLI is gone ---
GP="$WORKDIR/gone-plugin"; rm -rf "$GP"; mkdir -p "$GP/scripts/guards"
cp "$REPO_ROOT/scripts/guards/block-uncommitted-gate.sh" "$REPO_ROOT/scripts/guards/block-protected-paths.sh" "$GP/scripts/guards/"
for g in block-uncommitted-gate block-protected-paths; do
  OUT="$(cd "$WORKDIR" && echo '{"tool_input": {"command": "git commit -m x", "file_path": "a.txt"}}' | bash "$GP/scripts/guards/$g.sh" 2>&1; echo "rc=$?")"
  assert_eq "F30: $g passes with one line naming temper guards uninstall when the CLI is gone" "1|rc=0" "$(grep -c 'temper guards uninstall' <<<"$OUT")|$(grep -o 'rc=[0-9]*' <<<"$OUT")"
done
rm -rf "$GP"
