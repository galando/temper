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

import config_yaml
import tasks_md

VERSION = 1

TEMPER = ".temper"
GATE_HEADER = "Temper gate"
GROUP_HEADER = "Build group"
RESUME_HEADER = "Temper resume"
DRIFT_HEADER = "Scope drift"
DRIFT_PREFIX = "Outside the plan:"
DRIFT_OPTIONS = ["Add to plan", "Revert", "Allow once"]
SEQ = {"temper": ["intent", "plan", "design", "build", "review", "check", "commit"],
       "fix": ["rca", "fix", "review", "check", "commit"]}
LABEL = {"intent": "Intent", "plan": "Plan", "design": "Design", "build": "Build", "review": "Review",
         "check": "Check", "commit": "Commit", "rca": "RCA", "fix": "Fix"}
# The stage a gate verdict is kept under: a fix run's Fix stage is judged by the build gate.
GATE_OF = {"fix": "build", "rca": None}
# The stages a step back goes to, from a failed stage.
BACK_TO = {"temper": {"plan": "intent", "design": "plan", "build": "plan", "review": "build", "check": "build"},
           "fix": {"review": "fix", "check": "fix"}}
# The moves only the person may make; the mod lets their CLI calls through only for the person's answer.
PERSON_MOVES = {"approve", "arm", "override", "back", "accept", "keep", "commitOverride", "restart"}


# ---- reading the run -----------------------------------------------------------------------

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
        return s

    def open_concerns(self):
        return open_concerns(os.path.join(self.spec, "design.md")) if self.spec else []

    def has_design(self):
        if self.command != "temper":
            return False
        if self.spec and os.path.isfile(os.path.join(self.spec, "design.md")):
            return True
        if "design" in self.gates or self.stage == "design":
            return True
        complexity = (self.state.get("complexity") or "").lower()
        return self.on("phases.design", True) and complexity in ("medium", "complex")

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
        gate = self.gate_of(stage)
        hits = [o for o in self.overrides if isinstance(o, dict) and o.get("stage") == gate]
        return hits[-1] if hits else None

    def armed(self):
        return self.state.get("run_mode") == "autonomous" and self.on("autonomy.enabled")

    def loop_count(self, frm, to):
        for l in self.loops.get("active_loops", []) if isinstance(self.loops, dict) else []:
            if l.get("from_stage") == frm and l.get("to_stage") == to:
                return int(l.get("iteration") or 0)
        return 0

    def loop_budget(self, frm, to):
        if frm == "build" and to == "plan":
            return 1
        mx = self.cfg("loops.max-per-type", "2")
        if frm == "check" and to in ("build", "fix"):
            mx = self.cfg("fix.max-loops", mx)
        try:
            return int(mx)
        except ValueError:
            return 2

    def can_loop(self, frm, to):
        if not self.on("feedback.enabled", True):
            return False
        return self.loop_count(frm, to) < self.loop_budget(frm, to)

    def loop_into(self, stage):
        """The latest active step back to `stage`, or None."""
        best, at = None, ""
        for l in self.loops.get("active_loops", []) if isinstance(self.loops, dict) else []:
            if isinstance(l, dict) and l.get("to_stage") == stage and str(l.get("started", "")) >= at:
                best, at = l, str(l.get("started", ""))
        return best

    def latest_loop(self):
        """The latest step back to Build (or Fix), or None."""
        best, at = None, ""
        for l in self.loops.get("active_loops", []) if isinstance(self.loops, dict) else []:
            if isinstance(l, dict) and l.get("to_stage") in ("build", "fix") and str(l.get("started", "")) >= at:
                best, at = l, str(l.get("started", ""))
        return best

    def latest_feedback(self):
        """The reason of the latest step back to Build (or Fix), or of a "Run Build again"."""
        loop = self.latest_loop() or {}
        best, at = loop.get("reason") or "", str(loop.get("started", ""))
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
        out, active = [], False
        for line in self.intent.splitlines():
            h = re.match(r"^#{1,6}\s+(.*)$", line)
            if h:
                active = bool(re.match(r"open questions", h.group(1).strip(), re.I))
                continue
            m = re.match(r"^\s*[-*]\s+Blocking:\s*(.+)$", line) if active else None
            if m:
                out.append(m.group(1).strip())
        return out

    def findings(self):
        rows = read_json(os.path.join(TEMPER, "evidence", "review.json"), [])
        out = []
        for i, r in enumerate(rows, 1):
            if not isinstance(r, dict) or not r.get("severity") or r.get("claim") == "review completed":
                continue
            claim = str(r.get("claim") or "")
            m = re.match(r"^\s*([\w./@-]+\.\w+):(\d+)", claim)
            state = "accepted" if r.get("accepted_reason") or r.get("accepted") else (
                "resolved" if r.get("resolved") or r.get("fixed_by") or r.get("resolved_by") else "open")
            conf = r.get("confidence")
            out.append({"id": i, "severity": str(r.get("severity")).lower(), "claim": claim,
                        "file": m.group(1) if m else None, "line": int(m.group(2)) if m else None,
                        "state": state, "label": r.get("label"),
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
    def opt(self, label, description, move=None, calls=None, steps=None, do=None, stop=False, reason=None):
        o = {"label": label, "description": description, "move": move, "calls": calls or []}
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
        return self.opt("Save for later", "Stop here. The run is saved; /temper:temper takes it up again.", move="pause", stop=True)

    def skill(self, name, label, what):
        return self.opt(label, what, do="Use the %s skill on this stage's work, then ask this question again." % name)

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
        return ["git add -- %s/" % self.r.spec, 'git commit -m "%s"' % message]

    def to_branch(self):
        """The switch to the run's branch (`feature/{slug}`) when the project is on another one: the first commit of the
        run, the accepted intent, goes there, never onto main."""
        branch = self.r.state.get("branch") or ""
        if not branch or (self.r.ctx.get("branch") or "") == branch:
            return []
        return ["git checkout %s" % shlex.quote(branch) if self.r.ctx.get("branch_exists") else "git checkout -b %s" % shlex.quote(branch)]

    def leave_intent(self):
        """Switch to the run's branch, accept the intent (when there is one, and it is not accepted yet the accept changes
        it), commit, advance."""
        r = self.r
        has = bool(r.intent)
        # The whole value, as `temper intent accept` reads it: only `accepted` or `completed` leaves the file unchanged.
        m = re.search(r"^\*\*Status:\*\*(.*)$", r.intent, re.M)
        accepts = has and not (m and m.group(1).strip().lower() in ("accepted", "completed"))
        return self.to_branch() + ([self.c("intent accept")] if has else []) + \
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
            if passed:
                go = self.leave_plan()
                nl = LABEL.get(r.next_of("plan") or "build")
                text = "Plan: %s. Approve the plan and continue to %s?" % (state_of, nl)
                if r.on("autonomy.enabled"):
                    first = [self.opt("Stage by stage (Recommended)", "Approve the plan; every later stage keeps its own gate.", move="approve", calls=go),
                             self.opt("Autonomous: run the rest unattended", "Approve the plan; Build, Review and Check go on by themselves and park before the commit.",
                                      move="arm", calls=[self.c("state set run_mode autonomous")] + go), html]
                    return self.with_more(GATE_HEADER, text, stage, first, [share, grill, teach, self.save()], "Plan: more options.")
                first = [self.opt("Continue to %s (Recommended)" % nl, "Approve the plan, commit it, and start %s." % nl, move="approve", calls=go), html, share]
                return self.with_more(GATE_HEADER, text, stage, first, [grill, teach, self.save()], "Plan: more options.")
            return self.question(GATE_HEADER, "Plan: the check failed (%s). Fix the plan, or skip the check?" % why, stage=stage,
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
                return self.with_more(GATE_HEADER, text, stage,
                                      [self.opt("Continue to Build (Recommended)", cont, move="advance", calls=go), walk,
                                       self.skill("grill-me", "Grill Me", "Stress test the design.")],
                                      back_opt() + [self.skill("teach-me", "Teach Me", "Walk through the design."), self.save()], "Design: more options.")
            return self.question(GATE_HEADER, "Design: the check failed (%s). Fix the design, or skip the check?" % why, stage=stage,
                                 options=back_opt() + [override_opt(go), self.save()])

        if stage in ("build", "fix"):
            go = [self.c("state advance %s_complete %s" % (stage, nxt))]
            if passed:
                opts = [self.opt("Continue to %s (Recommended)" % LABEL[nxt], "Start %s." % LABEL[nxt], move="advance", calls=go),
                        self.skill("teach-me", "Teach Me", "Walk through the changes.")]
                return self.question(GATE_HEADER, "%s: %s. Continue to %s?" % (label, state_of, LABEL[nxt]), stage=stage,
                                     options=opts + back_opt() + [self.save()])
            again = self.opt("Run %s again (Recommended)" % label, "Mend what the failed rows name, then check %s again." % label,
                             move="redo", calls=[self.c('state redo %s --reason %s' % (stage, shlex.quote(why[:300])))])
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
            text = "Review: the check failed (%s). Loop back to Build?" % why
            q = self.with_more(GATE_HEADER, text, stage, first[:3], first[3:] + [arch, self.save()], "Review: more options.")
            if accept:
                q["accept"] = accept
            return q

        if stage == "check":
            go = [self.c("state advance check_complete commit")]
            if passed:
                # What Check passed with a warning (a lint run, a test gap) is the person's to send back to Build.
                opts = [self.opt("Commit (Recommended)", "Commit the change with its spec files.", move="advance", calls=go)] + back_opt()
                if r.spec and os.path.isfile(os.path.join(r.spec, "config-suggestions.json")):
                    opts.append(self.opt("Review config suggestions", "Accept, reject or defer each suggestion, then come back here.",
                                         do="Show each suggestion in config-suggestions.json: Accept (write it into CLAUDE.md or AGENTS.md), Reject or Defer. Then ask this question again."))
                return self.question(GATE_HEADER, "Check: %s. Commit?" % state_of, stage=stage, options=opts + [self.save()])
            return self.question(GATE_HEADER, "Check: the check failed (%s). Loop back to %s?" % (why, LABEL[back or "build"]), stage=stage,
                                 options=back_opt(rec=True) + [override_opt(go), self.save()])

        return None

    def accept_question(self, opens):
        """The `Accept a finding` question: one option per open finding (the first three), and Cancel."""
        aopts = [self.opt("Accept finding %d" % f["id"], f["claim"][:150], move="accept",
                          calls=[self.c("evidence accept --stage review --id %d --reason '{reason}'" % f["id"]), self.c("gate review")],
                          reason=["It is not a real issue", "I accept the risk"]) for f in opens[:3]]
        return self.question(GATE_HEADER, "Review: which finding do you accept?", stage="review",
                             options=aopts + [self.opt("Cancel", "Back to the Review question.", do="Ask the Review question again.")])

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
        if stage == "intent" and r.state.get("feature"):
            lines.append("Feature: %s." % r.state.get("feature"))
        lines.append("Spec path: %s." % r.spec)
        lines.extend(extra_lines)
        lines.append(self.plugin_line())
        return {"type": "temper:temper-%s" % stage, "model": models.get(stage, ""), "prompt": "\n".join(lines),
                "after": [self.c("usage add --stage %s --model %s --tokens {tokens} --ms {ms}" % (stage, models.get(stage, "") or "unknown"))]}

    def feedback_lines(self):
        fb = self.r.latest_feedback()
        lines = []
        if fb:
            lines.append("Feedback re-entry: %s. Fix this, then continue." % fb)
        found = self.r.latest_findings()
        if found:
            lines.append("What the stage before the loop left open: %s." % "; ".join("%d. %s" % (i + 1, x) for i, x in enumerate(found)))
        # The file of the stage the loop came back from: one an earlier run left (a Check context beside a loop from
        # Review) is not this loop's feedback.
        frm = (self.r.latest_loop() or {}).get("from_stage")
        for name in ("review-context.json", "check-context.json"):
            p = os.path.join(self.r.spec, name)
            if self.r.spec and os.path.isfile(p) and (frm not in ("review", "check") or name.startswith(frm)):
                lines.append("Feedback file: %s." % p)
        return lines

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
        # A step back to this stage (from Design to Plan, from Review to Intent): the agent runs again for the person's
        # reason, and with what the stage it came from left open.
        back = r.loop_into(stage) if stage not in ("build", "fix") else None
        if back:
            extra = extra + ["Loop back from %s: %s. Do this stage again for it, keeping what still holds." % (
                LABEL.get(back.get("from_stage"), back.get("from_stage")), back.get("reason") or "no reason given")]
            if back.get("findings"):
                extra.append("What %s left open: %s." % (LABEL.get(back.get("from_stage"), back.get("from_stage")),
                                                          "; ".join("%d. %s" % (i + 1, x) for i, x in enumerate(back["findings"]))))
        a = self.agent(stage, extra)
        a["after"].append(self.c("gate %s" % (r.gate_of(stage) or stage)))
        return {"action": "work", "stage": stage, "calls": [], "agents": [a],
                "say": "%s runs%s." % (LABEL.get(stage, stage), on_model([a]))}

    def build_work(self):
        """Grouped Build, computed: start groups, hand out ready tasks, gate tasks and groups, integrate."""
        r = self.r
        plan = r.plan or {"groups": [], "tasks": []}
        rg = r.groups.get("groups") or {}
        rt = r.groups.get("tasks") or {}
        integ = (r.groups.get("integration") or {}).get("verdict")
        gid = [g["id"] for g in plan.get("groups", [])]

        def gpass(g):
            return ((rg.get(g) or {}).get("gate") or {}).get("verdict") == "PASS"

        # the fix pass: the groups are integrated, so Build mends what a step back or "Run Build again" names. A door's
        # run whose code an earlier run built (built_before, from the walked Build's check) mends it the same way.
        before = r.state.get("built_before") and not rg
        if (integ and all(gpass(g) for g in gid)) or before:
            a = self.agent("build", self.feedback_lines())
            if integ != "PASS" and not before:
                a["after"].append(self.c("integrate"))
            a["after"].append(self.c("gate build"))
            return {"action": "work", "stage": "build", "calls": [], "agents": [a], "say": "Build mends what was found (the fix pass)%s." % on_model([a])}

        run = []
        if not r.state.get("base_sha") and r.ctx.get("head"):
            run.append(self.c("state set base_sha %s" % r.ctx.get("head")))
        for g in plan.get("groups", []):
            started = bool((rg.get(g["id"]) or {}).get("worktree"))
            # A group that builds on another starts after the person's Continue of it, not on its check alone: a Change
            # there reruns work this group would build on.
            if not started and all(gpass(d) and (rg.get(d) or {}).get("confirmed") for d in g.get("depends", [])):
                run.append(self.c("group start %s" % g["id"]))
        if run:
            return {"action": "work", "stage": "build", "calls": run, "agents": [], "say": "Build starts its groups."}

        try:
            mx = int(r.cfg("build.grouped.max-parallel", "4"))
        except ValueError:
            mx = 4
        sched = tasks_md.schedule(plan, r.groups, mx if mx > 0 else 4, r.ctx.get("task_model") or "haiku",
                                  r.ctx.get("escalation_model") or "sonnet", os.getcwd()) if plan.get("tasks") else []
        ready = [x for x in sched if "task" in x]
        if ready:
            agents = []
            for t in ready:
                agents.append({"type": "temper:temper-build-task", "model": t.get("agent_model") or "haiku",
                               "before": [self.c("task start %d" % t["task"])],
                               "prompt": "Follow %s/agents/build-task.md exactly.\n%s\nTask: %d." % (self.plugin, self.plugin_line(), t["task"]),
                               "after": [self.c("task gate %d --model %s --tokens {tokens} --ms {ms}" % (t["task"], t.get("model")))],
                               "task": t["task"], "group": t.get("group"), "title": t.get("title"), "attempt": t.get("attempt")})
            return {"action": "work", "stage": "build", "calls": [], "agents": agents,
                    "say": "Build hands out %d task%s%s." % (len(agents), "" if len(agents) == 1 else "s", on_model(agents))}

        running = [(int(n), v) for n, v in rt.items() if isinstance(v, dict) and v.get("status") == "running"]
        if running:
            return {"action": "wait", "stage": "build", "tasks": [
                {"task": n, "after": [self.c("task gate %d --model %s --tokens {tokens} --ms {ms}" % (n, v.get("model") or self.r.ctx.get("task_model") or "haiku"))]}
                for n, v in sorted(running)],
                "say": "Tasks are running. When you launched their agents in this conversation, wait for each result, then run its after calls; "
                       "otherwise (a new conversation) run the after calls now."}

        for g in gid:
            st = (rg.get(g) or {}).get("status")
            if st == "parked":
                return self.parked(g)
        for g in plan.get("groups", []):
            gidx = g["id"]
            ginfo = rg.get(gidx) or {}
            tasks = g.get("tasks", [])
            done = tasks and all((rt.get(str(n)) or {}).get("status") == "passed" for n in tasks)
            gate = (ginfo.get("gate") or {}).get("verdict")
            if done and not gate:
                return {"action": "work", "stage": "build", "calls": [self.c("group gate %s" % gidx)], "agents": [], "say": "Group %s is checked." % gidx}
            if gate == "FAIL":
                return self.group_failed(g, ginfo)
            if gate == "PASS" and not ginfo.get("confirmed"):
                if r.armed():
                    return {"action": "auto", "stage": "build", "calls": [self.c("group continue %s" % gidx)], "say": "Group %s passed; the armed run goes on." % gidx}
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

    def group_question(self, g):
        gid = g["id"]
        q = self.question(GROUP_HEADER, "Group %s (%s) passed its check. Continue?" % (gid, g.get("title", "")), stage="build", options=[
            self.opt("Continue (Recommended)", "Go on to the next group, or to the merge.", move="advance", calls=[self.c("group continue %s" % gid)]),
            self.opt("Change", "Give feedback; only the tasks it concerns run again.",
                     do="Record each item the person typed with %s, then run %s for each task it concerns. Then ask for the next step."
                        % (self.c("evidence add --stage build --phase feedback --claim 'feedback #{K}: {text}'"), self.c("group reopen %s --task {N} --feedback {K}" % gid))),
            self.opt("Stop", "Save the run for later.", move="pause", calls=[], stop=True)])
        return q

    def group_failed(self, g, ginfo):
        gid = g["id"]
        why = str((ginfo.get("gate") or {}).get("reason", ""))[:200]
        if self.r.armed():  # nobody is there to answer: an armed run parks, as on every stop
            return {"action": "auto", "stage": "build",
                    "calls": [self.c('park --verdict PARKED-NEEDS-DECISION --reason %s' % shlex.quote("group %s failed its check: %s" % (gid, why)))],
                    "say": "Group %s failed its check; the armed run parks for you." % gid}
        reopen = [self.c("group reopen %s %s" % (gid, " ".join("--task %d" % n for n in g.get("tasks", []))))]
        opts = [self.opt("Run the group's tasks again (Recommended)", "Each task of %s runs again." % gid, move="redo", calls=reopen)]
        if self.r.can_loop("build", "plan"):
            opts.append(self.opt("Loop back to Plan", "The plan cannot be built as written.", move="back",
                                 calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The plan cannot be built"]))
        opts.append(self.save())
        return {"action": "ask", "stage": "build", "ask": self.question(
            GATE_HEADER, "Group %s failed its check (%s). Run its tasks again?" % (gid, (ginfo.get("gate") or {}).get("reason", "")), stage="build", options=opts)}

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
        else:
            opts = [self.opt("Run the task again (Recommended)", "The parked tasks run again, from Haiku.", move="redo",
                             calls=[self.c("group reopen %s %s" % (gid, targs))])]
            if r.can_loop("build", "plan"):
                opts.append(self.opt("Loop back to Plan", "The plan cannot be built as written.", move="back",
                                     calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The plan cannot be built"]))
            opts.append(self.save())
            text = "Group %s is parked (%s). Run the task again?" % (gid, str(g.get("parked_reason", ""))[:200])
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=opts)}

    # -- the end of the run --------------------------------------------------------------------
    # Three actions, in order: the report steps (the intent completed, the report printed for the person), the person's
    # answer to the page question, then the record steps (the ledger archived, the commit, the state cleared). The CLI
    # records the first two in the run's end_report (temper report --end, then --html or --no-html).
    def report_steps(self):
        r = self.r
        steps = []
        if r.command == "temper":
            steps.append(self.c("intent complete"))
            steps.append("When %s/build-context.json records deviations from the plan, write them into plan.md as a ## Deviations section." % r.spec)
        if r.command == "fix":
            steps.append("Append one entry for this fix to .temper/lessons.md (create it with a # Lessons header when it is absent), "
                         "as %s/reference/fix.md section Commit + record shows: the next RCA reads it first." % self.plugin)
        steps.append(self.c("report --end"))
        steps.append("Copy what temper report printed into your reply, as it printed it, in a code block: the person does not "
                     "see the output of a Bash call.")
        return steps

    def page_question(self):
        r = self.r
        return self.question(GATE_HEADER, "Every gate passed. The report is above. Write it as an HTML page too, before the commit?",
                             stage="commit", options=[
            self.opt("Write report.html", "%s/report.html, committed with the spec." % (r.spec or ".temper/specs/{slug}"),
                     calls=[self.c("report --html")]),
            self.opt("Not now", "The commit goes on; the report stays the one in the terminal.", calls=[self.c("report --no-html")])])

    def record_steps(self):
        r = self.r
        steps = [self.c("state archive")]
        files = r.ctx.get("changed") or []
        if not r.spec_ignored() and r.spec:
            files = [r.spec + "/"] + [f for f in files if not f.startswith(r.spec + "/")]
        # A fix run's lesson is committed with it, unless the project keeps .temper out of git (then it stays local).
        lessons = [".temper/lessons.md"] if r.command == "fix" and ".temper/lessons.md" not in files and not r.ctx.get("lessons_ignored") else []
        # Each name one shell quoted word: the step runs as printed, and a file name is never shell code.
        steps.append("git add -- %s" % " ".join(shlex.quote(f) for f in files + lessons) if files
                     else "git add -- (each file the run changed)%s" % "".join(" " + x for x in lessons))
        code = [f for f in files if not (f.startswith(r.spec + "/") or f.startswith(".temper/"))] if r.spec else files
        # The code this commit carries: what is still uncommitted (Build commits each task, each group and the merge).
        if code and git("rev-parse", "--verify", "-q", "HEAD"):
            code = [f for f in code if git("status", "--porcelain", "--", f)]
        if r.command == "fix":
            steps.append("git commit -m 'fix({scope}): {description}' -m 'Root cause: {explanation}' -m 'Regression test: {test name}'")
        elif files and not code:
            # A grouped Build commits the code itself (each task, each group, the merge into this branch): this commit is
            # the run's record, and its message says so.
            steps.append("git commit -m %s" % shlex.quote("docs(%s): record the run: spec, gate ledger and report (the code is in the commits before it)" % r.slug))
        else:
            steps.append("git commit -m '{a conventional commit message for the feature}'")
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
                return {"action": "ask", "stage": "commit", "ask": self.page_question()}
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
    def next(self):
        r = self.r
        if not r.active:
            return {"v": VERSION, "action": "none", "run": None, "say": "No run is active."}
        out = {"v": VERSION, "run": self.run_info(), "restart": self.restart()}
        if r.stage not in r.seq() or (r.stage not in ("intent", "rca") and r.spec and not os.path.isdir(r.spec)):
            out.update({"action": "broken", "say": "The run state does not fit its spec folder (%s at %s)." % (r.spec, r.stage)})
            return out
        stage = r.stage
        if stage == "commit":
            out.update(self.commit())
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
        if verdict is None and not skipped:
            if self.walked(stage):
                out.update({"action": "work", "stage": stage, "calls": [self.c("gate %s" % stage)], "agents": [],
                            "say": "%s ran before this run started; it is checked." % LABEL[stage]})
            elif stage == "build" and r.command == "temper":
                out.update(self.build_work())
            else:
                out.update(self.stage_work(stage))
            return out
        if r.armed() and stage not in ("intent", "plan", "rca"):
            nxt = r.next_of(stage)
            if stage == "design" and r.open_concerns():
                # a person resolves each area of concern at the Design question, before Build: an armed run parks for them
                out.update({"action": "auto", "stage": stage, "calls": [self.c('park --verdict PARKED-NEEDS-DECISION --reason %s' % shlex.quote(
                    "Design has %d open area(s) of concern" % len(r.open_concerns())))],
                            "say": "Design has open areas of concern; the armed run parks for you."})
                return out
            if verdict == "PASS" or skipped:
                out.update({"action": "auto", "stage": stage, "calls": [self.c("state advance %s_complete %s" % (stage, nxt))],
                            "say": "%s passed; the armed run goes on." % LABEL[stage]})
                return out
            back = BACK_TO.get(r.command, {}).get(stage)
            why = "; ".join("%s: %s" % (x.get("name"), x.get("detail")) for x in r.failed_rows(stage))[:200]
            if stage in ("review", "check") and back and r.can_loop(stage, back):
                out.update({"action": "auto", "stage": stage, "calls": [self.c('state loop %s %s --reason %s' % (stage, back, shlex.quote(why)))],
                            "say": "%s failed; the armed run loops back to %s." % (LABEL[stage], LABEL[back])})
                return out
            out.update({"action": "auto", "stage": stage, "calls": [self.c('park --verdict PARKED-NEEDS-DECISION --reason %s' % shlex.quote("%s failed: %s" % (LABEL[stage], why)))],
                        "say": "%s failed; the armed run parks for you." % LABEL[stage]})
            return out
        q = self.ask(stage)
        out.update({"action": "ask", "stage": stage, "ask": q})
        if r.gate_of(stage):  # the gate to run again after a change the person typed at this question
            out["gate"] = self.c("gate %s" % r.gate_of(stage))
        blocking = r.blocking()
        if blocking:
            out["blocking"] = blocking
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

def on_model(agents):
    """ on <model>: the model each agent is launched on, as `next` names it (what Temper asks for, not the model that
    served each turn)."""
    models = sorted({str(a.get("model")) for a in agents if a.get("model")})
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
            mark = "skipped" if sk and v != "PASS" else ("failed" if v == "FAIL" else "passed")
        elif s == here:
            mark = "here"
        else:
            mark = "todo"
        row = {"id": s, "label": LABEL.get(s, s), "mark": mark, "verdict": v,
               "failed": [{"name": x.get("name"), "detail": x.get("detail")} for x in run.failed_rows(s)] if s != "rca" else []}
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
            st = info.get("status", "pending")
            phases = [str(r.get("phase")) for r in ev if isinstance(r, dict) and r.get("task") == n]
            if st == "passed":
                state = "pass"
            elif st == "failed":
                state = "parked" if ginfo.get("status") == "parked" else "fail"
            elif st == "running":
                state = "green" if "green" in phases else ("red" if "red" in phases else "running")
            else:
                state = "waiting"
            attempts = info.get("attempts") or []
            tasks.append({"n": n, "title": t.get("title", ""), "files": t.get("files", []), "state": state,
                          "model": (attempts[-1].get("model") if attempts and isinstance(attempts[-1], dict) else None) or info.get("model"),
                          "attempts": len(attempts)})
        groups.append({"id": g["id"], "title": g.get("title", ""), "status": ginfo.get("status", "pending"),
                       "verdict": (ginfo.get("gate") or {}).get("verdict"), "tasks": tasks})
    return {"groups": groups, "integration": (run.groups.get("integration") or {}).get("verdict")}


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
    """The totals Claude Code gave for each launch (tokens and time), summed, and by stage and by model."""
    rows = [r for r in run.usage if isinstance(r, dict)]
    num = lambda r, k: r[k] if isinstance(r.get(k), int) and not isinstance(r.get(k), bool) else 0

    def by(key):
        out = {}
        for r in rows:
            b = out.setdefault(r.get(key) or "unknown", {"tokens": 0, "ms": 0, "runs": 0})
            b["runs"] += 1
            b["tokens"] += num(r, "tokens")
            b["ms"] += num(r, "ms")
            # a stage names the models its launches asked for
            if key == "stage" and r.get("model") and r.get("model") not in b.setdefault("models", []):
                b["models"].append(r.get("model"))
        return out
    return {"tokens": sum(num(r, "tokens") for r in rows), "ms": sum(num(r, "ms") for r in rows),
            "by_stage": by("stage"), "by_model": by("model")}


def loops(run):
    out = []
    for l in (run.loops.get("active_loops", []) if isinstance(run.loops, dict) else []):
        out.append({"from": l.get("from_stage"), "to": l.get("to_stage"), "reason": l.get("reason"),
                    "iteration": l.get("iteration"), "max": l.get("max_iterations"), "at": l.get("started")})
    return out


def view(run, nxt):
    if not run.active:
        return {"version": VERSION, "run": None, "status": "No run is active.", "drift": drift_info()}
    r = run
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
                 "steps": nxt.get("steps") or [] if nxt.get("action") == "work" else []},
        "ask": nxt.get("ask") if nxt.get("action") == "ask" else None,
        "blocking": nxt.get("blocking") or [],
        "restart": nxt.get("restart"),
        "drift": drift_info(),
        "guard": {"stage": r.stage, "spec": r.spec, "slug": r.slug, "fix_run": r.command == "fix",
                  "grouped": bool(r.groups), "armed": r.armed(), "autonomy_enabled": r.on("autonomy.enabled"),
                  "plan_files": plan_view(r)["files"], "step": r.state.get("step"), "run_id": r.state.get("run_id"),
                  "prefix": git("rev-parse", "--show-prefix"),
                  "trivial_exit": r.stage == "intent" and int(r.state.get("step") or 0) == 0 and set(r.gates) <= {"intent"} and not r.overrides
                  and not any(os.path.isfile(os.path.join(r.spec, n)) for n in ("intent.md", "plan.md", "tasks.md", "design.md"))},
        "plan": plan_view(r),
        "build": build_view(r),
        "findings": r.findings(),
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


def write_view(doc):
    os.makedirs(TEMPER, exist_ok=True)
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
    run = Run(ctx)
    project_facts(run, ctx)
    if argv[1] == "next":
        out = Builder(run).next()
        if ctx.get("setup"):
            out["setup"] = ctx["setup"]
        print(json.dumps(out, indent=1))
        return 0
    try:
        nxt = Builder(run).next()
    except Exception as e:  # the view still says where the run is; it never stays behind the run
        nxt = {"action": "error", "say": "temper next failed: %s" % e}
    doc = view(run, nxt)
    doc["written"] = ctx.get("now")
    write_view(doc)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
