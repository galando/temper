"""flow_commit.py: CommitPart of Builder: the end of the run (report, record, commit) and the context question.

A module of the flow; scripts/flow.py is its facade. Standard library only.
"""

import os
import re
import shlex

import intent_parse

from flow_base import GATE_HEADER, LABEL, RESUME_HEADER, git


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
                       for f in outside] + [self.c("gate commit")]))
        if r.command == "fix" and "check" in failing and r.can_loop("check", "fix"):
            opts.append(self.opt("Loop back to Fix (Recommended)", "Write the fix again; Review and Check run again.", move="back",
                                 calls=[self.c("state loop check fix --reason '{reason}'")], reason=["The check found a real problem"]))
        if not own:
            opts.append(self.opt("Override and commit", "Skip the failed gates with your reason and commit.", move="commitOverride",
                                 calls=[self.c("override %s --reason '{reason}'" % s) for s in failing] + [self.c("gate commit")],
                                 reason=["I accept the risk", "It is not a real issue"]))
        opts.append(self.save())
        why = "; ".join("%s: %s" % (x.get("name"), x.get("detail")) for x in r.failed_rows("commit")[:3])
        ask = ("Override and commit?" if not own else "Add the files to the plan?" if outside else
               "An override does not clear this row: change what it names (the config's autonomy limits, or the change), then check again.")
        return {"action": "ask", "stage": "commit", "ask": self.question(GATE_HEADER, "Commit: the commit gate failed (%s). %s" % (why, ask), stage="commit", options=opts)}

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
