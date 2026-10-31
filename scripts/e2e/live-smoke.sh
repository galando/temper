#!/usr/bin/env bash
# A live smoke of Temper with a real model: Claude Code runs headless with this plugin on a scratch project and is asked to start
# a run. It is OFF by default and never part of CI (no job sets a key or logs in): set TEMPER_E2E_LIVE=1 on a machine where
# Claude Code is already signed in. It reads no key, token or settings file; it only starts `claude` and looks at what it left.
set -uo pipefail
if [[ "${TEMPER_E2E_LIVE:-}" != "1" ]]; then
  echo "live smoke is off (set TEMPER_E2E_LIVE=1 on a machine where Claude Code is signed in)"
  exit 0
fi
command -v claude >/dev/null 2>&1 || { echo "FAIL: claude is not installed" >&2; exit 1; }
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="${HERE%/scripts/e2e}"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
cd "$SCRATCH" && git init -q . && git checkout -q -B main && echo "# scratch" > README.md && git add -A && git -c user.email=e2e@example.com -c user.name=e2e commit -qm base
OUT="$(timeout 600 claude -p "/temper:temper \"print hello\"" --plugin-dir "$PLUGIN" --permission-mode plan 2>&1)"; rc=$?
echo "$OUT" | tail -20
[[ -d .temper ]] && echo "OK: the run left a .temper folder" || { echo "FAIL: no run was started (exit $rc)"; exit 1; }
