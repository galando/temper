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
import run_env

from flow_base import (BACK_TO, FRESH_ROWS, GATE_HEADER, LABEL, MOVES, OPTION_IDS, OPTION_KINDS, choice_id, goes_on, on_model,
                       question_entry, read_json, same_failure)

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
            oid=None, kind=None):
        """One option. `oid` is its id of OPTION_IDS (required), `kind` set only when a reader acts on it (OPTION_KINDS);
        `recommended` is true when the label ends in the suffix, and set_rec() changes both together."""
        if oid not in OPTION_IDS:
            raise ValueError("flow.py: the option id %r is not in OPTION_IDS" % oid)
        if kind is not None and kind not in OPTION_KINDS:
            raise ValueError("flow.py: the option kind %r is not in OPTION_KINDS" % kind)
        if move is not None and move not in MOVES:
            raise ValueError("flow.py: the move %r is not in MOVES" % move)
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
        if do:
            o["do"] = do
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

    def save(self):
        return self.opt("Save for later", "Stop here. The run is saved; /temper:%s takes it up again." % ("fix" if self.r.command == "fix" else "temper"),
                        move="pause", stop=True, oid="save")

    def skill(self, name, label, what):
        o = self.opt(label, what, do="Use the %s skill on this stage's work, then ask this question again." % name, oid=name)
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
        if clash:
            return [self.carry_switch(clash["branch"])]
        return [self.c("spec branch")]   # 9.8.0: git checkout (-b) of the run's branch, by the CLI

    def shown(self):
        """WP12 (ADR 0019 decision 4): the digests of intent.md and tasks.md as the question shows them, as the arguments
        of the approving advance; the CLI refuses the advance when a file changed since (scripts/approval.py)."""
        out = ""
        for name in ("intent.md", "tasks.md"):
            d = approval.digest(os.path.join(self.r.spec, name)) if self.r.spec else None
            if d:
                out += " --shown %s=%s" % (name, d)
        return out

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
        ask = self.opt("Ask me at every stage", lead + "Approve the plan; every later stage asks you.", move="approve",
                       calls=go("interactive"), oid="ask-every-stage")
        if r.run_default() == "never-unattended" or r.skip(stage) is not None or not self.may_run_alone():
            return [self.set_rec(ask, True)]
        run = self.opt("Approve and build", lead + self.armed_text(), move="arm",
                       calls=go("autonomous"), oid="approve-run")
        return [self.set_rec(ask, True), run] if r.run_default() == "ask" else [self.set_rec(run, True), ask]

    def sensitive_line(self):
        """The approval names the plan's files under a sensitive path (WP15 moves it to the card)."""
        hits = self.r.sensitive()
        return " The plan touches a sensitive path: %s. Nothing there is repaired by rule." % ", ".join(hits[:3]) if hits else ""

    def loop_opt(self, stage, back, rec=False):
        """Loop back from the stage to an earlier one, with the person's reason."""
        return self.opt("Loop back to %s%s" % (LABEL[back], " (Recommended)" if rec else ""),
                        "Do %s again; the stages after it are redone too." % LABEL[back], move="back",
                        calls=[self.c("state loop %s %s --reason '{reason}'" % (stage, back))],
                        reason=["The check found a real problem"], oid="back")

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

        def back_opt(rec=False):
            # a step back the budget refuses is dropped after (budget_guard), so the question says so
            return [self.loop_opt(stage, back, rec)] if back else []

        def override_opt(then):
            return self.opt("Override and continue", "Skip this check with your reason; the report shows it.", move="override",
                            calls=[self.c("override %s --reason '{reason}'" % (r.gate_of(stage) or stage))] + then,
                            reason=override_reasons, oid="override")

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
            return self.question(GATE_HEADER, "RCA: the root cause is in %s/rca.md. Proceed to Fix?" % r.spec, stage=stage, qid="rca.approve", options=[
                self.opt("Proceed to Fix (Recommended)", "Write the regression test and the fix.", move="approve",
                         calls=[self.c("state advance rca_complete fix")], oid="continue"), self.save()])

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
                            do="Follow %s/reference/plan-review.md (Open HTML review), then ask this question again." % self.plugin, oid="html-review")
            share = self.opt("Share HTML review", "Publish the plan as a private Claude artifact others can comment on.",
                             do="Follow %s/reference/plan-review.md (Share HTML review), then ask this question again." % self.plugin, oid="share-review")
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
                text = "Plan: %s.%s%s %s" % (state_of, said, self.sensitive_line(), ask_text % nl)
                # 9.8.0: the fresh review's open findings below high pass the gate, and are the person's call: the question
                # names them and offers Revise the plan (9.8.4: never recommended; they go to the builder as notes).
                lesser = [f for f in fr["findings"] if f["state"] not in ("resolved", "accepted")] if not skipped else []
                revise = None
                if lesser:
                    shown = "; ".join("#%d [%s] %s" % (f["id"], f["severity"], f["claim"][:120]) for f in lesser[:3])
                    # 9.8.4: only a high finding blocks; a medium or low one goes to the builder as a note (in the task's
                    # prompt), so revising is offered after the ways on, never recommended: a revision is another round.
                    text = "Plan: %s.%s%s The fresh review left %d finding(s) open: %s%s. They go to the builder as notes. %s" % (
                        state_of, said, self.sensitive_line(), len(lesser), shown, "; and %d more" % (len(lesser) - 3) if len(lesser) > 3 else "", ask_text % nl)
                    revise = self.revise_opt("The Plan agent fixes or contests each open finding of the fresh review; then the plan is checked again.",
                                             "fresh review: " + "; ".join(fresh_review.describe(f) for f in lesser))
                # The approval (WP11): here when no Design follows, at the Design question when it does.
                if not r.has_design():
                    # WP14: Design runs only when the person asks for it here. The option takes Teach Me's place in the More
                    # list, so every option stays within two dialogs (a More list of five made a third level, M2 of PR 115).
                    design = self.opt("Run Design first", "Approve the plan; Design runs next, and its question is the last "
                                      "one before Build.", move="approve", oid="run-design",
                                      calls=[self.c("state set want_design true")] + self.leave_plan("design", fold=fold))
                    first = self.approval(lambda m: self.leave_plan(fold=fold, mode=m), "plan", lead)
                    if revise is not None:   # findings below high: revising is offered, after the ways on
                        return self.with_more(GATE_HEADER, text, stage, first + [revise], more([html, design, grill, self.save()]), "Plan: more options.", qid="plan.approve")
                    if fr["offer"]:   # four options a question: the offer takes Share's place, which Open HTML review leads to anyway
                        return self.with_more(GATE_HEADER, text, stage, first + [self.fresh_offer()], more([html, design, grill, self.save()]), "Plan: more options.", qid="plan.approve")
                    return self.with_more(GATE_HEADER, text, stage, first + [html], more([share, design, grill, self.save()]), "Plan: more options.", qid="plan.approve")
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
            # WP08 (M16): a failed preflight is never returned from the store, so after the person repaired the
            # environment one option runs the plan's commands again and checks the plan
            again = [self.opt("Check again", "Run the plan's commands again (after you repaired the environment) and "
                              "check the plan.", move="redo", calls=[self.c("plan preflight"), self.c("gate plan")],
                              oid="check-again")] if any(x.get("name") == "preflight" for x in rows) else []
            env_opt = self.setup_offer(rows)
            if env_opt:
                # 9.8.5: the preflight hit the environment and the project declares none: one click adds the block that
                # temper doctor --propose made from the project's own facts, runs the preflight again and checks the plan
                text = ("Plan: the check failed (%s).%s The project's own files say what it needs: add the proposed "
                        "setup block (%s) and check again?" % (why, said, self.shown_block))
                opts = again + [env_opt] + back_opt() + [override_opt(self.skip_then()), self.save()]
            else:
                text = "Plan: the check failed (%s).%s Fix the plan, or skip the check?" % (why, said)
                opts = again + back_opt() + [override_opt(self.skip_then()), grill, self.save()]
            return self.with_more(GATE_HEADER, text, stage, opts[:3], opts[3:], "Plan: more options.", qid="plan.fail")

        if stage == "design":
            walk = self.opt("Walk through step by step", "Review the design section by section.",
                            do="Walk through the sections design.md has (architecture, API contracts, database changes, integration points, decision log), then ask this question again.",
                            oid="walk-through")
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
                # WP11: the Design question is the approval when the person asked for Design
                text = text[:-len(" Continue to Build?")] + self.sensitive_line() + " Continue to Build?"
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
            # 9.8.4: the same failure after a Run again is not run again by the recommendation: the run converges on the
            # person (an e2e run that followed it relaunched Build's fix pass forty times on one failure)
            redo = r.state.get("redo") if isinstance(r.state.get("redo"), dict) else {}
            same = redo.get("stage") == stage and same_failure(str(redo.get("reason") or ""), why[:300])
            again = self.opt("Run %s again" % label + ("" if same else " (Recommended)"), "Mend what the failed rows name, then check %s again." % label,
                             move="redo", calls=[self.c('state redo %s --reason %s' % (stage, shlex.quote(why[:300])))], oid="redo")
            text = "%s: the check failed (%s). %s" % (label, why, "It failed the same way after it ran again. Save the run for later?"
                                                       if same else "Run %s again?" % label)
            opts = ([self.set_rec(self.save(), True), again] + back_opt() + [override_opt(go)] if same else
                    [again] + back_opt() + [override_opt(go), self.save()])
            return self.question(GATE_HEADER, text, stage=stage, options=opts, qid="%s.fail" % stage)

        if stage == "review":
            go = [self.c("state advance review_complete check")]
            arch = self.opt("Architecture Depth Review", "Check the changed modules' depth, then come back here.",
                            do="Run the module depth analysis of %s/reference/architecture-depth.md on the changed files, add its [ARCH-DEPTH] findings to the summary, then ask this question again." % self.plugin,
                            oid="depth-review")
            opens = r.open_findings()
            if passed:
                # The open findings below the blocking severity (the gate counts only those at or above it).
                opens = [f for f in r.findings() if f["state"] == "open"]
                # Findings below the blocking severity are still open: Build can fix them (a loop back), or the person
                # keeps one. A typed change is no fix here, since Review writes no code.
                grill = self.skill("grill-me", "Grill Me", "Stress test the change.")
                keep = [self.opt("Accept a finding", "Keep a finding as it is, with your reason.", do="Ask the accept question.", oid="accept-finding", kind="accept")] if opens else []
                # 9.8.5 (Q2, F1 of WP08): an open finding at high or above is repaired by default: the loop back to Build is
                # recommended. A Medium one goes on to Check, listed in the Check question where the person commits.
                repair = back_opt(rec=True) if any(f["severity"] in ("critical", "high") for f in opens) else []
                if repair:
                    first = repair + [self.opt("Continue to Check", "Start Check with the findings open.", move="advance", calls=go, oid="continue"), arch]
                else:
                    first = [self.opt("Continue to Check (Recommended)", "Start Check.", move="advance", calls=go, oid="continue")] + (back_opt() if opens else []) + [arch]
                rest = [self.skill("teach-me", "Teach Me", "Walk through the change."), self.save()]
                q = self.with_more(GATE_HEADER, "Review: %s%s. %s" % (state_of, self.finding_counts(opens),
                                   "Loop back to Build to repair them?" if repair else "Continue to Check?"), stage,
                                   first + ([] if opens else [grill]), keep + ([grill] if opens else []) + rest, "Review: more options.", qid="review.pass")
                if keep:
                    q["accept"] = self.accept_question(opens, qid="review.pass.accept")
                return q
            accept = None
            # A review that recorded no completion row did not finish (its agent failed or stopped): run it again first.
            unfinished = bool(rows) and all(x.get("name") == "review completed" for x in rows)
            first = back_opt(rec=not unfinished)
            if unfinished:
                first.insert(0, self.opt("Run Review again (Recommended)", "The review did not finish; it runs again.", move="redo",
                                         calls=[self.c("state redo review --reason 'the review did not finish'")], oid="redo"))
            if opens:
                accept = self.accept_question(opens, qid="review.fail.accept")
                first.append(self.opt("Accept a finding", "Keep a finding as it is, with your reason.", do="Ask the accept question.", oid="accept-finding", kind="accept"))
            first.append(override_opt(go))
            text = "Review: the check failed (%s)%s. Loop back to %s?" % (why, self.finding_counts([f for f in r.findings() if f["state"] == "open"]),
                                                                         LABEL.get(back or "build", "Build"))
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
                                         oid="config-suggestions"))
                # F1 of WP08: an open finding goes on to Check, so the question where the person commits lists it
                return self.with_more(GATE_HEADER, "Check: %s%s. Commit?" % (state_of, self.open_listed()), stage, opts[:3] if len(opts) >= 4 else opts, opts[3:] + [self.save()] if len(opts) >= 4 else [self.save()], "Check: more options.",
                                      qid="check.pass")
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
                return self.question(GATE_HEADER, text, stage=stage, qid="check.fail", options=[
                    self.opt("Confirmed (Recommended)", "I checked it by hand; record my confirmation and check again.", move="confirm", calls=calls, oid="confirm")]
                    + back_opt() + [self.save()])
            setup = self.setup_fault()
            if setup:
                # 9.8.5 (Q6): the environment was not ready (no database, the wrong JDK, a failed setup line). Nothing in the
                # code is wrong, so a loop back is never recommended: repair the environment, then Check runs again.
                fix = self.opt("Repair the environment and run again (Recommended)",
                               "temper doctor shows what is missing; the setup: block of .claude/temper.config makes it ready. Then Check runs again.",
                               move="redo", calls=[self.c("state redo check --reason %s" % shlex.quote(("SETUP: " + setup)[:300]))], oid="redo")
                add = self.setup_offer([{"name": "preflight", "detail": "environment fault"}])   # no block, and one proposed
                if add:
                    self.set_rec(fix, False)
                    if add["id"] == "add-setup":
                        add["calls"] = [add["calls"][0], self.c("state redo check --reason %s" % shlex.quote(("SETUP: " + setup)[:300]))]
                # M10 of WP08: the same fault after Check ran again is not repaired again by the recommendation
                redo = r.state.get("redo") if isinstance(r.state.get("redo"), dict) else {}
                opts = ([add] if add else []) + [fix, self.save()]
                text = "Check: SETUP: the environment was not ready (%s), so the result is no verdict on the code. %s run Check again?" % (
                    setup, "Add the proposed setup block (%s) and" % self.shown_block if add else "Repair it and")
                if redo.get("stage") == "check" and same_failure(str(redo.get("reason") or ""), ("SETUP: " + setup)[:300]):
                    opts = [self.set_rec(self.save(), True)] + [self.set_rec(o, False) for o in opts[:-1]]
                    # M13 (c): while the block is offered, the question still shows it whole
                    text = "Check: SETUP: the environment was not ready (%s). It failed the same way after Check ran again: repair it%s, or save the run for later?" % (
                        setup, ", add the proposed setup block (%s)" % self.shown_block if add else "")
                return self.question(GATE_HEADER, text, stage=stage, options=opts + back_opt(rec=False) + [override_opt(go)], qid="check.fail")
            gap = self.measurement_gap(r.failed_rows("check"))
            # 9.8.4: the same missing measurement after a Run again (the tool is still not there) is not run again by the
            # recommendation: a benchmark run without coverage.py ran Check again 52 times
            redo = r.state.get("redo") if isinstance(r.state.get("redo"), dict) else {}
            same = gap and redo.get("stage") == "check" and same_failure(str(redo.get("reason") or ""), ("the measurement was missing: " + why)[:300])
            again = [self.opt("Run Check again" + ("" if same else " (Recommended)"), "Install what the failed row names, then Check measures again; Build is not redone.",
                              move="redo", calls=[self.c("state redo check --reason %s" % shlex.quote(("the measurement was missing: " + why)[:300]))], oid="redo")] if gap else []
            if same:
                save = self.set_rec(self.save(), True)
                return self.question(GATE_HEADER, "Check: the check failed (%s). It failed the same way after it ran again: install what it names, or save the run for later?" % why,
                                     stage=stage, options=[save] + again + back_opt(rec=False) + [override_opt(go)], qid="check.fail")
            acc = self.acceptance_options(r.failed_rows("check"))
            if acc:
                first = acc[0]
                rec = first.get("recommended") is True
                opts = [first] + back_opt(rec=False) if rec else back_opt(rec=True) + [first]
                lead = next((o for o in opts if o.get("recommended")), first)
                t = self.acc_triage()
                said = (" The triage says the %s looks wrong: %s." % (t["verdict"], t.get("reason", ""))) if t.get("verdict") in ("code", "test") else ""
                return self.question(GATE_HEADER, "Check: the check failed (%s).%s %s?" % (why, said, self.bare(lead)), stage=stage,
                                     options=opts + [override_opt(go), self.save()], qid="check.fail")
            return self.question(GATE_HEADER, "Check: the check failed (%s). %s?" % (why, "Run Check again" if gap else "Loop back to %s" % LABEL[back or "build"]), stage=stage,
                                 options=again + back_opt(rec=not gap) + [override_opt(go), self.save()], qid="check.fail")

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
                         move="advance", calls=[self.c("state set pr %s" % kind)] + go, oid="commit-pr" if kind == "one" else "commit-stacked-prs")
                for kind, label, what in kinds]

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
                        reason=["A small fix I will describe", "A change the review asked for"], oid="small-change")

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
        more = q.get("more")
        if stage == "review" and len(q["options"]) >= 4 and more and len(more["options"]) >= 4 and r.verdict("review") == "PASS" and \
                any(f["state"] == "open" for f in r.findings()):
            # M2 of WP08: at a passed Review with an open finding both questions are full. The Architecture Depth Review gives
            # way to the small change, and Teach Me takes its place, so Accept a finding, Grill Me, Teach Me and Save for
            # later all stay in reach (row D42).
            teach = next((o for o in more["options"] if o["label"] == "Teach Me"), None)
            at = next((i for i, o in enumerate(q["options"]) if o.get("id") == "depth-review"), None)
            if teach is not None and at is not None:
                q["options"][at] = teach
                more["options"] = [o for o in more["options"] if o is not teach]
                more["question"]["options"] = [{"label": o["label"], "description": o["description"]} for o in more["options"]]
        opt = self.adhoc_option(stage)
        self.follow_ups(opt, q["id"])

        def put(options):
            keep = [o for o in options if o["label"] == "Save for later"]
            rest = [o for o in options if o["label"] != "Save for later"]
            return rest + [opt] + keep

        if len(q["options"]) < 4:
            q["options"] = put(q["options"])
        elif q.get("more") and len(q["more"]["options"]) < 4:
            q["more"]["options"] = put(q["more"]["options"])
            q["more"]["question"]["options"] = [{"label": o["label"], "description": o["description"]} for o in q["more"]["options"]]
        elif q.get("more"):
            return out   # M2 of WP08: a full More question is never built again from the visible options
        else:
            first, rest = q["options"][:3], q["options"][3:]
            more = self.question(q["question"]["header"], q["question"]["question"].split("?")[0] + "? More options.", put(rest), stage,
                                 qid=q["id"] + ".more")
            q["options"] = first + [self.more_opt(more["options"])]
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
        if step == "check" and self.cli_check():
            # M7 of WP08: the CLI checks the tree itself, with no agent, as stage_work does (a claimed run counts for nothing)
            return {"action": "work", "stage": r.stage, "calls": [self.c("check run"), self.c("gate check")], "agents": [],
                    "say": "%s: the CLI checks the tree after your small change (no agent)." % LABEL.get(r.stage, r.stage)}
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
                                 calls=[self.c("state loop %s %s --reason '{reason}'" % (r.stage, work))], reason=["The review found a real problem"], oid="back"))
        opts.append(self.opt("Override and continue", "Skip the Review of your change with your reason; the report shows it.", move="override",
                             calls=[self.c("override review --reason '{reason}'")], reason=["I accept the risk", "It is not a real issue"], oid="override"))
        opts.append(self.save())
        return {"action": "ask", "stage": r.stage, "ask": self.question(GATE_HEADER, "%s: Review of your small change failed (%s). %s" % (
            LABEL.get(r.stage, r.stage), why, "Loop back to %s?" % LABEL[work] if len(opts) > 2 else "Override it?"), stage=r.stage, options=opts, qid="adhoc.fail")}

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
                     "The fix list in pipeline-context.json is applied, pushed, and the checks are read again.", move="advance", steps=steps, oid="apply-fix"),
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
            first.append(self.opt("Accept a finding", "Keep a finding as it is, with your reason.", do="Ask the accept question.", oid="accept-finding", kind="accept"))
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
