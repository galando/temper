"""flow_base.py: the tables and headers of the flow, the readers of the run's files, and the CLI's own checks.

A module of the flow; scripts/flow.py is its facade. Standard library only.
"""

import json
import os
import re
import shlex
import subprocess

import tasks_md


VERSION = 1

TEMPER = ".temper"
GATE_HEADER = "Temper gate"
GROUP_HEADER = "Build group"
RESUME_HEADER = "Temper resume"
DRIFT_HEADER = "Scope drift"
DRIFT_PREFIX = "Outside the plan:"
DRIFT_OPTIONS = ["Add to plan", "Revert", "Allow once"]
FRESH_ROWS = ("fresh review ran", "fresh reader's paraphrase", "no open plan blockers")   # the plan gate rows of fresh_review.py
SEQ = {"temper": ["intent", "plan", "design", "build", "review", "check", "commit"],
       "fix": ["rca", "fix", "review", "check", "commit"]}
LABEL = {"intent": "Intent", "plan": "Plan", "design": "Design", "build": "Build", "review": "Review",
         "check": "Check", "commit": "Commit", "pipeline": "Pipeline", "rca": "RCA", "fix": "Fix"}
# The stage a gate verdict is kept under: a fix run's Fix stage is judged by the build gate.
GATE_OF = {"fix": "build", "rca": None}
# The stages a step back goes to, from a failed stage.
BACK_TO = {"temper": {"plan": "intent", "design": "plan", "build": "plan", "review": "build", "check": "build"},
           "fix": {"review": "fix", "check": "fix"}}
# Every move an option of a question may carry (the `move` of view.json's options): each is the person's answer, and
# the mod lets an option's CLI calls through only on that answer. opt() refuses any other, so this list is the checked one.
MOVES = {"advance", "approve", "arm", "override", "back", "redo", "accept", "covered", "keep", "commitOverride", "restart",
         "confirm", "drift", "answer", "pause", "adhoc"}


# ---- reading the run -----------------------------------------------------------------------

def loop_at(l):
    """When a step back last ran: each step writes `at` (loop_step.py); a loop written before that has only `started`."""
    return str(l.get("at") or l.get("started") or "")


def read_json(path, default):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, type(default)) else default
    except (OSError, ValueError):
        return default


def read_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError):
        return ""


def scoped_notes(rows, task, group):
    """The notes for one Build task: `Task N: text` for task N, `Group G<n>: text` for every task of that group, and a note
    with no such prefix for all tasks. Each is returned as the person wrote it."""
    out = []
    for x in rows:
        claim = str(x.get("claim") or "")
        m = re.match(r"^(Task|Group)\s+(\S+?):", claim)
        if not m:
            out.append(claim)
        elif m.group(1) == "Task" and m.group(2) == str(task):
            out.append(claim)
        elif m.group(1) == "Group" and m.group(2) == str(group):
            out.append(claim)
    return out


def git(*args):
    try:
        r = subprocess.run(["git"] + list(args), capture_output=True, text=True, timeout=20)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


CARRY = "Carry forward"


def blocking_asks(items, cli):
    """9.8.0: each Blocking question as the session asks it, built by the CLI: `{question, answer, carry}`. `question` is the
    AskUserQuestion entry (header `Question N`, the text before `choices:`, the choices as options with the first marked
    recommended, at most three, then Carry forward); `answer` is the call that writes the person's answer into intent.md
    (`{answer}` is theirs: the label they chose or the text they typed), `carry` the call for Carry forward. Before, the
    session built each question from the line and then edited intent.md itself."""
    out = []
    for i, item in enumerate(items):
        m = re.match(r"^(.*?)\s+choices:\s*(.+?)\.?\s*$", item, re.I | re.S)
        q, cs = (m.group(1).strip(), [c.strip() for c in m.group(2).split("|") if c.strip()][:3]) if m else (item.strip(), [])
        opts = [{"label": c, "description": "Recommended" if k == 0 else ""} for k, c in enumerate(cs)]
        if not opts:   # a question with no ready answers: the person types the answer in Other
            opts = [{"label": "Type the answer", "description": "Type it in Other; this option alone answers nothing."}]
        opts.append({"label": CARRY, "description": "Keep it on record as Deferred; it no longer holds the gate."})
        out.append({"question": {"header": "Question %d" % (i + 1), "question": q, "multiSelect": False, "options": opts},
                    "answer": "%s intent answer %s '{answer}'" % (cli, shlex.quote(q)),
                    "carry": "%s intent carry %s" % (cli, shlex.quote(q))})
    return out


# ---- the CLI's own checks -----------------------------------------------------------------------

def advance_ok(run, done, nxt):
    """Whether `state advance <done> <nxt>` may move the run, and why not. One place for the rule:
    a run leaves the stage it is at, to the stage that comes next in its own sequence, once the
    stage's check passed or the person skipped it (ADR 0013)."""
    if not run.active:
        return "no active run (temper state init first)"
    if not done.endswith("_complete"):
        return "'%s' is not <stage>_complete" % done
    stage = done[: -len("_complete")]
    seq = run.seq()
    if stage not in seq:
        return "'%s' is not a stage of this run (%s)" % (stage, " ".join(seq))
    if stage != run.stage:
        return "the run is at %s, not at %s; a stage is left only from where the run is" % (run.stage, stage)
    expected = run.next_of(stage)
    if nxt != expected:
        return "after %s the next stage of this run is %s, not %s" % (stage, expected, nxt)
    if stage == "rca":
        return None
    if run.verdict(stage) == "PASS" or run.skip(stage) is not None:
        return None
    v = run.verdict(stage)
    if v is None:
        return "%s has no verdict yet: run temper gate %s first" % (stage, run.gate_of(stage))
    return ("%s failed its check and nobody skipped it: ask the person, who may skip it with "
            "temper override %s --reason '...'" % (stage, run.gate_of(stage)))


def plan_files(run_or_spec):
    """The files a plan allows: the backticked paths of the Files to Create and Files to Modify
    tables of plan.md, and of the **File:** lines of tasks.md."""
    spec = run_or_spec
    out = []
    active, level = False, 0
    for line in read_text(os.path.join(spec, "plan.md")).split("\n"):
        h = re.match(r"^(#{2,6})\s+(.*?)\s*$", line)
        if h:
            if active and len(h.group(1)) <= level:
                active = False
            if re.match(r"^files to (?:create|modify)$", h.group(2), re.I):
                active, level = True, len(h.group(1))
            continue
        if active and line.lstrip().startswith("|"):
            cells = line.split("|")
            out += path_tokens(cells[1] if len(cells) > 1 else "")
    tasks = os.path.join(spec, "tasks.md")
    if os.path.isfile(tasks):
        for t in tasks_md.parse(tasks).get("tasks", []):
            out += t.get("files", [])
    return list(dict.fromkeys(out))


def path_tokens(text):
    out = []
    for m in re.finditer(r"`([^`]+)`", text):
        t = m.group(1).strip()
        if re.fullmatch(r"[\w.@\-/*?]+", t) and ("/" in t or "." in t) and t.lower() != "none":
            out.append(t[2:] if t.startswith("./") else t)
    return out


# ---- the view ----------------------------------------------------------------------------------

def same_failure(a, b):
    """9.8.5: two failure texts name the same failure when they differ only in their numbers (a count that grows each run,
    `green=1` then `green=2`, made an end to end replay recommend "Run Build again" 72 times)."""
    norm = lambda t: re.sub(r"\d+", "#", " ".join(str(t).split()))
    return norm(a) == norm(b)


def goes_on(plural):
    return "The run goes on when %s." % ("they return" if plural else "it returns")


def short_model(model):
    """The name a person knows a model by: claude-haiku-5-5 is haiku. Any other name stays as it is."""
    m = re.match(r"^claude-(haiku|sonnet|opus|fable)-\d", str(model))
    return m.group(1) if m else str(model)


def on_model(agents):
    """ on <model>: the model each agent is launched on, as `next` names it (what Temper asks for, not the model that
    served each turn)."""
    models = sorted({short_model(a.get("model")) for a in agents if a.get("model")})
    return " on %s" % ", ".join(models) if models else ""


def criteria(run):
    if not run.spec or not os.path.isfile(os.path.join(run.spec, "intent.md")):
        return []
    try:
        import acceptance
        report = acceptance.status_report(os.path.join(run.spec, "intent.md"), os.path.join(TEMPER, "evidence"))
    except Exception:
        return []
    return report.get("criteria", [])


# ---- design.md's Areas of Concern -------------------------------------------------------------------------------------

CONCERN_STRUCT = {"open", "resolved", "closed", "accepted", "deferred", "open concerns", "resolved concerns", "closed concerns"}


def concern_blocks(lines):
    """The concerns of design.md's Areas of Concern section: one per heading under it (a heading such as "Open" or
    "Resolved" only groups them), else one per list item at the margin. Each is {title, start, end, item, resolved}; end
    is the line after its last non blank line, and a concern is resolved when a line of it starts with `resolved:`."""
    sec = None
    for i, l in enumerate(lines):
        m = re.match(r"^(#{1,6})\s+(.*)$", l)
        if m and re.search(r"areas of concern", m.group(2), re.I):
            sec = (i, len(m.group(1)))
            break
    if sec is None:
        return []
    start, lvl = sec
    end = next((j for j in range(start + 1, len(lines)) if (lambda m: m and len(m.group(1)) <= lvl)(re.match(r"^(#{1,6})\s", lines[j]))), len(lines))
    body = range(start + 1, end)

    def text(l):
        return re.sub(r"[*_`]", "", re.sub(r"^\s*(?:#{1,6}|[-*]|\d+[.)])\s+", "", l)).strip()

    def none_flagged(t):
        return t.lower().startswith("none flagged")

    subs = [j for j in body if re.match(r"^#{%d,6}\s+\S" % (lvl + 1), lines[j])]
    heads = [j for j in subs if text(lines[j]).lower().rstrip(":") not in CONCERN_STRUCT and not none_flagged(text(lines[j]))]
    if heads:
        starts, bounds, item = heads, subs + [end], False
    else:
        starts = [j for j in body if re.match(r"^(?:[-*]|\d+[.)])\s+\S", lines[j]) and not none_flagged(text(lines[j]))]
        bounds, item = [j for j in body if re.match(r"^(?:[-*]|\d+[.)])\s+\S", lines[j])] + [end], True
    out = []
    for h in starts:
        stop = min(b for b in bounds if b > h)
        while stop > h + 1 and not lines[stop - 1].strip():
            stop -= 1
        res = any(re.match(r"^\s*(?:[-*]\s+)?(?:\*\*|__)?resolved\s*:", lines[k], re.I) for k in range(h, stop))
        out.append({"title": text(lines[h])[:90], "start": h, "end": stop, "item": item, "resolved": res})
    return out


def open_concerns(path):
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return []
    return [b["title"] for b in concern_blocks(lines) if not b["resolved"]]


def design_accept(path, when):
    """Leaving Design with open concerns is the person's acceptance of them: each gets a `resolved:` line saying so, as a
    paragraph of its own after a blank line (right below a list item or a paragraph, Markdown would join it to that
    text); under a list item concern it is indented to the item's text, so it stays in that item."""
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return 0
    todo = [b for b in concern_blocks(lines) if not b["resolved"]]
    for b in sorted(todo, key=lambda b: b["start"], reverse=True):
        m = re.match(r"^(?:[-*]|\d+[.)])\s+", lines[b["start"]]) if b["item"] else None
        lines[b["end"]:b["end"]] = ["", "%sresolved: accepted as written at the Design question (%s)" % (
            " " * len(m.group(0)) if m else "", when)]
    if todo:
        tmp = "%s.tmp.%d" % (path, os.getpid())
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        os.replace(tmp, path)
    return len(todo)
