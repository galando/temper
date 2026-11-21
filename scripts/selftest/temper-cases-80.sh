# Case file 80 (WP32, the final verification): sourced by test-temper.sh after the case files before it. The gate on the
# A/B replay (scripts/e2e/replay_compare.py, the flag --base-only of scripts/e2e/ab-replay.sh, and where scripts/verify.sh
# calls each), the two rules of `scripts/check_done.py --final` that close the build (every package line of PROGRESS.md
# is done or blocked; the working papers are untracked and cited by no tracked file outside docs/plans/one-go), the mode
# `--summary` of the same script (done.md row D107) and its step in verify.sh, and the word `approval` of
# scripts/e2e/live-smoke.sh, which runs nothing while it is switched off (row D109). Every case runs on made up input
# in a throwaway folder; none calls a model, and none runs a replay. Token: final:.
#
# The folder of the working papers is never written out whole in this file: a tracked file outside docs/plans/one-go
# that names it fails `check_done.py --final` (test 4), and this file is such a file. It is built from a variable.

_c80="$WORKDIR/c80"
rm -rf "$_c80"; mkdir -p "$_c80"
_c80_kit="docs/plans/one-go"
_c80_ev="$_c80_kit/evidence"
_c80_git() { # _c80_git <dir> <git words...>: git in a throwaway repository, with a name of its own
  local d="$1"; shift
  git -C "$d" -c user.name=c80 -c user.email=c80@example.com -c commit.gpgsign=false "$@"
}
_c80_commit() { _c80_git "$1" add -A >/dev/null 2>&1; _c80_git "$1" commit -q --allow-empty -m "$2" >/dev/null 2>&1; }

# --- 1 and 2: the replay compare, on two made up result lines of scripts/e2e/replay.ts ---
_c80_line() { # _c80_line <file> [key=json...]: a result line of replay.ts with every key ab-replay.sh reads
  python3 -I - "$@" <<'PY'
import json, sys
d = {"label": "made-up", "version": "9.8.5", "shipped": True, "ended": "committed", "defect_in_commit": False,
     "questions": 3, "manual_repairs": [], "setup_clicks": 1, "agent_launch_total": 7, "agent_minutes_estimate": 92,
     "loops_recommended": [], "mvn_calls": 16, "cli_seconds": 40, "agent_launches": {"temper:temper-plan": 1}}
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    d[k] = json.loads(v)
with open(sys.argv[1], "w") as f:
    f.write(json.dumps(d) + "\n")
PY
}
_c80_cmp() { # _c80_cmp [key=json...]: the compare of the base line with a this line that differs by those keys; its exit
  _c80_line "$_c80/base.json"
  _c80_line "$_c80/this.json" "$@"
  python3 -I "$REPO_ROOT/scripts/e2e/replay_compare.py" "$_c80/base.json" "$_c80/this.json" > "$_c80/cmp.out" 2>&1
  echo "$?"
}
r1="$(_c80_cmp) $(_c80_cmp questions=2 agent_minutes_estimate=80)"
r2="$(_c80_cmp questions=4)|$(grep -c '^WORSE: questions to the person' "$_c80/cmp.out")"
r3="$(_c80_cmp shipped=false 'ended="parked"')|$(grep -c '^WORSE: shipped' "$_c80/cmp.out")"
r4="$(_c80_cmp defect_in_commit=true)|$(grep -c '^WORSE: defect in the commit' "$_c80/cmp.out")"
r5="$(_c80_cmp 'loops_recommended=["plan"]')|$(_c80_cmp 'manual_repairs=["export the JDK"]')|$(_c80_cmp setup_clicks=2)"
assert_eq "final: the replay compare fails when this tree is worse than the base" \
  "0 0 1|1 1|1 1|1 1|1|1" "$r1 $r2 $r3 $r4 $r5"

r1="$(_c80_cmp cli_seconds=400 mvn_calls=99)"
r2="$(grep -cE '^CLI seconds \(fake tools\) +40 +400$' "$_c80/cmp.out")|$(grep -cE '^build tool runs +16 +99$' "$_c80/cmp.out")"
assert_eq "final: cli_seconds and mvn_calls are printed and never compared" "0 1|1|0" \
  "$r1 $r2|$(grep -c '^WORSE' "$_c80/cmp.out")"

# --- 3 and 4: the two rules of check_done.py --final, on a made up root that passes every other rule ---
_c80_root() { # _c80_root: a fresh made up root at $_c80/root, committed: one row, an empty list, every package done
  local d="$_c80/root"
  rm -rf "$d"; mkdir -p "$d/docs/plans/one-go" "$d/scripts/selftest"
  git init -q "$d"
  cat > "$d/docs/plans/one-go/done.md" <<'DONE'
# Done

## The table

| Id | Promise | Check | No model call | Passes after |
|---|---|---|---|---|
| D01 | one | No automated check | person | WP32 |
DONE
  printf '%s\n' '# suite:name   passes after   promise' > "$d/scripts/selftest/expected-fail.txt"
  {
    printf '%s\n' '# Progress of the one pass build' '' '## Packages' '' '| Id | State | Commit | Date | Note |' '|---|---|---|---|---|'
    for wp in 00 01 02 03 04 05 06 07 08 09 10 18 14 11 12 13 15 16 17 19 20 21 22 23 24 25 26 27 28 29 30 31; do
      printf '| WP%s | done | `abc1234` | 2026-11-21 | made up |\n' "$wp"
    done
    printf '%s\n' '| WP32 | doing | | | |' '' '## Phase gates' '' '| Phase | Commit |' '|---|---|' '| 9 | doing |'
  } > "$d/docs/plans/one-go/PROGRESS.md"
  _c80_commit "$d" "the made up root"
}
_c80_final() { # _c80_final: check_done.py --final on the made up root, its output in $_c80/final.out; prints its exit code
  python3 -I "$REPO_ROOT/scripts/check_done.py" --root "$_c80/root" --final > "$_c80/final.out" 2>&1
  echo "$?"
}
_c80_state() { sed -i "s/^| $1 | [a-z]* |/| $1 | $2 |/" "$_c80/root/docs/plans/one-go/PROGRESS.md"; }

_c80_root
r1="$(_c80_final)"
_c80_state WP17 doing
r2="$(_c80_final)|$(grep -c '^FAIL: final: WP17 is doing' "$_c80/final.out")"
_c80_state WP17 todo
r3="$(_c80_final)|$(grep -c '^FAIL: final: WP17 is todo' "$_c80/final.out")"
_c80_root
sed -i '/^| WP05 |/d' "$_c80/root/docs/plans/one-go/PROGRESS.md"
r4="$(_c80_final)|$(grep -c '^FAIL: final: WP05 has no line' "$_c80/final.out")"
_c80_root
_c80_state WP09 blocked; _c80_state WP32 todo
r5="$(_c80_final)"
assert_eq "final: check_done --final fails while a package line is todo or doing" "0 1|1 1|1 1|1 0" \
  "$r1 $r2 $r3 $r4 $r5"

_c80_root
mkdir -p "$_c80/root/$_c80_ev"; printf 'a report\n' > "$_c80/root/$_c80_ev/v-report.md"
r1="$(_c80_final)"   # there, but untracked: the rule passes
_c80_commit "$_c80/root" "the working papers"
r2="$(_c80_final)|$(grep -c '^FAIL: final: the working papers are tracked' "$_c80/final.out")"
_c80_git "$_c80/root" rm -r -q "$_c80_ev"; _c80_commit "$_c80/root" "the working papers leave the tree"
r3="$(_c80_final)"
printf 'see %s/v-report.md\n' "$_c80_ev" > "$_c80/root/docs/plans/one-go/README.md"; _c80_commit "$_c80/root" "the kit cites it"
r4="$(_c80_final)"   # a file of docs/plans/one-go may name the folder
mkdir -p "$_c80/root/scripts"; printf '# from %s/v-report.md\n' "$_c80_ev" > "$_c80/root/scripts/tool.sh"
r5="$(_c80_final)"   # untracked, so not yet a citation of the tree
_c80_commit "$_c80/root" "a script cites it"
r6="$(_c80_final)|$(grep -c '^FAIL: final: scripts/tool.sh names the working papers' "$_c80/final.out")"
assert_eq "final: check_done --final fails while the evidence folder is tracked or cited by code" "0 1|1 0 0 0 1|1" \
  "$r1 $r2 $r3 $r4 $r5 $r6"

# --- 5: where verify.sh calls the replay: the compare that fails on a worse number in final only ---
r1="$(python3 -I - "$REPO_ROOT/scripts/verify.sh" <<'PY'
import sys
lines = [l.rstrip("\n") for l in open(sys.argv[1], encoding="utf-8")]
calls = [i for i, l in enumerate(lines) if "scripts/e2e/ab-replay.sh" in l and not l.lstrip().startswith("#")]
plain = [i for i in calls if "--base-only" not in lines[i]]
flag = [i for i in calls if "--base-only" in lines[i]]
ok = (len(plain) == 1 and len(flag) == 1 and lines[plain[0]].rstrip().endswith("bash scripts/e2e/ab-replay.sh 10e965a")
      and lines[plain[0] - 1].strip() == 'if [[ "$WORD" == final ]]; then' and lines[plain[0] + 1].strip() == "else"
      and flag[0] == plain[0] + 2 and lines[flag[0]].rstrip().endswith("bash scripts/e2e/ab-replay.sh --base-only 10e965a")
      and lines[flag[0] + 1].strip() == "fi")
print("%d %d %s" % (len(plain), len(flag), "in final alone" if ok else "elsewhere"))
PY
)"
r2="$(grep -cF 'python3 -I "$HERE/replay_compare.py" "$OUT/base.json" "$OUT/this.json" || CMP=$?' "$REPO_ROOT/scripts/e2e/ab-replay.sh")|$(grep -c -- '--base-only' "$REPO_ROOT/scripts/e2e/ab-replay.sh" | sed 's/^[1-9][0-9]*$/yes/')"
r3="$(bash "$REPO_ROOT/scripts/e2e/ab-replay.sh" --no-such-flag > "$_c80/ab.out" 2>&1; echo "$?")|$(grep -c 'usage: bash scripts/e2e/ab-replay.sh \[--base-only\] \[BASE\]' "$_c80/ab.out")"
assert_eq "final: verify.sh final runs the replay against the base" "1 1 in final alone|1|yes|2|1" "$r1|$r2|$r3"

# --- 6: check_done --summary, on a made up summary and a made up plan ---
_c80_sum() { # _c80_sum: a fresh root at $_c80/sum with a made up plan of three items and a summary that passes
  local d="$_c80/sum"
  rm -rf "$d"; mkdir -p "$d/docs/history" "$d/docs/plans"
  cat > "$d/docs/plans/two-approval-run.md" <<'PLAN'
# A made up plan

## 7. The releases

### Release 0. The first (1 day)

- **0a, first, as its own small change.** One thing.
- **0b.** Another.

- **Pass line:** not an item.

### Release 1. The second (2 days)

- **1a. A third thing.** Text.
- **Room under the file limit:** not an item.
- **Go or no go:** not an item.

### Later: separate proposals

- **2z. Not an item of a release.** Text.

## 8. Rules the plan never breaks

- **3a. Not an item either.** Text.
PLAN
  cat > "$d/docs/history/build-9.8.5.md" <<'SUM'
---
title: The build of 9.8.5
nav_exclude: true
---

# The build of 9.8.5

## In five lines

Made up.

## The numbers, before and after

| Number | Before | After | From |
|---|---|---|---|
| dialogs | 8 | 2 | a scripted run |

## The plan, item by item

| Item | What | State | Proof or reason |
|---|---|---|---|
| 0a | CI | built and proven | a check runs |
| 0b | the defects | built and not proven | a reader is needed |
| 1a | a third | not built | left out |

## What changes for someone who used 9.8.4

Made up.

## What went differently from the plan

Made up.

## What is not done, and what is yours to do

Made up.

## The build in numbers

Made up.

## Was it run for real

No run with a real model was made. Every check of this build used scripted agents.
SUM
}
_c80_summary() { # _c80_summary: check_done.py --summary on the made up root, its output in $_c80/sum.out; its exit code
  python3 -I "$REPO_ROOT/scripts/check_done.py" --root "$_c80/sum" --summary > "$_c80/sum.out" 2>&1
  echo "$?"
}
_c80_pad() { # _c80_pad <lines>: blank lines at the end of the made up summary until it has that many lines
  local f="$_c80/sum/docs/history/build-9.8.5.md"
  while [[ "$(wc -l < "$f")" -lt "$1" ]]; do printf '\n' >> "$f"; done
}
S="$_c80/sum/docs/history/build-9.8.5.md"
_c80_sum
r1="$(_c80_summary)"
_c80_pad 150; r1="$r1 $(_c80_summary)"
_c80_pad 151; r2="$(_c80_summary)|$(grep -c '^FAIL: summary: .* has 151 lines' "$_c80/sum.out")"
_c80_sum; sed -i '/^## The build in numbers$/d' "$S"
r3="$(_c80_summary)|$(grep -c '^FAIL: summary: .*The build in numbers' "$_c80/sum.out")"
_c80_sum; sed -i 's/^## In five lines$/## X/; s/^## The numbers, before and after$/## In five lines/; s/^## X$/## The numbers, before and after/' "$S"
r4="$(_c80_summary)|$(grep -c '^FAIL: summary: the headings are out of order' "$_c80/sum.out")"
_c80_sum; sed -i '/^| 1a |/d' "$S"
r5="$(_c80_summary)|$(grep -c '^FAIL: summary: the item 1a of the plan has no line in part 3' "$_c80/sum.out")"
_c80_sum; sed -i 's/^| 0b | the defects | built and not proven |/| 0b | the defects | done |/' "$S"
r6="$(_c80_summary)|$(grep -c '^FAIL: summary: the line of 0b in part 3 holds none of the three states' "$_c80/sum.out")"
_c80_sum; rm -f "$S"
r7="$(_c80_summary)|$(grep -c '^FAIL: summary: no docs/history/build-9.8.5.md' "$_c80/sum.out")"
r8="$(python3 -I - "$REPO_ROOT/scripts/verify.sh" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
block = re.search(r'^if \[\[ "\$WORD" == final \]\]; then\n(.*?)^fi$', text, re.S | re.M)
b = block.group(1) if block else ""
cond = re.search(r'if \[\[ -f "?docs/history/build-9\.8\.5\.md"? \]\]; then\n\s*step "[^"\n]*" python3 -I scripts/check_done\.py --summary\n'
                 r'\s*else\n\s*echo "OPEN: the summary of the build"\n\s*fi', b)
print("runs when there, OPEN when not" if cond else "no such step")
PY
)"
assert_eq "final: check_done --summary holds the form of the summary" \
  "0 0 1|1 1|1 1|1 1|1 1|1 1|1 runs when there, OPEN when not" "$r1 $r2 $r3 $r4 $r5 $r6 $r7 $r8"

# --- 7: the live smoke knows the word approval, and is off unless TEMPER_E2E_LIVE=1 ---
r1="$(env -u TEMPER_E2E_LIVE bash "$REPO_ROOT/scripts/e2e/live-smoke.sh" approval > "$_c80/live.out" 2>&1; echo "$?")"
r2="$(grep -c '^live smoke is off' "$_c80/live.out")|$(wc -l < "$_c80/live.out" | tr -d ' ')"
r3="$(grep -cE 'usage: live-smoke\.sh \[[^]]*\bapproval\b' "$REPO_ROOT/scripts/e2e/live-smoke.sh")"
r4="$(grep -cE '^#.*TEMPER_E2E_LIVE=1 bash scripts/e2e/live-smoke\.sh approval ' "$REPO_ROOT/scripts/e2e/live-smoke.sh")"
assert_eq "final: the live smoke knows the word approval and runs nothing unless it is switched on" "0|1|1|1|1" \
  "$r1|$r2|$r3|$r4"
