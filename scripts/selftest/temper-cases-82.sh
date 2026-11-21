# Case file 82 (adversarial review 2): rules 3 and 4, every way an unattended run starts and ends, and the never list of
# rule 4 against what `temper next --json` hands an unattended run to run by itself. Sourced by test-temper.sh; its
# helpers (setup, fresh, gpass, riskH, _unattended, _base_known) are used here. Every assertion name starts with
# "review 2:". Options and questions are selected by id, never by label text.

# --- the helpers of this file ---
_x82() { # _x82 <python code over d, the JSON of temper next, that sets r>: prints r
  python3 - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def opts(d):
    a = d.get("ask") or {}
    return list(a.get("options") or []) + list((a.get("more") or {}).get("options") or [])
def opt(d, i):
    return next((o for o in opts(d) if o.get("id") == i), None)
r = None
exec(sys.argv[1])
print(r)
PY
}
# A call an unattended run may never make by itself (rule 4): a step back to Plan or Intent, a change of the plan, of a
# gate's command or of the intent, a skip, an accepted finding, a config write, a push, a pull request, the final commit
_FORBID82='state loop \S+ (plan|intent)|state redo plan|plan patch|override|evidence accept|acceptance (skip|reopen)|baseline (skip|accept-red)|intent (answer|carry)|doctor .*--write|config tidy|git push|gh pr|spec commit .* -- |git commit'
_stop82() { # "stop" when next is a question or a recorded stop (the park call) and no call the run makes by itself (an auto,
            # or a work: the session runs its calls with no question) matches _FORBID82; else what next does
  python3 - "$_FORBID82" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
bad = re.compile(sys.argv[1])
try:
    d = json.loads(sys.argv[2])
except ValueError:
    print("no next")
    sys.exit(0)
a = d.get("action")
calls = list(d.get("calls") or []) + [c for x in d.get("agents") or [] for c in (x.get("before") or []) + (x.get("after") or [])]
short = ",".join(re.sub(r"^\S*/temper ", "", c)[:60] for c in calls[:2])
if a in ("auto", "work") and any(bad.search(c) for c in calls):
    print("%s runs %s" % (a, short))
elif a == "ask" or (a == "auto" and calls and all(re.search(r"\spark\s", c) and "--end" not in c for c in calls)):
    print("stop")
else:
    print("%s %s" % (a, short))
PY
}
_mode82() { "$TEMPER" state get run_mode 2>/dev/null; }
_go82() { # runs the calls of next while it is an auto or a work with no agents (what the run does by itself), at most 8
  local i c cs
  for i in 1 2 3 4 5 6 7 8; do
    cs="$(_x82 "r = '\n'.join(d.get('calls') or []) if d.get('action') == 'auto' or (d.get('action') == 'work' and not d.get('agents')) else ''")"
    [[ -n "$cs" ]] || return 0
    while IFS= read -r c; do [[ -n "$c" ]] && bash -c "$c" >/dev/null 2>&1; done <<<"$cs"
  done
}

# --- review 2: rule 4, an unattended run never skips a check: the acceptance writer locked nothing in its launches ---
_unattended build
printf '{"spec": ".temper/specs/demo", "launches": 2}\n' > .temper/evidence/acceptance-lock.json
_r82_acc="mode=$(_mode82)|next=$(_stop82)"
"$TEMPER" go >/dev/null 2>&1   # temper go runs the calls of a work with no agents inside the CLI
_r82_acc+="|after-go=$(python3 -c 'import json; print("skipped" if json.load(open(".temper/evidence/acceptance-lock.json")).get("skipped") else "not skipped")'),$(_mode82)"
assert_eq "review 2: an unattended run whose acceptance writer locked nothing stops and asks; it never runs acceptance skip by itself" \
  "mode=autonomous|next=stop|after-go=not skipped,autonomous" "$_r82_acc"

# The skip is the person's option at that stop (its id override, the skip with a reason): it ends the unattended run.
while IFS= read -r _c82; do [[ -n "$_c82" ]] && bash -c "${_c82//\{reason\}/I accept the risk}" >/dev/null 2>&1; done \
  < <(_x82 "r = '\n'.join((opt(d, 'override') or {}).get('calls') or [])")
assert_eq "review 2: the person's skip of the acceptance tests at that stop is recorded and ends the unattended run" \
  "skipped,interactive" "$(python3 -c 'import json; print("skipped" if json.load(open(".temper/evidence/acceptance-lock.json")).get("skipped") else "not skipped")'),$(_mode82)"
