# --- Grouped Build (9.7.0), focused review of the undo: reverse 3-way, batching, bytes, locks [G1-G6] ---
# Invariants: (a) a FAIL never changes a running same-group sibling's working tree or the CLI's commits; (b) a foreign
# (agent-made) commit's content never stays on the group branch after a FAIL, also when a sibling's CLI commit later
# touched the same path; (c) a FAIL on attempt 1 or 2 retries/escalates (D-03) and only a genuine undo failure parks.
g_now() { python3 -c "import time; print(time.time())"; }
g_setup() { # f_setup + src/b.sh and src/d.sh committed with eight lines on the group branch before any task starts
  f_setup
  mkdir -p "$ST_WT/src"
  printf 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\n' > "$ST_WT/src/b.sh"; cp "$ST_WT/src/b.sh" "$ST_WT/src/d.sh"
  git -C "$ST_WT" add src/b.sh src/d.sh; git -C "$ST_WT" commit -q -m "multi-line base" 2>/dev/null
}
g_lines() { git -C "$ST_WT" show "HEAD:$1" 2>/dev/null | paste -sd, -; }
g_red() { ST_EXIT=1 "$TEMPER" task test "$1" --phase red >/dev/null 2>&1; }
g_green() { ST_EXIT=0 "$TEMPER" task test "$1" --phase green >/dev/null 2>&1; }
g_commit() { git -C "$ST_WT" add -A -- "$@" 2>/dev/null; git -C "$ST_WT" commit -q -m "agent commit" 2>/dev/null; }

# G1: the agent edits a sibling's declared file and commits; the sibling starts later, edits another line and PASSes;
# then the agent's task FAILs: the foreign line is gone, the sibling's own change stays
g_setup
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
sed -i.bak 's/^l1$/FOREIGN/' "$ST_WT/src/b.sh"; rm -f "$ST_WT/src/b.sh.bak"; g_commit src/b.sh
"$TEMPER" task start 2 >/dev/null 2>&1; g_red 2
printf 'sibling line\n' >> "$ST_WT/src/b.sh"; g_green 2
assert_exit "G1: the sibling starting after the agent commit passes" 0 "$TEMPER" task gate 2
st_edit src/a.sh; g_green 1
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "G1: Task 1 FAILs for the commit it made and retries (not parked)" "1|failed||1" \
  "$rc|$(st_field 1 status)|$(gg_g G1 parked_reason)|$(printf '%s' "$out" | grep -c '^NEXT: retry Task 1')"
assert_eq "G1: the foreign line is off the branch and the sibling's own line is kept" "l1,l2,l3,l4,l5,l6,l7,l8,sibling line" "$(g_lines src/b.sh)"
assert_eq "G1: the working file of the finished sibling follows the branch" "l1,l2,l3,l4,l5,l6,l7,l8,sibling line" "$(paste -sd, - < "$ST_WT/src/b.sh")"
assert_eq "G1: the sibling's file is clean in git status" "" "$(git -C "$ST_WT" status --porcelain -- src/b.sh)"

# G1 conflict: the sibling changed the very line the agent changed; the reverse apply conflicts, so the group parks
# with an accurate message and the shas are not recorded as reverted
g_setup
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
sed -i.bak 's/^l1$/FOREIGN/' "$ST_WT/src/b.sh"; rm -f "$ST_WT/src/b.sh.bak"; g_commit src/b.sh
"$TEMPER" task start 2 >/dev/null 2>&1; g_red 2
sed -i.bak 's/^FOREIGN$/sibling l1/' "$ST_WT/src/b.sh"; rm -f "$ST_WT/src/b.sh.bak"; g_green 2
"$TEMPER" task gate 2 >/dev/null 2>&1
st_edit src/a.sh; g_green 1
BEFORE="$(git -C "$ST_WT" rev-parse HEAD)"
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "G1 conflict: the group parks and the branch is left as it was" "1|parked|$BEFORE" "$rc|$(gg_g G1 status)|$(git -C "$ST_WT" rev-parse HEAD)"
assert_eq "G1 conflict: nothing is recorded as reverted" "0" \
  "$(python3 -c "import json; print(len(json.load(open('.temper/groups.json')).get('reverted_foreign') or []))")"
assert_eq "G1 conflict: the park reason says the commit conflicts with a later change" "1" "$(gg_g G1 parked_reason | grep -c 'conflict')"
# G2: the park hint never tells the human to stash (that loses a running sibling's work) and points at the CLI
assert_eq "G2: the park hint has no stash, says to wait for running tasks and to reopen through the CLI" "0|1|1" \
  "$(gg_g G1 parked_reason | grep -ci 'stash')|$(gg_g G1 parked_reason | grep -c 'no task of this group is running')|$(gg_g G1 parked_reason | grep -c 'temper group reopen G1 --task 1')"

# G2 (sibling work): a running sibling's uncommitted file is intact after the parked FAIL
g_setup
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
"$TEMPER" task start 2 >/dev/null 2>&1; g_red 2; st_edit src/b.sh
sed -i.bak 's/^l1$/FOREIGN/' "$ST_WT/src/d.sh"; rm -f "$ST_WT/src/d.sh.bak"; g_commit src/d.sh
"$TEMPER" task start 4 >/dev/null 2>&1; g_red 4
sed -i.bak 's/^FOREIGN$/other l1/' "$ST_WT/src/d.sh"; rm -f "$ST_WT/src/d.sh.bak"; g_green 4
"$TEMPER" task gate 4 >/dev/null 2>&1
st_edit src/a.sh; g_green 1; "$TEMPER" task gate 1 >/dev/null 2>&1
assert_eq "G2: the running sibling's working file is intact after the parked FAIL" "work src/b.sh|running" \
  "$(cat "$ST_WT/src/b.sh" 2>/dev/null || echo MISSING)|$(st_field 2 status)"

# G3: the undo of a large foreign commit stays far below the lock wait (10 s)
g_bulk() { # g_bulk <count>: Task 4 passes, then the agent commits <count> files, then Task 1's gate runs; sets G_SECS
  g_setup
  "$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
  gg_pass 4 src/d.sh
  python3 -c "
import os, sys
os.makedirs(sys.argv[1] + '/bulk')
for i in range(int(sys.argv[2])):
    open('%s/bulk/file-%05d.txt' % (sys.argv[1], i), 'w').write('x%d\n' % i)" "$ST_WT" "$1"
  g_commit bulk
  st_edit src/a.sh; g_green 1
  local t0 t1; t0="$(g_now)"; F_OUT="$("$TEMPER" task gate 1 2>&1)"; F_RC=$?; t1="$(g_now)"
  G_SECS="$(python3 -c "import sys; print(int(float(sys.argv[2]) - float(sys.argv[1])))" "$t0" "$t1")"
}
for N in 1000 5000; do
  g_bulk "$N"; [[ -z "${G_VERBOSE:-}" ]] || echo "G3: $N paths gate ${G_SECS}s"
  assert_eq "G3: $N foreign paths: the gate took under 8 s" "yes" "$([[ "$G_SECS" -lt 8 ]] && echo yes || echo "no (${G_SECS}s)")"
  assert_eq "G3: $N foreign paths: off the branch and off the working tree, no park" "0|no|1|" \
    "$(git -C "$ST_WT" ls-tree -r --name-only HEAD | grep -c '^bulk/')|$([[ -e $ST_WT/bulk ]] && echo yes || echo no)|$(printf '%s' "$F_OUT" | grep -c '^NEXT: retry Task 1')|$(gg_g G1 parked_reason)"
done

# G4: non-UTF-8 names, a file turned into a directory
g_setup
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
gg_pass 4 src/d.sh
python3 -c "
import os, sys
open(os.fsencode(sys.argv[1]) + b'/odd\xff\xfe.txt', 'w').write('x')" "$ST_WT"
g_commit .
st_edit src/a.sh; g_green 1; out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "G4: a non-UTF-8 file name is off the branch and off the working tree, no park" "1|0|0|" \
  "$rc|$(git -C "$ST_WT" ls-tree -r -z HEAD | tr '\0' '\n' | grep -c 'odd')|$(ls -A "$ST_WT" | grep -c odd)|$(gg_g G1 parked_reason)"
g_setup
echo "was a file" > "$ST_WT/thing"; git -C "$ST_WT" add thing; git -C "$ST_WT" commit -q -m "thing" 2>/dev/null
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
gg_pass 4 src/d.sh
git -C "$ST_WT" rm -q thing; mkdir "$ST_WT/thing"; echo inner > "$ST_WT/thing/inner"; g_commit thing
st_edit src/a.sh; g_green 1; out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "G4: a file turned into a directory comes back as the file, no park" "1|blob|was a file|" \
  "$rc|$(git -C "$ST_WT" cat-file -t HEAD:thing 2>/dev/null)|$(cat "$ST_WT/thing" 2>/dev/null)|$(gg_g G1 parked_reason)"
assert_eq "G4: the directory's file is off the branch" "0" "$(git -C "$ST_WT" ls-tree -r --name-only HEAD | grep -c '^thing/')"

# index.lock contention: a lock held for 1.5 s while the gate undoes the commit is waited out, not parked
g_setup; LOCKF="$(git -C "$ST_WT" rev-parse --absolute-git-dir)/index.lock"
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
gg_pass 4 src/d.sh
echo stray > "$ST_WT/stray.txt"; g_commit stray.txt
st_edit src/a.sh; g_green 1
: > "$LOCKF"; ( sleep 1.5; rm -f "$LOCKF" ) &
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?; wait
assert_eq "lock: a briefly held index.lock does not park the group; the foreign commit is off" "1||0|1" \
  "$rc|$(gg_g G1 parked_reason)|$(git -C "$ST_WT" ls-tree -r --name-only HEAD | grep -c stray)|$(printf '%s' "$out" | grep -c '^NEXT: retry Task 1')"
g_setup
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
echo stray > "$ST_WT/stray.txt"; g_commit stray.txt
st_edit src/a.sh; g_green 1
: > "$LOCKF"; ( sleep 1.5; rm -f "$LOCKF" ) &
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?; wait
assert_eq "lock: the plain reset path waits out the lock too" "1||no" "$rc|$(gg_g G1 parked_reason)|$([[ -e $ST_WT/stray.txt ]] && echo yes || echo no)"

# G5: the lock comment and CHANGELOG say what the break guarantees; the check and the move happen in one process
assert_eq "G5: no unconditional 'no second holder' claim in scripts/temper or CHANGELOG" "0" \
  "$(cat "$TEMPER" "$REPO_ROOT/CHANGELOG.md" | grep -c 'no second holder')"
assert_eq "G5: the stale break does the age check and the rename in one process" "0|1" \
  "$(grep -c 'mv "\$_LOCK_DIR" "\$dead"' "$TEMPER")|$(grep -c 'os.rename' "$TEMPER")"
assert_eq "G5: the CHANGELOG says the window is narrowed, not closed" "1" "$(grep -c 'window.*narrowed' "$REPO_ROOT/CHANGELOG.md")"
# G6: the documented exception
assert_eq "G6: the CHANGELOG documents that an agent edit to a running sibling's file lands with its commit" "1" \
  "$(grep -c "lands with that sibling's commit" "$REPO_ROOT/CHANGELOG.md")"

# --- Grouped Build (9.7.0), second focused review of the undo: lock budget, plumbing config, merges, parked
# shas, crlf and symlinks, cost [H1-H7] ---
# H1: a stale index.lock costs one shared retry budget (a few seconds), not seconds per path; the park names the lock
g_setup; LOCKF="$(git -C "$ST_WT" rev-parse --absolute-git-dir)/index.lock"
for i in 1 2 3 4 5; do echo "base $i" > "$ST_WT/stray$i.txt"; done
git -C "$ST_WT" add stray1.txt stray2.txt stray3.txt stray4.txt stray5.txt; git -C "$ST_WT" commit -q -m "five tracked files" 2>/dev/null
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
for i in 1 2 3 4 5; do echo "stray $i" > "$ST_WT/stray$i.txt"; done
g_commit stray1.txt stray2.txt stray3.txt stray4.txt stray5.txt
st_edit src/a.sh; g_green 1
: > "$LOCKF"; t0="$(g_now)"; out="$("$TEMPER" task gate 1 2>&1)"; rc=$?; t1="$(g_now)"; rm -f "$LOCKF"
H_SECS="$(python3 -c "import sys; print(int(float(sys.argv[2]) - float(sys.argv[1])))" "$t0" "$t1")"
assert_eq "H1: a stale index.lock with five foreign paths: the gate took under 14 s" "yes" "$([[ "$H_SECS" -lt 14 ]] && echo yes || echo "no (${H_SECS}s)")"
assert_eq "H1: the group parks and the reason names index.lock" "1|parked|1" \
  "$rc|$(gg_g G1 status)|$(gg_g G1 parked_reason | grep -c 'index.lock')"
g_setup; LOCKF="$(git -C "$ST_WT" rev-parse --absolute-git-dir)/index.lock"   # the lock released in time: a normal retry
for i in 1 2 3 4 5; do echo "base $i" > "$ST_WT/stray$i.txt"; done
git -C "$ST_WT" add stray1.txt stray2.txt stray3.txt stray4.txt stray5.txt; git -C "$ST_WT" commit -q -m "five tracked files" 2>/dev/null
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
for i in 1 2 3 4 5; do echo "stray $i" > "$ST_WT/stray$i.txt"; done
g_commit stray1.txt stray2.txt stray3.txt stray4.txt stray5.txt
st_edit src/a.sh; g_green 1
: > "$LOCKF"; ( sleep 1.5; rm -f "$LOCKF" ) &
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?; wait
assert_eq "H1: a lock released within the budget is waited out, no park" "1||0" \
  "$rc|$(gg_g G1 parked_reason)|$(git -C "$ST_WT" show HEAD:stray1.txt | grep -c stray)"

# H2: colour and a zero diff context in the user's git config do not turn a clean undo into a conflict
for CFG in "color.ui always" "color.diff always" "diff.context 0" "diff.mnemonicPrefix true" "diff.noprefix true"; do
  g_setup; git -C "$ST_WT" config ${CFG%% *} "${CFG#* }"
  "$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
  sed -i.bak 's/^l1$/FOREIGN/' "$ST_WT/src/b.sh"; rm -f "$ST_WT/src/b.sh.bak"; g_commit src/b.sh
  "$TEMPER" task start 2 >/dev/null 2>&1; g_red 2
  printf 'sibling line\n' >> "$ST_WT/src/b.sh"; g_green 2; "$TEMPER" task gate 2 >/dev/null 2>&1
  st_edit src/a.sh; g_green 1; out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
  assert_eq "H2: with $CFG the undo retries (not parked) and the foreign line is off" "1|failed||l1,l2,l3,l4,l5,l6,l7,l8,sibling line" \
    "$rc|$(st_field 1 status)|$(gg_g G1 parked_reason)|$(g_lines src/b.sh)"
done

# H3: an agent merge commit and a foreign add that a later commit deleted are taken off without a false conflict
g_setup
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
gg_pass 4 src/d.sh
HB="$(git -C "$ST_WT" symbolic-ref --short HEAD)"
git -C "$ST_WT" checkout -q -b side
sed -i.bak 's/^l8$/SIDE/' "$ST_WT/src/b.sh"; rm -f "$ST_WT/src/b.sh.bak"; echo side > "$ST_WT/side.txt"; g_commit src/b.sh side.txt
git -C "$ST_WT" checkout -q "$HB"
echo main > "$ST_WT/main.txt"; g_commit main.txt
git -C "$ST_WT" merge -q --no-ff side -m "merge side" >/dev/null 2>&1
st_edit src/a.sh; g_green 1; out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "H3: an agent merge commit is undone: retry, not parked" "1|failed||1" \
  "$rc|$(st_field 1 status)|$(gg_g G1 parked_reason)|$(printf '%s' "$out" | grep -c '^NEXT: retry Task 1')"
assert_eq "H3: the merge's content is off the branch" "l8|0" "$(git -C "$ST_WT" show HEAD:src/b.sh | tail -1)|$(git -C "$ST_WT" ls-tree -r --name-only HEAD | grep -c 'main.txt\|side.txt')"
g_setup
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
gg_pass 4 src/d.sh
echo temp > "$ST_WT/temp.txt"; g_commit temp.txt
git -C "$ST_WT" rm -q temp.txt; git -C "$ST_WT" commit -q -m "agent removes it" 2>/dev/null
st_edit src/a.sh; g_green 1; out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "H3: a foreign add that a later commit deleted: retry, not parked" "1|failed||0" \
  "$rc|$(st_field 1 status)|$(gg_g G1 parked_reason)|$(git -C "$ST_WT" ls-tree -r --name-only HEAD | grep -c temp.txt)"
# the printed hint for a merge works as written: -m 1 on the merge, no separate revert of the side commit
g_setup
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
HB="$(git -C "$ST_WT" symbolic-ref --short HEAD)"
git -C "$ST_WT" checkout -q -b side
sed -i.bak 's/^l8$/SIDE/' "$ST_WT/src/b.sh"; rm -f "$ST_WT/src/b.sh.bak"; g_commit src/b.sh
SIDE_SHA="$(git -C "$ST_WT" rev-parse --short=7 HEAD)"
git -C "$ST_WT" checkout -q "$HB"
echo main > "$ST_WT/main.txt"; g_commit main.txt
git -C "$ST_WT" merge -q --no-ff side -m "merge side" >/dev/null 2>&1
MERGE_SHA="$(git -C "$ST_WT" rev-parse --short=7 HEAD)"
"$TEMPER" task start 2 >/dev/null 2>&1; g_red 2
sed -i.bak 's/^SIDE$/sibling l8/' "$ST_WT/src/b.sh"; rm -f "$ST_WT/src/b.sh.bak"; g_green 2; "$TEMPER" task gate 2 >/dev/null 2>&1
st_edit src/a.sh; g_green 1; out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
HINT="$(gg_g G1 parked_reason)"
assert_eq "H3: the park hint reverts the merge with -m 1 and does not name the absorbed side commit" "1|1|0" \
  "$(printf '%s' "$HINT" | grep -c 'revert --no-edit -m 1 '"$MERGE_SHA")|$(gg_g G1 status | grep -c parked)|$(printf '%s' "$HINT" | grep -c 'revert --no-edit.* '"$SIDE_SHA")"
# and the hint, run as written (when the sibling is done), is a command git accepts
HCMD="$(printf '%s' "$HINT" | grep -o 'git -C [^ ]* revert --no-edit -m 1 '"$MERGE_SHA" | head -1)"
assert_eq "H3: the hinted merge revert command is accepted by git (the conflict is the sibling's own line)" "1" \
  "$([[ -n "$HCMD" ]] && { $HCMD >/dev/null 2>&1; hrc=$?; git -C "$ST_WT" revert --abort >/dev/null 2>&1; [[ $hrc -le 1 ]] && echo 1 || echo 0; } || echo 0)"

# H4: after a conflict park, a running sibling holding the parked foreign sha is not blamed for it, the reason is kept
g_setup
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
"$TEMPER" task start 2 >/dev/null 2>&1; g_red 2
sed -i.bak 's/^l1$/FOREIGN/' "$ST_WT/src/d.sh"; rm -f "$ST_WT/src/d.sh.bak"; echo extra > "$ST_WT/parked-extra.txt"; g_commit src/d.sh parked-extra.txt
"$TEMPER" task start 4 >/dev/null 2>&1; g_red 4
sed -i.bak 's/^FOREIGN$/other l1/' "$ST_WT/src/d.sh"; rm -f "$ST_WT/src/d.sh.bak"; g_green 4; "$TEMPER" task gate 4 >/dev/null 2>&1
st_edit src/a.sh; g_green 1; "$TEMPER" task gate 1 >/dev/null 2>&1
REASON1="$(gg_g G1 parked_reason)"
st_edit src/b.sh; g_green 2; out="$("$TEMPER" task gate 2 2>&1)"; rc=$?
assert_eq "H4: the running sibling passes (the parked foreign commit is not blamed on it)" "0|passed" "$rc|$(st_field 2 status)"
assert_eq "H4: the group stays parked with the conflict reason" "parked|1|1" \
  "$(gg_g G1 status)|$([[ "$(gg_g G1 parked_reason)" == "$REASON1" ]] && echo 1 || echo 0)|$(gg_g G1 parked_reason | grep -c conflict)"
# the parked commit is still on the branch, so a reopen is refused (J3); once it is undone as the hint says, it is allowed
out="$("$TEMPER" group reopen G1 --task 1 2>&1)"; rc=$?
assert_eq "H4: a reopen is refused while the parked foreign commit is on the branch, and nothing changes" "1|parked|1" \
  "$rc|$(gg_g G1 status)|$(python3 -c "import json; print(len(json.load(open('.temper/groups.json'))['groups']['G1'].get('parked_foreign') or []))")"

# H5: a CRLF working file (eol=crlf) of a finished sibling follows the branch: the foreign line is not left behind
g_setup
printf 'src/*.sh text eol=crlf\n' > "$ST_WT/.gitattributes"; git -C "$ST_WT" add .gitattributes; git -C "$ST_WT" commit -q -m attrs 2>/dev/null
rm -f "$ST_WT/src/b.sh" "$ST_WT/src/d.sh"; git -C "$ST_WT" checkout -q -- src/b.sh src/d.sh
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
python3 -c "
import sys
open(sys.argv[1] + '/src/b.sh', 'wb').write(b'FOREIGN\r\n' + b''.join(b'l%d\r\n' % i for i in range(2, 9)))" "$ST_WT"
g_commit src/b.sh
"$TEMPER" task start 2 >/dev/null 2>&1; g_red 2
printf 'sibling line\r\n' >> "$ST_WT/src/b.sh"; g_green 2; "$TEMPER" task gate 2 >/dev/null 2>&1
st_edit src/a.sh; g_green 1; out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "H5: the branch is back at the original line, the CRLF working file of the finished sibling follows it" "1||0|l1" \
  "$rc|$(gg_g G1 parked_reason)|$(grep -c FOREIGN "$ST_WT/src/b.sh")|$(tr -d '\r' < "$ST_WT/src/b.sh" | head -1)"
assert_eq "H5: the working file stays clean in git status" "" "$(git -C "$ST_WT" status --porcelain -- src/b.sh)"

# H6: a symlink a foreign commit put in place of a directory is never written through
OUTD="$(mktemp -d)"; : "${OUTD:?}"
g_setup
mkdir -p "$ST_WT/sub"; echo inside > "$ST_WT/sub/x.txt"; git -C "$ST_WT" add sub; git -C "$ST_WT" commit -q -m "sub dir" 2>/dev/null
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
gg_pass 4 src/d.sh
git -C "$ST_WT" rm -q -r sub; rm -rf "${ST_WT:?}/sub"; ln -s "$OUTD" "$ST_WT/sub"; git -C "$ST_WT" add sub; git -C "$ST_WT" commit -q -m "sub is a link" 2>/dev/null
st_edit src/a.sh; g_green 1; out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "H6: nothing was written outside the worktree" "0" "$(ls -A "$OUTD" | wc -l | tr -d ' ')"
# J4: the link is not part of the group branch and the FAIL restore put the directory back, so there is nothing to park on
assert_eq "H6: the branch has the directory back, the restore replaced the link, attempt 1 retries (no park)" "blob|dir|1|" \
  "$(git -C "$ST_WT" cat-file -t HEAD:sub/x.txt 2>/dev/null)|$([[ -d $ST_WT/sub && ! -L $ST_WT/sub ]] && echo dir || echo other)|$(printf '%s' "$out" | grep -c '^NEXT: retry Task 1')|$(gg_g G1 parked_reason)"
rm -rf "${OUTD:?}"

# H7: the undo works on the paths the foreign commits touched, not the whole tree once per commit
g_h7() { # g_h7 <commits>: a 50000-file tree, <commits> agent commits touching one file each; sets H_SECS
  g_setup
  python3 -c "
import os, sys
os.makedirs(sys.argv[1] + '/big')
for i in range(50000):
    open('%s/big/f%05d.txt' % (sys.argv[1], i), 'w').write('x%d\n' % i)" "$ST_WT"
  git -C "$ST_WT" add big; git -C "$ST_WT" commit -q -m "big tree" 2>/dev/null
  "$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
  gg_pass 4 src/d.sh
  local i
  for ((i = 0; i < $1; i++)); do printf 'foreign %d\n' "$i" > "$ST_WT/big/f$(printf %05d "$i").txt"; g_commit "big/f$(printf %05d "$i").txt"; done
  st_edit src/a.sh; g_green 1
  local t0 t1; t0="$(g_now)"; F_OUT="$("$TEMPER" task gate 1 2>&1)"; F_RC=$?; t1="$(g_now)"
  H_SECS="$(python3 -c "import sys; print('%.2f' % (float(sys.argv[2]) - float(sys.argv[1])))" "$t0" "$t1")"
}
g_h7 1; H7_ONE="$H_SECS"; assert_eq "H7: one foreign commit in a 50000-file tree is undone" "1|0" "$F_RC|$(git -C "$ST_WT" show HEAD:big/f00000.txt | grep -c foreign)"
g_h7 20; H7_NINE="$H_SECS"; assert_eq "H7: twenty foreign commits are undone" "1|0" "$F_RC|$(git -C "$ST_WT" show HEAD:big/f00019.txt | grep -c foreign)"
[[ -z "${G_VERBOSE:-}" ]] || echo "H7: 1 commit ${H7_ONE}s, 20 commits ${H7_NINE}s"
assert_eq "H7: twenty commits cost under one commit plus 2.5 seconds (slack for a loaded machine)" "yes" \
  "$(python3 -c "import sys; print('yes' if float(sys.argv[2]) < float(sys.argv[1]) + 2.5 else 'no (%s vs %s)' % (sys.argv[2], sys.argv[1]))" "$H7_ONE" "$H7_NINE")"

# --- Grouped Build (9.7.0), third focused review: parked shas per group and by exact content, parks accumulate,
# hints that work as printed, a merge's line parent [J1-J6] ---
# Invariants: (a) a FAIL never changes a running same-group sibling's working tree or the CLI's commits; (b) foreign content
# never stays on a group branch at integrate and success is not recorded while it stays, also with two parks in one group
# and a reopen in another group; (c) attempts 1-2 retry/escalate, only a genuine undo failure parks, and every printed hint
# works exactly as written in the state the CLI leaves.
j_conflict() { # g_setup, Tasks 1 and 2 running; the agent commits C1 (src/d.sh line 1 and f1.txt); Task 4 rewrites that line and
               # passes; Task 1 FAILs and the group parks on C1 (J_C1)
  g_setup
  "$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
  "$TEMPER" task start 2 >/dev/null 2>&1; g_red 2
  sed -i.bak 's/^l1$/FOREIGN/' "$ST_WT/src/d.sh"; rm -f "$ST_WT/src/d.sh.bak"; echo one > "$ST_WT/f1.txt"; g_commit src/d.sh f1.txt
  J_C1="$(git -C "$ST_WT" rev-parse HEAD)"
  "$TEMPER" task start 4 >/dev/null 2>&1; g_red 4
  sed -i.bak 's/^FOREIGN$/other l1/' "$ST_WT/src/d.sh"; rm -f "$ST_WT/src/d.sh.bak"; g_green 4; "$TEMPER" task gate 4 >/dev/null 2>&1
  st_edit src/a.sh; g_green 1; J_OUT="$("$TEMPER" task gate 1 2>&1)"
}
j_hints() { gg_g G1 parked_reason | grep -o 'git -C [^ ]* revert --no-edit [0-9a-f]*'; }   # the revert commands the park reason prints
j_listed() { python3 -c "import json; print(','.join(json.load(open('.temper/groups.json'))['groups'][__import__('sys').argv[1]].get('parked_foreign') or []))" "$1"; }
j_resolve() { # j_resolve <hint command>: run it as written; a conflict (exit 1) is resolved by keeping the branch's side
  local hrc; J_HOUT="$($1 2>&1)"; hrc=$?
  if [[ $hrc -eq 1 ]]; then
    git -C "$ST_WT" checkout --ours -- . >/dev/null 2>&1; git -C "$ST_WT" add -A >/dev/null 2>&1
    GIT_EDITOR=true git -C "$ST_WT" revert --continue >/dev/null 2>&1
  fi
  J_HRC=$hrc
}

# J1: the sibling's gate excuses a path of the parked commit only while the file still holds that commit's content
j_conflict
assert_eq "J1: the conflict parks the group on C1, recorded for G1 only" "parked|$J_C1" "$(gg_g G1 status)|$(j_listed G1)"
J_REASON="$(gg_g G1 parked_reason)"
echo mine >> "$ST_WT/f1.txt"   # Task 2's own, undeclared edit of a path the parked commit touched
st_edit src/b.sh; g_green 2; out="$("$TEMPER" task gate 2 2>&1)"; rc=$?
assert_eq "J1: the running sibling's own edit of f1.txt is an undeclared change (FAIL, retry)" "1|1|1" \
  "$rc|$(printf '%s' "$out" | grep -c 'undeclared change: f1.txt')|$(printf '%s' "$out" | grep -c '^NEXT: retry Task 2')"
assert_eq "J1: the group keeps its park reason; the sibling's file is back at the branch's content, the tree is clean at f1.txt" "1|one|" \
  "$([[ "$(gg_g G1 parked_reason)" == "$J_REASON" ]] && echo 1 || echo 0)|$(cat "$ST_WT/f1.txt")|$(git -C "$ST_WT" status --porcelain -- f1.txt)"
# J5: the hint, run as written in the state the CLI left, is accepted by git (the only conflict is the sibling's own line)
HCMD="$(j_hints | head -1)"; j_resolve "$HCMD"
assert_eq "J5: the printed revert runs (exit 0 or a plain conflict), no 'local changes' refusal" "1|0" \
  "$([[ -n "$HCMD" && $J_HRC -le 1 ]] && echo 1 || echo 0)|$(printf '%s' "$J_HOUT" | grep -c 'local changes')"
assert_eq "J5: after the hint the foreign file is off the branch" "0" "$(git -C "$ST_WT" ls-tree -r --name-only HEAD | grep -c '^f1.txt')"
out="$("$TEMPER" group reopen G1 --task 1 2>&1)"; rc=$?
assert_eq "J5: the reopen the hint names is accepted and clears this group's parked shas" "0|running|" "$rc|$(gg_g G1 status)|$(j_listed G1)"

# J2: a reopen in another group leaves this group's parked shas alone; its running sibling is still not blamed
j_conflict
G2WT=".claude/worktrees/temper-demo-G2"
"$TEMPER" task start 3 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 3 --phase red >/dev/null 2>&1
mkdir -p "$G2WT/src"; echo c > "$G2WT/src/c.sh"; ST_EXIT=0 "$TEMPER" task test 3 --phase green >/dev/null 2>&1; "$TEMPER" task gate 3 >/dev/null 2>&1
assert_exit "J2: Task 3 of G2 is reopened while G1 is parked" 0 "$TEMPER" group reopen G2 --task 3
assert_eq "J2: G1 still lists its parked sha and G2 holds its own reopen revert" "$J_C1|0|1" \
  "$(j_listed G1)|$(python3 -c "import json; print(len(json.load(open('.temper/groups.json')).get('reopen_reverts') or []))")|$(python3 -c "import json; print(len(json.load(open('.temper/groups.json'))['groups']['G2'].get('reopen_reverts') or []))")"
st_edit src/b.sh; g_green 2; out="$("$TEMPER" task gate 2 2>&1)"; rc=$?
assert_eq "J2: G1's running sibling still passes and keeps its work" "0|work src/b.sh" "$rc|$(git -C "$ST_WT" show HEAD:src/b.sh 2>/dev/null)"

# J3: a second park in a parked group is added to the first; both foreign commits are off before the group runs again
j_conflict
st_edit src/b.sh; g_green 2   # Task 2's agent commits f2.txt; a stale index.lock makes the undo park too
echo two > "$ST_WT/f2.txt"; g_commit f2.txt; J_C2="$(git -C "$ST_WT" rev-parse HEAD)"
J_LOCK="$(git -C "$ST_WT" rev-parse --absolute-git-dir)/index.lock"
: > "$J_LOCK"; out="$("$TEMPER" task gate 2 2>&1)"; rc=$?; rm -f "$J_LOCK"
assert_eq "J3: the second park keeps the first reason and adds its own, both with the exact revert" "1|1|1|1|1" \
  "$(gg_g G1 status | grep -c parked)|$(gg_g G1 parked_reason | grep -c "${J_C1:0:7}")|$(gg_g G1 parked_reason | grep -c "${J_C2:0:7}")|$(gg_g G1 parked_reason | grep -c 'index.lock')|$([[ "$(j_hints | wc -l | tr -d ' ')" == 2 ]] && echo 1 || echo 0)"
assert_eq "J3: both shas are listed for G1" "$J_C1,$J_C2" "$(j_listed G1)"
out="$("$TEMPER" integrate 2>&1)"; rc=$?
assert_eq "J3: integrate does not succeed while the group is parked on foreign commits" "1|FAIL" "$rc|$(gi_int verdict)"
out="$("$TEMPER" group reopen G1 --task 1 2>&1)"; rc=$?
assert_eq "J3: the reopen is refused while either commit is on the branch, naming both" "1|1|1|parked" \
  "$rc|$(printf '%s' "$out" | grep -c "${J_C1:0:7}")|$(printf '%s' "$out" | grep -c "${J_C2:0:7}")|$(gg_g G1 status)"
while IFS= read -r HCMD; do j_resolve "$HCMD"; done < <(j_hints)
assert_eq "J3: both hints, run as written, take f1.txt and f2.txt off the branch" "0" "$(git -C "$ST_WT" ls-tree -r --name-only HEAD | grep -c '^f[12].txt')"
out="$("$TEMPER" group reopen G1 --task 1 2>&1)"; rc=$?
assert_eq "J3: the reopen then runs and clears the group's list" "0|running|" "$rc|$(gg_g G1 status)|$(j_listed G1)"

# J5 (lock park): the park leaves the working tree at the branch's content, and the printed hint works as written
g_setup; J_LOCK="$(git -C "$ST_WT" rev-parse --absolute-git-dir)/index.lock"
echo "base 1" > "$ST_WT/stray1.txt"; git -C "$ST_WT" add stray1.txt; git -C "$ST_WT" commit -q -m "tracked stray" 2>/dev/null
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
gg_pass 4 src/d.sh
echo "stray 1" > "$ST_WT/stray1.txt"; g_commit stray1.txt
st_edit src/a.sh; g_green 1
: > "$J_LOCK"; out="$("$TEMPER" task gate 1 2>&1)"; rc=$?; rm -f "$J_LOCK"
assert_eq "J5: the lock parks the group; the tracked file is at the branch's content, clean in git status" "parked|stray 1|" \
  "$(gg_g G1 status)|$(cat "$ST_WT/stray1.txt")|$(git -C "$ST_WT" status --porcelain -- stray1.txt)"
HCMD="$(j_hints | head -1)"; j_resolve "$HCMD"
assert_eq "J5: the lock hint's revert, run as written, takes the commit off (exit 0)" "1|0|base 1" \
  "$([[ -n "$HCMD" ]] && echo 1 || echo 0)|$J_HRC|$(cat "$ST_WT/stray1.txt")"
assert_eq "J5: the park text no longer claims the working tree was not changed" "0" "$(gg_g G1 parked_reason | grep -c 'working tree of .* was not changed')"

# J6: a merge's line parent is the one that carries the group's CLI commits, not always the first parent
g_setup
"$TEMPER" task start 1 >/dev/null 2>&1; g_red 1
J_START="$(git -C "$ST_WT" rev-parse HEAD)"; J_BR="$(git -C "$ST_WT" symbolic-ref --short HEAD)"
gg_pass 4 src/d.sh
git -C "$ST_WT" checkout -q -b side "$J_START"
echo side > "$ST_WT/side.txt"; g_commit side.txt
git -C "$ST_WT" merge -q --no-ff "$J_BR" -m "merge group into side" >/dev/null 2>&1
git -C "$ST_WT" checkout -q "$J_BR"; git -C "$ST_WT" merge -q --ff-only side >/dev/null 2>&1
st_edit src/a.sh; g_green 1; out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "J6: the agent's merge is undone (retry, no park)" "1|failed||1" \
  "$rc|$(st_field 1 status)|$(gg_g G1 parked_reason)|$(printf '%s' "$out" | grep -c '^NEXT: retry Task 1')"
assert_eq "J6: Task 4's CLI commit content stays, the agent's side.txt is gone, Task 4 stays passed" "work src/d.sh|0|passed" \
  "$(git -C "$ST_WT" show HEAD:src/d.sh 2>/dev/null)|$(git -C "$ST_WT" ls-tree -r --name-only HEAD | grep -c side.txt)|$(st_field 4 status)"
setup
