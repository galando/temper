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
(_pr_repo; _pr_group G1 a.c '/* opens here' 'int hidden;'; _pr_group G2 b.c 'int y;'
 assert_eq "F24: a block comment left open (code inside it) is not comment only: block state resets per hunk" "1:G1;2:G2" "$(_pr_parts)"
 cd ..; rm -rf pr24)
(_pr_repo; _pr_group G1 a.c 'int a;'; git checkout -q -b extra; printf 'int tail;\n' >> a.c; git add a.c; git commit -qm tail; git checkout -q feature/demo; git merge -q --ff-only extra
 assert_eq "F24: a commit after the last group merge joins the last part, which then ends at HEAD" "1:G1|$(git rev-parse HEAD)" \
   "$(python3 "$REPO_ROOT/scripts/pr_parts.py" parts "$PR_BASE" demo | python3 -c "import json,sys; p=json.load(sys.stdin)[0]; print(str(p['part'])+':'+'+'.join(p['groups'])+'|'+p['merge'])")"
 cd ..; rm -rf pr24)

# --- F23 and F25. The Check question offers draft pull requests; the readiness skill is detected without reading the home folder ---
fresh; gpass intent plan build review check; _at check
assert_eq "F23: without the readiness skill the Check question offers Commit, Install it, and Skip it for Temper PR steps" \
  "Commit (Recommended)|Loop back to Build|Install the readiness skill and try again|More options" "$(labels)"
assert_eq "F25: Skip it asks a reason, records readiness: unavailable, sets pr one and commit_path skip, then advances" \
  "True|evidence add --stage commit --claim 'readiness: unavailable, skipped by you: {reason}'|state set pr one|state set commit_path skip|state advance check_complete commit" \
  "$(nx "o = d['ask']['more']['options'][0]; str(o['reason']) + '|' + '|'.join(c.split('temper ', 1)[1] for c in o['calls'])")"
assert_eq "F25: view.json and next agree (same options)" "$(labels)" "$(vw "'|'.join(o['label'] for o in d['ask']['options'])")"
"$TEMPER" next --json --skill review-readiness >/dev/null 2>&1
assert_eq "F25: with the skill listed by the session, the question offers Commit and open PR with commit_path skill" \
  "Commit (Recommended)|Loop back to Build|Commit and open PR|More options|state set pr one|state set commit_path skill" \
  "$(labels)|$(nx "'|'.join(c.split('temper ', 1)[1] for c in d['ask']['options'][2]['calls'][:2])")"
assert_eq "F25: the view the next command wrote agrees, and a later command's view keeps the answer" "Commit (Recommended)|Commit and open PR" \
  "$("$TEMPER" state get next_stage >/dev/null; vw "d['ask']['options'][0]['label'] + '|' + d['ask']['options'][2]['label']")"
mkdir -p .claude/skills/review-readiness; echo x > .claude/skills/review-readiness/SKILL.md; "$TEMPER" next --json >/dev/null 2>&1
assert_eq "F25: the project's own .claude/skills folder also counts" "Commit and open PR" "$(labels | cut -d'|' -f3)"
rm -rf .claude/skills
fresh; gpass intent plan build review check; _at check; "$TEMPER" next --json --skill review-readiness >/dev/null 2>&1
printf '# Tasks: demo\n\n**Integration:** `true`\n\n## Group G1: A\n**Depends:** none\n**Validate:** `true`\n**Context:**\nx\n\n### Task 1: a\n**File:** `src/a.sh`\n**Test:** `true`\n**Cases:**\n- a\n- [x] done\n\n## Group G2: B\n**Depends:** none\n**Validate:** `true`\n**Context:**\nx\n\n### Task 2: b\n**File:** `src/b.sh`\n**Test:** `true`\n**Cases:**\n- b\n- [x] done\n' > .temper/specs/demo/tasks.md
assert_eq "F23: with two or more Build groups the stacked option is offered too" "Commit and open stacked PRs" "$(nx "d['ask']['more']['options'][0]['label'] if len(d['ask']['options']) == 4 and d['ask']['more']['options'][0]['label'].startswith('Commit and open') else d['ask']['options'][2]['label']")"
printf 'autonomy:\n  enabled: true\n' > .claude/temper.config; "$TEMPER" state set run_mode autonomous >/dev/null 2>&1
assert_eq "F23: an armed run is never offered a pull request" "0" "$(nx "str(sum(1 for o in d.get('ask', {}).get('options', []) if 'open' in o['label'].lower()))")"
printf 'stack: auto\n' > .claude/temper.config
