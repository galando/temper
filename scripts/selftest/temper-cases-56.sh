# Case file 56 (WP15): the cards. Each question that decides (the approval, the commit, a stop) carries one card the
# CLI computes from files and ledgers: `card` of `temper next --json` and of .temper/view.json, the rows `temper card`
# prints and the `card` rows of `temper go`. A card is {kind, run_id, step, title, tag, sections [{id, title, note,
# rows [{text, mark}], total, file}], foot}; a section is cut when total is larger than the count of its rows, and file
# says where the rest is. A section with no source is left out, never filled with a guess; no card holds dollars, and a
# time is in minutes. Sourced by test-temper.sh; its helpers (fresh, setup, gpass, gfail, _at, _unattended,
# _ran_unattended) are used here, and the builders below are this file's own. A call the CLI does not have yet stays
# inside $( ... ), so the file always runs to its end.

# --- the helpers of this file ---
_APPROVAL56="request assumptions criteria out_of_scope answers files commands context launches risk baseline"
_COMMIT56="criteria suite coverage planted_bugs review files rule_log skips tree run message"
_STOP56="what_fails tried reading still_green spent"
_x56() { # _x56 <python code over d, the JSON of temper next (or of the second argument), that sets r>: prints r.
         # card is d's card ({} for none), sec(i) its section with that id, rows(i) that section's rows, ids() the
         # section ids in order, texts() every text of the card (title, tag, each section's title, note and rows, the
         # foot), inorder(o) whether the ids come in the order of the list o (APPROVAL, COMMIT or STOP), opts(d) every
         # option of the question and of its More questions, opt(d, i) the one with that id; X and Y are the variables
         # X56 and Y56
  python3 -B - "$1" "${2:-$("$TEMPER" next --json 2>/dev/null)}" "$_APPROVAL56" "$_COMMIT56" "$_STOP56" <<'PY'
import json, os, re, sys
try:
    d = json.loads(sys.argv[2])
except ValueError:
    d = {}
APPROVAL, COMMIT, STOP = (sys.argv[k].split() for k in (3, 4, 5))
X, Y = os.environ.get("X56", ""), os.environ.get("Y56", "")
card = d.get("card") if isinstance(d.get("card"), dict) else {}
def sec(i):
    return next((s for s in card.get("sections") or [] if isinstance(s, dict) and s.get("id") == i), None)
def rows(i):
    return [x for x in (sec(i) or {}).get("rows") or [] if isinstance(x, dict)]
def ids():
    return [s.get("id") for s in card.get("sections") or [] if isinstance(s, dict)]
def texts():
    out = [str(card.get("title") or ""), str(card.get("tag") or "")] + [str(x) for x in card.get("foot") or []]
    for s in card.get("sections") or []:
        if isinstance(s, dict):
            out += [str(s.get("title") or ""), str(s.get("note") or "")]
            out += [str(x.get("text") or "") for x in s.get("rows") or [] if isinstance(x, dict)]
    return out
def inorder(order):
    have = ids()
    return bool(have) and [i for i in order if i in have] == have
def opts(d):
    out, q = [], d.get("ask") or {}
    while isinstance(q, dict) and q:
        out += list(q.get("options") or [])
        q = q.get("more")
    return out
def opt(d, i):
    return next((o for o in opts(d) if o.get("id") == i), None)
r = None
exec(sys.argv[1])
print(r)
PY
}
_map56() { # _map56 <entry line>...: plan.md with a Context Map of these entries (one use line first), not yet reviewed
  { printf '# Plan\n\n## Context Map\n- use: intent.md AC-01..AC-02 - the accepted scope\n'; printf '%s\n' "$@"
    printf -- '- reviewed: pending\n\n## Approach\nThe demo.\n'
  } > .temper/specs/demo/plan.md
}
_plan56() { # the demo run moved on to Plan, its Intent and Plan checks passed: the approval is asked
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
}
_rich56() { # the approval of the demo run with a source for every section but the baseline: an assumption, a criterion
            # marked proposed, the person's answer, a Context Map with a flagged line, and the risk the CLI rated
  fresh
  python3 -B - <<'PY'
p = ".temper/specs/demo/intent.md"
t = open(p).read()
t = t.replace("- [ ] AC-02 [required]: demo criterion two\n", "- [ ] AC-02 [required]: demo criterion two (proposed)\n")
t = t.replace("### Decisions\n", "### Decisions\n"
              "- How long does the demo wait? -> two seconds (the person, 2026-01-01)\n\n"
              "### Assumptions\n- The demo runs on one machine (because no rule was given)\n")
open(p, "w").write(t)
PY
  _map56 "- ignore: src/legacy/ - the old demo keeps its own flow"
  _plan56; "$TEMPER" risk >/dev/null 2>&1
}
_tasks56() { # _tasks56 <group block>...: tasks.md of the demo run with these groups (Integration `true`)
  { printf '# Tasks: demo\n\n**Integration:** `true`\n'; printf '%s\n' "$@"; } > .temper/specs/demo/tasks.md
}
_group56() { # _group56 <G> <validate> <task number> <file list> <test command>: one group of one task
  printf '\n## Group %s: Part %s\n**Depends:** none\n**Validate:** `%s`\n' "$1" "$1" "$2"
  printf '**Context:**\nThe part.\n\n### Task %s: task %s\n' "$3" "$3"
  printf '**File:** %s\n**Depends:** none\n**Test:** `%s`\n**Cases:**\n- it holds\n- [ ] done\n' "$4" "$5"
}
_runs56() { # two finished runs of this project kept in .temper/runs.jsonl, of 10 and 30 minutes
  local s
  for s in 600 1800; do
    printf '{"v": 1, "at": "2026-01-01T00:00:00Z", "run": "old-%s", "slug": "old", "command": "temper", ' "$s"
    printf '"version": "9.8.5", "mode": "interactive", "ended": "committed", '
    printf '"asks": {"n": 2, "by_stage": {}, "by_kind": {}}, "steps_back": [], '
    printf '"launches": {"by_stage": {}}, "seconds": %s, "agent_seconds": 60, "skips": []}\n' "$s"
  done > .temper/runs.jsonl
}
_auto56() { # runs the calls of the action next gives when it is an auto action, as temper go runs them
  local c
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    bash -c "$c" >/dev/null 2>&1 || break
  done < <(_x56 "r = '\n'.join(d.get('calls') or []) if d.get('action') == 'auto' else ''")
}
_commit56() { # the commit question of a run the person started at the approval, parked before the commit: one source
              # file changed, an open medium finding, a skip of Review with its reason
  _unattended commit
  rm -rf .git src; git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name T
  mkdir -p src; echo 'echo demo' > src/demo.sh; git add -A -- . ':(exclude).temper' ':(exclude).claude'
  git commit -q -m base; echo 'echo demo; exit 0' > src/demo.sh
  mkdir -p .temper/evidence
  printf '[{"claim": "src/demo.sh:1 the demo exits 0 on a bad input", "severity": "medium", "label": "HEURISTIC"}]\n' \
    > .temper/evidence/review.json
  "$TEMPER" override review --reason 'the review was read by hand' >/dev/null 2>&1
  _ran_unattended; gpass commit; _auto56
}
_stop56() { # a failed Check of the demo run: its stop question
  fresh; gpass intent plan build review; _at check; gfail check "tests pass" "exit 1: 2 failed"
}
_sample56() { # the sample project of the card: login-lockout, 5 criteria (one proposed), one answer, one assumption,
              # two groups of two files on a sensitive path (two of them on disk), a Context Map of six sources, one
              # left out
  setup; rm -f .temper/groups.json .temper/view.json; rm -rf .temper/specs/demo
  local s=.temper/specs/login-lockout
  mkdir -p "$s" src/auth test/auth; echo x > src/auth/login.ts; echo x > test/auth/login.test.ts
  cat > "$s/intent.md" <<'MD'
# Intent: Login lockout

**Author:** Demo Author <demo@example.com>
**Status:** accepted
**Created:** 2026-01-01
**Reviewer:** Demo Reviewer <rev@example.com>
**Complexity:** simple

## Problem
Anyone can try passwords without limit.

### Success Criteria
- [ ] AC-01 [required]: 5 failed logins in 15 min lock the account for 15 min (source: request)
  Why: stops guessing
  Validate: scenario — lock
- [ ] AC-02 [required]: a locked account is refused with the message of a wrong password (source: request)
  Why: tells nothing
  Validate: scenario — refuse
- [ ] AC-03 [required]: the lock ends by itself after 15 min (source: request)
  Why: no support call
  Validate: scenario — unlock
- [ ] AC-04 [required]: a good login resets the count (source: request)
  Why: typos happen
  Validate: scenario — reset
- [ ] AC-05 [required]: Admins are locked like everyone else (proposed)
  Why: one rule
  Validate: scenario — admin

### Scope and Non-goals
- In scope: the login endpoint
- Out of scope: unlock by email, CAPTCHA, limits per IP
- Must keep working: the existing suite

### Open Questions

### Decisions
- How long does the lock last? -> 15 minutes (the person, 2026-01-01)

### Assumptions
- Admins are locked like everyone else (because no rule was given)
MD
  cat > "$s/tasks.md" <<'MD'
# Tasks: login-lockout

**Integration:** `npm test`

## Group G1: the lockout rule
**Depends:** none
**Validate:** `npm test -- lockout`
**Context:**
The rule.

### Task 1: lock after five failures
**File:** `src/auth/lockout.ts`, `test/auth/lockout.test.ts`
**Depends:** none
**Test:** `npm test -- lockout`
**Cases:**
- five failures lock
- [ ] done

## Group G2: the login endpoint
**Depends:** G1
**Validate:** `npm test -- login`
**Context:**
The endpoint.

### Task 2: refuse a locked account
**File:** `src/auth/login.ts`, `test/auth/login.test.ts`
**Depends:** Task 1
**Test:** `npm test -- login`
**Cases:**
- a locked account is refused
- [ ] done
MD
  cat > "$s/plan.md" <<'MD'
# Plan: Login lockout

## Context Map
- use: intent.md AC-01..AC-05 - the accepted scope
- use: src/auth/login.ts - the login endpoint
- use: test/auth/login.test.ts - its tests
- use: src/auth/session.ts - how a session starts
- use: docs/security.md - the password rules
- ignore: src/admin/login.ts - the admin login keeps its own flow
- reviewed: pending

## Approach
A counter per account.
MD
  "$TEMPER" state init login-lockout --feature "lock accounts after too many failed logins" >/dev/null 2>&1; _base_known
  gpass intent plan; "$TEMPER" state advance intent_complete plan >/dev/null 2>&1
  # the sample's risk M, as the spec's sample shows it: `temper risk` rates the sensitive path H, and at H the fresh
  # review of the plan runs before the approval is asked
  python3 -B -c "import json; p = '.temper/build-state.json'; d = json.load(open(p)); d['risk'] = 'M'
json.dump(d, open(p, 'w'), indent=2)"
}

# --- the approval card: its sections in the order of the spec's table, the run and step of its question ---
_rich56
_c56_plan="$(_x56 "a = d.get('ask') or {}
pair = (card.get('run_id'), card.get('step')) == (a.get('run_id'), a.get('step')) and a.get('run_id') is not None
r = 'kind=%s|ids=%s|pair=%s' % (card.get('kind'), ','.join(map(str, ids())), 'same' if pair else 'differs')")"
# The Design question of a run where the person asked for Design is then the approval.
fresh; _plan56; "$TEMPER" state set want_design true >/dev/null 2>&1; : > .temper/specs/demo/design.md
"$TEMPER" state advance plan_complete design >/dev/null 2>&1; gpass design
_c56_design="$(_x56 "need = ('request', 'criteria', 'files', 'commands')
r = '%s:%s|%s' % ((d.get('ask') or {}).get('id'), card.get('kind'),
    'order' if inorder(APPROVAL) and all(i in ids() for i in need) else ','.join(map(str, ids())) or 'no sections')")"
_c56_want="kind=approval|ids=request,assumptions,criteria,out_of_scope,answers,files,commands,context,launches,risk,baseline"
_c56_want+="|pair=same|design=design.pass:approval|order"
assert_eq "card: the approval question carries an approval card" "$_c56_want" "$_c56_plan|design=$_c56_design"

# --- one row per criterion; a cut section names its count and its file ---
_crit56() { # _crit56 <n>: the demo intent with n criteria, AC-01 to AC-<n>
  python3 -B - "$1" <<'PY'
import re, sys
p = ".temper/specs/demo/intent.md"
t = open(p).read()
n = int(sys.argv[1])
crit = "".join("- [ ] AC-%02d [required]: demo criterion number %d\n  Why: w\n"
               "  Validate: scenario — traced to a test below\n" % (k, k) for k in range(1, n + 1))
t = re.sub(r"(### Success Criteria\n)(?:.*\n)*?(?=\n### Constraints)", lambda m: m.group(1) + crit, t)
open(p, "w").write(t)
PY
}
_CRITROWS56="rs = rows('criteria')
s = sec('criteria') or {}
first = all(str(x.get('text') or '').startswith('AC-%02d ' % (k + 1)) for k, x in enumerate(rs))
r = '%d,%s,%s,%s' % (len(rs), s.get('total'), s.get('file'), 'ids in order' if rs and first else 'ids not in order')"
fresh; _crit56 5; _plan56; _c56_few="$(_x56 "$_CRITROWS56")"
fresh; _crit56 12; _plan56; _c56_many="$(_x56 "$_CRITROWS56")"
assert_eq "card: one row per criterion, and a cut section names its count and its file" \
  "few=5,5,.temper/specs/demo/intent.md,ids in order|many=8,12,.temper/specs/demo/intent.md,ids in order" \
  "few=$_c56_few|many=$_c56_many"

# --- the gate commands, word for word; the section is never cut ---
fresh
_tasks56 "$(_group56 G1 'sh -c "true | cat"' 1 '`src/demo.sh`' 'test -n t01')" \
  "$(for _k in 02 03 04 05 06 07 08 09 10 11 12; do
       _group56 "G$((10#$_k))" true "$((10#$_k))" "\`src/d$_k.sh\`" "test -n t$_k"
     done)"
_plan56
assert_eq "card: the gate commands are word for word" "validate=whole|tests=12 of 12|integration=yes|cut=no" \
  "$(_x56 "t = [str(x.get('text') or '') for x in rows('commands')]
s = sec('commands') or {}
r = 'validate=%s|tests=%d of 12|integration=%s|cut=%s' % (
    'whole' if any('sh -c \"true | cat\"' in x for x in t) else 'not whole',
    sum(1 for k in range(1, 13) if any(('test -n t%02d' % k) in x for x in t)),
    'yes' if any(x.rstrip().endswith('true') for x in t) else 'no',
    'yes' if not t or (s.get('total') or 0) > len(t) else 'no')")"

# --- a sensitive path has its own row; the card and the commit gate's matcher give the same answer ---
fresh
_tasks56 "$(_group56 G1 true 1 '`src/auth/login.sh`' true)" "$(_group56 G2 true 2 '`src/oauth/token.sh`' true)" \
  "$(_group56 G3 true 3 '`src/demo.sh`' true)"
_plan56
_SENS56="fs = rows('files')
body = [x for x in fs if not str(x.get('text') or '').startswith('SENSITIVE PATH IN THE PLAN:')]
def marked(f):
    return any(f in str(x.get('text') or '') and x.get('mark') == 'sensitive' for x in body)
"
assert_eq "card: a sensitive path has its own row" \
  "auth=sensitive|oauth=not|last=SENSITIVE PATH IN THE PLAN, src/auth/" \
  "$(_x56 "$_SENS56
last = str((fs[-1] if fs else {}).get('text') or '')
r = 'auth=%s|oauth=%s|last=%s' % ('sensitive' if marked('src/auth/login.sh') else 'not',
    'sensitive' if marked('src/oauth/token.sh') else 'not',
    'SENSITIVE PATH IN THE PLAN, src/auth/' if last.startswith('SENSITIVE PATH IN THE PLAN:') and 'src/auth/' in last
    else last or 'no files section')")"
_s56_pat="$("$TEMPER" config get autonomy.park-on-touch 2>/dev/null)"
_s56_gate="$(printf 'src/auth/login.sh\nsrc/oauth/token.sh\nsrc/demo.sh\n' \
  | python3 -B "$REPO_ROOT/scripts/sensitive.py" touched "$_s56_pat" "" 2>/dev/null)"
assert_eq "card: the card marks a path sensitive exactly where the matcher of the commit gate does" \
  "src/auth/login.sh=yes,yes|src/oauth/token.sh=no,no|src/demo.sh=no,no" \
  "$(X56="$_s56_gate" _x56 "$_SENS56
r = '|'.join('%s=%s,%s' % (f, 'yes' if (f + ' matches ') in X else 'no', 'yes' if marked(f) else 'no')
             for f in ('src/auth/login.sh', 'src/oauth/token.sh', 'src/demo.sh'))")"

# --- every flagged Context Map line is whole on the card (the question text cuts a line at 90) ---
_LONG56="src/legacy/ - $(printf 'the old demo keeps its own flow and its own tests, %.0s' 1 2 3 4)"
_LONG56+="and stays out of scope"
_LONG56="${_LONG56:0:200}"
fresh; _map56 "- ignore: $_LONG56" "- gap: no rate limit policy was found"; _plan56
assert_eq "card: every flagged Context Map line is whole" "200|ignore=whole,left out|gap=whole,not found|cut=no" \
  "${#_LONG56}|$(X56="$_LONG56" _x56 "rs = rows('context')
s = sec('context') or {}
def seen(t):
    x = next((x for x in rs if t in str(x.get('text') or '')), None)
    return 'whole,%s' % x.get('mark') if x else 'not whole'
r = 'ignore=%s|gap=%s|cut=%s' % (seen(X), seen('no rate limit policy was found'),
    'yes' if not rs or (s.get('total') or 0) > len(rs) else 'no')")"

# --- nothing is estimated from nothing; two kept runs give their median, marked about ---
_EST56="foot = [str(x) for x in card.get('foot') or []]
mins = [x for x in foot if re.search(r'\d+\s*min', x)]"
fresh; _plan56
_e56_none="$(_x56 "$_EST56
b = ' '.join(str(x.get('text', '')) for x in (sec('baseline') or {}).get('rows') or [])
r = 'card=%s|baseline=%s|minutes=%s' % (card.get('kind'), 'unknown' if b.startswith('unknown: ') else b or 'absent',
    len(mins) or 'none')")"
fresh; _runs56; _plan56
_e56_two="$(_x56 "$_EST56
one = len(mins) == 1 and 'about' in mins[0] and re.search(r'\b20\s*min', mins[0])
r = 'card=%s|minutes=%d|%s' % (card.get('kind'), len(mins), 'about 20 min' if one else '; '.join(mins) or 'none')")"
assert_eq "card: nothing is estimated from nothing" \
  "none=card=approval|baseline=unknown|minutes=none|two=card=approval|minutes=1|about 20 min" \
  "none=$_e56_none|two=$_e56_two"

# --- no card holds dollars; every time is in minutes ---
_CLEAN56="price = re.compile(r'\\\$|dollar|\bUSD\b|\bcents?\b|€|£|\b\d+\.\d\d\b(?!\s*%)', re.I)
secs = re.compile(r'\b\d+(?:\.\d+)?\s*(?:ms|s|secs?|seconds?|h|hrs?|hours?)\b', re.I)
bad = [x for x in texts() if price.search(x) or secs.search(x)]
r = 'no card' if not card else ('clean' if not bad else 'holds: ' + ' / '.join(bad)[:200])"
fresh; _runs56; _plan56; _d56_a="$(_x56 "$_CLEAN56")"
_commit56; _runs56; _d56_c="$(_x56 "$_CLEAN56")"
_stop56; _runs56; _d56_s="$(_x56 "$_CLEAN56")"
assert_eq "card: no card holds dollars" "approval=clean|commit=clean|stop=clean" \
  "approval=$_d56_a|commit=$_d56_c|stop=$_d56_s"

# --- no criterion is marked as the person's answer by guess: answers and assumptions have their own sections ---
_rich56
assert_eq "card: no criterion is marked as the person's answer by guess" \
  "marks=AC-01:None,AC-02:proposed|answers=1|assumptions=1|apart=yes" \
  "$(_x56 "cr = rows('criteria')
marks = ','.join('%s:%s' % (str(x.get('text') or '')[:5], x.get('mark')) for x in cr)
ans = [x for x in rows('answers')
       if 'How long does the demo wait?' in str(x.get('text')) and 'two seconds' in str(x.get('text'))]
asm = [x for x in rows('assumptions') if 'The demo runs on one machine' in str(x.get('text'))]
apart = not any('two seconds' in str(x.get('text')) or 'one machine' in str(x.get('text')) for x in cr)
r = 'marks=%s|answers=%d|assumptions=%d|apart=%s' % (marks or 'none', len(ans), len(asm), 'yes' if apart else 'no')")"

# --- the text form fits: 76 columns, 40 rows apart from the commands and the flagged context rows ---
_sample56
_t56_text="$("$TEMPER" card 2>/dev/null)"
assert_eq "card: the text form fits" "width=76 or less|rows=40 or less" \
  "$(X56="$_t56_text" _x56 "lines = X.splitlines()
extra = len(rows('commands')) + len([x for x in rows('context') if x.get('mark') in ('left out', 'not found')])
wide = [l for l in lines if len(l) > 76]
r = 'width=%s|rows=%s' % ('76 or less' if lines and not wide else 'no text' if not lines else 'over: ' + wide[0][:60],
    '40 or less' if lines and len(lines) - extra <= 40
    else '%d rows, %d apart from commands and context' % (len(lines), len(lines) - extra))")"

# --- three carriers, one card: temper card, the card rows of temper go, and the card of the view and of next ---
_sample56
_t56_card="$("$TEMPER" card 2>/dev/null)"
_t56_go="$("$TEMPER" go 2>/dev/null | tail -n 1)"
assert_eq "card: three carriers, one card" "go=same|view=same" \
  "$(X56="$_t56_card" Y56="$_t56_go" _x56 "lines = X.splitlines()
try:
    go = json.loads(Y).get('card')
except (ValueError, AttributeError):
    go = None
try:
    v = json.load(open('.temper/view.json')).get('card')
except (OSError, ValueError, AttributeError):
    v = None
r = 'go=%s|view=%s' % (
    'same' if lines and go == lines else 'differs (%d rows, go %s)' % (len(lines), type(go).__name__),
    'same' if card and v == d.get('card') else 'differs' if card else 'no card')")"

# --- the commit question carries a commit card ---
_commit56
assert_eq "card: the commit question carries a commit card" \
  "ask=commit.confirm|kind=commit|order=yes|skip=with its reason|finding=with its text|message=the click's" \
  "$(_x56 "o = opt(d, 'commit') or {}
cs = list(o.get('calls') or []) + list(o.get('steps') or [])
m = [re.search(r\"(?:spec commit|git commit -m) '([^']+)'\", c) for c in cs]
msg = next((x.group(1) for x in m if x), '')
need = ('criteria', 'review', 'skips', 'message')
has = lambda i, t: any(t in str(x.get('text')) for x in rows(i))
r = 'ask=%s|kind=%s|order=%s|skip=%s|finding=%s|message=%s' % ((d.get('ask') or {}).get('id'), card.get('kind'),
    'yes' if inorder(COMMIT) and all(i in ids() for i in need) else ','.join(map(str, ids())) or 'no sections',
    'with its reason' if has('skips', 'the review was read by hand') else 'absent',
    'with its text' if has('review', 'the demo exits 0 on a bad input') else 'absent',
    \"the click's\" if msg and any(str(x.get('text')) == msg for x in rows('message'))
    else 'option message: %s' % (msg or 'none'))")"

# --- the commit card's review section says how many changed files Review read: the row review completed of WP18 ---
_commit56
_READ56="r = ','.join('%s:%s' % (x.get('text'), x.get('mark'))
         for x in rows('review') if 'files' in str(x.get('text')))"
"$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label PROVEN --read src/demo.sh \
  >/dev/null 2>&1
"$TEMPER" gate review >/dev/null 2>&1; _r56_read="$(_x56 "$_READ56")"
"$TEMPER" evidence add --stage review --claim 'review completed' --exit 0 --label PROVEN >/dev/null 2>&1
"$TEMPER" gate review >/dev/null 2>&1; _r56_unread="$(_x56 "$_READ56")"
assert_eq "card: the commit card's review section says how many changed files Review read" \
  "read=read 1 of 1 changed files:None|unread=read 0 of 1 changed files; not read: src/demo.sh:open" \
  "read=$_r56_read|unread=$_r56_unread"

# --- the tree row states what git reads (HEAD and the files not committed), never a claim about the verdicts ---
_commit56
assert_eq "card: the tree row states HEAD and the count of files not committed, and nothing of the verdicts" \
  "HEAD is commit $(git rev-parse --short HEAD); 1 file not committed yet" \
  "$(_x56 "r = ' '.join(str(x.get('text')) for x in rows('tree'))")"

# --- the commit card's FILES section draws one row a line with its mark, never the approval's group layout ---
_commit56
mkdir -p src/auth; echo 'echo b' > src/b.sh; echo 'total = 1' > src/auth/totals.py
_cf56_text="$("$TEMPER" card 2>/dev/null)"
assert_eq "card: the commit card's FILES rows are one a line, a file outside the plan and a sensitive file each its own" \
  "lines=2|b=whole|auth=whole, sensitive" \
  "$(X56="$_cf56_text" python3 -B -c "import os
lines = os.environ['X56'].split('\n')
at = next((i for i, l in enumerate(lines) if l.startswith('FILES')), None)
body = []
for l in lines[at + 1:] if at is not None else []:
    if not l.strip():
        break
    body.append(l)
b = [l for l in body if 'src/b.sh' in l]
a = [l for l in body if 'src/auth/totals.py' in l]
print('lines=%d|b=%s|auth=%s' % (len(body),
    'whole' if b == [' src/b.sh (outside the plan)'] else repr(b),
    'whole, sensitive' if len(a) == 1 and a[0].startswith(' src/auth/totals.py (outside the plan) ')
    and a[0].endswith('[sensitive]') and 'src/b.sh' not in a[0] else repr(a)))")"

# --- a cut files section counts the files it leaves out, not its rows ---
fresh
_tasks56 "$(_group56 G1 true 1 "$(printf '`src/f%d.sh`, ' 1 2 3 4 5 6 7)\`src/f8.sh\`" true)" \
  "$(_group56 G2 true 2 '`src/g1.sh`, `src/g2.sh`' true)"
_plan56; _f56_text="$("$TEMPER" card 2>/dev/null)"
assert_eq "card: a cut files section counts the files it leaves out" "note=10 files|shown=8|more=2|text=and 2 more" \
  "$(X56="$_f56_text" _x56 "s = sec('files') or {}; fs = [x for x in rows('files') if x.get('mark')]
r = 'note=%s|shown=%d|more=%s|text=%s' % (str(s.get('note') or '').split(';')[0], len(fs),
    (s.get('total') or 0) - len(rows('files')), 'and 2 more' if 'and 2 more:' in X else X[-80:])")"

# --- a failed check asks with a stop card ---
_stop56
assert_eq "card: a failed check asks with a stop card" \
  "ask=check.fail|kind=stop|order=yes|fails=tests pass, exit 1: 2 failed|budget=per failure, per run|options=none" \
  "$(_x56 "t = ' '.join(texts())
fail = ' '.join(str(x.get('text')) for x in rows('what_fails'))
tried = ' '.join([str((sec('tried') or {}).get('note') or '')] + [str(x.get('text')) for x in rows('tried')])
labels = [str(o.get('label') or '') for o in opts(d)]
labels = [l for l in labels + [l.replace(' (Recommended)', '') for l in labels] if l]
inside = [l for l in labels if l in t]
need = ('what_fails', 'tried', 'still_green')
budget = re.search(r'\b\d+ of 2\b', tried) and re.search(r'\b\d+ of 6\b', tried)
r = 'ask=%s|kind=%s|order=%s|fails=%s|budget=%s|options=%s' % ((d.get('ask') or {}).get('id'), card.get('kind'),
    'yes' if inorder(STOP) and all(i in ids() for i in need) else ','.join(map(str, ids())) or 'no sections',
    'tests pass, exit 1: 2 failed' if 'tests pass' in fail and 'exit 1: 2 failed' in fail else fail or 'none',
    'per failure, per run' if budget else tried.strip() or 'none',
    'none' if card and not inside else ', '.join(inside) or 'no card')")"

# --- a question that is none of the three has no card: a passed Build of a run that asks at every stage ---
fresh; gpass intent plan; _at build; gpass build; "$TEMPER" state set run_mode interactive >/dev/null 2>&1
assert_eq "card: a question that is none of the three has no card" "ask=build.pass|next=null|view=null" \
  "$(_x56 "try:
    v = json.load(open('.temper/view.json'))
except (OSError, ValueError):
    v = {}
null = lambda x: 'null' if 'card' in x and x['card'] is None else 'no field' if 'card' not in x else 'a card'
r = 'ask=%s|next=%s|view=%s' % ((d.get('ask') or {}).get('id'), null(d), null(v if isinstance(v, dict) else {}))")"

# --- golden texts: temper card at the states plan-pass, check-fail and check-pass of make-view-fixtures.sh ---
# The commit card is read at check-pass: the fixture's run asks at every stage, so its passed Check question is the
# commit decision (its state commit-pass is a work, no question). The fixed texts are those of the fixture: the plugin
# folder, the project folder, the commit id, the run id and the times. TEMPER_WRITE_CARDS=1 writes the three files.
_pwfile56() { # _pwfile56 <intent|plan|tasks|findings>: the text of that file of the fixture's run, as it writes it
  python3 -B - "$1" <<'PY'
import json, sys
INTENT = "\n".join(["# Intent: Password reset by email", "", "**Status:** draft", "**Complexity:** simple", "",
                    "### Success Criteria", ""]
                   + ["- [ ] AC-0%d [required]: criterion %d (source: test)" % (n, n) for n in range(1, 6)] + [""])
PLAN = "\n".join(["# Plan", "", "### Files to Modify", "", "| File | Change |", "|---|---|", "| `src/app.ts` | edit |",
                  "| `unit/app.test.ts` | add |", "| `src/mail.ts` | edit |", ""])
TASKS = "\n".join([
    "# Tasks: Password reset by email", "", "**Integration:** `npm test`", "",
    "## Group G1: Tokens", "**Depends:** none", "**Validate:** `npm test`", "**Context:**", "Keep the token API.", "",
    "### Task 1: Issue a token", "**File:** `src/app.ts`, `unit/app.test.ts`", "**Depends:** none",
    "**Test:** `npm test`",
    "**Cases:**", "- a token is issued", "**Traced to:** Scenario: \"reset\"", "- [ ] done", "",
    "### Task 2: Expire a token", "**File:** `src/app.ts`", "**Depends:** Task 1", "**Test:** `npm test`",
    "**Cases:**", "- an old token is refused", "**Traced to:** Scenario: \"reset\"", "- [ ] done", "",
    "## Group G2: Mail", "**Depends:** G1", "**Validate:** `npm test`", "**Context:**", "Send the mail.", "",
    "### Task 3: Send the mail", "**File:** `src/mail.ts`", "**Depends:** none", "**Test:** `npm test`",
    "**Cases:**", "- the mail holds the link", "**Traced to:** Scenario: \"reset\"", "- [ ] done", ""])
FINDINGS = json.dumps([
    {"claim": "src/app.ts:12 the token never expires", "severity": "critical", "label": "PROVEN"},
    {"claim": "src/mail.ts:4 the subject is not localized", "severity": "low", "label": "HEURISTIC"},
])
sys.stdout.write({"intent": INTENT, "plan": PLAN, "tasks": TASKS, "findings": FINDINGS}[sys.argv[1]])
PY
}
_golden56() { # _golden56 <name>: same when temper card here, with the fixture's fixed texts, is the golden file
               # byte for byte
  local f="$REPO_ROOT/scripts/selftest/cards/$1.txt" out="$WORKDIR/card56-$1.txt"
  "$TEMPER" card > "$out.raw" 2>/dev/null
  python3 -B - "$out.raw" "$out" "$REPO_ROOT" "$PWD" "$WORKDIR" "$(git rev-parse HEAD 2>/dev/null)" \
    "$("$TEMPER" state get run_id 2>/dev/null)" <<'PY'
import re, sys
src, dst, root, cwd, work, head, rid = sys.argv[1:8]
text = open(src, encoding="utf-8").read().replace(root, "/plugin").replace(cwd, "/project").replace(work, "/work")
if len(head) >= 7:
    text = re.sub(r"\b%s[0-9a-f]{0,33}\b" % re.escape(head[:7]), "0000000", text)
if rid:
    text = text.replace(rid, "run-pw")
text = re.sub(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:?\d\d)?", "2026-01-01T00:00:00Z", text)
open(dst, "w", encoding="utf-8").write(text)
PY
  if [[ -n "${TEMPER_WRITE_CARDS:-}" && -s "$out" ]]; then mkdir -p "${f%/*}"; cp "$out" "$f"; fi
  if [[ ! -s "$out" ]]; then echo "no card"; elif [[ ! -f "$f" ]]; then echo "no golden file"
  elif cmp -s "$out" "$f"; then echo same; else echo differs; fi
  rm -f "$out" "$out.raw"
}
_snap56() { "$TEMPER" next --json >/dev/null 2>&1; }   # a snap of the fixture: it reads next once, as the fixture does
setup; rm -rf "${WORKDIR:?}/pw56"; mkdir -p "$WORKDIR/pw56/.temper"; cd "$WORKDIR/pw56" || exit 1
git init -q .; git config user.email t@example.com; git config user.name t
echo x > README.md; git add README.md; git commit -q -m init
mkdir -p .claude; printf 'review:\n  block-on: [critical]\n' > .claude/temper.config
_snap56; "$TEMPER" state init pw --feature "Password reset by email" >/dev/null 2>&1; _base_known; _snap56
mkdir -p .temper/specs/pw; _pwfile56 intent > .temper/specs/pw/intent.md
gfail intent "Success criteria" "AC-03 has no Validate line"; _snap56; gpass intent; _snap56
"$TEMPER" state advance intent_complete plan >/dev/null 2>&1; _snap56
_pwfile56 plan > .temper/specs/pw/plan.md; _pwfile56 tasks > .temper/specs/pw/tasks.md
gfail plan "Blast radius" "src/mail.ts is not in the plan"; _snap56; gpass plan; _snap56
_g56_approval="$(_golden56 approval)"
printf 'review:\n  block-on: [critical]\nautonomy:\n  enabled: true\n' > .claude/temper.config; _snap56
printf 'review:\n  block-on: [critical]\n' > .claude/temper.config
"$TEMPER" intent accept >/dev/null 2>&1; "$TEMPER" state advance plan_complete build >/dev/null 2>&1; _snap56
gfail build "tests pass" "2 tests fail: unit/app.test.ts"; _snap56; gpass build; _snap56
"$TEMPER" state advance build_complete review >/dev/null 2>&1; _snap56
mkdir -p .temper/evidence; _pwfile56 findings > .temper/evidence/review.json
gfail review "critical findings" "1 open critical finding"; _snap56; gpass review; _snap56
"$TEMPER" state advance review_complete check >/dev/null 2>&1; _snap56
gfail check "tests pass" "exit 1: 2 failed"; _snap56
_g56_stop="$(_golden56 stop)"
gpass check; _snap56
_g56_commit="$(_golden56 commit)"
cd "$WORKDIR" || exit 1; rm -rf "${WORKDIR:?}/pw56"
assert_eq "card: golden texts" "approval=same|commit=same|stop=same" \
  "approval=$_g56_approval|commit=$_g56_commit|stop=$_g56_stop"
