# Case file 91 (the CI runner's git, D45b): the spec commit carries the Temper identity when the machine has none.
# On CI (ubuntu-latest, no git identity anywhere: actions/checkout points HOME at a temp dir with only safe.directory)
# the third call of an approving answer, `temper spec commit`, died with "Author identity unknown" (pull 117, shard 4;
# the diagnostic pull 119), because scripts/spec_ops.py had no fallback of its own — scripts/temper's _git_id_args
# (WP12) never reached the python side the commit moved to in 9.8.0. A developer's global identity hides it locally.
# The case takes every identity away by hand — no local identity, HOME a fresh empty folder, both config files
# /dev/null, PATH only the system bin — and asks for the spec commit of an approved run on the run's branch.
_tasks91() {
  printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
    '**Context:**' 'The demo group.' '' '### Task 1: first task' '**File:** `src/demo.sh`, `src/demo_test.sh`' '**Depends:** none' \
    '**Test:** `true`' '**Cases:**' '- a holds' '- [x] done'
}
_tasks91 | m_setup
git config --local --unset user.email 2>/dev/null; git config --local --unset user.name 2>/dev/null
_H91="$(mktemp -d)"
_out91="$(env -i PATH=/usr/bin:/bin HOME="$_H91" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
  "$TEMPER" spec commit 'the approved intent and plan' 2>&1)"; _rc91=$?
assert_eq "91 D45b: the spec commit on a machine with no git identity still commits, as the Temper identity" \
  "0|OK|Temper <temper@localhost>" \
  "$_rc91|${_out91%%:*}|$(git log -1 --format='%an <%ae>' 2>/dev/null)"
rm -rf "$_H91"
