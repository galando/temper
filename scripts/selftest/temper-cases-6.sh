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
setup
