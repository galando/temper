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
