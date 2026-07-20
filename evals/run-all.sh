#!/usr/bin/env bash
#
# run-all.sh — run every fixture under evals/fixtures/ through run-fixture.sh and
# print the aggregate catch rate (the README badge number).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAUGHT=0
TOTAL=0
declare -a RESULTS=()

for dir in "$REPO_ROOT"/evals/fixtures/*/; do
  name="$(basename "$dir")"
  [[ -f "$dir/expect.json" ]] || continue
  TOTAL=$((TOTAL + 1))
  if bash "$REPO_ROOT/evals/run-fixture.sh" "$name"; then
    CAUGHT=$((CAUGHT + 1))
    RESULTS+=("CAUGHT  $name")
  else
    RESULTS+=("MISSED  $name")
  fi
  echo ""
done

echo "=== evals/run-all.sh ==="
printf '%s\n' "${RESULTS[@]}"
echo ""
echo "Seeded-defect catch rate: $CAUGHT/$TOTAL"

[[ "$CAUGHT" -eq "$TOTAL" ]] && exit 0 || exit 1
