# --- Grouped Build (9.7.0), intent D-08: a commit the CLI did not record FAILs the task and parks its group; nothing is undone ---
# One worktree per task: the agent's commit sits in that task's own worktree (T1W for Task 1, T2W for Task 2).
# Invariants: (a) a foreign commit never causes a write to the task's branch or worktree (HEAD, refs, index and every file are
# byte-identical before and after the gate), and the park keeps that worktree; (b) a parked group refuses task gate and task test
# of its running siblings without a verdict, attempt or ledger row, and a sibling keeps its own worktree and status; (c) a reopen is
# accepted only when no parked sha is an ancestor of the task branch's HEAD any more, or when the human accepts the sha with
# --accept-foreign and a reason (recorded like an override, shown by temper report); (d) the group gate checks that every passed
# task's commit is still on the group branch; (e) a FAIL without a foreign commit discards the attempt's worktree and retries or
# escalates (D-03).
T2W=".claude/worktrees/temper-demo-T2"
d_setup() { f_setup; }
d_red() { ST_EXIT=1 "$TEMPER" task test "$1" --phase red >/dev/null 2>&1; }
d_green() { ST_EXIT=0 "$TEMPER" task test "$1" --phase green >/dev/null 2>&1; }
d_commit() { local w; w="$(st_twt "$1")"; git -C "$w" add -A -- "$@" 2>/dev/null; git -C "$w" commit -q -m "agent commit" 2>/dev/null; }
d_state() { # d_state [worktree, default Task 1's]: HEAD, every ref, the index and the hash of every file there, as one string
  local w="${1:-$T1W}"
  { git -C "$w" rev-parse HEAD
    git -C "$w" show-ref
    git -C "$w" status --porcelain=v1 -uall
    git -C "$w" ls-files -s
    ( cd "$w" && find . -name .git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum )
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
  FSHA="$(git -C "$T1W" rev-parse HEAD)"
  echo "more work" >> "$T1W/src/a.sh"; echo junk > "$T1W/untracked.txt"
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
  "$([[ -e $T1W/stray.txt ]] && echo yes || echo no)|$([[ -e $T1W/untracked.txt ]] && echo yes || echo no)|$([[ "$(tail -1 "$T1W/src/a.sh")" == "more work" ]] && echo yes || echo no)|$([[ "$(git -C "$T1W" rev-parse HEAD)" == "$FSHA" ]] && echo yes || echo no)"
assert_eq "D-08: the park message prints both ways out and never a reset --hard" "1|1|0" \
  "$(printf '%s' "$D_OUT" | grep -c 'rebase --autostash --onto')|$(printf '%s' "$D_OUT" | grep -c -- '--accept-foreign')|$(printf '%s' "$D_OUT" | grep -c 'reset --hard')"

# a parked group refuses its running sibling's gate and test: no verdict, attempt or ledger row, its work stays
S_BEFORE="$(d_state "$T2W")"; ROWS="$(d_rows)"; SIB="$(st_rows 2)"; SATT="$(d_attempts 2)"
d_green 2
out="$("$TEMPER" task gate 2 2>&1)"; rc=$?
assert_eq "D-08: the sibling's task gate is refused with a message naming the park" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'parked')"
ST_EXIT=0 "$TEMPER" task test 2 --phase green >/dev/null 2>&1; rc=$?
assert_eq "D-08: the sibling's task test is refused too" "1" "$rc"
# the commit is in Task 1's own worktree, so the sibling is not touched: it stays running, its refusals add nothing
assert_eq "D-08: the refusals recorded no verdict, attempt or ledger row, and the sibling is still running" "running|$SATT|$ROWS|$SIB" \
  "$(st_field 2 status)|$(d_attempts 2)|$(d_rows)|$(st_rows 2)"
assert_eq "D-08: the sibling's worktree and branch are untouched by the refusals" "$S_BEFORE" "$(d_state "$T2W")"
assert_eq "D-08: the sibling's own file is still its uncommitted work, in its own worktree" "work src/b.sh" "$(cat "$T2W/src/b.sh")"
# a task of another group is not affected
git -C .claude/worktrees/temper-demo-G2 commit -q --allow-empty -m "g2 base" 2>/dev/null
assert_exit "D-08: a task in another group still starts" 0 "$TEMPER" task start 3

# reopen is refused while the parked sha is an ancestor of the branch HEAD
S_BEFORE="$(d_state)"
out="$("$TEMPER" group reopen G1 --task 1 2>&1)"; rc=$?
assert_eq "D-08: reopen is refused while the foreign sha is on the branch, naming it and both ways out" "1|1|1|1" \
  "$rc|$(printf '%s' "$out" | grep -q "${FSHA:0:7}" && echo 1)|$(printf '%s' "$out" | grep -c -- '--accept-foreign')|$(printf '%s' "$out" | grep -c 'rebase --autostash --onto')"
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
FSHA="$(git -C "$T1W" rev-parse HEAD)"; PARENT="$(git -C "$T1W" rev-parse HEAD~1)"
d_green 1
out="$("$TEMPER" task gate 1 2>&1)"
CMD="$(printf '%s\n' "$out" | grep -o 'git -C [^ ]* rebase --autostash --onto [0-9a-f~^]* [0-9a-f]*' | head -1)"
assert_eq "D-08: the printed route (a) is a rebase --onto of the foreign sha's parent" "1" "$(printf '%s' "$CMD" | grep -c "rebase --autostash --onto ${FSHA:0:7}~1 ${FSHA:0:7}")"
bash -c "$CMD" >/dev/null 2>&1; rrc=$?
assert_eq "D-08: the printed command runs as written and takes the commit off the branch" "0|$PARENT" "$rrc|$(git -C "$T1W" rev-parse HEAD)"
assert_eq "D-08: the sha is no longer on the branch" "1" "$(git -C "$T1W" merge-base --is-ancestor "$FSHA" HEAD >/dev/null 2>&1; echo $?)"
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
# the sibling, still running in its own worktree, finishes and passes; an accepted sha counts as known, so a later reopen
# (M5: every commit of the branch must be recorded or accepted) does not call the accepted commit one the CLI did not make
d_red 2; st_edit src/b.sh; d_green 2
out="$("$TEMPER" task gate 2 2>&1)"; rc=$?
assert_eq "D-08: an accepted sha counts as known, so the sibling is not told it holds a commit the CLI did not make" "0|0" \
  "$rc|$(printf '%s' "$out" | grep -c 'not made by the CLI')"
assert_exit "D-08: a later reopen does not refuse the accepted commit as unrecorded (M5)" 0 "$TEMPER" group reopen G1 --task 2

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

# a normal FAIL (no foreign commit) discards the attempt's worktree, then retry, escalate, park (D-03)
d_setup
"$TEMPER" task start 2 >/dev/null 2>&1; d_red 2; st_edit src/b.sh
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1; st_edit src/a.sh; st_edit stray.txt; d_green 1
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "D-08: a normal FAIL names the undeclared file and retries on the task model" "1|1|1" \
  "$rc|$(printf '%s' "$out" | grep -c 'undeclared change: stray.txt')|$(printf '%s' "$out" | grep -c '^NEXT: retry Task 1')"
assert_eq "D-08: a normal FAIL discards the task's worktree, and not the running sibling's" "no|work src/b.sh|" \
  "$([[ -d $T1W ]] && echo yes || echo no)|$(cat "$T2W/src/b.sh")|$(d_pfield status | sed 's/running//')"
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

# --- D-08 review M1-M6: detect and stop only; no automatic repair of agent misbehaviour (intent D-03, D-08) ---
# d_hint_lines: the shell lines a message prints for a human, as written (indented git lines)
d_git_lines() { printf '%s\n' "$1" | grep -E '^ +git -C ' | sed 's/^ *//'; }
d_then_line() { printf '%s\n' "$1" | grep -E '^ +then: temper ' | head -1 | sed -E "s#^ +then: temper#$TEMPER#"; }

# M1: with one worktree per task the commit is attributed exactly: the other running task's gate does not see it and passes;
# the culprit's own gate finds it and parks; after the printed rebase and reopen the culprit needs fresh RED and GREEN rows
d_setup
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1
"$TEMPER" task start 2 >/dev/null 2>&1; d_red 2
st_edit src/a.sh; st_edit src/b.sh
git -C "$T1W" add src/a.sh; echo s > "$T1W/stray.txt"; git -C "$T1W" add stray.txt; git -C "$T1W" commit -q -m "agent commit" 2>/dev/null   # the culprit is Task 1
FSHA="$(git -C "$T1W" rev-parse HEAD)"
d_green 1; d_green 2
out="$("$TEMPER" task gate 2 2>&1)"; rc=$?                              # the gate of Task 2 runs first: its worktree is clean of it
assert_eq "M1: the other task's gate does not see the culprit's commit and passes" "0|passed|running" "$rc|$(st_field 2 status)|$(st_field 1 status)"
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "M1: the culprit's own gate finds it: group parked, the culprit failed, both ways out name the culprit only" "1|parked|failed|2|0" \
  "$rc|$(d_pfield status)|$(st_field 1 status)|$(printf '%s' "$out" | grep -c -- '--task 1')|$(printf '%s' "$out" | grep -c -- '--task 2')"
RC1="$(d_then_line "$out")"
while IFS= read -r l; do bash -c "$l" >/dev/null 2>&1; done < <(d_git_lines "$out")
assert_exit "M1: the printed rebase and then the printed reopen are accepted" 0 bash -c "$RC1"
"$TEMPER" task start 1 >/dev/null 2>&1
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "M1: the culprit's reopened task does not pass on its pre-park RED and GREEN rows" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'no green run')"

# M2 is covered by the guard case in temper-cases-2.sh and tests/mod/bash.test.ts

# M3 (normal run): a D-03 park refuses the gate of a sibling that finished in the same batch; the reopen says how to gate it
d_setup
"$TEMPER" task start 2 >/dev/null 2>&1; d_red 2; st_edit src/b.sh; d_green 2
for i in 1 2 3; do
  "$TEMPER" task start 1 >/dev/null 2>&1; d_red 1; st_edit stray.txt; st_edit src/a.sh; d_green 1
  "$TEMPER" task gate 1 >/dev/null 2>&1
done
out="$("$TEMPER" group reopen G1 --task 1 2>&1)"; rc=$?
GL="$(printf '%s\n' "$out" | grep -E '^NEXT: temper task gate 2' | head -1 | sed -E "s#^NEXT: temper#$TEMPER#; s# *\(.*##")"
assert_eq "M3: after a retry-chain park and reopen, the reopen offers the gate of the finished sibling" "0|1" "$rc|$([[ -n "$GL" ]] && echo 1 || echo 0)"
assert_exit "M3: the printed gate line passes the sibling" 0 bash -c "$GL"
assert_eq "M3: the sibling is passed" "passed" "$(st_field 2 status)"

# M4: route (a) runs as written with a dirty sibling file, nothing is lost and no stash is left behind
d_setup
"$TEMPER" task start 2 >/dev/null 2>&1; d_red 2; st_edit src/b.sh      # the sibling's uncommitted work
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1
st_edit src/a.sh; st_edit stray.txt; d_commit stray.txt
FSHA="$(git -C "$T1W" rev-parse HEAD)"; PARENT="$(git -C "$T1W" rev-parse HEAD~1)"
st_edit src/a.sh; d_green 1
out="$("$TEMPER" task gate 1 2>&1)"
assert_eq "M4: the park message prints no reset, no 'or a reset'" "0" "$(printf '%s' "$out" | grep -c -i 'reset')"
M4OK=0
while IFS= read -r l; do bash -c "$l" >/dev/null 2>&1 || M4OK=1; done < <(d_git_lines "$out")
assert_eq "M4: the printed git lines run as written (exit 0) with a dirty sibling file" "0|$PARENT" "$M4OK|$(git -C "$T1W" rev-parse HEAD)"
assert_eq "M4: the sibling's dirty file is kept, the author's own uncommitted file too, no stash is left" "work src/b.sh|work src/a.sh|0" \
  "$(cat "$T2W/src/b.sh")|$(cat "$T1W/src/a.sh")|$(git -C "$T1W" stash list | wc -l | tr -d ' ')"

# M5: an agent merge. The printed lines remove the merge; the commits it brought in leave with it; reopen is accepted
d_setup
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1
git -C "$T1W" checkout -q -b side 2>/dev/null; echo x > "$T1W/side.txt"; git -C "$T1W" add side.txt 2>/dev/null; git -C "$T1W" commit -q -m "side" 2>/dev/null
git -C "$T1W" checkout -q - 2>/dev/null
git -C "$T1W" merge -q --no-ff -m "agent merge" side >/dev/null 2>&1
MSHA="$(git -C "$T1W" rev-parse HEAD)"; MPAR="$(git -C "$T1W" rev-parse HEAD~1)"
st_edit src/a.sh; d_green 1
out="$("$TEMPER" task gate 1 2>&1)"
assert_eq "M5: the park names the merge and the printed rebase is for the merge only (not the side commit)" "1|1" \
  "$(printf '%s' "$out" | grep '^FAIL' | grep -c "${MSHA:0:7}")|$(d_git_lines "$out" | wc -l | tr -d ' ')"
M5OK=0
while IFS= read -r l; do bash -c "$l" >/dev/null 2>&1 || M5OK=1; done < <(d_git_lines "$out")
RC5="$(d_then_line "$out")"
assert_eq "M5: after the printed lines the branch is back on the merge's first parent" "0|$MPAR" "$M5OK|$(git -C "$T1W" rev-parse HEAD)"
assert_exit "M5: the reopen is accepted" 0 bash -c "$RC5"
# a commit replayed under a new sha is neither recorded nor accepted: reopen refuses and names it
d_setup
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1
st_edit src/a.sh; st_edit stray.txt; d_commit stray.txt; S1="$(git -C "$T1W" rev-parse HEAD)"
st_edit stray2.txt; d_commit stray2.txt; S2="$(git -C "$T1W" rev-parse HEAD)"
d_green 1; "$TEMPER" task gate 1 >/dev/null 2>&1
git -C "$T1W" rebase -q --autostash --onto "${S1:0:7}~1" "${S1:0:7}" >/dev/null 2>&1     # the human removes only the older one
S2N="$(git -C "$T1W" rev-parse HEAD)"
out="$("$TEMPER" group reopen G1 --task 1 2>&1)"; rc=$?
assert_eq "M5: a replayed foreign commit (new sha) is refused at reopen, named" "1|1|parked" "$rc|$(printf '%s' "$out" | grep '^FAIL' | grep -c "${S2N:0:7}")|$(d_pfield status)"
out="$("$TEMPER" group reopen G1 --task 1 --accept-foreign "${S2N:0:7}" --reason "reviewed" 2>&1)"; rc=$?
assert_eq "M5: the human can accept the replayed commit knowingly" "0|running" "$rc|$(d_pfield status)"
# integrate refuses while a commit of a group branch is neither recorded nor accepted
gi_all
echo agent > .claude/worktrees/temper-demo-G1/agentfile.txt
git -C .claude/worktrees/temper-demo-G1 add agentfile.txt 2>/dev/null; git -C .claude/worktrees/temper-demo-G1 commit -q -m "agent commit" 2>/dev/null
ASHA="$(git -C .claude/worktrees/temper-demo-G1 rev-parse HEAD)"; HEAD0="$(git rev-parse HEAD)"
out="$("$TEMPER" integrate 2>&1)"; rc=$?
assert_eq "M5: integrate refuses a group branch holding an unrecorded commit, naming it, and merges nothing" "1|1|$HEAD0" \
  "$rc|$(printf '%s' "$out" | grep -c "${ASHA:0:7}")|$(git rev-parse HEAD)"

# M6: the verdict reads no environment variable for the overrides file
assert_eq "M6: no TEMPER_OVERRIDES_FILE in scripts/temper" "0" "$(grep -c 'TEMPER_OVERRIDES_FILE' "$TEMPER")"

# the undo machinery is gone from the CLI
assert_eq "D-08: no automatic-undo code is left in scripts/temper" "0" \
  "$(grep -c 'stillon\|reverthint\|TEMPER_UNDO_HEAL\|reverted_foreign\|merge_info\|temper-undo' "$TEMPER")"
setup

# --- Grouped Build: whole-diff review fixes (F1-F5) and the fail-closed spec path ---
FX_T="bash -c 'echo boom; pwd; [ -z \"\$ST_LONG\" ] || for i in \$(seq 1 400); do echo \"line \$i of a long failing output\"; done; [ -z \"\$ST_SLEEP\" ] || sleep \$ST_SLEEP; exit \${ST_EXIT:-0}'"

# F5: a file the declared test command creates (a byproduct such as __pycache__) is not an undeclared change
gg_setup
gp_mut "\`$FX_T\`" "\`bash -c 'mkdir -p __pycache__; echo pyc > __pycache__/a.pyc; exit \${ST_EXIT:-0}'\`"
gg_pass 1 src/a.sh
assert_eq "F5: a test byproduct does not fail the task gate and is not committed" "passed|0" \
  "$(st_field 1 status)|$(git -C "$ST_WT" ls-tree -r --name-only HEAD | grep -c pycache)"
gg_setup
"$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; st_edit notes.txt; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 2>&1)"
assert_eq "F5: a file the agent wrote outside the test run is still undeclared" "1" "$(printf '%s' "$out" | grep -c 'undeclared change: notes.txt')"

# F4: the group gate refuses an uncommitted change to a tracked file in the group worktree, and names it
gg_setup; gp_mut '**Depends:** Task 1' '**Depends:** none'
gg_pass 1 src/a.sh; gg_pass 2 src/b.sh
echo HACKED >> "$ST_WT/src/a.sh"
out="$("$TEMPER" group gate G1 2>&1)"; rc=$?
assert_eq "F4: group gate FAILs on an uncommitted edit of a passed task's file, naming it" "1|1" \
  "$rc|$(printf '%s' "$out" | grep -c 'uncommitted changes in the group worktree.*src/a.sh')"
git -C "$ST_WT" checkout -q -- src/a.sh
assert_exit "F4: once the edit is reverted the group gate passes" 0 "$TEMPER" group gate G1

# F3: a task that depends on a task of another group needs its group to depend on that group
gp_setup
gp_mut '**File:** `src/c.sh`
**Depends:** none' '**File:** `src/c.sh`
**Depends:** Task 1'
assert_eq "F3: the plan gate rejects a cross-group task dependency without a group dependency" "1" \
  "$(gp_has 'Task 3 (G2) depends on Task 1 (G1) but G2 does not depend on G1')"
gp_mut '## Group G2: Edge
**Depends:** none' '## Group G2: Edge
**Depends:** G1'
assert_eq "F3: with G2 depending on G1 the dependency row passes" "0|1" \
  "$(gp_has 'does not depend on')|$(gp_gate | grep -c '\[v\] dependencies')"

# F1: Change at a group gate: the feedback text reaches the reopened task, and passing it answers the feedback
gg_setup; gg_pass 1 src/a.sh; gg_pass 2 src/b.sh
"$TEMPER" group gate G1 >/dev/null 2>&1
"$TEMPER" evidence add --stage build --phase feedback --claim "feedback #1: name the function beta_main" >/dev/null 2>&1
"$TEMPER" group reopen G1 --task 2 --feedback 1 >/dev/null 2>&1
"$TEMPER" task start 2 >/dev/null 2>&1
SHOW="$("$TEMPER" task show 2)"
assert_eq "F1: task show prints the group-gate feedback for the reopened task" "1|1" \
  "$(printf '%s\n' "$SHOW" | grep -c '^--- FEEDBACK #1')|$(printf '%s\n' "$SHOW" | grep -c 'name the function beta_main')"
ST_EXIT=1 "$TEMPER" task test 2 --phase red >/dev/null 2>&1; echo beta_main > "$T2W/src/b.sh"
ST_EXIT=0 "$TEMPER" task test 2 --phase green >/dev/null 2>&1
assert_exit "F1: the reopened task passes its gate" 0 "$TEMPER" task gate 2
assert_eq "F1: the CLI recorded the feedback-resolved row, so gate build has nothing unanswered" "1|0" \
  "$(python3 -c "import json; print(sum(1 for r in json.load(open('.temper/evidence/build.json')) if r.get('phase')=='feedback-resolved' and r['claim'].startswith('feedback #1:')))")|$("$TEMPER" gate build 2>&1 | grep -c 'unanswered')"
assert_eq "F1: once answered, task show no longer prints the feedback" "0" "$("$TEMPER" task show 2 | grep -c '^--- FEEDBACK')"

# F2: a loop back to Plan ends the grouped run: groups.json archived, clean worktrees removed, branches renamed, work kept
gg_setup; gg_pass 1 src/a.sh
echo wip > .claude/worktrees/temper-demo-G2/wip.txt
G1SHA="$(git rev-parse temper/demo/G1)"
out="$("$TEMPER" state loop build plan --reason "the plan was wrong" 2>&1)"
assert_eq "F2: groups.json is archived and the reset is reported" "no|1|1" \
  "$([[ -e .temper/groups.json ]] && echo yes || echo no)|$(ls .temper/archive/groups-*.json 2>/dev/null | wc -l | tr -d ' ')|$(printf '%s' "$out" | grep -c 'grouped run reset')"
assert_eq "F2: the clean G1 worktree is removed and its branch renamed with its commits" "no|no|$G1SHA" \
  "$([[ -d $ST_WT ]] && echo yes || echo no)|$(git show-ref --verify --quiet refs/heads/temper/demo/G1 && echo yes || echo no)|$(git rev-parse "$(git for-each-ref --format='%(refname)' 'refs/heads/temper/demo/replan-*/G1')")"
assert_eq "F2: a worktree with uncommitted work is kept and named" "yes|1" \
  "$([[ -e .claude/worktrees/temper-demo-G2/wip.txt ]] && echo yes || echo no)|$(printf '%s' "$out" | grep -c 'temper-demo-G2 has uncommitted work')"
assert_exit "F2: the re-planned run starts G1 again" 0 "$TEMPER" group start G1

# fail closed: a run state that lost spec_path (an agent rewrote build-state.json) refuses every gate with the repair
setup; "$TEMPER" state init demo >/dev/null 2>&1
python3 -c "
import json; p='.temper/build-state.json'; d=json.load(open(p)); d.pop('spec_path', None); json.dump(d, open(p, 'w'))"
out="$("$TEMPER" gate check 2>&1)"; rc=$?
assert_eq "spec_path lost: gate check refuses and prints the repair" "1|1" "$rc|$(printf '%s' "$out" | grep -c 'state set spec_path .temper/specs/demo')"
assert_eq "build brief: never tells the build agent to write build-state.json" "0" \
  "$(grep -c 'write `.temper/build-state.json`' "$REPO_ROOT/reference/build.md")"
setup

# build.mode: per-task (the previous Build): its loop page, its template example, and the orchestrator choice
setup; printf 'build:\n  mode: per-task\n' >> .claude/temper.config; rm -f .temper/groups.json
awk '/^<!-- per-task-example:begin/{f=1;next} /^<!-- per-task-example:end/{f=0} f' "$REPO_ROOT/templates/tasks.md" > .temper/specs/demo/tasks.md
assert_eq "per-task template: one - [ ] box under every task" "yes" \
  "$([[ "$(grep -c '^### Task' .temper/specs/demo/tasks.md)" -gt 0 && "$(grep -c '^### Task' .temper/specs/demo/tasks.md)" == "$(sed -n '/^## Tasks/,$p' .temper/specs/demo/tasks.md | grep -c '^- \[ \] done')" ]] && echo yes || echo no)"
assert_eq "per-task template: the plan gate shows no grouped row" "0" "$("$TEMPER" gate plan 2>&1 | grep -c 'grouped plan\|integration command')"
assert_eq "orchestrator: Stage 2 reads the per-task loop page when build.mode is per-task" "1|1" \
  "$(grep -c 'reference/build-per-task.md' "$REPO_ROOT/commands/temper.md" | sed 's/^[1-9][0-9]*$/1/')|$(grep -c 'Checkpoint: task {N}' "$REPO_ROOT/reference/build-per-task.md" | sed 's/^[1-9][0-9]*$/1/')"
setup

# --- Task agents and Plan: fewer tools, real-code tests, a real RED, few groups, production-file tiers ---
# RED must fail on the tests themselves: pytest exit 2 (collection or import error), 126/127 and a timeout are no RED
FX_T2="bash -c 'echo boom; pwd; [ -z \"\$ST_LONG\" ] || for i in \$(seq 1 400); do echo \"line \$i of a long failing output\"; done; [ -z \"\$ST_SLEEP\" ] || sleep \$ST_SLEEP; exit \${ST_EXIT:-0}'"
red_case() { # red_case <exit of the RED run>: Task 1 runs a pytest-named command, RED with that exit, then GREEN
  gg_setup
  gp_mut "\`$FX_T2\`" "\`bash -c 'echo running pytest; exit \${ST_EXIT:-0}'\`"
  "$TEMPER" task start 1 >/dev/null 2>&1
  ST_EXIT="$1" "$TEMPER" task test 1 --phase red >/dev/null 2>&1
  st_edit src/a.sh
  ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
  RED_OUT="$("$TEMPER" task gate 1 2>&1)"; RED_RC=$?
}
red_case 2
assert_eq "RED: a pytest collection error (exit 2) is no RED, and the reason says so" "1|1" \
  "$RED_RC|$(printf '%s' "$RED_OUT" | grep -c 'did not run the tests (exit 2: pytest exits 1')"
red_case 1
assert_eq "RED: a pytest assertion failure (exit 1) is a RED" "0|passed" "$RED_RC|$(st_field 1 status)"
red_case 127
assert_eq "RED: exit 127 (command missing) is no RED" "1|1" "$RED_RC|$(printf '%s' "$RED_OUT" | grep -c 'could not run')"
gg_setup
"$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=2 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
assert_exit "RED: exit 2 of a command that is not pytest is still a RED" 0 "$TEMPER" task gate 1

# the task agent type carries only the tools a task needs, and the loop launches it
assert_eq "task brief: frontmatter restricts the tools to Read, Edit, Write, Bash, Glob, Grep" "1" \
  "$(grep -c '^tools: Read, Edit, Write, Bash, Glob, Grep$' "$REPO_ROOT/agents/build-task.md")"
assert_eq "grouped loop: launches the temper:temper-build-task agent type" "1" \
  "$(grep -c 'subagent_type: temper:temper-build-task' "$REPO_ROOT/reference/build-groups.md")"
assert_eq "task brief: tests call the real code, RED fails on an assertion" "1|1" \
  "$(grep -c 'Test the real code' "$REPO_ROOT/agents/build-task.md")|$(grep -c 'FAIL on an assertion' "$REPO_ROOT/agents/build-task.md")"
# Plan: few groups with parallel tasks, and the complexity tier counts production files only
assert_eq "plan reference: few groups, parallel tasks, and production files only for the tier" "1|1" \
  "$(grep -c '^\*\*Few groups, parallel tasks\.\*\*' "$REPO_ROOT/reference/plan.md")|$(grep -c '^\*\*Count production files only\.\*\*' "$REPO_ROOT/reference/plan.md")"
# --- Second whole-diff review of one worktree per task: kept work, accepted commits, the reopen check, pytest RED, merge parks ---
d_gfile() { git -C "$ST_WT" show "HEAD:$1" 2>/dev/null; }
d_on_g1() { git -C "$ST_WT" merge-base --is-ancestor "$1" HEAD >/dev/null 2>&1 && echo yes || echo no; }
# an accepted agent commit, and the uncommitted work kept beside it, both reach the group branch when the reused task passes
d_setup
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1; st_edit src/a.sh; d_commit src/a.sh
FSHA="$(git -C "$T1W" rev-parse HEAD)"; echo "kept work" >> "$T1W/src/a.sh"; d_green 1
"$TEMPER" task gate 1 >/dev/null 2>&1
"$TEMPER" group reopen G1 --task 1 --accept-foreign "${FSHA:0:7}" --reason "reviewed, it stays" >/dev/null 2>&1
"$TEMPER" task start 1 >/dev/null 2>&1
assert_eq "reuse: a reused task worktree starts with an empty snapshot (its dirty work is this attempt's)" "{}" "$(st_field 1 snapshot)"
d_red 1; d_green 1
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "reuse: the task passes, the accepted commit is on the group branch and the kept work is merged" "0|yes|kept work" \
  "$rc|$(d_on_g1 "$FSHA")|$(d_gfile src/a.sh | tail -1)"
assert_eq "reuse: the task's recorded commit is its branch tip, on the group branch" "yes|yes" \
  "$([[ -n "$(st_field 1 commit)" && "$(st_field 1 commit)" != "None" ]] && echo yes || echo no)|$(d_on_g1 "$(st_field 1 commit)")"
# an accepted commit with no further change is still merged (nothing new to commit)
d_setup
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1; st_edit src/a.sh; d_commit src/a.sh
FSHA="$(git -C "$T1W" rev-parse HEAD)"; d_green 1
"$TEMPER" task gate 1 >/dev/null 2>&1
"$TEMPER" group reopen G1 --task 1 --accept-foreign "${FSHA:0:7}" --reason "reviewed, it stays" >/dev/null 2>&1
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1; d_green 1
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "accept: a pass with only the accepted commit merges it and records it as the task's commit" "0|yes|$FSHA" \
  "$rc|$(d_on_g1 "$FSHA")|$(st_field 1 commit)"
# reopening another task does not clear a park whose commit sits in a kept task worktree
d_setup
"$TEMPER" task start 2 >/dev/null 2>&1; d_red 2; st_edit src/b.sh; d_green 2; "$TEMPER" task gate 2 >/dev/null 2>&1
"$TEMPER" task start 1 >/dev/null 2>&1; d_red 1; st_edit src/a.sh; d_commit src/a.sh
FSHA="$(git -C "$T1W" rev-parse HEAD)"; d_green 1; "$TEMPER" task gate 1 >/dev/null 2>&1
out="$("$TEMPER" group reopen G1 --task 2 2>&1)"; rc=$?
assert_eq "reopen: naming another task is refused while the parked commit is in Task 1's kept worktree" "1|1|parked" \
  "$rc|$(printf '%s' "$out" | grep -q "^FAIL: group G1 is parked on.*${FSHA:0:7}" && echo 1)|$(d_pfield status)"
out="$("$TEMPER" group reopen G1 --task 2 --accept-foreign "${FSHA:0:7}" --reason "reviewed, it stays" 2>&1)"; rc=$?
assert_eq "reopen: a sha accepted from any kept worktree of the group is accepted" "0|running" "$rc|$(d_pfield status)"
# pytest at the start of the Test command: exit 2 is no RED
gg_setup
mkdir -p "$WORKDIR/fakebin"; printf '#!/bin/sh\nexit ${ST_EXIT:-0}\n' > "$WORKDIR/fakebin/pytest"; chmod +x "$WORKDIR/fakebin/pytest"
gp_mut "\`$FX_T2\`" "\`pytest -q tests/a_test.py\`"
"$TEMPER" task start 1 >/dev/null 2>&1
PATH="$WORKDIR/fakebin:$PATH" ST_EXIT=2 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; PATH="$WORKDIR/fakebin:$PATH" ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "RED: a Test command that starts with pytest and exits 2 is no RED" "1|1" \
  "$rc|$(printf '%s' "$out" | grep -c 'pytest exits 1')"
# a pass that cannot be merged parks with git's reason and records the CLI's commit as its own; the reopen then works
gg_setup
"$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
st_edit src/a.sh; ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
mkdir -p "$ST_WT/src"; echo "in the way" > "$ST_WT/src/a.sh"
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
TSHA="$(git -C "$T1W" rev-parse HEAD)"
assert_eq "merge park: the gate FAILs, parks, and the reason carries git's own line" "1|parked|1" \
  "$rc|$(d_pfield status)|$(printf '%s' "$out" | grep -c 'could not be merged.*untracked')"
assert_eq "merge park: the CLI's task commit is recorded as the CLI's" "1" \
  "$(python3 -c "import json,sys; print(int(sys.argv[1] in json.load(open('.temper/groups.json')).get('cli_commits', [])))" "$TSHA")"
rm -f "$ST_WT/src/a.sh"
assert_exit "merge park: once the file is out of the way the reopen is accepted" 0 "$TEMPER" group reopen G1 --task 1
"$TEMPER" task start 1 >/dev/null 2>&1; ST_EXIT=1 "$TEMPER" task test 1 --phase red >/dev/null 2>&1
ST_EXIT=0 "$TEMPER" task test 1 --phase green >/dev/null 2>&1
out="$("$TEMPER" task gate 1 2>&1)"; rc=$?
assert_eq "merge park: the rerun passes and merges the kept commit" "0|yes|work src/a.sh" "$rc|$(d_on_g1 "$TSHA")|$(d_gfile src/a.sh)"
# Blocking questions are asked with AskUserQuestion in every phase, with or without the Temper bar
assert_eq "orchestrator: Blocking questions go to one AskUserQuestion in every phase, bar or not" "1|1|1" \
  "$(grep -c '^   \*\*Blocking questions first, in every phase, with or without the Temper bar\*\*' "$REPO_ROOT/commands/temper.md")|$(grep -c 'Never list Blocking questions as text' "$REPO_ROOT/commands/temper.md")|$(grep -c 'asked as the Gates section says (Blocking questions' "$REPO_ROOT/commands/temper.md")"
setup
