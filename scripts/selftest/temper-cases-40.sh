# Case file 40 (WP04, ids in the protocol): sourced by test-temper.sh after the case files before it. Every question and
# every option that `temper next --json`, `temper go` and .temper/view.json carry has a stable id from the registry of
# scripts/flow_base.py; a question has a kind; an option says when it is recommended. Token: ids:.

# The walker over the two generated fixture modules: each question a view carries (the gate question, its More options and
# accept questions, the Context check, the resume question, each Blocking question, and each option's reason and name
# questions), with the options a reader selects by. Prints "ok", or the first problems it found.
_i40() { # _i40 <mode>
  python3 -I - "$REPO_ROOT" "$1" <<'PY'
import ast, json, os, re, sys
root, mode = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, "scripts"))
import flow_base as fb

SUFFIX = " (Recommended)"


def views():
    for f in ("view-fixtures.ts", "view-fixtures-2.ts"):
        d = json.loads(open(os.path.join(root, "scripts", "selftest", f), encoding="utf-8").read().split("= ", 1)[1])
        for k in sorted(d):
            yield k, d[k]


def beside(q, ids):
    """A dialog question and the ids beside it, as one question: the id and kind of the ids, and each option of the
    dialog with the id (and kind) at its place. A count that differs leaves an option with no id."""
    ids = ids if isinstance(ids, dict) else {}
    opts = (q or {}).get("options") or []
    io = ids.get("options") or []
    merged = [dict(o, **(io[k] if k < len(io) and len(io) == len(opts) else {})) for k, o in enumerate(opts)]
    return {"id": ids.get("id"), "kind": ids.get("kind")}, merged


def questions(v):
    out = []

    def follow(where, opts):
        for o in opts:
            for key, ids in (("reason_question", "reason_ids"), ("answer_question", "answer_ids")):
                if isinstance(o.get(key), dict):
                    out.append(("%s/%s/%s" % (where, o.get("label"), key),) + beside(o[key], o.get(ids)))

    def walk(where, a):
        if not isinstance(a, dict):
            return
        out.append((where, a, a.get("options") or []))
        follow(where, a.get("options") or [])
        walk(where + ".more", a.get("more"))
        walk(where + ".accept", a.get("accept"))
        walk(where + ".change", a.get("change"))

    walk("ask", v.get("ask"))
    cc = v.get("context_check")
    if isinstance(cc, dict):
        out.append(("context_check", cc, cc.get("options") or []))
        follow("context_check", cc.get("options") or [])
    rs = v.get("restart")
    if isinstance(rs, dict):
        out.append(("restart", rs, rs.get("options") or []))
    for i, b in enumerate(v.get("blocking_asks") or []):
        out.append(("blocking_asks[%d]" % i,) + beside(b.get("question"), b.get("question_ids")))
    return out


bad = []
if mode == "ids":
    for qid, e in fb.QUESTIONS.items():
        if e.get("kind") not in fb.QUESTION_KINDS or not str(e.get("decision") or "").strip():
            bad.append("registry %s: %r" % (qid, e))
    for name, v in views():
        for where, q, _ in questions(v):
            e = fb.question_entry(q.get("id")) if isinstance(q.get("id"), str) else None
            if e is None or q.get("kind") != e["kind"] or not e["decision"]:
                bad.append("%s %s: id %r kind %r" % (name, where, q.get("id"), q.get("kind")))
elif mode == "options":
    for name, v in views():
        for where, q, opts in questions(v):
            ids = [o.get("id") for o in opts]
            if len(set(ids)) != len(ids) or any(i not in fb.OPTION_IDS for i in ids) or \
                    any("kind" in o and o["kind"] not in fb.OPTION_KINDS for o in opts):
                bad.append("%s %s: %r" % (name, where, ids))
elif mode == "rec":
    for name, v in views():
        for where, q, opts in questions(v):
            for o in opts:
                suf = str(o.get("label", "")).endswith(SUFFIX)
                if (suf and o.get("recommended") is not True) or (not suf and "recommended" in o):
                    bad.append("%s %s: %r %r" % (name, where, o.get("label"), o.get("recommended")))
elif mode == "one":
    for name, v in views():
        for where, q, opts in questions(v):
            if where.endswith(".more"):
                continue
            n = sum(1 for o in opts + ((q.get("more") or {}).get("options") or []) if o.get("recommended"))
            if n > 1:
                bad.append("%s %s: %d" % (name, where, n))
elif mode == "reach":
    # the walker reaches each kind of question the fixture views carry, so the modes above look at every one of them
    seen = {re.sub(r"\[\d+\]|/[^/]*/", "", where) for _, v in views() for where, _, _ in questions(v)}
    bad = ["%s not reached" % w for w in os.environ["REACH"].split() if w not in seen]
elif mode == "dialog":
    for name, v in views():
        def walk(where, a):
            if not isinstance(a, dict):
                return
            d = a.get("question") or {}
            if set(d) != {"header", "question", "multiSelect", "options"} or \
                    any(set(o) != {"label", "description"} for o in d.get("options") or []):
                bad.append("%s %s: %r" % (name, where, sorted(d)))
            walk(where + ".more", a.get("more"))
            walk(where + ".accept", a.get("accept"))
        walk("ask", v.get("ask"))
elif mode == "keys":
    # every dict a session hands to the question tool, as the CLI wrote it: the tool takes these keys and refuses others
    QK, OK = {"question", "header", "options", "multiSelect"}, {"label", "description", "preview"}

    def dialog(name, where, d):
        if not isinstance(d, dict):
            return
        extra = sorted(set(d) - QK) + sorted({k for o in d.get("options") or [] for k in set(o) - OK})
        if extra:
            bad.append("%s %s: %s" % (name, where, ",".join(extra)))

    for name, v in views():
        def walk(where, a):
            if not isinstance(a, dict):
                return
            dialog(name, where, a.get("question"))
            for o in a.get("options") or []:
                for key in ("reason_question", "answer_question"):
                    dialog(name, "%s/%s/%s" % (where, o.get("label"), key), o.get(key))
            for k in ("more", "accept", "change"):
                walk(where + "." + k, a.get(k))
        walk("ask", v.get("ask"))
        walk("context_check", v.get("context_check"))
        for i, b in enumerate(v.get("blocking_asks") or []):
            dialog(name, "blocking_asks[%d]" % i, b.get("question"))
elif mode in ("suffix", "calls"):
    files = os.environ["FLOW_FILES"].split()
    for f in files:
        text = open(os.path.join(root, f), encoding="utf-8").read()
        tree = ast.parse(text)
        if mode == "suffix":
            own = set()
            for node in ast.walk(tree):
                if isinstance(node, ast.FunctionDef) and node.name in ("opt", "set_rec"):
                    own |= set(range(node.lineno, node.end_lineno + 1))
            for i, line in enumerate(text.split("\n"), 1):
                if i not in own and re.search(r'endswith\(.\(Recommended\)|replace\(. \(Recommended\)|\["label"\] *\+=', line):
                    bad.append("%s:%d" % (f, i))
        else:
            want = {"question": "qid", "with_more": "qid", "opt": "oid"}
            for node in ast.walk(tree):
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in want:
                    if not any(k.arg == want[node.func.attr] for k in node.keywords):
                        bad.append("%s:%d %s" % (f, node.lineno, node.func.attr))
print("ok" if not bad else "; ".join(bad[:6]) + (" (and %d more)" % (len(bad) - 6) if len(bad) > 6 else ""))
PY
}

assert_eq "ids: every question has an id of the registry and a kind, and the registry holds its decision" "ok" "$(_i40 ids 2>&1)"
assert_eq "ids: option ids are unique in a question and come from the closed list" "ok" "$(_i40 options 2>&1)"
assert_eq "ids: recommended is true exactly where the label ends in the suffix, and absent elsewhere" "ok" "$(_i40 rec 2>&1)"
assert_eq "ids: at most one recommended option in a question and its More question together" "ok" "$(_i40 one 2>&1)"
assert_eq "ids: the walker reaches the More, accept and change questions of a gate, so the checks above see them" "ok" \
  "$(REACH="ask.more ask.accept ask.change" _i40 reach 2>&1)"
assert_eq "ids: the question that goes to the dialog has no new key" "ok" "$(_i40 dialog 2>&1)"
assert_eq "ids: no dialog the CLI writes holds a key the question tool refuses" "ok" "$(_i40 keys 2>&1)"
assert_eq "ids: only opt() and set_rec() know the suffix" "ok" "$(FLOW_FILES="$FLOW_FILES" _i40 suffix 2>&1)"
assert_eq "ids: every call of question(), with_more() and opt() passes qid or oid" "ok" "$(FLOW_FILES="$FLOW_FILES" _i40 calls 2>&1)"

assert_eq "ids: an unknown question id and an unknown option id are refused" "question|option|duplicate|registry" \
  "$(python3 -I - "$REPO_ROOT/scripts" <<'PY' 2>&1
import sys, types
sys.path.insert(0, sys.argv[1])
import flow_ask, flow_base


class S(flow_ask.AskPart):
    pass


s = S()
s.cli, s.plugin = "temper", ""
s.r = types.SimpleNamespace(state={"step": 1, "run_id": "r"}, command="temper")
out = []
for what, call in (("question", lambda: s.question("Temper gate", "Go?", [s.save()], "plan", qid="plan.nothing")),
                   ("option", lambda: s.opt("Go", "Go on.", move="advance", oid="go-somewhere")),
                   ("duplicate", lambda: s.question("Temper gate", "Go?", [s.save(), s.save()], "plan", qid="plan.approve"))):
    try:
        call()
        out.append("accepted " + what)
    except ValueError:
        out.append(what)
out.append("registry" if flow_base.question_entry("plan.nothing") is None and flow_base.question_entry("plan.approve.more") else "no registry")
print("|".join(out))
PY
)"

fresh; gpass intent
assert_eq "ids: temper go passes id, kind, move and recommended" "intent.accept|gate|continue|approve|True|save|False" \
  "$(_ev "a = d['ask']; o = a['options']; s = [x for x in o if x['id'] == 'save'][0]; '|'.join(str(x) for x in (a['id'], a['kind'], o[0]['id'], o[0]['move'], o[0]['recommended'], s['id'], 'recommended' in s))" \
    "$("$TEMPER" go 2>/dev/null)")"

# The questions the fixture views do not reach, each asked once (a refused id would stop a person's run there)
setup; "$TEMPER" state init bug --command fix >/dev/null 2>&1; "$TEMPER" state advance rca_complete fix >/dev/null 2>&1
mkdir -p .temper/specs/bug
gfail build "tests pass" "2 tests fail"
assert_eq "ids: a failed Fix asks fix.fail, with the redo the run takes again" "fix.fail|gate|redo|True" \
  "$(nx "a = d['ask']; o = a['options'][0]; '|'.join(str(x) for x in (a['id'], a['kind'], o['id'], o.get('recommended')))")"
fresh
printf '# Intent: Demo\n\n**Status:** draft\n\n### Open Questions\n\n- Blocking: Who may run the demo? choices: Admins only | Everyone\n' \
  > .temper/specs/demo/intent.md
gpass intent
assert_eq "ids: a Blocking question carries intent.blocking beside its question, its choices and Carry forward by id" \
  "intent.blocking|blocking|choice-1,choice-2,carry|carry|header,multiSelect,options,question" \
  "$(nx "b = d['blocking_asks'][0]; i = b['question_ids']; o = i['options']; '|'.join([i['id'], i['kind'], ','.join(x['id'] for x in o), o[-1]['kind'], ','.join(sorted(b['question']))])")"
assert_eq "ids: the resume and the Scope drift questions of the view have their ids" "run.restart|resume|start-over,cancel|scope.drift|drift" \
  "$(vw "r = d['restart']; '|'.join([r['id'], r['kind'], ','.join(o['id'] for o in r['options']), d['drift']['id'], d['drift']['kind']])")"
