"""flow_work.py: WorkPart of Builder: the agents, the work of a stage, the acceptance tests and Check.

A module of the flow; scripts/flow.py is its facade. Standard library only.
"""

import os
import re
import shlex

import approval
import baseline
import check_run
import decisions
import doctor
import failure
import findings
import repair_ops
import run_env

from flow_base import GATE_HEADER, LABEL, TEMPER, goes_on, loop_at, on_model, read_json, same_failure


class WorkPart:
    # -- the work of a stage -------------------------------------------------------------------
    def agent(self, stage, extra_lines=()):
        r = self.r
        model = r.model(stage)
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
        return {"type": "temper:temper-%s" % stage, "model": model, "prompt": "\n".join(lines),
                "after": [self.c("usage add --stage %s --model %s --ms {ms}" % (stage, model or "unknown"))]}

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
        model = r.model("rca")
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

    def rule_move(self, stage, verdict):
        """WP11 (ADR 0019 decision 3): Review and Check of a run that goes on by itself, by the closed list. Review: an open
        finding at a level of review.block-on takes the repair; a PASS moves on (a finding below the level is carried to
        the commit question); anything else stops. Check: a PASS moves on (a coverage not measured fails nothing: the
        commit question lists it, and no rule repairs it); a setup fault, a missing measurement, the acceptance rows and
        a criterion only the person can confirm stop; anything else, a measured coverage drop with it, takes the repair.
        Nothing is skipped or accepted by rule. The planted bug score is no row: it moves nothing (WP19)."""
        r = self.r
        rows = r.failed_rows(stage)
        why = "; ".join("%s: %s" % (x.get("name"), " ".join(str(x.get("detail", "")).split())) for x in rows)[:300]
        nxt = r.next_of(stage)
        go = {"action": "auto", "stage": stage, "say": "%s passed; the run goes on to %s." % (LABEL[stage], LABEL.get(nxt, nxt)),
              "calls": [self.c("state advance %s_complete %s" % (stage, nxt))]}
        if stage == "review":
            opens = r.open_findings()
            if opens:   # WP24: the repair in the stage ran or may not run (repair_step): the person decides
                return self.stop(stage, "%d open finding(s), no repair by rule (%s): %s" % (
                    len(opens), repair_ops.can_start(r, stage) or "its repair ran", "; ".join(f["claim"][:100] for f in opens[:3])))
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
            return self.stop(stage, "%s (%s)" % (why or "the check failed", repair_ops.can_start(r, stage) or "its repair ran"))
        return None

    def setup_offer(self, base=False):
        """The option that adds temper doctor --propose's setup block, when the config has none and one is proposed;
        None else. Its calls write the block as the question shows it (--expect its hash: a proposal that changed since
        is refused), then run the baseline again, which is its check (WP20; WP21: at Check too, which takes the second
        call for its own). `base` (the red base question) shows the block line by line, else on one line."""
        cfg = self.r.ctx.get("config_file") or os.path.join(".claude", "temper.config")
        if run_env.load_setup(cfg):
            return None
        block, _ = doctor.propose(os.getcwd())
        if not block:
            return None   # WP21: no rule proposes a block: the question says what is missing, in the fault's words
        parts = doctor.parts(block)
        run, env = parts["run"], ", ".join("%s=%s" % kv for kv in parts["env"].items())
        what = "; ".join(x for x in [("run: " + run_env.mask(run)) if run else "", ("variables: " + env) if env else ""] if x)
        # M13 of WP08: the question shows the block whole, line by line (the run line masked), since the person who
        # reads it is the check: a block that fakes a tool passes the CLI's own
        shown = [("  run: " + run_env.mask(l[len("  run: "):])) if l.startswith("  run: ") else l for l in block]
        self.shown_block = "\n".join(shown) if base else " | ".join(l.strip() for l in shown if l.strip())
        desc = "%s. Temper writes the block as shown into .claude/temper.config, then checks the environment and runs the suite again." % what
        calls = [self.c("doctor --propose --write --expect %s" % doctor.block_hash(block)), self.c("baseline start --again")]
        return self.opt("Add this setup block and run it again (Recommended)", desc, move="redo", calls=calls, oid="add-setup")

    # -- WP20: the baseline, before any other step of an active run, and the red base question ----------------------
    def base_step(self):
        """The CLI's own `baseline start` when the run has no baseline file (`--env-only` at a door into Review or
        Check); the red base question while the base is red and nobody answered; None else. A run that goes on by
        itself stops first (a recorded stop with its notice); agents in flight have finished when next is asked."""
        r = self.r
        f = os.path.join(TEMPER, "evidence", "baseline.json")
        if not os.path.exists(f):
            door = (r.state.get("enter") or "") in ("review", "check")
            if not door and r.state.get("base_sha"):
                return None   # a run approved before it had a baseline (an earlier version saved it): its code is no base
            return {"action": "auto", "stage": r.stage, "calls": [self.c("baseline start" + (" --env-only" if door else ""))],
                    "say": "The environment is checked%s, before any agent." % (
                        "" if door else ", and the project's suite runs once on the current code")}
        b = read_json(f, {})
        if b.get("result") != "red" or b.get("answer") or b.get("env_only"):
            return None
        if r.armed():
            return self.stop(r.stage, "the base is red: %s" % (b.get("why") or b.get("kind") or "the suite fails on the current code"))
        return {"action": "ask", "stage": r.stage, "ask": self.base_red(b)}

    def plan_command_step(self, after=False):
        """WP21: the plan's commands on the base, after the plan gate passed (and at Build, before any task's work is
        checked): the CLI's own `baseline plan` while one has no result; the question plan.command for the first that
        failed or timed out and that nobody skipped (a recorded stop in a run that goes on by itself: it may never change
        a gate's command, and never plans again); None else. A result still running waits for nobody here."""
        r = self.r
        b = read_json(os.path.join(TEMPER, "evidence", "baseline.json"), {})
        if not isinstance(b.get("plan"), dict) or not r.spec:
            return None   # no baseline of this run started (or a selftest's file of a baseline not run)
        root, cfg = os.getcwd(), r.ctx.get("config_file") or os.path.join(".claude", "temper.config")
        fails = baseline.failed(root, cfg, r.spec, b)
        gs = r.groups.get("groups") or {}

        def unchecked(where):   # a command whose check has not run in Build yet
            return any((w.startswith("G") and not (gs.get(w.split()[0]) or {}).get("gate"))
                       or (w == "Integration" and not r.groups.get("integration")) for w in where.split(", "))
        if after:   # after the approval: only a command whose check has not run in Build yet still asks
            fails = [(c, e) for c, e in fails if unchecked(e["where"])]
        if fails:
            c, e = fails[0]
            if r.armed():
                return self.stop(r.stage, "a command the plan wrote %s on the current code: %s (%s)" % (
                    "timed out" if e.get("result") == "timeout" else "fails", c[:200], e.get("why") or ""))
            return {"action": "ask", "stage": r.stage, "ask": self.base_red(b, (c, e), after)}
        pend = baseline.pending(root, cfg, r.spec, b)
        if after and r.groups.get("groups"):   # WP25: a command a patch changed in Build runs once on the base before its check
            pend = [p for p in pend if unchecked(p[1])]
        if pend:
            return {"action": "auto", "stage": r.stage, "calls": [self.c("baseline plan")],
                    "say": "The plan's Validates and its Integration line run once on the current code."}
        return None

    def base_red(self, b, pc=None, after=False):
        """base.red: one fault, one dialog. The command, the exit, the seconds, the fault or the first fail lines, and
        the exact proposed block when there is one; Add this setup block and run it again (first and recommended,
        when the config has no block and one is proposed), Run it again, Go on anyway (a recorded skip, with a
        reason), Save for later. WP21, the scope plan-command (`pc`, the command and its result; the id plan.command):
        a command the plan wrote failed or timed out on the base. Allow it more time first at a time out (else Run it
        again), Change the command (typed, `plan patch`), Revise the plan (after the approval: Loop back to Plan), Go
        on anyway (a skip with a reason, the override plan-command), Save for later; no setup block and no agent."""
        cmd, e = pc or (b.get("run") or b.get("cmd") or "the suite", b)
        q, more, env = shlex.quote(cmd), e.get("result") == "timeout", [x for x in b.get("env") or [] if isinstance(x, dict)]
        secs = " after %s s" % e["seconds"] if isinstance(e.get("seconds"), (int, float)) else ""
        lines = [str(x) for x in e.get("fail_lines") or []][:3]
        printed = "It printed: %s." % " | ".join(lines) if lines else "It printed no line that names a failing test."
        change = back = add = None
        if pc:
            what = "The plan's command %s (%s) %s on the current code, before any task changed it: exit %s%s. %s" % (
                cmd, e.get("where") or "the plan", "did not end within its limit" if more else "fails", e.get("exit"), secs, printed)
            target = e["where"].split(", ")[0]
            change = self.opt("Change the command", "Type the command to run instead; it runs once on the current code%s." % (
                "" if after else ", and the plan is checked again"), move="redo",
                calls=[self.c("plan patch %s --cmd '{answer}'" % ("integration" if target == "Integration" else target.split()[0])),
                       self.c("baseline plan")] + ([] if after else [self.c("gate plan")]),
                answer=("Command", "What command should %s run? It must pass on the current code." % e.get("where")), oid="change-command")
            why = "%s %s on the current code: %s" % (e.get("where"), cmd[:160], e.get("why") or "")
            back = (self.plan_loop(False, why) if self.r.can_loop("build", "plan") else None) if after else self.revise_opt(
                "The Plan agent writes another command; then the plan is checked again.", why)
        elif env and b.get("kind") != "red-base":
            what = "The environment check found %s before any agent: %s." % (
                "1 fault" if len(env) == 1 else "%d faults" % len(env),
                "; ".join(str(x.get("why") or "%s needs %s; the shell has %s" % (x.get("file"), x.get("need"), x.get("have")))
                          for x in env))
        else:
            what = "The project's suite fails on the current code, before this run changed anything: %s exited %s%s. %s" % (
                cmd, b.get("exit_code", "with an error"), secs, printed)
        if not pc:
            add = self.setup_offer(base=True)
        again = self.opt("Allow it more time" if more else "Run it again", (
            "Its limit doubles (%s s now), and it runs once more on the current code." % e.get("limit")) if more else
            "%s once more on the current code, after you repaired it by hand." % (
                "It runs" if pc else "The environment check and the suite run"), move="redo",
            calls=([self.c("baseline timeout %s %s" % (q, e.get("limit") or 600))] if more else [])
            + [self.c("baseline plan --cmd %s" % q if pc else "baseline start --again")], oid="more-time" if more else "check-again")
        go = self.opt("Go on anyway", "This check of the command is skipped, with your reason recorded (an override named "
                      "plan-command); it runs at its gate in Build as written." if pc else "The base's failures become a recorded "
                      "skip of the suite's row, which the commit shows; one new failing line still fails it.", move="override",
                      calls=[self.c("baseline skip --cmd %s --reason '{reason}'" % q if pc else "baseline accept-red --reason '{reason}'")],
                      reason=["The command needs what only Build adds", "It is known to fail and is fixed elsewhere"] if pc else
                      ["The failure is known and not this change's", "It is fixed in another change"], oid="go-on-anyway")
        save = self.save()
        if add:
            text = "%s The project's own files propose this setup block:\n%s\nAdd it and run the check again?" % (what, self.shown_block)
        elif pc:
            # a time out is no fault of the command's text: more time first; a command fault is the command's to change
            self.set_rec(again if more or e.get("class") == "environment" else change, True)
            text = "%s %s change the command, %s, or skip this check with a reason?" % (what, "Allow it more time," if more else
                   "A Validate must pass on the code as it is: run it again after a repair,", "loop back to Plan" if after else "revise the plan")
        else:
            # a fault of the environment is repaired first; a suite red before the change is most often a known
            # failure, which the person may pass as a recorded skip (one new failing line still fails the row)
            self.set_rec(again if b.get("kind") != "red-base" else go, True)
            text = "%s Repair it and run it again, go on anyway with the failures as a recorded skip, or save the run?" % what
        return self.question(GATE_HEADER, text, [o for o in (add, again, change, back, go, save) if o], self.r.stage,
                             qid="plan.command" if pc else "base.red")

    def check_stage(self):
        """The stage whose checks the run is at: build (Build, Fix) or check."""
        return "build" if self.r.stage in ("build", "fix") else "check"

    def env_records(self, stage=None):
        """WP23: the open failure records of class environment of the stage's gate (scripts/failure.py) that still stand: a
        record stands only while its own failure is the latest of its check at that stage. Its row is still on the stage's
        ledger with its key (a step back takes it off), no later record of its check names another failure, and its
        command did not pass later in the ledger (a repair on the same key, which leaves it open)."""
        st = stage or self.check_stage()
        rows = read_json(os.path.join(TEMPER, "evidence", "%s.json" % st), [])
        rows = rows if isinstance(rows, list) else []
        recs = failure.read()

        def same(a, b):
            return (a.get("class"), a.get("kind"), a.get("cmd")) == (b.get("class"), b.get("kind"), b.get("cmd"))

        def stands(x):
            last = [y for y in recs if (y.get("scope"), y.get("check")) == (x.get("scope"), x.get("check"))]
            if last and not same(last[-1], x):
                return False
            if not x.get("row"):
                return True
            m = re.match(r"^%s#(\d+)$" % st, str(x.get("row") or ""))
            i = int(m.group(1)) if m else len(rows)
            r = rows[i] if i < len(rows) and isinstance(rows[i], dict) else {}
            if not r or (r.get("key") or "") != (x.get("key") or ""):
                return False
            return not any(isinstance(y, dict) and y.get("cmd") == r.get("cmd") and y.get("exit_code") == 0 for y in rows[i + 1:])
        return [x for x in failure.open_records(scope="gate:%s" % st) if x.get("class") == "environment" and stands(x)]

    def setup_fault(self, stage=None):
        """9.8.5 (Q6): the reason the latest run of the stage's checks hit the environment (a `setup fault:` row after its last
        suite row), or "". WP23: the stage the run is at (integrate's checks at Build, Check's at Check), and else an open
        record of class environment at a failed suite row of that gate, or of the locked acceptance tests at their failed
        row (an exit 125 with no SETUP marker writes no `setup fault:` row)."""
        st = stage or self.check_stage()
        rows = [x for x in read_json(os.path.join(TEMPER, "evidence", "%s.json" % st), []) if isinstance(x, dict)]
        suite = "Integration suite" if st == "build" else "tests: the suite"
        last = max((i for i, x in enumerate(rows) if str(x.get("claim", "")).startswith(suite)), default=-1)
        hits = [x for x in rows[last + 1:] if str(x.get("claim", "")).startswith("setup fault: ")]
        if hits:
            return " ".join(hits[-1]["claim"][len("setup fault: "):].split())[:300]
        failed = {str(x.get("name") or "") for x in self.r.failed_rows(st)}
        suite = bool(failed & {"integration", "tests pass"})
        acc = any(x.startswith("acceptance tests written before Build") for x in failed)
        env = [x for x in self.env_records(st) if suite or (acc and x.get("check") == "acceptance")]
        return " ".join(str(env[-1].get("why") or "").split())[:300] if env else ""

    def setup_question(self, stage, setup, rest):
        """9.8.5 (Q6), WP23: the environment was not ready (no database, the wrong JDK, a failed setup line) when the checks
        ran, at Build (integrate) or at Check. Nothing in the code is wrong, so no fix agent runs and nothing that mends the
        code is recommended: add the proposed setup block, or the person repairs it and the checks run again (the kept
        failure runs again, its class being environment); It is the code sends it to the fix pass. M10 of WP08: the same
        fault after the checks ran again recommends Save for later. `rest` follows (the step back, the skip)."""
        r = self.r
        label = LABEL[stage]
        reason = shlex.quote(("SETUP: " + setup)[:300])
        if stage == "check":
            again = [self.c("state redo check --reason %s" % reason)]
            code = [self.c("state loop check build --reason %s" % shlex.quote(("it is the code: " + setup)[:300]))]
        else:
            again = ([self.c("integrate")] if (r.groups.get("integration") or {}).get("verdict") else [self.c("check build-checks")]) + [self.c("gate build")]
            code = [self.c("state redo %s --reason %s" % (stage, shlex.quote(("it is the code: " + setup)[:300])))]
        check = self.set_rec(self.opt("Run it again", "You repaired the environment (temper doctor shows what is missing; the "
                                      "setup: block of .claude/temper.config makes it ready): the checks run again.", move="redo",
                                      calls=again, oid="check-again"), True)
        add = self.setup_offer()   # no block, and one proposed: written as shown, bound by its hash (WP21)
        if add:
            self.set_rec(check, False)
            add["calls"] = add["calls"][:1] + again
        its = self.opt("It is the code", "The failure is the code's, not the environment's: %s." % (
            "Build's fix pass mends it" if stage != "check" else "loop back to Build to mend it"), move="redo" if stage != "check" else "back",
            calls=code, oid="it-is-the-code")
        opts = ([add] if add else []) + [check, its, self.save()]
        text = "%s: SETUP: the environment was not ready (%s), so the result is no verdict on the code. %s run the checks again?" % (
            label, setup, "Add the proposed setup block (%s) and" % self.shown_block if add else "Repair it and")
        redo = r.state.get("redo") if isinstance(r.state.get("redo"), dict) else {}
        env = self.env_records(stage if stage == "check" else "build")   # WP23: the same fault twice in the records
        env = [x for x in env if (x.get("check"), x.get("cmd"), x.get("kind")) == (env[-1].get("check"), env[-1].get("cmd"), env[-1].get("kind"))] if env else []
        if (redo.get("stage") == stage and same_failure(str(redo.get("reason") or ""), ("SETUP: " + setup)[:300])) or len(env) >= 2:
            opts = [self.set_rec(opts[-1], True)] + [self.set_rec(o, False) for o in opts[:-1]]
            # M13 (c): while the block is offered, the question still shows it whole
            text = "%s: SETUP: the environment was not ready (%s). It failed the same way after the checks ran again: repair it%s, or save the run for later?" % (
                label, setup, ", add the proposed setup block (%s)" % self.shown_block if add else "")
        return self.question(GATE_HEADER, text, stage=stage, options=opts + rest, qid="%s.fail" % stage)

    def record_lines(self, recs):
        """WP23: what a failure record keeps, for a prompt: its id, class, why and first failing lines."""
        return ["Failure record %s (%s, %s): %s%s." % (x.get("id"), x.get("class"), x.get("check"), x.get("why"),
                "; failing lines: %s" % " | ".join(x.get("fail_lines")[:5]) if x.get("fail_lines") else "") for x in recs[-3:]]

    def fault_lines(self):
        """9.8.5 (S7): what failed at Build when no loop carries feedback: the integrate verdict, then the gate's failed rows.
        WP23: then the open failure records of the Build gate, with why and the failing lines they keep."""
        r = self.r
        out = []
        integ = r.groups.get("integration") or {}
        if integ.get("verdict") == "FAIL" and integ.get("reason"):
            out.append("What failed: integrate: %s." % " ".join(str(integ["reason"]).split())[:600])
        rows = ["%s: %s" % (x.get("name"), " ".join(str(x.get("detail", "")).split())[:300]) for x in r.failed_rows("build")[:4]]
        if rows:
            out.append("What failed at the Build gate: %s." % "; ".join(rows))
        return out + self.record_lines(failure.open_records(scope="gate:build")) if out else out

    def feedback_lines(self):
        fb = self.r.latest_feedback()
        lines = []
        redo = self.r.state.get("redo") if isinstance(self.r.state.get("redo"), dict) else {}
        if fb and str(self.r.state.get("wrong_test")) == str(redo.get("reason")) == fb:   # WP23 mechanism 9: correct-test
            lines.append("Note from the person: the regression test is wrong: %s. Write the regression test again so it fails on "
                         "the code before the fix and passes with it (a test the shield of regression_test keeps stays as it "
                         "is: add the new one beside it), keep the fix as rca.md says, then continue." % fb)
        elif fb:
            lines.append("Feedback re-entry: %s. Fix this, then continue." % fb)
        found = self.r.latest_findings()
        loop = self.r.latest_loop() or {}
        ids = set(loop.get("records") or [])
        if ids and found:   # WP23: the records the step back named (scripts/loop_step.py)
            lines += self.record_lines([x for x in failure.read() if x.get("id") in ids])
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
                             "say which and why in your panel; the person decides at the question of the stage." % self.r.spec)
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
        model = r.model("plan-review")
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
                 "after": [self.c("usage add --stage plan --model %s --ms {ms}" % (model or "unknown")), self.c("baseline plan"),
                           self.c("gate plan")]}
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
            rv = self.revise_work()   # WP27: a change to a plan that exists is the narrow revise agent's
            if rv:
                return rv
            opens = [f for f in r.fresh()["findings"] if f["state"] not in ("resolved", "accepted")]
            if opens:   # WP27: each finding whole (it was cut at 200 characters)
                extra = ["Fresh review findings to answer (reference/plan.md, Answering the fresh review): %s." % "; ".join(
                    "#%d [%s] %s" % (f["id"], f["severity"], " ".join(f["claim"].split())) for f in opens)]
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
        # with coverage, each scenario's Test: command, each criterion's command (WP27: a criterion validated by code or a
        # metric) and a fix's regression proof, all recorded as real runs. No agent and no model; the Check agent stays for
        # a stack the CLI cannot read (and for a step back that brings a person's note to it).
        if stage == "check" and not back and self.cli_check():
            gate = self.c("gate %s" % (r.gate_of(stage) or stage))
            return {"action": "work", "stage": stage, "calls": [self.c("check run"), gate], "agents": [], "gate": gate,
                    "say": "Check: the CLI runs the suite, coverage, the scenario tests and the criteria's commands (no agent)."}
        a = self.agent(stage, extra)
        if stage == "review" and self.cli_check():
            # 9.8.0: the CLI works while Review reads the change (Review writes no code). A feature run plants bugs only
            # (WP19, the one place they run, as information beside Review), timed by the store's entry of the tree that
            # integrate left (WP23 mechanism 10). A fix run, which has no integrate, first runs Check's suite and coverage
            # into the reuse store, where Check finds the run by its key (WP22, WP17), then plants the bugs.
            a["before"] = (a.get("before") or []) + [self.c("check ahead")]
        if stage == "design":
            # 9.8.0 (round 5): the CLI draws the stage's panel from the files the agent wrote; the agent draws
            # none. WP15: Plan has none: its approval card shows the plan, and the question follows at once.
            a["after"].append(self.c("panel design"))
        if stage == "plan":
            # WP27: the CLI rates the plan's risk (temper risk); WP21: it runs the plan's Validates and its Integration line
            # once on the current code (in a process of its own), after the planner returned and never in its turn; the
            # plan gate itself runs no command
            a["after"] += [self.c("risk"), self.c("baseline plan")]
        if stage == "fix":
            # WP23: a fix run has no integrate: the suite and the regression proof run when the Fix agent returns, and a
            # red result fails the Build gate before Review is paid for
            a["after"].append(self.c("check build-checks"))
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
        model = r.model("acceptance")
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
                "task's criteria: your code must make them pass at integration. Never edit them (the Build gate fails a change)." % self.r.spec)

    ACC_REASONS = ["The test asks for what the intent does not say", "The test contradicts how the code base works"]

    def acc_failure(self):
        """(detail, digest) when the gate of the stage the run is at (Build, where integrate ran them, or Check) failed on
        the locked acceptance tests and on nothing else, they were not changed after the lock and are not reopened: a test
        or the code is wrong. Else None; also when the environment failed them (WP23: the setup question comes first)."""
        d = self.acceptance()
        rows = self.r.failed_rows(self.check_stage())
        acc = [x for x in rows if str(x.get("name", "")).startswith("acceptance tests written before Build")]
        if not d.get("cmd") or d.get("reopened") or not acc or len(acc) != len(rows) or self.setup_fault():
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
        if not f or self.acc_triage():   # WP23: in every mode, a run that goes on by itself too
            return None
        st = self.check_stage()
        model = r.model("acceptance")
        a = {"type": "temper:temper-acceptance", "model": model,
             "prompt": "\n".join(["Follow %s/agents/acceptance.md exactly." % self.plugin, "Spec path: %s." % r.spec,
                                   "Triage: a locked acceptance test fails at %s. Decide whether the code or the test is wrong; change nothing." % LABEL[st],
                                   "The failure: %s" % " ".join(f[0].split())[-900:], self.plugin_line()]),
             "after": [self.c("usage add --stage %s --model %s --ms {ms}" % (st, model or "unknown")),
                       self.c("acceptance triaged --reason %s" % f[1])]}
        return {"action": "work", "stage": r.stage, "calls": [], "agents": [a],
                "say": "%s: a locked acceptance test fails; an agent reads it, the intent and the code to say which looks wrong%s. %s" % (
                    LABEL[st], on_model([a]), goes_on(False))}

    def triage_fix_pass(self):
        """WP23: the triage blames the code: one fix pass as the CLI's own action (`state redo build`, one repeat of
        gate:build); once that repeat is spent the run asks. No rule changes code for a test the triage calls wrong."""
        r = self.r
        f = self.acc_failure()
        t = self.acc_triage()
        if self.check_stage() != "build" or not f or t.get("verdict") != "code":
            return None
        rm = r.room("gate:build")
        if rm["used"] >= 1 or not rm["ok"] or r.sensitive():
            return None
        why = ("acceptance tests written before Build: %s. The triage says the code looks wrong: %s" % (
            " ".join(f[0].split()), t.get("reason", "")))[:300]
        return {"action": "auto" if r.armed() else "work", "stage": r.stage, "agents": [],
                "calls": [self.c("state redo build --reason %s" % shlex.quote(why))],
                "say": "Build: the triage says the code is wrong, not the test; the CLI runs Build's fix pass once (one repeat)."}

    def code_fix_pass(self):
        """WP23: a run that goes on by itself, at a failed Build gate whose open records are all of class code (a run the
        CLI made: a failed suite, a measured coverage drop): one fix pass as the CLI's own action (`state redo build`,
        one repeat of gate:build); once spent, or with a sensitive path in the plan, the run stops. A run the person
        drives asks (row D41)."""
        r = self.r
        recs = failure.open_records(scope="gate:build")
        rows = {x.get("name") for x in r.failed_rows("build")}
        if (not r.armed() or r.stage != "build" or not recs or any(x.get("class") != "code" for x in recs)
                or not rows or not rows <= {"integration", "coverage"}):
            return None
        rm = r.room("gate:build")
        if rm["used"] >= 1 or not rm["ok"] or r.sensitive():
            return None
        why = "; ".join("%s: %s" % (x.get("name"), " ".join(str(x.get("detail", "")).split())) for x in r.failed_rows("build"))
        return {"action": "auto", "stage": "build", "agents": [],
                "calls": [self.c("state redo build --reason %s" % shlex.quote(("rule: " + why)[:300]))],
                "say": "Build: the check failed on the code (%s); the rule runs Build's fix pass once." % why[:120]}

    def acceptance_options(self, rows):
        """9.8.0: the options when the locked acceptance tests failed and nothing else did (WP23: at the Build gate, where
        integrate ran them, or at Check). A builder changed them: put them back as locked (no decision: the person's lock
        holds), then check again. They fail as locked: Build mends the code, or the person says the test is wrong and the
        writer corrects it. After a fix pass or a step back left the same failure, the correction is the recommended way.
        [] when this does not apply."""
        r = self.r
        d = self.acceptance()
        st = self.check_stage()
        acc = [x for x in rows if str(x.get("name", "")).startswith("acceptance tests written before Build")]
        if not d.get("cmd") or not acc or len(acc) != len(rows):
            return []
        detail = str(acc[0].get("detail", ""))
        if detail.startswith("changed after they were locked"):
            again = [self.c("check build-checks"), self.c("gate build")] if st == "build" else [
                self.c("state redo check --reason %s" % shlex.quote("the locked acceptance tests were restored"))]
            return [self.opt("Restore the locked tests (Recommended)", "A builder changed the locked acceptance tests: put them back as they were locked, then check again.",
                             move="redo", calls=[self.c("acceptance restore")] + again, oid="restore-tests")]
        if d.get("reopened"):
            return []
        t = self.acc_triage()
        if st == "build":   # a fix pass (the CLI's for a code verdict, or the person's Run Build again) spent its repeat
            spent = r.room("gate:build")["used"] >= 1 or not r.room("gate:build")["ok"]
            rec = t.get("verdict") == "test" or spent
        elif t.get("verdict") in ("code", "test"):
            rec = t["verdict"] == "test" or not r.can_loop("check", "build")
        else:
            rec = r.loop_count("check", "build") >= 1 or not r.can_loop("check", "build")
        return [self.correct_test(rec)]

    REG_REASONS = ["The test does not fail on the code before the fix", "The test checks another fault than the root cause"]

    def correct_test(self, rec, what="acceptance"):
        """The person's answer that a test is wrong, not the code (correct-test, one label for both). A locked acceptance
        test: the writer corrects it against the intent and locks it again. A fix run's regression test (WP23 mechanism 9,
        after its proof failed twice the same way; the head has no lock on it): the Fix agent gets the person's reason as
        a note (feedback_lines), and Fix is checked again."""
        if what == "regression":
            desc = "The regression test is wrong, not the fix: the Fix agent gets your reason as a note and writes the test again; Fix is checked again."
            calls, reasons = [self.c("state redo fix --reason '{reason}'"), self.c("state set wrong_test '{reason}'")], self.REG_REASONS
        else:
            desc = "The test is wrong, not the code: the writer corrects it against the intent and locks it again; the report shows your reason."
            calls, reasons = [self.c("acceptance reopen --reason '{reason}'")], self.ACC_REASONS
        return self.opt("Correct the %s test" % what + (" (Recommended)" if rec else ""), desc, move="redo", calls=calls, reason=reasons,
                        oid="correct-test")

    def acceptance_fix_work(self):
        """The person reopened the locked acceptance tests at the question of the stage (Build or Check): the writer
        corrects the test the failure names, against the intent, and locks it again; the checks run again (at Build
        `integrate` and the Build gate). At most check_run.ACC_MAX_CORRECTIONS launches for one reopen (its `before` call
        counts them): then the question is the person's again."""
        r = self.r
        d = self.acceptance()
        st = self.check_stage()
        if not isinstance(d.get("reopened"), dict) or r.stage not in ("build", "check"):
            return None
        if int(d["reopened"].get("launches") or 0) >= check_run.ACC_MAX_CORRECTIONS:
            return None
        model = r.model("acceptance")
        rows = [x for x in r.failed_rows(st) if str(x.get("name", "")).startswith("acceptance tests written before Build")]
        fail = " ".join(str(rows[0].get("detail", "")).split())[-700:] if rows else ""
        a = {"type": "temper:temper-acceptance", "model": model,
             "prompt": "\n".join(["Follow %s/agents/acceptance.md exactly." % self.plugin, "Spec path: %s." % r.spec,
                                   "Correction: the person says a locked test is wrong (%s)." % d["reopened"].get("reason", ""),
                                   "The failure: %s" % (fail or "see the acceptance row of the %s ledger" % LABEL[st]),
                                   "Lock command: %s" % d.get("cmd", ""), self.plugin_line()]),
             "before": [self.c("acceptance start")],
             "after": [self.c("usage add --stage %s --model %s --ms {ms}" % (st, model or "unknown"))] + (
                 [self.c("integrate"), self.c("gate build")] if st == "build" else
                 [self.c("state redo check --reason 'the person corrected a locked acceptance test'")])}
        return {"action": "work", "stage": r.stage, "calls": [], "agents": [a],
                "say": "%s: the acceptance writer corrects the test you said is wrong, then the checks run again%s. %s" % (
                    LABEL[st], on_model([a]), goes_on(False))}

    def criteria(self, *types):
        """The required, open criteria of intent.md whose Validate type is one of types. WP27: `manual` is the list the
        person confirms, so it also takes a criterion validated by code or a metric with no command (acceptance.by_person)."""
        r = self.r
        if not r.spec or not os.path.isfile(os.path.join(r.spec, "intent.md")):
            return []
        import acceptance
        lines = open(os.path.join(r.spec, "intent.md"), encoding="utf-8").read().splitlines()
        return [c for c in acceptance.parse_criteria(acceptance.section_lines(lines, "Success Criteria"))
                if c.get("id") and not c.get("placeholder") and c.get("has_validate")
                and (c.get("vtype") in types or "manual" in types and acceptance.by_person(c))
                and not (c.get("deferred") and c.get("optional"))]

    def cli_check(self):
        """True when the CLI can run Check itself: a configured test command, one it detects for the stack, or else the
        plan's Integration line (WP23 mechanism 2, as check_run.run reads it)."""
        try:
            return bool(check_run.det_for(os.getcwd(), self.r.cfg("check.commands.test", ""), self.r.cfg("check.commands.coverage", ""))
                        or check_run.plan_line(self.r.spec))
        except Exception:
            return False
