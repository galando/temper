#!/usr/bin/env python3
"""flow.py: what a Temper run does next, and the view the mod draws (ADR 0013).

  flow.py next --ctx JSON    prints the next action of the run in the current folder, as JSON
  flow.py view --ctx JSON    writes .temper/view.json and prints nothing
  flow.py changed BASE STARTED  prints the files the run changed (for the commit steps), as JSON

`scripts/temper next --json` and the CLI's view writer call this; nothing else should. The CLI
passes what only it knows (the plugin folder, its own path, the config values, the models, the
parsed tasks.md, the schedule) in --ctx. Everything else is read from the run's own files. It never
writes a file but .temper/view.json. The schema of both outputs is in docs/flow.md; a change to it
is a change of VERSION. Standard library only.
"""

import datetime
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

import adhoc_ops
import check_run
import config_yaml
import fresh_review
import intent_parse
import plan_ops
import tasks_md
from findings import finding_state  # the one state of a finding row, the CLI's own reading (A20)
import loop_step

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


class Run:
    """The run as its files say. Nothing here decides; it only reads."""

    def __init__(self, ctx):
        self.ctx = ctx
        self.state = read_json(os.path.join(TEMPER, "build-state.json"), {})
        self.active = bool(self.state) and bool(self.state.get("next_stage"))
        self.gates = read_json(os.path.join(TEMPER, "gates.json"), {})
        self.overrides = read_json(os.path.join(TEMPER, "overrides.json"), [])
        self.loops = read_json(os.path.join(TEMPER, "feedback-loops.json"), {})
        self.groups = read_json(os.path.join(TEMPER, "groups.json"), {})
        self.usage = read_json(os.path.join(TEMPER, "usage.json"), [])
        self.command = self.state.get("command") or "temper"
        self.stage = self.state.get("next_stage") or ""
        self.slug = self.state.get("spec") or ""
        self.spec = self.state.get("spec_path") or ""
        self.config = config_yaml.load(ctx.get("config_file") or os.path.join(".claude", "temper.config"))
        tasks = os.path.join(self.spec, "tasks.md") if self.spec else ""
        self.plan = tasks_md.parse(tasks) if tasks and os.path.isfile(tasks) else None
        self.intent = read_text(os.path.join(self.spec, "intent.md")) if self.spec else ""

    @staticmethod
    def plan_core_digest(m):
        """The digest of a parsed plan, the same as the CLI's _plan_digest (None when the plan does not parse)."""
        import hashlib
        n = lambda p: p.strip()[2:] if p.strip().startswith("./") else p.strip()
        try:
            core = {"tasks": [{"n": t["n"], "group": t["group"], "files": [n(f) for f in t["files"]], "depends": t["depends"], "test": t["test"]}
                              for t in m["tasks"]],
                    "groups": [{"id": g["id"], "depends": g["depends"], "validate": g["validate"], "interfaces": g["interfaces"],
                                "context": g["context"], "tasks": g["tasks"]} for g in m["groups"]],
                    "integration": m["integration"]}
        except (KeyError, TypeError):
            return None
        return hashlib.sha256(json.dumps(core, sort_keys=True).encode("utf-8")).hexdigest()

    def tasks_changed(self):
        """True when tasks.md differs from the tasks the person approved at the plan gate (the digest `state advance
        plan_complete` recorded): Design changed them."""
        h = self.state.get("plan_hash")
        if not h or not self.plan:
            return False
        d = self.plan_core_digest(self.plan)
        return d is not None and d != h

    def tasks_change_summary(self):
        """What changed in the tasks since the plan gate, in a few words each ("Task 1 gains src/floor.sh", "new Task 7"),
        from the copy the CLI kept at the plan gate; [] when there is no copy of the approved tasks."""
        old = read_json(os.path.join(TEMPER, "evidence", "approved-tasks.json"), {})
        if not old or not self.plan or self.plan_core_digest(old) != self.state.get("plan_hash"):
            return []
        was = {t["n"]: t for t in old.get("tasks", [])}
        now = {t["n"]: t for t in self.plan.get("tasks", [])}
        out = []
        for k in sorted(set(now) - set(was)):
            out.append("new Task %s (%s)" % (k, ", ".join(now[k].get("files") or []) or "no file"))
        for k in sorted(set(was) - set(now)):
            out.append("Task %s removed" % k)
        for k in sorted(set(was) & set(now)):
            a, b = was[k], now[k]
            gained = [f for f in b.get("files", []) if f not in a.get("files", [])]
            lost = [f for f in a.get("files", []) if f not in b.get("files", [])]
            if gained:
                out.append("Task %s gains %s" % (k, ", ".join(gained)))
            if lost:
                out.append("Task %s drops %s" % (k, ", ".join(lost)))
            if a.get("test") != b.get("test"):
                out.append("Task %s has a new Test command" % k)
            if a.get("depends") != b.get("depends"):
                out.append("Task %s depends on other tasks" % k)
        if not out:
            out.append("the groups or the integration command")
        return out

    def notes(self, stage, kind=None):
        """The notes of the stage (temper evidence add --phase note): the person's words for the next agent (input) or a
        change the orchestrator made for them (edit), oldest first."""
        rows = read_json(os.path.join(TEMPER, "evidence", "%s.json" % stage), [])
        return [x for x in rows if isinstance(x, dict) and x.get("phase") == "note" and x.get("claim")
                and (kind is None or (x.get("kind") or "input") == kind)]

    def stale_notes(self, stage, kind):
        """The notes of the stage newer than its recorded verdict; none when the stage has no verdict time."""
        g = self.gates.get(self.gate_of(stage) or "")
        at = str(g.get("ts") or "") if isinstance(g, dict) else ""
        return [x for x in self.notes(stage, kind) if at and str(x.get("ts") or "") > at]

    def missing_records(self, stage):
        """When the stage's gate fails only for success criteria that lack a row the CLI could record (a scenario with no CLI
        run row or no Test: line, a Validate: code criterion with no row), the lines of those rows; else []. A row that
        exists and failed (an exit code) is not one of them: that keeps the gate question."""
        rows = self.failed_rows(stage)
        if stage != "build" or len(rows) != 1 or rows[0].get("name") != "criteria validated":
            return []
        found = []
        for m in re.finditer(r"(AC-\d+) FAIL: (.*?)(?<=\.)(?:\s|$)", str(rows[0].get("detail") or "")):
            what = m.group(2)
            sm = re.match(r"scenario '(.*?)' \((.*)\) has no row run by the CLI\.?$", what)
            if sm:
                found.append("Record scenario: %s (%s)." % (sm.group(1), sm.group(2)))
            elif "no passing row records it" in what:
                found.append("Record criterion: %s (Validate: code)." % m.group(1))
            else:
                return []
        return found

    def round_id(self):
        """What marks one round of a stage: the latest Run Build again and the latest step back."""
        return "%s|%s" % ((self.state.get("redo") or {}).get("ts", ""), (self.latest_loop() or {}).get("at") or (self.latest_loop() or {}).get("started", ""))

    def cfg(self, key, default=""):
        v = config_yaml.get(self.config, key, default)
        return default if v is None or v == "" else str(v)

    def on(self, key, default=False):
        v = self.cfg(key, "true" if default else "false").lower()
        return v in ("true", "yes", "on", "1")

    def seq(self):
        s = list(SEQ.get(self.command, SEQ["temper"]))
        if self.command == "temper" and not self.has_design():
            s.remove("design")
        # Pipeline follows a Commit that opened a pull request, unless phases.pipeline is false
        if self.command == "temper" and self.cfg("phases.pipeline", "true").lower() != "false" and (
                self.state.get("pr") in ("one", "stacked") or self.stage == "pipeline"):
            s.append("pipeline")
        return s

    def open_concerns(self):
        return open_concerns(os.path.join(self.spec, "design.md")) if self.spec else []

    def fresh(self):
        """The fresh review of the plan (9.7.6, scripts/fresh_review.py): whether it applies or is offered, what ran on the
        spec files as they are, the reader's paraphrase and the findings."""
        if not self.spec or self.command != "temper":
            return {"applies": False, "offer": False, "launched": False, "stale": False, "capped": False, "missing": [], "need": [],
                    "lazy": [], "findings": [], "contests": [], "paraphrase": "", "paraphrase_short": False, "rounds": 0, "cap": 0}
        return fresh_review.status(self.spec, os.path.join(TEMPER, "evidence", "plan.json"), os.path.join(TEMPER, "build-state.json"),
                                   self.cfg("plan.fresh-review", "ask"), self.cfg("plan.fresh-review-twice", "true"),
                                   self.cfg("plan.fresh-review-rounds", "3"))

    def has_design(self):
        if self.command != "temper":
            return False
        if self.spec and os.path.isfile(os.path.join(self.spec, "design.md")):
            return True
        if "design" in self.gates or self.stage == "design":
            return True
        # 9.8.0: Design runs on risk, not on size. A complex plan gets it; a medium one only when its risk is H (temper risk:
        # a large blast radius, a CRITICAL or HIGH file, or Plan's raise for a data model, money, permissions or an
        # integration). Before 9.8.0 every medium plan ran Design: minutes per run, and concerns the person only approved.
        # A complex plan of a request that was fully specified (Intent asked the person nothing) skips it too, unless its
        # risk is H: the request already settled what Design would ask, and the design concerns were only approved.
        complexity = (self.state.get("complexity") or "").lower()
        risk = (self.state.get("risk") or "").upper()
        asked = bool(self.state.get("intent_asked"))
        return self.on("phases.design", True) and (risk == "H" and complexity in ("medium", "complex") or (complexity == "complex" and asked))

    def next_of(self, stage):
        s = self.seq()
        return s[s.index(stage) + 1] if stage in s and s.index(stage) + 1 < len(s) else None

    def gate_of(self, stage):
        return GATE_OF.get(stage, stage) if self.command == "fix" else stage

    def verdict(self, stage):
        g = self.gates.get(self.gate_of(stage) or "")
        return g.get("verdict") if isinstance(g, dict) else None

    def rows(self, stage):
        g = self.gates.get(self.gate_of(stage) or "")
        return g.get("requirements", []) if isinstance(g, dict) else []

    def failed_rows(self, stage):
        return [r for r in self.rows(stage) if isinstance(r, dict) and not r.get("pass")]

    def skip(self, stage):
        # the CLI's rule (_override_covers): a skip covers the verdict the person saw, recorded at or before it (or no
        # verdict); a verdict computed again after it is not covered. A skip or verdict with no time is matched by stage.
        gate = self.gate_of(stage)
        g = self.gates.get(gate or "")
        vts = str(g.get("ts") or "") if isinstance(g, dict) else ""
        hits = [o for o in self.overrides if isinstance(o, dict) and o.get("stage") == gate
                and (not vts or not o.get("ts") or str(o.get("ts")) >= vts)]
        return hits[-1] if hits else None

    def armed(self):
        # 9.8.0: no setting turns the unattended run on or off; the person arms it at the last question before Build.
        # autonomy.enabled is no longer read (it was false in the shipped config, so most runs never saw the option).
        return self.state.get("run_mode") == "autonomous"

    def active_loops(self):
        return [l for l in (self.loops.get("active_loops", []) if isinstance(self.loops, dict) else []) if isinstance(l, dict)]

    def loop_count(self, frm, to):
        for l in self.active_loops():
            if l.get("from_stage") == frm and l.get("to_stage") == to:
                return int(l.get("iteration") or 0)
        return 0

    def loop_budget(self, frm, to):
        # the one rule, the CLI's own (loop_step.budget): Build to Plan once per run, the rest by the config
        return loop_step.budget(frm, to, self.cfg)

    def can_loop(self, frm, to):
        if not self.on("feedback.enabled", True):
            return False
        return self.loop_count(frm, to) < self.loop_budget(frm, to)

    def loop_into(self, stage):
        """The latest active step back to `stage`, or None."""
        best, at = None, ""
        for l in self.active_loops():
            if l.get("to_stage") == stage and loop_at(l) >= at:
                best, at = l, loop_at(l)
        return best

    def loop_through(self, stage):
        """9.8.4: the latest active step back that went from `stage` (or a later stage) to an earlier one, or None: the run
        comes through `stage` again for the same reason (Plan to Intent, then Plan again)."""
        seq = SEQ.get(self.command, SEQ["temper"])
        if stage not in seq:
            return None
        i = seq.index(stage)
        best, at = None, ""
        for l in self.active_loops():
            f, t = l.get("from_stage"), l.get("to_stage")
            if f in seq and t in seq and seq.index(t) < i <= seq.index(f) and loop_at(l) >= at:
                best, at = l, loop_at(l)
        return best

    def latest_loop(self):
        """The latest step back to Build (or Fix), or None."""
        best, at = None, ""
        for l in self.active_loops():
            if l.get("to_stage") in ("build", "fix") and loop_at(l) >= at:
                best, at = l, loop_at(l)
        return best

    def latest_feedback(self):
        """The reason of the latest step back to Build (or Fix), or of a "Run Build again"."""
        loop = self.latest_loop() or {}
        best, at = loop.get("reason") or "", loop_at(loop)
        redo = self.state.get("redo") or {}
        if isinstance(redo, dict) and str(redo.get("ts", "")) >= at and redo.get("reason"):
            best = redo.get("reason")
        return best

    def latest_findings(self):
        """What the stage that looped back left open (the loop keeps it, as the loop clears that stage's ledger)."""
        loop = self.latest_loop() or {}
        return [str(x) for x in loop.get("findings") or [] if isinstance(x, str)]

    def title(self):
        m = re.search(r"^#\s+(?:Intent:\s*)?(.+?)\s*$", self.intent, re.M)
        return m.group(1).strip() if m else self.slug

    def blocking(self):
        # the Blocking questions the gate counts (intent_parse.py), but the Context check: the CLI asks that one itself
        return [self.house_rule_first(q) for q in intent_parse.blocking(self.intent, context_check=False)]

    @staticmethod
    def house_rule_first(q):
        """9.8.0: a choice marked `(house rule)` (what CONVENTIONS.md, CLAUDE.md, AGENTS.md or the code's own pattern
        already does) goes first, so it is the recommended answer whatever order the model wrote."""
        m = re.match(r"^(.*?\bchoices:\s*)(.+?)(\.?)\s*$", q, re.I)
        if not m:
            return q
        cs = [c.strip() for c in m.group(2).split("|")]
        house = [c for c in cs if re.search(r"\(house rule\)", c, re.I)]
        if not house:
            return q
        return m.group(1) + " | ".join(house[:1] + [c for c in cs if c is not house[0]]) + m.group(3)

    def context(self):
        """The Context Map of plan.md as `temper next` and the view carry it, or None."""
        return plan_ops.map_json(self.spec) if self.spec and os.path.isfile(os.path.join(self.spec, "plan.md")) else None

    def context_choices(self):
        """The choices of the Context check, from the Blocking line Plan wrote into intent.md (three at most)."""
        m = re.search(r"^\s*[-*]\s+Blocking:\s*Context check:.*?choices:\s*(.+?)\.?\s*$", self.intent, re.M | re.I)
        got = [c.strip().rstrip(".") for c in m.group(1).split("|")] if m else []
        return [c for c in got if c][:3] or ["Right direction", "Narrow the focus", "Fix the sources"]

    def findings(self):
        rows = read_json(os.path.join(TEMPER, "evidence", "review.json"), [])
        out = []
        for i, r in enumerate(rows, 1):
            if not isinstance(r, dict) or not r.get("severity") or r.get("claim") == "review completed":
                continue
            claim = str(r.get("claim") or "")
            m = re.match(r"^\s*([\w./@-]+\.\w+):(\d+)", claim)
            # the one reading of a finding's state (the CLI writes nested `resolved` and `accepted`, and a contest or an
            # escalation keeps the finding open: the gate still counts it, the question shows the answer)
            fs = finding_state(r)
            state = fs if fs in ("resolved", "accepted") else "open"
            conf = r.get("confidence")
            out.append({"id": i, "severity": str(r.get("severity")).lower(), "claim": claim,
                        "file": m.group(1) if m else None, "line": int(m.group(2)) if m else None,
                        "state": state, "label": r.get("label"),
                        "answer": fs if fs in ("contested", "escalated") else None,
                        "cite": (r.get("contested") or {}).get("cite"), "quote": (r.get("contested") or {}).get("quote"),
                        "confidence": conf if isinstance(conf, (int, float)) and not isinstance(conf, bool) else None})
        return out

    def open_findings(self):
        block = [s.strip().lower() for s in re.split(r"[\x1f,\s\[\]]+", self.cfg("review.block-on", "critical")) if s.strip()]
        return [f for f in self.findings() if f["state"] == "open" and f["severity"] in block]

    def spec_ignored(self):
        return bool(self.ctx.get("spec_ignored"))


# ---- building the answer ---------------------------------------------------------------------

class Builder:
    def __init__(self, run):
        self.r = run
        self.cli = run.ctx.get("cli") or "temper"
        self.plugin = run.ctx.get("plugin") or ""

    def c(self, *words):
        return " ".join([self.cli] + [w for w in words if w])

    def run_info(self):
        r = self.r
        return {"id": r.state.get("run_id"), "step": r.state.get("step"), "slug": r.slug, "stage": r.stage,
                "command": r.command, "mode": r.state.get("run_mode") or "interactive"}

    def plugin_line(self):
        return ("Plugin folder: %s; wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT "
                "variable, use this folder." % self.plugin)

    # -- options ---------------------------------------------------------------------------
    def opt(self, label, description, move=None, calls=None, steps=None, do=None, stop=False, reason=None, answer=None):
        if move is not None and move not in MOVES:
            raise ValueError("flow.py: the move %r is not in MOVES" % move)
        o = {"label": label, "description": description, "move": move, "calls": calls or []}
        if answer:  # a question whose typed answer fills {answer} in the calls (the person's name, for a manual task)
            # Two options at least, or the question tool refuses the dialog (9.8.0: a run with a manual task stopped at
            # its name question, which held Cancel alone). The first only says to type; the typed text is the answer.
            o["answer_question"] = {"header": answer[0], "question": answer[1], "multiSelect": False,
                                    "options": [{"label": "Type it below", "description": "Type the answer in the box below; this option alone records nothing."},
                                                {"label": "Cancel", "description": "Back to the question before."}]}
        if steps:
            o["steps"] = steps
        if do:
            o["do"] = do
        if stop:
            o["stop"] = True
        if reason:
            o["reason"] = True
            o["reason_question"] = {
                "header": GATE_HEADER, "question": "%s. What is the reason?" % label,
                "multiSelect": False,
                "options": [{"label": x, "description": ""} for x in reason] + [{"label": "Cancel", "description": "Back to the question before."}]}
        return o

    def save(self):
        return self.opt("Save for later", "Stop here. The run is saved; /temper:%s takes it up again." % ("fix" if self.r.command == "fix" else "temper"),
                        move="pause", stop=True)

    def skill(self, name, label, what):
        o = self.opt(label, what, do="Use the %s skill on this stage's work, then ask this question again." % name)
        o["skill"] = name   # 9.8.0: the mod lets the skill's own questions through while it runs (its session guard)
        return o

    def question(self, header, text, options, stage, more=None, extra=None):
        q = {"header": header, "question": text, "multiSelect": False,
             "options": [{"label": o["label"], "description": o["description"]} for o in options]}
        out = {"stage": stage, "step": self.r.state.get("step"), "run_id": self.r.state.get("run_id"),
               "question": q, "options": options}
        if more:
            out["more"] = more
        if extra:
            out.update(extra)
        return out

    def with_more(self, header, text, stage, first, rest, more_text):
        """At most four options a question: the first three, then "More options" with the rest."""
        if len(first) + len(rest) <= 4:
            return self.question(header, text, first + rest, stage)
        more_opt = self.opt("More options", ", ".join(o["label"] for o in rest), do="Ask the more question.")
        more = self.question(header, more_text, rest, stage)
        return self.question(header, text, first[:3] + [more_opt], stage, more=more)

    # -- the steps that leave Intent and Plan ------------------------------------------------
    def spec_commit(self, message, changes=False):
        """The spec folder's commit, only when it has something to commit: a commit with nothing staged is refused by the
        commit hook (no spec only carve out applies), which would stop the answer's calls."""
        if self.r.spec_ignored() or not self.r.spec or not (changes or self.r.ctx.get("spec_dirty")):
            return []
        # 9.8.0: one CLI call (scripts/spec_ops.py) in place of `git add` and `git commit`, which had to go in two Bash
        # calls; now every call of the answer is a temper call, run with `temper go` in one.
        return [self.c("spec commit %s" % shlex.quote(message))]

    def to_branch(self):
        """The switch to the run's branch (`feature/{slug}`) when the project is on another one: the first commit of the
        run, the accepted intent, goes there, never onto main."""
        branch = self.r.state.get("branch") or ""
        if not branch or (self.r.ctx.get("branch") or "") == branch:
            return []
        return [self.c("spec branch")]   # 9.8.0: git checkout (-b) of the run's branch, by the CLI

    def branch_clash(self):
        """The run's branch (`feature/{slug}`) exists from an earlier run, the project is on another branch, and that branch holds
        commits HEAD lacks: a plain switch would leave them behind, or carry the new spec onto old work. None when there is none."""
        r = self.r
        want = r.state.get("branch") or ""
        if not want or (r.ctx.get("branch") or "") == want or not r.ctx.get("branch_exists") or not int(r.ctx.get("branch_ahead") or 0):
            return None
        n = 2
        while subprocess.run(["git", "show-ref", "--verify", "--quiet", "refs/heads/%s-%d" % (want, n)], capture_output=True).returncode == 0:
            n += 1
        return {"branch": want, "last": r.ctx.get("branch_last") or "", "new": "%s-%d" % (want, n)}

    def carry_switch(self, branch):
        """One shell call that carries the new spec files across the switch through a temp folder (never git stash, whose stack
        every worktree shares): restore the spec folder to HEAD, switch, copy the files back. A refused switch puts them back,
        fails, and names the temp folder."""
        spec = shlex.quote(self.r.spec)
        return ('t="$(mktemp -d)" && cp -R %s/. "$t"/ && { git restore --source=HEAD --worktree -- %s 2>/dev/null; git clean -fdq -- %s; } ; '
                'if git checkout %s; then mkdir -p %s && cp -R "$t"/. %s/ && rm -rf "$t"; '
                'else mkdir -p %s && cp -R "$t"/. %s/; echo "FAIL: could not switch to %s; your spec files are in $t" >&2; exit 1; fi'
                % (spec, spec, spec, shlex.quote(branch), spec, spec, spec, spec, branch.replace('"', '')))

    def leave_intent(self, switch=True):
        """Switch to the run's branch, accept the intent (when there is one, and it is not accepted yet the accept changes
        it), commit, advance."""
        r = self.r
        has = bool(r.intent)
        # The first Status line's value, as `temper intent accept` reads it: only `accepted` or `completed` leaves the file unchanged.
        accepts = has and intent_parse.status(r.intent) not in ("accepted", "completed")
        return (self.to_branch() if switch else []) + ([self.c("intent accept")] if has else []) + \
            self.spec_commit("docs(intent): accept %s" % r.slug, changes=accepts) + [self.c("state advance intent_complete plan")]

    def leave_plan(self):
        r, nxt = self.r, self.r.next_of("plan") or "build"
        # Still on another branch (a run whose Intent was left before this step existed, or a switch since): switch now.
        return self.to_branch() + self.spec_commit("docs(plan): approve the plan of %s" % r.slug) + \
            [self.c("state advance plan_complete %s" % nxt)]

    # -- gate questions ----------------------------------------------------------------------
    def ask(self, stage):
        r = self.r
        verdict = r.verdict(stage)
        skipped = r.skip(stage) is not None
        nxt = r.next_of(stage)
        label = LABEL.get(stage, stage)
        passed = verdict == "PASS" or skipped
        back = BACK_TO.get(r.command, {}).get(stage)
        rows = r.failed_rows(stage)
        why = "; ".join("%s: %s" % (x.get("name"), x.get("detail")) for x in rows[:3])
        state_of = "the check passed" if verdict == "PASS" else ("skipped by you" if skipped else "the check failed")
        override_reasons = ["I accept the risk", "It is not a real issue"]
        back_reasons = ["The check found a real problem"]

        def back_opt(rec=False):
            if not back or not r.can_loop(stage, back):
                return []
            return [self.opt("Loop back to %s%s" % (LABEL[back], " (Recommended)" if rec else ""),
                             "Do %s again; the stages after it are redone too." % LABEL[back], move="back",
                             calls=[self.c("state loop %s %s --reason '{reason}'" % (stage, back))], reason=back_reasons)]

        def override_opt(then):
            return self.opt("Override and continue", "Skip this check with your reason; the report shows it.", move="override",
                            calls=[self.c("override %s --reason '{reason}'" % (r.gate_of(stage) or stage))] + then,
                            reason=override_reasons)

        walked = self.walked(stage)
        if walked:
            text = "%s: %s%s (this stage ran before; it is checked, not run again). Go on to %s?" % (
                label, state_of, " (%s)" % why if why and not passed else "", LABEL.get(nxt, nxt))
            go = self.leave(stage)
            if passed:
                return self.question(GATE_HEADER, text, stage=stage, options=[
                    self.opt("Continue to %s (Recommended)" % LABEL.get(nxt, nxt), "Go on to %s." % LABEL.get(nxt, nxt),
                             move=self.go_move(stage), calls=go), self.save()])
            # A stage of an earlier session leaves no evidence in this run (state init starts it empty): its check fails,
            # and the person runs it now (it and every stage after it run) or skips it.
            run = self.opt("Run %s (Recommended)" % label, "%s runs now, and every stage after it." % label, move="redo",
                           calls=[self.c("state redo %s --reason %s" % (stage, shlex.quote("the check of %s failed when the run entered at a later stage%s" % (
                               label, " (%s)" % why[:300] if why else ""))))])
            return self.question(GATE_HEADER, text, stage=stage, options=[run, override_opt(go), self.save()])

        if r.command == "fix" and stage == "rca":
            return self.question(GATE_HEADER, "RCA: the root cause is in %s/rca.md. Proceed to Fix?" % r.spec, stage=stage, options=[
                self.opt("Proceed to Fix (Recommended)", "Write the regression test and the fix.", move="approve",
                         calls=[self.c("state advance rca_complete fix")]), self.save()])

        if stage == "intent":
            clash = self.branch_clash() if passed else None
            if clash:
                text = ("Intent: %s. The branch %s already exists from an earlier run; its last commit is %s. Accept the intent and continue to Plan?"
                        % (state_of, clash["branch"], clash["last"]))
                tail = self.leave_intent(switch=False)
                return self.question(GATE_HEADER, text, stage=stage, options=[
                    self.opt("Continue on %s" % clash["branch"], "Switch to it (the new spec files go across), accept intent.md, commit it there, and start Plan.", move="approve",
                             calls=[self.carry_switch(clash["branch"])] + tail),
                    self.opt("Continue on a new branch %s" % clash["new"], "Start a new branch from here, accept intent.md, commit it there, and start Plan.", move="approve",
                             calls=["git checkout -b %s" % shlex.quote(clash["new"]), self.c("state set branch %s" % shlex.quote(clash["new"]))] + tail),
                    self.skill("grill-me", "Grill Me", "Stress test the intent first."), self.save()])
            if passed:
                return self.question(GATE_HEADER, "Intent: %s. Accept the intent and continue to Plan?" % state_of, stage=stage, options=[
                    self.opt("Continue to Plan (Recommended)", "Accept intent.md, commit it on the run's branch, and start Plan.", move="approve", calls=self.leave_intent()),
                    self.skill("grill-me", "Grill Me", "Stress test the intent first."),
                    self.skill("teach-me", "Teach Me", "Walk through the intent."), self.save()])
            return self.question(GATE_HEADER, "Intent: the check failed (%s). Correct intent.md, or skip the check?" % why, stage=stage, options=[
                override_opt(self.leave_intent()[0:1] + self.leave_intent()[1:]),
                self.skill("grill-me", "Grill Me", "Stress test the intent first."), self.save()])

        if stage == "plan":
            html = self.opt("Open HTML review", "Open the plan as a page to comment on.",
                            do="Follow %s/reference/plan-review.md (Open HTML review), then ask this question again." % self.plugin)
            share = self.opt("Share HTML review", "Publish the plan as a private Claude artifact others can comment on.",
                             do="Follow %s/reference/plan-review.md (Share HTML review), then ask this question again." % self.plugin)
            grill = self.skill("grill-me", "Grill Me", "Stress test the plan.")
            teach = self.skill("teach-me", "Teach Me", "Walk through the plan.")
            fr = r.fresh()
            # The fresh reader's paraphrase goes in the question: the person compares it with the intent (a wrong one is a finding).
            said = " A reader with no context took it as: %s." % fr["paraphrase"][:300].rstrip(".") if fr["paraphrase"] and not skipped else ""
            if passed:
                go = self.leave_plan()
                nl = LABEL.get(r.next_of("plan") or "build")
                text = "Plan: %s.%s Approve the plan and continue to %s?" % (state_of, said, nl)
                # 9.8.0: the fresh review's open findings below high pass the gate, and are the person's call: the question
                # names them and offers Revise the plan (9.8.4: never recommended; they go to the builder as notes).
                lesser = [f for f in fr["findings"] if f["state"] not in ("resolved", "accepted")] if not skipped else []
                revise = None
                if lesser:
                    shown = "; ".join("#%d [%s] %s" % (f["id"], f["severity"], f["claim"][:120]) for f in lesser[:3])
                    # 9.8.4: only a high finding blocks; a medium or low one goes to the builder as a note (in the task's
                    # prompt), so revising is offered after the ways on, never recommended: a revision is another round.
                    text = "Plan: %s.%s The fresh review left %d finding(s) open: %s%s. They go to the builder as notes. Approve the plan and continue to %s?" % (
                        state_of, said, len(lesser), shown, "; and %d more" % (len(lesser) - 3) if len(lesser) > 3 else "", nl)
                    revise = self.opt("Revise the plan",
                                      "The Plan agent fixes or contests each open finding of the fresh review; then the plan is checked again.",
                                      move="redo", calls=[self.c("state redo plan --reason %s" % shlex.quote(
                                          ("fresh review: " + "; ".join(fresh_review.describe(f) for f in lesser))[:300]))])
                # 9.8.0: the unattended run is offered at the last question before Build: here when no Design follows,
                # at the Design question when it does (so every decision is made before the run goes on by itself).
                if not r.has_design():
                    first = [self.opt("Stage by stage (Recommended)", "Approve the plan; every later stage keeps its own gate.", move="approve", calls=go),
                             self.opt("Autonomous Build: run Build unattended", "Approve the plan; Build runs every group and task by itself and parks if it stops. Review and Check then ask you as usual.",
                                      move="arm", calls=[self.c("state set run_mode autonomous")] + go), html]
                    if revise is not None:   # findings below high: revising is offered, after the ways on
                        return self.with_more(GATE_HEADER, text, stage, first[:2] + [revise], [html, grill, teach, self.save()], "Plan: more options.")
                    if fr["offer"]:   # four options a question: the offer takes Share's place, which Open HTML review leads to anyway
                        return self.with_more(GATE_HEADER, text, stage, first[:2] + [self.fresh_offer()], [html, grill, teach, self.save()], "Plan: more options.")
                    return self.with_more(GATE_HEADER, text, stage, first, [share, grill, teach, self.save()], "Plan: more options.")
                if revise is not None:
                    first = [self.opt("Continue to %s (Recommended)" % nl, "Approve the plan, commit it, and start %s." % nl, move="approve", calls=go), revise, html]
                    return self.with_more(GATE_HEADER, text, stage, first, [share, grill, teach, self.save()], "Plan: more options.")
                if fr["offer"]:
                    first = [self.opt("Continue to %s (Recommended)" % nl, "Approve the plan, commit it, and start %s." % nl, move="approve", calls=go),
                             self.fresh_offer(), html]
                    return self.with_more(GATE_HEADER, text, stage, first, [share, grill, teach, self.save()], "Plan: more options.")
                first = [self.opt("Continue to %s (Recommended)" % nl, "Approve the plan, commit it, and start %s." % nl, move="approve", calls=go), html, share]
                return self.with_more(GATE_HEADER, text, stage, first, [grill, teach, self.save()], "Plan: more options.")
            fresh_failed = [x for x in rows if x.get("name") in FRESH_ROWS]
            if fr["applies"] and fresh_failed:
                return self.fresh_question(fr, why, said, back_opt, override_opt, grill)
            return self.question(GATE_HEADER, "Plan: the check failed (%s).%s Fix the plan, or skip the check?" % (why, said), stage=stage,
                                 options=back_opt() + [override_opt(self.leave_plan()), grill, self.save()])

        if stage == "design":
            walk = self.opt("Walk through step by step", "Review the design section by section.",
                            do="Walk through the sections design.md has (architecture, API contracts, database changes, integration points, decision log), then ask this question again.")
            go = self.leave_design()
            opens = r.open_concerns()
            if passed:
                # A concern the design raises can need the plan changed (a missing case, a task): the plan is closed from
                # here on, so the way to change it is a step back to Plan. The open ones are named, since the person is
                # here for them; another call than accepting one as written is typed, and written into design.md.
                text = "Design: %s. Continue to Build?" % state_of
                cont = "Start Build."
                if opens:
                    text = "Design: %s, with %d open area(s) of concern: %s%s. Continue to Build?" % (
                        state_of, len(opens), "; ".join("%d. %s" % (i + 1, t) for i, t in enumerate(opens[:3])),
                        "; and %d more" % (len(opens) - 3) if len(opens) > 3 else "")
                    cont = "Accept the open concerns as written (design.md records it) and start Build."
                if r.tasks_changed():
                    # 9.8.0: Design changed the approved tasks; Continue approves them with the design (the CLI records it),
                    # so Build does not refuse to start on a plan that changed after the plan gate.
                    what = r.tasks_change_summary()
                    text = text[:-len(" Continue to Build?")].rstrip(".") + ". Design changed the plan's tasks (tasks.md%s); Continue approves them with the design. Continue to Build?" % (
                        ": " + "; ".join(what[:4]) + ("; and %d more" % (len(what) - 4) if len(what) > 4 else "") if what else "")
                    cont = cont[:-1] + "; the changed tasks are approved with the design."
                arm = self.opt("Autonomous Build: run Build unattended", ("Accept the open concerns as written; " if opens else "") +
                               "Build runs every group and task by itself and parks if it stops. Review and Check then ask you as usual.",
                               move="arm", calls=[self.c("state set run_mode autonomous")] + go)
                return self.with_more(GATE_HEADER, text, stage,
                                      [self.opt("Continue to Build (Recommended)", cont, move="advance", calls=go), arm, walk],
                                      [self.skill("grill-me", "Grill Me", "Stress test the design.")] + back_opt() +
                                      [self.skill("teach-me", "Teach Me", "Walk through the design."), self.save()], "Design: more options.")
            return self.question(GATE_HEADER, "Design: the check failed (%s). Fix the design, or skip the check?" % why, stage=stage,
                                 options=back_opt() + [override_opt(go), self.save()])

        if stage in ("build", "fix"):
            go = [self.c("state advance %s_complete %s" % (stage, nxt))]
            if passed:
                change = self.opt("Change something", ("Say what to change; Build's fix pass makes it, and Build is checked again." if stage == "build"
                                                       else "Say what to change; the Fix agent makes it, and Fix is checked again."), move="redo",
                                  calls=[self.c("state redo %s --reason '{reason}'" % stage)], reason=["Handle a case it missed", "Simplify the change"])
                opts = [self.opt("Continue to %s (Recommended)" % LABEL[nxt], "Start %s." % LABEL[nxt], move="advance", calls=go), change,
                        self.skill("teach-me", "Teach Me", "Walk through the changes.")]
                return self.question(GATE_HEADER, "%s: %s. Continue to %s?" % (label, state_of, LABEL[nxt]), stage=stage,
                                     options=opts + back_opt() + [self.save()])
            # 9.8.4: the same failure after a Run again is not run again by the recommendation: the run converges on the
            # person (an e2e run that followed it relaunched Build's fix pass forty times on one failure)
            redo = r.state.get("redo") if isinstance(r.state.get("redo"), dict) else {}
            same = redo.get("stage") == stage and str(redo.get("reason") or "") == why[:300]
            again = self.opt("Run %s again" % label + ("" if same else " (Recommended)"), "Mend what the failed rows name, then check %s again." % label,
                             move="redo", calls=[self.c('state redo %s --reason %s' % (stage, shlex.quote(why[:300])))])
            if same:
                save = self.save()
                save["label"] += " (Recommended)"
                return self.question(GATE_HEADER, "%s: the check failed (%s). It failed the same way after it ran again. Save the run for later?" % (label, why), stage=stage,
                                     options=[save, again] + back_opt() + [override_opt(go)])
            return self.question(GATE_HEADER, "%s: the check failed (%s). Run %s again?" % (label, why, label), stage=stage,
                                 options=[again] + back_opt() + [override_opt(go), self.save()])

        if stage == "review":
            go = [self.c("state advance review_complete check")]
            arch = self.opt("Architecture Depth Review", "Check the changed modules' depth, then come back here.",
                            do="Run the module depth analysis of %s/reference/architecture-depth.md on the changed files, add its [ARCH-DEPTH] findings to the summary, then ask this question again." % self.plugin)
            opens = r.open_findings()
            if passed:
                # The open findings below the blocking severity (the gate counts only those at or above it).
                opens = [f for f in r.findings() if f["state"] == "open"]
                # Findings below the blocking severity are still open: Build can fix them (a loop back), or the person
                # keeps one. A typed change is no fix here, since Review writes no code.
                grill = self.skill("grill-me", "Grill Me", "Stress test the change.")
                keep = [self.opt("Accept a finding", "Keep a finding as it is, with your reason.", do="Ask the accept question.")] if opens else []
                first = [self.opt("Continue to Check (Recommended)", "Start Check.", move="advance", calls=go)] + (back_opt() if opens else []) + [arch]
                rest = [self.skill("teach-me", "Teach Me", "Walk through the change."), self.save()]
                q = self.with_more(GATE_HEADER, "Review: %s. Continue to Check?" % state_of, stage,
                                   first + ([] if opens else [grill]), keep + ([grill] if opens else []) + rest, "Review: more options.")
                if keep:
                    q["accept"] = self.accept_question(opens)
                return q
            accept = None
            # A review that recorded no completion row did not finish (its agent failed or stopped): run it again first.
            unfinished = bool(rows) and all(x.get("name") == "review completed" for x in rows)
            first = back_opt(rec=not unfinished)
            if unfinished:
                first.insert(0, self.opt("Run Review again (Recommended)", "The review did not finish; it runs again.", move="redo",
                                         calls=[self.c("state redo review --reason 'the review did not finish'")]))
            if opens:
                accept = self.accept_question(opens)
                first.append(self.opt("Accept a finding", "Keep a finding as it is, with your reason.", do="Ask the accept question."))
            first.append(override_opt(go))
            text = "Review: the check failed (%s). Loop back to %s?" % (why, LABEL.get(back or "build", "Build"))
            q = self.with_more(GATE_HEADER, text, stage, first[:3], first[3:] + [arch, self.save()], "Review: more options.")
            if accept:
                q["accept"] = accept
            return q

        if stage == "pipeline":
            return self.pipeline_question(passed, why)

        if stage == "check":
            go = [self.c("state advance check_complete commit")]
            if passed:
                # What Check passed with a warning (a lint run, a test gap) is the person's to send back to Build.
                opts = [self.opt("Commit (Recommended)", "Commit the change with its spec files.", move="advance", calls=go)] + back_opt() + self.pr_options(go)
                if r.spec and os.path.isfile(os.path.join(r.spec, "config-suggestions.json")):
                    opts.append(self.opt("Review config suggestions", "Accept, reject or defer each suggestion, then come back here.",
                                         do="Show each suggestion in config-suggestions.json: Accept (write it into CLAUDE.md or AGENTS.md), Reject or Defer. Then ask this question again."))
                return self.with_more(GATE_HEADER, "Check: %s. Commit?" % state_of, stage, opts[:3] if len(opts) >= 4 else opts, opts[3:] + [self.save()] if len(opts) >= 4 else [self.save()], "Check: more options.")
            # A measurement nobody took (no coverage run, no test run recorded: a tool is missing) is not a fault of the code:
            # Check runs again once the tool is there, and going back to Build would redo work for nothing.
            # 9.8.0: a criterion validated by hand is confirmed by the person here (the agent used to claim it).
            details = " ".join(str(x.get("detail", "")) for x in r.failed_rows("check"))
            manual = [c for c in self.criteria("manual") if re.search(r"\b%s has no supported passing evidence row" % re.escape(c["id"]), details)]
            if manual:
                calls = [self.c("evidence add --stage check --criterion %s --claim %s --cmd %s --exit 0" % (
                    c["id"], shlex.quote("confirmed by the person at the Check question: " + c["vdetails"][:150]),
                    shlex.quote("the person, at the Check question"))) for c in manual] + [self.c("gate check")]
                text = "Check: %s %s your confirmation: %s. Confirm?" % (
                    ", ".join(c["id"] for c in manual), "needs" if len(manual) == 1 else "need",
                    "; ".join("%s: %s" % (c["id"], c["vdetails"][:150]) for c in manual))
                return self.question(GATE_HEADER, text, stage=stage, options=[
                    self.opt("Confirmed (Recommended)", "I checked it by hand; record my confirmation and check again.", move="confirm", calls=calls)]
                    + back_opt() + [self.save()])
            gap = self.measurement_gap(r.failed_rows("check"))
            # 9.8.4: the same missing measurement after a Run again (the tool is still not there) is not run again by the
            # recommendation: a benchmark run without coverage.py ran Check again 52 times
            redo = r.state.get("redo") if isinstance(r.state.get("redo"), dict) else {}
            same = gap and redo.get("stage") == "check" and str(redo.get("reason") or "") == ("the measurement was missing: " + why)[:300]
            again = [self.opt("Run Check again" + ("" if same else " (Recommended)"), "Install what the failed row names, then Check measures again; Build is not redone.",
                              move="redo", calls=[self.c("state redo check --reason %s" % shlex.quote(("the measurement was missing: " + why)[:300]))])] if gap else []
            if same:
                save = self.save()
                save["label"] += " (Recommended)"
                return self.question(GATE_HEADER, "Check: the check failed (%s). It failed the same way after it ran again: install what it names, or save the run for later?" % why,
                                     stage=stage, options=[save] + again + back_opt(rec=False) + [override_opt(go)])
            acc = self.acceptance_options(r.failed_rows("check"))
            if acc:
                first = acc[0]
                rec = first["label"].endswith("(Recommended)")
                opts = [first] + back_opt(rec=False) if rec else back_opt(rec=True) + [first]
                lead = next(o["label"] for o in opts if o["label"].endswith("(Recommended)")) if any(o["label"].endswith("(Recommended)") for o in opts) else first["label"]
                t = self.acc_triage()
                said = (" The triage says the %s looks wrong: %s." % (t["verdict"], t.get("reason", ""))) if t.get("verdict") in ("code", "test") else ""
                return self.question(GATE_HEADER, "Check: the check failed (%s).%s %s?" % (why, said, lead.replace(" (Recommended)", "")), stage=stage,
                                     options=opts + [override_opt(go), self.save()])
            return self.question(GATE_HEADER, "Check: the check failed (%s). %s?" % (why, "Run Check again" if gap else "Loop back to %s" % LABEL[back or "build"]), stage=stage,
                                 options=again + back_opt(rec=not gap) + [override_opt(go), self.save()])

        return None

    @staticmethod
    def measurement_gap(rows):
        """True when every failed row of Check is a measurement nobody took (no passing test run recorded, no coverage value):
        a missing tool, not a defect in the code."""
        if not rows:
            return False
        return all(re.search(r"no passing test-run evidence recorded|recorded coverage 'none'", str(x.get("detail", ""))) for x in rows)

    def pr_options(self, go):
        """At a passed Check of an unarmed /temper:temper run: Commit and open PR (and, with two or more Build groups, stacked PRs).
        Temper opens them itself (reference/pr.md); every one is a draft."""
        r = self.r
        if r.armed() or r.command != "temper":
            return []
        kinds = [("one", "PR", "a draft pull request")]
        if len((r.plan or {}).get("groups", [])) >= 2:
            kinds.append(("stacked", "stacked PRs", "a stack of draft pull requests, one per Build group"))
        return [self.opt("Commit and open %s" % label, "Commit, then Temper opens %s itself (reference/pr.md); every one is a draft." % what,
                         move="advance", calls=[self.c("state set pr %s" % kind)] + go) for kind, label, what in kinds]

    # The stages a small change window may open at are adhoc_ops.py's, the one list (the CLI refuses any other).
    ADHOC_STAGES = tuple(adhoc_ops.ADHOC_STAGES)   # the stages a small change window may open at: adhoc_ops.py's own list
    # The gate question offers Make a small change at each of them but Pipeline, whose question opens the window itself:
    # its "Apply the fix and push" opens one for the CI fix (pipeline_question).
    ADHOC_OPTION_STAGES = tuple(s for s in ADHOC_STAGES if s != "pipeline")

    def adhoc_option(self, stage):
        # Claude makes it, here in the conversation (a person read "change the work yourself" as their own edit).
        return self.opt("Make a small change", "Claude makes one small change here, with no loop back to %s: the one you describe, " % (
                        "Fix" if self.r.command == "fix" else "Build") +
                        "or the one the review asked for. Only what it touches is checked again.",
                        move="adhoc", calls=[self.c("adhoc open --stage %s --reason '{reason}'" % stage)],
                        do="Make the small change: for a fix the person describes, ask them in one line what to change first; for the "
                           "review's, take what the review asked for. Then run %s, then run %s again." % (self.c("adhoc close"), self.c("next --json")),
                        reason=["A small fix I will describe", "A change the review asked for"])

    def add_adhoc(self, out, stage):
        """Add Make a small change to the gate question of Build, Review, Check or Commit, before Save for later. Four options
        at most: when the question is full it goes under More options. Not offered while a window is open, nor at a fix
        run's Fix stage (its change is the fix itself)."""
        r = self.r
        if stage not in self.ADHOC_OPTION_STAGES or r.state.get("adhoc") or (r.command == "fix" and r.stage == "fix"):
            return out
        q = out.get("ask") if "ask" in out else out
        if not isinstance(q, dict) or "options" not in q or any(o["label"] == "Make a small change" for o in q["options"]):
            return out
        if stage == "review" and q["options"] and q["options"][0]["label"].startswith("Continue") and r.verdict("review") == "PASS" and \
                any(f["state"] == "open" for f in r.findings()):
            q["options"] = [o for o in q["options"] if o["label"] != "Teach Me"]   # Teach Me gives way to the change
            if q.get("more"):
                q["more"]["options"] = [o for o in q["more"]["options"] if o["label"] != "Teach Me"]
                q["more"]["question"]["options"] = [{"label": o["label"], "description": o["description"]} for o in q["more"]["options"]]
        opt = self.adhoc_option(stage)

        def put(options):
            keep = [o for o in options if o["label"] == "Save for later"]
            rest = [o for o in options if o["label"] != "Save for later"]
            return rest + [opt] + keep

        if len(q["options"]) < 4:
            q["options"] = put(q["options"])
        elif q.get("more") and len(q["more"]["options"]) < 4:
            q["more"]["options"] = put(q["more"]["options"])
            q["more"]["question"]["options"] = [{"label": o["label"], "description": o["description"]} for o in q["more"]["options"]]
        else:
            first, rest = q["options"][:3], q["options"][3:]
            more = self.question(q["question"]["header"], q["question"]["question"].split("?")[0] + "? More options.", put(rest), stage)
            q["options"] = first + [self.opt("More options", ", ".join(o["label"] for o in more["options"]), do="Ask the more question.")]
            q["more"] = more
        for o in q["options"]:   # the description of More options lists what is behind it, as it is now
            if o["label"] == "More options" and q.get("more"):
                o["description"] = ", ".join(x["label"] for x in q["more"]["options"])
        q["question"]["options"] = [{"label": o["label"], "description": o["description"]} for o in q["options"]]
        return out

    def small_change_work(self, done):
        """A small change is closed: run the steps it touches, in order (review of the changed files, check, the commit gate;
        or only the stage's own gate), before the stage's question is asked again."""
        r = self.r
        step = (done.get("steps") or [""])[0]
        files = ", ".join(done.get("files") or [])
        if step == "review":
            a = self.agent("review", ["Ad-hoc change: review only %s." % files])
            a["after"].append(self.c("gate review"))
            a["gate"] = a["after"][-1]
            return {"action": "work", "stage": r.stage, "calls": [], "agents": [a],
                    "say": "%s: the Review agent checks your small change%s. %s" % (LABEL.get(r.stage, r.stage), on_model([a]), goes_on(False))}
        if step == "check":
            a = self.agent("check", ["Ad-hoc change: check the tree as it is now; the change touched %s." % files])
            a["after"].append(self.c("gate check"))
            a["gate"] = a["after"][-1]
            return {"action": "work", "stage": r.stage, "calls": [], "agents": [a],
                    "say": "%s: the Check agent checks the tree after your small change%s. %s" % (LABEL.get(r.stage, r.stage), on_model([a]), goes_on(False))}
        gate = {"commit": "commit"}.get(step) or (r.gate_of(done.get("stage") or r.stage) or r.stage)
        return {"action": "work", "stage": r.stage, "calls": [self.c("gate %s" % gate)], "agents": [],
                "say": "%s is checked again after your small change." % LABEL.get(done.get("stage") or r.stage, r.stage)}

    def side_review_failed(self, done):
        """Review of a change made at Check or Commit failed: the run has left Review, so it never offers to advance from it."""
        r = self.r
        why = "; ".join("%s: %s" % (x.get("name"), x.get("detail")) for x in r.failed_rows("review")[:3])
        opts = []
        work = "fix" if r.command == "fix" else "build"
        if r.can_loop(r.stage, work):
            opts.append(self.opt("Loop back to %s (Recommended)" % LABEL[work], "Do %s again; the stages after it are redone too." % LABEL[work], move="back",
                                 calls=[self.c("state loop %s %s --reason '{reason}'" % (r.stage, work))], reason=["The review found a real problem"]))
        opts.append(self.opt("Override and continue", "Skip the Review of your change with your reason; the report shows it.", move="override",
                             calls=[self.c("override review --reason '{reason}'")], reason=["I accept the risk", "It is not a real issue"]))
        opts.append(self.save())
        return {"action": "ask", "stage": r.stage, "ask": self.question(GATE_HEADER, "%s: Review of your small change failed (%s). %s" % (
            LABEL.get(r.stage, r.stage), why, "Loop back to %s?" % LABEL[work] if len(opts) > 2 else "Override it?"), stage=r.stage, options=opts)}

    def round_limit(self):
        """The most CI fix rounds (loops.max-per-type, 2 by default): the Pipeline question and the Pipeline agent's launch line use the same."""
        try:
            return int(self.r.cfg("loops.max-per-type", "2"))
        except ValueError:
            return 2

    def pipeline_round(self):
        """The CI fix round the run is on (1 before any fix). The flow alone moves it, by one, in the fix steps; a value it
        cannot read as a round (not a whole number of at least 1) counts as past the limit, so it never opens the rounds
        again (the CLI validates what `state set` writes, too)."""
        v = self.r.state.get("pipeline_round")
        if v in (None, ""):
            return 1
        try:
            n = int(str(v).strip())
        except ValueError:
            return self.round_limit() + 1
        return n if n >= 1 else self.round_limit() + 1

    def pipeline_question(self, passed, why):
        r = self.r
        ctx = read_json(os.path.join(r.spec, "pipeline-context.json"), {}) if r.spec else {}
        status = ctx.get("status") if ctx else None
        rnd = self.pipeline_round()
        mx = self.round_limit()
        end = self.opt("End the run" + (" (Recommended)" if passed or rnd > mx else ""), "Finish here; the run state is cleared.", move="advance", calls=[self.c("state clear")])
        if passed:
            return self.question(GATE_HEADER, "Pipeline: every job passed. End the run?", stage="pipeline", options=[end, self.save()])
        if status not in ("green", "red"):
            return self.question(GATE_HEADER, "Pipeline: the check failed (%s). Run Pipeline again?" % (why or "the Pipeline result is missing or not final"), stage="pipeline", options=[
                self.opt("Run Pipeline again (Recommended)", "Read the pull request's checks again.", move="redo",
                         calls=[self.c("state redo pipeline --reason 'the Pipeline result is missing or not final'")]), self.save()])
        if rnd > mx:
            return self.question(GATE_HEADER, "Pipeline: the fix limit is reached (round %d of %d). End the run?" % (rnd, mx), stage="pipeline", options=[end, self.save()])
        fix = ["Apply the changes the fix list in %s/pipeline-context.json names: the step names the file, never the CI text." % r.spec,
               "git add -- {each changed file, by name}",
               "git commit -m 'fix(ci): apply the Pipeline fix (CI fix round %d)'" % rnd]
        fix.append("git push")
        steps = [self.c("adhoc open --stage pipeline --reason 'CI fix round %d'" % rnd)] + fix + [
            self.c("adhoc close"), self.c("state set pipeline_round %d" % (rnd + 1)),
            self.c("state redo pipeline --reason 'CI fix round %d pushed; CI runs again'" % rnd)]
        text = "Pipeline: the check failed (%s). Apply the fix and push?" % (why or "see pipeline-context.json")
        return self.question(GATE_HEADER, text, stage="pipeline", options=[
            self.opt("Apply the fix and push (Recommended)",
                     "The fix list in pipeline-context.json is applied, pushed, and the checks are read again.", move="advance", steps=steps),
            self.opt("End the run", "Finish here without the fix; the run state is cleared.", move="advance", calls=[self.c("state clear")]), self.save()])

    def fresh_offer(self):
        """plan.fresh-review: ask (the default): the person asks for the fresh review at the plan question."""
        return self.opt("Fresh review first", "A reviewer with no context reads the plan before you approve it (worth it for medium and complex work).",
                        move="redo", calls=[self.c("plan fresh request")])   # next launches the reviewer; its gate call follows it

    def fresh_question(self, fr, why, said, back_opt, override_opt, grill):
        """The plan question when the fresh review failed the gate: revise the plan with its findings, run a reviewer that
        did not finish again, or keep a finding (contested and escalated ones first: they need the person's call)."""
        r = self.r
        opens = sorted([f for f in fr["findings"] if f["severity"] in fresh_review.BLOCKING and f["state"] not in ("resolved", "accepted")],
                       key=lambda f: {"escalated": 0, "contested": 1}.get(f["state"], 2))
        first = []
        unfinished = fr["launched"] and not fr["stale"] and (fr["missing"] or not fr["paraphrase"] or fr["paraphrase_short"])
        if unfinished and not fr["capped"]:
            first.append(self.opt("Run the fresh review again (Recommended)", "A reviewer did not finish (%s); it runs again." % (
                ", ".join(fr["missing"] + fr["lazy"]) or "no usable paraphrase"), move="redo", calls=[self.c("plan fresh again")]))
        if opens and not fr["capped"]:
            first.append(self.opt("Revise the plan%s" % ("" if first else " (Recommended)"),
                                  "The Plan agent fixes or contests each finding; the fresh review runs again on the changed files.",
                                  move="redo", calls=[self.c("state redo plan --reason %s" % shlex.quote(
                                      ("fresh review: " + "; ".join(fresh_review.describe(f) for f in opens))[:300]))]))
        if opens:
            first.append(self.opt("Accept a finding", "Keep a finding as it is, with your reason.", do="Ask the accept question."))
        limit = " The fresh review ran %d of %d rounds (plan.fresh-review-rounds): accept, skip or step back." % (fr["rounds"], fr["cap"]) if fr["capped"] else ""
        text = "Plan: the check failed (%s).%s%s %s?" % (why, said, limit, "Revise the plan" if opens and not fr["capped"] else
                                                       "Run the fresh review again" if first and not opens else "Accept a finding, or skip the check" if opens else "Fix the plan, or skip the check")
        q = self.with_more(GATE_HEADER, text, "plan", first[:3], first[3:] + back_opt() + [override_opt(self.leave_plan()), grill, self.save()],
                           "Plan: more options.")
        if opens:
            q["accept"] = self.accept_question(opens, stage="plan")
        return q

    def accept_question(self, opens, stage="review"):
        """The `Accept a finding` question: one option per open finding (the first three), and Cancel."""
        label = LABEL.get(stage, stage)
        aopts = []
        # escalated and contested findings first: they wait for the person's call, with what only they know or the author's citation
        rank = lambda f: {"escalated": 0, "contested": 1}.get(f.get("answer") or f.get("state"), 2)
        for f in sorted(opens, key=rank)[:3]:
            reasons = ["It is not a real issue", "I accept the risk"]
            mark = f.get("answer") or (f.get("state") if f.get("state") in ("contested", "escalated") else None)
            if mark == "contested" and f.get("cite"):
                reasons.insert(0, "Contested with evidence: %s" % f["cite"])     # the author's citation, checked by the CLI
            if mark == "contested" and f.get("quote"):
                reasons.insert(1, "The quoted text answers it: %s" % f["quote"][:80])
            aopts.append(self.opt("Accept finding %d" % f["id"], ("[%s] " % mark if mark else "") + f["claim"][:150],
                                  move="accept", calls=[self.c("evidence accept --stage %s --id %d --reason '{reason}'" % (stage, f["id"])), self.c("gate %s" % stage)],
                                  reason=reasons))
        return self.question(GATE_HEADER, "%s: which finding do you accept?" % label, stage=stage,
                             options=aopts + [self.opt("Cancel", "Back to the %s question." % label, do="Ask the %s question again." % label)])

    def go_move(self, stage):
        return "approve" if stage in ("intent", "plan") else "advance"

    def leave_design(self):
        """Leave Design: the CLI records the open concerns as accepted, then design.md is committed (it was left for the
        last commit before)."""
        r = self.r
        return [self.c("state advance design_complete %s" % (r.next_of("design") or "build"))] + \
            self.spec_commit("docs(design): the design of %s" % r.slug, changes=bool(r.open_concerns()))

    def leave(self, stage):
        if stage == "intent":
            return self.leave_intent()
        if stage == "plan":
            return self.leave_plan()
        if stage == "design":
            return self.leave_design()
        nxt = self.r.next_of(stage)
        return [self.c("state advance %s_complete %s" % (stage, nxt))]

    def walked(self, stage):
        """A door started this run at a later stage: the stages before it are checked and asked, not run."""
        enter = self.r.state.get("enter") or ""
        seq = self.r.seq()
        # By the order of all stages, so the Design door of a run with no Design stage still walks what comes before.
        order = ["intent", "plan", "design", "build", "review", "check", "commit"]
        return enter in order and stage in seq and stage in order and order.index(stage) < order.index(enter)

    # -- the work of a stage -------------------------------------------------------------------
    def agent(self, stage, extra_lines=()):
        r = self.r
        models = r.ctx.get("models") or {}
        lines = ["Follow %s/agents/%s.md exactly." % (self.plugin, stage)]
        if stage in ("plan", "design"):
            # 9.8.0 (round 5): the CLI's map of the code the request reaches, made by the action's own call (temper brief).
            lines.append("Project brief: .temper/brief.md (the CLI's map of the code the request reaches; read it first).")
        if stage == "intent" and r.state.get("feature"):
            # The request as typed, with one period after it unless it already ends a sentence (round 5: a request that
            # ended with a period got two, a session tidied them to one, and its launch was refused as another prompt).
            feature = r.state.get("feature").rstrip()
            lines.append("Feature: %s%s" % (feature, "" if feature[-1:] in ".!?" else "."))
        lines.append("Spec path: %s." % r.spec)
        lines.extend(extra_lines)
        lines.extend("Person's note: %s" % x["claim"] for x in r.notes(stage, "input"))
        lines.append(self.plugin_line())
        return {"type": "temper:temper-%s" % stage, "model": models.get(stage, ""), "prompt": "\n".join(lines),
                "after": [self.c("usage add --stage %s --model %s --ms {ms}" % (stage, models.get(stage, "") or "unknown"))]}

    def feedback_lines(self):
        fb = self.r.latest_feedback()
        lines = []
        if fb:
            lines.append("Feedback re-entry: %s. Fix this, then continue." % fb)
        found = self.r.latest_findings()
        if found:
            # 9.8.0: each finding in a line short enough to copy exactly, the full text where the agent reads it. A finding
            # can hold a test's whole output (tracebacks with ~~~^^^ marks): the session launches the agent with this prompt
            # word for word (the mod refuses any other), and in round 5 a session miscounted those marks twice.
            def brief(x):
                x = " ".join(re.sub(r"[~^]{3,}", " ", x).split())
                return x if len(x) <= 200 else x[:197].rstrip() + "..."
            lines.append("What the stage before the loop left open (each in full in .temper/feedback-loops.json, the latest loop's "
                         "findings): %s." % "; ".join("%d. %s" % (i + 1, brief(x)) for i, x in enumerate(found)))
            if any(x.startswith("acceptance (written before Build)") for x in found):
                # 9.8.0: three benchmark runs looped after a fix pass edited a locked acceptance test.
                lines.append("The acceptance tests are locked: change the code, never a test in %s/acceptance/. If a test is wrong, "
                             "say which and why in your panel; the person decides at the Check question." % self.r.spec)
                t = check_run.acc_read(self.ACC_LOCK).get("triage") or {}
                if t.get("verdict") == "code" and t.get("reason"):
                    lines.append("The triage of the failing test: %s." % t["reason"])
        # The file of the stage the loop came back from: one an earlier run left (a Check context beside a loop from
        # Review) is not this loop's feedback.
        frm = (self.r.latest_loop() or {}).get("from_stage")
        for name in ("review-context.json", "check-context.json"):
            p = os.path.join(self.r.spec, name)
            if self.r.spec and os.path.isfile(p) and (frm not in ("review", "check") or name.startswith(frm)):
                lines.append("Feedback file: %s." % p)
        return lines

    def fresh_work(self, fr):
        """Launch the fresh reviewer(s) of the plan: no context but the spec folder (agents/plan-review.md). The first
        marks the launch (the files' digest and the time), so a row written before it never counts and a reviewer that stopped is
        reported as not run instead of launched again."""
        r = self.r
        model = r.cfg("models.plan-review", "")
        if not model:
            import cli_ctx
            model = cli_ctx.frontmatter_model(os.path.join(self.plugin, "agents", "plan-review.md")) or ""
        insts = sorted({n.split()[1] for n in fr["need"]})
        agents = []
        for i, inst in enumerate(insts):
            lines = ["Follow %s/agents/plan-review.md exactly." % self.plugin, "Spec path: %s." % r.spec, "Instance: %s." % inst,
                     "Lenses: %s." % ", ".join(n.split()[0] for n in fr["need"] if n.split()[1] == inst),
                     "Round: %d of %d." % (fr["rounds"] + 1, fr["cap"])]
            rc = fr.get("recheck")
            if rc:
                # 9.8.4: a later round re-checks the round before it: each earlier finding, and the changed task blocks only
                ch = rc.get("changed") or []
                lines += ["Re-check: this round checks only whether each earlier finding below is fixed, and reads only the changed task blocks; "
                          "it runs no other lens.",
                          "Earlier findings (%d): %s." % (len(rc.get("findings") or []), "; ".join(
                              "#%d [%s] %s" % (f["id"], f["severity"], f["claim"][:200]) for f in rc.get("findings") or []) or "none"),
                          "Changed task blocks: %s." % (", ".join("Task %d" % n for n in ch) if ch else "none")]
            lines += ["Earlier contest: %s; its evidence: %s (%s). Read that evidence before you raise it again." % (
                c["claim"][:160], c.get("cite"), (c.get("why") or "")[:160]) for c in fr["contests"]]
            lines.append(self.plugin_line())
            a = {"type": "temper:temper-plan-review", "model": model, "prompt": "\n".join(lines),
                 "after": [self.c("usage add --stage plan --model %s --ms {ms}" % (model or "unknown")), self.c("gate plan")]}
            a["gate"] = a["after"][-1]
            if i == 0:   # the CLI's launch mark: only rows recorded from now on count, and only on these files
                a["before"] = [self.c("plan fresh start")]
            agents.append(a)
        return {"action": "work", "stage": "plan", "calls": [], "agents": agents,
                "say": "Plan: %s with no context reads the plan%s. %s" % (
                    "a reviewer" if len(agents) == 1 else "%d reviewers" % len(agents), on_model(agents), goes_on(len(agents) > 1))}

    def stage_work(self, stage):
        r = self.r
        extra = []
        if r.command == "fix":
            if stage == "review":
                extra = ["Fix mode: there is no intent.md; read %s/rca.md instead, and verify the fix addresses its root cause, "
                         "the regression test proves the fix (not a trivial assert), and no same pattern occurrence it flagged is left unfixed." % r.spec]
            elif stage == "check":
                extra = ["Fix mode: there is no intent.md, so scenario tracing does not apply; %s/rca.md names the regression test "
                         "that must be in the passing run." % r.spec]
            elif stage == "fix":
                extra = self.feedback_lines()
        if stage == "pipeline":
            extra = ["Round: %s of %s." % (self.pipeline_round(), self.round_limit())]
        if stage == "plan":
            opens = [f for f in r.fresh()["findings"] if f["state"] not in ("resolved", "accepted")]
            if opens:
                extra = ["Fresh review findings to answer (reference/plan.md, Answering the fresh review): %s." % "; ".join(
                    "#%d [%s] %s" % (f["id"], f["severity"], f["claim"][:200]) for f in opens)]
        # A step back to this stage (from Design to Plan, from Review to Intent): the agent runs again for the person's
        # reason, and with what the stage it came from left open.
        back = r.loop_into(stage) if stage not in ("build", "fix") else None
        # 9.8.4: a step back to an earlier stage (Plan to Intent) comes through this stage again: its reason and what it left
        # open reach this stage's agent too, unless a later step back into this stage speaks for it.
        through = r.loop_through(stage) if stage not in ("build", "fix") else None
        if through and (not back or loop_at(through) > loop_at(back)):
            extra = extra + ["Earlier loop back from %s to %s: %s. Take it into account, keeping what still holds." % (
                LABEL.get(through.get("from_stage"), through.get("from_stage")), LABEL.get(through.get("to_stage"), through.get("to_stage")),
                through.get("reason") or "no reason given")]
            if through.get("findings"):
                extra.append("What %s left open: %s." % (LABEL.get(through.get("from_stage"), through.get("from_stage")),
                                                          "; ".join("%d. %s" % (i + 1, x) for i, x in enumerate(through["findings"]))))
            back = None
        if back:
            extra = extra + ["Loop back from %s: %s. Do this stage again for it, keeping what still holds." % (
                LABEL.get(back.get("from_stage"), back.get("from_stage")), back.get("reason") or "no reason given")]
            if back.get("findings"):
                extra.append("What %s left open: %s." % (LABEL.get(back.get("from_stage"), back.get("from_stage")),
                                                          "; ".join("%d. %s" % (i + 1, x) for i, x in enumerate(back["findings"]))))
        # 9.8.0: Check is run by the CLI (scripts/check_run.py) whenever it can find the project's test command: the suite
        # with coverage, each scenario's Test: command, the mutation score and a fix's regression proof, all recorded as
        # real runs. No agent and no model; the Check agent stays for a stack the CLI cannot read (and for a step back
        # that brings a person's note to it).
        if stage == "check" and not back and self.cli_check():
            gate = self.c("gate %s" % (r.gate_of(stage) or stage))
            rec = self.criteria("code", "metric")
            if not rec:
                return {"action": "work", "stage": stage, "calls": [self.c("check run"), gate], "agents": [], "gate": gate,
                        "say": "Check: the CLI runs the suite, coverage, the scenario tests and the mutation score (no agent)."}
            # A criterion validated by code or by a metric needs its own evidence: the Check agent records only those, after
            # the CLI's run (a manual one is the person's to confirm at the Check question).
            a = self.agent("check", extra + ["The CLI has run the suite, coverage, the scenario tests and the mutation score (temper check run). "
                                            "Record evidence only for these criteria, each with --criterion: %s." % "; ".join(
                                                "%s (%s: %s)" % (c["id"], c["vtype"], c["vdetails"][:120]) for c in rec)])
            a["after"].append(gate)
            a["gate"] = gate
            return {"action": "work", "stage": stage, "calls": [self.c("check run")], "agents": [a],
                    "say": "Check: the CLI runs the suite, coverage, the scenario tests and the mutation score; the Check agent records %d criteria%s." % (len(rec), on_model([a]))}
        a = self.agent(stage, extra)
        if stage == "review" and r.command == "temper" and self.cli_check():
            # 9.8.0: the CLI runs Check's suite, coverage and mutation score while Review reads the change (Review writes
            # no code); Check adopts that run when the tree is unchanged.
            a["before"] = (a.get("before") or []) + [self.c("check ahead")]
        if stage in ("plan", "design"):
            # 9.8.0 (round 5): the CLI draws the stage's panel from the files the agent wrote; the agent draws none.
            a["after"].append(self.c("panel %s" % stage))
        a["after"].append(self.c("gate %s" % (r.gate_of(stage) or stage)))
        a["gate"] = a["after"][-1]
        return {"action": "work", "stage": stage, "calls": [self.c("brief")] if stage in ("plan", "design") else [], "agents": [a],
                "say": "%s: the %s agent is working%s. %s" % (LABEL.get(stage, stage), LABEL.get(stage, stage), on_model([a]), goes_on(False))}

    ACC_LOCK = os.path.join(TEMPER, "evidence", "acceptance-lock.json")

    def acceptance(self):
        """This run's acceptance lock ({} when none): the tests written from the intent before Build."""
        d = check_run.acc_read(self.ACC_LOCK)
        return d if d.get("spec") == self.r.spec else {}

    def acceptance_work(self):
        """9.8.0: before the first Build task, an agent that writes no code writes the acceptance tests from the approved
        intent (agents/acceptance.md) and locks them. Only for a /temper:temper run with an intent, before any group starts,
        and at most check_run.ACC_MAX_LAUNCHES launches: a writer that cannot lock does not hold Build up, and the CLI
        records the skip (Check shows it as a skipped acceptance row, the report too) instead of going on in silence."""
        r = self.r
        if r.command != "temper" or not r.spec or not os.path.isfile(os.path.join(r.spec, "intent.md")):
            return None
        if r.state.get("built_before") or (r.groups.get("groups") or {}):
            return None
        d = self.acceptance()
        if d.get("cmd") or d.get("skipped"):
            return None
        if int(d.get("launches") or 0) >= check_run.ACC_MAX_LAUNCHES:
            why = "the acceptance writer locked no tests in %d launches" % int(d.get("launches") or 0)
            return {"action": "work", "stage": "build", "calls": [self.c("acceptance skip --reason %s" % shlex.quote(why))],
                    "agents": [], "say": "Build: %s; the skip is recorded and Build goes on without them." % why}
        model = r.cfg("models.acceptance", "")
        if not model:
            import cli_ctx
            model = cli_ctx.frontmatter_model(os.path.join(self.plugin, "agents", "acceptance.md")) or ""
        a = {"type": "temper:temper-acceptance", "model": model,
             "prompt": "\n".join(["Follow %s/agents/acceptance.md exactly." % self.plugin, "Spec path: %s." % r.spec, self.plugin_line()]),
             "before": [self.c("acceptance start")],
             "after": [self.c("usage add --stage build --model %s --ms {ms}" % (model or "unknown"))]}
        return {"action": "work", "stage": "build", "calls": [], "agents": [a],
                "say": "Build: first, an agent that writes no code writes the acceptance tests from the intent%s. %s" % (on_model([a]), goes_on(False))}

    def acceptance_line(self):
        d = self.acceptance()
        if not d.get("cmd"):
            return ""
        return ("\nAcceptance tests: %s/acceptance/ holds the tests written from the intent before Build. Read the ones for your "
                "task's criteria: your code must make them pass at integration. Never edit them (Check fails a change)." % self.r.spec)

    ACC_REASONS = ["The test asks for what the intent does not say", "The test contradicts how the code base works"]

    def acc_failure(self):
        """(detail, digest) when Check failed on the locked acceptance tests and on nothing else, they were not changed
        after the lock and are not reopened: a test or the code is wrong. Else None."""
        d = self.acceptance()
        rows = self.r.failed_rows("check")
        acc = [x for x in rows if str(x.get("name", "")).startswith("acceptance tests written before Build")]
        if not d.get("cmd") or d.get("reopened") or not acc or len(acc) != len(rows):
            return None
        detail = str(acc[0].get("detail", ""))
        if detail.startswith(("changed after they were locked", "reopened")):
            return None
        import hashlib
        return detail, hashlib.sha256(detail.encode("utf-8")).hexdigest()[:16]

    def acc_triage(self):
        """The triage of the current acceptance failure ({} when none, or when it read another failure)."""
        f = self.acc_failure()
        t = self.acceptance().get("triage")
        return t if f and isinstance(t, dict) and t.get("failure") == f[1] else {}

    def acceptance_triage_work(self):
        """9.8.0: before the person is asked whether to step back to Build, an agent reads the failing test, the intent
        and the code, and says which looks wrong (`temper acceptance triage`). It only sets the recommended option; a
        step back to Build when the test is wrong is a Build and a Review round for nothing (the benchmark's reruns)."""
        r = self.r
        f = self.acc_failure()
        if not f or r.armed() or self.acc_triage():
            return None
        model = r.cfg("models.acceptance", "")
        if not model:
            import cli_ctx
            model = cli_ctx.frontmatter_model(os.path.join(self.plugin, "agents", "acceptance.md")) or ""
        a = {"type": "temper:temper-acceptance", "model": model,
             "prompt": "\n".join(["Follow %s/agents/acceptance.md exactly." % self.plugin, "Spec path: %s." % r.spec,
                                   "Triage: a locked acceptance test fails at Check. Decide whether the code or the test is wrong; change nothing.",
                                   "The failure: %s" % " ".join(f[0].split())[-900:], self.plugin_line()]),
             "after": [self.c("usage add --stage check --model %s --ms {ms}" % (model or "unknown")),
                       self.c("acceptance triaged --reason %s" % f[1])]}
        return {"action": "work", "stage": "check", "calls": [], "agents": [a],
                "say": "Check: a locked acceptance test fails; an agent reads it, the intent and the code to say which looks wrong%s. %s" % (
                    on_model([a]), goes_on(False))}

    def acceptance_options(self, rows):
        """9.8.0: the Check options when the locked acceptance tests failed and nothing else did. A builder changed them:
        put them back as locked (no decision: the person's lock holds). They fail as locked: Build mends the code (the
        step back carries the failing test's output), or the person says the test is wrong and the writer corrects it.
        After a step back to Build left the same failure, the correction is the recommended way. [] when this does not apply."""
        r = self.r
        d = self.acceptance()
        acc = [x for x in rows if str(x.get("name", "")).startswith("acceptance tests written before Build")]
        if not d.get("cmd") or not acc or len(acc) != len(rows):
            return []
        detail = str(acc[0].get("detail", ""))
        redo = self.c("state redo check --reason %s")
        if detail.startswith("changed after they were locked"):
            return [self.opt("Restore the locked tests (Recommended)", "A builder changed the locked acceptance tests: put them back as they were locked, then check again.",
                             move="redo", calls=[self.c("acceptance restore"), redo % shlex.quote("the locked acceptance tests were restored")])]
        if d.get("reopened"):
            return []
        t = self.acc_triage()
        if t.get("verdict") in ("code", "test"):
            rec = t["verdict"] == "test" or not r.can_loop("check", "build")
        else:
            rec = r.loop_count("check", "build") >= 1 or not r.can_loop("check", "build")
        return [self.opt("Correct the acceptance test" + (" (Recommended)" if rec else ""),
                         "The test is wrong, not the code: the writer corrects it against the intent and locks it again; the report shows your reason.",
                         move="redo", calls=[self.c("acceptance reopen --reason '{reason}'")], reason=self.ACC_REASONS)]

    def acceptance_fix_work(self):
        """The person reopened the locked acceptance tests at the Check question: the writer corrects the test the failure
        names, against the intent, and locks it again; Check runs again. At most check_run.ACC_MAX_CORRECTIONS launches
        for one reopen (its `before` call counts them): then the Check question is the person's again."""
        r = self.r
        d = self.acceptance()
        if not isinstance(d.get("reopened"), dict) or r.stage != "check":
            return None
        if int(d["reopened"].get("launches") or 0) >= check_run.ACC_MAX_CORRECTIONS:
            return None
        model = r.cfg("models.acceptance", "")
        if not model:
            import cli_ctx
            model = cli_ctx.frontmatter_model(os.path.join(self.plugin, "agents", "acceptance.md")) or ""
        rows = [x for x in r.failed_rows("check") if str(x.get("name", "")).startswith("acceptance tests written before Build")]
        fail = " ".join(str(rows[0].get("detail", "")).split())[-700:] if rows else ""
        a = {"type": "temper:temper-acceptance", "model": model,
             "prompt": "\n".join(["Follow %s/agents/acceptance.md exactly." % self.plugin, "Spec path: %s." % r.spec,
                                   "Correction: the person says a locked test is wrong (%s)." % d["reopened"].get("reason", ""),
                                   "The failure: %s" % (fail or "see the acceptance row of the Check ledger"),
                                   "Lock command: %s" % d.get("cmd", ""), self.plugin_line()]),
             "before": [self.c("acceptance start")],
             "after": [self.c("usage add --stage check --model %s --ms {ms}" % (model or "unknown")),
                       self.c("state redo check --reason 'the person corrected a locked acceptance test'")]}
        return {"action": "work", "stage": "check", "calls": [], "agents": [a],
                "say": "Check: the acceptance writer corrects the test you said is wrong, then Check runs again%s. %s" % (on_model([a]), goes_on(False))}

    def criteria(self, *types):
        """The required, open criteria of intent.md whose Validate type is one of types."""
        r = self.r
        if not r.spec or not os.path.isfile(os.path.join(r.spec, "intent.md")):
            return []
        import acceptance
        lines = open(os.path.join(r.spec, "intent.md"), encoding="utf-8").read().splitlines()
        return [c for c in acceptance.parse_criteria(acceptance.section_lines(lines, "Success Criteria"))
                if c.get("id") and not c.get("placeholder") and c.get("has_validate") and c.get("vtype") in types
                and not (c.get("deferred") and c.get("optional"))]

    def cli_check(self):
        """True when the CLI can run Check itself: a configured test command, or one it detects for the stack."""
        try:
            return bool(check_run.detect(os.getcwd(), self.r.cfg("check.commands.test", ""), self.r.cfg("check.commands.coverage", "")))
        except Exception:
            return False

    @staticmethod
    def chain_of(plan, rt, first, ready):
        """The tasks one agent builds in order, starting at a ready task: each next task of the same group that waits only
        on this chain (its dependencies passed or in the chain, and it depends on the chain or shares a file with it), and
        clashes with no other ready or running task. Independent tasks are never pulled in, so they stay parallel."""
        tasks = sorted([t for t in plan.get("tasks", []) if t.get("group") == first.get("group")], key=lambda t: t["n"])
        files = {t["n"]: {f.strip().lstrip("./") for f in t.get("files", [])} for t in plan.get("tasks", [])}
        deps = {t["n"]: set(t.get("depends", [])) for t in plan.get("tasks", [])}
        status = lambda n: (rt.get(str(n)) or {}).get("status", "pending")
        # Only a pending task joins a chain: a failed one (also STARTABLE in tasks_md) is retried alone, on the model its
        # attempt number gives, never on the chain's.
        others = {x["task"] for x in ready if x["task"] != first["task"]} | {int(n) for n, v in rt.items() if isinstance(v, dict) and v.get("status") == "running"}
        chain = [first["task"]]
        grew = True
        while grew:
            grew = False
            mine = set().union(*(files.get(n, set()) for n in chain))
            for t in tasks:
                n = t["n"]
                if n in chain or n in others or status(n) not in ("pending",):
                    continue
                if not all(d in chain or status(d) == "passed" for d in deps.get(n, set())):
                    continue
                if not (deps.get(n, set()) & set(chain) or files.get(n, set()) & mine):
                    continue
                if any(files.get(n, set()) & files.get(o, set()) for o in others):
                    continue
                chain.append(n)
                grew = True
                break
        return chain

    def review_notes(self):
        """9.8.4: the fresh review's open medium and low findings, as notes for the task each names ({task: [claim]}). They
        do not block the plan gate; the builder of the task reads them."""
        out = {}
        try:
            found = self.r.fresh().get("findings") or []
        except Exception:
            return out
        for f in found:
            if f.get("severity") in fresh_review.BLOCKING or f.get("state") in ("resolved", "accepted"):
                continue
            for n in {int(x) for x in re.findall(r"\bTask\s+(\d+)\b", f.get("claim") or "")}:
                out.setdefault(n, []).append(" ".join(str(f["claim"]).split())[:240])
        return out

    def task_model(self):
        """The model of a Build task: the one `temper next` resolved (cli_ctx.resolve: the config, else sonnet for a complex
        or risk H plan, else the brief's), and the same rule when it resolved none (9.8.4: it was haiku for any plan)."""
        import cli_ctx
        return self.r.ctx.get("task_model") or (cli_ctx.RISK_TASK_MODEL if (
            str(self.r.state.get("complexity") or "").lower() == "complex" or str(self.r.state.get("risk") or "").upper() == "H") else "haiku")

    def ran_on(self, task):
        """The model of the running attempt: the one task start recorded, else (a run started before it did) the one the
        attempt number gives, the task model for the first two attempts and the escalation model after."""
        if task.get("model"):
            return task["model"]
        task_model = self.task_model()
        esc = self.r.ctx.get("escalation_model") or "sonnet"
        return task_model if int(task.get("attempt") or 1) <= 2 else esc

    def no_groups(self):
        """tasks.md has tasks and no group: Build stops before any group starts, with no agent."""
        r = self.r
        text = "Build stopped: tasks.md has tasks but no groups, so Build cannot run them in isolated groups."
        opts = []
        if r.can_loop("build", "plan"):
            opts.append(self.opt("Run Plan again (Recommended)", "Plan writes the tasks in groups.", move="back",
                                 calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The tasks have no groups"]))
            text += " Run Plan again to write the tasks in groups."
        else:
            text += " Plan has run again already: write the groups by hand in tasks.md, or save the run."
        opts.append(self.save())
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=opts)}

    def build_work(self):
        """Grouped Build, computed: start groups, hand out ready tasks, gate tasks and groups, integrate."""
        r = self.r
        plan = r.plan or {"groups": [], "tasks": []}
        if plan.get("tasks") and not plan.get("groups"):
            return self.no_groups()
        acc = self.acceptance_work()
        if acc:
            return acc
        rg = r.groups.get("groups") or {}
        rt = r.groups.get("tasks") or {}
        integ = (r.groups.get("integration") or {}).get("verdict")
        gid = [g["id"] for g in plan.get("groups", [])]

        # A group passed is its gate's PASS, the CLI's verdict; its `status` is the CLI's record of the same (passed iff
        # the gate is PASS) and is read here only for `parked`, which no gate sets. So a status left behind by an older
        # write never decides what comes next (tasks_md.schedule reads the gate the same way).
        def gpass(g):
            return ((rg.get(g) or {}).get("gate") or {}).get("verdict") == "PASS"

        # the fix pass: the groups are integrated, so Build mends what a step back or "Run Build again" names. A door's
        # run whose code an earlier run built (built_before, from the walked Build's check) mends it the same way.
        before = r.state.get("built_before") and not rg
        if (integ and gid and all(gpass(g) for g in gid)) or before:
            a = self.agent("build", self.feedback_lines())
            # 9.8.4: the CLI runs the scenario tests on the fixed tree (integrate does when the groups are merged already),
            # so no record pass of a model is needed after a step back that cleared Build's rows
            if integ and not before:
                a["after"].append(self.c("integrate"))
            a["after"].append(self.c("gate build"))
            a["gate"] = a["after"][-1]
            return {"action": "work", "stage": "build", "calls": [], "agents": [a], "say": "Build: the fix pass is working%s. %s" % (on_model([a]), goes_on(False))}

        run = []
        if not r.state.get("base_sha") and r.ctx.get("head"):
            run.append(self.c("state set base_sha %s" % r.ctx.get("head")))
        # build.grouped.max-groups groups work at once (default 2; anything but a whole number of at least 1 means 2)
        mg = r.cfg("build.grouped.max-groups", "2")
        room = (int(mg) if re.fullmatch(r"[1-9][0-9]*", mg) else 2) - sum(
            1 for g in plan.get("groups", []) if (rg.get(g["id"]) or {}).get("worktree") and not (rg.get(g["id"]) or {}).get("confirmed"))
        for g in plan.get("groups", []):
            started = bool((rg.get(g["id"]) or {}).get("worktree"))
            # A group that builds on another starts after the person's Continue of it, not on its check alone: a Change
            # there reruns work this group would build on.
            if not started and room > 0 and all(gpass(d) and (rg.get(d) or {}).get("confirmed") for d in g.get("depends", [])):
                run.append(self.c("group start %s" % g["id"]))
                room -= 1
        if run:
            return {"action": "work", "stage": "build", "calls": run, "agents": [], "say": "Build starts its groups."}

        try:
            mx = int(r.cfg("build.grouped.max-parallel", "4"))
        except ValueError:
            mx = 4
        sched = tasks_md.schedule(plan, r.groups, mx if mx > 0 else 4, self.task_model(),
                                  r.ctx.get("escalation_model") or "sonnet", os.getcwd()) if plan.get("tasks") else []
        ready = [x for x in sched if "task" in x]
        if ready:
            agents = []
            build_notes = r.notes("build", "input")
            # 9.8.0: one agent per chain. The tasks that would run one after another anyway (each depends on the one before,
            # or shares a file with it) go to one agent, which starts, builds and gates each in order (agents/build-task.md);
            # independent tasks still get agents of their own, launched at once. Each task keeps its worktree, its RED run,
            # its CLI gate and its retry. In measured runs every task ran alone, each paying a launch and its orchestration.
            review_notes = self.review_notes()
            for t in ready:
                chain = self.chain_of(plan, rt, t, ready)
                said = "".join("\nPerson's note: %s" % x for n in chain for x in scoped_notes(build_notes, n, t.get("group")))
                said += "".join("\nPlan review note: %s" % x for n in chain for x in review_notes.get(n, []))
                tasks_line = ("Task: %d." % t["task"]) if len(chain) == 1 else (
                    "Tasks: %s (a chain: do them in this order; start, build and gate each before the next)." % ", ".join(str(n) for n in chain))
                agents.append({"type": "temper:temper-build-task", "model": t.get("agent_model") or self.task_model(),
                               "before": [self.c("task start %d" % t["task"])],
                               "prompt": "Follow %s/agents/build-task.md exactly.\n%s\n%s%s%s\nModel: %s." % (
                                   self.plugin, self.plugin_line(), tasks_line, said, self.acceptance_line(), t.get("model")),
                               # the first task's gate judges the agent; the others it gated itself (a task it left running is gated here)
                               "after": [self.c("usage add --stage build --model %s --ms {ms} --task %d" % (t.get("model"), t["task"]))] +
                                        [self.c("task gate %d --model %s --if-running" % (n, t.get("model"))) for n in chain] +
                                        # the CLI draws each task's panel from what it recorded; the agent returns one line a task
                                        [self.c("panel task %s" % " ".join(str(n) for n in chain))],
                               "task": t["task"], "tasks": chain, "group": t.get("group"), "title": t.get("title"), "attempt": t.get("attempt")})
            return {"action": "work", "stage": "build", "calls": [], "agents": agents,
                    "say": "Build: %s. %s" % (", ".join(("Task %d" % x["task"] if len(x["tasks"]) == 1 else "Tasks %s" % ", ".join(str(n) for n in x["tasks"])) + " on " + short_model(x["model"]) for x in agents), goes_on(len(agents) > 1))}

        running = [(int(n), v) for n, v in rt.items() if isinstance(v, dict) and v.get("status") == "running"]
        covered = sorted(int(n) for n, v in rt.items() if isinstance(v, dict) and v.get("status") == "covered")
        if covered:
            return self.covered_task(covered[0], plan, rt.get(str(covered[0])) or {})
        waiting_on_person = sorted(n for n, v in running if v.get("awaiting") == "confirm")
        if waiting_on_person:
            return self.manual_task(waiting_on_person[0], plan)
        if running:
            return {"action": "wait", "stage": "build", "tasks": [
                {"task": n, "model": self.ran_on(v), "after": [self.c("task gate %d --model %s --ms {ms}" % (n, self.ran_on(v))),
                                                                 self.c("panel task %d" % n)]}
                for n, v in sorted(running)],
                "say": "Build: %s. %s" % (", ".join("Task %d runs on %s" % (n, short_model(self.ran_on(v))) for n, v in sorted(running)), goes_on(len(running) > 1))}

        for g in gid:
            st = (rg.get(g) or {}).get("status")
            if st == "parked":
                return self.parked(g)
        for g in plan.get("groups", []):
            gidx = g["id"]
            ginfo = rg.get(gidx) or {}
            tasks = g.get("tasks", [])
            done = tasks and all(tasks_md.task_done(t, r.groups) for t in plan.get("tasks", []) if t.get("n") in tasks)
            gate = (ginfo.get("gate") or {}).get("verdict")
            if done and not gate:
                return {"action": "work", "stage": "build", "calls": [self.c("group gate %s" % gidx)], "agents": [], "say": "Group %s is checked." % gidx}
            if gate == "FAIL" and ginfo.get("fix") and not r.armed():
                return self.group_fix_work(g, ginfo)
            if gate == "FAIL":
                return self.group_failed(g, ginfo)
            if gate == "PASS" and not ginfo.get("confirmed"):
                if r.armed():
                    return {"action": "auto", "stage": "build", "calls": [self.c("group continue %s" % gidx)], "say": "Group %s passed; the armed run goes on." % gidx}
                # 9.8.0: a plan with one group goes on to the merge by itself: the Build question comes right after, and
                # its "Change something" sends work back. Two questions in a row about the same work were one too many.
                if len(plan.get("groups", [])) == 1:
                    return {"action": "auto", "stage": "build", "calls": [self.c("group continue %s" % gidx)],
                            "say": "Group %s passed; the merge and the Build check come next." % gidx}
                return {"action": "ask", "stage": "build", "ask": self.group_question(g)}
        if gid and all(gpass(g) and (rg.get(g) or {}).get("confirmed") for g in gid):
            return {"action": "work", "stage": "build", "calls": [self.c("integrate"), self.c("gate build")], "agents": [],
                    "say": "Every group passed: the groups are merged and Build is checked."}
        return {"action": "work", "stage": "build", "calls": [self.c("gate build")], "agents": [], "say": "Build is checked."}

    def foreign_branch(self):
        """`temper integrate` found commits the CLI did not make on a passed group's branch: the person takes them out
        or keeps them (an armed run parks for them). None when there are none."""
        r = self.r
        integ = r.groups.get("integration") or {}
        foreign = integ.get("foreign") if integ.get("verdict") == "FAIL" else None
        if not isinstance(foreign, dict) or not foreign:
            return None
        again = [self.c("integrate"), self.c("gate build")]
        branches = (r.groups.get("groups") or {})
        left = {}
        for g in sorted(foreign):
            # A commit the person kept already (an override) or one no longer on the group's branch is no question: the
            # next integrate reads the branch again.
            kept = {str(o.get("stage", "")).split(":", 2)[2] for o in r.overrides
                    if isinstance(o, dict) and str(o.get("stage", "")).startswith("foreign-commit:%s:" % g)}
            on = set(git("rev-list", "temper/%s/%s" % (r.slug, g)).split())
            shas = [x for x in foreign.get(g) or [] if isinstance(x, str) and x not in kept and (not on or x in on)]
            if shas:
                left[g] = shas
        if not left:
            # Asked, never run unattended: integrate leaves its record as it is when it stops early (another branch, a
            # protected one), and running it again unasked would go round with no one told why.
            if r.armed():
                return {"action": "auto", "stage": "build",
                        "calls": [self.c("park --verdict PARKED-NEEDS-DECISION --reason %s" % shlex.quote("the groups are to be merged again after the commits the CLI did not make were kept or taken out"))],
                        "say": "The armed run parks for you before the groups are merged again."}
            return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER,
                    "The commits the CLI did not make are kept or taken out. Merge the groups again?", stage="build", options=[
                        self.opt("Merge the groups (Recommended)", "Merge the passed groups again and check Build.", move="redo", calls=again),
                        self.save()])}
        gid = sorted(left)[0]
        shas = left[gid]
        csv = ",".join(x[:7] for x in shas)
        if r.armed():
            return {"action": "auto", "stage": "build",
                    "calls": [self.c("park --verdict PARKED-NEEDS-DECISION --reason %s" % shlex.quote("group %s's branch holds commits the CLI did not make: %s" % (gid, csv)))],
                    "say": "Group %s holds commits the CLI did not make; the armed run parks for you." % gid}
        wt = (branches.get(gid) or {}).get("worktree") or ""
        # They are taken out newest first, each one by a rebase of the group's worktree onto its parent. Only when they
        # are the newest commits of that branch: a rebase would write the CLI's own commits above them again, as commits
        # the CLI did not make. Never with no worktree (`git -C ''` is the project's own branch).
        tip = git("-C", wt, "rev-list", "--first-parent", "-n", str(len(shas)), "HEAD").split() if wt and os.path.isdir(wt) else []
        out = []
        if tip and set(tip) == set(shas):
            out.append(self.opt("Take the commits out (Recommended)", "Remove them from the group's branch, newest first; the groups are merged again.", move="redo",
                                calls=["git -C %s rebase --autostash --onto %s~1 %s" % (shlex.quote(wt), x[:7], x[:7]) for x in shas] + again))
        out += [self.opt("Keep the commits", "Keep them knowingly, with your reason (recorded like a skip).", move="keep",
                         calls=[self.c("group reopen %s --accept-foreign %s --reason '{reason}'" % (gid, csv))] + again,
                         reason=["The commits are right", "I accept the risk"]),
                self.save()]
        if len(out) == 3:
            text = "Group %s's branch holds commits the CLI did not make (%s). Take them out, or keep them?" % (gid, csv)
        else:
            why = ("its worktree is gone" if not (wt and os.path.isdir(wt)) else
                   "they are not the newest commits of the group's branch")
            text = ("Group %s's branch holds commits the CLI did not make (%s); %s, so they cannot be taken out here. "
                    "Keep them, or save the run and take them out by hand?" % (gid, csv, why))
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=out)}

    def covered_task(self, n, plan, info):
        """A task whose tests passed before any change: an earlier task built it. The person decides; nothing retries it."""
        r = self.r
        title = next((x.get("title", "") for x in plan.get("tasks", []) if x["n"] == n), "")
        c = info.get("covered") or {}
        if r.armed():
            # 9.8.0: an unattended run takes a covered task as done (its tests pass, the plan asked for work already done);
            # the reason names it, and the run's report lists it. It parked here before, which ended most unattended runs.
            return {"action": "auto", "stage": "build", "calls": [self.c("task accept %d --reason %s" % (n, shlex.quote(
                "An earlier task built it (unattended run)")))],
                "say": "Task %d's tests already pass: an earlier task built it, so the unattended run takes it as done." % n}
        tail = " ".join(str(c.get("tail", "")).split())[:300]
        text = "Task %d (%s): its tests already pass before any change, so an earlier task built it. The RED run %s passed (exit 0): %s. Accept it as done?" % (
            n, title, c.get("cmd") or "(no command)", tail or "no output")
        # `covered`, not `accept`: accepting a review finding leaves a defect in; this takes work that is done (9.8.0).
        # 9.8.0: the reason is the question's own fact (an earlier task built it), so it is recorded without a second question.
        opts = [self.opt("Accept it as done (Recommended)", "Commit its tests, merge them and tick the task (reason: an earlier task built it).", move="covered",
                         calls=[self.c("task accept %d --reason %s" % (n, shlex.quote("An earlier task built it")))]),
                self.opt("Run it again", "The kept worktree goes and a fresh attempt starts.", move="redo", calls=[self.c("task retry %d" % n)])]
        if r.can_loop("build", "plan"):
            opts.append(self.opt("Loop back to Plan", "The plan asks for work that is already done.", move="back",
                                 calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The plan cannot be built"]))
        opts.append(self.save())
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=opts)}

    def manual_task(self, n, plan):
        """A manual task (`**Test:** manual`) whose files are made: the person confirms each Case by hand."""
        r = self.r
        t = next((x for x in plan.get("tasks", []) if x["n"] == n), {"title": "", "block": ""})
        cases = []
        on = False
        for line in t.get("block", "").splitlines():
            if re.match(r"^\*\*Cases:\*\*", line):
                on = True
                inline = line.split(":**", 1)[1].strip()
                if inline:
                    cases.append(inline)
                continue
            if on and re.match(r"^\*\*\w+:\*\*", line):
                on = False
            m = re.match(r"^\s*[-*]\s+(?!\[[ xX]\])(\S.*)$", line) if on else None
            if m:
                cases.append(m.group(1).strip())
        if r.armed():
            return {"action": "auto", "stage": "build", "calls": [self.c("park --verdict PARKED-NEEDS-DECISION --reason %s" % shlex.quote(
                "Task %d is a manual task: it needs you to confirm it by hand" % n))],
                "say": "Task %d is a manual task; the armed run parks for you." % n}
        text = "Task %d (%s) is a manual task. Confirm by hand that each Case holds: %s." % (n, t.get("title", ""), "; ".join(cases) or "see the task")
        confirm = self.opt("Confirm", "Every Case holds; the task passes.", move="confirm",
                           calls=[self.c("task confirm %d --by '{answer}'" % n), self.c("task gate %d --model person" % n)],
                           answer=("Manual task", "Task %d: what name should the confirmation carry?" % n))
        return {"action": "ask", "stage": "build", "ask": self.question("Manual task", text, stage="build", options=[
            confirm, self.opt("Stop", "Save the run for later.", move="pause", calls=[], stop=True)])}

    def reopen_set(self, g, n):
        """Task n and the tasks that must reopen with it: a task of the group that has run (passed or running), depends on a
        task already taken, directly or not, and shares a declared file with it."""
        plan = self.r.plan or {"tasks": []}
        rt = self.r.groups.get("tasks") or {}
        by_n = {t["n"]: t for t in plan["tasks"] if t.get("group") == g["id"]}

        def deps(m, seen):
            out = set()
            for d in by_n[m]["depends"]:
                if d in by_n and d not in seen:
                    out |= {d} | deps(d, seen | {d})
            return out

        taken = [n]
        grew = True
        while grew:
            grew = False
            for m in sorted(by_n):
                if m in taken or (rt.get(str(m)) or {}).get("status") not in ("passed", "running"):
                    continue
                up = deps(m, {m})
                if any(t in up and set(by_n[m]["files"]) & set(by_n[t]["files"]) for t in taken):
                    taken.append(m)
                    grew = True
        return sorted(taken)

    def group_question(self, g):
        gid = g["id"]
        opts = []
        for t in g.get("tasks", []):
            n = t if isinstance(t, int) else t
            taken = self.reopen_set(g, n)
            others = [m for m in taken if m != n]
            names = ["Task %d" % m for m in taken]
            label = "Task %d" % n + (" (with %s)" % ", ".join("Task %d" % m for m in others) if others else "")
            what = names[0] if len(names) == 1 else "%s and %s" % (", ".join(names[:-1]), names[-1])
            opts.append(self.opt(label, "Re-runs %s; the other tasks of %s keep their work." % (what, gid), move="redo",
                                 calls=[self.c("group reopen %s %s --feedback {K}" % (gid, " ".join("--task %d" % m for m in taken)))]))
        which = self.with_more(GROUP_HEADER, "Which task changes?", "build", opts[:3] if len(opts) > 4 else opts,
                               opts[3:] if len(opts) > 4 else [], "Which task changes? More tasks.")
        q = self.question(GROUP_HEADER, "Group %s (%s) passed its check. Continue?" % (gid, g.get("title", "")), stage="build", options=[
            self.opt("Continue (Recommended)", "Go on to the next group, or to the merge.", move="advance", calls=[self.c("group continue %s" % gid)]),
            self.opt("Change", "Give feedback; only the tasks it concerns run again.",
                     do="Record each item the person typed with %s, then ask the change question (Which task changes?) in this action's `change`; its option runs the reopen call."
                        % self.c("evidence add --stage build --phase feedback --claim 'feedback #{K}: {text}'")),
            self.opt("Stop", "Save the run for later.", move="pause", calls=[], stop=True)],
            extra={"change": which})
        return q

    @staticmethod
    def fail_text(ginfo, n=3):
        """9.8.4: the first FAIL lines of the group's Validate output, as the gate kept them ('' when none)."""
        lines = [str(x) for x in ((ginfo.get("gate") or {}).get("fail_lines") or []) if str(x).strip()][:n]
        return "; ".join(x if len(x) <= 160 else x[:157] + "..." for x in lines)

    def group_failed(self, g, ginfo):
        gid = g["id"]
        gate = ginfo.get("gate") or {}
        reason = " ".join(str(gate.get("reason", "")).split())
        reason = reason if len(reason) <= 300 else reason[:297] + "..."
        fl = self.fail_text(ginfo)
        if self.r.armed():  # nobody is there to answer: an armed run parks, as on every stop
            why = (reason[:200] + (" | " + fl if fl else ""))[:400]
            return {"action": "auto", "stage": "build",
                    "calls": [self.c('park --verdict PARKED-NEEDS-DECISION --reason %s' % shlex.quote("group %s failed its check: %s" % (gid, why)))],
                    "say": "Group %s failed its check; the armed run parks for you." % gid}
        plan = self.r.plan or {"tasks": []}
        # 9.8.4: how many times the group's check failed, and whether the whole failed while every part passed. A blind
        # rerun of every task was always the recommended answer; a measured run reran a group of 12 tasks five times.
        fails = int(ginfo.get("fails") or 1)
        all_passed = bool(g.get("tasks")) and all(tasks_md.task_done(t, self.r.groups) for t in plan.get("tasks", []) if t.get("n") in g.get("tasks", []))
        fixable = all_passed and bool(gate.get("ran"))
        # a fix of the merged tree that did not make the group pass is not recommended again: the run converges on the plan
        # (a step back) or on the person (Save for later), never on the same retry (an e2e run looped on it 131 times)
        tried = int(ginfo.get("fix_tries") or 0)
        reopen = [self.c("group reopen %s %s" % (gid, " ".join("--task %d" % n for n in g.get("tasks", []))))]
        opts = []
        limit = int(gate.get("timeout_s") or 0)
        if limit:  # the gate ran out of time, not out of luck: the same checks again with twice the limit
            opts.append(self.opt("Run the gate again with twice the time (Recommended)", "Group %s's checks run again, limit %d seconds." % (gid, 2 * limit),
                                 move="redo", calls=[self.c("group gate %s --timeout-s %d" % (gid, 2 * limit))]))
        fix_rec = fixable and not limit and not tried
        fix = self.opt("Fix the group's merged work" + (" (Recommended)" if fix_rec else ""),
                       "One Build fix agent works on %s's merged tree (every task's work together) until its check passes; the tasks keep their work." % gid,
                       move="redo", calls=[self.c("group fix %s" % gid)]) if fixable else None
        back = self.r.can_loop("build", "plan")
        rerun_rec = not limit and not fixable and fails < 2
        rerun = self.opt("Run the group's tasks again" + (" (Recommended)" if rerun_rec else ""), "Each task of %s runs again." % gid, move="redo", calls=reopen)
        plan_rec = not limit and not fix_rec and not rerun_rec and back
        loop = self.opt("Loop back to Plan" + (" (Recommended)" if plan_rec else ""), "The plan cannot be built as written.", move="back",
                        calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The plan cannot be built"]) if back else None
        save_rec = not limit and not fix_rec and not rerun_rec and not plan_rec
        save = self.save()
        if save_rec:
            save["label"] += " (Recommended)"
        if fix_rec or limit:
            rest = [fix, rerun, loop]
        elif plan_rec:
            rest = [loop, fix, rerun]
        elif save_rec:
            rest = [save, fix, rerun]
        else:
            rest = [rerun, fix, loop]
        opts += [o for o in rest if o]
        if not save_rec:
            opts.append(save)
        text = "Group %s failed its check" % gid + (" %d times" % fails if fails > 1 else "") + " (%s)." % reason
        if fl:
            text += " What failed: %s." % fl
        if tried and fixable:
            text += " A fix of its merged work did not make it pass" + (": the plan is the likelier cause." if back else ".")
        text += (" Fix its merged work?" if fix_rec else " Loop back to Plan?" if plan_rec else
                 " Save the run for later?" if save_rec else " Run its tasks again?")
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=opts)}

    def group_fix_work(self, g, ginfo):
        """9.8.4: the person chose to fix a group whose check failed after every task passed: one Build fix agent works on the
        group's merged tree; the CLI commits what it changed on the group's branch, and the next action checks the group."""
        gid = g["id"]
        gate = ginfo.get("gate") or {}
        fl = [str(x) for x in gate.get("fail_lines") or []][:8]
        lines = ["Group fix: group %s's check failed after every one of its tasks passed. Work only in its worktree %s (the merged "
                 "work of the group, on branch %s); do not commit, the CLI commits what you change. Make its Validate command pass: %s." % (
                     gid, ginfo.get("worktree", ""), ginfo.get("branch", ""), g.get("validate") or "(none declared)"),
                 "Why the check failed: %s." % " ".join(str(gate.get("reason", "")).split())]
        if fl:
            lines.append("What failed (the first FAIL lines of its output): %s." % "; ".join(fl))
        a = self.agent("build", lines)
        # the commit clears the group's gate: the next action checks the group as an ordinary call, and a FAIL there asks
        # the group question again (a group gate prints no `-> FAIL`, so as an agent's gate call a FAIL would stop the run)
        a["after"].append(self.c("group fix %s --commit" % gid))
        return {"action": "work", "stage": "build", "calls": [], "agents": [a],
                "say": "Build: one fix agent works on group %s's merged tree%s. %s" % (gid, on_model([a]), goes_on(False))}

    def parked(self, gid):
        r = self.r
        g = r.groups.get("groups", {}).get(gid) or {}
        tasks = sorted(int(n) for n, v in (r.groups.get("tasks") or {}).items()
                       if isinstance(v, dict) and v.get("group") == gid and v.get("status") in ("failed", "running"))
        targs = " ".join("--task %d" % n for n in tasks) or "--task {N}"
        foreign = g.get("parked_foreign") or []
        if r.armed():
            return {"action": "auto", "stage": "build",
                    "calls": [self.c('park --verdict PARKED-NEEDS-DECISION --reason %s' % shlex.quote("group %s is parked: %s" % (gid, str(g.get("parked_reason", ""))[:200])))],
                    "say": "Group %s is parked; the armed run parks for you." % gid}
        if foreign:
            wt = ""
            for n in tasks:
                wt = (r.groups.get("tasks", {}).get(str(n)) or {}).get("worktree") or wt
            wt = wt or g.get("worktree", "")
            fp = git("-C", wt, "rev-list", "--first-parent", "HEAD").split() if wt else []
            lines = ["git -C %s rebase --autostash --onto %s~1 %s" % (wt, s[:7], s[:7]) for s in foreign if not fp or s in fp] or \
                    ["git -C %s rebase --autostash --onto %s~1 %s" % (wt, s[:7], s[:7]) for s in foreign]
            csv = ",".join(s[:7] for s in foreign)
            opts = [self.opt("Take the commits out and run the task again (Recommended)", "Remove the agent's commits, newest first; the task runs again.",
                             move="redo", calls=lines + [self.c("group reopen %s %s" % (gid, targs))]),
                    self.opt("Keep the agent's commits", "Keep them knowingly, with your reason (recorded like a skip).", move="keep",
                             calls=[self.c("group reopen %s %s --accept-foreign %s --reason '{reason}'" % (gid, targs, csv))],
                             reason=["The commits are right", "I accept the risk"]),
                    self.save()]
            text = "Group %s is parked: a task agent made commits the CLI did not (%s). Take them out, or keep them?" % (gid, csv)
        elif any(isinstance((r.groups.get("tasks", {}).get(str(n)) or {}).get("blocked"), dict) for n in tasks):
            # 9.8.4: a task whose test needs a file it does not declare: no attempt on any model can build it as planned
            # (a benchmark run spent two Haiku and two Sonnet attempts on one), so the plan comes first
            b = [((r.groups.get("tasks", {}).get(str(n)) or {}).get("blocked"), n) for n in tasks]
            b = [(x, n) for x, n in b if isinstance(x, dict)]
            what = "; ".join("Task %d needs %s, which %s (%s)" % (
                n, x.get("needs"), ("Task %s declares" % ", ".join(str(o) for o in x.get("owners") or []) if x.get("owners") else "no task declares"),
                x.get("reason") or "no reason given") for x, n in b)
            back = r.can_loop("build", "plan")
            rerun = self.opt("Run the task again", "The blocked tasks run again as planned.", move="redo", calls=[self.c("group reopen %s %s" % (gid, targs))])
            save = self.save()
            if back:
                opts = [self.opt("Loop back to Plan (Recommended)", "Plan moves the change or the test into the task that owns the file.", move="back",
                                 calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The plan cannot be built"]), rerun, save]
            else:
                save["label"] += " (Recommended)"
                opts = [save, rerun]
            text = "Group %s is parked: %s. No attempt can build it as planned. %s" % (
                gid, what, "Loop back to Plan?" if back else "Save the run for later?")
        else:
            # 9.8.0 (round 5): a group that parks again after the person ran it again failed every model twice over: the
            # plan is the likelier cause, so Loop back to Plan is the recommended answer then (a measured run reran a
            # task whose gate ran a test a later task writes, and parked five times).
            again = r.can_loop("build", "plan") and any((r.groups.get("tasks", {}).get(str(n)) or {}).get("reopened") for n in tasks)
            rerun = self.opt("Run the task again" + ("" if again else " (Recommended)"), "The parked tasks run again, from Haiku.", move="redo",
                             calls=[self.c("group reopen %s %s" % (gid, targs))])
            opts = [] if again else [rerun]
            if r.can_loop("build", "plan"):
                opts.append(self.opt("Loop back to Plan" + (" (Recommended)" if again else ""), "The plan cannot be built as written.", move="back",
                                     calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The plan cannot be built"]))
            if again:
                opts.append(rerun)
            opts.append(self.save())
            text = ("Group %s is parked again after a rerun (%s). Loop back to Plan?" if again else
                    "Group %s is parked (%s). Run the task again?") % (gid, str(g.get("parked_reason", ""))[:200])
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=opts)}

    # -- the end of the run --------------------------------------------------------------------
    # Three actions, in order: the report steps (the intent completed, the report printed for the person), the page
    # (temper report --html, with no question since 9.8.0), then the record steps (the ledger archived, the commit, the state cleared). The CLI
    # records the first two in the run's end_report (temper report --end, then --html or --no-html).
    def report_steps(self):
        r = self.r
        steps = []
        if r.command == "temper":
            # the CLI completes only an accepted intent (a draft is never marked completed): a run whose intent nobody
            # accepted, or one completed already, has no completion step
            if intent_parse.status(r.intent) == "accepted":
                steps.append(self.c("intent complete"))
            steps.append(self.c("spec deviations"))   # 9.8.0: by the CLI, from build-context.json
        steps.append(self.c("report --end"))
        steps.append("Copy what temper report printed into your reply, as it printed it, in a code block: the person does not "
                     "see the output of a Bash call.")
        return steps

    def feature_message(self):
        title = (self.r.title() or self.r.slug or "the change").strip().rstrip(".")
        return "feat(%s): %s" % (self.r.slug, title[:1].lower() + title[1:] if title else "the change")

    def fix_message(self):
        """The commit message of a fix run: fix(<slug>): <the RCA's title>, then the root cause and the regression tests, from
        rca.md and the diff, one paragraph each."""
        r = self.r
        text = ""
        try:
            text = open(os.path.join(r.spec, "rca.md"), encoding="utf-8").read() if r.spec else ""
        except OSError:
            pass
        m = re.search(r"^#\s+(?:RCA:\s*)?(.+?)\s*$", text, re.M)
        title = (m.group(1) if m else (r.state.get("feature") or "the bug")).strip().rstrip(".")
        cause = ""
        sec = re.search(r"^##+\s*Root cause\s*$(.*?)(?=^##|\Z)", text, re.M | re.S | re.I)
        if sec:
            cause = next((l.strip() for l in sec.group(1).splitlines() if l.strip()), "")
        tests = sorted({f for f in (r.ctx.get("changed") or []) if re.search(r"(^|/)(tests?|unit|spec)/|test_[^/]*$|_test\.|\.(test|spec)\.", f)})
        parts = ["fix(%s): %s" % (r.slug, title[:1].lower() + title[1:])]
        if cause:
            parts.append("Root cause: " + cause[:300])
        if tests:
            parts.append("Regression test: " + ", ".join(tests[:5]))
        return "\n\n".join(parts)

    def record_steps(self):
        r = self.r
        steps = [self.c("state archive")]
        files = r.ctx.get("changed") or []
        if not r.spec_ignored() and r.spec:
            files = [r.spec + "/"] + [f for f in files if not f.startswith(r.spec + "/")]
        # A fix run's lesson is committed with it, unless the project keeps .temper out of git (then it stays local).
        lessons = [".temper/lessons.md"] if r.command == "fix" and ".temper/lessons.md" not in files and not r.ctx.get("lessons_ignored") else []
        code = [f for f in files if not (f.startswith(r.spec + "/") or f.startswith(".temper/"))] if r.spec else files
        # The code this commit carries: what is still uncommitted (Build commits each task, each group and the merge).
        if code and git("rev-parse", "--verify", "-q", "HEAD"):
            code = [f for f in code if git("status", "--porcelain", "--", f)]
        if not code and not lessons and (r.spec_ignored() or not r.spec or not r.ctx.get("spec_dirty")):
            # F27: nothing to stage: no uncommitted code, no lesson file, and a spec folder git ignores. No git add, no git commit.
            steps.append("There is no record commit: no uncommitted code, no lesson file, and the spec folder is git-ignored or unchanged, so there is nothing to stage.")
        else:
            if r.command == "fix":
                # 9.8.0: the CLI drafts the message from rca.md and the tests the fix changed; the person can still amend it.
                message = self.fix_message()
            elif files and not code:
                # A grouped Build commits the code itself (each task, each group, the merge into this branch): this commit is
                # the run's record, and its message says so.
                message = "docs(%s): record the run: spec, gate ledger and report (the code is in the commits before it)" % r.slug
            else:
                # 9.8.0: the CLI drafts the message from the intent's title (one call fewer for the session).
                message = self.feature_message()
            if files:
                # 9.8.0: one CLI call stages the files and commits (scripts/spec_ops.py): the steps are all temper calls,
                # run in one Bash call. Each name is one shell quoted word: a file name is never shell code.
                steps.append(self.c("spec commit %s -- %s" % (shlex.quote(message), " ".join(shlex.quote(f) for f in files + lessons))))
            else:
                steps.append("git add -- (each file the run changed)%s" % "".join(" " + x for x in lessons))
                steps.append("git commit -m %s" % shlex.quote(message))
        pr = r.state.get("pr")
        if pr in ("one", "stacked") and not r.armed() and r.command == "temper":
            steps.append("Pull request: follow %s/reference/pr.md, section Capture, now: note base_sha, the branch, the default branch and the spec path, "
                         "since the state is gone after state clear." % self.plugin)
            steps.append("Follow %s/reference/pr.md, section %s: every pull request is a draft, and Temper never marks one ready. "
                         "A pull request that cannot be opened never fails the commit." % (self.plugin, "One PR" if pr == "one" else "Stacked PRs"))
        if r.command == "temper" and r.cfg("phases.pipeline", "true").lower() != "false" and pr in ("one", "stacked") and not r.armed():
            steps.append("If a pull request was opened, run %s: Pipeline reads its checks. Otherwise run %s." % (
                self.c("state advance commit_complete pipeline"), self.c("state clear")))
        else:
            steps.append(self.c("state clear"))
        return steps

    def commit(self):
        r = self.r
        verdict = r.verdict("commit")
        if verdict is None:
            return {"action": "work", "stage": "commit", "calls": [self.c("gate commit")], "agents": [], "say": "The commit gate is checked."}
        if r.armed():
            kind = "SHIP-PENDING-COMMIT" if verdict == "PASS" else "PARKED-NEEDS-DECISION"
            why = "; ".join("%s: %s" % (x.get("name"), x.get("detail")) for x in r.failed_rows("commit"))[:200]
            return {"action": "auto", "stage": "commit", "calls": [self.c('park --verdict %s --reason %s' % (kind, shlex.quote(why or "every gate passed")))],
                    "say": "The armed run parks before the commit; the person decides."}
        if verdict == "PASS":
            end = r.state.get("end_report")
            if end in ("html", "none"):
                return {"action": "work", "stage": "commit", "calls": [], "agents": [], "steps": self.record_steps(),
                        "say": "The commit carries the run's record."}
            if end == "shown":
                # 9.8.0: the report page is written without a question (it is committed with the spec); the run asked
                # "write it as HTML too?" at every commit before, one more decision with nothing at stake.
                return {"action": "work", "stage": "commit", "calls": [self.c("report --html")], "agents": [],
                        "say": "The report page is written (report.html in the spec folder); then the commit."}
            if r.state.get("parked"):
                return {"action": "ask", "stage": "commit", "ask": self.question(GATE_HEADER, "Commit: every gate passed, and the armed run parked here for you (its report: .temper/autonomy-report.md). Commit?", stage="commit", options=[
                    self.opt("Commit (Recommended)", "Commit the change with its spec files.", move="advance", steps=self.report_steps()), self.save()])}
            return {"action": "work", "stage": "commit", "calls": [], "agents": [], "steps": self.report_steps(),
                    "say": "Every gate passed: the report first, then the commit."}
        failing = sorted({re.sub(r"\s+gate$", "", str(x.get("name", ""))) for x in r.failed_rows("commit") if str(x.get("name", "")).endswith(" gate")})
        # Only rows of the commit gate's own failed (an armed run's blast radius or park-on-touch): the person's skip is
        # of the commit check itself, recorded with their reason like any other.
        failing = failing or ["commit"]
        opts = []
        # 9.8.0: files changed outside the plan (the scope row): the person adds them to the plan here, the same answer as
        # "Add to plan" at a Scope drift question (a drift row in the Build ledger), and the commit gate runs again.
        outside = []
        for x in r.failed_rows("commit"):
            m = re.match(r"changed outside declared files: (.+)$", str(x.get("detail", ""))) if x.get("name") == "blast radius" else None
            if m:
                outside = [f.strip() for f in re.sub(r"\s*\(and \d+ more\)$", "", m.group(1)).split(",") if f.strip() and not re.search(r"\s|'", f.strip())]
        if outside:
            opts.append(self.opt("Add to plan (Recommended)", "%s belong%s to this feature: record %s as planned, then check the commit again." % (
                ", ".join(outside), "s" if len(outside) == 1 else "", "it" if len(outside) == 1 else "them"), move="drift",
                calls=[self.c("evidence add --stage build --phase feedback --claim %s" % shlex.quote("drift %s: Add to plan: the person, at the commit gate" % f))
                       for f in outside] + [self.c("gate commit")]))
        if r.command == "fix" and "check" in failing and r.can_loop("check", "fix"):
            opts.append(self.opt("Loop back to Fix (Recommended)", "Write the fix again; Review and Check run again.", move="back",
                                 calls=[self.c("state loop check fix --reason '{reason}'")], reason=["The check found a real problem"]))
        opts.append(self.opt("Override and commit", "Skip the failed gates with your reason and commit.", move="commitOverride",
                             calls=[self.c("override %s --reason '{reason}'" % s) for s in failing] + [self.c("gate commit")],
                             reason=["I accept the risk", "It is not a real issue"]))
        opts.append(self.save())
        why = "; ".join("%s: %s" % (x.get("name"), x.get("detail")) for x in r.failed_rows("commit")[:3])
        return {"action": "ask", "stage": "commit", "ask": self.question(GATE_HEADER, "Commit: the commit gate failed (%s). Override and commit?" % why, stage="commit", options=opts)}

    def restart(self):
        r = self.r
        return {"header": RESUME_HEADER, "question": "A run of %s is open at %s. Start over?" % (r.slug, LABEL.get(r.stage, r.stage)),
                "multiSelect": False, "step": r.state.get("step"), "run_id": r.state.get("run_id"),
                "options": [{"label": "Start over", "description": "The saved run state goes; the spec files stay.", "move": "restart",
                             "calls": [self.c("state clear")]},
                            {"label": "Cancel", "description": "Keep the run.", "move": None, "calls": []}]}

    # -- the one entry point -------------------------------------------------------------------
    @staticmethod
    def context_text(cm):
        """9.8.0: the Context check names what the plan leaves out and what it could not find, from the map's own `ignore` and
        `gap` lines, so the person answers a concrete question instead of judging a list of sources."""
        rows = cm.get("rows") or []
        cut = lambda t: t if len(t) <= 90 else t[:87] + "..."
        left = [cut(x["text"]) for x in rows if x.get("kind") == "ignore"][:3]
        gaps = [cut(x["text"]) for x in rows if x.get("kind") == "gap"][:2]
        parts = []
        if left:
            parts.append("The plan leaves out: %s." % "; ".join(left))
        if gaps:
            parts.append("It could not find: %s." % "; ".join(gaps))
        if not parts:
            return "Is this the right context for the plan?", []
        return " ".join(parts) + " Is that right?", left

    def context_question(self, cm):
        """The Context check as the CLI's own question. "As planned" records the answer and checks the plan again; any other
        answer (including what was left out, a source the person names) also sends Plan back to revise with it (`--redo`),
        so the answer changes the plan instead of only being written down (9.8.0)."""
        text, left = self.context_text(cm)
        opts = [self.opt("As planned (Recommended)", "The plan's context is right; check the plan again.", move="answer",
                         calls=[self.c("plan review --answer 'As planned'"), self.c("gate plan")])]
        if left:
            # 9.8.4: Plan gets the whole text of what is left out (the question shows each cut to fit); a cut at 100
            # characters told the Plan agent "already co".
            full = [x["text"] for x in (cm.get("rows") or []) if x.get("kind") == "ignore"][:3]
            what = "Include what is left out: %s" % "; ".join(full)
            opts.append(self.opt("Include what is left out", "Plan revises the plan to cover: %s." % "; ".join(left), move="answer",
                                 calls=[self.c("plan review --answer %s --redo" % shlex.quote(what))]))
        opts.append(self.opt("Something else", "Type what Plan should change or read (Other); Plan revises the plan with it.",
                             do="Ask the person to type it in Other, then run the question's `answer` call with their text."))
        carry = self.opt("Carry forward", "Decide later; the plan gate keeps naming this question.", move=None, calls=[])
        opts.append(carry)
        for o in opts:
            o["preview"] = cm["table"]
        q = self.question(GATE_HEADER, text, opts, "plan")
        q["context"] = True
        q["answer"] = self.c("plan review --answer '{text}' --redo")
        q["gate"] = self.c("gate plan")
        return q

    def next(self):
        out = self.core_next()
        r = self.r
        if r.active and r.stage == "plan":
            cm = r.context()
            if cm:
                out["context_map"] = {k: cm[k] for k in ("intro", "file", "rows", "answer", "table")}
                if cm["reviewed"] not in ("human", "auto") and r.cfg("plan.context-check", "auto").lower() != "off":
                    q = self.context_question(cm)
                    out["context_check"] = {k: q[k] for k in ("question", "options", "answer", "gate")}
                    out["context_check"]["header"] = GATE_HEADER
                    rows = r.failed_rows("plan")
                    if out.get("action") == "ask" and len(rows) == 1 and rows[0].get("name") == "context map reviewed":
                        out["ask"] = q    # the only failed row is the pending check: ask the check itself, so a refused call can be answered again
        return out

    def core_next(self):
        r = self.r
        if not r.active:
            return {"v": VERSION, "action": "none", "run": None, "say": "No run is active."}
        out = {"v": VERSION, "run": self.run_info(), "restart": self.restart()}
        if r.stage not in r.seq() or (r.stage not in ("intent", "rca") and r.spec and not os.path.isdir(r.spec)):
            out.update({"action": "broken", "say": "The run state does not fit its spec folder (%s at %s)." % (r.spec, r.stage)})
            return out
        stage = r.stage
        done = r.state.get("adhoc_done")
        if isinstance(done, dict) and done.get("steps") and not r.state.get("adhoc"):
            step = done["steps"][0]
            if step in ("check", "commit") and "review" not in done["steps"] and r.verdict("review") == "FAIL" and stage in ("check", "commit"):
                out.update(self.side_review_failed(done))
            else:
                out.update(self.small_change_work(done))
            return out
        if stage == "commit":
            out.update(self.commit())
            if out.get("action") == "ask":
                self.add_adhoc(out, "commit")
            return out
        if stage == "build" and r.command == "temper":
            fb = self.foreign_branch()
            if fb is not None:
                out.update(fb)
                return out
        if r.command == "fix" and stage == "rca":
            out.update({"action": "ask", "stage": stage, "ask": self.ask(stage)})
            return out
        verdict = r.verdict(stage)
        skipped = r.skip(stage) is not None
        fixacc = (self.acceptance_fix_work() or self.acceptance_triage_work()) if stage == "check" and verdict is not None and not skipped else None
        if fixacc:
            out.update(fixacc)
            return out
        # A note the person gave after the verdict: input goes to the agent again, edit (made for them) only to the gate.
        if verdict is not None and not skipped and not self.walked(stage):
            if r.stale_notes(stage, "input"):
                if stage == "build" and r.command == "temper":
                    a = self.agent("build", self.feedback_lines())
                    a["after"].append(self.c("gate build"))
                    a["gate"] = a["after"][-1]
                    out.update({"action": "work", "stage": "build", "calls": [], "agents": [a],
                                "say": "Build: the fix pass is taking up your note%s. %s" % (on_model([a]), goes_on(False))})
                else:
                    out.update(self.stage_work(stage))
                return out
            if r.stale_notes(stage, "edit"):
                out.update({"action": "work", "stage": stage, "calls": [self.c("gate %s" % (r.gate_of(stage) or stage))], "agents": [],
                            "say": "%s is checked again after your change." % LABEL[stage]})
                return out
        records = r.missing_records(stage) if verdict == "FAIL" and not skipped and r.command == "temper" else []
        if records and r.state.get("record_pass") != r.round_id():
            a = self.agent("build", ["Record only: write the rows below with `temper evidence run`; change no code, no test and no plan file."] + records)
            a["after"].append(self.c("state set record_pass %s" % shlex.quote(r.round_id())))
            a["after"].append(self.c("gate build"))
            a["gate"] = a["after"][-1]
            out.update({"action": "work", "stage": "build", "calls": [], "agents": [a],
                        "say": "Build: the record pass is working%s. %s" % (on_model([a]), goes_on(False))})
            return out
        if stage == "plan" and verdict is not None and not skipped:
            fr = r.fresh()
            ready = all(x.get("name") in FRESH_ROWS + ("context map reviewed",) for x in r.failed_rows("plan"))
            if fresh_review.need_launch(fr) and ready:
                out.update(self.fresh_work(fr))
                return out
        if verdict is None and not skipped:
            if self.walked(stage):
                out.update({"action": "work", "stage": stage, "calls": [self.c("gate %s" % stage)], "agents": [],
                            "say": "%s ran before this run started; it is checked." % LABEL[stage]})
            elif stage == "build" and r.command == "temper":
                out.update(self.build_work())
            else:
                out.update(self.stage_work(stage))
            return out
        # 9.8.0: the unattended run is Build alone (the person asked for it): Review, Check and the commit keep their
        # questions. When Build's gate passes, the run goes on to Review and turns back to interactive.
        if r.armed() and stage not in ("intent", "plan", "rca", "review", "check"):
            nxt = r.next_of(stage)
            if stage == "design" and r.tasks_changed():
                out.update({"action": "auto", "stage": stage, "calls": [self.c('park --verdict PARKED-NEEDS-DECISION --reason %s' % shlex.quote(
                    "Design changed the plan's tasks; the person approves them"))],
                            "say": "Design changed the plan's tasks; the armed run parks for you."})
                return out
            if stage == "design" and r.open_concerns():
                # a person resolves each area of concern at the Design question, before Build: an armed run parks for them
                out.update({"action": "auto", "stage": stage, "calls": [self.c('park --verdict PARKED-NEEDS-DECISION --reason %s' % shlex.quote(
                    "Design has %d open area(s) of concern" % len(r.open_concerns())))],
                            "say": "Design has open areas of concern; the armed run parks for you."})
                return out
            if verdict == "PASS" or skipped:
                calls = [self.c("state advance %s_complete %s" % (stage, nxt))]
                say = "%s passed; the armed run goes on." % LABEL[stage]
                if stage == "build":
                    calls.append(self.c("state set run_mode interactive"))
                    say = "Build passed; the unattended part ends here, and %s asks you as usual." % LABEL.get(nxt, nxt)
                out.update({"action": "auto", "stage": stage, "calls": calls, "say": say})
                return out
            why = "; ".join("%s: %s" % (x.get("name"), x.get("detail")) for x in r.failed_rows(stage))[:200]
            out.update({"action": "auto", "stage": stage, "calls": [self.c('park --verdict PARKED-NEEDS-DECISION --reason %s' % shlex.quote("%s failed: %s" % (LABEL[stage], why)))],
                        "say": "%s failed; the armed run parks for you." % LABEL[stage]})
            return out
        q = self.ask(stage)
        out.update({"action": "ask", "stage": stage, "ask": q})
        self.add_adhoc(out, stage)
        if r.gate_of(stage):  # the gate to run again after a change the person typed at this question
            out["gate"] = self.c("gate %s" % r.gate_of(stage))
        blocking = r.blocking()
        if blocking:
            out["blocking"] = blocking
            out["blocking_asks"] = blocking_asks(blocking, self.cli)
        return out


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


def check_markers(run):
    rows = read_json(os.path.join(TEMPER, "evidence", "check.json"), [])
    kinds = [("compile", r"compile|build\b|type ?check|tsc|mypy"), ("tests", r"\btests?\b|unittest|pytest|jest"),
             ("coverage", r"coverage"), ("lint", r"lint|ruff|eslint|flake8"), ("security", r"security|secret|audit|semgrep|bandit|scan")]
    out = []
    for name, rx in kinds:
        # A scenario's trace row names its test; it is no run of a check (as in `temper gate check`).
        hits = [r for r in rows if isinstance(r, dict) and not r.get("scenario") and re.search(rx, str(r.get("claim", "")), re.I)]
        if not hits:
            out.append({"name": name, "state": "none", "detail": "", "lines": []})
            continue
        last = hits[-1]
        code = last.get("exit_code")
        state = "pass" if code == 0 else ("fail" if isinstance(code, int) else "info")
        if name == "coverage" and last.get("value") is not None:
            state = "pass" if code in (0, None) else state
        lines = [str(r.get("claim", ""))[:200] for r in hits if isinstance(r.get("exit_code"), int) and r.get("exit_code") != 0][-5:]
        out.append({"name": name, "state": state, "detail": str(last.get("claim", ""))[:200],
                    "value": last.get("value"), "lines": lines})
    return out


def criteria(run):
    if not run.spec or not os.path.isfile(os.path.join(run.spec, "intent.md")):
        return []
    try:
        import acceptance
        report = acceptance.status_report(os.path.join(run.spec, "intent.md"), os.path.join(TEMPER, "evidence"))
    except Exception:
        return []
    return report.get("criteria", [])


# 9.8.0: a failed row that only waits for the person's answer: the Intent's open Blocking questions, the Plan's Context
# check and the fresh review the person asked for, a criterion only the person can confirm at Check. The stage is waiting
# for the person, not failed, and the mod draws it so: a person read the red Intent before its first question as a fault.
PERSON_ROWS = ("blocking question open", "context map reviewed") + FRESH_ROWS


def manual_ids(run):
    """The ids of the intent's required criteria validated by hand."""
    if not run.spec or not os.path.isfile(os.path.join(run.spec, "intent.md")):
        return set()
    try:
        import acceptance
        lines = open(os.path.join(run.spec, "intent.md"), encoding="utf-8").read().splitlines()
        return {c["id"] for c in acceptance.parse_criteria(acceptance.section_lines(lines, "Success Criteria"))
                if c.get("id") and c.get("vtype") == "manual"}
    except Exception:
        return set()


def waits_on_person(row, stage, manual, records=()):
    """True for a failed row that is no fault of the work: it waits for the person's answer, or for a record the CLI
    writes itself next (Build's criteria with no CLI row yet)."""
    if row.get("name") in PERSON_ROWS:
        return True
    if stage == "build" and records and row.get("name") == "criteria validated":
        return True
    if stage == "check":
        ids = re.findall(r"\b([A-Z]+-\d+) has no supported passing evidence row", str(row.get("detail", "")))
        return bool(ids) and all(i in manual for i in ids)
    return False


def stage_marks(run, nxt):
    out = []
    seq = run.seq()
    here = run.stage
    for s in seq:
        v = run.verdict(s) if s != "rca" else None
        sk = run.skip(s)
        if here not in seq:
            mark = "todo"
        elif seq.index(s) < seq.index(here):
            # An earlier stage shows what it has: a skip, its verdict, or (a stage with no gate, RCA) passed. One with no
            # verdict and no skip did not pass: it shows as not done, never as passed.
            if sk and v != "PASS":
                mark = "skipped"
            elif v in ("PASS", "FAIL"):
                mark = "passed" if v == "PASS" else "failed"
            else:
                mark = "passed" if run.gate_of(s) is None else "todo"
        elif s == here:
            mark = "here"
        else:
            mark = "todo"
        manual = manual_ids(run) if s == "check" else set()
        records = run.missing_records(s) if s == "build" else []
        row = {"id": s, "label": LABEL.get(s, s), "mark": mark, "verdict": v,
               "failed": [dict({"name": x.get("name"), "detail": x.get("detail")}, **({"waits": True} if waits_on_person(x, s, manual, records) else {}))
                          for x in run.failed_rows(s)] if s != "rca" else []}
        if sk:
            row["skipped"] = {"reason": sk.get("reason"), "by": sk.get("by")}
        out.append(row)
    return out


def status_line(run, nxt):
    if not run.active:
        return "No run is active."
    label = LABEL.get(run.stage, run.stage)
    a = nxt.get("action")
    if a == "ask":
        if (nxt.get("ask") or {}).get("context"):
            return "%s: your answer to the Is this the right context for the plan? question is not recorded yet." % label
        return "%s: waiting for your answer to the %s question." % (label, (nxt.get("ask") or {}).get("question", {}).get("header", GATE_HEADER))
    if a == "auto":
        return nxt.get("say") or "%s: the armed run goes on." % label
    if a == "broken":
        return nxt.get("say")
    if run.state.get("parked") and a != "work":
        return "%s: parked for you." % label
    return nxt.get("say") or "%s: Claude is working on it." % label


def build_view(run):
    plan = run.plan or {"groups": [], "tasks": []}
    rg = run.groups.get("groups") or {}
    rt = run.groups.get("tasks") or {}
    ev = read_json(os.path.join(TEMPER, "evidence", "build.json"), [])
    groups = []
    for g in plan.get("groups", []):
        ginfo = rg.get(g["id"]) or {}
        tasks = []
        for n in g.get("tasks", []):
            t = next((x for x in plan.get("tasks", []) if x.get("n") == n), {})
            info = rt.get(str(n)) or {}
            phases = [str(r.get("phase")) for r in ev if isinstance(r, dict) and r.get("task") == n]
            state = tasks_md.display_state(info, ginfo, phases)
            attempts = info.get("attempts") or []
            tasks.append({"n": n, "title": t.get("title", ""), "files": t.get("files", []), "state": state,
                          "model": (attempts[-1].get("model") if attempts and isinstance(attempts[-1], dict) else None) or info.get("model"),
                          "attempts": len(attempts)})
        groups.append({"id": g["id"], "title": g.get("title", ""), "status": ginfo.get("status", "pending"),
                       "verdict": (ginfo.get("gate") or {}).get("verdict"), "tasks": tasks})
    return {"groups": groups, "integration": (run.groups.get("integration") or {}).get("verdict")}


def fresh_view(r):
    """The fresh review of the plan for the pane (9.7.6): the reader's paraphrase, the lenses not run, whether tasks.md changed
    after it, and its findings with their state; null when it does not apply to the run."""
    fr = r.fresh()
    if not fr["applies"]:
        return None
    return {"paraphrase": fr["paraphrase"], "missing": fr["missing"], "stale": fr["stale"],
            "findings": [{"id": f["id"], "severity": f["severity"], "lens": f["lens"], "claim": f["claim"], "state": f["state"],
                          "cite": f.get("cite")} for f in fr["findings"]]}


def plan_view(run):
    plan = run.plan or {"groups": [], "tasks": []}
    approved = run.state.get("approved_files")
    by_group = []
    for g in plan.get("groups", []):
        files = []
        for n in g.get("tasks", []):
            t = next((x for x in plan.get("tasks", []) if x.get("n") == n), {})
            files += [f for f in t.get("files", []) if f not in files]
        by_group.append({"id": g["id"], "title": g.get("title", ""), "files": files})
    return {"approved": isinstance(approved, list), "files": approved if isinstance(approved, list) else (plan_files(run.spec) if run.spec else []),
            "groups": by_group}


def usage(run):
    """The time Claude Code gave for each launch, summed, and by stage and by model (no token count since 9.7.4)."""
    rows = [r for r in run.usage if isinstance(r, dict)]
    num = lambda r, k: r[k] if isinstance(r.get(k), int) and not isinstance(r.get(k), bool) else 0

    def by(key):
        out = {}
        for r in rows:
            b = out.setdefault(r.get(key) or "unknown", {"ms": 0, "runs": 0})
            b["runs"] += 1
            b["ms"] += num(r, "ms")
            # a stage names the models its launches asked for
            if key == "stage" and r.get("model") and r.get("model") not in b.setdefault("models", []):
                b["models"].append(r.get("model"))
        return out
    return {"ms": sum(num(r, "ms") for r in rows), "by_stage": by("stage"), "by_model": by("model")}


def loops(run):
    """The run's steps back, each with its live budget (the one can_loop decides with, not the max_iterations stored at
    its first step) and the time of its latest step (the time every reader orders loops by)."""
    out = []
    for l in run.active_loops():
        frm, to = l.get("from_stage"), l.get("to_stage")
        out.append({"from": frm, "to": to, "reason": l.get("reason"),
                    "iteration": l.get("iteration"), "max": run.loop_budget(frm, to), "at": loop_at(l) or None})
    return out


def view(run, nxt):
    if not run.active:
        return {"version": VERSION, "run": None, "status": "No run is active.", "drift": drift_info()}
    r = run
    # 9.8.0: the agents the session may launch now (the mod launches no other: its session guard). An agent's `before`
    # call (a Build task's `task start`) changes the next action before the agent is launched: to `wait`, to a `work`
    # that names only the other tasks of the same launch (and a chain shortened by the task now running), or to the
    # question a manual task asks. While the run
    # stays at the same stage, the view keeps naming every agent it named there. That memory is .temper/agents-named.json
    # ({run, stage, agents}, written with the view): a view lost, written again, or written for an error mid-stage does not
    # forget it (the view written last was the memory before, and an older run's view still serves as one). The mod keeps
    # none (it is loaded again between turns).
    agents = [{"type": a.get("type") or "", "model": a.get("model") or "", "prompt": a.get("prompt") or ""}
              for a in (nxt.get("agents") or [])] if nxt.get("action") == "work" else []
    if nxt.get("action") in ("work", "wait", "ask", "auto"):
        for a in named_before(r):
            if isinstance(a, dict) and a not in agents:
                agents.append(a)
        agents = agents[:AGENTS_NAMED_MAX]   # the current action's first
    out = {
        "version": VERSION,
        "run": {"id": r.state.get("run_id"), "step": r.state.get("step"), "slug": r.slug, "title": r.title(),
                "command": r.command, "stage": r.stage, "mode": r.state.get("run_mode") or "interactive",
                "complexity": r.state.get("complexity"), "branch": r.state.get("branch"), "spec": r.spec,
                "feature": r.state.get("feature"), "parked": r.state.get("parked") or None},
        "stages": stage_marks(r, nxt),
        "status": status_line(r, nxt),
        "next": {"action": nxt.get("action"), "stage": nxt.get("stage"), "say": nxt.get("say"),
                 "calls": nxt.get("calls") or [] if nxt.get("action") in ("work", "auto") else [],
                 "steps": nxt.get("steps") or [] if nxt.get("action") == "work" else [],
                 "agents": agents},
        "ask": nxt.get("ask") if nxt.get("action") == "ask" else None,
        "blocking": nxt.get("blocking") or [],
        "blocking_asks": nxt.get("blocking_asks") or [],
        "context_map": nxt.get("context_map"),
        "context_check": nxt.get("context_check"),
        "restart": nxt.get("restart"),
        "drift": drift_info(),
        "guard": {"stage": r.stage, "spec": r.spec, "slug": r.slug, "fix_run": r.command == "fix",
                  "grouped": bool(r.groups), "armed": r.armed(), "autonomy_enabled": True,
                  "plan_files": plan_view(r)["files"], "step": r.state.get("step"), "run_id": r.state.get("run_id"),
                  "prefix": git("rev-parse", "--show-prefix"),
                  "adhoc_stage": (r.state.get("adhoc") or {}).get("stage") if isinstance(r.state.get("adhoc"), dict) else None,
                  "trivial_exit": r.stage == "intent" and int(r.state.get("step") or 0) == 0 and set(r.gates) <= {"intent"} and not r.overrides
                  and not any(os.path.isfile(os.path.join(r.spec, n)) for n in ("intent.md", "plan.md", "tasks.md", "design.md"))},
        "plan": plan_view(r),
        "fresh": fresh_view(r),
        "build": build_view(r),
        "findings": [{k: v for k, v in f.items() if k not in ("answer", "cite", "quote")} for f in r.findings()],   # the view's schema stays as it was
        "checks": [{"name": x.get("name"), "pass": bool(x.get("pass")), "detail": x.get("detail")} for x in r.rows("check")],
        "check_markers": check_markers(r),
        "criteria": criteria(r),
        "loops": loops(r),
        "skips": [{"stage": o.get("stage"), "reason": o.get("reason"), "by": o.get("by")} for o in r.overrides if isinstance(o, dict)],
        "usage": usage(r),
        "time": {"started": r.state.get("started") or r.state.get("created"), "updated": r.state.get("updated")},
    }
    return out


def drift_info():
    return {"header": DRIFT_HEADER, "prefix": DRIFT_PREFIX, "options": DRIFT_OPTIONS}


AGENTS_NAMED = "agents-named.json"
AGENTS_NAMED_MAX = 64   # a grouped Build names one agent per task (a chain counts once); more than a plan holds


def named_before(r):
    """The agents the run named at its current stage, from the record written with the view (or, for a run whose record
    predates it, the view written last)."""
    for name in (AGENTS_NAMED, "view.json"):
        d = read_json(os.path.join(TEMPER, name), {})
        if name == AGENTS_NAMED:
            run_id, stage, agents = d.get("run"), d.get("stage"), d.get("agents")
        else:
            pr = d.get("run") if isinstance(d.get("run"), dict) else {}
            run_id, stage, agents = pr.get("id"), pr.get("stage"), (d.get("next") or {}).get("agents") if isinstance(d.get("next"), dict) else None
        if run_id is not None and run_id == r.state.get("run_id") and stage == r.stage and isinstance(agents, list):
            return agents
    return []


def write_named(doc):
    """Keep the agents a view names at its stage (named_before reads them): only a view that names some writes the record,
    so a view of an error or of a question mid-stage leaves the memory as it was."""
    run, agents = doc.get("run"), (doc.get("next") or {}).get("agents") or []
    if not isinstance(run, dict) or not agents:
        return
    fd, tmp = tempfile.mkstemp(dir=TEMPER, prefix=".named.", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump({"run": run.get("id"), "stage": run.get("stage"), "agents": agents}, f, indent=1)
    os.replace(tmp, os.path.join(TEMPER, AGENTS_NAMED))


def write_view(doc):
    os.makedirs(TEMPER, exist_ok=True)
    try:
        write_named(doc)
    except OSError:
        pass   # the record is a memory for the mod's guard: a launch it forgets is refused, never let through
    fd, tmp = tempfile.mkstemp(dir=TEMPER, prefix=".view.", suffix=".tmp")
    os.chmod(tmp, 0o644)
    with os.fdopen(fd, "w") as f:
        json.dump(doc, f, indent=1)
        f.write("\n")
    os.replace(tmp, os.path.join(TEMPER, "view.json"))


def changed_files(base, started):
    """The files a run changed, for the commit steps' git add: what differs from base_sha, the tracked changes, and the
    untracked files made since the run started (one older than the run, such as a local.env, is not the run's). Names
    are read with -z, so a name with a quote, a space or a letter outside ASCII arrives as it is. Git gives each name
    from the top of the work tree; the project can be a folder below it (a package of a monorepo), where the commit
    steps run, so each name is given from the project folder."""
    def git(*args):
        try:
            return subprocess.run(["git", "-c", "core.quotePath=false"] + list(args), capture_output=True, check=False).stdout
        except OSError:
            return b""
    top = git("rev-parse", "--show-toplevel").decode("utf-8", "replace").strip() or "."
    names = []
    if base:
        names += [n for n in git("diff", "--name-only", "-z", base).decode("utf-8", "replace").split("\0") if n]
    since = None
    try:
        since = datetime.datetime.strptime(started, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()
    except (TypeError, ValueError):
        since = None
    fields = git("status", "--porcelain", "-z", "--untracked-files=all").decode("utf-8", "replace").split("\0")
    i = 0
    while i < len(fields):
        f = fields[i]
        i += 1
        if len(f) < 4:
            continue
        code, name = f[:2], f[3:]
        if "R" in code or "C" in code:
            i += 1  # the old name of a rename or copy follows, in the index or the work tree
        if code == "??" and since is not None:
            try:
                if os.path.getmtime(os.path.join(top, name)) < since:
                    continue
            except OSError:
                continue
        names.append(name)
    # A name that is neither in the work tree nor in the index (a file deleted in a commit since base_sha, as grouped
    # Build commits every task) has nothing to add, and one such name makes the whole `git add` fail.
    gone = [n for n in dict.fromkeys(names) if not os.path.lexists(os.path.join(top, n))]
    indexed = set()
    if gone:
        indexed = {x for x in git("-C", top, "ls-files", "-z", "--", *gone).decode("utf-8", "replace").split("\0") if x}
    out = []
    for n in names:
        if n in gone and n not in indexed:
            continue
        rel = os.path.relpath(os.path.join(top, n))
        if rel.startswith((".temper/", ".claude/")) or rel in out:
            continue
        out.append(rel)
    return sorted(out)


def project_facts(run, ctx):
    """The facts of the project that the run's files do not hold: the branch, HEAD, whether the run's branch exists,
    whether the spec folder is ignored or has something to commit, whether the lessons file is ignored, and the files
    the run changed (at Commit). `temper next` and the view read them the same way, so the question the view holds is
    the one `next` gives. A fact the caller gave in ctx is kept."""
    def ok(*args):
        try:
            return subprocess.run(["git"] + list(args), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20).returncode == 0
        except (OSError, subprocess.SubprocessError):
            return False
    spec = run.spec
    want = run.state.get("branch") or ""
    facts = {
        "branch": lambda: git("branch", "--show-current"),
        "head": lambda: git("rev-parse", "HEAD"),
        "branch_exists": lambda: bool(want) and ok("show-ref", "--verify", "--quiet", "refs/heads/" + want),
        "branch_ahead": lambda: int(git("rev-list", "--count", "HEAD..refs/heads/" + want) or 0) if want and ok("show-ref", "--verify", "--quiet", "refs/heads/" + want) else 0,
        "branch_last": lambda: git("log", "-1", "--format=%h %s", "refs/heads/" + want) if want and ok("show-ref", "--verify", "--quiet", "refs/heads/" + want) else "",
        "spec_ignored": lambda: bool(spec) and ok("check-ignore", "-q", spec + "/intent.md"),
        "lessons_ignored": lambda: ok("check-ignore", "-q", os.path.join(TEMPER, "lessons.md")),
        "spec_dirty": lambda: bool(spec) and bool(git("status", "--porcelain", "--untracked-files=all", "--", spec)),
        "changed": lambda: changed_files(run.state.get("base_sha") or "", run.state.get("started") or "") if run.stage == "commit" else [],
    }
    if not run.active:
        return
    for key, get in facts.items():
        if key not in ctx:
            ctx[key] = get()


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


def main(argv):
    if len(argv) >= 3 and argv[1] == "changed":
        print(json.dumps(changed_files(argv[2], argv[3] if len(argv) > 3 else "")))
        return 0
    if len(argv) >= 4 and argv[1] == "advance-ok":
        why = advance_ok(Run({}), argv[2], argv[3])
        if why:
            print(why)
            return 1
        return 0
    if len(argv) >= 4 and argv[1] == "design-accept":
        n = design_accept(argv[2], argv[3])
        if n:
            print("OK: %d open area(s) of concern recorded in design.md as accepted at the Design question" % n)
        return 0
    if len(argv) >= 3 and argv[1] == "plan-files":
        print(json.dumps(plan_files(argv[2])))
        return 0
    if len(argv) < 2 or argv[1] not in ("next", "view"):
        print(__doc__, file=sys.stderr)
        return 2
    ctx = {}
    if "--ctx" in argv:
        try:
            ctx = json.loads(argv[argv.index("--ctx") + 1])
        except (ValueError, IndexError):
            print("FAIL: --ctx needs a JSON object", file=sys.stderr)
            return 2
    for flag in ("plugin", "cli", "now", "config_file"):
        f = "--" + flag.replace("_", "-")
        if f in argv and argv.index(f) + 1 < len(argv):
            ctx[flag] = argv[argv.index(f) + 1]
    if argv[1] == "next":
        print(run_next(ctx))
        return 0
    run_view(ctx)
    return 0


def run_next(ctx):
    """The next action as the JSON text `temper next` prints."""
    run = Run(ctx)
    project_facts(run, ctx)
    out = Builder(run).next()
    if ctx.get("setup"):
        out["setup"] = ctx["setup"]
    return json.dumps(out, indent=1)


def run_view(ctx):
    """Write .temper/view.json for the run as it stands."""
    run = Run(ctx)
    project_facts(run, ctx)
    try:
        nxt = Builder(run).next()
    except Exception as e:  # the view still says where the run is; it never stays behind the run
        nxt = {"action": "error", "say": "temper next failed: %s" % e}
    doc = view(run, nxt)
    doc["written"] = ctx.get("now")
    write_view(doc)

if __name__ == "__main__":
    sys.exit(main(sys.argv))
