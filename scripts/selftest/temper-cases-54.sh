# Case file 54 (WP13): the run leaves Intent by rule; the approval accepts the intent. A passed Intent gate with an
# intent.md and nothing open is a `work` action of the CLI with the one call `state advance intent_complete plan`; the
# person accepts the intent with the plan, in one click (`intent accept --digest <H1>` among the approval's calls). The
# Intent question stays when the gate failed or was skipped, intent.md is missing, a Blocking question is open, the run
# came back to Intent, the person typed a note at Intent, or a door walked Intent: each case below holds the clean run
# beside it, so it shows the condition is what keeps the question. The Context check asks nothing for a clean map, and
# a flagged map whose lines fit the approval is folded into it. Sourced by test-temper.sh; its helpers (fresh, gpass,
# gfail) are used here, and the builders below are this file's own. The intent of the fixture is accepted, so a case
# that needs a draft sets the Status first. A digest is computed by scripts/approval.py, never held as text.

# --- the helpers of this file ---
_x54() { # _x54 <python code over d, the JSON of temper next>: prints r. opts(d) is every option of the question and of
         # its More questions, more(d) the options of its More questions only, opt(d, i) the one with that id, short(c)
         # a call without the path of the CLI
  python3 -B - "$1" "$("$TEMPER" next --json 2>/dev/null)" <<'PY'
import json, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
def chain(q):
    out = []
    while isinstance(q, dict) and q:
        out.append(q)
        q = q.get("more")
    return out
def opts(d):
    return [o for q in chain(d.get("ask") or {}) for o in q.get("options") or []]
def more(d):
    return [o for q in chain(d.get("ask") or {})[1:] for o in q.get("options") or []]
def opt(d, i):
    return next((o for o in opts(d) if o.get("id") == i), None)
def short(c):
    return re.sub(r"^\S*/temper ", "", str(c))
r = None
exec(sys.argv[1])
print(r)
PY
}
_repo54() { # a git repository under the run: one source file in one commit on master, the run's files left out
  rm -rf .git src; git init -q . 2>/dev/null; git checkout -q -B master 2>/dev/null
  git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh
  git add -A -- . ':(exclude).temper' ':(exclude).claude'; git commit -q -m base
}
_dg54() { python3 -B "$REPO_ROOT/scripts/approval.py" digest "$1" 2>/dev/null; }   # _dg54 <file>: its digest
_draft54() { sed -i 's/^\*\*Status:\*\* accepted/**Status:** draft/' .temper/specs/demo/intent.md; }
_status54() { sed -n 's/^\*\*Status:\*\* *//p' .temper/specs/demo/intent.md | head -n 1; }
_at54() { "$TEMPER" state get next_stage 2>/dev/null; }
_calls54() { # _calls54 <option id>: the calls of that option of the question next asks, one a line
  _x54 "o = opt(d, '$1'); r = '\n'.join((o or {}).get('calls') or [])"
}
_run54() { # _run54 <option id>: runs the calls of that option as the session would ({reason} filled), stopping at the
           # first that fails
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    c="${c//\{reason\}/the person gave a reason}"
    bash -c "$c" >/dev/null 2>&1 || break
  done < <(_calls54 "$1")
}
_work54() { # runs the calls of the action next gives when it is a work with no agents, as temper go runs it
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    bash -c "$c" >/dev/null 2>&1 || break
  done < <(_x54 "r = '\n'.join(d.get('calls') or []) if d.get('action') == 'work' and not d.get('agents') else ''")
}
_how54() { # what next does at Intent: `work` for the rule's move (a work with no agents and the one advance), else
           # ask:<question id>, else the action and its calls
  _x54 "c = [short(x) for x in d.get('calls') or []]
if d.get('action') == 'work' and not d.get('agents') and c == ['state advance intent_complete plan']:
    r = 'work'
elif d.get('action') == 'ask':
    r = 'ask:%s' % (d.get('ask') or {}).get('id')
else:
    r = '%s:%s' % (d.get('action'), ';'.join(c))"
}
_plan54() { "$TEMPER" state advance intent_complete plan >/dev/null 2>&1; }   # the run moved on to Plan by hand
_row54() { # _row54 <stage> <row name>: pass and detail of that row of the stage's verdict in gates.json, or absent
  python3 -B - "$1" "$2" <<'PY'
import json, sys
try:
    e = json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}
except (OSError, ValueError):
    e = {}
r = next((x for x in e.get("requirements") or [] if x.get("name") == sys.argv[2]), None)
print("absent" if r is None else "%s:%s" % (r.get("pass"), r.get("detail")))
PY
}
_verdict54() { # _verdict54 <stage>: the verdict of the stage in gates.json
  python3 -B -c 'import json, sys
try:
    print((json.load(open(".temper/gates.json")).get(sys.argv[1]) or {}).get("verdict"))
except (OSError, ValueError):
    print(None)' "$1"
}

# --- the clean run: a passed Intent with nothing open is work, not a question ---
fresh; gpass intent
_c54_next="$(_x54 "c = [short(x) for x in d.get('calls') or []]
r = 'action=%s|stage=%s|agents=%d|calls=%s' % (d.get('action'), d.get('stage'), len(d.get('agents') or []),
    ';'.join(c))")"
_clean54="$(_how54)"
_work54
assert_eq "intent rule: a passed Intent with nothing open is work, not a question" \
  "action=work|stage=intent|agents=0|calls=state advance intent_complete plan|then=plan" "$_c54_next|then=$(_at54)"

# --- the six conditions of the rule: each keeps the Intent question, beside the clean run that moves on ---
fresh; gfail intent "header fields" "missing, empty, or placeholder: Author"; _s54_failed="$(_how54)"
"$TEMPER" override intent --reason 'the author is known' >/dev/null 2>&1; _s54_skipped="$(_how54)"
assert_eq "intent rule: the question stays when the gate failed or was skipped" \
  "clean=work|failed=ask:intent.fail|skipped=ask:intent.accept" \
  "clean=$_clean54|failed=$_s54_failed|skipped=$_s54_skipped"

fresh; rm -f .temper/specs/demo/intent.md; gpass intent
assert_eq "intent rule: the question stays when intent.md is missing" \
  "clean=work|no intent.md=ask:intent.accept" "clean=$_clean54|no intent.md=$(_how54)"

_blocking54() { # a Blocking question under the Open Questions of the run's intent.md
  local q='- Blocking: Who may run the demo? choices: everyone | admins only'
  sed -i "s/^### Open Questions\$/### Open Questions\n$q/" .temper/specs/demo/intent.md
}
fresh; _blocking54; gpass intent
assert_eq "intent rule: the question stays when a Blocking question is open" \
  "clean=work|blocking=ask:intent.accept" "clean=$_clean54|blocking=$(_how54)"

fresh; gpass intent; _plan54; gpass plan
"$TEMPER" state loop plan intent --reason 'the scope is wrong' >/dev/null 2>&1
gpass intent   # the Intent agent returned and its gate passed again
assert_eq "intent rule: the question stays when the run came back to Intent" \
  "clean=work|came back=ask:intent.accept" "clean=$_clean54|came back=$(_how54)"

fresh; gpass intent
"$TEMPER" evidence add --stage intent --phase note --claim 'keep the demo to one screen' >/dev/null 2>&1
assert_eq "intent rule: the question stays when the person typed a note at Intent" \
  "clean=work|note=ask:intent.accept" "clean=$_clean54|note=$(_how54)"

# A door that walks Intent checks it and asks its own question (run.walked), as today.
fresh; "$TEMPER" state init demo --feature "the demo thing" --enter plan >/dev/null 2>&1; gpass intent
assert_eq "intent rule: the question stays when a door walked Intent" \
  "clean=work|door=ask:run.walked" "clean=$_clean54|door=$(_how54)"

# An answer to a Blocking question is no note: once the gate passes again the rule moves on (a trap of the spec).
fresh; _blocking54
"$TEMPER" intent answer 'Who may run the demo?' 'everyone' >/dev/null 2>&1
gpass intent
assert_eq "intent rule: an answered Blocking question is no note: the run leaves Intent by rule" \
  "answered=yes|work" \
  "answered=$(grep -q 'Who may run the demo? -> everyone' .temper/specs/demo/intent.md && echo yes \
    || echo no)|$(_how54)"

# --- after the rule the intent is still a draft: the person accepts it with the plan ---
fresh; _draft54; gpass intent; _work54
assert_eq "intent rule: after the rule the intent is still a draft" \
  "at=plan|status=draft|accepted-by=0" \
  "at=$(_at54)|status=$(_status54)|accepted-by=$(grep -c '^\*\*Accepted-by:\*\*' .temper/specs/demo/intent.md)"

# --- the approval accepts it: run_mode, the branch, the accept bound to the intent shown, one commit, the advance ---
fresh; _repo54; _draft54; gpass intent; _plan54; gpass plan
_a54_h1="$(_dg54 .temper/specs/demo/intent.md)"
_a54_order="$(_x54 "h1 = '$_a54_h1'
def kind(c):
    if c == 'state set run_mode autonomous':
        return 'mode'
    if c == 'spec branch':
        return 'branch'
    if c.startswith('intent accept'):
        return 'accept' if h1 and c == 'intent accept --digest %s' % h1 else 'accept(%s)' % c[14:30]
    if c.startswith('spec commit'):
        return 'commit'
    if c.startswith('state advance plan_complete'):
        return 'advance'
    return 'other(%s)' % c[:40]
r = ','.join(kind(short(x)) for x in (opt(d, 'approve-run') or {}).get('calls') or []) or 'no approve-run'")"
_a54_n="$(git rev-list --count HEAD)"
_run54 approve-run
_a54="order=$_a54_order|at=$(_at54)|status=$(_status54)"
_a54+="|by=$(sed -n 's/^\*\*Accepted-by:\*\* *//p' .temper/specs/demo/intent.md | head -n 1)"
_a54+="|commits=$(( $(git rev-list --count HEAD) - _a54_n ))|subject=$(git log -1 --format=%s)"
_a54_want="order=mode,branch,accept,commit,advance|at=build|status=accepted|by=the person, at the plan approval"
_a54_want+="|commits=1|subject=docs(plan): accept the intent and approve the plan of demo"
assert_eq "intent rule: the approval accepts it" "$_a54_want" "$_a54"

# --- a failed or skipped plan gate never accepts the intent ---
fresh; _draft54; gpass intent; _plan54; gfail plan "task test command" "Task 1 has no Test line"
_f54_h1="$(_dg54 .temper/specs/demo/intent.md)"
_f54_skip="$(_x54 "c = ' '.join(short(x) for x in (opt(d, 'override') or {}).get('calls') or [])
r = ('no skip' if not c else 'accepts' if 'intent accept' in c else 'advances' if 'state advance' in c
     else 'override only')")"
_run54 override
_f54_asked="$(_x54 "q = d.get('ask') or {}
c = [short(x) for x in ((q.get('options') or [{}])[0]).get('calls') or []]
r = '%s:%s|call=%s' % (d.get('stage'), q.get('id'),
    'ok' if c == ['intent accept --digest $_f54_h1'] else ';'.join(c)[:80])")"
_run54 "$(_x54 "r = ((d.get('ask') or {}).get('options') or [{}])[0].get('id')")"
_f54_then="$(_x54 "r = '%s|ask-every-stage=%s|approve-run=%s' % ((d.get('ask') or {}).get('id'),
    'present' if opt(d, 'ask-every-stage') else 'absent', 'present' if opt(d, 'approve-run') else 'absent')")"
_f54_want="skip=override only|asked=plan:intent.accept|call=ok|then=plan.approve|ask-every-stage=present"
_f54_want+="|approve-run=absent|status=accepted"
assert_eq "intent rule: a failed or skipped plan gate never accepts the intent" "$_f54_want" \
  "skip=$_f54_skip|asked=$_f54_asked|then=$_f54_then|status=$(_status54)"

# --- the approval offers a step back to Intent; it turns the mode off, and the Intent question is asked again ---
fresh; gpass intent; _plan54; gpass plan
"$TEMPER" state set run_mode autonomous >/dev/null 2>&1   # as an approval of an earlier round left it
_b54_back="$(_x54 "o = next((x for x in more(d) if x.get('id') == 'back'), None)
r = 'back=%s|in=%s' % ((o or {}).get('label'), 'more' if o else 'first' if opt(d, 'back') else 'none')")"
_run54 back
_b54_mode="$("$TEMPER" state get run_mode 2>/dev/null)"; _b54_at="$(_at54)"
gpass intent   # the Intent agent returned and its gate passed again
assert_eq "intent rule: the approval offers a step back to Intent" \
  "back=Loop back to Intent|in=more|mode=interactive|at=intent|asked=ask:intent.accept" \
  "$_b54_back|mode=$_b54_mode|at=$_b54_at|asked=$(_how54)"

# --- the Plan agent gets the request ---
fresh; gpass intent; _plan54
assert_eq "intent rule: the Plan agent gets the request" "temper:temper-plan|Feature: the demo thing." \
  "$(_x54 "a = (d.get('agents') or [{}])[0]
f = 'Feature: the demo thing.'
r = '%s|%s' % (a.get('type'), f if f in (a.get('prompt') or '').splitlines() else 'no Feature line')")"

# --- a draft with scenarios passes the Intent gate once tasks.md exists (Plan wrote them) ---
fresh; _draft54
cat >> .temper/specs/demo/intent.md <<'RULES'

### Rules covered
- Who: not applicable (the demo has one user)
- When: not applicable (the demo has no time window)
- How much: not applicable (the demo has no amount)
- Exempt: not applicable (the demo has no exemption)
- States: not applicable (the demo has one state)
- Where it shows: not applicable (the demo shows one line)
- Exceptions: not applicable (the demo has no exception)
RULES
mv .temper/specs/demo/tasks.md "$WORKDIR/.git/tasks.md.54"
"$TEMPER" gate intent >/dev/null 2>&1
_d54_without="$(_verdict54 intent),$(_row54 intent 'no scenarios in draft' | cut -d: -f1)"
mv "$WORKDIR/.git/tasks.md.54" .temper/specs/demo/tasks.md
"$TEMPER" gate intent >/dev/null 2>&1
_d54_with="$(_verdict54 intent),$(_row54 intent 'no scenarios in draft' | cut -d: -f1)"
assert_eq "intent rule: a draft with scenarios passes the Intent gate once tasks.md exists" \
  "without=FAIL,False|with=PASS,True" "without=$_d54_without|with=$_d54_with"

# --- the Context check: a clean map asks nothing, a flagged map that fits is folded into the approval ---
_USE54="- use: intent.md AC-01..AC-02 - the accepted scope"
_GAP54="no rate limit policy was found in code, docs or the ticket"
_IGN54=".temper/specs/old-login/ - a finished feature of another scope"
# Two gap lines at the cut of context_text (90 characters): the first is shown whole, the second (93, the longest a gap
# line can be under the map's own limit of 100 characters a line) is not.
_G90_54="no rate limit policy was found in the code, the docs, the ticket or the notes of a release"
_G93_54="no rate limit policy was found in the code, the docs, the ticket or the notes of the releases"
_map54() { # _map54 <entry line>...: plan.md with a Context Map of these entries, not yet reviewed, and the other
           # section the plan gate reads, so the map's row is the only one that can fail
  { printf '# Plan\n\n## Context Map\n'; printf '%s\n' "$@"; printf -- '- reviewed: pending\n\n## Approach\nThe demo.\n'
    printf '\n## Cross-Repo Search\n\n- not available: no cross-repo search tool is connected, '
    printf 'so local tools were used.\n'
  } > .temper/specs/demo/plan.md
}
_mapat54() { # _mapat54 <mode or ''> <entry line>...: a fresh run at Plan with that map under plan.context-check, its
             # gate run by the CLI
  local mode="$1"; shift
  fresh; gpass intent; _plan54
  [[ -n "$mode" ]] && printf 'plan:\n  context-check: %s\n' "$mode" >> .claude/temper.config
  _map54 "$@"
  "$TEMPER" gate plan >/dev/null 2>&1
}
_asked54() { # what the Context check does now: asked (the row fails and the check is in next), folded (the row passes,
             # no check, and both approving options answer it with plan review), not asked (the row passes, no check,
             # no plan review), else what was seen
  local row; row="$(_row54 plan 'context map reviewed')"
  _x54 "row = '''${row%%:*}'''
chk = bool(d.get('context_check'))
rev = [any('plan review --answer' in c for c in (opt(d, i) or {}).get('calls') or [])
       for i in ('approve-run', 'ask-every-stage')]
if row == 'False' and chk:
    r = 'asked'
elif row == 'True' and not chk and all(rev):
    r = 'folded'
elif row == 'True' and not chk and not any(rev):
    r = 'not asked'
else:
    r = 'row=%s,check=%s,review=%s' % (row, chk, rev)"
}

_mapat54 "" "$_USE54"
_k54_row="$(_row54 plan 'context map reviewed')"
_k54_next="$(_x54 "rev = any('plan review' in c for o in opts(d) for c in o.get('calls') or [])
r = 'check=%s|ask=%s|review call=%s' % ('none' if d.get('context_check') is None else 'asked',
    (d.get('ask') or {}).get('id'), 'yes' if rev else 'no')")"
_repo54; _run54 ask-every-stage
assert_eq "context: a clean pending map passes the row and asks nothing" \
  "row=True|not asked: no flagged line|check=none|ask=plan.approve|review call=no|reviewed=pending|at=build" \
  "row=${_k54_row%%:*}|$([[ "$_k54_row" == *"not asked: no flagged line"* ]] && echo "not asked: no flagged line" \
    || echo "${_k54_row#*:}")|$_k54_next|reviewed=$(sed -n 's/^- reviewed: *//p' .temper/specs/demo/plan.md)|at=$(
    _at54)"

# WP15, row D02b: the answer is recorded at the approval only when the context section of the approval card holds
# every flagged line whole. The card shows a line of any length the map allows, so the gap of 93 characters, which the
# question text cuts at 90, is folded too. For the most flagged lines a map holds (eleven, beside one use line), the
# Context check is asked exactly when the card's context section is cut.
_whole54() { # whole when the context section of the card of next holds each line of W54 (one a line) and is not cut
  _x54 "import os
card = d.get('card') if isinstance(d.get('card'), dict) else {}
sec = next((s for s in card.get('sections') or [] if isinstance(s, dict) and s.get('id') == 'context'), None)
rows = [str(x.get('text') or '') for x in (sec or {}).get('rows') or [] if isinstance(x, dict)]
want = [w for w in os.environ.get('W54', '').split(chr(10)) if w]
r = 'whole' if sec and (sec.get('total') or 0) <= len(rows) and all(any(w in x for x in rows) for w in want) else 'cut'"
}
_mapat54 "" "$_USE54" "- gap: $_G90_54"; _l54_90="$(_asked54)"
_mapat54 "" "$_USE54" "- gap: $_G93_54"; _l54_93="$(_asked54)"
_m54_lines=(); _m54_want=""
for _k in 1 2 3 4 5 6; do
  _m54_t="src/part-0$_k/ - a finished part of another scope, kept for its history and its own tests"
  _m54_lines+=("- ignore: $_m54_t"); _m54_want+="$_m54_t"$'\n'
done
for _k in 1 2 3 4 5; do
  _m54_t="no rule for case 0$_k was found in the code, the docs, the ticket or the notes of a release"
  _m54_lines+=("- gap: $_m54_t"); _m54_want+="$_m54_t"$'\n'
done
_mapat54 "" "$_USE54" "${_m54_lines[@]}"; _l54_many="$(_asked54)"; _w54_many="$(W54="$_m54_want" _whole54)"
case "$_l54_many:$_w54_many" in
  folded:whole|asked:cut) _l54_many=agrees ;;
  *) _l54_many="$_l54_many with a card that is $_w54_many" ;;
esac
assert_eq "context: a flagged line the map allows is folded when the card shows it whole; a cut card still asks" \
  "90=folded|93=folded|many=agrees" "90=$_l54_90|93=$_l54_93|many=$_l54_many"

_mapat54 "" "$_USE54" "- ignore: $_IGN54" "- gap: $_GAP54"
_k54_fold_row="$(_row54 plan 'context map reviewed')"
_k54_fold="$(_x54 "q = (d.get('ask') or {}).get('question') or {}
t = str(q.get('question') or '')
rev = [any(c.startswith('plan review --answer') for c in map(short, (opt(d, i) or {}).get('calls') or []))
       for i in ('approve-run', 'ask-every-stage')]
r = 'check=%s|ask=%s|text=%s|approve-run=%s|ask-every-stage=%s|include=%s' % (
    'none' if d.get('context_check') is None else 'asked', (d.get('ask') or {}).get('id'),
    'whole' if '''$_IGN54''' in t and '''$_GAP54''' in t else 'cut',
    'review' if rev[0] else 'no review', 'review' if rev[1] else 'no review',
    'more' if any(o.get('id') == 'include-left-out' for o in more(d)) else 'absent')")"
_repo54; _run54 ask-every-stage
_k54_answer="$(grep -q '^- answer: .*at the approval, 2 flagged lines shown' .temper/specs/demo/plan.md \
  && echo "at the approval, 2 flagged lines shown" || sed -n 's/^- answer: *//p' .temper/specs/demo/plan.md)"
_k54_want="row=True|2 flagged line(s), answered at the approval|check=none|ask=plan.approve|text=whole"
_k54_want+="|approve-run=review|ask-every-stage=review|include=more|reviewed=human"
_k54_want+="|answer=at the approval, 2 flagged lines shown|at=build"
assert_eq "context: a flagged map that fits is folded" "$_k54_want" \
  "row=${_k54_fold_row%%:*}|$([[ "$_k54_fold_row" == *"2 flagged line(s), answered at the approval"* ]] \
    && echo "2 flagged line(s), answered at the approval" || echo "${_k54_fold_row#*:}")|$_k54_fold|reviewed=$(
    sed -n 's/^- reviewed: *//p' .temper/specs/demo/plan.md)|answer=$_k54_answer|at=$(_at54)"

_mapat54 "" "$_USE54"; _k54_auto="$(_asked54)"
_mapat54 always "$_USE54"; _k54_always="$(_asked54)"
assert_eq "context: always still asks" "auto=not asked|always=asked" "auto=$_k54_auto|always=$_k54_always"

_mapat54 "" "$_USE54" "- gap: $_GAP54"; _k54_auto="$(_asked54)"
_mapat54 off "$_USE54" "- gap: $_GAP54"; _k54_off="$(_asked54)"
assert_eq "context: off never asks" "auto=folded|off=not asked" "auto=$_k54_auto|off=$_k54_off"
