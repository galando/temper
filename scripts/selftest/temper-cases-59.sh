# Case file 59 (WP18): two holes. `temper evidence resolve` marks a finding resolved only for a commit the CLI made
# after Review read the code; Review's completion row names the files it read, and the row `review completed` passes
# only when that list holds every changed file of the run. Sourced by test-temper.sh; its helpers (fresh, gpass, nx,
# review_done, cli_commit) are used here, and the state builders below are this file's own.
# The four checks of resolve: --fixed-by names a commit; it is an ancestor of HEAD; it is not an ancestor of the
# reviewed HEAD (the `head` of review_snapshot, which the CLI writes when the run enters Review); it is in cli_commits
# of .temper/groups.json. A refusal exits 1 with one `FAIL:` line that names which check failed and the short ids, and
# writes nothing. The changed files of the run are the commit gate's set (since base_sha, plus uncommitted and
# untracked files), less .temper/ and .claude/ and less files that no longer exist; after a small change at Review,
# that window's files. `temper review files` prints them, one path a line.

# --- the helpers of this file ---
_repo59() { # a fresh git repository under the run: one source file, every file but the run's own in one commit
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh
  git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_branch59() { # the run's own branch, with base_sha at the commit checked out
  git checkout -q -B feature/demo; "$TEMPER" state set branch feature/demo >/dev/null 2>&1
  "$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
}
_review59() { # the run goes from Intent to Review by the CLI's own calls, each check before it passed; entering Review
              # writes review_snapshot
  local s
  gpass intent plan build
  for s in intent_complete:plan plan_complete:build build_complete:review; do
    "$TEMPER" state advance "${s%%:*}" "${s##*:}" >/dev/null 2>&1
  done
}
_cli59() { # _cli59 <commit>...: appends the full ids to cli_commits of .temper/groups.json
  python3 - "$@" <<'PY'
import json, subprocess, sys
p = ".temper/groups.json"
d = json.load(open(p))
for x in sys.argv[1:]:
    sha = subprocess.run(["git", "rev-parse", x], stdout=subprocess.PIPE).stdout.decode().strip()
    d.setdefault("cli_commits", []).append(sha)
json.dump(d, open(p, "w"))
PY
}
_req59() { # _req59 <row name> <pass|detail>: that field of the row of Review's verdict in gates.json, or absent
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get("review") or {}
except (OSError, ValueError):
    e = {}
r = next((x for x in e.get("requirements") or [] if x.get("name") == sys.argv[1]), None)
print("absent" if r is None else r.get(sys.argv[2]))
PY
}
_pass59() { _req59 "$1" pass; }
_verdict59() { # Review's verdict in gates.json
  python3 -c "import json; print(json.load(open('.temper/gates.json'))['review']['verdict'])" 2>/dev/null
}
_done59row() { # _done59row <detail prefix>: pass of the row review completed, then the prefix when its detail starts
               # with it, else the detail
  local d; d="$(_req59 'review completed' detail)"
  [[ "$d" == "$1"* ]] && d="$1"
  echo "$(_pass59 'review completed')|$d"
}

# --- evidence resolve checks its commit ---
_resolve59() { # a run of a git repository on its branch at a failed Review: one change committed after the base, the
               # reviewed HEAD in review_snapshot, one high finding (id 1) and the completion row that names every
               # changed file, so the finding is the one failed row; a grouped Build passed, and cli_commits is
               # there and empty
  fresh; _repo59; sed -i '/block-on/d' .claude/temper.config; _branch59
  echo 'echo built' > src/demo.sh; printf 'a=1\n' > src/demo_test.sh; git add src; git commit -q -m build
  python3 - "$(git rev-parse HEAD)" <<'PY'
import json, sys
d = {"version": 1, "slug": "demo", "cli_commits": [],
     "groups": {"G1": {"status": "passed", "worktree": "", "branch": "temper/demo/G1", "confirmed": True,
                       "gate": {"verdict": "PASS"}}},
     "tasks": {"1": {"status": "passed", "group": "G1"}},
     "integration": {"verdict": "PASS", "head": sys.argv[1], "merged": True}}
json.dump(d, open(".temper/groups.json", "w"))
PY
  _review59
  "$TEMPER" evidence add --stage review --claim 'src/demo.sh:1 the demo prints nothing on error' --severity high \
    --label PROVEN >/dev/null 2>&1
  review_done
  "$TEMPER" gate review >/dev/null 2>&1
}
_rs59() { # _rs59 <fixed-by>: resolves finding 1 with it; the exit code in _rs59_rc, the output in _rs59_out
  _rs59_out="$("$TEMPER" evidence resolve --stage review --id 1 --fixed-by "$1" 2>&1)"; _rs59_rc=$?
}
_state59() { # the state of finding 1: open, or resolved and what it was resolved by
  python3 - <<'PY' 2>/dev/null || echo none
import json
e = json.load(open(".temper/evidence/review.json"))[0]
r = e.get("resolved") or {}
print("resolved by %s" % r.get("fixed_by") if r else "accepted" if e.get("accepted") else "open")
PY
}
_failline59() { # _failline59 [commit...]: "one FAIL line" when the last resolve printed exactly one line that starts
                # with FAIL:, and that line holds the first 7 characters of each commit given; else what it printed
  local line n c sha
  n="$(grep -c '^FAIL: ' <<<"$_rs59_out")"
  line="$(grep '^FAIL: ' <<<"$_rs59_out" | head -1)"
  [[ "$n" == 1 ]] || { echo "$n FAIL lines: $_rs59_out"; return; }
  for c in "$@"; do
    sha="$(git rev-parse "$c")"
    [[ "$line" == *"${sha:0:7}"* ]] || { echo "the line names no ${sha:0:7}: $line"; return; }
  done
  echo "one FAIL line"
}

_resolve59
_rs59 'no such commit'
_x1_gate="$("$TEMPER" gate review 2>&1)"
[[ "$_x1_gate" == *'-> FAIL'* ]] && _x1_gate='gate prints FAIL' || _x1_gate='gate prints PASS'
_x1_rows="no blocking findings=$(_pass59 'no blocking findings')|review completed=$(_pass59 'review completed')"
assert_eq "evidence resolve refuses a text that is no commit: exit 1, and temper gate review still prints FAIL (X1)" \
  "exit=1|one FAIL line|gate prints FAIL|no blocking findings=False|review completed=True|open" \
  "exit=$_rs59_rc|$(_failline59)|$_x1_gate|$_x1_rows|$(_state59)"

_resolve59
_rv59_head="$(git rev-parse HEAD)"; _rv59_base="$(git rev-parse HEAD~1)"
_cli59 "$_rv59_head" "$_rv59_base"   # both in cli_commits: only the third check can refuse them
_rs59 "$_rv59_head"; _rv59_a="exit=$_rs59_rc:$(_failline59 "$_rv59_head"):$(_state59)"
_rs59 "$_rv59_base"; _rv59_b="exit=$_rs59_rc:$(_failline59 "$_rv59_base" "$_rv59_head"):$(_state59)"
assert_eq "evidence resolve refuses a commit Review already read: the reviewed HEAD itself, and any ancestor of it" \
  "head=exit=1:one FAIL line:open|ancestor=exit=1:one FAIL line:open" "head=$_rv59_a|ancestor=$_rv59_b"

_resolve59
cli_commit >/dev/null   # a commit of the CLI in cli_commits, so the list is not empty
echo 'by hand' > .temper/specs/demo/hand.md; git add -f .temper/specs/demo/hand.md; git commit -q -m 'a commit by hand'
_rs59 "$(git rev-parse HEAD)"
assert_eq "evidence resolve refuses a commit the CLI did not make: a commit made by hand after Review started" \
  "exit=1|one FAIL line|open" "exit=$_rs59_rc|$(_failline59 HEAD)|$(_state59)"

_resolve59
_el59="$(git commit-tree 'HEAD^{tree}' -p HEAD -m 'a commit on another branch')"
git update-ref refs/heads/elsewhere "$_el59"; _cli59 "$_el59"
_rs59 "$_el59"
assert_eq "evidence resolve refuses a commit that is not on this branch" \
  "exit=1|one FAIL line|open" "exit=$_rs59_rc|$(_failline59 "$_el59")|$(_state59)"

_resolve59
python3 - <<'PY'
import json
p = ".temper/build-state.json"
d = json.load(open(p))
d.pop("review_snapshot", None)
json.dump(d, open(p, "w"), indent=2)
PY
_ns59="$(cli_commit)"
_rs59 "$_ns59"
assert_eq "evidence resolve refuses when the run has no Review snapshot" \
  "exit=1|one FAIL line|open" "exit=$_rs59_rc|$(_failline59)|$(_state59)"

_resolve59
_tk59="$(cli_commit)"
_rs59 "${_tk59:0:7}"   # a short id: the stored mark is the full id
"$TEMPER" gate review >/dev/null 2>&1
assert_eq "evidence resolve takes a commit the CLI recorded after the reviewed HEAD, and stores the full id" \
  "exit=0|resolved by $_tk59|no blocking findings=True|review=PASS" \
  "exit=$_rs59_rc|$(_state59)|no blocking findings=$(_pass59 'no blocking findings')|review=$(_verdict59)"

# --- Review's completion row names the files read ---
_change59() { # _change59 <n>: a run at Review whose change, committed after the base, adds n files src/f01.sh,
              # src/f02.sh and on; no completion row yet
  local i
  fresh; _repo59; _branch59
  for ((i = 1; i <= $1; i++)); do printf 'echo %d\n' "$i" > "src/f$(printf %02d "$i").sh"; done
  git add src; git commit -q -m change
  _review59
}
_done59() { # _done59 <file>...: Review's completion row with one --read for each file named, then the gate
  local f args=()
  for f in "$@"; do args+=(--read "$f"); done
  "$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label HEURISTIC ${args[@]+"${args[@]}"} \
    >/dev/null 2>&1
  "$TEMPER" gate review >/dev/null 2>&1
}
_f59() { # _f59 <from> <to>: the names src/fNN.sh from one number to the other
  local i
  for ((i = $1; i <= $2; i++)); do printf 'src/f%02d.sh\n' "$i"; done
}
_files59() { "$TEMPER" review files 2>/dev/null | LC_ALL=C sort | tr '\n' ' '; }   # what it prints, on one line

_change59 14; _done59 src/f01.sh src/f02.sh
_sh59_d="$(_req59 'review completed' detail)"
[[ "$_sh59_d" == *src/f03.sh* ]] && _sh59_d='names src/f03.sh' || _sh59_d='names no unread file'
assert_eq "review completed fails when a changed file was not read: 14 changed files, a row that names 2" \
  "False|read 2 of 14 changed files; not read:|names src/f03.sh" \
  "$(_done59row 'read 2 of 14 changed files; not read:')|$_sh59_d"

_change59 14; _done59 $(_f59 1 14)
assert_eq "review completed passes when every changed file is named, with the detail read 14 of 14 changed files" \
  "True|read 14 of 14 changed files" "$(_done59row 'read 14 of 14 changed files')"

_change59 14; _done59
assert_eq "review completed fails on a row with no read list when files changed (as a run saved before WP18 has)" \
  "False|read 0 of 14 changed files" "$(_done59row 'read 0 of 14 changed files')"

_change59 2; _done59 ./src/f01.sh src/f02.sh
_rl59="$(python3 - <<'PY' 2>/dev/null
import json
e = [x for x in json.load(open(".temper/evidence/review.json")) if x.get("claim") == "review completed"]
print(",".join(e[-1].get("read") or []) if e else "no row")
PY
)"
assert_eq "the completion row stores its read list relative to the project, a leading ./ taken off" \
  "read=src/f01.sh,src/f02.sh|True" "read=$_rl59|$(_pass59 'review completed')"

_change59 1
_rd59() { "$TEMPER" evidence add "$@" --read src/f01.sh >/dev/null 2>&1; echo $?; }
_rd59_done="$(_rd59 --stage review --claim 'review completed' --exit 0)"
_rd59_build="$(_rd59 --stage build --claim 'a build note')"
_rd59_find="$(_rd59 --stage review --claim 'src/f01.sh:1 a finding' --severity high)"
assert_eq "evidence add takes --read only on Review's completion row" \
  "completion=0|build row=1|finding=1" "completion=$_rd59_done|build row=$_rd59_build|finding=$_rd59_find"

fresh; _repo59; echo 'echo gone' > src/gone.sh; git add src; git commit -q -m 'base two'; _branch59
echo 'echo built' > src/demo.sh; git rm -q src/gone.sh
echo 'a note' > .temper/specs/demo/notes.md; echo 'a note' > .claude/notes.md
git add src; git add -f .temper/specs/demo/notes.md .claude/notes.md; git commit -q -m change
echo 'scratch' > .claude/scratch.md   # untracked, beside the run's own untracked state in .temper/
_review59
_dl59_files="$(_files59)"
_done59 src/demo.sh
assert_eq "a deleted file and the run's own state are not asked for" \
  "files=src/demo.sh |True|read 1 of 1 changed files" "files=$_dl59_files|$(_done59row 'read 1 of 1 changed files')"

_window59() { # _window59 <file>: a run at Review whose change adds three files, Review done; then a small change of
              # src/f01.sh at Review, and the narrow Review's completion row names the one file given
  _change59 3; review_done; "$TEMPER" gate review >/dev/null 2>&1
  "$TEMPER" adhoc open --stage review --reason 'a small change' >/dev/null 2>&1
  echo 'echo changed' > src/f01.sh
  "$TEMPER" adhoc close >/dev/null 2>&1
  _wn59_files="$(_files59)"
  _done59 "$1"
}
_window59 src/f01.sh
_wn59_ok="files=$_wn59_files|window=$(_done59row 'read 1 of 1 changed files')"
_window59 src/f02.sh
assert_eq "the narrow Review after a small change is held to the window's files" \
  "files=src/f01.sh |window=True|read 1 of 1 changed files|another file=False" \
  "$_wn59_ok|another file=$(_pass59 'review completed')"

fresh; _repo59; echo 'echo keep' > src/keep.sh; git add src; git commit -q -m 'base two'; _branch59
echo 'echo a' > src/a.sh; echo 'echo built' > src/demo.sh; git add src; git commit -q -m change
echo 'echo changed' > src/keep.sh; echo 'echo new' > src/new.sh   # one file changed and one new, neither committed
_review59
"$TEMPER" review files >/dev/null 2>&1; _pf59_rc=$?
_pf59_files="$(_files59)"
_done59 $_pf59_files
assert_eq "temper review files prints the set the gate compares: since the base, uncommitted and untracked" \
  "exit=0|src/a.sh src/demo.sh src/keep.sh src/new.sh |True|read 4 of 4 changed files" \
  "exit=$_pf59_rc|$_pf59_files|$(_done59row 'read 4 of 4 changed files')"

_change59 3; _done59 src/f01.sh
_ag59_rec="$(nx "next((o['label'] for o in d['ask']['options'] if o.get('recommended')), None)")"
_ag59_calls="$(nx "'\n'.join(c for o in d['ask']['options'] if o.get('recommended') for c in o.get('calls') or [])")"
while IFS= read -r _c59; do
  [[ -n "$_c59" ]] && bash -c "${_c59//\{reason\}/the review did not finish}" >/dev/null 2>&1
done <<<"$_ag59_calls"
_ag59_launch="$(python3 - "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
except ValueError:
    d = {}
a = (d.get("agents") or [{}])[0]
lines = str(a.get("prompt") or "").split("\n")
named = any("src/f02.sh" in x and "src/f03.sh" in x and "src/f01.sh" not in x for x in lines)
print("%s:%s|%s" % (d.get("action"), d.get("stage"),
                    "a line names the unread files" if named else "no line names the unread files"))
PY
)"
assert_eq "the question after a short Review recommends Run Review again, and the launch names the unread files" \
  "Run Review again (Recommended)|work:review|a line names the unread files" "$_ag59_rec|$_ag59_launch"
