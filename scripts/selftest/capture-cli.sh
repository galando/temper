#!/usr/bin/env bash
# capture-cli.sh: the output of the temper CLI in every state the fixture generator makes, to compare a refactor of the
# CLI with the tree before it. Not a case: run it before a change and after, with folders outside the repository, and
# compare them with `diff -r BEFORE AFTER`.
#
#   bash scripts/selftest/capture-cli.sh OUT_DIR
#
# It runs scripts/selftest/make-view-fixtures.sh with TEMPER_CAPTURE_DIR=OUT_DIR: each state of a run it makes is copied,
# and in the copy a fixed list of calls runs (reads, every gate, then one call for each writer). OUT_DIR/<state>.txt
# holds each call, its exit code and its two outputs, then the name and the text of every file under .temper of the
# copy, with the plugin folder, the project folder, commit ids, run ids and times replaced by fixed text. Compare only
# captures made on the same machine: a gate runs the fixture's commands.
set -euo pipefail
unset CDPATH
[[ $# -eq 1 && -n "$1" ]] || { echo "usage: bash scripts/selftest/capture-cli.sh OUT_DIR" >&2; exit 2; }
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$1"
OUT="$(cd -P "$1" && pwd)"
TEMPER_CAPTURE_DIR="$OUT" bash "$HERE/make-view-fixtures.sh" > "$OUT/view-fixtures.out"
echo "capture-cli: $(find "$OUT" -name '*.txt' | wc -l) states in $OUT"
