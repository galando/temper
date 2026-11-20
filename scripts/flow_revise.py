"""flow_revise.py: RevisePart of Builder (WP27): the narrow revise agent of the plan (agents/plan-revise.md).

A change to a plan that exists (a fresh finding, the person's note, an answer, a loop back that does not pass through
Intent) is made by a small agent that gets the reason, every item whole and the task blocks they name, not by a second
full planner pass. A module of the flow; scripts/flow.py is its facade. Standard library only.
"""

import os
import re
import shlex
import time

import budget
import decisions

from flow_base import LABEL, TEMPER, goes_on, loop_at, on_model


def brief_at():
    """When the CLI last wrote the project brief (`temper brief`, the first call of every planner launch), as a time
    of the run's records, or ''."""
    try:
        return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(os.path.getmtime(os.path.join(TEMPER, "brief.md"))))
    except OSError:
        return ""


class RevisePart:
    REVISE_KEYS = {"fresh findings": "findings", "the person's note": "note", "the context answer": "context",
                   "a decision against the plan": "decision", "a failed plan row": "row"}

    def revise_items(self):
        """(reason, items) of a change to the plan that exists, else None: a loop back into Plan that does not pass through
        Intent, the open fresh findings, an answer the tasks do not follow, the person's notes, in that order for the
        reason; every item whole, one a line. A loop back through Intent, or a plan with no tasks.md, is the planner's."""
        r = self.r
        if r.command != "temper" or not r.spec or not os.path.isfile(os.path.join(r.spec, "tasks.md")):
            return None
        back, through = r.loop_into("plan"), r.loop_through("plan")
        if through and (not back or loop_at(through) > loop_at(back)):
            return None
        one = lambda x: " ".join(str(x).split())
        found = [f for f in r.fresh()["findings"] if f["state"] not in ("resolved", "accepted")]
        unmet = decisions.unmet(decisions.project_of(r.spec), r.spec)
        notes = r.notes("plan", "input")
        # a step back: its reason, then what the stage it came from left open, first what stopped the run, in the words
        # the planner's prompt uses for them
        frm = LABEL.get(back.get("from_stage"), back.get("from_stage")) if back else ""
        items = ["Left open: Loop back from %s: %s." % (frm, one(back.get("reason") or "no reason given").rstrip("."))] if back else []
        items += ["Left open: What %s left open: %d. %s" % (frm, i + 1, one(x)) for i, x in enumerate((back or {}).get("findings") or [])]
        items += ["Finding #%d [%s]: %s" % (f["id"], f["severity"], one(f["claim"])) for f in found]
        items += ["Left open: answers the tasks do not follow yet: %s" % one(unmet)] if unmet else []
        items += ["Person's note: %s" % one(x["claim"]) for x in notes]
        reason = ("a loop back from %s" % back.get("from_stage") if back else "fresh findings" if found else
                  "a decision against the plan" if unmet else "the context answer" if notes and all(
                      str(x["claim"]).startswith("Context check:") for x in notes) else "the person's note" if notes else "")
        return (reason, items) if items else None

    # the rows of the plan gate that wait on the person or on a reviewer, which no revision answers
    WAITS = ("blocking question open", "context map reviewed", "fresh review ran", "fresh reader's paraphrase")

    def revise_key(self, reason):
        return "plan-revise:" + (self.REVISE_KEYS.get(reason) or re.sub(r"\W+", "-", reason.replace("a loop back from ", "loop-")))

    def affected(self, items):
        """The tasks the items name: a `Task N`, the tasks of a group named, the tasks that declare a file named."""
        plan, text = self.r.plan or {}, "\n".join(items)
        got = {int(n) for n in re.findall(r"\bTasks? (\d+)\b", text)}
        for g in plan.get("groups") or []:
            if re.search(r"(?<![\w.])%s\b" % re.escape(str(g.get("id"))), text):
                got.update(int(n) for n in g.get("tasks") or [])
        got.update(int(t["n"]) for t in plan.get("tasks") or [] if any(f and f in text for f in t.get("files") or []))
        return ", ".join(str(n) for n in sorted(got)) or "not named"

    def revise_agent(self, reason, items, key):
        """The revise launch: a closed list of lines the CLI writes; no project brief, no brief call. Its before call
        counts it against the budget (plan-revise:<reason>); its after calls are the planner's."""
        r = self.r
        model = r.model("plan-revise")
        lines = ["Follow %s/agents/plan-revise.md exactly." % self.plugin, "Spec path: %s." % r.spec, "Reason: %s." % reason]
        lines += items + ["Affected tasks: %s" % self.affected(items)]
        prompt = "\n".join(lines) + self.decisions_line() + "\n" + self.plugin_line()
        a = {"type": "temper:temper-plan-revise", "model": model, "prompt": prompt,
             "before": [self.c("budget revise --key %s --reason %s" % (key, shlex.quote(reason)))],
             "after": [self.c("usage add --stage plan --model %s --ms {ms}" % (model or "unknown")), self.c("risk"),
                       self.c("baseline plan"), self.c("gate plan")]}
        a["gate"] = a["after"][-1]
        return {"action": "work", "stage": "plan", "calls": [], "agents": [a],
                "say": "Plan: the revise agent changes the tasks named by %s%s. %s" % (
                    {"fresh findings": "the findings", "the person's note": "your note", "a failed plan row": "the failed check"}.get(
                        reason, "the step back" if reason.startswith("a loop back") else "your answer"), on_model([a]), goes_on(False))}

    def revise_work(self):
        """WP27 (step 3): the revise agent when tasks.md exists, an item exists, no loop back passes through Intent, and
        fewer than two revise launches were made for the reason; before the approval the planner after two (the fall
        back), after it the same launch, which the budget turns into its question (a rule never plans again)."""
        got = self.revise_items()
        if not got:
            return None
        key = self.revise_key(got[0])
        if self.r.room(key)["used"] >= 2 and not self.r.state.get("plan_hash"):
            return None
        return self.revise_agent(got[0], got[1], key)

    def revise_again(self):
        """WP27 (step 4): the plan gate failed after a revise launch: one more revise for the same reason, the failed rows
        added as items; after the second, before the approval, the planner with the same items, once; after the approval
        the revise launch the budget refuses (run.budget). A row that waits on the person is the question's."""
        r = self.r
        rows = r.failed_rows("plan")
        used = budget.record(budget.Facts(r))["used"]
        last = ([x for x in used if str(x.get("key") or "").startswith("plan-revise:")] or [None])[-1]
        g = r.gates.get("plan") if isinstance(r.gates.get("plan"), dict) else {}
        redo = r.state.get("redo") if isinstance(r.state.get("redo"), dict) else {}
        if (r.armed() or not last or r.verdict("plan") != "FAIL" or str(g.get("ts") or "") < str(last.get("ts") or "")
                or max([str(redo.get("ts") or ""), brief_at()] + [loop_at(x) for x in r.active_loops()]) > str(last.get("ts") or "")
                or r.state.get("revise_fallback") == last["key"] or not rows or all(x.get("name") in self.WAITS for x in rows)):
            return None   # the latest launch of Plan was no revise: a run again, a step back or a planner came after it
        if all(x.get("name") in self.WAITS + ("no open plan blockers",) for x in rows) and not any(
                f["state"] == "open" for f in r.fresh()["findings"]):
            return None   # a contested or escalated finding is the person's call, at the question
        got = self.revise_items() or (next((k for k, v in self.REVISE_KEYS.items() if "plan-revise:" + v == last["key"]),
                                            "a failed plan row"), [])
        items = got[1] + ["Row %s: %s" % (x.get("name"), " ".join(str(x.get("detail") or "").split())) for x in rows]
        if r.room(last["key"])["used"] < 2 or r.state.get("plan_hash"):
            return self.revise_agent(got[0], items, last["key"])
        out = self.stage_work_planner(items)
        out["agents"][0]["after"].insert(1, self.c("state set revise_fallback %s" % last["key"]))
        out["say"] = "Plan: two revisions left the check failing; the Plan agent writes the plan again%s. %s" % (
            on_model(out["agents"]), goes_on(False))
        return out

    def stage_work_planner(self, items):
        """The planner's launch with these items (the fall back of revise_again): stage_work's, with the items as lines."""
        a = self.agent("plan", [x for x in items if not x.startswith("Person's note: ")])
        a["after"] += [self.c("risk"), self.c("baseline plan"), self.c("gate plan")]
        a["gate"] = a["after"][-1]
        return {"action": "work", "stage": "plan", "calls": [self.c("brief")], "agents": [a]}
