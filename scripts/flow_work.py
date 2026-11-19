"""flow_work.py: WorkPart of Builder: the agents, the work of a stage, the acceptance tests and Check.

A module of the flow; scripts/flow.py is its facade. Standard library only.
"""

import os
import re
import shlex

import approval
import check_run
import decisions
import doctor
import findings
import run_env

from flow_base import GATE_HEADER, LABEL, TEMPER, goes_on, loop_at, on_model, read_json


class WorkPart:
    # -- the work of a stage -------------------------------------------------------------------
    def agent(self, stage, extra_lines=()):
        r = self.r
        models = r.ctx.get("models") or {}
        lines = ["Follow %s/agents/%s.md exactly." % (self.plugin, stage)]
        if stage in ("plan", "design"):
            # 9.8.0 (round 5): the CLI's map of the code the request reaches, made by the action's own call (temper brief).
            lines.append("Project brief: .temper/brief.md (the CLI's map of the code the request reaches; read it first).")
        # WP13: the planner gets the request too (the run may leave Intent by rule, and nobody restated it)
        if stage in ("intent", "plan") and r.state.get("feature"):
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

    def armed_text(self):
        return ("Approve the %s; the run goes on by itself: a passed check moves on, a failed check gets one repair and then "
                "asks you, the commit asks you, and nothing is pushed." % ("fix" if self.r.command == "fix" else "plan"))

    def rca_approval(self):
        """WP17: the root cause question of a fix run is its approval. Approve and fix (arm) and Ask me at every stage
        each bind the run's mode to rca.md as the card shows it (bind), make the fix branch off main or master only
        (`spec branch --if-protected`) and leave RCA with the digest on the advance; run.default orders them as at the
        plan question (approval). A typed answer is the note the root cause agent runs again with (rca_work)."""
        go = lambda m: [self.bind(m), self.c("spec branch --if-protected"), self.c("state advance rca_complete fix" + self.shown())]
        return self.question(GATE_HEADER, "RCA: the root cause and the proposed fix are on the card. Approve the fix?", stage="rca",
                             qid="rca.approve", options=self.approval(go, "rca") + [self.save()])

    def rca_work(self):
        """WP17: the person typed a change at the root cause question (a note at stage rca): the root cause agent runs
        again with it, with the prompt commands/fix.md and the run driver give it (the bug as typed), before the question
        is asked again. The run state counts the notes taken (rca_notes), as record_pass marks its round. None when every
        note was taken."""
        r = self.r
        notes = r.notes("rca", "input")
        if len(notes) <= int(r.state.get("rca_notes") or 0):
            return None
        model = (r.ctx.get("models") or {}).get("rca", "")
        prompt = "\n".join(["Follow %s/agents/rca.md exactly. Bug: %s." % (self.plugin, r.state.get("feature") or r.slug),
                            "RCA file: %s/rca.md" % r.spec] + ["Person's note: %s" % x["claim"] for x in notes] + [self.plugin_line()])
        a = {"type": "temper:temper-rca", "model": model, "prompt": prompt,
             "after": [self.c("usage add --stage rca --model %s --ms {ms}" % (model or "unknown")), self.c("state set rca_notes %d" % len(notes))]}
        return {"action": "work", "stage": "rca", "calls": [], "agents": [a],
                "say": "RCA: the root cause agent takes up your note%s. %s" % (on_model([a]), goes_on(False))}

    def stop(self, stage, reason):
        """WP11: a recorded stop of a run that goes on by itself: the park call (the stage then asks its own question, and
        the run goes on by itself after the answer). Its say names the stop."""
        what = "%s: %s" % (LABEL.get(stage, stage), " ".join(str(reason).split()))
        return {"action": "auto", "stage": stage, "say": "%s. The run stops here and asks you." % what[:240].rstrip("."),
                "calls": [self.c("park --verdict PARKED-NEEDS-DECISION --reason %s" % shlex.quote(what[:1200]))]}

    def repair(self, stage, reason):
        """WP11 (ADR 0019 decision 3): the one seam of the repair by rule: one counted loop back to Build (or Fix). It stops
        when the plan declares a sensitive path, when the budget already holds a repeat for the stage's check, or when that
        key has no room. WP24 replaces this body by the repair in place."""
        r = self.r
        back = "fix" if r.command == "fix" else "build"
        key = "gate:%s" % (r.gate_of(stage) or stage)
        if r.sensitive():
            return self.stop(stage, "the plan touches a sensitive path (%s), so nothing is repaired by rule: %s" % (
                ", ".join(r.sensitive()[:3]), reason))
        rm = r.room(key)
        if rm["used"] >= 1 or not rm["ok"]:
            return self.stop(stage, "%s after its one repair by rule: %s" % (
                "it failed again" if rm["used"] >= 1 else "the budget has no room", reason))
        return {"action": "auto", "stage": stage, "say": "%s: the rule loops back to %s once (%s)." % (LABEL[stage], LABEL[back], reason[:120]),
                "calls": [self.c("state loop %s %s --reason %s" % (stage, back, shlex.quote(("rule: " + reason)[:300])))]}

    def rule_move(self, stage, verdict):
        """WP11 (ADR 0019 decision 3): Review and Check of a run that goes on by itself, by the closed list. Review: an open
        finding at a level of review.block-on takes the repair; a PASS moves on (a finding below the level is carried to
        the commit question); anything else stops. Check: a PASS moves on; a setup fault, a missing measurement, the
        acceptance rows, a criterion only the person can confirm and a failed mutation row alone stop; anything else takes
        the repair. Nothing is skipped or accepted by rule."""
        r = self.r
        rows = r.failed_rows(stage)
        why = "; ".join("%s: %s" % (x.get("name"), " ".join(str(x.get("detail", "")).split())) for x in rows)[:300]
        nxt = r.next_of(stage)
        go = {"action": "auto", "stage": stage, "say": "%s passed; the run goes on to %s." % (LABEL[stage], LABEL.get(nxt, nxt)),
              "calls": [self.c("state advance %s_complete %s" % (stage, nxt))]}
        if stage == "review":
            opens = r.open_findings()
            if opens:
                return self.repair(stage, "repair %d open finding(s): %s" % (len(opens), "; ".join(f["claim"][:100] for f in opens[:3])))
            if verdict == "PASS":
                return go
            return self.stop(stage, why or "the check failed")
        if stage == "check":
            if verdict == "PASS":
                return go
            if any(x.get("name") == approval.ROW for x in rows):
                return self.stop(stage, why)   # WP12: a rule never changes the intent or the approved plan
            if self.setup_fault():
                return self.stop(stage, "SETUP: " + self.setup_fault())
            if self.measurement_gap(rows) or any(str(x.get("name", "")).startswith("acceptance tests written before Build") for x in rows):
                return self.stop(stage, why)
            # M6 of WP08: a criterion only the person can confirm stops, so the next question is the confirmation
            details = " ".join(str(x.get("detail", "")) for x in rows)
            manual = [c["id"] for c in self.criteria("manual") if re.search(r"\b%s has no supported passing evidence row" % re.escape(c["id"]), details)]
            if manual:
                return self.stop(stage, "%s: only you can confirm %s" % (why, ", ".join(manual)))
            if rows and all(x.get("name") == "mutation score >= threshold" for x in rows):
                return self.stop(stage, why)   # stop 21: the score is information only from WP19 on
            return self.repair(stage, why or "the check failed")
        return None

    def setup_offer(self, rows):
        """9.8.5: the option that adds temper doctor --propose's setup block, when the preflight failed on the environment and
        the config has no block; None when that does not hold or nothing is proposed."""
        cfg = self.r.ctx.get("config_file") or os.path.join(".claude", "temper.config")
        if not any(x.get("name") == "preflight" and "environment fault" in str(x.get("detail", "")) for x in rows) or run_env.load_setup(cfg):
            return None
        kept = read_json(os.path.join(TEMPER, "preflight.json"), {})
        if not (isinstance(kept, dict) and kept.get("env_faults")):
            return None   # nothing to check a block against: a block is written only after it fixed a stored failing command
        block, _ = doctor.propose(os.getcwd())
        if block and not doctor.tried_and_failed(os.getcwd(), block):
            parts = doctor.parts(block)
            run, env = parts["run"], ", ".join("%s=%s" % kv for kv in parts["env"].items())
            what = "; ".join(x for x in [("run: " + run_env.mask(run)) if run else "", ("variables: " + env) if env else ""] if x)
            # M13 of WP08: the question shows the block whole, line by line (the run line masked), since the person who
            # reads it is the check: a block that fakes a tool passes the CLI's own
            self.shown_block = " | ".join(("run: " + run_env.mask(l.strip()[len("run: "):])) if l.strip().startswith("run: ")
                                          else l.strip() for l in block if l.strip())
            return self.opt("Add the proposed setup block (Recommended)", what + ". Temper first reruns the failing commands with it, "
                            "and adds it only when they no longer fail on the environment.", move="redo",
                            calls=[self.c("doctor --propose --write"), self.c("plan preflight"), self.c("gate plan")], oid="add-setup")
        return None   # M13 of WP08: the environment agent is no longer offered

    def setup_fault(self):
        """9.8.5 (Q6): the reason Check's latest run hit the environment (a `setup fault:` row after its last suite row), or ""."""
        rows = [x for x in read_json(os.path.join(TEMPER, "evidence", "check.json"), []) if isinstance(x, dict)]
        last = max((i for i, x in enumerate(rows) if str(x.get("claim", "")).startswith("tests: the suite")), default=-1)
        hits = [x for x in rows[last + 1:] if str(x.get("claim", "")).startswith("setup fault: ")]
        return " ".join(hits[-1]["claim"][len("setup fault: "):].split())[:300] if hits else ""

    def fault_lines(self):
        """9.8.5 (S7): what failed at Build when no loop carries feedback: the integrate verdict, then the gate's failed rows."""
        r = self.r
        out = []
        integ = r.groups.get("integration") or {}
        if integ.get("verdict") == "FAIL" and integ.get("reason"):
            out.append("What failed: integrate: %s." % " ".join(str(integ["reason"]).split())[:600])
        rows = ["%s: %s" % (x.get("name"), " ".join(str(x.get("detail", "")).split())[:300]) for x in r.failed_rows("build")[:4]]
        if rows:
            out.append("What failed at the Build gate: %s." % "; ".join(rows))
        return out

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
        if stage == "review":
            extra = extra + self.unread_lines()
        if stage == "plan":
            opens = [f for f in r.fresh()["findings"] if f["state"] not in ("resolved", "accepted")]
            if opens:
                extra = ["Fresh review findings to answer (reference/plan.md, Answering the fresh review): %s." % "; ".join(
                    "#%d [%s] %s" % (f["id"], f["severity"], f["claim"][:200]) for f in opens)]
            unmet = decisions.unmet(decisions.project_of(r.spec), r.spec) if r.spec else ""
            if unmet:   # WP14: an answer other than the choice the plan assumed; the tasks are written under it now
                extra = extra + ["Answers the tasks do not follow yet: %s. Write the tasks under them." % unmet]
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
        if stage == "review" and self.cli_check():
            # 9.8.0: the CLI runs Check's suite, coverage and mutation score while Review reads the change (Review writes
            # no code); Check adopts that run when the tree is unchanged. WP17: in a fix run too (its regression proof).
            a["before"] = (a.get("before") or []) + [self.c("check ahead")]
        if stage == "design":
            # 9.8.0 (round 5): the CLI draws the stage's panel from the files the agent wrote; the agent draws
            # none. WP15: Plan has none: its approval card shows the plan, and the question follows at once.
            a["after"].append(self.c("panel design"))
        a["after"].append(self.c("gate %s" % (r.gate_of(stage) or stage)))
        a["gate"] = a["after"][-1]
        return {"action": "work", "stage": stage, "calls": [self.c("brief")] if stage in ("plan", "design") else [], "agents": [a],
                "say": "%s: the %s agent is working%s. %s" % (LABEL.get(stage, stage), LABEL.get(stage, stage), on_model([a]), goes_on(False))}

    def unread_lines(self):
        """9.8.5 (WP18): Review runs again after a completion row that did not name every changed file: the files it left
        out, for the second launch (scripts/findings.py holds the set the gate compares)."""
        row = findings.completion(os.path.join(TEMPER, "evidence", "review.json"))
        redo = self.r.state.get("redo") or {}
        if not row or redo.get("stage") != "review" or str(row.get("ts") or "") > str(redo.get("ts") or ""):
            return []
        left = findings.unread(row, findings.review_files(self.r.state))
        return ["The last Review did not read: %s. Read each whole, and name it with --read." % findings.names(left, 40)] if left else []

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

    @staticmethod
    def finding_counts(opens):
        """", open findings: 1 high, 2 medium" (every level, most severe first), or "" with none."""
        order = ["critical", "high", "medium", "low", "info"]
        n = {}
        for f in opens:
            n[f["severity"]] = n.get(f["severity"], 0) + 1
        parts = ["%d %s" % (n[k], k) for k in sorted(n, key=lambda k: order.index(k) if k in order else len(order))]
        return ", open findings: " + ", ".join(parts) if parts else ""

    def open_listed(self):
        """F1 of WP08: ", open findings: 1 medium: <the first three claims>" for the questions where the person commits
        (a Medium finding goes on past Review), or "" with none."""
        opens = [f for f in self.r.findings() if f["state"] == "open"]
        if not opens:
            return ""
        more = "; and %d more" % (len(opens) - 3) if len(opens) > 3 else ""
        return "%s: %s%s" % (self.finding_counts(opens), "; ".join(f["claim"][:120] for f in opens[:3]), more)

    def decisions_line(self):
        text = decisions.prompt(self.r.spec) if self.r.spec else ""
        return "\n" + text if text else ""

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
                             move="redo", calls=[self.c("acceptance restore"), redo % shlex.quote("the locked acceptance tests were restored")], oid="restore-tests")]
        if d.get("reopened"):
            return []
        t = self.acc_triage()
        if t.get("verdict") in ("code", "test"):
            rec = t["verdict"] == "test" or not r.can_loop("check", "build")
        else:
            rec = r.loop_count("check", "build") >= 1 or not r.can_loop("check", "build")
        return [self.opt("Correct the acceptance test" + (" (Recommended)" if rec else ""),
                         "The test is wrong, not the code: the writer corrects it against the intent and locks it again; the report shows your reason.",
                         move="redo", calls=[self.c("acceptance reopen --reason '{reason}'")], reason=self.ACC_REASONS, oid="correct-test")]

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
