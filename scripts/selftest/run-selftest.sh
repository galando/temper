#!/usr/bin/env bash
# run-selftest.sh: the self test in parallel, by case file, with tiers.
#
#   bash scripts/selftest/run-selftest.sh [--jobs N] [--fast | --slow | --changed [REV]]
#
#   (default)        every case file, N at a time (TEMPER_SELFTEST_JOBS, default the number of CPUs, at most 12)
#   --fast           the case files the 9.7.5 work added (10 to 13): a minute or two
#   --slow           the whole self test, one case file after another, as test-temper.sh runs it (what CI runs)
#   --changed [REV]  the case files that the files changed since REV (default HEAD) point at, plus the 9.7.5 ones
#
# Each case file runs alone (TEMPER_CASES_ONLY=N) in its own process and folder; the helpers they share are case-helpers.sh.
# Exit 0 only when every file ends with FAIL: 0. The totals count each file once.
set -uo pipefail
unset CDPATH
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts/selftest}"
JOBS="${TEMPER_SELFTEST_JOBS:-$(nproc 2>/dev/null || echo 4)}"
TIER="all"; REV="HEAD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs) JOBS="${2:-}"; shift 2 ;;
    --fast) TIER="fast"; shift ;;
    --slow) TIER="slow"; shift ;;
    --changed) TIER="changed"; REV="HEAD"; if [[ "${2:-}" != "" && "${2:-}" != --* ]]; then REV="$2"; shift; fi; shift ;;
    *) echo "FAIL: usage: run-selftest.sh [--jobs N] [--fast | --slow | --changed [REV]]" >&2; exit 2 ;;
  esac
done
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || JOBS=4
[[ "$JOBS" -le 12 ]] || JOBS=12

if [[ "$TIER" == "slow" ]]; then exec bash "$HERE/test-temper.sh"; fi

ALL="1 2 3 4 5 6 7 8 9 10 11 12 13"
case "$TIER" in
  fast) FILES="10 11 12 13" ;;
  changed)
    FILES=""
    while IFS= read -r f; do
      case "$f" in
        scripts/selftest/temper-cases-*.sh) n="${f##*cases-}"; FILES="$FILES ${n%.sh}" ;;
        scripts/flow.py|scripts/cli_ctx.py|scripts/selftest/make-view-fixtures.sh) FILES="$FILES 8 10 12 13" ;;
        scripts/task_ops.py|scripts/tasks_md.py|scripts/scenario_ops.py|scripts/maven_loop.py|scripts/run_env.py|scripts/task_rows.py|scripts/task_cover.py) FILES="$FILES 5 11" ;;
        scripts/guards/*|scripts/guards_ops.py) FILES="$FILES 1 3 4 12" ;;
        scripts/*|templates/*|agents/*|commands/*|reference/*) FILES="$ALL" ;;
      esac
    done < <(git -C "$ROOT" diff --name-only "$REV" 2>/dev/null; git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null)
    FILES="$(printf '%s\n' $FILES 10 11 12 13 | sort -n | uniq | tr '\n' ' ')"
    ;;
  *) FILES="$ALL" ;;
esac

LOGS="$(mktemp -d)"; trap 'rm -rf "$LOGS"' EXIT
run_one() { TEMPER_CASES_ONLY="$1" bash "$HERE/test-temper.sh" > "$LOGS/$1.log" 2>&1; }
running=0
for n in $FILES; do
  run_one "$n" &
  running=$((running + 1))
  if [[ "$running" -ge "$JOBS" ]]; then wait -n 2>/dev/null || wait; running=$((running - 1)); fi
done
wait

pass=0; fail=0; bad=0
for n in $FILES; do
  line="$(grep -E '^PASS: [0-9]+  FAIL: [0-9]+' "$LOGS/$n.log" | tail -1)"
  if [[ -z "$line" ]]; then echo "case file $n: no result (the run stopped early)"; tail -5 "$LOGS/$n.log" | sed 's/^/    /'; bad=$((bad + 1)); continue; fi
  p="${line#PASS: }"; p="${p%% *}"; f="${line##*FAIL: }"
  echo "case file $n: $line"
  pass=$((pass + p)); fail=$((fail + f))
  [[ "$f" -eq 0 ]] || { grep '^FAIL' "$LOGS/$n.log" | head -8 | sed 's/^/    /'; }
done
echo ""
echo "=== run-selftest.sh ($TIER, $JOBS at a time) ==="
echo "PASS: $pass  FAIL: $((fail + bad))"
[[ $fail -eq 0 && $bad -eq 0 ]]
