# --- Grouped Build (9.7.0), intent D-08: a commit the CLI did not record FAILs the task and parks its group; nothing is undone ---
# Invariants: (a) a foreign commit never causes a write to the branch or the working tree (HEAD, refs, index and every file are
# byte-identical before and after the gate); (b) a parked group refuses task gate and task test of its running siblings without a
# verdict, attempt, restore or ledger row; (c) a reopen is accepted only when no parked sha is an ancestor of the branch HEAD any
# more, or when the human accepts the sha with --accept-foreign and a reason (recorded like an override, shown by temper report);
# (d) the group gate checks that every passed task's commit is still on the branch; (e) a FAIL without a foreign commit still
# restores the task's files and retries or escalates (D-03).
d_setup() { f_setup; }
d_red() { ST_EXIT=1 "$TEMPER" task test "$1" --phase red >/dev/null 2>&1; }
d_green() { ST_EXIT=0 "$TEMPER" task test "$1" --phase green >/dev/null 2>&1; }
d_commit() { git -C "$ST_WT" add -A -- "$@" 2>/dev/null; git -C "$ST_WT" commit -q -m "agent commit" 2>/dev/null; }
d_state() { # HEAD, every ref, the index and the hash of every file of the group worktree, as one string
  { git -C "$ST_WT" rev-parse HEAD
    git -C "$ST_WT" show-ref
    git -C "$ST_WT" status --porcelain=v1 -uall
    git -C "$ST_WT" ls-files -s
    ( cd "$ST_WT" && find . -name .git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum )
  } 2>&1 | sha256sum | cut -d' ' -f1
}
d_pfield() { python3 -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1'].get('$1', ''))"; }
d_pf_count() { python3 -c "import json; print(len(json.load(open('.temper/groups.json'))['groups']['G1'].get('parked_foreign') or []))"; }
d_rows() { python3 -c "import json; print(len(json.load(open('.temper/evidence/build.json'))))"; }
d_attempts() { python3 -c "import json; print(len(json.load(open('.temper/groups.json'))['tasks']['$1'].get('attempts') or []))"; }
# d_park: Task 2 running with an uncommitted edit; Task 1 commits a declared and a stray file and leaves more work dirty; its gate parks G1
d_park() {
  d_setup
  "$TEMPER" task start 2 >/dev/null 2>&1; d_red 2; st_edit src/b.sh
  "$TEMPER" task start 1 >/dev/null 2>&1; d_red 1
  st_edit src/a.sh; st_edit stray.txt; d_commit src/a.sh stray.txt
  FSHA="$(git -C "$ST_WT" rev-parse HEAD)"
  echo "more work" >> "$ST_WT/src/a.sh"; echo junk > "$ST_WT/untracked.txt"
  d_green 1
  D_BEFORE="$(d_state)"
  D_OUT="$("$TEMPER" task gate 1 2>&1)"; D_RC=$?
  D_AFTER="$(d_state)"
}

# D-08 task gate: the foreign commit FAILs the task and parks the group at once, and changes nothing on the branch or the tree
d_park
assert_eq "D-08: a foreign commit FAILs the task gate (exit 1) and the task is failed" "1|failed" "$D_RC|$(st_field 1 status)"
assert_eq "D-08: the reason names the foreign sha and the files it changed" "1|1|1" \
  "$(printf '%s' "$D_OUT" | grep -c "^FAIL:.*commit not made by the CLI: ${FSHA:0:7}")|$(printf '%s' "$D_OUT" | grep -c 'src/a.sh')|$(printf '%s' "$D_OUT" | grep -c 'stray.txt')"
assert_eq "D-08: the group is parked at once on attempt 1, with the sha recorded for this group" "parked|1|$FSHA|1" \
  "$(d_pfield status)|$(d_attempts 1)|$(python3 -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1']['parked_foreign'][0])")|$(d_pf_count)"
assert_eq "D-08: the next step is to park the group (no retry)" "1|0" \
  "$(printf '%s' "$D_OUT" | grep -c '^NEXT: park group G1')|$(printf '%s' "$D_OUT" | grep -c '^NEXT: retry')"
assert_eq "D-08: the branch and the working tree are byte-identical before and after the gate" "$D_BEFORE" "$D_AFTER"
assert_eq "D-08: no declared file, stray file or dirty file was restored or removed" "yes|yes|yes|yes" \
  "$([[ -e $ST_WT/stray.txt ]] && echo yes || echo no)|$([[ -e $ST_WT/untracked.txt ]] && echo yes || echo no)|$([[ "$(tail -1 "$ST_WT/src/a.sh")" == "more work" ]] && echo yes || echo no)|$([[ "$(git -C "$ST_WT" rev-parse HEAD)" == "$FSHA" ]] && echo yes || echo no)"
assert_eq "D-08: the park message prints both ways out and never a reset --hard" "1|1|0" \
  "$(printf '%s' "$D_OUT" | grep -c 'rebase --onto')|$(printf '%s' "$D_OUT" | grep -c -- '--accept-foreign')|$(printf '%s' "$D_OUT" | grep -c 'reset --hard')"

# a parked group refuses its running sibling's gate and test: no verdict, attempt, restore or ledger row, its work stays
S_BEFORE="$(d_state)"; ROWS="$(d_rows)"; SIB="$(st_rows 2)"
d_green 2
out="$("$TEMPER" task gate 2 2>&1)"; rc=$?
assert_eq "D-08: the sibling's task gate is refused with a message naming the park" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'parked')"
ST_EXIT=0 "$TEMPER" task test 2 --phase green >/dev/null 2>&1; rc=$?
assert_eq "D-08: the sibling's task test is refused too" "1" "$rc"
assert_eq "D-08: the refusals recorded no verdict, attempt or ledger row, and the sibling is still running" "running|0|$ROWS|$SIB" \
  "$(st_field 2 status)|$(d_attempts 2)|$(d_rows)|$(st_rows 2)"
assert_eq "D-08: the sibling's working files and the branch are untouched by the refusals" "$S_BEFORE" "$(d_state)"
assert_eq "D-08: the sibling's own file is still its uncommitted work" "work src/b.sh" "$(cat "$ST_WT/src/b.sh")"
# a task of another group is not affected
git -C .claude/worktrees/temper-demo-G2 commit -q --allow-empty -m "g2 base" 2>/dev/null
assert_exit "D-08: a task in another group still starts" 0 "$TEMPER" task start 3

# reopen is refused while the parked sha is an ancestor of the branch HEAD
S_BEFORE="$(d_state)"
out="$("$TEMPER" group reopen G1 --task 1 2>&1)"; rc=$?
assert_eq "D-08: reopen is refused while the foreign sha is on the branch, naming it and both ways out" "1|1|1|1" \
  "$rc|$(printf '%s' "$out" | grep -q "${FSHA:0:7}" && echo 1)|$(printf '%s' "$out" | grep -c -- '--accept-foreign')|$(printf '%s' "$out" | grep -c 'rebase --onto')"
assert_eq "D-08: the refused reopen changed nothing (group still parked, task still failed, branch untouched)" "parked|failed|$S_BEFORE" \
  "$(d_pfield status)|$(st_field 1 status)|$(d_state)"
out="$("$TEMPER" group reopen G1 --task 1 --accept-foreign "${FSHA:0:7}" 2>&1)"; rc=$?
assert_eq "D-08: --accept-foreign without --reason is refused" "1" "$rc"
out="$("$TEMPER" group reopen G1 --task 1 --accept-foreign deadbee --reason "nope" 2>&1)"; rc=$?
assert_eq "D-08: --accept-foreign of a sha the group is not parked on is refused" "1|parked" "$rc|$(d_pfield status)"

# the human removes the commit as the park message printed (route a), with no task of the group running: the reopen is accepted
d_setup
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1
st_edit src/a.sh; st_edit stray.txt; d_commit src/a.sh stray.txt
FSHA="$(git -C "$ST_WT" rev-parse HEAD)"; PARENT="$(git -C "$ST_WT" rev-parse HEAD~1)"
d_green 1
out="$("$TEMPER" task gate 1 2>&1)"
CMD="$(printf '%s\n' "$out" | grep -o 'git -C [^ ]* rebase --onto [0-9a-f~^]* [0-9a-f]*' | head -1)"
assert_eq "D-08: the printed route (a) is a rebase --onto of the foreign sha's parent" "1" "$(printf '%s' "$CMD" | grep -c "rebase --onto ${FSHA:0:7}~1 ${FSHA:0:7}")"
bash -c "$CMD" >/dev/null 2>&1; rrc=$?
assert_eq "D-08: the printed command runs as written and takes the commit off the branch" "0|$PARENT" "$rrc|$(git -C "$ST_WT" rev-parse HEAD)"
assert_eq "D-08: the sha is no longer on the branch" "1" "$(git -C "$ST_WT" merge-base --is-ancestor "$FSHA" HEAD >/dev/null 2>&1; echo $?)"
assert_exit "D-08: the reopen is accepted once the parked sha is off the branch" 0 "$TEMPER" group reopen G1 --task 1
assert_eq "D-08: the reopen cleared the park and reset the task" "running|0|pending" "$(d_pfield status)|$(d_pf_count)|$(st_field 1 status)"
# the group runs again and the task passes
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1; st_edit src/a.sh; d_green 1
assert_exit "D-08: after the reopen the task runs again and passes" 0 "$TEMPER" task gate 1

# the human keeps the commit knowingly: --accept-foreign with a reason, recorded like an override and shown by temper report
d_park
out="$("$TEMPER" group reopen G1 --task 1 --accept-foreign "${FSHA:0:7}" --reason "reviewed the agent commit, it is fine" 2>&1)"; rc=$?
assert_eq "D-08: --accept-foreign with a reason reopens although the sha is on the branch" "0|running|0" "$rc|$(d_pfield status)|$(d_pf_count)"
assert_eq "D-08: the accepted sha is recorded in overrides.json with the reason" "1|1" \
  "$(grep -c "$FSHA" .temper/overrides.json)|$(grep -c 'reviewed the agent commit' .temper/overrides.json)"
rep="$("$TEMPER" report 2>&1)"
assert_eq "D-08: temper report shows the accepted agent commit" "1|1" \
  "$(printf '%s' "$rep" | grep -c "${FSHA:0:7}")|$(printf '%s' "$rep" | grep -c 'reviewed the agent commit')"
# the sibling that was running when the group parked is not blamed for the accepted commit as one the CLI did not make
d_green 2
out="$("$TEMPER" task gate 2 2>&1)"
assert_eq "D-08: an accepted sha counts as known, so the sibling is not told it holds a commit the CLI did not make" "0" \
  "$(printf '%s' "$out" | grep -c 'not made by the CLI')"

# an accepted sha only excuses itself: a later unknown commit still FAILs and parks again
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1; st_edit src/a.sh; st_edit stray2.txt; d_commit src/a.sh stray2.txt
d_green 1
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "D-08: a new foreign commit after an accepted one parks the group again" "1|parked|1" "$rc|$(d_pfield status)|$(d_pf_count)"

# D-08 group gate: a passed task's commit must still be on the group branch, and a parked group does not pass
gg_setup; gg_pass 1 src/a.sh; gg_pass 2 src/b.sh
T2="$(git -C "$ST_WT" rev-parse HEAD)"
assert_exit "D-08: with both commits on the branch the group gate passes" 0 "$TEMPER" group gate G1
gg_setup; gg_pass 1 src/a.sh; gg_pass 2 src/b.sh
T2="$(git -C "$ST_WT" rev-parse HEAD)"
git -C "$ST_WT" reset -q --hard HEAD~1 2>/dev/null
out="$("$TEMPER" group gate G1 2>&1)"; rc=$?
assert_eq "D-08: a passed task whose commit left the branch FAILs the group gate, naming the task and the sha" "1|1|1" \
  "$rc|$(printf '%s' "$out" | grep -c 'Task 2')|$(printf '%s' "$out" | grep -c "${T2:0:7}")"
gg_setup; gg_pass 1 src/a.sh; gg_pass 2 src/b.sh
python3 - <<'PY'
import json
d = json.load(open('.temper/groups.json'))
d['groups']['G1']['status'] = 'parked'
d['groups']['G1']['parked_reason'] = 'test'
json.dump(d, open('.temper/groups.json', 'w'))
PY
out="$("$TEMPER" group gate G1 2>&1)"; rc=$?
assert_eq "D-08: the group gate FAILs while the group is parked" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'parked')"

# a normal FAIL (no foreign commit) keeps today's behaviour: restore the declared and the named undeclared files, retry, escalate, park (D-03)
d_setup
"$TEMPER" task start 2 >/dev/null 2>&1; d_red 2; st_edit src/b.sh
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1; st_edit src/a.sh; st_edit stray.txt; d_green 1
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "D-08: a normal FAIL names the undeclared file and retries on the task model" "1|1|1" \
  "$rc|$(printf '%s' "$out" | grep -c 'undeclared change: stray.txt')|$(printf '%s' "$out" | grep -c '^NEXT: retry Task 1')"
assert_eq "D-08: a normal FAIL restores the task's own and the undeclared file, and not the running sibling's" "no|no|work src/b.sh|" \
  "$([[ -e $ST_WT/src/a.sh ]] && echo yes || echo no)|$([[ -e $ST_WT/stray.txt ]] && echo yes || echo no)|$(cat "$ST_WT/src/b.sh")|$(d_pfield status | sed 's/running//')"
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1; st_edit stray.txt; st_edit src/a.sh; d_green 1
out="$("$TEMPER" task gate 1 2>&1)"
assert_eq "D-08: attempt 2 escalates" "1" "$(printf '%s' "$out" | grep -c '^NEXT: escalate Task 1')"
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1; st_edit stray.txt; st_edit src/a.sh; d_green 1
out="$("$TEMPER" task gate 1 2>&1)"
assert_eq "D-08: attempt 3 parks the group (D-03) with no foreign sha recorded" "1|parked|0" \
  "$(printf '%s' "$out" | grep -c '^NEXT: park group G1')|$(d_pfield status)|$(d_pf_count)"
d_green 2; out="$("$TEMPER" task gate 2 2>&1)"; rc=$?
assert_eq "D-08: the retry chain's park refuses the running sibling too, with no verdict" "1|1|running" "$rc|$(printf '%s' "$out" | grep -c 'parked')|$(st_field 2 status)"
# a reopen of a group parked by the retry chain needs no acknowledgement
assert_exit "D-08: a group parked by the retry chain reopens without --accept-foreign" 0 "$TEMPER" group reopen G1 --task 1

# the undo machinery is gone from the CLI
assert_eq "D-08: no automatic-undo code is left in scripts/temper" "0" \
  "$(grep -c 'stillon\|reverthint\|TEMPER_UNDO_HEAL\|reverted_foreign\|merge_info\|temper-undo' "$TEMPER")"
setup
