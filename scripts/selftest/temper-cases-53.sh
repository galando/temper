# Case file 53 (WP12): the approval is bound to what was shown. The approving calls carry the digests of intent.md and
# tasks.md as the question showed them (--shown intent.md=<H1> --shown tasks.md=<H2>), computed by scripts/approval.py,
# and the CLI refuses them when a file changed since. The advance records intent_hash beside plan_hash; a later change
# to either file fails the row `intent unchanged since the approval` of the Build, Check and commit gates until the
# person approves again. Before the approval a run makes no branch and no commit, and with the mod off the commit hook
# and the classic hook scripts/guards/hold_before_approval.py hold rule 1. Sourced by test-temper.sh; its helpers
# (fresh, gpass, _at, _unattended) are used here, and the builders below are this file's own. A digest is always
# computed by scripts/approval.py, never held as text. A call the CLI does not have yet stays inside $( ... ) or ends
# in || true, so the file always runs to its end.

# --- the helpers of this file ---
_ROW53="intent unchanged since the approval"
_x53() { # _x53 <python code over d, the JSON of temper next (or of the second argument)>: prints r. opts(d) is every
         # option of the question and of its More questions, opt(d, i) the one with that id, short(c) a call without
         # the path of the CLI
  python3 -B - "$1" "${2:-$("$TEMPER" next --json 2>/dev/null)}" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def opts(d):
    out, q = [], d.get("ask") or {}
    while isinstance(q, dict) and q:
        out += list(q.get("options") or [])
        q = q.get("more")
    return out
def opt(d, i):
    return next((o for o in opts(d) if o.get("id") == i), None)
def short(c):
    return re.sub(r"^\S*/temper ", "", str(c))
r = None
exec(sys.argv[1])
print(r)
PY
}
_repo53() { # a git repository under the run: one source file in one commit on master, the run's files left out
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh
  git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_dg53() { # _dg53 <file>: the digest scripts/approval.py makes of it, or nothing
  python3 -B "$REPO_ROOT/scripts/approval.py" digest "$1" 2>/dev/null
}
_calls53() { # _calls53 <option id>: the calls of that option of the question next asks, one a line
  _x53 "o = opt(d, '$1'); r = '\n'.join((o or {}).get('calls') or [])"
}
_run53() { # _run53 <option id>: runs the calls of that option as the session would, stopping at the first that fails
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    bash -c "$c" >/dev/null 2>&1 || break
  done < <(_calls53 "$1")
}
_tail53() { # _tail53 <option id>: "ok" when the last call of the option ends in the two --shown arguments of the
            # digests scripts/approval.py makes of the files now, else what it ends in
  local h1 h2 last
  h1="$(_dg53 .temper/specs/demo/intent.md)"; h2="$(_dg53 .temper/specs/demo/tasks.md)"
  last="$(_calls53 "$1" | tail -n 1)"
  if [[ -n "$h1" && -n "$h2" && "$h1" != "$h2" && "$last" == *" --shown intent.md=$h1 --shown tasks.md=$h2" ]]; then
    echo ok
  else
    echo "no digests (${last##*/temper })"
  fi
}
_row53() { # _row53 <stage>: pass and detail of the row of the stage's verdict in gates.json, or absent
  python3 -B - "$1" "$_ROW53" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    e = {}
r = next((x for x in e.get("requirements") or [] if x.get("name") == sys.argv[2]), None)
print("absent" if r is None else "%s:%s" % (r.get("pass"), r.get("detail")))
PY
}
_gate53() { # _gate53 <stage>: the run moved to the stage, its gate run, then the pass of the row and whether its detail
            # names intent.md or tasks.md
  local row; _at "$1"; "$TEMPER" gate "$1" >/dev/null 2>&1; row="$(_row53 "$1")"
  echo "${row%%:*}$([[ "$row" == *intent.md* ]] && echo ",intent.md")$([[ "$row" == *tasks.md* ]] && echo ",tasks.md")"
}
_work53() { # WP13: runs the calls of the action next gives when it is a work with no agents (the run leaves Intent by rule)
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    bash -c "$c" >/dev/null 2>&1 || break
  done < <(_x53 "r = '\n'.join(d.get('calls') or []) if d.get('action') == 'work' and not d.get('agents') else ''")
}
_intent53() { # a fresh run in a repository at Plan, left Intent by rule (WP13: the CLI's own work, its one advance)
  fresh; _repo53; gpass intent; _work53; gpass plan
}
_approved53() { # _approved53 [option id]: an approved run at Build, from the approval's own calls (ask-every-stage)
  _intent53; _run53 "${1:-ask-every-stage}"
}
_criterion53() { sed -i "s/demo criterion one/demo criterion one, $1/" .temper/specs/demo/intent.md; }
_hashes53() { # "ok" when the state's intent_hash and plan_hash are the digests scripts/approval.py makes of the files
  local h1 h2; h1="$(_dg53 .temper/specs/demo/intent.md)"; h2="$(_dg53 .temper/specs/demo/tasks.md)"
  if [[ -n "$h1" && -n "$h2" && "$("$TEMPER" state get intent_hash 2>/dev/null)" == "$h1" \
    && "$("$TEMPER" state get plan_hash 2>/dev/null)" == "$h2" ]]; then echo ok; else echo "no"; fi
}

# --- the approving options carry both digests, at the plan question and at the Design question ---
_intent53
assert_eq "bound: the approving options carry both digests in their last call, approve-run and ask-every-stage" \
  "approve-run=ok|ask-every-stage=ok" "approve-run=$(_tail53 approve-run)|ask-every-stage=$(_tail53 ask-every-stage)"
_intent53; _run53 run-design; gpass design
_d53_tails="approve-run=$(_tail53 approve-run)|ask-every-stage=$(_tail53 ask-every-stage)"
_d53_calls="$(_calls53 ask-every-stage)"
_criterion53 "changed after the Design question was built"
_d53_adv=""
while IFS= read -r _c; do
  [[ -n "$_c" ]] || continue
  bash -c "$_c" >/dev/null 2>&1; _rc=$?
  # the first call (the run's mode, with the digests shown) compares them before anything is written (WP12)
  [[ $_rc -eq 0 ]] || { _d53_adv="${_c##*/temper }"; _d53_adv="${_d53_adv%% --shown *},$_rc"; break; }
done <<<"$_d53_calls"
assert_eq "bound: the approving options carry both digests at the Design question; a stale digest is refused there" \
  "approve-run=ok|ask-every-stage=ok|refused=state set run_mode interactive,1|at=design" \
  "$_d53_tails|refused=${_d53_adv:-not run}|at=$("$TEMPER" state get next_stage 2>/dev/null)"

# --- a stale digest is refused and nothing advances: no branch and no commit are made by the refused advance ---
_intent53
_s53_calls="$(_calls53 ask-every-stage)"
_criterion53 "changed after the question was built"
_s53_adv=""
# HEAD and the branches before the option's first call: no call of a refused approval makes a branch or a commit
_s53_head="$(git rev-parse HEAD)"; _s53_br="$(git rev-parse --abbrev-ref HEAD),$(git branch --list | wc -l)"
while IFS= read -r _c; do
  [[ -n "$_c" ]] || continue
  bash -c "$_c" >/dev/null 2>&1; _rc=$?
  [[ $_rc -eq 0 ]] || { _s53_adv="${_c##*/temper }"; _s53_adv="${_s53_adv%% --shown *},$_rc"; break; }
done <<<"$_s53_calls"
assert_eq "bound: a stale digest is refused and nothing advances: exit 1, at Plan, no branch and no commit by it" \
  "refused=state set run_mode interactive,1|at=plan|head=same|branch=same" \
  "refused=${_s53_adv:-not run}|at=$("$TEMPER" state get next_stage 2>/dev/null)|head=$(
    [[ -n "$_s53_head" && "$(git rev-parse HEAD)" == "$_s53_head" ]] && echo same || echo moved)|branch=$(
    [[ -n "$_s53_br" && "$(git rev-parse --abbrev-ref HEAD),$(git branch --list | wc -l)" == "$_s53_br" ]] \
    && echo same || echo moved)"

# --- the binding check runs first: a stale approval writes no run_mode, makes no branch and no commit (rules 1, 2) ---
_f53=""
for _o53 in approve-run ask-every-stage run-design; do
  _intent53
  _f53_calls="$(_calls53 "$_o53")"
  _criterion53 "changed after the question was built"
  _f53_head="$(git rev-parse HEAD)"; _f53_br="$(git rev-parse --abbrev-ref HEAD),$(git branch --list | wc -l)"
  _f53_ran=""
  while IFS= read -r _c; do
    [[ -n "$_c" ]] || continue
    bash -c "$_c" >/dev/null 2>&1 || break
    _f53_ran+="${_c##*/temper };"
  done <<<"$_f53_calls"
  _f53+="${_f53:+|}$_o53=$([[ "$_f53_ran" =~ run_mode|spec\ branch|spec\ commit|checkout ]] && echo "written first" \
    || echo "checked first"),$("$TEMPER" state get next_stage 2>/dev/null),$("$TEMPER" state get run_mode interactive \
    2>/dev/null),head=$([[ "$(git rev-parse HEAD)" == "$_f53_head" ]] && echo same || echo moved),branch=$(
    [[ "$(git rev-parse --abbrev-ref HEAD),$(git branch --list | wc -l)" == "$_f53_br" ]] && echo same || echo moved)"
done
_f53_want=""
for _o53 in approve-run ask-every-stage run-design; do
  _f53_want+="${_f53_want:+|}$_o53=checked first,plan,interactive,head=same,branch=same"
done
assert_eq "bound: a stale approval is refused before any run_mode, branch or commit is written, for each option" \
  "$_f53_want" "$_f53"

# --- the advance records intent_hash beside plan_hash, with the approving calls and with a bare advance ---
_approved53; _h53_shown="$(_hashes53)"
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
"$TEMPER" state advance plan_complete build >/dev/null 2>&1; _h53_bare="$(_hashes53)"
assert_eq "bound: the advance records intent_hash beside plan_hash, also when no --shown was given" \
  "shown=ok|bare=ok" "shown=$_h53_shown|bare=$_h53_bare"

# --- state set refuses intent_hash ---
fresh; gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
assert_eq "bound: state set refuses intent_hash" "refused|not written" \
  "$("$TEMPER" state set intent_hash abc >/dev/null 2>&1 && echo taken || echo refused)|$(
    [[ "$("$TEMPER" state get intent_hash 2>/dev/null)" == abc ]] && echo written || echo "not written")"

# --- a changed criterion fails the Build, Check and commit gates, three assertions on the row ---
_approved53; _criterion53 "changed after the approval"
assert_eq "bound: a changed criterion fails the Build gate on the row intent unchanged since the approval" \
  "False,intent.md" "$(_gate53 build)"
assert_eq "bound: a changed criterion fails the Check gate on the row intent unchanged since the approval" \
  "False,intent.md" "$(_gate53 check)"
assert_eq "bound: a changed criterion fails the commit gate on the row intent unchanged since the approval" \
  "False,intent.md" "$(_gate53 commit)"

# --- the CLI's own lines are exempt: intent accept and intent complete leave the row passing ---
_approved53
sed -i 's/^\*\*Status:\*\* accepted/**Status:** draft/' .temper/specs/demo/intent.md   # a Status line is the CLI's own
"$TEMPER" intent accept >/dev/null 2>&1; _o53_acc="$(grep -c '^\*\*Accepted-by:\*\*' .temper/specs/demo/intent.md)"
"$TEMPER" intent complete >/dev/null 2>&1; _o53_cmp="$(grep -c '^\*\*Completed:\*\*' .temper/specs/demo/intent.md)"
assert_eq "bound: the CLI's own lines are exempt: intent accept and intent complete leave the row passing" \
  "accepted-by=1|completed=1|build=True|check=True|commit=True" \
  "accepted-by=$_o53_acc|completed=$_o53_cmp|build=$(_gate53 build)|check=$(_gate53 check)|commit=$(_gate53 commit)"

# --- a changed Test line of tasks.md fails the three gates too, and the detail names tasks.md ---
_approved53; sed -i 's|^\*\*Test:\*\* `true`|**Test:** `true; true`|' .temper/specs/demo/tasks.md
assert_eq "bound: a changed Test line of tasks.md fails the three gates too, and the detail names tasks.md" \
  "build=False,tasks.md|check=False,tasks.md|commit=False,tasks.md" \
  "build=$(_gate53 build)|check=$(_gate53 check)|commit=$(_gate53 commit)"

# --- a run with no recorded digest passes the row (a run saved by 9.8.4 or by the base) ---
_approved53
python3 -B - <<'PY'
import json
p = ".temper/build-state.json"
d = json.load(open(p))
d.pop("intent_hash", None)
json.dump(d, open(p, "w"), indent=2)
PY
_criterion53 "changed in a run saved before WP12"
assert_eq "bound: a run with no recorded digest passes the row" "build=True|check=True" \
  "build=$(_gate53 build)|check=$(_gate53 check)"

# --- a step back to Plan and a new approval record the new digests ---
_approved53; _criterion53 "changed after the approval"
_b53_before="$(_gate53 build)"
_at build; "$TEMPER" state loop build plan --reason 'the criterion changed' >/dev/null 2>&1; gpass plan
_b53_tail="$(_tail53 ask-every-stage)"; _run53 ask-every-stage
assert_eq "bound: a step back to Plan and a new approval record the new digests" \
  "before=False,intent.md|shown=ok|at=build|hashes=ok|after=True" \
  "before=$_b53_before|shown=$_b53_tail|at=$("$TEMPER" state get next_stage 2>/dev/null)|hashes=$(_hashes53)|after=$(
    _gate53 build)"

# --- an unattended run stops at the failed row: next is the park call, never a loop back ---
# The real Build gate computes the row; only that row is kept, so the stop is the row's and no other row's.
_approved53 approve-run; _criterion53 "changed after the approval"
"$TEMPER" gate build >/dev/null 2>&1
python3 -B - "$_ROW53" <<'PY'
import json, sys
p = ".temper/gates.json"
g = json.load(open(p))
rows = [x for x in (g.get("build") or {}).get("requirements") or [] if x.get("name") == sys.argv[1]]
if rows:
    g["build"] = {"verdict": "FAIL", "requirements": rows}
json.dump(g, open(p, "w"))
PY
assert_eq "bound: an unattended run stops at the failed row: next is the park call, never a loop back" \
  "mode=autonomous|auto|park|names the row|no loop" \
  "mode=$("$TEMPER" state get run_mode 2>/dev/null)|$(_x53 "c = [short(x) for x in d.get('calls') or []]
park = c and all(x.startswith('park ') and '--end' not in x for x in c)
r = '|'.join([str(d.get('action')), 'park' if park else 'calls: ' + '; '.join(c)[:120],
    'names the row' if any('$_ROW53' in x for x in c) else 'names no row',
    'loop' if any('state loop' in x for x in c) else 'no loop'])")"

# --- leaving Intent makes no branch and no commit ---
fresh; _repo53; gpass intent
_i53_head="$(git rev-parse HEAD)"
_i53_calls="$(_x53 "cs = ' '.join(d.get('calls') or [])   # WP13: the rule's own work
r = 'branch=%s|commit=%s' % ('yes' if 'spec branch' in cs else 'no',
    'yes' if 'spec commit' in cs or 'git commit' in cs else 'no')")"
_work53
assert_eq "bound: leaving Intent makes no branch and no commit" "branch=no|commit=no|head=same|on=master|at=plan" \
  "$_i53_calls|head=$([[ "$(git rev-parse HEAD)" == "$_i53_head" ]] && echo same || echo moved)|on=$(
    git rev-parse --abbrev-ref HEAD)|at=$("$TEMPER" state get next_stage 2>/dev/null)"

# --- the approval makes the branch and one commit: spec branch, then one spec commit, then the advance ---
_intent53
_a53_order="$(_x53 "c = [short(x) for x in (opt(d, 'ask-every-stage') or {}).get('calls') or []]
keep = ('spec branch', 'spec commit', 'state advance plan_complete')
k = [('branch' if x.startswith('spec branch') else 'commit' if x.startswith('spec commit') else 'advance')
     for x in c if x.startswith(keep)]
r = ','.join(k) or 'none'")"
_a53_n="$(git rev-list --count HEAD)"; _a53_master="$(git rev-parse master)"
_run53 ask-every-stage
_a53="order=$_a53_order|commits=$(( $(git rev-list --count HEAD) - _a53_n ))|on=$(git rev-parse --abbrev-ref HEAD)"
_a53+="|master=$([[ "$(git rev-parse master)" == "$_a53_master" ]] && echo same || echo moved)"
_a53+="|at=$("$TEMPER" state get next_stage 2>/dev/null)"
assert_eq "bound: the approval makes the branch and one commit, on the run's branch" \
  "order=branch,commit,advance|commits=1|on=feature/demo|master=same|at=build" "$_a53"

# --- with the mod off a project file cannot be committed before the approval: the commit hook refuses it ---
fresh; _repo53; bash "$REPO_ROOT/scripts/guards/install.sh" >/dev/null 2>&1
gpass intent; _work53
echo 'echo early' > src/early.sh; git add src/early.sh >/dev/null 2>&1
assert_eq "bound: with the mod off a project file cannot be committed before the approval" \
  "at=plan|on=master|refused|1" \
  "at=$("$TEMPER" state get next_stage 2>/dev/null)|on=$(git rev-parse --abbrev-ref HEAD)|$(
    git commit -q -m early >/dev/null 2>&1 && echo committed || echo refused)|$(
    git rev-list --count HEAD)"
git reset -q 2>/dev/null; rm -f src/early.sh; git config --unset core.hooksPath 2>/dev/null

# --- with the mod off a project file cannot be written before the approval: hold_before_approval.py ---
_hw53() { # _hw53 <cwd> <tool> <path or command> [raw input]: deny when the hook prints one JSON answer whose
          # decision is deny, with a reason, and exits 0; none when it prints nothing and exits 0; else what it did
  local in out rc
  if [[ -n "${4:-}" ]]; then
    in="$4"
  else
    in="$(python3 -B -c 'import json, sys
cwd, tool, arg = sys.argv[1:4]
ti = {"command": arg} if tool == "Bash" else {"file_path": arg, "content": "x\n"}
print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": tool, "cwd": cwd, "tool_input": ti}))' "$1" "$2" "$3")"
  fi
  out="$(printf '%s' "$in" | (cd "$1" && python3 -I "$REPO_ROOT/scripts/guards/hold_before_approval.py") 2>/dev/null)"
  rc=$?
  if [[ $rc -eq 0 && -z "$out" ]]; then echo none; return; fi
  python3 -B -c 'import json, sys
try:
    lines = [l for l in sys.argv[1].splitlines() if l.strip()]
    h = json.loads(sys.argv[1])["hookSpecificOutput"]
    ok = len(lines) == 1 and h["permissionDecision"] == "deny" and bool(h.get("permissionDecisionReason"))
    ok = ok and sys.argv[2] == "0"
    print("deny" if ok else "rc=%s" % sys.argv[2])
except Exception:
    print("rc=%s:%s" % (sys.argv[2], sys.argv[1][:60]))' "$out" "$rc"
}
fresh; gpass intent; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
_w53="plan=$(_hw53 "$WORKDIR" Write "$WORKDIR/src/demo.sh")"
_w53+="|spec=$(_hw53 "$WORKDIR" Write "$WORKDIR/.temper/specs/demo/plan.md")"
_w53+="|bash=$(_hw53 "$WORKDIR" Bash "echo x > $WORKDIR/src/demo.sh")"
_w53+="|unreadable=$(_hw53 "$WORKDIR" Write "" 'not json {')"
_np53="$(mktemp -d)"
_w53+="|no project=$(_hw53 "$_np53" Write "$_np53/src/demo.sh")"
rm -rf "$_np53"
gpass plan; "$TEMPER" state advance plan_complete build >/dev/null 2>&1
_w53+="|build=$(_hw53 "$WORKDIR" Write "$WORKDIR/src/demo.sh")"
fresh; "$TEMPER" state init bug --command fix >/dev/null 2>&1
_w53+="|fix=$(_hw53 "$WORKDIR" Write "$WORKDIR/src/demo.sh")"
fresh; rm -f .temper/build-state.json
_w53+="|no run=$(_hw53 "$WORKDIR" Write "$WORKDIR/src/demo.sh")"
assert_eq "bound: with the mod off a project file cannot be written before the approval: the classic hook refuses it" \
  "plan=deny|spec=none|bash=none|unreadable=none|no project=none|build=none|fix=none|no run=none" "$_w53"
