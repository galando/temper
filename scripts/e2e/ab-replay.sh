#!/usr/bin/env bash
# ab-replay.sh [--base-only] [BASE]: the replay of the measured run (scripts/e2e/replay.ts) on the version before a
# change and on this tree, side by side. BASE defaults to 7c7a1c1 (9.8.4, what users have). It checks the base out into a
# throwaway worktree, runs the same scripted agents and person against both, prints one table, and removes the
# worktree. Needs bun. Nothing here touches the project's own .temper or branches. With the base 10e965a it also holds
# the base column against replay_base of scripts/e2e/floor.json (scripts/check_floor.py --replay-base).
# The table and the compare are scripts/e2e/replay_compare.py (9.8.5, WP32): the script exits 1 when a counted number of
# this tree is above the base, or this tree did not ship or committed the High defect (done.md row D59). With
# --base-only the table is printed and the result of the compare is not returned: only the check of the base column
# counts (the mode full of scripts/verify.sh; the mode final calls it without the flag).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
USAGE="usage: bash scripts/e2e/ab-replay.sh [--base-only] [BASE]"
BASE_ONLY=0; BASE=""
for a in "$@"; do
  case "$a" in
    --base-only) BASE_ONLY=1 ;;
    -*) echo "ab-replay.sh: unknown flag $a. $USAGE" >&2; exit 2 ;;
    *) [[ -z "$BASE" ]] || { echo "ab-replay.sh: one BASE only. $USAGE" >&2; exit 2; }; BASE="$a" ;;
  esac
done
BASE="${BASE:-7c7a1c1}"
OUT="$(mktemp -d)"
OLD="$OUT/base"
trap 'git -C "$ROOT" worktree remove --force "$OLD" >/dev/null 2>&1 || true; rm -rf "$OUT"' EXIT
git -C "$ROOT" worktree add -q --detach "$OLD" "$BASE"
# the base runs this tree's replay and harness (the driver is the measuring tool; only the CLI under test differs)
( TEMPER_E2E_ROOT="$OLD" bun "$HERE/replay.ts" base | tail -1 > "$OUT/base.json" ) &
( bun "$HERE/replay.ts" this | tail -1 > "$OUT/this.json" ) &
wait
CMP=0
python3 -I "$HERE/replay_compare.py" "$OUT/base.json" "$OUT/this.json" || CMP=$?
# 9.8.5 (WP05): the harness of this tree must still drive the CLI of the base to the numbers recorded for it. When the
# base is 10e965a, its column is held against the entry replay_base of scripts/e2e/floor.json, and a difference fails.
if [[ "$(git -C "$ROOT" rev-parse --verify --quiet "$BASE^{commit}")" == "$(git -C "$ROOT" rev-parse --verify --quiet "10e965a^{commit}")" ]]; then
  python3 -I "$ROOT/scripts/check_floor.py" --replay-base "$OUT/base.json"
fi
# a wrong call of the compare (exit 2) fails in every mode; a worse number fails only without --base-only
if [[ "$CMP" -eq 2 || ( "$CMP" -ne 0 && "$BASE_ONLY" -eq 0 ) ]]; then
  exit "$CMP"
fi
[[ "$CMP" -eq 0 ]] || echo "ab-replay.sh: --base-only: the compare against the base is printed above and not returned"
