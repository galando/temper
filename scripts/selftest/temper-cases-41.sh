# Case file 41 (WP05, the floor, the caps and the run summary): sourced by test-temper.sh after the case files before
# it. The floor (scripts/e2e/floor.json, held by scripts/check_floor.py), the growth caps (scripts/caps.json, held by
# scripts/check_caps.py), the stops an unattended run must keep (scripts/stops.json) and the one line a finished run
# leaves in .temper/runs.jsonl. Tokens: floor:, caps:, summary:.

_c41_caps="$REPO_ROOT/scripts/check_caps.py"
_c41_floor="$REPO_ROOT/scripts/check_floor.py"
_c41_edit() { # _c41_edit <json file> <python statement over d>: changes the file in place
  python3 -I - "$1" "$2" <<'PY'
import json, sys
p, code = sys.argv[1], sys.argv[2]
d = json.load(open(p))
exec(code, {"d": d})
json.dump(d, open(p, "w"), indent=1)
PY
}
_c41_dir="$WORKDIR/c41"
rm -rf "$_c41_dir"; mkdir -p "$_c41_dir"

# --- caps ---
assert_exit "caps: every cap is measured and equals its now value" 0 python3 -I "$_c41_caps"

cp "$REPO_ROOT/scripts/caps.json" "$_c41_dir/up.json"
_c41_edit "$_c41_dir/up.json" 'd["caps"]["question_sites"]["now"] += 1'
cp "$REPO_ROOT/scripts/caps.json" "$_c41_dir/down.json"
_c41_edit "$_c41_dir/down.json" 'd["caps"]["prompt_bytes"]["now"] -= 1'
assert_eq "caps: a now value one above the measure fails, and one below fails" "1 1 yes" \
  "$(python3 -I "$_c41_caps" --caps "$_c41_dir/up.json" >/dev/null 2>&1; echo -n "$? "
     python3 -I "$_c41_caps" --caps "$_c41_dir/down.json" > "$_c41_dir/down.out" 2>&1; echo -n "$? "
     grep -q 'prompt_bytes: the measure is' "$_c41_dir/down.out" && echo yes || echo no)"

# every final at its now value, then one final below its now: only --final fails
cp "$REPO_ROOT/scripts/caps.json" "$_c41_dir/final.json"
_c41_edit "$_c41_dir/final.json" 'for c in d["caps"].values(): c["final"] = c["now"]'
cp "$_c41_dir/final.json" "$_c41_dir/below.json"
_c41_edit "$_c41_dir/below.json" 'd["caps"]["agent_briefs"]["final"] = d["caps"]["agent_briefs"]["now"] - 1'
assert_eq "caps: a now value above its final fails only in the final mode" "0 0 1" \
  "$(python3 -I "$_c41_caps" --caps "$_c41_dir/final.json" --final >/dev/null 2>&1; echo -n "$? "
     python3 -I "$_c41_caps" --caps "$_c41_dir/below.json" >/dev/null 2>&1; echo -n "$? "
     python3 -I "$_c41_caps" --caps "$_c41_dir/below.json" --final >/dev/null 2>&1; echo "$?")"

# a throwaway git folder: the file committed, then a final raised and committed (refused also after the commit); a key
# no earlier commit holds is exempt
_c41_hist() { # _c41_hist <folder> <file name> <source>: a git folder whose first commit holds the file
  rm -rf "$1"; mkdir -p "$1"
  git -C "$1" init -q . && cp "$3" "$1/$2"
  git -C "$1" add "$2" && git -C "$1" -c user.name=t -c user.email=t@example.com commit -qm first
}
_c41_hist "$_c41_dir/hc" caps.json "$REPO_ROOT/scripts/caps.json"
_c41_edit "$_c41_dir/hc/caps.json" 'd["caps"]["question_sites"]["final"] += 1'
git -C "$_c41_dir/hc" -c user.name=t -c user.email=t@example.com commit -qam raise
_c41_raise="$(python3 -I "$_c41_caps" --caps "$_c41_dir/hc/caps.json" 2>&1; echo "exit $?")"
cp "$REPO_ROOT/scripts/caps.json" "$_c41_dir/new.json"
_c41_edit "$_c41_dir/new.json" 'd["caps"].pop("readme_lines")'
_c41_hist "$_c41_dir/hn" caps.json "$_c41_dir/new.json"
cp "$REPO_ROOT/scripts/caps.json" "$_c41_dir/hn/caps.json"
_c41_edit "$_c41_dir/hn/caps.json" 'd["caps"]["readme_lines"]["final"] = 999'
assert_eq "caps: a final value above its first committed value fails" "yes exit 1|exit 0" \
  "$(grep -q 'question_sites: final 54 is above its first committed value 53' <<< "$_c41_raise" && echo -n yes; echo -n " ${_c41_raise##*$'\n'}|"
     python3 -I "$_c41_caps" --caps "$_c41_dir/hn/caps.json" >/dev/null 2>&1; echo "exit $?")"

# --- floor ---
_c41_hist "$_c41_dir/hf" floor.json "$REPO_ROOT/scripts/e2e/floor.json"
_c41_edit "$_c41_dir/hf/floor.json" 'd["scenarios"]["default-run"]["plain"]["final"]["dialogs"] += 1'
git -C "$_c41_dir/hf" -c user.name=t -c user.email=t@example.com commit -qam raise
assert_eq "floor: a final value above its first committed value fails" "0|1 yes" \
  "$(python3 -I "$_c41_floor" --floor "$REPO_ROOT/scripts/e2e/floor.json" >/dev/null 2>&1; echo -n "$?|"
     python3 -I "$_c41_floor" --floor "$_c41_dir/hf/floor.json" > "$_c41_dir/hf.out" 2>&1; echo -n "$? "
     grep -q 'scenarios/default-run/plain/final/dialogs is 3, above its first committed value 2' "$_c41_dir/hf.out" && echo yes || echo no)"

# a final removed or set to null loosens its bound as a raise does; a type a `launches` final no longer names stands at 0
_c41_drop() { # _c41_drop <name> <python statement over d>: the floor committed, then the statement committed; prints the exit
  _c41_hist "$_c41_dir/$1" floor.json "$REPO_ROOT/scripts/e2e/floor.json"
  _c41_edit "$_c41_dir/$1/floor.json" "$2"
  git -C "$_c41_dir/$1" -c user.name=t -c user.email=t@example.com commit -qam drop
  python3 -I "$_c41_floor" --floor "$_c41_dir/$1/floor.json" > "$_c41_dir/$1.out" 2>&1; echo -n "$?"
}
assert_eq "floor: a final removed or set to null fails, a launch type left out of a launches final does not" "1 yes|1 yes|1|0" \
  "$(_c41_drop hl 'for e in d["scenarios"]["default-run"].values(): e["final"].pop("launches")'
     grep -q 'scenarios/default-run/plain/final/launches/temper:temper-plan is removed, its first committed value is 1: a final is never removed' "$_c41_dir/hl.out" && echo -n " yes|" || echo -n " no|"
     _c41_drop hn 'd["scenarios"]["default-run"]["driver"]["final"]["dialogs"] = None'
     grep -q 'scenarios/default-run/driver/final/dialogs is null, its first committed value is' "$_c41_dir/hn.out" && echo -n " yes|" || echo -n " no|"
     _c41_drop hb 'd["scenarios"]["default-run"]["plain"].pop("final")'; echo -n "|"
     _c41_drop ht 'd["scenarios"]["default-run"]["plain"]["final"]["launches"].pop("temper:temper-review")')"

# a made up counts file: the counts of default-run in plain mode as the floor holds them, then one moved
python3 -I - "$REPO_ROOT/scripts/e2e/floor.json" "$_c41_dir" <<'PY'
import json, os, sys
now = json.load(open(sys.argv[1]))["scenarios"]["default-run"]["plain"]["now"]
same = [{"scenario": "default-run", "mode": "plain", "counts": now}]
json.dump(same, open(os.path.join(sys.argv[2], "same.json"), "w"))
moved = json.loads(json.dumps(same))
moved[0]["counts"]["dialogs"] += 1
json.dump(moved, open(os.path.join(sys.argv[2], "moved.json"), "w"))
json.dump([{"scenario": "no-such-run", "mode": "plain", "counts": now}], open(os.path.join(sys.argv[2], "none.json"), "w"))
PY
_c41_want="$(python3 -c 'import json,sys; n=json.load(open(sys.argv[1]))["scenarios"]["default-run"]["plain"]["now"]["dialogs"]; print("default-run [plain]: dialogs is %d, the floor holds %d" % (n + 1, n))' "$REPO_ROOT/scripts/e2e/floor.json")"
assert_eq "floor: a count that differs from the file fails with the scenario, the mode and both numbers" "0|1 yes|1" \
  "$(python3 -I "$_c41_floor" --counts "$_c41_dir/same.json" >/dev/null 2>&1; echo -n "$?|"
     python3 -I "$_c41_floor" --counts "$_c41_dir/moved.json" > "$_c41_dir/moved.out" 2>&1; echo -n "$? "
     grep -qF "$_c41_want" "$_c41_dir/moved.out" && echo -n yes || echo -n no; echo -n "|"
     python3 -I "$_c41_floor" --counts "$_c41_dir/none.json" >/dev/null 2>&1; echo "$?")"

# a made up line of the replay: the numbers of replay_base (a list the replay prints is held as its length)
python3 -I - "$REPO_ROOT/scripts/e2e/floor.json" "$_c41_dir" <<'PY'
import json, os, sys
base = json.load(open(sys.argv[1]))["replay_base"]
line = dict(base, loops_recommended=["x"] * base["loops_recommended"], manual_repairs=["x"] * base["manual_repairs"],
            label="base", cli_seconds=9)
open(os.path.join(sys.argv[2], "equal.txt"), "w").write("a table line\n" + json.dumps(line) + "\n")
line["agent_minutes_estimate"] += 1
open(os.path.join(sys.argv[2], "moved.txt"), "w").write(json.dumps(line) + "\n")
PY
assert_eq "floor: the base column of the replay equals replay_base" "0|1 yes" \
  "$(python3 -I "$_c41_floor" --replay-base "$_c41_dir/equal.txt" >/dev/null 2>&1; echo -n "$?|"
     python3 -I "$_c41_floor" --replay-base < "$_c41_dir/moved.txt" > "$_c41_dir/rb.out" 2>&1; echo -n "$? "
     grep -q 'replay_base: agent_minutes_estimate is' "$_c41_dir/rb.out" && echo yes || echo no)"

# a stop with no check yet is allowed here (WP07 writes the checks); a name that is set must be found
assert_eq "floor: every check that scripts/stops.json names exists" "ok" \
  "$(python3 -I - "$REPO_ROOT" <<'PY'
import json, os, subprocess, sys
root = sys.argv[1]
doc = json.load(open(os.path.join(root, "scripts", "stops.json")))
bad = []
ids = [s.get("id") for s in doc.get("stops") or []]
if len(ids) < 18 or len(set(ids)) != len(ids):
    bad.append("the list has %d stops, %d distinct" % (len(ids), len(set(ids))))
for s in doc.get("stops") or []:
    if set(s) != {"id", "where", "trigger", "check"}:
        bad.append("%s: keys %s" % (s.get("id"), sorted(s)))
    name = s.get("check") or ""
    if name and subprocess.run(["grep", "-rqF", "--", name, os.path.join(root, "scripts", "selftest"),
                                os.path.join(root, "scripts", "e2e")]).returncode != 0:
        bad.append("%s: no check named %s" % (s.get("id"), name))
print("; ".join(bad) or "ok")
PY
)"

# --- summary: one line a finished run, in .temper/runs.jsonl ---
_c41_runs() { python3 -c 'import sys; print(sum(1 for l in open(".temper/runs.jsonl") if l.strip()))' 2>/dev/null || echo 0; }
_c41_last() { # _c41_last <python expression over d, the last line>
  python3 -c 'import json,sys; d=json.loads([l for l in open(".temper/runs.jsonl") if l.strip()][-1]); print(eval(sys.argv[1]))' "$1"
}
setup
_pass intent
"$TEMPER" state clear >/dev/null
_c41_one="$(_c41_runs)"
"$TEMPER" state init demo --command temper >/dev/null
"$TEMPER" state clear >/dev/null
assert_eq "summary: state clear appends one line to .temper/runs.jsonl and the line survives state init" "1 2 demo temper cleared yes" \
  "$_c41_one $(_c41_runs) $(_c41_last 'd["slug"], d["command"], d["ended"]' | tr -d "(),'") $(grep -qxF '/.temper/runs.jsonl' .git/info/exclude && echo yes || echo no)"

# `next` twice at the same question: asked once
setup
_at intent
gpass intent
"$TEMPER" next --json >/dev/null; "$TEMPER" next --json >/dev/null
_c41_q="$(nx "d['ask']['id']")"
"$TEMPER" state clear >/dev/null
assert_eq "summary: the line counts the questions the CLI asked once each" "intent.accept 1 1 1 no" \
  "$_c41_q $(_c41_last 'd["asks"]["n"], d["asks"]["by_stage"].get("intent"), d["asks"]["by_kind"].get("gate")' | tr -d "(),") $([[ -f .temper/asked.json ]] && echo yes || echo no)"

# one question about two groups at one step is two questions; a view written by any other command asks nothing
_c41_groups() { # _c41_groups <G1 confirmed: "" or a time>: both groups passed their gate, the first confirmed or not
  printf '{"version": 1, "slug": "demo", "groups": {"G1": {"status": "passed", "worktree": "w1", "gate": {"verdict": "PASS"}%s}, "G2": {"status": "passed", "worktree": "w2", "gate": {"verdict": "PASS"}}}, "tasks": {"1": {"status": "passed", "group": "G1"}, "2": {"status": "passed", "group": "G1"}, "3": {"status": "passed", "group": "G2"}}}\n' \
    "${1:+, \"confirmed\": \"$1\"}" > .temper/groups.json
}
declare -F gp_base >/dev/null || source "$TESTS_DIR/case-helpers-5.sh"
fresh; printf 'build:\n  mode: grouped\n' >> .claude/temper.config; gp_base
gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
_c41_groups ""
_c41_q="$(nx "d['ask']['id']") $(nx "d['run']['step']")"
"$TEMPER" evidence add --stage build --phase note --kind input --claim 'a view written, no question handed' >/dev/null 2>&1
_c41_groups "t"
_c41_q="$_c41_q $(nx "d['ask']['question']['question'].split(' (')[0]") $(nx "d['run']['step']")"
"$TEMPER" state clear >/dev/null
assert_eq "summary: one question about two groups at one step counts two" "group.pass 2 Group G2 2 2 {'group': 2}" \
  "$_c41_q $(_c41_last 'd["asks"]["n"]') $(_c41_last 'd["asks"]["by_kind"]')"

setup
_at review
"$TEMPER" state loop review build --reason 'a finding to repair' >/dev/null
"$TEMPER" state clear >/dev/null
assert_eq "summary: the steps back of the run are in the line" "[{'from': 'review', 'n': 1, 'to': 'build'}]" \
  "$(_c41_last 'd["steps_back"]')"

# two steps back from Review to Build are one record of feedback-loops.json, with its iteration at 2
setup
_at review
"$TEMPER" state loop review build --reason 'a finding to repair' >/dev/null
_at review
"$TEMPER" state loop review build --reason 'a second finding' >/dev/null
_c41_it="$(python3 -c 'import json; print([l["iteration"] for l in json.load(open(".temper/feedback-loops.json"))["active_loops"]])')"
"$TEMPER" state clear >/dev/null
assert_eq "summary: two steps back of one pair count two" "[2] [{'from': 'review', 'n': 2, 'to': 'build'}]" \
  "$_c41_it $(_c41_last 'd["steps_back"]')"

# A Build task agent: its own gate of Task 1 (a `task` row), its launch's row (`build`, 2 s), the gate of its after calls
# (nothing to gate). Then the gate of Task 3, left running by an earlier conversation, with its time (3 s): one launch.
declare -F st_setup >/dev/null || source "$TESTS_DIR/case-helpers-5.sh"
st_setup
st_pass_ready
"$TEMPER" task gate 1 --model m >/dev/null 2>&1
"$TEMPER" usage add --stage build --model m --ms 2000 --task 1 >/dev/null
"$TEMPER" task gate 1 --model m --if-running >/dev/null 2>&1
"$TEMPER" task start 3 >/dev/null 2>&1
"$TEMPER" task gate 3 --model m --ms 3000 >/dev/null 2>&1
_c41_rows="$(python3 -c 'import json; print(",".join(r["stage"] for r in json.load(open(".temper/usage.json"))))')"
"$TEMPER" state clear >/dev/null
assert_eq "summary: a task gate is no launch, but for the gate of a task left running" "task,build,task {'build': 2} 5" \
  "$_c41_rows $(_c41_last 'd["launches"]["by_stage"]') $(_c41_last 'd["agent_seconds"]')"

setup
python3 -c 'import json; open(".temper/runs.jsonl", "w").write("".join(json.dumps({"v": 1, "n": i}) + "\n" for i in range(205)))'
"$TEMPER" state clear >/dev/null
assert_eq "summary: the file keeps the last 200 lines" "200 6 1" \
  "$(_c41_runs) $(python3 -c 'import json; print(json.loads(open(".temper/runs.jsonl").readline())["n"])') $(_c41_last 'd["v"]')"

# --- summary of a bench round: bench/scorecard.py on a made up results folder (no model call) ---
python3 -I - "$_c41_dir/bench" <<'PY'
import json, os, sys
root = sys.argv[1]
def run(folder, task, arm, rep, cost, wall, dialogs, reviews, back=0, mod=False):
    d = os.path.join(root, folder, "%s__%s__%d" % (task, arm, rep))
    os.makedirs(os.path.join(d, "session", "subagents"), exist_ok=True)
    json.dump({"task": task, "arm": arm, "rep": rep, "cost_usd": cost, "wall_s": wall, "questions": dialogs,
               "ended": "done", "mod": mod, "plugin_commit": "c" + folder}, open(os.path.join(d, "run.json"), "w"))
    json.dump({"hidden_pass": 4, "hidden_total": 4}, open(os.path.join(d, "grade.json"), "w"))
    with open(os.path.join(d, "person.jsonl"), "w") as f:
        for k in range(dialogs):
            f.write(json.dumps({"dialog": k + 1, "qid": "plan.approve", "move": "back" if k < back else None}) + "\n")
    for k in range(reviews):
        base = os.path.join(d, "session", "subagents", "agent-%d" % k)
        json.dump({"agentType": "temper:temper-review", "model": "sonnet"}, open(base + ".meta.json", "w"))
        open(base + ".jsonl", "w").write(json.dumps({"timestamp": "2026-01-01T00:00:0%dZ" % k}) + "\n"
                                          + json.dumps({"timestamp": "2026-01-01T00:00:1%dZ" % k}) + "\n")
for rep in (1, 2):
    run("before", "cent-mismatch", "vanilla", rep, 1.0, 100, 0, 0)
    run("before", "cent-mismatch", "temper", rep, 3.0, 400, 6, 2, back=1)
    run("after", "cent-mismatch", "vanilla", rep, 1.0, 100, 0, 0)
    run("after", "cent-mismatch", "temper", rep, 1.4, 240, 2, 1)
PY
_c41_sc="$(cd "$_c41_dir/bench" && python3 -I "$REPO_ROOT/bench/scorecard.py" before after --gate gate.json >/dev/null 2>&1; echo -n "$? "
  python3 -c 'import json; d=json.load(open("gate.json")); l=d["lines"]; print(d["arm"], d["before"], d["plain"], l["bug"]["cost_ratio"], l["bug"]["time_ratio"], l["bug"]["pass"], l["hidden"]["pass"], l["reviews"]["pass"], l["steps_back"]["pass"], l["clear"]["pass"])'
  python3 -c 'import json; b=json.load(open("after/scorecard.json"))["blocks"]["after/temper"]; print(b["all"]["launches"], b["bug"]["cost"]["median"])')"
assert_eq "summary: the bench scorecard holds the round after against the plain arm and the round before" \
  "0 after/temper before/temper after/vanilla 1.4 2.4 True True True True None
{'temper:temper-review': 2} 1.4" "$_c41_sc"
