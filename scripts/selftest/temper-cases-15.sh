# Release 9.8.0: what the benchmark found and what it led to (docs/evidence/bench-2026-11.md): the CLI finds its project from
# a subfolder, and the 9.8.0 gates and flow below.
# Sourced by test-temper.sh after temper-cases-14.sh (helpers: nx, labels, gpass, gfail, setup, fresh, assert_eq, assert_exit).

# --- 1. Called from a subfolder, the CLI uses the project's .temper and never starts a second one ---
fresh
mkdir -p docs/decisions
assert_eq "9.8.0: temper called from docs/decisions reads the run of the project above it" "demo" \
  "$(cd docs/decisions && "$TEMPER" state get spec 2>/dev/null)"
(cd docs/decisions && "$TEMPER" state set complexity medium >/dev/null 2>&1)
assert_eq "9.8.0: and writes to it, never to docs/decisions/.temper" "medium|no" \
  "$("$TEMPER" state get complexity 2>/dev/null)|$([[ -d docs/decisions/.temper ]] && echo yes || echo no)"
