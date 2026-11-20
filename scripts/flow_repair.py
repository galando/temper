"""flow_repair.py: RepairPart of Builder: a finding repaired in its stage (9.8.5, WP24, ADR 0021).

What comes next while a repair runs: what it asks (repair.stop, scope.drift), the fixer, the recheck or the full Review,
and the CLI's own `repair start` when scripts/repair_ops.py can_start holds. A module of the flow; scripts/flow.py is its
facade. Standard library only.
"""

import os
import re
import shlex

import failure
import repair_ops

from flow_base import (DRIFT_HEADER, DRIFT_IDS, DRIFT_OPTIONS, DRIFT_PREFIX, GATE_HEADER, LABEL, TEMPER, goes_on, on_model,
                       read_json)

DRIFT_SAYS = {"Add to plan": "The file joins the plan; the CLI commits the repair with it.",
              "Revert": "The repair is taken back: the work tree goes back to the tree Review read.",
              "Allow once": "The CLI commits the repair with this file, this once."}


class RepairPart:
    def repair_step(self, stage):
        """The repair in the stage, in every mode, before the rule's move and before the question: what a repair asks
        (repair.stop, scope.drift; in a run that goes on by itself the park first), the fixer while the window is open,
        the recheck (or the full Review) once the CLI committed it, and the CLI's own `repair start` whenever
        scripts/repair_ops.py can_start holds. None when no repair applies."""
        r = self.r
        d = r.state
        st = d.get("repair_stop") if isinstance(d.get("repair_stop"), dict) else None
        if st and st.get("stage") in (None, stage):
            if r.armed():
                return self.stop(stage, "repair %s: %s" % (st.get("n"), st.get("why")))
            return {"action": "ask", "stage": stage, "ask": self.repair_question(stage, st)}
        w = d.get("repair") if isinstance(d.get("repair"), dict) else None
        if w and w.get("stage") == stage:
            if not w.get("commit"):
                return self.repair_work(w)
            if w.get("recheck") == "none":
                gate = self.c("gate %s" % stage)
                return {"action": "auto", "stage": stage, "calls": [self.c("repair close"), gate],
                        "say": "%s: repair %s changed test files alone, so no reader rechecks it; the CLI closes it." % (LABEL[stage], w["n"])}
            return self.recheck_work(w)
        if repair_ops.can_start(r, stage) is None:
            what = "; ".join(f["claim"][:100] for f in r.open_findings()[:2]) if stage == "review" else "; ".join(
                str(x.get("name")) for x in r.failed_rows(stage))
            return {"action": "auto", "stage": stage, "calls": [self.c("repair start --stage %s" % stage)],
                    "say": "%s: the rule repairs it in the stage (%s): a fresh Build agent fixes it, the CLI commits and checks it, "
                           "and a reader rechecks it." % (LABEL[stage], what[:160])}
        return None

    def repair_work(self, w):
        """The fixer: a fresh Build agent with the whole finding (or the failed row with its whole kept output), the open
        findings it must not touch, and the line `Repair in place:`. It commits nothing; its after call is the CLI's
        `repair commit`."""
        r = self.r
        stage = w["stage"]
        rows = read_json(os.path.join(TEMPER, "evidence", "review.json"), [])
        lines = ["Repair in place: repair %s at %s. Fix exactly what is named below and nothing else, in the files of the plan; "
                 "commit nothing (the CLI commits and runs the checks again); change no locked acceptance test; never accept, "
                 "override or skip. When the fix needs the plan or the intent changed, stop and say so." % (w["n"], LABEL[stage])]
        for fid in w.get("findings") or []:
            e = rows[fid - 1] if 0 < fid <= len(rows) and isinstance(rows[fid - 1], dict) else {}
            claim = str(e.get("claim") or "")
            proof = "test" if str(e.get("proof") or "none") == "test" else "none"
            lines.append("Finding #%d [%s]: %s" % (fid, e.get("severity"), claim))
            lines.append("Detail: %s" % (e.get("detail") or claim))
            if e.get("fix"):
                lines.append("Suggested fix: %s" % e["fix"])
            lines.append("The finding's proof: test: a behaviour defect. Write the failing test first and run `temper repair test %d "
                         "--phase red -- <command>`, then the code, then the same call with --phase green." % fid if proof == "test" else
                         "The finding's proof: none: no new test is asked; the recheck reads the fix.")
        if stage == "check":
            ledger = read_json(os.path.join(TEMPER, "evidence", "check.json"), [])
            for x in r.failed_rows(stage):
                lines.append("Failed row: %s: %s" % (x.get("name"), " ".join(str(x.get("detail") or "").split())))
            for rec in failure.open_records(scope="gate:check"):
                m = re.match(r"^check#(\d+)$", str(rec.get("row") or ""))
                row = ledger[int(m.group(1))] if m and int(m.group(1)) < len(ledger) and isinstance(ledger[int(m.group(1))], dict) else {}
                lines.append("Failure record %s (%s, %s): %s%s" % (rec.get("id"), rec.get("class"), rec.get("check"), rec.get("why"),
                             "; the kept output:\n%s" % str(row.get("output")).rstrip() if row.get("output") else
                             "; failing lines: %s" % " | ".join(rec.get("fail_lines") or [])))
            lines.append("No new failing test is asked here: the CLI's failed row is the RED, and the same check must pass on the new tree.")
        others = [f for f in r.findings() if f["state"] == "open" and f["id"] not in (w.get("findings") or [])]
        if others:
            lines.append("Open findings this repair must not touch: %s." % "; ".join(f["claim"][:160] for f in others[:5]))
        a = self.agent("build", lines)
        a["after"].append(self.c("repair commit"))
        return {"action": "work", "stage": stage, "calls": [], "agents": [a],
                "say": "%s: repair %s: a fresh Build agent fixes it in the stage%s. %s" % (LABEL[stage], w["n"], on_model([a]), goes_on(False))}

    def recheck_work(self, w):
        """The narrow recheck of a repair (the section Re-check: of agents/review.md), or a full Review when the diff is over
        300 changed lines or touches a file no finding names. Its before call is the CLI's launch mark: only rows written
        after it count. Its after calls close the repair and compute the gates again."""
        r = self.r
        stage = w["stage"]
        rows = read_json(os.path.join(TEMPER, "evidence", "review.json"), [])
        mine = [(fid, rows[fid - 1]) for fid in w.get("findings") or [] if 0 < fid <= len(rows) and isinstance(rows[fid - 1], dict)]
        answer = ("Record `recheck #<id>: fixed` (--exit 0) or `recheck #<id>: not fixed` (--exit 1) for each finding of the repair, "
                  "with --cmd recheck")
        g = read_json(os.path.join(TEMPER, "gates.json"), {})
        results = "integration %s; Build gate %s%s" % ((r.groups.get("integration") or {}).get("verdict") or "not run",
                                                        (g.get("build") or {}).get("verdict") or "none",
                                                        "; Check gate %s" % (g.get("check") or {}).get("verdict") if stage == "check" else "")
        found = "; ".join("#%d [%s] %s (detail: %s)" % (fid, e.get("severity"), e.get("claim"), e.get("detail") or e.get("claim"))
                          for fid, e in mine) or "none: the failed rows %s" % ", ".join(w.get("rows") or [])
        if w.get("recheck") == "full":
            a = self.agent("review", ["Repair %s at %s (commit %s) changed %s line(s) in %s: more than a narrow recheck reads, so "
                                      "Review reads the whole change again." % (w["n"], LABEL[stage], str(w.get("commit"))[:7],
                                                                               w.get("lines"), ", ".join(w.get("files") or [])),
                                      "%s: %s." % (answer, found)])
            say = "%s: repair %s changed more than a recheck reads; a full Review reads the change%s. %s"
        else:
            models = r.ctx.get("models") or {}
            others = [f for f in r.findings() if f["state"] == "open" and f["id"] not in (w.get("findings") or [])]
            lines = ["Follow %s/agents/review.md exactly." % self.plugin, "Spec path: %s." % r.spec,
                     "Re-check: repair %s at %s, commit %s. Read only the diff %s/repair-%s.diff (from the reviewed HEAD to the "
                     "repair commit) and answer three questions, no other lens: is each finding fixed; did the changed lines add "
                     "a defect; was a test weakened or removed." % (w["n"], LABEL[stage], str(w.get("commit"))[:7], r.spec, w["n"]),
                     "Findings this repair answers: %s." % found,
                     "Findings still open, not this repair's: %s." % ("; ".join("[%s] %s" % (f["severity"], f["claim"][:160]) for f in others) or "none"),
                     "The CLI's results on the new tree: %s." % results,
                     "%s; a new finding only on a changed line; then one row `review completed` with --cmd recheck, --value <the "
                     "count of ids checked> and one --read for each changed file: %s." % (answer, ", ".join(w.get("files") or [])),
                     self.plugin_line()]
            a = {"type": "temper:temper-review", "model": models.get("review", ""), "prompt": "\n".join(lines),
                 "after": [self.c("usage add --stage review --model %s --ms {ms}" % (models.get("review", "") or "unknown"))]}
            say = "%s: repair %s is committed and checked; a reader that did not write it rechecks the diff%s. %s"
        # the launch mark only: the CLI ran the suite on the repair tree already, and `check ahead` runs in the
        # background, where it would race the CLI's own revert commit on git's index
        a["before"] = [self.c("repair mark")]
        a["after"] = a["after"] + [self.c("repair close"), self.c("gate review")] + ([self.c("gate check")] if stage == "check" else [])
        a["gate"] = a["after"][-1]
        return {"action": "work", "stage": stage, "calls": [], "agents": [a],
                "say": say % (LABEL[stage], w["n"], on_model([a]), goes_on(False))}

    def repair_question(self, stage, st):
        """What a repair asks: scope.drift for a file a repair may not commit, repair.stop for anything else (a diff that
        removes test lines, a repair reverted as worse, one that changed nothing, a commit the CLI did not make)."""
        r = self.r
        kind = st.get("kind")
        n, path = st.get("n"), st.get("path") or ""
        revert = [self.c("repair revert")]
        # the options of the repair's own answers: (label, description, move, calls, id)
        if kind == "drift":
            plan = "outside the approved file set" in str(st.get("why"))
            note = lambda label: [self.c("evidence add --stage build --phase feedback --claim %s" % shlex.quote(
                "drift %s: %s: repair %s" % (path, label, n))), self.c("repair commit")]
            own = [(label, DRIFT_SAYS[label], "drift", revert if label == "Revert" else note(label), ids["id"])
                   for label, ids in zip(DRIFT_OPTIONS, DRIFT_IDS) if plan or label == "Revert"]
        elif kind == "tests":
            own = [("Revert the repair (Recommended)", "The work tree goes back to the tree Review read; the finding stays open.",
                    "redo", revert, "revert-repair")]
        else:
            own = []
        opts = [self.opt(label, desc, move=move, calls=calls, oid=oid) for label, desc, move, calls, oid in own]
        back = self.loop_opt(stage, "build", rec=kind not in ("tests", "drift"))
        opens = [f for f in r.findings() if f["state"] == "open"] if stage == "review" and kind not in ("tests", "drift") else []
        if kind == "drift":
            header, qid, more = DRIFT_HEADER, "scope.drift", []
            if not plan:
                opts = [self.set_rec(opts[0], True)]
            first = opts + ([] if plan else [self.save()])
            text = "%s %s\nWhy: %s\nChange: repair %s at %s; nothing is committed, and the change stays in the work tree." % (
                DRIFT_PREFIX, path, st.get("why"), n, LABEL[stage])
        elif kind == "tests":
            header, qid, more = GATE_HEADER, "repair.stop", []
            first = opts + [back, self.save()]
            text = "%s: repair %s removes lines of a test file that existed at the reviewed HEAD, so the rule never resolves it:\n%s\nRevert the repair?" % (
                LABEL[stage], n, "\n".join(str(x) for x in (st.get("lines") or [])[:8]))
        else:
            header, qid = GATE_HEADER, "repair.stop"
            rep = repair_ops.offer(r, stage)
            first = [back] + ([self.repair_opt(stage, False)] if rep is not None else []) + ([self.accept_opt()] if opens else [])
            more = first[3:] + [self.override_opt(stage, [self.c("state advance %s_complete %s" % (stage, r.next_of(stage)))]), self.save()]
            first = first[:3]
            text = "%s: %s. Loop back to Build?" % (LABEL[stage], str(st.get("why")).rstrip("."))
        q = self.with_more(header, text, stage, first, more, "%s: more options." % LABEL[stage], qid=qid)
        if opens:
            q["accept"] = self.accept_question(opens, qid="repair.stop.accept")
        return q
