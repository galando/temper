"""flow_run.py: Run, the reading of a run's state and records; the files a run changed; the facts of the project.

A module of the flow; scripts/flow.py is its facade. Standard library only.
"""

import datetime
import json
import os
import re
import subprocess

import approval
import config_yaml
import fresh_review
import intent_parse
import plan_ops
import tasks_md
from findings import finding_state  # the one state of a finding row, the CLI's own reading (A20)
import budget
import sensitive

from flow_base import GATE_OF, SEQ, TEMPER, git, loop_at, open_concerns, read_json, read_text


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
        """The digest of a parsed plan: the one rule of scripts/approval.py (None when the plan does not parse)."""
        return approval.plan_digest(m)

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

    def drifts(self):
        """WP16: the Scope drift asks of the Build ledger (`temper drift ask`), oldest first, each {path, why,
        change, choice, delivered}: choice the label of the person's answer (a later `drift <path>: <label>` row) or
        ''; delivered true once a `drift decided` row follows that answer (the agent was launched with its line)."""
        rows = [x for x in read_json(os.path.join(TEMPER, "evidence", "build.json"), []) if isinstance(x, dict)]
        out = []
        for i, x in enumerate(rows):
            m = re.match(r"drift ask (\S+)\nWhy: (.*)\nChange: (.*)$", str(x.get("claim") or "")) if x.get("phase") == "drift" else None
            if not m:
                continue
            j, choice = next(((i + 1 + k, a.group(1)) for k, y in enumerate(rows[i + 1:]) for a in [re.match(
                r"drift %s: (Add to plan|Revert|Allow once)\b" % re.escape(m.group(1)), str(y.get("claim") or ""))] if a), (None, ""))
            done = j is not None and any(y.get("phase") == "drift" and y.get("claim") == "drift decided" for y in rows[j + 1:])
            out.append({"path": m.group(1), "why": m.group(2), "change": m.group(3), "choice": choice, "delivered": done})
        return out

    def stale_notes(self, stage, kind):
        """The notes of the stage newer than its recorded verdict; none when the stage has no verdict time."""
        g = self.gates.get(self.gate_of(stage) or "")
        at = str(g.get("ts") or "") if isinstance(g, dict) else ""
        return [x for x in self.notes(stage, kind) if at and str(x.get("ts") or "") > at]

    def round_id(self):
        """What marks one round of a stage: the latest Run Build again and the latest step back."""
        return "%s|%s" % ((self.state.get("redo") or {}).get("ts", ""), (self.latest_loop() or {}).get("at") or (self.latest_loop() or {}).get("started", ""))

    def model(self, name):
        """WP27: the model of an agent as `temper next` resolved it (scripts/cli_ctx.py: the config keys over the table of
        models, by the class of the run), else by the same rule here."""
        m = (self.ctx.get("models") or {}).get(name)
        if m:
            return m
        import cli_ctx
        return cli_ctx.resolve("", self.config, state=self.state).get(name, ("", ""))[0]

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
        """WP14 (ADR 0019 decision 2): a run of /temper:temper has the Design stage only when the person asked for it
        (the option run-design of the approval sets want_design), when design.md exists, or when the run is at Design or
        has a Design verdict (a run saved there by 9.8.4 keeps it). No tier, risk or setting adds it: what Design asked is
        now Blocking questions Plan writes, answered in front of the approval."""
        if self.command != "temper":
            return False
        if self.spec and os.path.isfile(os.path.join(self.spec, "design.md")):
            return True
        if "design" in self.gates or self.stage == "design":
            return True
        # the person's ask: the option run-design
        return str(self.state.get("want_design")).strip().lower() == "true"

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
        # WP19: a row not measured (pass null, state "not measured") is no failure; a row with no pass at all still is.
        # WP20: nor is a row the person skipped at the red base (pass null, state "skipped")
        return [r for r in self.rows(stage) if isinstance(r, dict) and r.get("pass") is not True and r not in self.unmeasured(stage)
                and not (r.get("pass") is None and r.get("state") == "skipped")]

    def unmeasured(self, stage):
        """WP19: the rows of the third state, a measurement that was not taken: they fail nothing and pass nothing."""
        return [r for r in self.rows(stage) if isinstance(r, dict) and r.get("pass") is None and r.get("state") == "not measured"]

    def skip(self, stage):
        # the CLI's rule (_override_covers): a skip covers the verdict the person saw, recorded at or before it (or no
        # verdict); a verdict computed again after it is not covered. A skip or verdict with no time is matched by stage.
        gate = self.gate_of(stage)
        g = self.gates.get(gate or "")
        vts = str(g.get("ts") or "") if isinstance(g, dict) else ""
        hits = [o for o in self.overrides if isinstance(o, dict) and o.get("stage") == gate
                and (not vts or not o.get("ts") or str(o.get("ts")) >= vts)]
        return hits[-1] if hits else None

    def run_default(self):
        """WP11 (ADR 0019 decision 3): run.default, the first option of the approval: to-commit (the default), ask or
        never-unattended. With the key absent and autonomy.enabled false (the shipped config before 9.8.0) it is ask, and
        an unknown value is ask."""
        v = str(config_yaml.get(self.config, "run.default", "") or "").strip().lower()
        if not v:
            return "ask" if self.cfg("autonomy.enabled", "").strip().lower() == "false" else "to-commit"
        return v if v in ("to-commit", "ask", "never-unattended") else "ask"

    def armed(self):
        """WP11: the run goes on by itself here: the person started it at the approval (unattended_from, an earlier stage
        than this one), and no stop is open (`parked`, which a stop sets and the next stage change or the answer ends). A
        run whose approving calls stopped half way is still at its approval, so the question is asked again."""
        start = self.state.get("unattended_from")
        return (self.state.get("run_mode") == "autonomous" and bool(start) and start != self.stage
                and not self.state.get("parked"))

    def sensitive(self):
        """The files the plan declares under a sensitive path (autonomy.park-on-touch, scripts/sensitive.py): nothing there
        is repaired by rule."""
        files = [f for t in (self.plan or {}).get("tasks", []) for f in t.get("files", [])]
        return [f for f, _ in sensitive.declared(files, self.cfg("autonomy.park-on-touch", ""))]

    def active_loops(self):
        return [l for l in (self.loops.get("active_loops", []) if isinstance(self.loops, dict) else []) if isinstance(l, dict)]

    def loop_count(self, frm, to):
        for l in self.active_loops():
            if l.get("from_stage") == frm and l.get("to_stage") == to:
                return int(l.get("iteration") or 0)
        return 0

    def room(self, key):
        """The room of a budget key, as the CLI counts it (scripts/budget.py): used, limit, run_used, run_limit, ok."""
        return budget.room(key, budget.Facts(self))

    def can_loop(self, frm, to):
        """A step back that spends nothing (from a gate that did not fail), or one whose key has room: the row of SPENDS."""
        hit = budget.key_of(["state", "loop", frm, to], budget.Facts(self))
        return hit is None or self.room(hit[0])["ok"]

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

    def context_mode(self):
        """plan.context-check as the plan gate reads it: auto, always or off (an unknown value is auto)."""
        return plan_ops.norm_mode(self.cfg("plan.context-check", "auto"))

    def context_folded(self, cm=None):
        """9.8.5 (WP13): the map is answered at the approval, not by a question of its own (scripts/plan_ops.py folds).
        Not when the approval has no room for it: with no Design to follow and a branch clash, the More list would hold
        the new branch, run-design, the step back, Include what is left out and Save for later, five options and a third
        dialog (WP14: every option within two). The Context check then stays its own question, asked first."""
        cm = cm if cm is not None else self.context()
        return (bool(cm) and plan_ops.folds(cm["rows"], cm["reviewed"], self.context_mode())
                and not (not self.has_design() and self.branch_clashes()))

    def branch_clashes(self):
        """WP12: the run's branch exists from an earlier run, the project is on another branch, and that branch holds
        commits HEAD lacks (the facts of project_facts)."""
        want = self.state.get("branch") or ""
        return bool(want and (self.ctx.get("branch") or "") != want and self.ctx.get("branch_exists")
                    and int(self.ctx.get("branch_ahead") or 0))

    def context_asked(self, cm=None):
        """9.8.5 (WP13): the Context check is its own question: the map is not reviewed, the mode asks about it, and it is
        not folded into the approval."""
        cm = cm if cm is not None else self.context()
        return (bool(cm) and cm["reviewed"] not in ("human", "auto") and plan_ops.asks(cm["rows"], self.context_mode())
                and not self.context_folded(cm))

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
        block = [s.strip().lower() for s in re.split(r"[\x1f,\s\[\]]+", self.cfg("review.block-on", "critical, high")) if s.strip()]
        return [f for f in self.findings() if f["state"] == "open" and f["severity"] in block]

    def spec_ignored(self):
        return bool(self.ctx.get("spec_ignored"))


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
    the run changed (at Check, for the commit card of WP15, and at Commit). `temper next` and the view read them the
    same way, so the question the view holds is the one `next` gives. A fact the caller gave in ctx is kept."""
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
        "changed": lambda: changed_files(run.state.get("base_sha") or "", run.state.get("started") or "") if run.stage in ("check", "commit") else [],
    }
    if not run.active:
        return
    for key, get in facts.items():
        if key not in ctx:
            ctx[key] = get()
