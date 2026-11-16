#!/usr/bin/env bash
# verify.sh: the one gate of a change to Temper, the same answer CI gives, from one command.
#
#   bash scripts/verify.sh quick [REV]   about 3 minutes, at the end of every package
#   bash scripts/verify.sh full          the whole suite, at the end of every phase (start it in the background)
#
# quick: the validators, the name check, the case files that differ from REV (run-selftest.sh --touched), and, only when
# what they cover changed since REV, the two fixture compares and one whole end to end run (a file under scripts outside
# scripts/selftest), and the mod's tests (a .ts or .tsx file); then the type check of the mod. REV defaults to HEAD when
# the work tree has changes and to HEAD~1 when it is clean.
# full: the validators, the name check, every case file in parallel (the fixture compares are in case file 8), the end
# to end suite in every mode as shards side by side (one per CPU, up to 4), the mod's tests, its manifest, its reviewed
# calls, the type check and the test of the directory rules.
#
# One line per step with its result and seconds, then `verify quick: PASS` or `FAIL` (or `full`). Exit 0 only when
# every step passed; another word exits 2. When the mod's types cannot be made here, the two fixture files are
# compiled alone and a line says the full type check is left to CI.
set -uo pipefail
unset CDPATH
# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts}"
[[ "$ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
USAGE="usage: bash scripts/verify.sh quick [REV] | full"
WORD="${1:-}"
case "$WORD" in
  quick|full) ;;
  *) echo "verify.sh: unknown word '$WORD'; the words are quick and full. $USAGE" >&2; exit 2 ;;
esac
[[ "$WORD" == full && $# -gt 1 ]] && { echo "verify.sh: full takes no REV. $USAGE" >&2; exit 2; }
cd "$ROOT" || exit 1

LOGS="$(mktemp -d)"; trap 'rm -rf "$LOGS"' EXIT
FAILED=0; N=0; T0=$SECONDS; BG=()
report() { # report <name> <exit> <seconds> <log>
  if [[ "$2" -eq 0 ]]; then
    printf 'PASS  %5d s  %s\n' "$3" "$1"
  else
    printf 'FAIL  %5d s  %s\n' "$3" "$1"
    tail -n 20 "$4" | sed 's/^/        /'
    FAILED=$((FAILED + 1))
  fi
}
skip() { printf 'SKIP  %5d s  %s\n' 0 "$1"; }
step() { # step <name> <command...>: runs the command in the plugin folder, then prints its line
  local name="$1" t rc; shift
  N=$((N + 1)); t=$SECONDS
  "$@" > "$LOGS/$N.log" 2>&1; rc=$?
  report "$name" "$rc" "$((SECONDS - t))" "$LOGS/$N.log"
}
bg_step() { # bg_step <name> <command...>: as step, started in the background; collect prints its line
  local name="$1"; shift
  N=$((N + 1))
  ( t=$SECONDS; "$@" > "$LOGS/$N.log" 2>&1; echo "$? $((SECONDS - t))" > "$LOGS/$N.rc" ) &
  BG+=("$N:$name")
}
collect() {
  local e n rc secs
  wait
  for e in "${BG[@]}"; do
    n="${e%%:*}"; read -r rc secs < "$LOGS/$n.rc" || { rc=1; secs=0; }
    report "${e#*:}" "$rc" "$secs" "$LOGS/$n.log"
  done
  BG=()
}

fixtures_first() { bash scripts/selftest/make-view-fixtures.sh | cmp - scripts/selftest/view-fixtures.ts; }
fixtures_extra() { bash scripts/selftest/make-view-fixtures.sh extra | cmp - scripts/selftest/view-fixtures-2.ts; }
TYPES=".claude-plugin/types/claude-code/index.d.ts"
make_types() { # a load of the plugin by the Claude Code version CI pins writes the mod's types (no key is needed)
  [[ -f "$TYPES" ]] && return 0
  timeout 120 npx -y -p @anthropic-ai/claude-code@2.1.287 claude -p "hi" --plugin-dir . \
    --debug-file "$LOGS/mod-debug.log" > /dev/null 2>&1 || true
  [[ -f "$TYPES" ]]
}
fixtures_alone() {
  local d rc
  d="$(mktemp -d)"
  cp scripts/selftest/view-fixtures.ts scripts/selftest/view-fixtures-2.ts "$d"
  (cd "$d" && npx -y -p typescript@5.6 tsc --noEmit --strict --target es2023 view-fixtures.ts view-fixtures-2.ts); rc=$?
  rm -rf "$d"
  return "$rc"
}
type_check() {
  if make_types; then
    step "type check of the mod (tsc 5.6, tsconfig.mod.json)" npx -y -p typescript@5.6 tsc -p tsconfig.mod.json
  else
    echo "NOTE  the mod's types could not be made here: the full type check is left to CI"
    step "type check of the two fixture files alone (tsc 5.6)" fixtures_alone
  fi
}

echo "=== verify.sh $WORD ($ROOT) ==="
step "validate-directory.sh" bash scripts/validate-directory.sh
step "quality-check.sh" bash scripts/quality-check.sh
step "validate-docs.sh" bash scripts/validate-docs.sh
step "validate-readme.sh" bash scripts/validate-readme.sh
step "validate-plugin.sh" bash scripts/validate-plugin.sh
step "validate-panels.py" python3 scripts/validate-panels.py
step "check-known-limits.sh" bash scripts/check-known-limits.sh
step "check-names.py (the tracked Python scripts)" python3 -I scripts/selftest/check-names.py

if [[ "$WORD" == quick ]]; then
  REV="${2:-}"
  if [[ -z "$REV" ]]; then
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then REV="HEAD"; else REV="HEAD~1"; fi
  fi
  git rev-parse --verify --quiet "$REV^{commit}" > /dev/null || { echo "verify.sh: no commit '$REV'. $USAGE" >&2; exit 2; }
  CHANGED="$( (git diff --name-only "$REV"; git ls-files --others --exclude-standard) 2>/dev/null | sort -u)"
  SCRIPTS=0; TS=0
  while IFS= read -r f; do
    case "$f" in scripts/selftest/*) ;; scripts/*) SCRIPTS=1 ;; esac
    case "$f" in *.ts|*.tsx) TS=1 ;; esac
  done <<< "$CHANGED"
  echo "      the files changed since $REV: $(printf '%s' "$CHANGED" | grep -c .)"
  # the selftest, the fixture compares and the end to end run are separate processes: they run side by side
  bg_step "selftest: run-selftest.sh --touched $REV" bash scripts/selftest/run-selftest.sh --touched "$REV"
  if [[ "$SCRIPTS" -eq 1 ]]; then
    bg_step "fixture compare: make-view-fixtures.sh and view-fixtures.ts" fixtures_first
    bg_step "fixture compare: make-view-fixtures.sh extra and view-fixtures-2.ts" fixtures_extra
    bg_step "end to end: run.ts both full-run" bun scripts/e2e/run.ts both full-run
  fi
  collect
  if [[ "$SCRIPTS" -eq 0 ]]; then
    skip "fixture compares and end to end (no file under scripts outside scripts/selftest changed)"
  fi
  if [[ "$TS" -eq 1 ]]; then
    step "claude plugin test ." claude plugin test .
    step "check-mod-calls.sh" bash scripts/check-mod-calls.sh
  else
    skip "the mod's tests (no .ts or .tsx file changed)"
  fi
  type_check
else
  step "selftest: run-selftest.sh (every case file, in parallel)" bash scripts/selftest/run-selftest.sh
  CPUS="$(nproc 2>/dev/null || echo 4)"
  [[ "$CPUS" =~ ^[1-9][0-9]*$ ]] || CPUS=4
  (( CPUS <= 4 )) || CPUS=4
  for k in $(seq 1 "$CPUS"); do
    bg_step "end to end: run.ts all --shard $k/$CPUS" bun scripts/e2e/run.ts all --shard "$k/$CPUS"
  done
  collect
  step "claude plugin test ." claude plugin test .
  step "claude plugin validate --strict ." claude plugin validate --strict .
  step "test-check-mod-calls.sh" bash scripts/selftest/test-check-mod-calls.sh
  step "check-mod-calls.sh" bash scripts/check-mod-calls.sh
  type_check
  step "test-validate-directory.sh" bash scripts/selftest/test-validate-directory.sh
fi

echo "      $((SECONDS - T0)) s in all"
if [[ "$FAILED" -eq 0 ]]; then
  echo "verify $WORD: PASS"
  exit 0
fi
echo "verify $WORD: FAIL"
exit 1
