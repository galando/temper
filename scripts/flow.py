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

import copy
import json
import os
import re
import shlex
import sys

import budget
import card
import fresh_review
import run_summary
import trivial

from flow_base import (
    FRESH_ROWS, GATE_HEADER, LABEL, TEMPER, VERSION, advance_ok, blocking_asks, design_accept, goes_on, on_model, plan_files)
from flow_run import changed_files, project_facts, Run
from flow_view import PERSON_ROWS, view, write_view
# the names other code reads on this module (cli_ctx.py, answer_ops.py, panel.py, drift.py, the cases)
from flow_base import MOVES, SEQ, concern_blocks, open_concerns, same_failure, scoped_notes
from flow_ask import AskPart
from flow_work import WorkPart
from flow_build import BuildPart
from flow_commit import CommitPart


# ---- building the answer ---------------------------------------------------------------------

class Builder(AskPart, WorkPart, BuildPart, CommitPart):
    def __init__(self, run):
        self.r = run
        self.cli = run.ctx.get("cli") or "temper"
        self.plugin = run.ctx.get("plugin") or ""

    def next(self):
        out = self.budget_guard(self.core_next())
        r = self.r
        if r.active and r.stage == "plan":
            cm = r.context()
            if cm:
                out["context_map"] = {k: cm[k] for k in ("intro", "file", "rows", "answer", "table")}
                # WP13: asked only about a flagged map (auto), every map (always), never (off); a flagged map that the
                # approval shows whole is answered there (r.context_folded()), and context_check stays null
                if r.context_asked(cm):
                    q = self.context_question(cm)
                    out["context_check"] = {k: q[k] for k in ("id", "kind", "question", "options", "answer", "gate")}
                    out["context_check"]["header"] = GATE_HEADER
                    rows = r.failed_rows("plan")
                    if out.get("action") == "ask" and len(rows) == 1 and rows[0].get("name") == "context map reviewed":
                        out["ask"] = q    # the only failed row is the pending check: ask the check itself, so a refused call can be answered again
                    elif out.get("action") == "ask" and (out.get("ask") or {}).get("id") == "plan.approve":
                        # WP14: a map the gate passed as folded that the approval has no room for (Run.context_folded):
                        # the Context check is asked first, and the approval after it, with no fold
                        out["ask"] = q
        self.stop_answer(out)
        self.add_note(out)
        self.add_typed(out)
        if out.get("action") == "ask":
            # WP15: the card of a question that decides (the approval, the commit, a stop), built in the same call
            # as the question and its digests; null for any other question. Never part of the question text.
            out["card"] = card.build(self, out)
        return out

    def stop_answer(self, out):
        """WP11 (ADR 0019 decision 3): a question asked at a stop of a run that goes on by itself (the mark `parked`, at
        a stage other than Commit). Its text says the run goes on by itself after the answer; every option with calls and
        no stop ends the stop with `park --end --answer <its id>` as its last call; and Ask me at every stage from here
        turns the run back to one that asks."""
        r = self.r
        q = out.get("ask") if out.get("action") == "ask" else None
        if (not isinstance(q, dict) or not r.state.get("parked") or r.stage == "commit"
                or r.state.get("run_mode") != "autonomous" or not r.state.get("unattended_from")):
            return

        def walk(x):
            for o in x.get("options") or []:
                if o.get("calls") and not o.get("stop") and o.get("kind") != "more":
                    o["calls"] = list(o["calls"]) + [self.c("park --end --answer %s" % o["id"])]
            for k in ("more", "accept", "change"):
                if isinstance(x.get(k), dict):
                    walk(x[k])
        walk(q)
        q["question"]["question"] = "%s After your answer the run goes on by itself." % q["question"]["question"].rstrip()
        shown = list(q.get("options") or []) + list((q.get("more") or {}).get("options") or [])
        if not any(o.get("id") == "ask-every-stage" for o in shown):
            self.add_option(q, self.opt("Ask me at every stage from here", "Answer this question yourself, and every later stage asks you.",
                                        move="approve", calls=[self.c("state set run_mode interactive"),
                                                               self.c("park --end --answer ask-every-stage")], oid="ask-every-stage"))

    def add_typed(self, out):
        """WP16: a gate question carries `typed`, the calls a typed answer runs with the text in place of {text} (a
        typed text is a change request by rule): the note for the next agent and, at Intent, Plan, Design, Build and
        Fix while the budget has room, the stage run again with it (`again` false: its agent runs). Elsewhere, and at
        the budget's limit, the note only, and the same question is asked again (`again` true)."""
        q = out.get("ask") if out.get("action") == "ask" else None
        if not isinstance(q, dict) or q.get("kind") != "gate":
            return
        r = self.r
        stage = q.get("stage") or r.stage
        calls = [self.c("evidence add --stage %s --phase note --kind input --claim '{text}'" % stage)]
        redo = self.c("state redo %s --reason '{text}'" % stage)
        if stage in ("intent", "plan", "design", "build", "fix") and stage == r.stage and str(q.get("id") or "").split(".")[0] == stage \
                and budget.refused([redo], self.cli, budget.Facts(r)) is None:
            calls.append(redo)
        x = q
        while isinstance(x, dict):
            x["typed"] = {"calls": calls, "again": len(calls) == 1}
            x = x.get("more")

    def add_option(self, q, o):
        """Add an option to a question as far down its More list as there is room, before Save for later; a full one
        gets a More question of its own."""
        m = q
        while len(m["options"]) >= 4 and isinstance(m.get("more"), dict):
            m = m["more"]
        if len(m["options"]) < 4:
            at = next((i for i, x in enumerate(m["options"]) if x.get("id") == "save"), len(m["options"]))
            m["options"].insert(at, o)
        else:
            last = m["options"][3]
            rest = [o, last] if last.get("id") == "save" else [last, o]
            m["more"] = self.question(m["question"]["header"], m["question"]["question"].split("?")[0] + "? More options.", rest,
                                      m["stage"], qid=m["id"] + ".more")
            m["options"] = m["options"][:3] + [self.more_opt(rest)]
        self.follow_ups(o, m["id"])
        m["question"]["options"] = [{"label": x["label"], "description": x["description"]} for x in m["options"]]

    def may_run_alone(self):
        """WP14 (ADR 0019 decision 2): whether the approval may offer the run that goes on by itself. At risk H only when
        the fresh review ran on the plan as it is (every lens of the round completed) and left no open finding at high."""
        r = self.r
        if (r.state.get("risk") or "").upper() != "H":
            return True
        fr = r.fresh()
        return bool(fr["applies"] and fr["launched"] and not fr["stale"] and not fr["missing"] and not fresh_review.blockers(fr))

    def answers_redo(self):
        """WP14: the plan gate failed only on answers the tasks do not follow yet (and on rows the person answers): the CLI
        sends the plan back once by itself. The same answers unmet after that revision are the person's question."""
        r = self.r
        names = [x.get("name") for x in r.failed_rows("plan")]
        why = self.answers_reason()
        redo = r.state.get("redo") if isinstance(r.state.get("redo"), dict) else {}
        if (r.verdict("plan") != "FAIL" or "tasks agree with decisions" not in names or not why
                or any(n not in PERSON_ROWS + ("tasks agree with decisions",) for n in names)
                or redo.get("stage") == "plan" and same_failure(str(redo.get("reason") or ""), why)):
            return None
        return {"action": "work", "stage": "plan", "calls": [self.c("state redo plan --reason %s" % shlex.quote(why))], "agents": [],
                "say": "Plan: an answer is not the choice the plan assumed; the Plan agent writes the tasks under it."}

    # -- the budget (WP10, ADR 0019 decision 1) --
    def budget_guard(self, out):
        """Never offer a call the budget refuses (scripts/budget.py). An `auto` or `work` action that holds one parks an
        armed run, or asks run.budget; a question that holds one becomes run.budget, which keeps the options that spend
        nothing."""
        r, facts = self.r, budget.Facts(self.r)
        calls_of = lambda o: list(o.get("calls") or []) + list(o.get("steps") or [])
        refused = lambda calls: budget.refused(calls, self.cli, facts)   # the calls of one option or action, in order
        if out.get("action") in ("auto", "work"):
            key = refused(calls_of(out) + [c for a in out.get("agents") or [] for c in (a.get("before") or []) + (a.get("after") or [])])
            if key is None:
                return out
            stage = out.get("stage") or r.stage
            line = budget.count_line(key, r.room(key))
            kept = {k: out[k] for k in ("v", "run", "restart") if k in out}
            if r.armed():
                kept.update({"action": "auto", "stage": stage, "say": "%s: the budget is spent; the armed run parks for you." % LABEL.get(stage, stage),
                             "calls": [self.c("park --verdict PARKED-NEEDS-DECISION --reason %s" % shlex.quote(
                                 "%s: the budget is spent: %s" % (LABEL.get(stage, stage), line)))]})
                return kept
            kept.update({"action": "ask", "stage": stage, "ask": self.budget_question(stage, "%s: its next step repeats a failed check." % LABEL.get(stage, stage), key, [])})
            return kept
        q = out.get("ask") if out.get("action") == "ask" else None
        if not isinstance(q, dict):
            return out
        shown = list(q.get("options") or []) + list((q.get("more") or {}).get("options") or [])
        subs = [s for s in (q.get("accept"), q.get("change")) if isinstance(s, dict)]
        every = shown + [o for s in subs for o in s.get("options") or []]
        key = next((k for o in every for k in [refused(calls_of(o))] if k), None)
        if key is None:
            return out
        free = [self.set_rec(copy.deepcopy(o), False) for o in shown if o.get("kind") != "more" and o.get("id") != "save"
                and not any(budget.key_in(c, self.cli, facts) for c in calls_of(o))]
        nq = self.budget_question(q.get("stage") or r.stage, self.first_sentence(q["question"]["question"]), key, free)
        for name, s in (("accept", q.get("accept")), ("change", q.get("change"))):
            if isinstance(s, dict) and any(o.get("kind") == name or o.get("id") == name for o in free):
                s = self.rehome(copy.deepcopy(s), q["id"], "run.budget")
                s["options"] = [o for o in s["options"] if not refused(calls_of(o))]
                s["question"]["options"] = [{"label": o["label"], "description": o["description"]} for o in s["options"]]
                nq[name] = s
        out["ask"] = nq
        return out

    def budget_question(self, stage, first, key, free):
        """run.budget: the stage's first sentence, the count, then Save for later (recommended), Allow two more (the
        person's grant), and the options of the stage's question that spend nothing."""
        rm = self.r.room(key)
        line = budget.count_line(key, rm)
        if rm["used"] >= rm["limit"]:
            line += ": " + ", ".join(budget.kinds(key, budget.Facts(self.r)))
        grant = self.opt("Allow two more", "Two more repeats for %s and for the run; `temper budget` shows your reason." % budget.what(key),
                         move="grant", calls=[self.c("budget grant --key %s --reason '{reason}'" % key)],
                         reason=["The next try is different", "I changed something outside the run"], oid="grant-more")
        return self.question(GATE_HEADER, "%s %s. Save the run for later, or allow two more?" % (first, line),
                             [self.set_rec(self.save(), True), grant] + free, stage, qid="run.budget")

    @staticmethod
    def first_sentence(text):
        """The text up to its first full stop or question mark outside parentheses."""
        depth = 0
        for i, ch in enumerate(text):
            depth += {"(": 1, ")": -1}.get(ch, 0)
            if ch in ".?" and depth <= 0 and (i + 1 == len(text) or text[i + 1] in " \n"):
                return text[:i] + "."
        return text.rstrip(".?") + "."

    @staticmethod
    def rehome(obj, old, new):
        """A follow up question moved under another question: its ids and those of its reason and name questions."""
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k == "id" and isinstance(v, str) and (v == old or v.startswith(old + ".")):
                    obj[k] = new + v[len(old):]
                else:
                    Builder.rehome(v, old, new)
        elif isinstance(obj, list):
            for v in obj:
                Builder.rehome(v, old, new)
        return obj

    def add_note(self, out):
        """9.8.5 (U2): the orchestrator's note for the question of this step (`temper state set ask_note '<step>: <text>'`),
        added to the CLI's own question text and marked as Claude's, so the person reads the facts above the dialog in it.
        A note of another step is not shown. It changes no option."""
        r = self.r
        m = re.match(r"^\s*(\d+):\s*(\S.*)$", str(r.state.get("ask_note") or ""), re.S)
        q = (out.get("ask") or {}).get("question") if out.get("action") == "ask" else None
        if not m or not isinstance(q, dict) or int(m.group(1)) != r.state.get("step"):
            return
        note = " ".join(m.group(2).split())[:600]
        q["question"] = "%s\n\nNote from Claude (not from Temper): %s" % (q["question"], note)

    def core_next(self):
        r = self.r
        if not r.active:
            # WP17: after a trivial request the one line says what the person has: an uncommitted change, held to the
            # bound
            return {"v": VERSION, "action": "none", "run": None, "say": trivial.say() or "No run is active."}
        out = {"v": VERSION, "run": self.run_info(), "restart": self.restart()}
        if r.stage not in r.seq() or (r.stage not in ("intent", "rca") and r.spec and not os.path.isdir(r.spec)):
            out.update({"action": "broken", "say": "The run state does not fit its spec folder (%s at %s)." % (r.spec, r.stage)})
            return out
        if isinstance(r.state.get("trivial"), dict) and r.stage == "intent" and r.verdict("intent") is not None:
            # WP17: the Intent agent took the trivial verdict and made the one change; the flow closes the run, no
            # question
            out.update({"action": "auto", "stage": "intent", "calls": [self.c("intent trivial --close")],
                        "say": "Intent: the request is trivial (%s); the run closes, and the change is left for you to commit."
                        % r.state["trivial"].get("why")})
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
        drift = self.drift_next(stage) if stage in ("build", "fix") else None
        if drift is not None:
            out.update(drift)
            return out
        if stage == "build" and r.command == "temper":
            fb = self.foreign_branch()
            if fb is not None:
                out.update(fb)
                return out
        if r.command == "fix" and stage == "rca":
            # WP17: the root cause question is the approval; a change the person typed there runs the agent again first
            out.update(self.rca_work() or {"action": "ask", "stage": stage, "ask": self.rca_approval()})
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
            redo = self.answers_redo()
            if redo:
                out.update(redo)
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
        # WP11 (ADR 0019 decision 3): a run that goes on by itself, at a stage with a verdict. The Design stops stay; a
        # passed check moves on as the CLI's own action; a failed Build, Design or Fix stops; Review and Check go by the
        # closed list of rule_move. A stop is the park call: the stage then asks its own question (`parked` ends armed).
        if r.armed() and stage in ("design", "build", "fix", "review", "check"):
            nxt = r.next_of(stage)
            if stage == "design" and r.tasks_changed():
                out.update(self.stop(stage, "Design changed the plan's tasks; the person approves them"))
                return out
            if stage == "design" and r.open_concerns():
                # a person resolves each area of concern at the Design question, before Build
                out.update(self.stop(stage, "Design has %d open area(s) of concern" % len(r.open_concerns())))
                return out
            if stage in ("review", "check"):
                out.update(self.rule_move(stage, verdict))
                return out
            if verdict == "PASS" or skipped:
                out.update({"action": "auto", "stage": stage, "calls": [self.c("state advance %s_complete %s" % (stage, nxt))],
                            "say": "%s passed; the run goes on to %s." % (LABEL[stage], LABEL.get(nxt, nxt))})
                return out
            why = "; ".join("%s: %s" % (x.get("name"), x.get("detail")) for x in r.failed_rows(stage))[:200]
            out.update(self.stop(stage, "the check failed: %s" % why))
            return out
        if stage == "intent" and self.intent_by_rule():
            # WP13: the run leaves Intent as the CLI's own action; the person accepts the intent with the plan, at the
            # approval. A `work` with calls and no agents, never an `auto` (the mod draws an auto as an armed run).
            out.update({"action": "work", "stage": stage, "calls": [self.c("state advance intent_complete plan")], "agents": [],
                        "say": "Intent: the check passed and nothing is open. The run goes on to Plan; you accept the intent "
                               "with the plan, in one question."})
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
    trivial.spent()   # WP17: a trivial record whose head is not HEAD any more holds nothing
    run = Run(ctx)
    project_facts(run, ctx)
    try:
        nxt = Builder(run).next()
    except Exception as e:  # the view still says where the run is; it never stays behind the run
        nxt = {"action": "error", "say": "temper next failed: %s" % e}
    doc = view(run, nxt)
    doc["written"] = ctx.get("now")
    if ctx.get("asked"):   # the view of `temper next`: its question is the one the carrier is handed (run summary)
        try:
            run_summary.record_ask(TEMPER, nxt)
        except (OSError, ValueError, TypeError, AttributeError):
            pass   # the count of the summary never stops a view
    write_view(doc)

if __name__ == "__main__":
    sys.exit(main(sys.argv))
