"""card.py: the card of a question that decides (9.8.5, WP15): the approval, the commit, or a stop.

  python3 card.py text VIEW_JSON     `temper card`: the rows of the card of the view's question (nothing with none)

`build(b, nxt)` makes the card of the question `nxt` asks, as data, or None; `b` is the flow's Builder (its Run is b.r).
`render(card, width)` makes the text rows. The card is a field of `temper next --json` and of .temper/view.json (the
same object), and `temper go` gives its rows; the mod draws it above the dialog. The shape:

  {"kind": "approval" | "commit" | "stop", "run_id", "step", "title", "tag",
   "sections": [{"id", "title", "note", "rows": [{"text", "mark"}], "total", "file"}], "foot": [...]}

A section is cut when `total` is larger than the count of its rows; `file` says where the rest is. A mark is one of
MARKS or null. A section with no source is left out, never filled with a guess. No card holds dollars: the CLI holds
none, and a time is in minutes, an estimate only from the kept run summaries (scripts/run_summary.py). No field holds
a rendered line. The card never goes into the question text: the mod counts an answer only on the question as asked.
WP17, WP19, WP20, WP22, WP24, WP25 and WP27 add rows here and nowhere else. Standard library only.
"""
import json
import os
import re
import subprocess
import sys
import textwrap

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import acceptance  # noqa: E402
import budget  # noqa: E402
import output_ops  # noqa: E402
import plan_ops  # noqa: E402
import run_summary  # noqa: E402
import sensitive  # noqa: E402
from flow_base import criteria, plan_files  # noqa: E402
from flow_view import PERSON_ROWS  # noqa: E402
from panel import plain, rca_fields, section  # noqa: E402
import check_run  # noqa: E402

KINDS = ("approval", "commit", "stop")
MARKS = ("proposed", "create", "modify", "sensitive", "left out", "not found", "not measured", "open", "skipped",
         "by rule")
APPROVAL = ("request", "assumptions", "criteria", "out_of_scope", "answers", "files", "commands", "context", "launches",
            "risk", "baseline")
FIX_APPROVAL = ("request", "cause", "fix", "test", "files", "commands", "risk")   # WP17: the approval of a fix run
COMMIT = ("regression", "criteria", "suite", "coverage", "planted_bugs", "review", "files", "rule_log", "skips", "tree",
          "run", "message")   # regression: a fix run only (WP17)
STOP = ("what_fails", "tried", "reading", "still_green", "spent")
# a short section is one row that starts with its title (render)
SHORT = ("request", "out_of_scope", "launches", "risk", "baseline", "suite", "coverage", "planted_bugs", "tree", "run",
         "reading", "still_green", "spent", "fix")
JOINS = ("out_of_scope",)   # a short section that goes on from the section before it, with no blank row
WIDTH = 76
SENSITIVE_ROW = "SENSITIVE PATH IN THE PLAN:"
TEMPER = ".temper"
STAGE_NAMES = {"intent": "Intent", "plan": "Plan", "design": "Design", "build": "Build", "review": "Review",
               "check": "Check", "commit": "Commit", "rca": "RCA", "fix": "Fix", "pipeline": "Pipeline"}



def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return ""


def load(path, default):
    try:
        d = json.load(open(path, encoding="utf-8"))
        return d if isinstance(d, type(default)) else default
    except (OSError, ValueError):
        return default


def cell(text, mark=None):
    return {"text": str(text).strip(), "mark": mark}


def sec(sid, title, rows, note=None, cap=None, file=None):
    """A section: at most `cap` rows; `total` counts them all, `file` names where the rest is."""
    kept = rows if cap is None else rows[:cap]
    return {"id": sid, "title": title, "note": note, "rows": kept, "total": len(rows), "file": file}


def minutes(ms):
    return int(round((ms or 0) / 60000.0))


def git(*args):
    try:
        r = subprocess.run(["git"] + list(args), capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout.strip() if r.returncode == 0 else ""


# ---- which question gets which card ----------------------------------------------------------------------------------

def failed_rows(r, stage):
    return [x for x in r.failed_rows(stage) if x.get("name") not in PERSON_ROWS]   # a row that waits for the person


def kind_of(r, nxt):
    """The one place that says which question carries which card: the approval (plan.approve, rca.approve, and
    design.pass when the person asked for Design: it is then the approval), the commit (commit.confirm, a parked commit;
    and check.pass in a run that asks at every stage), a stop (any other question at a stage whose check failed and is
    not skipped, or a stop of a run that goes on by itself); else None."""
    ask = nxt.get("ask") if nxt.get("action") == "ask" else None
    if not isinstance(ask, dict):
        return None
    qid = ask.get("id") or ""
    stage = ask.get("stage") or r.stage
    if qid in ("plan.approve", "rca.approve") or (qid == "design.pass" and r.has_design()):
        return "approval"
    if qid == "commit.confirm" or (qid == "check.pass" and not r.state.get("parked")):
        return "commit"
    if qid.startswith("plan.context") or qid == "run.restart":
        return None
    if r.verdict(stage) == "FAIL" and r.skip(stage) is None and failed_rows(r, stage):
        return "stop"
    if r.state.get("parked") and stage != "commit" and r.state.get("unattended_from"):
        return "stop"
    return None


def build(b, nxt):
    """The card of the question nxt asks, or None. b is the Builder: the same reads as the question, in one call."""
    r = b.r
    kind = kind_of(r, nxt)
    if kind is None:
        return None
    ask = nxt.get("ask") or {}
    risk = str(r.state.get("risk") or "").upper()
    tag = "%s · risk %s" % (r.slug, risk) if risk else r.slug
    made = {"approval": approval, "commit": commit, "stop": stop}[kind](b, nxt)
    out = {"kind": kind, "run_id": ask.get("run_id"), "step": ask.get("step"), "title": made[0], "tag": tag,
           "sections": [s for s in made[1] if s is not None], "foot": made[2]}
    return out


# ---- the approval ----------------------------------------------------------------------------------------------------

def strip_tags(text):
    """A criterion's text without its source and its mark (proposed)."""
    return " ".join(re.sub(r"\s*\((?:source:[^)]*|proposed)\)", "", text).split())


def criterion_text(c):
    """`AC-01 the text` of a criterion line, its priority tag, source and the mark (proposed) left out."""
    t = re.sub(r"^(AC-\d+)\s*\[(?:required|optional)\]:\s*", r"\1 ", c.get("first_line") or "")
    t = re.sub(r"\s*\((?:source:[^)]*|proposed)\)", "", t)
    return " ".join(t.split())


def bullets(lines):
    return [plain(re.sub(r"^\s*[-*]\s+", "", l)) for l in lines if re.match(r"^\s*[-*]\s+\S", l)]


def answer_rows(intent_text):
    """The person's answers: the rows of ### Decisions that end (the person, DATE) (scripts/answer_ops.py)."""
    out = []
    for b in bullets(section(intent_text, "Decisions")):
        m = re.match(r"^(.*?)\s*\(the person, [^)]*\)\s*$", b)
        if m and m.group(1).strip():
            out.append(cell(m.group(1)))
    return out


def files_rows(r, b):
    """Per Build group a row of its title, then a row a file of it (create, modify, or sensitive); the last row names
    the sensitive paths. The matcher is the commit gate's (scripts/sensitive.py)."""
    plan = r.plan or {"groups": [], "tasks": []}
    hot = dict(sensitive.declared([f for t in plan.get("tasks", []) for f in t.get("files", [])],
                                  r.cfg("autonomy.park-on-touch", "")))
    out, seen = [], set()
    for g in plan.get("groups", []):
        files = []
        for n in g.get("tasks", []):
            t = next((x for x in plan.get("tasks", []) if x.get("n") == n), {})
            files += [f for f in t.get("files", []) if f not in files and f not in seen]
        if not files:
            continue
        seen.update(files)
        out.append(cell("%s %s" % (g["id"], g.get("title") or "")))
        for f in files:
            out.append(cell(f, "sensitive" if f in hot else "modify" if os.path.exists(f) else "create"))
    return out, sorted({os.path.dirname(f) + "/" if os.path.dirname(f) else f for f in hot})


def command_rows(r):
    """Each group's Validate, each task's Test unless it is its group's Validate, and the Integration line, word for
    word; a manual task is named."""
    plan = r.plan or {"groups": [], "tasks": []}
    out = []
    for g in plan.get("groups", []):
        if g.get("validate"):
            out.append(cell("%s: %s" % (g["id"], g["validate"])))
        for n in g.get("tasks", []):
            t = next((x for x in plan.get("tasks", []) if x.get("n") == n), {})
            if t.get("manual"):
                out.append(cell("Task %d: by hand: %s" % (n, t.get("confirm") or "the person confirms it")))
            elif t.get("test") and t.get("test") != g.get("validate"):
                out.append(cell("Task %d: %s" % (n, t["test"])))
    if plan.get("integration"):
        out.append(cell("all: %s" % plan["integration"]))
    return out


def launches(b):
    """How many agents of which kind the run launches after the click, with the model of each kind."""
    r = b.r
    plan = r.plan or {"tasks": []}
    models = r.ctx.get("models") or {}
    short = lambda m: re.sub(r"^claude-(haiku|sonnet|opus|fable)-\d.*$", r"\1", str(m or "")) or "its model"
    acc = r.cfg("models.acceptance", "") or models.get("acceptance") or "sonnet"
    parts = []
    if r.command == "temper" and r.intent:
        parts.append("1 test writer (%s)" % short(acc))
    if r.stage == "plan" and r.has_design():
        parts.append("1 designer (%s)" % short(models.get("design") or "opus"))
    n = len(plan.get("tasks", []))
    if n:
        parts.append("%d builder%s (%s)" % (n, "" if n == 1 else "s", short(b.task_model())))
    parts.append("1 reviewer (%s)" % short(models.get("review") or "sonnet"))
    return [cell(", ".join(parts))]


def risk_rows(r, nfiles):
    level = str(r.state.get("risk") or "").upper()
    if not level:
        return None
    why = ["%d file%s" % (nfiles, "" if nfiles == 1 else "s")] if nfiles else []
    if r.sensitive():
        why.append("a sensitive path")
    hot = load(os.path.join(TEMPER, "security-map.json"), [])
    hot = [str(e.get("sensitivity", "")).upper() for e in hot if isinstance(e, dict)]
    n = sum(1 for x in hot if x in ("CRITICAL", "HIGH"))
    if n:
        why.append("%d hot path%s" % (n, "" if n == 1 else "s"))
    return sec("risk", "RISK %s" % level, [cell(", ".join(why) or "as the CLI rated it")])


def baseline():
    """The baseline WP20 records (.temper/evidence/baseline.json): absent before it, and then no section."""
    d = load(os.path.join(TEMPER, "evidence", "baseline.json"), {})
    if not d:
        return None
    parts = []
    if d.get("cmd"):
        parts.append(str(d["cmd"]))
    if isinstance(d.get("exit_code"), int):
        parts.append("passed" if d["exit_code"] == 0 else "failed (exit %d)" % d["exit_code"])
    if isinstance(d.get("seconds"), (int, float)):
        parts.append("%d min" % int(round(d["seconds"] / 60.0)))
    if d.get("coverage") is not None:
        parts.append("coverage floor %s%%" % d["coverage"])
    return sec("baseline", "BASELINE", [cell(", ".join(parts))]) if parts else None


def estimate():
    """One foot row from the kept run summaries: their median in minutes, marked about; None with none kept."""
    m = run_summary.median_minutes(TEMPER)
    if m is None:
        return None
    return "A run of this project took about %d min (the median of %d finished run%s)." % (
        m[0], m[1], "" if m[1] == 1 else "s")


def first_option(nxt):
    return ((nxt.get("ask") or {}).get("options") or [{}])[0]


def request_section(r):
    feature = str(r.state.get("feature") or "").strip()
    if not feature:
        return None
    said = feature if len(feature) <= 140 else feature[:137] + "..."
    return sec("request", "You asked", [cell('"%s"' % said)])


def fix_approval(b, nxt):
    """WP17: the approval of a fix run, the root cause question: the bug as typed, the cause, the fix, the regression
    test, the files the fix may change, the test command the CLI found, and the risk, from rca.md as panel.py reads it.
    The foot names the branch the click makes."""
    r = b.r
    path = os.path.join(r.spec, "rca.md") if r.spec else ""
    f = rca_fields(read(path) if path else "")
    out = [request_section(r)]
    cause = [cell(f["CAUSE"])] if f["CAUSE"] else []
    cause += [cell("%s: %s" % (k.capitalize(), f[k])) for k in ("AT", "CONFIDENCE", "SINCE", "CHAIN") if f[k]]
    out.append(sec("cause", "THE CAUSE", cause, None, None, path) if cause else None)
    out.append(sec("fix", "THE FIX", [cell(f["FIX"])]) if f["FIX"] else None)
    out.append(sec("test", "THE REGRESSION TEST", [cell(f["TEST"])], "written first; it must fail before the fix")
               if f["TEST"] else None)
    names = []
    for x in [f["AT"].split(":")[0].strip()] + f["blast"] + f["read"]:
        x = x.split()[0].strip("`") if x.strip() else ""
        if x and x not in names:
            names.append(x)
    hot = dict(sensitive.declared(names, r.cfg("autonomy.park-on-touch", "")))
    rows = [cell(x, "sensitive" if x in hot else "modify" if os.path.exists(x) else "create") for x in names]
    out.append(sec("files", "WHAT WILL CHANGE", rows, "the fix may change these %d and its test; any other file asks you first"
                   % len(rows), None, path) if rows else None)
    try:
        test = check_run.detect(os.getcwd(), r.cfg("check.commands.test", ""), r.cfg("check.commands.coverage", "")).get("test")
    except Exception:
        test = None
    out.append(sec("commands", "THE CHECKS RUN", [cell(test)]) if test else None)
    risk = [cell("a sensitive path: %s" % x, "sensitive") for x in names if x in hot]
    if f["CONFIDENCE"].upper().startswith("LOW"):
        risk.append(cell("the root cause agent's confidence is LOW"))
    out.append(sec("risk", "RISK", risk) if risk else None)
    cur = git("branch", "--show-current")
    default = git("symbolic-ref", "--short", "refs/remotes/origin/HEAD").split("/", 1)[-1]
    branch = r.state.get("branch") or "fix/%s" % r.slug
    foot = ["Your approval makes the branch %s off %s." % (branch, cur) if cur in ("main", "master") or (cur and cur == default)
            else "The fix goes on %s, the branch you are on." % (cur or "the branch you are on")]
    foot.append("You are asked again only if a check still fails after one repair, and at the commit."
                if first_option(nxt).get("id") == "approve-run" else "You are asked after every stage, and at the commit.")
    foot.append("Nothing is pushed.")
    return "APPROVE THE FIX BEFORE ANY CODE IS WRITTEN", out, foot


def approval(b, nxt):
    r = b.r
    if r.command == "fix":
        return fix_approval(b, nxt)
    ipath = os.path.join(r.spec, "intent.md") if r.spec else ""
    text = read(ipath) if ipath else ""
    lines = text.splitlines()
    out = [request_section(r)]
    assumed = [cell(x) for x in bullets(section(text, "Assumptions"))]
    if assumed:
        out.append(sec("assumptions", "ASSUMED", assumed, "%d; nobody was asked" % len(assumed), 4, ipath))
    crits = [c for c in acceptance.parse_criteria(acceptance.section_lines(lines, "Success Criteria"))
             if c.get("id") and not c.get("placeholder")]
    if crits:
        rows = [cell(criterion_text(c), "proposed" if "(proposed)" in (c.get("first_line") or "") else None)
                for c in crits]
        out.append(sec("criteria", "WHAT WILL BE TRUE", rows, "%d criteria; each gets a test written and locked first"
                       % len(rows), 8, ipath))
    scope = acceptance.out_of_scope(lines)
    if scope:
        items = [x.strip() for x in re.split(r"[,;]\s+", scope) if x.strip()]
        out.append(sec("out_of_scope", "NOT IN SCOPE", [cell(" · ".join(items))]))
    answers = answer_rows(text)
    if answers:
        out.append(sec("answers", "YOUR ANSWERS", answers, "%d" % len(answers), 4, ipath))
    frows, paths = files_rows(r, b)
    nfiles = sum(1 for x in frows if x["mark"])
    if frows:
        tasks = os.path.join(r.spec, "tasks.md")
        files = [x for x in frows if x["mark"]]
        cut = frows
        if len(files) > 8:
            last = [i for i, x in enumerate(frows) if x["mark"]][7]
            cut = frows[:last + 1]
        tail = [cell("%s %s" % (SENSITIVE_ROW, ", ".join(paths)))] if paths else []
        s = sec("files", "WHAT WILL CHANGE", cut + tail, "%d file%s; any other file asks you first"
                % (nfiles, "" if nfiles == 1 else "s"), None, tasks)
        s["total"] = len(cut) + len(tail) + nfiles - sum(1 for x in cut if x["mark"])   # `and N more` counts files
        out.append(s)
    cmds = command_rows(r)
    if cmds:
        out.append(sec("commands", "THE CHECKS RUN", cmds, None, None, os.path.join(r.spec, "tasks.md")))
    cm = r.context()
    if cm:
        flagged = [cell(e["text"], "left out" if e["kind"] == "ignore" else "not found")
                   for e in cm["rows"] if e.get("kind") in ("ignore", "gap")]
        n = len(cm["rows"])
        out.append(sec("context", "CONTEXT", flagged, "%d source%s" % (n, "" if n == 1 else "s"), plan_ops.CARD_ROWS,
                       cm["file"]))
    if r.plan and r.plan.get("tasks"):
        out.append(sec("launches", "LAUNCHES", launches(b)))
    out.append(risk_rows(r, nfiles))
    out.append(baseline())
    first = first_option(nxt)
    foot = (["You are asked again only if a check still fails after one repair, and at the commit."]
            if first.get("id") == "approve-run" else ["You are asked after every stage, and at the commit."])
    if paths:
        foot.append("Nothing under a sensitive path is repaired by rule.")
    est = estimate()
    if est:
        foot.append(est)
    foot.append("Nothing is pushed.")
    return "APPROVE BEFORE ANY CODE IS WRITTEN", out, foot


# ---- the commit ------------------------------------------------------------------------------------------------------

def last_check(name):
    rows = [x for x in load(os.path.join(TEMPER, "evidence", "check.json"), [])
            if isinstance(x, dict) and not x.get("scenario")]
    rx = {"tests": r"\btests?\b|unittest|pytest|jest", "coverage": r"coverage", "mutation": r"mutation|planted"}[name]
    hits = [x for x in rows if re.search(rx, str(x.get("claim", "")), re.I)]
    return hits[-1] if hits else None


def regression():
    """WP17: a fix run's regression test as the CLI ran it: the last RED run of the Fix ledger and the last GREEN run
    after it (test runs the CLI executed, none void; those whose claim names the regression test when there are any),
    and the regression proof row of Check; None with none recorded."""
    runs = [x for x in load(os.path.join(TEMPER, "evidence", "build.json"), []) if isinstance(x, dict)
            and x.get("executed_by") == "cli" and not x.get("voided") and isinstance(x.get("exit_code"), int)
            and re.search("test", str(x.get("claim") or ""), re.I)]
    runs = [x for x in runs if re.search("regression", str(x.get("claim"))[:200], re.I)] or runs   # its own claim first
    reds = [i for i, x in enumerate(runs) if x.get("phase") == "red" and x["exit_code"] != 0]
    greens = [i for i, x in enumerate(runs) if x.get("phase") == "green" and x["exit_code"] == 0
              and (not reds or i > reds[-1])]
    rows = [cell("RED: %s: failed (exit %d)" % (runs[reds[-1]].get("cmd") or "the test", runs[reds[-1]]["exit_code"]))
            ] if reds else []
    rows += [cell("GREEN: %s: passed" % (runs[greens[-1]].get("cmd") or "the test"))] if greens else []
    proof = [x for x in load(os.path.join(TEMPER, "evidence", "check.json"), [])
             if isinstance(x, dict) and x.get("claim") == "regression proof"]
    if proof:
        p = proof[-1]
        rows.append(cell("proof: %s" % (" ".join(str(p.get("output") or "").split()) or "exit %s" % p.get("exit_code")),
                         None if p.get("exit_code") == 0 else "open"))
    return sec("regression", "THE REGRESSION TEST", rows, None, None, os.path.join(TEMPER, "evidence", "build.json")) \
        if rows else None


def commit(b, nxt):
    r = b.r
    out = [regression()] if r.command == "fix" else []
    crit = [c for c in criteria(r) if isinstance(c, dict)]
    if crit:
        met = [c for c in crit if c.get("status") == "passed"]
        rows = [cell("%s %s" % (c.get("id"), strip_tags(c.get("text") or "")), "open")
                for c in crit if c.get("status") != "passed"]
        out.append(sec("criteria", "WHAT IS TRUE", rows, "%d of %d met" % (len(met), len(crit)), 8,
                       os.path.join(r.spec, "intent.md")))
    t = last_check("tests")
    if t is not None:
        code = t.get("exit_code")
        what = "passed" if code == 0 else "failed (exit %s)" % code if isinstance(code, int) else "recorded"
        out.append(sec("suite", "THE SUITE", [cell("%s: %s" % (t.get("cmd") or t.get("claim") or "the tests", what))]))
    else:
        out.append(sec("suite", "THE SUITE", [cell("no run is recorded", "not measured")]))
    c = last_check("coverage")
    floor = r.cfg("check.coverage-threshold", "")
    if c is not None and c.get("value") is not None:
        against = " against a floor of %s%%" % floor if floor else ""
        out.append(sec("coverage", "COVERAGE", [cell("%s%%%s" % (c["value"], against))]))
    else:
        out.append(sec("coverage", "COVERAGE", [cell("no value is recorded", "not measured")]))
    m = last_check("mutation")
    if m is not None and m.get("value") is not None:
        out.append(sec("planted_bugs", "PLANTED BUGS", [cell("%s caught, as information" % m["value"])]))
    found = r.findings()
    opens = [f for f in found if f["state"] == "open"]
    if found or r.verdict("review"):
        order = ["critical", "high", "medium", "low", "info"]
        n = {}
        for f in opens:
            n[f["severity"]] = n.get(f["severity"], 0) + 1
        levels = ", ".join("%d %s" % (n[k], k) for k in sorted(n, key=lambda k: order.index(k) if k in order else 9))
        rows = [cell("[%s] %s" % (f["severity"], f["claim"]), "open") for f in opens]
        s = sec("review", "REVIEW", rows, "open: %s" % levels if levels else "no open finding", 6,
                os.path.join(TEMPER, "evidence", "review.json"))
        done = [x for x in r.rows("review") if isinstance(x, dict) and x.get("name") == "review completed"]
        if done:   # the row review completed of the Review verdict (WP18): N of N files read
            s["rows"] = s["rows"] + [cell(done[-1].get("detail") or "", None if done[-1].get("pass") else "open")]
            s["total"] += 1
        out.append(s)
    changed = r.ctx.get("changed") or []
    if changed:
        allowed = set(plan_files(r.spec) if r.spec else [])
        hot = dict(sensitive.declared(changed, r.cfg("autonomy.park-on-touch", "")))
        outside = [f for f in changed if f not in allowed]
        rows = [cell("%s (outside the plan)" % f, "sensitive" if f in hot else None) for f in outside]
        rows += [cell(f, "sensitive") for f in changed if f in hot and f not in outside]
        note = "%d changed, %s" % (len(changed), "%d outside the plan" % len(outside) if outside else "all in the plan")
        out.append(sec("files", "FILES", rows, note, 8))
    log = [x for x in load(os.path.join(TEMPER, "rule-log.json"), []) if isinstance(x, dict)]
    rm = budget.room("gate:check", budget.Facts(r))
    if log or rm["run_used"]:
        rows = [cell("%s at %s: %s" % (x.get("kind"), STAGE_NAMES.get(x.get("stage"), x.get("stage")),
                                       x.get("what") or ""),
                    "by rule" if x.get("kind") in ("advance", "repair", "group fix", "covered", "amend") else None)
                for x in log]
        out.append(sec("rule_log", "DECIDED BY RULE", rows, "%d of %d repeats of the budget used" % (
            rm["run_used"], rm["run_limit"]), 8, os.path.join(TEMPER, "rule-log.json")))
    skips = [o for o in r.overrides if isinstance(o, dict) and o.get("stage")]
    if skips:
        out.append(sec("skips", "SKIPPED", [cell("%s: %s" % (STAGE_NAMES.get(o["stage"], o["stage"]),
                                                              o.get("reason") or ""),
                                                "skipped") for o in skips]))
    head = git("rev-parse", "--short", "HEAD")
    if head:
        dirty = [l for l in git("status", "--porcelain", "--untracked-files=all").splitlines()
                 if l[3:] and not l[3:].strip('"').startswith((".temper/", ".claude/"))]
        out.append(sec("tree", "TREE", [cell("HEAD is commit %s; %d file%s not committed yet"
                                            % (head, len(dirty), "" if len(dirty) == 1 else "s"))]))
    out.append(sec("run", "RUN", [cell(run_line(r))]))
    msg = b.commit_message()
    branch = r.state.get("branch") or ""
    rows = [cell(msg) if msg else cell("no commit: nothing to stage")]
    rows.append(cell("on %s, not pushed" % branch if branch else "not pushed"))
    out.append(sec("message", "THE COMMIT", rows))
    at_commit = (nxt.get("ask") or {}).get("id") == "commit.confirm"
    foot = (["The report follows the click, then the record of the run is committed."] if at_commit else
            ["The commit gate runs first; the report and the commit follow with no question."])
    foot.append("Nothing is pushed.")
    return "READY TO COMMIT", out, foot


def run_line(r):
    s = run_summary.summary(TEMPER, None) or {}
    ms = sum(x.get("ms") for x in r.usage if isinstance(x, dict) and isinstance(x.get("ms"), int))
    launched = sum((s.get("launches") or {}).get("by_stage", {}).values())
    asks = (s.get("asks") or {}).get("n", 0)
    return "%d min of agent time, %d launch%s, %d dialog%s" % (minutes(ms), launched, "" if launched == 1 else "es",
                                                              asks, "" if asks == 1 else "s")


# ---- a stop ----------------------------------------------------------------------------------------------------------

def stop(b, nxt):
    r = b.r
    stage = (nxt.get("ask") or {}).get("stage") or r.stage
    gate = r.gate_of(stage) or stage
    label = STAGE_NAMES.get(stage, stage)
    out = []
    rows = [cell("%s: %s" % (x.get("name"), x.get("detail") or "")) for x in failed_rows(r, stage)]
    run = output_ops.last_failed(TEMPER, gate)
    if run is not None:
        rows += [cell(str(x)) for x in (run.get("fail_lines") or [])][:5]
    if not rows:
        last = [x for x in load(os.path.join(TEMPER, "rule-log.json"), [])
                if isinstance(x, dict) and x.get("kind") == "stop"]
        rows = [cell(last[-1].get("what") or "the run stopped here")] if last else [cell("the run stopped here")]
    out.append(sec("what_fails", "WHAT FAILS", rows, None, 8, os.path.join(TEMPER, "gates.json")))
    key = "gate:%s" % gate
    rm = budget.room(key, budget.Facts(r))
    tried = [cell(k) for k in budget.kinds(key, budget.Facts(r))] or [cell("no repeat yet: this is its first failure")]
    out.append(sec("tried", "WHAT WAS TRIED", tried, "%d of %d repeats for this failure, %d of %d for the run" % (
        rm["used"], rm["limit"], rm["run_used"], rm["run_limit"])))
    t = b.acc_triage() if stage == "check" else {}
    if t.get("verdict"):
        out.append(sec("reading", "THE READING", [cell("the %s looks wrong%s" % (
            t["verdict"], ": %s" % t["reason"] if t.get("reason") else ""))]))
    seq = r.seq()
    green = [STAGE_NAMES.get(s, s) for s in seq[:seq.index(stage)] if stage in seq and r.verdict(s) == "PASS"]
    if green:
        out.append(sec("still_green", "STILL GREEN", [cell(" · ".join(green))]))
    ms = sum(x.get("ms") for x in r.usage if isinstance(x, dict) and isinstance(x.get("ms"), int))
    launched = sum(1 for x in r.usage if isinstance(x, dict))
    out.append(sec("spent", "SPENT", [cell("%d min of agent time, %d launch%s" % (minutes(ms), launched,
                                                                                 "" if launched == 1 else "es"))]))
    alone = r.state.get("run_mode") == "autonomous" and r.state.get("unattended_from") and r.state.get("parked")
    foot = ["After your answer the run goes on by itself." if alone else
            "After your answer the run asks you at each stage.",
            "Nothing is pushed."]
    return "STOPPED: %s DID NOT PASS" % label.upper(), out, foot


# ---- the text form ---------------------------------------------------------------------------------------------------

def wrap(text, width, indent="", hang="  "):
    """A row wrapped to the width: a line after the first is indented two more spaces (`hang`), as panel.py rows."""
    return textwrap.wrap(str(text), width, subsequent_indent=indent + hang, initial_indent=indent,
                         break_long_words=True, break_on_hyphens=False) or [indent]


def marked(text, mark, width):
    """One row: indented one space, its mark in square brackets at the right edge; a long row wraps."""
    if not mark:
        return wrap(text, width, " ")
    tag = "[%s]" % mark
    lines = wrap(text, width - len(tag) - 1, " ")
    last = lines[-1]
    lines[-1] = last + " " * max(1, width - len(last) - len(tag)) + tag
    return lines


GLYPH = {"create": "+", "modify": "~", "sensitive": "!"}


def files_lines(rows, width):
    """The files section: a line a group, its title padded, each file with + (create), ~ (modify) or ! (sensitive); a
    line that holds a sensitive file ends in its mark, and a long one goes on under the first file."""
    groups, cur = [], None
    for x in rows:
        if x.get("mark") in GLYPH:
            if cur is None:
                cur = ["", []]
                groups.append(cur)
            cur[1].append(x)
        else:
            cur = [x["text"], []]
            groups.append(cur)
    pad = min(24, max([len(g[0]) for g in groups if g[1]] or [0]))
    out = []
    for name, files in groups:
        if not files:
            out += wrap(name, width, " ")
            continue
        tag = "[sensitive]" if any(f["mark"] == "sensitive" for f in files) else ""
        room = width - (len(tag) + 1 if tag else 0)
        head = " " + name.ljust(pad)
        lines, cur = [], head
        for f in files:
            unit = "%s %s" % (GLYPH[f["mark"]], f["text"])
            if cur.strip() and len(cur) + 2 + len(unit) > room and cur != head:
                lines.append(cur)
                cur = " " * len(head)
            cur += "  " + unit
        lines.append(cur)
        if tag:
            lines[-1] += " " * max(1, width - len(lines[-1]) - len(tag)) + tag
        out += lines
    return out


def render(card, width=WIDTH):
    """The rows of the card: the title left and the tag right, then each section (its title with the note in brackets,
    its rows indented one space with the mark at the right edge, `and N more: FILE` when cut; a short section is one row
    that starts with its title), a blank row between sections, the foot last. No box border."""
    if not isinstance(card, dict):
        return []
    title, tag = str(card.get("title") or ""), str(card.get("tag") or "")
    if len(title) + len(tag) + 2 <= width:
        out = [title + " " * (width - len(title) - len(tag)) + tag]
    else:
        out = wrap(title, width) + [tag]
    prev = None
    for s in card.get("sections") or []:
        rows = [x for x in s.get("rows") or [] if isinstance(x, dict)]
        short = s.get("id") in SHORT
        # a blank row between sections; a short section follows a short one directly, and NOT IN SCOPE goes on from
        # the criteria
        if not (short and (prev is None or prev in SHORT or s.get("id") in JOINS)):
            out.append("")
        prev = s.get("id")
        if short:
            said = " · ".join("%s%s" % (x.get("text"), " [%s]" % x["mark"] if x.get("mark") else "") for x in rows)
            out += wrap("%s: %s" % (s.get("title"), said), width)
            continue
        out += wrap("%s%s" % (s.get("title"), " (%s)" % s["note"] if s.get("note") else ""), width)
        if s.get("id") == "files":
            out += files_lines(rows, width)
        else:
            for x in rows:
                out += marked(x.get("text"), x.get("mark"), width)
        more = int(s.get("total") or 0) - len(rows)
        if more > 0:
            out += wrap("and %d more: %s" % (more, s.get("file") or "the run's files"), width, " ")
    foot = " ".join(str(x) for x in card.get("foot") or [])
    if foot:
        out += wrap(foot, width, "", "")
    return out


def main(argv):
    if len(argv) == 3 and argv[1] == "text":
        d = load(argv[2], {})
        rows = render(d.get("card"), WIDTH)
        if rows:
            print("\n".join(rows))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
