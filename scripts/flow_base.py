"""flow_base.py: the tables and headers of the flow, the readers of the run's files, and the CLI's own checks.

A module of the flow; scripts/flow.py is its facade. Standard library only.
"""

import json
import os
import re
import shlex
import subprocess

import intent_parse
import tasks_md


VERSION = 1

TEMPER = ".temper"
GATE_HEADER = "Temper gate"
GROUP_HEADER = "Build group"
RESUME_HEADER = "Temper resume"
DRIFT_HEADER = "Scope drift"
DRIFT_PREFIX = "Outside the plan:"
DRIFT_OPTIONS = ["Add to plan", "Revert", "Allow once"]
# the ids of the three, at their places: a list of its own beside the options, which readers take as labels
DRIFT_IDS = [{"id": "add-to-plan"}, {"id": "revert"}, {"id": "allow-once"}]
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
         "confirm", "drift", "answer", "pause", "adhoc", "grant", "repair"}
# WP16: the closed list of what an option or a step needs beyond its calls (its `needs`). Three are navigation the run
# driver does itself (more, accept, cancel); the other seven are the hand back kinds, each one step the conversation
# does for the person, then it stops. opt() refuses any other, and a `do` text with no needs.
NEEDS = {"more", "accept", "cancel", "talk", "html-review", "depth-review", "config-suggestions", "small-change", "pull-request",
         "pipeline-fix"}
# WP16: the two steps of the flow that are no CLI call and that the run driver does itself, by kind: the report shown as
# temper report printed it (`show-last`) and the note of a run with nothing to stage (`note`). Beside an action's or an
# option's `steps`, `step_kinds` gives each step its kind ("" for any other), so a reader selects by kind, never by text.
REPORT_STEP = ("Copy what temper report printed into your reply, as it printed it, in a code block: the person does not "
               "see the output of a Bash call.")
NO_RECORD_STEP = ("There is no record commit: no uncommitted code, no lesson file, and the spec folder is git-ignored or "
                  "unchanged, so there is nothing to stage.")
STEP_KINDS = {REPORT_STEP: "show-last", NO_RECORD_STEP: "note"}


def step_kinds(steps):
    """The kind of each step ("" for a CLI call or a step of the conversation), or None when no step has one."""
    kinds = [STEP_KINDS.get(s, "") for s in steps or []]
    return kinds if any(kinds) else None


def with_step_kinds(d):
    """`d` (an action or an option) with `step_kinds` beside its `steps`, when a step has a kind."""
    kinds = step_kinds(d.get("steps"))
    if kinds:
        d["step_kinds"] = kinds
    return d


# 9.8.5 (WP04): the ids of the protocol. Every question of `next`, `go` and view.json has an `id` of QUESTIONS and its
# `kind`; every option an `id` of OPTION_IDS, a `kind` when a reader acts on it, and `recommended: true` when it is the
# recommended one. Readers select by these, never by label text; the label stays what the person reads and what an answer
# is matched on. The closed list is section 5 of docs/plans/one-go/contracts.md. question() and opt() refuse any other id.
QUESTION_KINDS = ("gate", "group", "resume", "drift", "blocking", "context", "reason", "name")
OPTION_KINDS = ("more", "accept", "cancel", "carry", "type")
# A question id is `<stage or scope>.<state>`; sites that share one decision share one id. `decision` says what only the
# person can decide there.
QUESTIONS = {
    "intent.accept": {"kind": "gate", "decision": "Whether the intent is right, so the run goes on to Plan with it."},
    "intent.fail": {"kind": "gate", "decision": "Whether to correct the intent or skip its failed check."},
    "intent.blocking": {"kind": "blocking", "decision": "The answer to an open question of the intent, or that it waits."},
    "rca.approve": {"kind": "gate", "decision": "Whether the root cause is right, so the fix is written from it."},
    "plan.approve": {"kind": "gate", "decision": "Whether the plan is approved, and whether the run then asks at every stage."},
    "plan.fail": {"kind": "gate", "decision": "Whether to revise the plan, keep a finding, step back or skip the failed check."},
    "plan.context": {"kind": "context", "decision": "Whether the plan reads the right context, or what it should read."},
    "design.pass": {"kind": "gate", "decision": "Whether the design is accepted, its open concerns as written, before Build."},
    "design.fail": {"kind": "gate", "decision": "Whether to step back to Plan or skip the failed check of the design."},
    "build.pass": {"kind": "gate", "decision": "Whether the change is right as built, or what to change."},
    "build.fail": {"kind": "gate", "decision": "Whether Build runs again, steps back, skips the check or is saved."},
    "build.ungrouped": {"kind": "gate", "decision": "Whether Plan runs again to write the tasks in groups."},
    "build.foreign": {"kind": "gate", "decision": "Whether commits the CLI did not make are taken out or kept."},
    "fix.pass": {"kind": "gate", "decision": "Whether the fix is right as written, or what to change."},
    "fix.fail": {"kind": "gate", "decision": "Whether Fix runs again, steps back, skips the check or is saved."},
    "task.covered": {"kind": "gate", "decision": "Whether a task an earlier task built is taken as done."},
    "task.env": {"kind": "gate", "decision": "Whether the environment is repaired, so the kept work is checked again."},
    "task.manual": {"kind": "gate", "decision": "Whether each Case of a manual task holds, confirmed by hand."},
    "group.pass": {"kind": "group", "decision": "Whether a passed group is right, or what to change in it."},
    "group.change": {"kind": "group", "decision": "Which task of the group changes."},
    "group.fail": {"kind": "group", "decision": "What happens to a group whose check failed."},
    "group.parked": {"kind": "group", "decision": "What happens to a group that stopped."},
    "review.pass": {"kind": "gate", "decision": "Whether the change goes on to Check with the open findings, or is repaired."},
    "review.fail": {"kind": "gate", "decision": "Whether to repair the findings, keep one or skip the failed check."},
    "check.pass": {"kind": "gate", "decision": "Whether the change is committed, and how."},
    "check.fail": {"kind": "gate", "decision": "What happens to a failed check: run again, confirm, step back, skip or save."},
    "pipeline.pass": {"kind": "gate", "decision": "Whether the run ends once every job passed."},
    "pipeline.fail": {"kind": "gate", "decision": "Whether the CI fix is applied and pushed, or the run ends."},
    "commit.confirm": {"kind": "gate", "decision": "Whether the change is committed."},
    "commit.fail": {"kind": "gate", "decision": "Whether to add the files to the plan, step back or skip the failed gates."},
    "adhoc.fail": {"kind": "gate", "decision": "Whether a small change whose Review failed is redone or let through."},
    "run.restart": {"kind": "resume", "decision": "Whether the saved run state goes, so a new run starts."},
    "scope.drift": {"kind": "drift", "decision": "Whether a file outside the plan is added to it, reverted or allowed once."},
    "run.budget": {"kind": "gate", "decision": "Whether the run is saved, or allowed two more repeats of a failed check."},
    "base.red": {"kind": "gate", "decision": "Whether a fault of the environment or a red base is repaired first, or the run "
                 "goes on with the base's failures as a recorded skip."},
    "plan.command": {"kind": "gate", "decision": "Whether a command the plan wrote that fails or times out on the base gets "
                     "more time, another command, a revised plan or a skip with a reason."},
    "config.tidy": {"kind": "gate", "decision": "Whether the lines of an older config that only repeat old defaults, or are "
                    "no longer read, are removed so the new defaults apply, or the file is kept as it is."},
    "repair.stop": {"kind": "gate", "decision": "What happens to a repair in the stage that the rule may not resolve, or that "
                    "was reverted: revert it, repair again, step back, keep a finding, skip the check or save."},
}
# A follow up question takes its parent's id and one of these suffixes: a More question asks its parent's decision, an
# accept question keeps a finding, a reason question asks the reason the report shows, a name question a typed value.
FOLLOW_UPS = {"more": None, "accept": "gate", "reason": "reason", "name": "name"}
FOLLOW_DECISION = {"accept": "Which open finding is kept as it is, with a reason.",
                   "reason": "The reason for the answer, which the report shows.",
                   "name": "The value the answer needs, typed by the person: a name or a command."}
OPTION_IDS = frozenset((
    # the names section 5 of docs/plans/one-go/contracts.md fixes
    "approve-run", "ask-every-stage", "continue", "commit", "back", "redo", "override", "save", "more", "accept-finding",
    "small-change", "confirm", "as-planned", "carry", "cancel", "type", "add-setup", "start-over",
    "choice-1", "choice-2", "choice-3", "choice-4",
    # the rest of the head, by the rule: one id a meaning
    "grill-me", "teach-me", "html-review", "share-review", "revise-plan", "fresh-review", "fresh-again",
    "walk-through", "change", "depth-review", "commit-pr", "commit-stacked-prs", "config-suggestions", "restore-tests",
    "correct-test", "end-run", "apply-fix", "new-branch", "merge-groups", "take-out",
    "keep-commits", "accept-done", "fix-group", "change-command", "add-to-plan", "include-left-out",
    "revert", "allow-once",
    # WP08
    "check-again", "it-is-the-code",
    # WP10
    "grant-more",
    # WP14
    "run-design",
    # WP20
    "go-on-anyway",
    # WP21
    "more-time",
    # WP22
    "run-anyway",
    # WP24
    "repair-again", "revert-repair",
    # WP25: a file no task declares, added to the blocked task by the person's plan patch
    "add-file",
    # WP29: the two answers of the one time config question
    "tidy-config", "keep-config"))


def question_entry(qid):
    """The registry's entry of a question id, `{"kind", "decision"}`, or None when it is no id of the registry. A follow
    up's entry is its parent's, with the kind and the decision of its suffix (a More question asks its parent's decision)."""
    if not isinstance(qid, str):
        return None
    if qid in QUESTIONS:
        return QUESTIONS[qid]
    parent, _, suffix = qid.rpartition(".")
    up = question_entry(parent) if suffix in FOLLOW_UPS else None
    if up is None:
        return None
    return {"kind": FOLLOW_UPS[suffix] or up["kind"], "decision": FOLLOW_DECISION.get(suffix, up["decision"])}


def choice_id(i, n):
    """The id of the i-th of n ready answers (a task, a finding) as they land in questions of four options at most: the
    first three and More options, the rest in the More question, split the same way again (question())."""
    while n > 4 and i >= 3:
        i, n = i - 3, n - 3
    return "choice-%d" % (i + 1)


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
    recommended, at most three, then Carry forward), exactly as the dialog takes it, and beside it `question_ids`: the
    question's id and kind and each option's id in order, Carry forward with the kind `carry`; `answer` is the call that writes the person's answer into intent.md
    (`{answer}` is theirs: the label they chose or the text they typed), `carry` the call for Carry forward. Before, the
    session built each question from the line and then edited intent.md itself."""
    out = []
    for i, item in enumerate(items):
        m = re.match(r"^(.*?)\s+choices:\s*(.+?)\.?\s*$", item, re.I | re.S)
        q, cs = (m.group(1).strip(), [c.strip() for c in m.group(2).split("|") if c.strip()][:3]) if m else (item.strip(), [])
        opts = [{"label": c, "description": "Recommended" if k == 0 else ""} for k, c in enumerate(cs)]
        ids = [{"id": "choice-%d" % (k + 1)} for k in range(len(cs))]
        if not opts:   # a question with no ready answers: the person types the answer in Other
            opts = [{"label": "Type the answer", "description": "Type it in Other; this option alone answers nothing."}]
            ids = [{"id": "type", "kind": "type"}]
        opts.append({"label": CARRY, "description": "Keep it on record as Deferred; it no longer holds the gate."})
        ids.append({"id": "carry", "kind": "carry"})
        out.append({"question": {"header": "Question %d" % (i + 1), "question": q, "multiSelect": False, "options": opts},
                    "question_ids": {"id": "intent.blocking", "kind": "blocking", "options": ids},
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
    if stage == "plan" and run.blocking():
        # WP14: what Design asked is now a Blocking question Plan writes; it is answered before the plan is approved, with
        # the mod or without it
        return ("intent.md holds %d open Blocking question(s) (%s): answer each with temper intent answer, or carry it "
                "forward with temper intent carry, before the plan is approved" % (len(run.blocking()), run.blocking()[0][:120]))
    if stage == "plan" and intent_parse.status(run.intent) == "draft":
        # WP12: the approval is of an accepted intent; a draft is accepted first (temper intent accept)
        return "intent.md is a draft: the intent is accepted (temper intent accept) before the plan is approved"
    if run.verdict(stage) == "PASS" or run.skip(stage) is not None:
        return None
    v = run.verdict(stage)
    if v is None:
        return "%s has no verdict yet: run temper gate %s first" % (stage, run.gate_of(stage))
    return ("%s failed its check and nobody skipped it: ask the person, who may skip it with "
            "temper override %s --reason '...'" % (stage, run.gate_of(stage)))


def plan_files(run_or_spec, tables=True):
    """The files a plan allows: the backticked paths of the **File:** lines of tasks.md, and of the two file tables of
    plan.md that a plan approved by 9.8.4 or by the base holds (WP26: Plan writes those tables no more, so a new plan
    has none and its files are the **File:** lines alone). tables False: the **File:** lines alone, the files the
    approval card shows, which the approval records (`flow.py plan-files`; WP32, review finding R2d)."""
    spec = run_or_spec
    out = []
    active, level = False, 0
    for line in read_text(os.path.join(spec, "plan.md")).split("\n") if tables else []:
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
