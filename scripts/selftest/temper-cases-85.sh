# Case file 85: review 5 of 9.8.5, rules 9 and 10 (every repeat is counted against one budget, only the person grants
# more; the commit question lists everything a rule decided since the approval). Sourced by test-temper.sh; its helpers
# (fresh, gpass, m_setup, f9_tasks) are used here. Each check below fails on the code it was written against: it is the
# reproduction of one finding of the review, not a row of done.md.
# A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
_used85() { # _used85 [key]: the entries of the budget record, of that key when given
  python3 - "${1:-}" <<'PY'
import json, sys
try:
    u = json.load(open(".temper/budget.json")).get("used") or []
except (OSError, ValueError, AttributeError):
    u = []
print(sum(1 for x in u if isinstance(x, dict) and (not sys.argv[1] or x.get("key") == sys.argv[1])))
PY
}
_log85() { # _log85 <ERE>: how many entries of the rule log (the record the commit card lists) match the ERE
  python3 - "$1" <<'PY'
import json, re, sys
try:
    e = json.load(open(".temper/rule-log.json"))
except (OSError, ValueError):
    e = []
print(sum(1 for x in e if isinstance(x, dict) and re.search(sys.argv[1], "%s %s" % (x.get("kind"), x.get("what")))))
PY
}
_next85() { # _next85: action, then the calls of temper next, each after the word temper
  "$TEMPER" next --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('action'), '|'.join(c.split('temper ', 1)[-1] for c in d.get('calls') or []))" 2>/dev/null
}
_armed85() { # _armed85 <gate JSON of G1>: an unattended run (started at the approval) at Build, one group G1 of one passed
             # task, the group's check as given
  fresh
  printf '%s\n' '# Tasks: demo' '' '**Integration:** `true`' '' '## Group G1: Core' '**Depends:** none' '**Validate:** `true`' \
    '**Context:**' 'x' '' '### Task 1: first' '**File:** `src/p1.sh`' '**Depends:** none' '**Test:** `true`' '**Cases:**' '- p' \
    '- [x] done' > .temper/specs/demo/tasks.md
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  "$TEMPER" state set run_mode autonomous >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
  python3 - "$1" <<'PY'
import json, sys
g = {"version": 1, "slug": "demo", "groups": {"G1": {"status": "running", "worktree": "w1", "branch": "temper/demo/G1",
     "fails": 1, "gate": json.loads(sys.argv[1])}}, "tasks": {"1": {"status": "passed", "group": "G1"}}}
json.dump(g, open(".temper/groups.json", "w"))
PY
}
_commit_card85() { # the unattended run walked on to its commit question (each later gate passed); prints the card's
                   # DECIDED BY RULE section, or "no commit question"
  local s
  for s in build:review review:check check:commit; do gpass "${s%%:*}"; "$TEMPER" state advance "${s%%:*}_complete" "${s##*:}" >/dev/null 2>&1; done
  "$TEMPER" gate commit >/dev/null 2>&1
  "$TEMPER" park --verdict SHIP-PENDING-COMMIT --reason 'every gate passed' >/dev/null 2>&1
  if [[ "$("$TEMPER" next --json 2>/dev/null | python3 -c "import json,sys; print((json.load(sys.stdin).get('ask') or {}).get('id'))" 2>/dev/null)" != commit.confirm ]]; then
    echo "no commit question"; return
  fi
  "$TEMPER" card 2>/dev/null | awk '/^DECIDED BY RULE/ {on=1} on && /^$/ {exit} on'
}
_listed85() { # _listed85 <card section>: yes when it names group G1, else no and the section on one line
  if grep -c 'G1' <<<"$1" >/dev/null; then echo yes; else echo "no: $(tr '\n' '/' <<<"$1")"; fi
}

# --- rule 9: a fix of a failed group check that no request paid for ---
# `group fix G --commit` is the after call of the fix agent the request `group fix G` launched (that request spends
# group:G). The CLI takes --commit with no request open: it commits what the worktree holds as its own commit
# (cli_commits, so integrate never calls it foreign), clears the group's failed check, and the next `group gate` checks
# it again. Each round is a fix and a check again after a failure, and none spends a repeat.
f9_tasks | m_setup
python3 - <<'PY'
import json
d = json.load(open(".temper/groups.json"))
for n in ("1", "2"):
    d.setdefault("tasks", {})[n] = {"status": "passed", "group": "G1"}
json.dump(d, open(".temper/groups.json", "w"))
p = ".temper/specs/demo/tasks.md"
text = open(p).read().replace("**Validate:** `true`", "**Validate:** `test -f src/fixed`")
open(p, "w").write(text)
for f in (".temper/groups.json", ".temper/build-state.json"):
    x = json.load(open(f)); x.pop("plan_hash", None); json.dump(x, open(f, "w"))
PY
"$TEMPER" group gate G1 >/dev/null 2>&1
_r9a_first="$(python3 -c "import json; print(((json.load(open('.temper/groups.json'))['groups']['G1'].get('gate') or {}).get('verdict')) or 'none')" 2>/dev/null)"
_wt85="$(python3 -c "import json; print(json.load(open('.temper/groups.json'))['groups']['G1']['worktree'])" 2>/dev/null)"
_ncli85() { python3 -c "import json; print(len(json.load(open('.temper/groups.json')).get('cli_commits') or []))" 2>/dev/null; }
_r9a_before="$(_ncli85)"
for _i in 1 2 3; do
  mkdir -p "$_wt85/src"; echo "echo try $_i" >> "$_wt85/src/a.sh"
  "$TEMPER" group fix G1 --commit >/dev/null 2>&1
  "$TEMPER" group gate G1 >/dev/null 2>&1
done
_r9a_rounds=$(( $(_ncli85) - _r9a_before ))
assert_eq "review 5: a fix of a failed group check committed by the CLI and checked again spends a repeat, or is refused when no fix was asked" \
  "check failed first=FAIL|fix commits of the CLI no repeat paid for=0" \
  "check failed first=$_r9a_first|fix commits of the CLI no repeat paid for=$(( _r9a_rounds - $(_used85 group:G1) ))"


# --- rule 10: the commit question lists what a rule decided at a failed group check ---
# A failed group check whose recommended option is "Run the group's tasks again": the unattended run takes it by rule
# (an `auto` action, one repeat of group:G1). `group reopen` writes no entry of the rule log, so the commit card shows
# "repeats of the budget used: 1 of 6" and no line that says what the rule did.
_armed85 '{"verdict": "FAIL", "reason": "uncommitted changes in the group worktree, not on its branch: src/p1.sh", "ran": false}'
_r10a_next="$(_next85)"
"$TEMPER" group reopen G1 --task 1 >/dev/null 2>&1; _r10a_rc=$?
_r10a_card="$(_commit_card85)"
assert_eq "review 5: the rule's run of a failed group's tasks again is listed on the commit card" \
  "rule's move=auto group reopen G1 --task 1|ran=0|spent=1|listed=yes" \
  "rule's move=$_r10a_next|ran=$_r10a_rc|spent=$(_used85 group:G1)|listed=$(_listed85 "$_r10a_card")"

# The first time out of a group's check: the CLI runs it again with twice the limit as its own `auto` call (one repeat of
# group:G1 when the base did not measure the suite). No entry of the rule log names it.
_armed85 '{"verdict": "FAIL", "reason": "group G1 Validate timed out after 600s: true", "ran": true, "timeout_s": 600}'
_r10b_next="$(_next85)"
"$TEMPER" group gate G1 --timeout-s 1200 >/dev/null 2>&1
_r10b_card="$(_commit_card85)"
assert_eq "review 5: the rule's run of a timed out group check with twice the limit is listed on the commit card" \
  "rule's move=auto group gate G1 --timeout-s 1200|spent=1|listed=yes" \
  "rule's move=$_r10b_next|spent=$(_used85 group:G1)|listed=$(_listed85 "$_r10b_card")"
