"""flow_commit.py: CommitPart of Builder: the end of the run (report, record, commit), the context question, and (WP13)
the steps that leave Intent by rule and leave Plan at the approval.

A module of the flow; scripts/flow.py is its facade. Standard library only.
"""

import os
import re
import shlex

import approval
import intent_parse

from flow_base import GATE_HEADER, LABEL, NO_RECORD_STEP, REPORT_STEP, RESUME_HEADER, git, with_step_kinds


class CommitPart:
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
        steps.append(REPORT_STEP)
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

    def record_parts(self):
        """What the run's record commit stages and the message it uses: {files, lessons, code, message}. The code is
        what is still uncommitted (Build commits each task, each group and the merge); message is None when there is
        nothing to stage. The commit card shows this message (WP15)."""
        r = self.r
        files = r.ctx.get("changed") or []
        if not r.spec_ignored() and r.spec:
            files = [r.spec + "/"] + [f for f in files if not f.startswith(r.spec + "/")]
        # A fix run's lesson is committed with it, unless the project keeps .temper out of git (then it stays local).
        lessons = [".temper/lessons.md"] if r.command == "fix" and ".temper/lessons.md" not in files and not r.ctx.get("lessons_ignored") else []
        code = [f for f in files if not (f.startswith(r.spec + "/") or f.startswith(".temper/"))] if r.spec else files
        if code and git("rev-parse", "--verify", "-q", "HEAD"):
            code = [f for f in code if git("status", "--porcelain", "--", f)]
        if not code and not lessons and (r.spec_ignored() or not r.spec or not r.ctx.get("spec_dirty")):
            message = None
        elif r.command == "fix":
            # 9.8.0: the CLI drafts the message from rca.md and the tests the fix changed; the person can still
            # amend it.
            message = self.fix_message()
        elif files and not code:
            # A grouped Build commits the code itself (each task, each group, the merge into this branch): this
            # commit is the run's record, and its message says so.
            message = "docs(%s): record the run: spec, gate ledger and report (the code is in the commits before it)" % r.slug
        else:
            # 9.8.0: the CLI drafts the message from the intent's title (one call fewer for the session).
            message = self.feature_message()
        return {"files": files, "lessons": lessons, "code": code, "message": message}

    def commit_message(self):
        """The message of the commit the commit question's click makes (WP15): at commit.confirm the change's own commit
        when code is uncommitted (commit_calls), else the record commit's."""
        return self.record_parts()["message"]

    def commit_calls(self):
        """WP15: the click of commit.confirm commits the change with the message its card shows (the uncommitted code
        only); the report and the run's record commit follow, as after any commit."""
        p = self.record_parts()
        if not p["code"] or not p["message"]:
            return []
        return [self.c("spec commit %s -- %s" % (shlex.quote(p["message"]), " ".join(shlex.quote(f) for f in p["code"])))]

    def record_steps(self):
        r = self.r
        steps = [self.c("state archive")]
        p = self.record_parts()
        files, lessons, message = p["files"], p["lessons"], p["message"]
        if message is None:
            # F27: nothing to stage: no uncommitted code, no lesson file, and a spec folder git ignores. No git add, no git commit.
            steps.append(NO_RECORD_STEP)
        else:
            # 9.8.0: one CLI call stages the files and commits (scripts/spec_ops.py): the steps are all temper calls,
            # run in one Bash call. Each name is one shell quoted word: a file name is never shell code. WP16: with no
            # file list, the same call with the lesson file alone (no raw git add and git commit).
            steps.append(self.c("spec commit %s -- %s" % (shlex.quote(message), " ".join(shlex.quote(f) for f in files + lessons))))
        pr = r.state.get("pr")
        if pr in ("one", "stacked") and not r.armed() and r.command == "temper":
            steps.append("Pull request: follow %s/reference/pr.md, section Capture, now: note base_sha, the branch, the default branch and the spec path, "
                         "since the state is gone after state clear." % self.plugin)
            steps.append("Follow %s/reference/pr.md, section %s: every pull request is a draft, and Temper never marks one ready. "
                         "A pull request that cannot be opened never fails the commit." % (self.plugin, "One PR" if pr == "one" else "Stacked PRs"))
        if r.command == "temper" and r.cfg("phases.pipeline").lower() != "false" and pr in ("one", "stacked") and not r.armed():
            steps.append("If a pull request was opened, run %s: Pipeline reads its checks. Otherwise run %s." % (
                self.c("state advance commit_complete pipeline"), self.c("state clear")))
        else:
            steps.append(self.c("state clear"))
        return steps

    def commit_question(self):
        """WP11: the commit question of a run that stopped at Commit (always, for a run that went on by itself): commit
        (recommended), commit and open a pull request, or a loop back to Build; under More the stacked pull requests,
        the small change (add_adhoc) and Save for later. Its text names the open findings by level."""
        r = self.r
        steps = self.report_steps()
        # WP15: the click commits the change with the message the commit card shows, then the report and the record
        first = [self.opt("Commit (Recommended)", "Commit the change with its spec files.", move="advance", calls=self.commit_calls(),
                          steps=steps, oid="commit")]
        prs = self.pr_options([])   # a /temper:temper run only: one pull request, and stacked ones for two groups or more
        for o in prs:
            o["steps"] = steps
            with_step_kinds(o)
        first += prs[:1] + [self.loop_opt("check", "fix" if r.command == "fix" else "build")]
        rest = prs[1:]
        opens = [f for f in r.findings() if f["state"] == "open"]
        text = "Commit: every gate passed%s, and the armed run parked here for you (its report: .temper/autonomy-report.md). Commit?" % (
            self.finding_counts(opens))
        anyway = self.run_anyway(["check run --fresh", "gate check", "gate commit"])   # WP22
        return self.with_more(GATE_HEADER, text, "commit", first, rest + [anyway, self.save()], "Commit: more options.", qid="commit.confirm")

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
                out = with_step_kinds({"action": "work", "stage": "commit", "calls": [], "agents": [], "steps": self.record_steps(),
                                       "say": "The commit carries the run's record."})
                if any("/reference/pr.md" in x for x in out["steps"]):
                    # WP16: the pull request steps are the conversation's one step (a hand back kind of NEEDS), with the
                    # id of the option the person chose them by
                    out.update({"needs": "pull-request", "option": "commit-pr" if r.state.get("pr") == "one" else "commit-stacked-prs"})
                return out
            if end == "shown":
                # 9.8.0: the report page is written without a question (it is committed with the spec); the run asked
                # "write it as HTML too?" at every commit before, one more decision with nothing at stake.
                return {"action": "work", "stage": "commit", "calls": [self.c("report --html")], "agents": [],
                        "say": "The report page is written (report.html in the spec folder); then the commit."}
            if r.state.get("parked"):
                return {"action": "ask", "stage": "commit", "ask": self.commit_question()}
            return with_step_kinds({"action": "work", "stage": "commit", "calls": [], "agents": [], "steps": self.report_steps(),
                                    "say": "Every gate passed: the report first, then the commit."})
        failing = sorted({re.sub(r"\s+gate$", "", str(x.get("name", ""))) for x in r.failed_rows("commit") if str(x.get("name", "")).endswith(" gate")})
        # Only rows of the commit gate's own failed (an armed run's blast radius or park-on-touch): the person's skip is
        # of the commit check itself, recorded with their reason like any other.
        # 9.8.5 (Q8): an override clears a failed stage gate the commit gate names; it never clears the commit gate's own rows
        # (blast radius, scope, park-on-touch), so it is not offered for them (a run asked the same question again after it)
        own = not failing
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
                       for f in outside] + [self.c("gate commit")], oid="add-to-plan"))
        if r.command == "fix" and "check" in failing and r.can_loop("check", "fix"):
            opts.append(self.opt("Loop back to Fix (Recommended)", "Write the fix again; Review and Check run again.", move="back",
                                 calls=[self.c("state loop check fix --reason '{reason}'")], reason=["The check found a real problem"], oid="back"))
        if own and not outside:
            # M11 of WP08: the question says "then check again", and this option does it (first, with no mark: what the
            # row names changes first)
            opts.append(self.opt("Check again", "Run the commit gate again, once you changed what the row names.", move="redo",
                                 calls=[self.c("gate commit")], oid="check-again"))
        # WP11: a changed file under a sensitive path, outside the plan: the person confirms the change here, with a reason
        touched = []
        for x in r.failed_rows("commit"):
            if x.get("name") in ("park-on-touch paths", "sensitive paths"):
                touched += [m.group(1) for m in re.finditer(r"(?:^|; )(\S+) matches \S+ and is not in the plan", str(x.get("detail", "")))]
        if touched:
            opts.append(self.opt("Confirm the change to %s" % touched[0], "The change to %s is right: record your reason and check the commit "
                                 "again." % touched[0], move="commitOverride", reason=["The change belongs to this feature"],
                                 calls=[self.c("override %s --reason '{reason}'" % shlex.quote("sensitive-path:" + touched[0])), self.c("gate commit")],
                                 oid="confirm"))
        if any(x.get("name") == "checked tree" for x in r.failed_rows("commit")):   # WP22: Check judged another tree
            opts.insert(0, self.run_anyway(["check run --fresh", "gate check", "gate commit"]))
        if not own:
            opts.append(self.opt("Override and commit", "Skip the failed gates with your reason and commit.", move="commitOverride",
                                 calls=[self.c("override %s --reason '{reason}'" % s) for s in failing] + [self.c("gate commit")],
                                 reason=["I accept the risk", "It is not a real issue"], oid="override"))
        opts.append(self.save())
        why = "; ".join("%s: %s" % (x.get("name"), x.get("detail")) for x in r.failed_rows("commit")[:3])
        ask = ("Override and commit?" if not own else "Add the files to the plan?" if outside else
               "Confirm the change, or check again?" if touched else "Change what the row names, then check again?")
        return {"action": "ask", "stage": "commit", "ask": self.question(GATE_HEADER, "Commit: the commit gate failed (%s). %s" % (why, ask), stage="commit", options=opts,
                                                                       qid="commit.fail")}

    def restart(self):
        r = self.r
        return {"header": RESUME_HEADER, "question": "A run of %s is open at %s. Start over?" % (r.slug, LABEL.get(r.stage, r.stage)),
                "multiSelect": False, "step": r.state.get("step"), "run_id": r.state.get("run_id"), "id": "run.restart", "kind": "resume",
                "options": [{"label": "Start over", "description": "The saved run state goes; the spec files stay.", "move": "restart",
                             "calls": [self.c("state clear")], "id": "start-over"},
                            {"label": "Cancel", "description": "Keep the run.", "move": None, "calls": [], "id": "cancel", "kind": "cancel"}]}

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

    # -- WP13: the run leaves Intent by rule; the approval accepts the intent and answers a folded map --
    def intent_by_rule(self):
        """WP13 (ADR 0019 decision 5): the run leaves Intent with no question, as the CLI's own action, only when a
        /temper:temper run's Intent check passed (not skipped), intent.md exists, no Blocking question is open, the run did
        not come back to Intent, and the person typed no note there. The intent stays a draft; the
        person accepts it with the plan, at the approval (accept_draft). Else the Intent question is asked as before."""
        r = self.r
        return (r.command == "temper" and r.verdict("intent") == "PASS" and r.skip("intent") is None and bool(r.intent)
                and not r.blocking() and not r.loop_into("intent") and not r.loop_through("intent")
                and not r.notes("intent", "input"))

    def fold_calls(self, cm):
        """WP13: the folded Context check is answered by the approving option the person picks: plan.md records that the
        answer was given at the approval and how many flagged lines it showed. Never an auto or work action's call."""
        if not cm or not self.r.context_folded(cm):
            return []
        n = cm["flagged"]
        return [self.c("plan review --answer %s" % shlex.quote("As planned (at the approval, %d flagged line%s shown)" % (n, "" if n == 1 else "s")))]

    def intent_question(self, text, stage):
        """intent.accept: at Intent, Continue to Plan accepts intent.md and advances; at Plan (WP13: after a skip of the
        plan check, the intent still a draft) it accepts the intent as shown, and the plan question follows."""
        at = stage == "plan"
        return self.question(GATE_HEADER, text, stage=stage, qid="intent.accept", options=[
            self.opt("Accept the intent (Recommended)" if at else "Continue to Plan (Recommended)",
                     "Accept intent.md as shown; the plan question follows." if at else "Accept intent.md and start Plan.",
                     move="approve", calls=self.accept_draft() if at else self.leave_intent(), oid="continue"),
            self.skill("grill-me", "Grill Me", "Stress test the intent first."),
            self.skill("teach-me", "Teach Me", "Walk through the intent."), self.save()])

    def accept_draft(self):
        """WP12: `plan_complete` is refused while intent.md is a draft. A run saved at Plan by 9.8.4 or by the base can
        hold one (the saved states of its fixtures left Intent with no accept), so the approving options accept it
        first, bound to the intent the question shows; a skip of the plan gate never does."""
        r = self.r
        if not r.spec or intent_parse.status(r.intent) != "draft":
            return []
        d = approval.digest(os.path.join(r.spec, "intent.md"))
        return [self.c("intent accept" + (" --digest %s" % d if d else ""))]

    def leave_plan(self, nxt=None, fold=(), mode="interactive", then=()):
        """The approval: first the run's mode, which the CLI writes only once the digests of what the question showed
        still hold (bind: WP12, rules 1 and 2, so a stale approval makes no branch and no commit; WP11, rule 3: an
        option that does not start the unattended run sets it to ask, so a run whose approve-run stopped half way does
        not go on by itself), the folded Context check's answer (WP13), switch to the run's branch, accept a draft
        intent bound to the text shown (WP13: the approval accepts it), commit the spec folder there (the intent and
        the plan) once, advance with the digests of what the question showed. THEN (Run Design first: want_design)
        follows the bound mode, so a stale approval writes nothing at all. A skip of the plan gate never takes it for a
        draft (skip_then)."""
        r, nxt = self.r, nxt or self.r.next_of("plan") or "build"
        acc = self.accept_draft()
        what = "accept the intent and approve the plan" if acc else "approve the intent and the plan"
        return [self.bind(mode)] + list(then) + list(fold) + self.to_branch() + acc + \
            self.spec_commit("docs(plan): %s of %s" % (what, r.slug), changes=bool(acc or fold)) + \
            [self.c("state advance plan_complete %s%s" % (nxt, self.shown()))]

    def skip_then(self):
        """WP13 (red-safety B1): what a skip of the plan gate runs after its override: the way on, or nothing while the
        intent is a draft. Then `next` asks intent.accept at Plan, and the plan question follows."""
        return [] if self.accept_draft() else self.leave_plan()

    def include_opt(self, cm):
        """Include what is left out: Plan revises the plan to cover the map's ignore lines (None when it has none). An
        option of the Context check, and of the approval's More list when the check is folded into it (WP13)."""
        left = self.context_text(cm)[1]
        if not left:
            return None
        # 9.8.4: Plan gets the whole text of what is left out (the question shows each cut to fit); a cut at 100
        # characters told the Plan agent "already co".
        full = [x["text"] for x in (cm.get("rows") or []) if x.get("kind") == "ignore"][:3]
        what = "Include what is left out: %s" % "; ".join(full)
        return self.opt("Include what is left out", "Plan revises the plan to cover: %s." % "; ".join(left), move="answer",
                        calls=[self.c("plan review --answer %s --redo" % shlex.quote(what))], oid="include-left-out")

    def context_question(self, cm):
        """The Context check as the CLI's own question. "As planned" records the answer and checks the plan again; any other
        answer (including what was left out, a source the person names) also sends Plan back to revise with it (`--redo`),
        so the answer changes the plan instead of only being written down (9.8.0)."""
        text, left = self.context_text(cm)
        opts = [self.opt("As planned (Recommended)", "The plan's context is right; check the plan again.", move="answer",
                         calls=[self.c("plan review --answer 'As planned'"), self.c("gate plan")], oid="as-planned")]
        opts += [o for o in [self.include_opt(cm)] if o]
        # WP16: the typed answer fills the question's own `answer` call (no `do` text a session or the driver must read)
        opts.append(self.opt("Something else", "Type what Plan should change or read (Other); Plan revises the plan with it.", move="answer",
                             calls=[self.c("plan review --answer '{answer}' --redo")], answer=(GATE_HEADER, "What should Plan change or read? Type it below."),
                             oid="type", kind="type"))
        carry = self.opt("Carry forward", "Decide later; the plan gate keeps naming this question.", move=None, calls=[], oid="carry", kind="carry")
        opts.append(carry)
        for o in opts:
            o["preview"] = cm["table"]
        q = self.question(GATE_HEADER, text, opts, "plan", qid="plan.context")
        q["context"] = True
        q["answer"] = self.c("plan review --answer '{text}' --redo")
        q["gate"] = self.c("gate plan")
        return q
