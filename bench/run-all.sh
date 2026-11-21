#!/usr/bin/env bash
# run-all.sh [REPS] [ARMS...]: every task x every arm x REPS (default 3), each run graded. Costs real model calls.
# The arms default to vanilla careful temper. BENCH_TASKS="a b" runs only those tasks. Runs go one at a time, so the costs and times do not interfere.
# BENCH_CONFIG_YAML="models:\n  plan: sonnet" adds those lines to each run's project config (run.mjs --config-yaml); unset, none.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPS="${1:-3}"; shift || true
RESULTS="${TEMPER_BENCH_RESULTS:-$HOME/temper-bench-results}"
ARMS=("$@"); [[ ${#ARMS[@]} -eq 0 ]] && ARMS=(vanilla careful temper)
while IFS= read -r t; do
  for rep in $(seq 1 "$REPS"); do
    for arm in "${ARMS[@]}"; do
      d="$RESULTS/${t}__${arm}__${rep}"
      [[ -f "$d/grade.json" ]] && { echo "skip $t $arm $rep (graded)"; continue; }
      echo "run  $t $arm $rep"
      node "$HERE/run.mjs" --task "$t" --arm "$arm" --rep "$rep" --timeout-min "${BENCH_TIMEOUT_MIN:-90}" \
        ${BENCH_CONFIG_YAML:+--config-yaml "$BENCH_CONFIG_YAML"} || echo "FAIL: run $t $arm $rep"
      python3 "$HERE/grade.py" "$d" || echo "FAIL: grade $t $arm $rep"
    done
  done
done < <(if [[ -n "${BENCH_TASKS:-}" ]]; then printf '%s\n' $BENCH_TASKS; else find "$HERE/tasks" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort; fi)
python3 "$HERE/report.py"
