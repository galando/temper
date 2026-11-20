"""flow_ask.py: AskPart of Builder: the options and the questions of each stage.

A module of the flow; scripts/flow.py is its facade. Standard library only.
"""

import os
import re
import shlex
import subprocess

import adhoc_ops
import approval
import decisions
import fresh_review
import repair_ops
import run_env

from flow_base import (BACK_TO, FRESH_ROWS, GATE_HEADER, LABEL, MOVES, NEEDS, OPTION_IDS, OPTION_KINDS, TEMPER, choice_id, goes_on,
                       on_model, question_entry, read_json, same_failure, with_step_kinds)

RECOMMENDED = " (Recommended)"   # the label's suffix: only opt() and set_rec() read or write it


class AskPart:
    def c(self, *words):
        return " ".join([self.cli] + [w for w in words if w])

    def run_info(self):
        r = self.r
        return {"id": r.state.get("run_id"), "step": r.state.get("step"), "slug": r.slug, "stage": r.stage,
                "command": r.command, "mode": r.state.get("run_mode") or "interactive", "armed": r.armed()}

    def plugin_line(self):
        line = ("Plugin folder: %s; wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT "
                "variable, use this folder." % self.plugin)
        return line + self.setup_line()

    def setup_line(self):
        """The project's environment contract (the setup: block of .claude/temper.config), one line, in every agent prompt.
        No block: nothing (the prompt is as before). A credential-named variable is never shown (run_env.load_setup)."""
        s = run_env.load_setup(self.r.ctx.get("config_file") or os.path.join(".claude", "temper.config"))
        if not s:
            return ""
        env = ", ".join("%s=%s" % kv for kv in s["env"].items()) or "(none)"
        return ("\nEnvironment setup (.claude/temper.config setup:): in each new shell, before a build or test command, "
                "run: %s; variables: %s. The CLI applies it to every command it runs." % (run_env.mask(s["run"]) or "(none)", env))

    # -- options ---------------------------------------------------------------------------
    def opt(self, label, description, move=None, calls=None, steps=None, do=None, stop=False, reason=None, answer=None,
            oid=None, kind=None, needs=None):
        """One option. `oid` is its id of OPTION_IDS (required), `kind` set only when a reader acts on it (OPTION_KINDS);
        `recommended` is true when the label ends in the suffix, and set_rec() changes both together. `needs` (WP16) is
        the kind of NEEDS of what the answer needs beyond its calls; a `do` text is only the words for it."""
        if oid not in OPTION_IDS:
            raise ValueError("flow.py: the option id %r is not in OPTION_IDS" % oid)
        if kind is not None and kind not in OPTION_KINDS:
            raise ValueError("flow.py: the option kind %r is not in OPTION_KINDS" % kind)
        if move is not None and move not in MOVES:
            raise ValueError("flow.py: the move %r is not in MOVES" % move)
        needs = needs or (kind if kind in ("more", "accept", "cancel") else None)
        if (needs or do) and needs not in NEEDS:
            raise ValueError("flow.py: the option %r needs %r, which is not in NEEDS" % (oid, needs))
        o = {"label": label, "description": description, "move": move, "calls": calls or [], "id": oid}
        if kind:
            o["kind"] = kind
        if label.endswith(RECOMMENDED):
            o["recommended"] = True
        if answer:  # a question whose typed answer fills {answer} in the calls (the person's name, for a manual task)
            # Two options at least, or the question tool refuses the dialog (9.8.0: a run with a manual task stopped at
            # its name question, which held Cancel alone). The first only says to type; the typed text is the answer.
            o["answer_question"] = {"header": answer[0], "question": answer[1], "multiSelect": False,
                                    "options": [{"label": "Type it below", "description": "Type the answer in the box below; this option alone records nothing."},
                                                {"label": "Cancel", "description": "Back to the question before."}]}
            o["answer_ids"] = {"options": [{"id": "type", "kind": "type"}, {"id": "cancel", "kind": "cancel"}]}
        if steps:
            o["steps"] = steps
            with_step_kinds(o)
        if do:
            o["do"] = do
        if needs:
            o["needs"] = needs
        if stop:
            o["stop"] = True
        if reason:
            o["reason"] = True
            o["reason_question"] = {"header": GATE_HEADER, "question": "%s. What is the reason?" % label, "multiSelect": False}
            self.set_reasons(o, reason)
        return o

    @staticmethod
    def set_reasons(o, reasons):
        """The options of a reason question: each ready reason, then Cancel. The question goes to the dialog as it is, so
        their ids sit beside it, in `reason_ids`, in the same order: `choice-N`, and `cancel` (kind `cancel`: back to the
        question before). Returns the option."""
        o["reason_question"]["options"] = [{"label": x, "description": ""} for x in reasons] + \
            [{"label": "Cancel", "description": "Back to the question before."}]
        o["reason_ids"] = {"options": [{"id": "choice-%d" % (k + 1)} for k in range(len(reasons))] + [{"id": "cancel", "kind": "cancel"}]}
        return o

    @staticmethod
    def set_rec(o, on):
        """Make an option the recommended one, or not: the label's suffix and the `recommended` field change together.
        Returns the option."""
        bare = o["label"][:-len(RECOMMENDED)] if o["label"].endswith(RECOMMENDED) else o["label"]
        o["label"] = bare + (RECOMMENDED if on else "")
        if on:
            o["recommended"] = True
        else:
            o.pop("recommended", None)
        return o

    def bare(self, o):
        """The option's label without the suffix (a question's text names the recommended option in plain words)."""
        return self.set_rec(dict(o), False)["label"]

    def accept_opt(self):
        return self.opt("Accept a finding", "Keep a finding as it is, with your reason.", do="Ask the accept question.", oid="accept-finding", kind="accept")

    def run_anyway(self, calls):
        """WP22: the person's Run it anyway (never recommended, never taken by rule): the check runs whatever the reuse store
        holds (`--fresh`, the first call), its row is marked forced, and it spends one repeat of the budget."""
        return self.opt("Run it anyway", "The check runs once more whatever Temper kept of this tree (a service started by hand, a "
                        "flaky test); it counts as one repeat.", move="redo", calls=[self.c(x) for x in calls], oid="run-anyway")

    def kept_again(self, stage, since="", claim=None):
        """WP22 step 8: the store first. Whether the reuse store already knows that a check of the stage's ledger (its rows
        of `claim` alone, when given) failed again on the same key since `since` (run_env.kept_again): then what ran in
        between changed nothing, whatever the failure's text."""
        try:
            rows = read_json(os.path.join(TEMPER, "evidence", "%s.json" % stage), [])
            return run_env.kept_again(os.getcwd(), [x for x in rows if claim is None or (isinstance(x, dict) and x.get("claim") == claim)], since)
        except Exception:   # a question never fails on the store: the text compare stands
            return False

    def save(self):
        return self.opt("Save for later", "Stop here. The run is saved; /temper:%s takes it up again." % ("fix" if self.r.command == "fix" else "temper"),
                        move="pause", stop=True, oid="save")

    def skill(self, name, label, what):
        o = self.opt(label, what, do="Use the %s skill on this stage's work, then ask this question again." % name, oid=name,
                     needs="talk")
        o["skill"] = name   # 9.8.0: the mod lets the skill's own questions through while it runs (its session guard)
        return o

    def more_opt(self, rest):
        return self.opt("More options", ", ".join(o["label"] for o in rest), do="Ask the more question.", oid="more", kind="more")

    @staticmethod
    def follow_ups(o, qid):
        """The ids of an option's reason and name questions, from the question it is in: `<qid>.reason`, `<qid>.name` (an
        option under More options belongs to the decision of the question above it). They go into `reason_ids` and
        `answer_ids`, beside the questions, which go to the dialog as they are."""
        top = re.sub(r"(\.more)+$", "", qid)
        for key, suffix in (("reason_ids", "reason"), ("answer_ids", "name")):
            if isinstance(o.get(key), dict):
                o[key] = {"id": "%s.%s" % (top, suffix), "kind": suffix, "options": o[key]["options"]}

    def question(self, header, text, options, stage, more=None, extra=None, qid=None):
        """A question of the CLI: `qid` is its id of the registry (required), its kind is the registry's. `question` is the
        dialog's question, exactly as it is asked: the ids go beside it, never inside."""
        entry = question_entry(qid)
        if entry is None:
            raise ValueError("flow.py: the question id %r is not in QUESTIONS" % qid)
        ids = [o.get("id") for o in options]
        if len(set(ids)) != len(ids):
            raise ValueError("flow.py: two options of %s share an id (%s)" % (qid, ", ".join(sorted(str(i) for i in ids))))
        if len(options) > 4 and more is None:
            # 9.8.5: the question dialog takes four options at most (a group question once had five, and the session could
            # only drop one): the first three, then "More options" with the rest, as with_more does.
            rest = options[3:]
            more = self.question(header, text.split("?")[0] + "? More options.", rest, stage, qid=qid + ".more")
            options = options[:3] + [self.more_opt(rest)]
        for o in options:
            self.follow_ups(o, qid)
        q = {"header": header, "question": text, "multiSelect": False,
             "options": [{"label": o["label"], "description": o["description"]} for o in options]}
        out = {"stage": stage, "step": self.r.state.get("step"), "run_id": self.r.state.get("run_id"), "id": qid, "kind": entry["kind"],
               "question": q, "options": options}
        if more:
            out["more"] = more
        if extra:
            out.update(extra)
        return out

    def with_more(self, header, text, stage, first, rest, more_text, qid=None):
        """At most four options a question: the first three, then "More options" with the rest."""
        if len(first) + len(rest) <= 4:
            return self.question(header, text, first + rest, stage, qid=qid)
        more_opt = self.more_opt(rest)
        more = self.question(header, more_text, rest, stage, qid=(qid or "") + ".more")
        return self.question(header, text, first[:3] + [more_opt], stage, more=more, qid=qid)

    def revise_opt(self, description, why):
        """Revise the plan: the Plan agent runs again for the reason (state redo plan)."""
        return self.opt("Revise the plan", description, move="redo", oid="revise-plan",
                        calls=[self.c("state redo plan --reason %s" % shlex.quote(why[:300]))])

    def answers_reason(self):
        """WP14: the reason of the plan's revision for the answers the tasks do not follow yet, or ''."""
        r = self.r
        unmet = decisions.unmet(decisions.project_of(r.spec), r.spec) if r.spec else ""
        return ("the tasks follow your answers: %s" % unmet)[:300] if unmet else ""

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
        run, the approved intent and plan, goes there, never onto main. WP12: a branch an earlier run left is the carried
        switch, so the new spec files go across."""
        branch = self.r.state.get("branch") or ""
        if not branch or (self.r.ctx.get("branch") or "") == branch:
            return []
        clash = self.branch_clash()
        # 9.8.0: git checkout (-b) of the run's branch, by the CLI; WP16: a clash carries the spec files across
        # (spec_ops.py)
        return [self.c("spec branch" + (" --carry %s" % shlex.quote(clash["branch"]) if clash else ""))]

    def shown(self):
        """WP12 (ADR 0019 decision 4): the digests of intent.md and tasks.md as the question shows them, as the arguments
        of the approving advance; the CLI refuses the advance when a file changed since (scripts/approval.py)."""
        out = ""
        for name in ("rca.md",) if self.r.command == "fix" else ("intent.md", "tasks.md"):   # WP17: a fix run binds rca.md
            d = approval.digest(os.path.join(self.r.spec, name)) if self.r.spec else None
            if d:
                out += " --shown %s=%s" % (name, d)
        return out

    def branch_clash(self):
        """The run's branch (`feature/{slug}`) exists from an earlier run, the project is on another branch, and that branch holds
        commits HEAD lacks: a plain switch would leave them behind, or carry the new spec onto old work. None when there is none."""
        r = self.r
        want = r.state.get("branch") or ""
        if not r.branch_clashes():
            return None
        n = 2
        while subprocess.run(["git", "show-ref", "--verify", "--quiet", "refs/heads/%s-%d" % (want, n)], capture_output=True).returncode == 0:
            n += 1
        return {"branch": want, "last": r.ctx.get("branch_last") or "", "new": "%s-%d" % (want, n)}

    def leave_intent(self):
        """Accept the intent (when there is one), advance. WP12 (rule 1): no branch and no commit before the approval."""
        return ([self.c("intent accept")] if self.r.intent else []) + [self.c("state advance intent_complete plan")]

    def bind(self, mode):
        """The first call of an approving option (WP11, WP12): the run's mode, set by the CLI only after it compared the
        digests of what the question showed (`--shown`), so a stale approval writes nothing, no branch and no commit."""
        return self.c("state set run_mode %s%s" % (mode, self.shown()))

    def approval(self, go, stage, lead=""):
        """WP11 (ADR 0019 decision 3): the first options of the approval (the plan question, or the Design question when
        the person asked for Design): approve-run lets the run go on to the commit, ask-every-stage keeps every gate's
        question. run.default orders them; approve-run is left out under never-unattended, for a skipped check, and when
        may_run_alone() says no (WP14). go(mode) is the option's calls, the first of them its bind(mode)."""
        r = self.r
        fix = r.command == "fix"   # WP17: the root cause question of a fix run is its approval
        ask = self.opt("Ask me at every stage", lead + "Approve the %s; every later stage asks you." % ("fix" if fix else "plan"),
                       move="approve", calls=go("interactive"), oid="ask-every-stage")
        if r.run_default() == "never-unattended" or r.skip(stage) is not None or not self.may_run_alone():
            return [self.set_rec(ask, True)]
        run = self.opt("Approve and %s" % ("fix" if fix else "build"), lead + self.armed_text(), move="arm",
                       calls=go("autonomous"), oid="approve-run")
        return [self.set_rec(ask, True), run] if r.run_default() == "ask" else [self.set_rec(run, True), ask]

    def loop_opt(self, stage, back, rec=False):
        """Loop back from the stage to an earlier one, with the person's reason."""
        return self.opt("Loop back to %s%s" % (LABEL[back], " (Recommended)" if rec else ""),
                        "Do %s again; the stages after it are redone too." % LABEL[back], move="back",
                        calls=[self.c("state loop %s %s --reason '{reason}'" % (stage, back))],
                        reason=["The check found a real problem"], oid="back")

    def override_opt(self, stage, then):
        return self.opt("Override and continue", "Skip this check with your reason; the report shows it.", move="override",
                        calls=[self.c("override %s --reason '{reason}'" % (self.r.gate_of(stage) or stage))] + then,
                        reason=["I accept the risk", "It is not a real issue"], oid="override")

    def repair_opt(self, stage, rec):
        """WP24: Repair again, the person's click: one more repair in the stage (`repair start --again`), which the CLI
        refuses outside its conditions (scripts/repair_ops.py can_start)."""
        return self.opt("Repair again" + (" (Recommended)" if rec else ""), "A fresh Build agent repairs it here; the CLI commits "
                        "and rechecks it (one repeat).", move="repair",
                        calls=[self.c("repair start --stage %s --again" % stage)], oid="repair-again")

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
        rep = repair_ops.offer(r, stage) if stage in ("review", "check") else None   # WP24: Repair again, first while it may run

        def back_opt(rec=False):
            # a step back the budget refuses is dropped after (budget_guard), so the question says so
            return [self.loop_opt(stage, back, rec)] if back else []

        def override_opt(then):
            return self.override_opt(stage, then)

        walked = self.walked(stage)
        if walked:
            text = "%s: %s%s (this stage ran before; it is checked, not run again). Go on to %s?" % (
                label, state_of, " (%s)" % why if why and not passed else "", LABEL.get(nxt, nxt))
            go = self.leave(stage)
            if passed:
                return self.question(GATE_HEADER, text, stage=stage, qid="run.walked", options=[
                    self.opt("Continue to %s (Recommended)" % LABEL.get(nxt, nxt), "Go on to %s." % LABEL.get(nxt, nxt),
                             move=self.go_move(stage), calls=go, oid="continue"), self.save()])
            # A stage of an earlier session leaves no evidence in this run (state init starts it empty): its check fails,
            # and the person runs it now (it and every stage after it run) or skips it.
            run = self.opt("Run %s (Recommended)" % label, "%s runs now, and every stage after it." % label, move="redo",
                           calls=[self.c("state redo %s --reason %s" % (stage, shlex.quote("the check of %s failed when the run entered at a later stage%s" % (
                               label, " (%s)" % why[:300] if why else ""))))], oid="redo")
            return self.question(GATE_HEADER, text, stage=stage, options=[run, override_opt(go), self.save()], qid="run.walked")

        if r.command == "fix" and stage == "rca":
            return self.rca_approval()

        if stage == "intent":
            if passed:
                return self.intent_question("Intent: %s. Accept the intent and continue to Plan?" % state_of, stage)
            return self.question(GATE_HEADER, "Intent: the check failed (%s). Correct intent.md, or skip the check?" % why, stage=stage, qid="intent.fail", options=[
                override_opt(self.leave_intent()[0:1] + self.leave_intent()[1:]),
                self.skill("grill-me", "Grill Me", "Stress test the intent first."), self.save()])

        if stage == "plan" and skipped and self.accept_draft():
            # WP13 (red-safety B1): a skip of the plan check never accepts a draft intent: it is accepted here, by its own
            # question, bound to the text shown; then the plan question follows (with no run that goes on by itself)
            return self.intent_question("Plan: skipped by you. The intent is still a draft, and the skip does not accept it. "
                                        "Accept the intent as it stands?", stage)

        if stage == "plan":
            html = self.opt("Open HTML review", "Open the plan as a page to comment on.",
                            do="Follow %s/reference/plan-review.md (Open HTML review), then ask this question again." % self.plugin, oid="html-review",
                            needs="html-review")
            share = self.opt("Share HTML review", "Publish the plan as a private Claude artifact others can comment on.",
                             do="Follow %s/reference/plan-review.md (Share HTML review), then ask this question again." % self.plugin, oid="share-review",
                             needs="html-review")
            grill = self.skill("grill-me", "Grill Me", "Stress test the plan.")
            teach = self.skill("teach-me", "Teach Me", "Walk through the plan.")
            fr = r.fresh()
            # The fresh reader's paraphrase goes in the question: the person compares it with the intent (a wrong one is a finding).
            said = " A reader with no context took it as: %s." % fr["paraphrase"][:300].rstrip(".") if fr["paraphrase"] and not skipped else ""
            if passed:
                # WP13: the approval accepts a draft intent (leave_plan), and answers a folded Context check
                cm = r.context()
                fold = self.fold_calls(cm)
                go = self.leave_plan(fold=fold)
                nl = LABEL.get(r.next_of("plan") or "build")
                accepts = bool(self.accept_draft())
                lead = "Accept the intent. " if accepts else ""
                if fold:
                    said += " %s Your approval says that is right." % self.context_text(cm)[0].rsplit(" Is that right?", 1)[0]
                include = [o for o in [self.include_opt(cm) if fold else None] if o]
                # WP12: the run's branch exists from an earlier run: the approval continues on it, or the run takes a new one
                clash = self.branch_clash()
                said += (" The branch %s exists from an earlier run; its last commit is %s. The approval continues on it." % (
                    clash["branch"], clash["last"])) if clash else ""
                newb = [self.opt("Build on a new branch %s" % clash["new"], "Leave %s as it is; the run takes the new branch, and "
                                 "this question is asked again." % clash["branch"], move="redo", oid="new-branch",
                                 calls=[self.c("state set branch %s" % shlex.quote(clash["new"]))])] if clash else []

                def more(rest):
                    # four options a question: the new branch takes the place of a review or skill option. WP13: the step
                    # back to Intent, and with a folded Context check what it leaves out, go before Save for later
                    out = newb + rest[:-1] + back_opt() + include + rest[-1:]
                    for drop in ("share-review", "teach-me", "grill-me", "html-review"):
                        out = out if len(out) <= 4 else [o for o in out if o.get("id") != drop]
                    return out
                ask_text = "Accept the intent, approve the plan and continue to %s?" if accepts else "Approve the plan and continue to %s?"
                text = "Plan: %s.%s %s" % (state_of, said, ask_text % nl)
                # 9.8.0: the fresh review's open findings below high pass the gate, and are the person's call: the question
                # names them and offers Revise the plan (9.8.4: never recommended; they go to the builder as notes).
                lesser = [f for f in fr["findings"] if f["state"] not in ("resolved", "accepted")] if not skipped else []
                revise = None
                if lesser:
                    shown = "; ".join("#%d [%s] %s" % (f["id"], f["severity"], f["claim"][:120]) for f in lesser[:3])
                    # 9.8.4: only a high finding blocks; a medium or low one goes to the builder as a note (in the task's
                    # prompt), so revising is offered after the ways on, never recommended: a revision is another round.
                    text = "Plan: %s.%s The fresh review left %d finding(s) open: %s%s. They go to the builder as notes. %s" % (
                        state_of, said, len(lesser), shown, "; and %d more" % (len(lesser) - 3) if len(lesser) > 3 else "", ask_text % nl)
                    revise = self.revise_opt("The Plan agent fixes or contests each open finding of the fresh review; then the plan is checked again.",
                                             "fresh review: " + "; ".join(fresh_review.describe(f) for f in lesser))
                # The approval (WP11): here when no Design follows, at the Design question when it does.
                if not r.has_design():
                    # WP14: Design runs only when the person asks for it here. The option takes Teach Me's place in the More
                    # list, so every option stays within two dialogs (a More list of five made a third level, M2 of PR 115).
                    design = self.opt("Run Design first", "Approve the plan; Design runs next, and its question is the last "
                                      "one before Build.", move="approve", oid="run-design",
                                      calls=self.leave_plan("design", fold=fold, then=[self.c("state set want_design true")]))
                    first = self.approval(lambda m: self.leave_plan(fold=fold, mode=m), "plan", lead)
                    # findings below high: revising is offered, after the ways on; else the fresh review's offer takes
                    # Share's place (four options a question), which Open HTML review leads to anyway
                    extra = [revise] if revise is not None else [self.fresh_offer()] if fr["offer"] else [html]
                    rest = [share, design, grill, self.save()] if extra == [html] else [html, design, grill, self.save()]
                    return self.with_more(GATE_HEADER, text, stage, first + extra, more(rest), "Plan: more options.", qid="plan.approve")
                cont = self.opt("Continue to %s (Recommended)" % nl, "%sApprove the plan, commit it, and start %s." % (lead, nl), move="approve", calls=go, oid="ask-every-stage")
                if revise is not None:
                    return self.with_more(GATE_HEADER, text, stage, [cont, revise, html], more([share, grill, teach, self.save()]), "Plan: more options.", qid="plan.approve")
                if fr["offer"]:
                    return self.with_more(GATE_HEADER, text, stage, [cont, self.fresh_offer(), html], more([share, grill, teach, self.save()]), "Plan: more options.", qid="plan.approve")
                return self.with_more(GATE_HEADER, text, stage, [cont, html, share], more([grill, teach, self.save()]), "Plan: more options.", qid="plan.approve")
            fresh_failed = [x for x in rows if x.get("name") in FRESH_ROWS]
            if fr["applies"] and fresh_failed:
                return self.fresh_question(fr, why, said, back_opt, override_opt, grill)
            if any(x.get("name") == "tasks agree with decisions" for x in rows):
                # WP14 (ADR 0019 decision 2): an answer is not the choice the plan assumed, and the tasks have not changed
                # since. Plan writes them under it; or the person says no task names the old rule (a skip with that reason).
                ov = self.set_reasons(override_opt(self.skip_then()), ["The tasks already agree"] + override_reasons)
                return self.question(GATE_HEADER, "Plan: the check failed (%s).%s Revise the plan so the tasks follow your answers?" % (
                    why, said), stage=stage, qid="plan.fail", options=[self.set_rec(self.revise_opt(
                        "The Plan agent writes the tasks under your answers; then the plan is checked again.", self.answers_reason() or why), True),
                        ov] + back_opt() + [self.save()])
            # WP20: the offer of the setup block moved to the red base question (base.red), before any agent; WP21: the
            # plan gate runs no command, so a command the plan wrote is the question plan.command, after the gate passed
            text = "Plan: the check failed (%s).%s Fix the plan, or skip the check?" % (why, said)
            opts = back_opt() + [override_opt(self.skip_then()), grill, self.save()]
            return self.with_more(GATE_HEADER, text, stage, opts[:3], opts[3:], "Plan: more options.", qid="plan.fail")

        if stage == "design":
            walk = self.opt("Walk through step by step", "Review the design section by section.",
                            do="Walk through the sections design.md has (architecture, API contracts, database changes, integration points, decision log), then ask this question again.",
                            oid="walk-through", needs="talk")
            go = self.leave_design()
            opens = r.open_concerns()
            if passed:
                # A concern the design raises can need the plan changed (a missing case, a task): the plan is closed from
                # here on, so the way to change it is a step back to Plan. The open ones are named, since the person is
                # here for them; another call than accepting one as written is typed, and written into design.md.
                text = "Design: %s. Continue to Build?" % state_of
                if opens:
                    text = "Design: %s, with %d open area(s) of concern: %s%s. Continue to Build?" % (
                        state_of, len(opens), "; ".join("%d. %s" % (i + 1, t) for i, t in enumerate(opens[:3])),
                        "; and %d more" % (len(opens) - 3) if len(opens) > 3 else "")
                if r.tasks_changed():
                    # 9.8.0: Design changed the approved tasks; the approval approves them with the design (the CLI records
                    # it), so Build does not refuse to start on a plan that changed after the plan gate.
                    what = r.tasks_change_summary()
                    text = text[:-len(" Continue to Build?")].rstrip(".") + ". Design changed the plan's tasks (tasks.md%s); Continue approves them with the design. Continue to Build?" % (
                        ": " + "; ".join(what[:4]) + ("; and %d more" % (len(what) - 4) if len(what) > 4 else "") if what else "")
                # WP11: the Design question is the approval when the person asked for Design (WP15: its card names a
                # sensitive path of the plan)
                first = self.approval(lambda m: [self.bind(m)] + go, "design",
                                      "Accept the open concerns as written; " if opens else "")
                return self.with_more(GATE_HEADER, text, stage, first + [walk],
                                      [self.skill("grill-me", "Grill Me", "Stress test the design.")] + back_opt() +
                                      [self.skill("teach-me", "Teach Me", "Walk through the design."), self.save()], "Design: more options.", qid="design.pass")
            return self.question(GATE_HEADER, "Design: the check failed (%s). Fix the design, or skip the check?" % why, stage=stage,
                                 options=back_opt() + [override_opt(go), self.save()], qid="design.fail")

        if stage in ("build", "fix"):
            go = [self.c("state advance %s_complete %s" % (stage, nxt))]
            if passed:
                change = self.opt("Change something", ("Say what to change; Build's fix pass makes it, and Build is checked again." if stage == "build"
                                                       else "Say what to change; the Fix agent makes it, and Fix is checked again."), move="redo",
                                  calls=[self.c("state redo %s --reason '{reason}'" % stage)], reason=["Handle a case it missed", "Simplify the change"],
                                  oid="change")
                opts = [self.opt("Continue to %s (Recommended)" % LABEL[nxt], "Start %s." % LABEL[nxt], move="advance", calls=go, oid="continue"), change,
                        self.skill("teach-me", "Teach Me", "Walk through the changes.")]
                return self.question(GATE_HEADER, "%s: %s. Continue to %s?" % (label, state_of, LABEL[nxt]), stage=stage,
                                     options=opts + back_opt() + [self.save()], qid="%s.pass" % stage)
            integ_failed = stage == "build" and (r.groups.get("integration") or {}).get("verdict") == "FAIL"
            setup = self.setup_fault("build")
            if setup:   # WP23: a fault of the environment when Build ended: the setup question, and no fix agent
                return self.setup_question(stage, setup, back_opt(rec=False) + [override_opt(go)] + (
                    [self.run_anyway(["integrate --fresh", "gate build"])] if integ_failed else []))
            # 9.8.4: the same failure after a Run again is not run again by the recommendation: the run converges on the
            # person (an e2e run that followed it relaunched Build's fix pass forty times on one failure)
            redo = r.state.get("redo") if isinstance(r.state.get("redo"), dict) else {}
            # WP22 step 8: the store first (a fix pass by rule names its reason "rule: ...", which no text compare matches)
            same = redo.get("stage") == stage and (self.kept_again(r.gate_of(stage) or stage, str(redo.get("ts") or "")) or
                                                   same_failure(str(redo.get("reason") or ""), why[:300]))
            acc = self.acceptance_options(rows) if stage == "build" else []
            same = same and not acc
            again = self.opt("Run %s again" % label + ("" if same or (acc and acc[0].get("recommended")) else " (Recommended)"),
                             "Mend what the failed rows name, then check %s again." % label,
                             move="redo", calls=[self.c('state redo %s --reason %s' % (stage, shlex.quote(why[:300])))], oid="redo")
            text = "%s: the check failed (%s). %s" % (label, why, "It failed the same way after it ran again. Save the run for later?"
                                                       if same else "Run %s again?" % label)
            opts = ([self.set_rec(self.save(), True), again] + back_opt() + [override_opt(go)] if same else
                    [again] + back_opt() + [override_opt(go), self.save()])
            if same and r.command == "fix" and any(x.get("name") == "regression proof" for x in rows):
                # WP23 mechanism 9: a fix's regression proof failed twice the same way; its test has no lock, so the
                # person may say it is wrong: their reason goes to the Fix agent as a note
                opts.insert(1, self.correct_test(False, "regression"))
                text = ("%s: the check failed (%s). It failed the same way after it ran again: if the regression test is wrong, "
                        "say why and the Fix agent writes it again. Save the run for later?" % (label, why))
            if acc:   # WP23: the locked acceptance tests failed when Build ended, and nothing else did
                t = self.acc_triage()
                said = (" The triage says the %s looks wrong: %s." % (t["verdict"], t.get("reason", ""))) if t.get("verdict") in ("code", "test") else ""
                first = [acc[0], again] if acc[0].get("recommended") else [again, acc[0]]
                text = "%s: the check failed (%s).%s %s?" % (label, why, said, self.bare(first[0]))
                opts = first + back_opt() + [override_opt(go), self.save()]
            if integ_failed:   # WP22
                opts.insert(len(opts) - (0 if same else 1), self.run_anyway(["integrate --fresh", "gate build"]))
            return self.question(GATE_HEADER, text, stage=stage, options=opts, qid="%s.fail" % stage)

        if stage == "review":
            go = [self.c("state advance review_complete check")]
            arch = self.opt("Architecture Depth Review", "Check the changed modules' depth, then come back here.",
                            do="Run the module depth analysis of %s/reference/architecture-depth.md on the changed files, add its [ARCH-DEPTH] findings to the summary, then ask this question again." % self.plugin,
                            oid="depth-review", needs="depth-review")
            opens = r.open_findings()
            if passed:
                # The open findings below the blocking severity (the gate counts only those at or above it).
                opens = [f for f in r.findings() if f["state"] == "open"]
                # Findings below the blocking severity are still open: Build can fix them (a loop back), or the person
                # keeps one. A typed change is no fix here, since Review writes no code.
                grill = self.skill("grill-me", "Grill Me", "Stress test the change.")
                keep = [self.accept_opt()] if opens else []
                # 9.8.5 (Q2, F1 of WP08): an open finding at high or above is repaired by default: Repair again first while its
                # call may start (WP24, mechanism 14), else the loop back to Build is recommended. A Medium one goes on to
                # Check, listed in the Check question where the person commits.
                high = any(f["severity"] in ("critical", "high") for f in opens)
                repair = ([self.repair_opt(stage, rep)] if high and rep is not None else []) + (back_opt(rec=not rep) if high else [])
                if repair:
                    first = repair + [self.opt("Continue to Check", "Start Check with the findings open.", move="advance", calls=go, oid="continue"), arch]
                else:
                    first = [self.opt("Continue to Check" + " (Recommended)", "Start Check.", move="advance", calls=go, oid="continue")] + (back_opt() if opens else []) + [arch]
                rest = [self.skill("teach-me", "Teach Me", "Walk through the change."), self.save()]
                q = self.with_more(GATE_HEADER, "Review: %s%s. %s" % (state_of, self.finding_counts(opens),
                                   ("Repair them in the stage?" if rep is not None else "Loop back to Build to repair them?") if repair else "Continue to Check?"), stage,
                                   first[:3] + ([] if opens else [grill]), first[3:] + keep + ([grill] if opens else []) + rest, "Review: more options.", qid="review.pass")
                if keep:
                    q["accept"] = self.accept_question(opens, qid="review.pass.accept")
                return q
            accept = None
            # A review that recorded no completion row did not finish (its agent failed or stopped): run it again first.
            unfinished = bool(rows) and all(x.get("name") == "review completed" for x in rows)
            first = ([self.repair_opt(stage, rep)] if rep is not None else []) + back_opt(rec=not unfinished and rep is None)
            if unfinished:
                first.insert(0, self.opt("Run Review again (Recommended)", "The review did not finish; it runs again.", move="redo",
                                         calls=[self.c("state redo review --reason 'the review did not finish'")], oid="redo"))
            if opens:
                accept = self.accept_question(opens, qid="review.fail.accept")
                first.append(self.accept_opt())
            # WP24: with Repair again first, the skip stays in the question and keeping a finding goes under More options
            first.insert(len(first) - (1 if opens and rep is not None else 0), override_opt(go))
            text = "Review: the check failed (%s)%s. %s?" % (why, self.finding_counts([f for f in r.findings() if f["state"] == "open"]),
                                                            "Repair it in the stage" if rep else "Loop back to %s" % LABEL.get(back or "build", "Build"))
            q = self.with_more(GATE_HEADER, text, stage, first[:3], first[3:] + [arch, self.save()], "Review: more options.", qid="review.fail")
            if accept:
                q["accept"] = accept
            return q

        if stage == "pipeline":
            return self.pipeline_question(passed, why)

        if stage == "check":
            go = [self.c("state advance check_complete commit")]
            if passed:
                # What Check passed with a warning (a lint run, a test gap) is the person's to send back to Build.
                opts = [self.opt("Commit (Recommended)", "Commit the change with its spec files.", move="advance", calls=go, oid="commit")] + back_opt() + self.pr_options(go)
                if r.spec and os.path.isfile(os.path.join(r.spec, "config-suggestions.json")):
                    opts.append(self.opt("Review config suggestions", "Accept, reject or defer each suggestion, then come back here.",
                                         do="Show each suggestion in config-suggestions.json: Accept (write it into CLAUDE.md or AGENTS.md), Reject or Defer. Then ask this question again.",
                                         oid="config-suggestions", needs="config-suggestions"))
                # F1 of WP08: an open finding goes on to Check, so the question where the person commits lists it
                anyway = self.run_anyway(["check run --fresh", "gate check"])   # WP22
                return self.with_more(GATE_HEADER, "Check: %s%s. Commit?" % (state_of, self.open_listed()), stage, opts[:3], opts[3:] + [anyway, self.save()], "Check: more options.",
                                      qid="check.pass")
            # A run nobody made (no test run recorded: a tool is missing) is not a fault of the code:
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
                return self.question(GATE_HEADER, text, stage=stage, qid="check.fail", options=[
                    self.opt("Confirmed (Recommended)", "I checked it by hand; record my confirmation and check again.", move="confirm", calls=calls, oid="confirm")]
                    + back_opt() + [self.save()])
            anyway = self.run_anyway(["check run --fresh", "gate check"])   # WP22 (trap 8): every failed check offers it
            setup = self.setup_fault("check")
            if setup:
                return self.setup_question(stage, setup, back_opt(rec=False) + [override_opt(go), anyway])
            gap = self.measurement_gap(r.failed_rows("check"))
            # 9.8.4: the same missing measurement after a Run again (the tool is still not there) is not run again by the
            # recommendation: a benchmark run without coverage.py ran Check again 52 times
            redo = r.state.get("redo") if isinstance(r.state.get("redo"), dict) else {}
            same = gap and redo.get("stage") == "check" and (self.kept_again("check", str(redo.get("ts") or "")) or   # WP22: the store first
                                                             same_failure(str(redo.get("reason") or ""), ("the measurement was missing: " + why)[:300]))
            again = [self.opt("Run Check again" + ("" if same else " (Recommended)"), "Install what the failed row names, then Check measures again; Build is not redone.",
                              move="redo", calls=[self.c("state redo check --reason %s" % shlex.quote(("the measurement was missing: " + why)[:300]))], oid="redo")] if gap else []
            if same:
                save = self.set_rec(self.save(), True)
                return self.question(GATE_HEADER, "Check: the check failed (%s). It failed the same way after it ran again: install what it names, or save the run for later?" % why,
                                     stage=stage, options=[save] + again + back_opt(rec=False) + [override_opt(go), anyway], qid="check.fail")
            acc = self.acceptance_options(r.failed_rows("check"))
            if acc:
                first = acc[0]
                rec = first.get("recommended") is True
                opts = [first] + back_opt(rec=False) if rec else back_opt(rec=rep is None) + [first]
                if rep is not None:
                    opts.insert(0 if rep and not rec else 1, self.repair_opt(stage, rep and not rec))
                lead = next((o for o in opts if o.get("recommended")), first)
                t = self.acc_triage()
                said = (" The triage says the %s looks wrong: %s." % (t["verdict"], t.get("reason", ""))) if t.get("verdict") in ("code", "test") else ""
                return self.question(GATE_HEADER, "Check: the check failed (%s).%s %s?" % (why, said, self.bare(lead)), stage=stage,
                                     options=opts + [override_opt(go), anyway, self.save()], qid="check.fail")
            fix = [self.repair_opt(stage, rep)] if rep is not None and not gap else []
            return self.question(GATE_HEADER, "Check: the check failed (%s). %s?" % (why, "Run Check again" if gap else "Repair it in the stage" if fix and rep
                                 else "Loop back to %s" % LABEL[back or "build"]), stage=stage,
                                 options=fix + again + back_opt(rec=not gap and not (fix and rep)) + [override_opt(go), anyway, self.save()], qid="check.fail")

        return None

    @staticmethod
    def measurement_gap(rows):
        """True when every failed row of Check is a run nobody made (no passing test run recorded). WP19: a coverage that
        was not measured is no failed row at all, and a failed coverage row is a measured drop, a defect in the code."""
        if not rows:
            return False
        return all(re.search(r"no passing test-run evidence recorded", str(x.get("detail", ""))) for x in rows)

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
                         move="advance", calls=[self.c("state set pr %s" % kind)] + go, oid="commit-pr" if kind == "one" else "commit-stacked-prs")
                for kind, label, what in kinds]

    # The stages a small change window may open at are adhoc_ops.py's, the one list (the CLI refuses any other).
    ADHOC_STAGES = tuple(adhoc_ops.ADHOC_STAGES)   # the stages a small change window may open at: adhoc_ops.py's own list
    # The gate question offers Make a small change at each of them but Pipeline, whose question opens the window itself:
    # its "Apply the fix and push" opens one for the CI fix (pipeline_question).
    ADHOC_OPTION_STAGES = tuple(s for s in ADHOC_STAGES if s != "pipeline")

    def round_limit(self):
        """The most CI fix rounds: the limit of the budget key pipeline (each round's `state set pipeline_round` spends it).
        The Pipeline question and the Pipeline agent's launch line use the same."""
        return self.r.room("pipeline")["limit"]

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
        end = self.opt("End the run" + (" (Recommended)" if passed or rnd > mx else ""), "Finish here; the run state is cleared.", move="advance", calls=[self.c("state clear")],
                       oid="end-run")
        if passed:
            return self.question(GATE_HEADER, "Pipeline: every job passed. End the run?", stage="pipeline", options=[end, self.save()], qid="pipeline.pass")
        if status not in ("green", "red"):
            return self.question(GATE_HEADER, "Pipeline: the check failed (%s). Run Pipeline again?" % (why or "the Pipeline result is missing or not final"), stage="pipeline", qid="pipeline.fail", options=[
                self.opt("Run Pipeline again (Recommended)", "Read the pull request's checks again.", move="redo",
                         calls=[self.c("state redo pipeline --reason 'the Pipeline result is missing or not final'")], oid="redo"), self.save()])
        if rnd > mx:
            return self.question(GATE_HEADER, "Pipeline: the fix limit is reached (round %d of %d). End the run?" % (rnd, mx), stage="pipeline", options=[end, self.save()],
                                 qid="pipeline.fail")
        fix = ["Apply the changes the fix list in %s/pipeline-context.json names: the step names the file, never the CI text." % r.spec,
               "git add -- {each changed file, by name}",
               "git commit -m 'fix(ci): apply the Pipeline fix (CI fix round %d)'" % rnd]
        fix.append("git push")
        steps = [self.c("adhoc open --stage pipeline --reason 'CI fix round %d'" % rnd)] + fix + [
            self.c("adhoc close"), self.c("state set pipeline_round %d" % (rnd + 1)),
            self.c("state redo pipeline --reason 'CI fix round %d pushed; CI runs again'" % rnd)]
        text = "Pipeline: the check failed (%s). Apply the fix and push?" % (why or "see pipeline-context.json")
        return self.question(GATE_HEADER, text, stage="pipeline", qid="pipeline.fail", options=[
            self.opt("Apply the fix and push (Recommended)",
                     "The fix list in pipeline-context.json is applied, pushed, and the checks are read again.", move="advance", steps=steps, oid="apply-fix",
                     needs="pipeline-fix"),
            self.opt("End the run", "Finish here without the fix; the run state is cleared.", move="advance", calls=[self.c("state clear")], oid="end-run"), self.save()])

    def fresh_offer(self):
        """plan.fresh-review: ask (the default): the person asks for the fresh review at the plan question."""
        return self.opt("Fresh review first", "A reviewer with no context reads the plan before you approve it (worth it for medium and complex work).",
                        move="redo", calls=[self.c("plan fresh request")], oid="fresh-review")   # next launches the reviewer; its gate call follows it

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
                ", ".join(fr["missing"] + fr["lazy"]) or "no usable paraphrase"), move="redo", calls=[self.c("plan fresh again")], oid="fresh-again"))
        if opens and not fr["capped"]:
            first.append(self.opt("Revise the plan%s" % ("" if first else " (Recommended)"),
                                  "The Plan agent fixes or contests each finding; the fresh review runs again on the changed files.",
                                  move="redo", calls=[self.c("state redo plan --reason %s" % shlex.quote(
                                      ("fresh review: " + "; ".join(fresh_review.describe(f) for f in opens))[:300]))], oid="revise-plan"))
        if opens:
            first.append(self.accept_opt())
        limit = " The fresh review ran %d of %d rounds (plan.fresh-review-rounds): accept, skip or step back." % (fr["rounds"], fr["cap"]) if fr["capped"] else ""
        text = "Plan: the check failed (%s).%s%s %s?" % (why, said, limit, "Revise the plan" if opens and not fr["capped"] else
                                                       "Run the fresh review again" if first and not opens else "Accept a finding, or skip the check" if opens else "Fix the plan, or skip the check")
        q = self.with_more(GATE_HEADER, text, "plan", first[:3], first[3:] + back_opt() + [override_opt(self.skip_then()), grill, self.save()],
                           "Plan: more options.", qid="plan.fail")
        if opens:
            q["accept"] = self.accept_question(opens, stage="plan", qid="plan.fail.accept")
        return q

    def accept_question(self, opens, stage="review", qid=None):
        """The `Accept a finding` question: one option per open finding (the first three), and Cancel."""
        label = LABEL.get(stage, stage)
        aopts = []
        # escalated and contested findings first: they wait for the person's call, with what only they know or the author's citation
        rank = lambda f: {"escalated": 0, "contested": 1}.get(f.get("answer") or f.get("state"), 2)
        for k, f in enumerate(sorted(opens, key=rank)[:3]):
            reasons = ["It is not a real issue", "I accept the risk"]
            mark = f.get("answer") or (f.get("state") if f.get("state") in ("contested", "escalated") else None)
            if mark == "contested" and f.get("cite"):
                reasons.insert(0, "Contested with evidence: %s" % f["cite"])     # the author's citation, checked by the CLI
            if mark == "contested" and f.get("quote"):
                reasons.insert(1, "The quoted text answers it: %s" % f["quote"][:80])
            aopts.append(self.opt("Accept finding %d" % f["id"], ("[%s] " % mark if mark else "") + f["claim"][:150],
                                  move="accept", calls=[self.c("evidence accept --stage %s --id %d --reason '{reason}'" % (stage, f["id"])), self.c("gate %s" % stage)],
                                  reason=reasons, oid="choice-%d" % (k + 1)))
        return self.question(GATE_HEADER, "%s: which finding do you accept?" % label, stage=stage, qid=qid,
                             options=aopts + [self.opt("Cancel", "Back to the %s question." % label, do="Ask the %s question again." % label,
                                                       oid="cancel", kind="cancel")])

    def go_move(self, stage):
        return "approve" if stage in ("intent", "plan") else "advance"

    def leave_design(self):
        """Leave Design: the CLI records the open concerns as accepted, then design.md is committed (it was left for the
        last commit before)."""
        r = self.r
        return [self.c("state advance design_complete %s%s" % (r.next_of("design") or "build", self.shown()))] + \
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
