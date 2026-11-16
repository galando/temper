#!/usr/bin/env bash
# run-selftest.sh: the self test in parallel, by case file, with tiers.
#
#   bash scripts/selftest/run-selftest.sh [--jobs N] [--fast | --slow | --changed [REV] | --touched [REV]] [--shard K/N] [--list]
#
#   (default)        every case file, N at a time (TEMPER_SELFTEST_JOBS, default the number of CPUs, at most 12)
#   --fast           every case file from 10 up: a few minutes
#   --slow           the whole self test, one case file after another, as test-temper.sh runs it
#   --changed [REV]  the case files that the files changed since REV (default HEAD) point at, plus every one from 10 up
#   --touched [REV]  only the case files that themselves differ from REV (default HEAD) or are untracked; a changed
#                    temper-cases-5.sh or case-helpers-5.sh also selects 6 and 31 (what bash scripts/verify.sh quick runs)
#   --shard K/N      of the groups in order, only those whose index modulo N is K minus 1 (what CI runs, one shard a job)
#   --list           print the groups the chosen tier would run, one per line, and run nothing
#
# A case file is found by its name: every temper-cases-N.sh next to this script, so a new one needs no list. Files that
# use what an earlier file defines run in one process with it (group_of). Each group runs alone (TEMPER_CASES_ONLY) in
# its own process and folder; the helpers they share are case-helpers.sh. Exit 0 only when every group ends with
# FAIL: 0. The totals count each file once; the checks of scripts/selftest/expected-fail.txt that failed as expected are
# added up apart, in the line XFAIL: <n> before the last line.
set -uo pipefail
unset CDPATH
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts/selftest}"
JOBS="${TEMPER_SELFTEST_JOBS:-$(nproc 2>/dev/null || echo 4)}"
TIER="all"; REV="HEAD"; LIST=0; SHARD=""
USAGE="usage: run-selftest.sh [--jobs N] [--fast | --slow | --changed [REV] | --touched [REV]] [--shard K/N] [--list]"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs) JOBS="${2:-}"; shift 2 ;;
    --fast) TIER="fast"; shift ;;
    --slow) TIER="slow"; shift ;;
    --changed|--touched) TIER="${1#--}"; REV="HEAD"; if [[ "${2:-}" != "" && "${2:-}" != --* ]]; then REV="$2"; shift; fi; shift ;;
    --shard) [[ -n "${2:-}" ]] || { echo "FAIL: --shard needs K/N; $USAGE" >&2; exit 2; }; SHARD="$2"; shift 2 ;;
    --list) LIST=1; shift ;;
    *) echo "FAIL: $USAGE" >&2; exit 2 ;;
  esac
done
if [[ -n "$SHARD" ]]; then
  [[ "$SHARD" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ ]] && (( BASH_REMATCH[1] <= BASH_REMATCH[2] )) \
    || { echo "FAIL: --shard takes K/N with 1 <= K <= N, not '$SHARD'; $USAGE" >&2; exit 2; }
  SHARD_K="${BASH_REMATCH[1]}"; SHARD_N="${BASH_REMATCH[2]}"
fi
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || JOBS=4
[[ "$JOBS" -le 12 ]] || JOBS=12

if [[ "$TIER" == "slow" && "$LIST" -eq 0 && -z "$SHARD" ]]; then exec bash "$HERE/test-temper.sh"; fi

# The numbers of the temper-cases-N.sh files next to this script, in number order.
case_files() { (cd "$HERE" && for f in temper-cases-*.sh; do f="${f#temper-cases-}"; echo "${f%.sh}"; done) | sort -n | tr '\n' ' '; }
ALL="$(case_files)"
FROM10="$(for n in $ALL; do [[ "$n" -ge 10 ]] && echo "$n"; done | tr '\n' ' ')"
# Case files that use what an earlier file defines run in one process with it, in order: 2 with 3, 8 with 9. (Case
# file 6 sources case-helpers-5.sh, which make-helpers-5.sh generates, so 5 and 6 run side by side.)
group_of() { case "$1" in 3) echo "2 3" ;; 2) echo "2 3" ;; 8|9) echo "8 9" ;; *) echo "$1" ;; esac; }
if [[ "$TIER" == touched || "$TIER" == changed ]]; then
  git -C "$ROOT" rev-parse --verify --quiet "$REV^{commit}" > /dev/null \
    || { echo "FAIL: --$TIER takes a commit, and '$REV' is none; $USAGE" >&2; exit 2; }
fi
case "$TIER" in
  fast) FILES="$FROM10" ;;
  touched)
    FILES=""
    while IFS= read -r f; do
      case "$f" in
        scripts/selftest/temper-cases-5.sh|scripts/selftest/case-helpers-5.sh) FILES="$FILES 5 6 31" ;;
        scripts/selftest/temper-cases-*.sh) n="${f##*cases-}"; FILES="$FILES ${n%.sh}" ;;
      esac
    done < <(git -C "$ROOT" diff --name-only "$REV" 2>/dev/null; git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null)
    FILES="$(for n in $FILES; do [[ -f "$HERE/temper-cases-$n.sh" ]] && echo "$n"; done | sort -n | uniq | tr '\n' ' ')"
    ;;
  changed)
    FILES=""
    while IFS= read -r f; do
      case "$f" in
        scripts/selftest/temper-cases-*.sh) n="${f##*cases-}"; FILES="$FILES ${n%.sh}" ;;
        scripts/flow.py|scripts/flow_*.py|scripts/cli_ctx.py|scripts/selftest/make-view-fixtures.sh) FILES="$FILES 8 10 12 13" ;;
        scripts/task_ops.py|scripts/tasks_md.py|scripts/scenario_ops.py|scripts/maven_loop.py|scripts/run_env.py|scripts/task_rows.py|scripts/task_cover.py) FILES="$FILES 5 11" ;;
        scripts/guards/*|scripts/guards_ops.py) FILES="$FILES 1 3 4 12" ;;
        scripts/*|templates/*|agents/*|commands/*|reference/*) FILES="$ALL" ;;
      esac
    done < <(git -C "$ROOT" diff --name-only "$REV" 2>/dev/null; git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null)
    FILES="$(printf '%s\n' $FILES $FROM10 | sort -n | uniq | tr '\n' ' ')"
    ;;
  *) FILES="$ALL" ;;
esac
GROUPS_TO_RUN="$(for n in $FILES; do group_of "$n" | tr ' ' '_'; done | sort -t_ -k1,1n | uniq | tr '\n' ' ')"
if [[ -n "$SHARD" ]]; then
  GROUPS_TO_RUN="$(i=0; for g in $GROUPS_TO_RUN; do (( i % SHARD_N == SHARD_K - 1 )) && echo "$g"; i=$((i + 1)); done | tr '\n' ' ')"
fi
if [[ "$LIST" -eq 1 ]]; then
  for g in $GROUPS_TO_RUN; do echo "${g//_/ }"; done
  exit 0
fi
if [[ -z "${GROUPS_TO_RUN// /}" ]]; then
  echo "=== run-selftest.sh ($TIER) ==="
  echo "no case file to run"
  echo "XFAIL: 0"
  echo "PASS: 0  FAIL: 0"
  exit 0
fi

LOGS="$(mktemp -d)"; trap 'rm -rf "$LOGS"' EXIT
run_one() { TEMPER_CASES_ONLY="${1//_/ }" bash "$HERE/test-temper.sh" > "$LOGS/$1.log" 2>&1; }
running=0
for n in $GROUPS_TO_RUN; do
  run_one "$n" &
  running=$((running + 1))
  if [[ "$running" -ge "$JOBS" ]]; then wait -n 2>/dev/null || wait; running=$((running - 1)); fi
done
wait

pass=0; fail=0; bad=0; xfail=0
for n in $GROUPS_TO_RUN; do
  line="$(grep -E '^PASS: [0-9]+  FAIL: [0-9]+' "$LOGS/$n.log" | tail -1)"
  if [[ -z "$line" ]]; then echo "case file(s) ${n//_/ }: no result (the run stopped early)"; tail -5 "$LOGS/$n.log" | sed 's/^/    /'; bad=$((bad + 1)); continue; fi
  p="${line#PASS: }"; p="${p%% *}"; f="${line##*FAIL: }"
  # the checks still expected to fail (scripts/selftest/expected-fail.txt), counted apart: test-temper.sh prints XFAIL: <n>
  # before its last line
  x="$(grep -E '^XFAIL: [0-9]+$' "$LOGS/$n.log" | tail -1)"; x="${x#XFAIL: }"; x="${x:-0}"
  echo "case file(s) ${n//_/ }: $line${x:+  XFAIL: $x}"
  pass=$((pass + p)); fail=$((fail + f)); xfail=$((xfail + x))
  [[ "$f" -eq 0 ]] || { grep -E '^(FAIL|UNEXPECTED PASS)' "$LOGS/$n.log" | head -8 | sed 's/^/    /'; }
done
echo ""
echo "=== run-selftest.sh ($TIER${SHARD:+, shard $SHARD}, $JOBS at a time) ==="
echo "XFAIL: $xfail"
echo "PASS: $pass  FAIL: $((fail + bad))"
[[ $fail -eq 0 && $bad -eq 0 ]]
