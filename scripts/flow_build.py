"""flow_build.py: BuildPart of Builder: the grouped Build, its chains, its failed groups and its parked runs.

A module of the flow; scripts/flow.py is its facade. Standard library only.
"""

import os
import re
import shlex

import fresh_review
import tasks_md

from flow_base import GATE_HEADER, GROUP_HEADER, choice_id, git, goes_on, on_model, scoped_notes, short_model


class BuildPart:
    @staticmethod
    def chain_of(plan, rt, first, ready):
        """The tasks one agent builds in order, starting at a ready task: each next task of the same group that waits only
        on this chain (its dependencies passed or in the chain, and it depends on the chain or shares a file with it), and
        clashes with no other ready or running task. Independent tasks are never pulled in, so they stay parallel."""
        tasks = sorted([t for t in plan.get("tasks", []) if t.get("group") == first.get("group")], key=lambda t: t["n"])
        files = {t["n"]: {f.strip().lstrip("./") for f in t.get("files", [])} for t in plan.get("tasks", [])}
        deps = {t["n"]: set(t.get("depends", [])) for t in plan.get("tasks", [])}
        status = lambda n: (rt.get(str(n)) or {}).get("status", "pending")
        # Only a pending task joins a chain: a failed one (also STARTABLE in tasks_md) is retried alone, on the model its
        # attempt number gives, never on the chain's.
        others = {x["task"] for x in ready if x["task"] != first["task"]} | {int(n) for n, v in rt.items() if isinstance(v, dict) and v.get("status") == "running"}
        chain = [first["task"]]
        grew = True
        while grew:
            grew = False
            mine = set().union(*(files.get(n, set()) for n in chain))
            for t in tasks:
                n = t["n"]
                if n in chain or n in others or status(n) not in ("pending",):
                    continue
                if not all(d in chain or status(d) == "passed" for d in deps.get(n, set())):
                    continue
                if not (deps.get(n, set()) & set(chain) or files.get(n, set()) & mine):
                    continue
                if any(files.get(n, set()) & files.get(o, set()) for o in others):
                    continue
                chain.append(n)
                grew = True
                break
        return chain

    def review_notes(self):
        """9.8.4: the fresh review's open medium and low findings, as notes for the task each names ({task: [claim]}). They
        do not block the plan gate; the builder of the task reads them."""
        out = {}
        try:
            found = self.r.fresh().get("findings") or []
        except Exception:
            return out
        for f in found:
            if f.get("severity") in fresh_review.BLOCKING or f.get("state") in ("resolved", "accepted"):
                continue
            for n in {int(x) for x in re.findall(r"\bTask\s+(\d+)\b", f.get("claim") or "")}:
                out.setdefault(n, []).append(" ".join(str(f["claim"]).split())[:240])
        return out

    def task_model(self):
        """The model of a Build task: the one `temper next` resolved (cli_ctx.resolve: the config, else sonnet for a complex
        or risk H plan, else the brief's), and the same rule when it resolved none (9.8.4: it was haiku for any plan)."""
        import cli_ctx
        return self.r.ctx.get("task_model") or (cli_ctx.RISK_TASK_MODEL if (
            str(self.r.state.get("complexity") or "").lower() == "complex" or str(self.r.state.get("risk") or "").upper() == "H") else "haiku")

    def ran_on(self, task):
        """The model of the running attempt: the one task start recorded, else (a run started before it did) the one the
        attempt number gives, the task model for the first two attempts and the escalation model after."""
        if task.get("model"):
            return task["model"]
        task_model = self.task_model()
        esc = self.r.ctx.get("escalation_model") or "sonnet"
        return task_model if int(task.get("attempt") or 1) <= 2 else esc

    def no_groups(self):
        """tasks.md has tasks and no group: Build stops before any group starts, with no agent."""
        r = self.r
        text = "Build stopped: tasks.md has tasks but no groups, so Build cannot run them in isolated groups."
        opts = []
        if r.can_loop("build", "plan"):
            opts.append(self.opt("Run Plan again (Recommended)", "Plan writes the tasks in groups.", move="back",
                                 calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The tasks have no groups"], oid="back"))
            text += " Run Plan again to write the tasks in groups."
        else:
            text += " Plan has run again already: write the groups by hand in tasks.md, or save the run."
        opts.append(self.save())
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=opts, qid="build.ungrouped")}

    def build_work(self):
        """Grouped Build, computed: start groups, hand out ready tasks, gate tasks and groups, integrate."""
        r = self.r
        plan = r.plan or {"groups": [], "tasks": []}
        if plan.get("tasks") and not plan.get("groups"):
            return self.no_groups()
        acc = self.acceptance_work()
        if acc:
            return acc
        rg = r.groups.get("groups") or {}
        rt = r.groups.get("tasks") or {}
        integ = (r.groups.get("integration") or {}).get("verdict")
        gid = [g["id"] for g in plan.get("groups", [])]

        # A group passed is its gate's PASS, the CLI's verdict; its `status` is the CLI's record of the same (passed iff
        # the gate is PASS) and is read here only for `parked`, which no gate sets. So a status left behind by an older
        # write never decides what comes next (tasks_md.schedule reads the gate the same way).
        def gpass(g):
            return ((rg.get(g) or {}).get("gate") or {}).get("verdict") == "PASS"

        # the fix pass: the groups are integrated, so Build mends what a step back or "Run Build again" names. A door's
        # run whose code an earlier run built (built_before, from the walked Build's check) mends it the same way.
        before = r.state.get("built_before") and not rg
        if (integ and gid and all(gpass(g) for g in gid)) or before:
            lines = self.feedback_lines() + self.fault_lines()   # M1: the finding and what failed since
            if not lines and not r.notes("build", "input"):
                # 9.8.5 (S7): a fix pass with no fault in its prompt fixes nothing (a measured launch said so): the CLI
                # checks Build again, and a failure there names the fault for the next pass
                return {"action": "auto", "stage": "build", "calls": ([self.c("integrate")] if integ and not before else []) + [self.c("gate build")],
                        "say": "Build: nothing names a fault to fix, so the CLI checks Build again first."}
            a = self.agent("build", lines)
            # 9.8.4: the CLI runs the scenario tests on the fixed tree (integrate does when the groups are merged already),
            # so no record pass of a model is needed after a step back that cleared Build's rows
            if integ and not before:
                a["after"].append(self.c("integrate"))
            a["after"].append(self.c("gate build"))
            a["gate"] = a["after"][-1]
            return {"action": "work", "stage": "build", "calls": [], "agents": [a], "say": "Build: the fix pass is working%s. %s" % (on_model([a]), goes_on(False))}

        run = []
        if not r.state.get("base_sha") and r.ctx.get("head"):
            run.append(self.c("state set base_sha %s" % r.ctx.get("head")))
        # build.grouped.max-groups groups work at once (default 2; anything but a whole number of at least 1 means 2)
        mg = r.cfg("build.grouped.max-groups", "2")
        room = (int(mg) if re.fullmatch(r"[1-9][0-9]*", mg) else 2) - sum(
            1 for g in plan.get("groups", []) if (rg.get(g["id"]) or {}).get("worktree") and not (rg.get(g["id"]) or {}).get("confirmed"))
        for g in plan.get("groups", []):
            started = bool((rg.get(g["id"]) or {}).get("worktree"))
            # A group that builds on another starts after the person's Continue of it, not on its check alone: a Change
            # there reruns work this group would build on.
            if not started and room > 0 and all(gpass(d) and (rg.get(d) or {}).get("confirmed") for d in g.get("depends", [])):
                run.append(self.c("group start %s" % g["id"]))
                room -= 1
        if run:
            return {"action": "work", "stage": "build", "calls": run, "agents": [], "say": "Build starts its groups."}

        try:
            mx = int(r.cfg("build.grouped.max-parallel", "4"))
        except ValueError:
            mx = 4
        sched = tasks_md.schedule(plan, r.groups, mx if mx > 0 else 4, self.task_model(),
                                  r.ctx.get("escalation_model") or "sonnet", os.getcwd()) if plan.get("tasks") else []
        ready = [x for x in sched if "task" in x]
        if ready:
            agents = []
            build_notes = r.notes("build", "input")
            # 9.8.0: one agent per chain. The tasks that would run one after another anyway (each depends on the one before,
            # or shares a file with it) go to one agent, which starts, builds and gates each in order (agents/build-task.md);
            # independent tasks still get agents of their own, launched at once. Each task keeps its worktree, its RED run,
            # its CLI gate and its retry. In measured runs every task ran alone, each paying a launch and its orchestration.
            review_notes = self.review_notes()
            for t in ready:
                chain = self.chain_of(plan, rt, t, ready)
                said = "".join("\nPerson's note: %s" % x for n in chain for x in scoped_notes(build_notes, n, t.get("group")))
                said += "".join("\nPlan review note: %s" % x for n in chain for x in review_notes.get(n, []))
                tasks_line = ("Task: %d." % t["task"]) if len(chain) == 1 else (
                    "Tasks: %s (a chain: do them in this order; start, build and gate each before the next)." % ", ".join(str(n) for n in chain))
                agents.append({"type": "temper:temper-build-task", "model": t.get("agent_model") or self.task_model(),
                               "before": [self.c("task start %d" % t["task"])],
                               "prompt": "Follow %s/agents/build-task.md exactly.\n%s\n%s%s%s%s\nModel: %s." % (
                                   self.plugin, self.plugin_line(), tasks_line, said, self.acceptance_line(), self.decisions_line(), t.get("model")),
                               # the first task's gate judges the agent; the others it gated itself (a task it left running is gated here)
                               "after": [self.c("usage add --stage build --model %s --ms {ms} --task %d" % (t.get("model"), t["task"]))] +
                                        [self.c("task gate %d --model %s --if-running" % (n, t.get("model"))) for n in chain] +
                                        # the CLI draws each task's panel from what it recorded; the agent returns one line a task
                                        [self.c("panel task %s" % " ".join(str(n) for n in chain))],
                               "task": t["task"], "tasks": chain, "group": t.get("group"), "title": t.get("title"), "attempt": t.get("attempt")})
            return {"action": "work", "stage": "build", "calls": [], "agents": agents,
                    "say": "Build: %s. %s" % (", ".join(("Task %d" % x["task"] if len(x["tasks"]) == 1 else "Tasks %s" % ", ".join(str(n) for n in x["tasks"])) + " on " + short_model(x["model"]) for x in agents), goes_on(len(agents) > 1))}

        running = [(int(n), v) for n, v in rt.items() if isinstance(v, dict) and v.get("status") == "running"]
        covered = sorted(int(n) for n, v in rt.items() if isinstance(v, dict) and v.get("status") == "covered")
        if covered:
            return self.covered_task(covered[0], plan, rt.get(str(covered[0])) or {})
        on_env = sorted(n for n, v in running if v.get("env_fault"))
        if on_env:
            return self.env_task(on_env[0], plan, rt.get(str(on_env[0])) or {})
        waiting_on_person = sorted(n for n, v in running if v.get("awaiting") == "confirm")
        if waiting_on_person:
            return self.manual_task(waiting_on_person[0], plan)
        if running:
            return {"action": "wait", "stage": "build", "tasks": [
                {"task": n, "model": self.ran_on(v), "after": [self.c("task gate %d --model %s --ms {ms}" % (n, self.ran_on(v))),
                                                                 self.c("panel task %d" % n)]}
                for n, v in sorted(running)],
                "say": "Build: %s. %s" % (", ".join("Task %d runs on %s" % (n, short_model(self.ran_on(v))) for n, v in sorted(running)), goes_on(len(running) > 1))}

        for g in gid:
            st = (rg.get(g) or {}).get("status")
            if st == "parked":
                return self.parked(g)
        for g in plan.get("groups", []):
            gidx = g["id"]
            ginfo = rg.get(gidx) or {}
            tasks = g.get("tasks", [])
            done = tasks and all(tasks_md.task_done(t, r.groups) for t in plan.get("tasks", []) if t.get("n") in tasks)
            gate = (ginfo.get("gate") or {}).get("verdict")
            if done and not gate:
                return {"action": "work", "stage": "build", "calls": [self.c("group gate %s" % gidx)], "agents": [], "say": "Group %s is checked." % gidx}
            if gate == "FAIL" and ginfo.get("fix") and (not r.armed() or r.policy()):   # M3 of WP08: the policy launches it too
                return self.group_fix_work(g, ginfo)
            if gate == "FAIL":
                return self.group_failed(g, ginfo)
            if gate == "PASS" and not ginfo.get("confirmed"):
                if r.armed():
                    return {"action": "auto", "stage": "build", "calls": [self.c("group continue %s" % gidx)], "say": "Group %s passed; the armed run goes on." % gidx}
                # 9.8.0: a plan with one group goes on to the merge by itself: the Build question comes right after, and
                # its "Change something" sends work back. Two questions in a row about the same work were one too many.
                if len(plan.get("groups", [])) == 1:
                    return {"action": "auto", "stage": "build", "calls": [self.c("group continue %s" % gidx)],
                            "say": "Group %s passed; the merge and the Build check come next." % gidx}
                return {"action": "ask", "stage": "build", "ask": self.group_question(g)}
        if gid and all(gpass(g) and (rg.get(g) or {}).get("confirmed") for g in gid):
            return {"action": "work", "stage": "build", "calls": [self.c("integrate"), self.c("gate build")], "agents": [],
                    "say": "Every group passed: the groups are merged and Build is checked."}
        return {"action": "work", "stage": "build", "calls": [self.c("gate build")], "agents": [], "say": "Build is checked."}

    def foreign_branch(self):
        """`temper integrate` found commits the CLI did not make on a passed group's branch: the person takes them out
        or keeps them (an armed run parks for them). None when there are none."""
        r = self.r
        integ = r.groups.get("integration") or {}
        foreign = integ.get("foreign") if integ.get("verdict") == "FAIL" else None
        if not isinstance(foreign, dict) or not foreign:
            return None
        again = [self.c("integrate"), self.c("gate build")]
        branches = (r.groups.get("groups") or {})
        left = {}
        for g in sorted(foreign):
            # A commit the person kept already (an override) or one no longer on the group's branch is no question: the
            # next integrate reads the branch again.
            kept = {str(o.get("stage", "")).split(":", 2)[2] for o in r.overrides
                    if isinstance(o, dict) and str(o.get("stage", "")).startswith("foreign-commit:%s:" % g)}
            on = set(git("rev-list", "temper/%s/%s" % (r.slug, g)).split())
            shas = [x for x in foreign.get(g) or [] if isinstance(x, str) and x not in kept and (not on or x in on)]
            if shas:
                left[g] = shas
        if not left:
            # Asked, never run unattended: integrate leaves its record as it is when it stops early (another branch, a
            # protected one), and running it again unasked would go round with no one told why.
            if r.armed():
                return {"action": "auto", "stage": "build",
                        "calls": [self.c("park --verdict PARKED-NEEDS-DECISION --reason %s" % shlex.quote("the groups are to be merged again after the commits the CLI did not make were kept or taken out"))],
                        "say": "The armed run parks for you before the groups are merged again."}
            return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER,
                    "The commits the CLI did not make are kept or taken out. Merge the groups again?", stage="build", qid="build.foreign", options=[
                        self.opt("Merge the groups (Recommended)", "Merge the passed groups again and check Build.", move="redo", calls=again, oid="merge-groups"),
                        self.save()])}
        gid = sorted(left)[0]
        shas = left[gid]
        csv = ",".join(x[:7] for x in shas)
        if r.armed():
            return {"action": "auto", "stage": "build",
                    "calls": [self.c("park --verdict PARKED-NEEDS-DECISION --reason %s" % shlex.quote("group %s's branch holds commits the CLI did not make: %s" % (gid, csv)))],
                    "say": "Group %s holds commits the CLI did not make; the armed run parks for you." % gid}
        wt = (branches.get(gid) or {}).get("worktree") or ""
        # They are taken out newest first, each one by a rebase of the group's worktree onto its parent. Only when they
        # are the newest commits of that branch: a rebase would write the CLI's own commits above them again, as commits
        # the CLI did not make. Never with no worktree (`git -C ''` is the project's own branch).
        tip = git("-C", wt, "rev-list", "--first-parent", "-n", str(len(shas)), "HEAD").split() if wt and os.path.isdir(wt) else []
        out = []
        if tip and set(tip) == set(shas):
            out.append(self.opt("Take the commits out (Recommended)", "Remove them from the group's branch, newest first; the groups are merged again.", move="redo",
                                calls=["git -C %s rebase --autostash --onto %s~1 %s" % (shlex.quote(wt), x[:7], x[:7]) for x in shas] + again, oid="take-out"))
        out += [self.opt("Keep the commits", "Keep them knowingly, with your reason (recorded like a skip).", move="keep",
                         calls=[self.c("group reopen %s --accept-foreign %s --reason '{reason}'" % (gid, csv))] + again,
                         reason=["The commits are right", "I accept the risk"], oid="keep-commits"),
                self.save()]
        if len(out) == 3:
            text = "Group %s's branch holds commits the CLI did not make (%s). Take them out, or keep them?" % (gid, csv)
        else:
            why = ("its worktree is gone" if not (wt and os.path.isdir(wt)) else
                   "they are not the newest commits of the group's branch")
            text = ("Group %s's branch holds commits the CLI did not make (%s); %s, so they cannot be taken out here. "
                    "Keep them, or save the run and take them out by hand?" % (gid, csv, why))
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=out, qid="build.foreign")}

    def covered_task(self, n, plan, info):
        """A task whose tests passed before any change: an earlier task built it. The person decides; nothing retries it."""
        r = self.r
        title = next((x.get("title", "") for x in plan.get("tasks", []) if x["n"] == n), "")
        c = info.get("covered") or {}
        if r.armed():
            # 9.8.0: an unattended run takes a covered task as done (its tests pass, the plan asked for work already done);
            # the reason names it, and the run's report lists it. It parked here before, which ended most unattended runs.
            return {"action": "auto", "stage": "build", "calls": [self.c("task accept %d --reason %s" % (n, shlex.quote(
                "An earlier task built it (unattended run)")))],
                "say": "Task %d's tests already pass: an earlier task built it, so the unattended run takes it as done." % n}
        tail = " ".join(str(c.get("tail", "")).split())[:300]
        text = "Task %d (%s): its tests already pass before any change, so an earlier task built it. The RED run %s passed (exit 0): %s. Accept it as done?" % (
            n, title, c.get("cmd") or "(no command)", tail or "no output")
        # `covered`, not `accept`: accepting a review finding leaves a defect in; this takes work that is done (9.8.0).
        # 9.8.0: the reason is the question's own fact (an earlier task built it), so it is recorded without a second question.
        opts = [self.opt("Accept it as done (Recommended)", "Commit its tests, merge them and tick the task (reason: an earlier task built it).", move="covered",
                         calls=[self.c("task accept %d --reason %s" % (n, shlex.quote("An earlier task built it")))], oid="accept-done"),
                self.opt("Run it again", "The kept worktree goes and a fresh attempt starts.", move="redo", calls=[self.c("task retry %d" % n)], oid="redo")]
        if r.can_loop("build", "plan"):
            opts.append(self.opt("Loop back to Plan", "The plan asks for work that is already done.", move="back",
                                 calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The plan cannot be built"], oid="back"))
        opts.append(self.save())
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=opts, qid="task.covered")}

    def env_task(self, n, plan, info):
        """A task whose GREEN run failed on the environment (a JDK, a database, the setup block), not on its code: it kept
        its attempt and its worktree. The person repairs the environment; the same work is checked again. Asked in every
        mode: an armed run cannot repair a toolchain."""
        title = next((x.get("title", "") for x in plan.get("tasks", []) if x["n"] == n), "")
        why = " ".join(str((info.get("env_fault") or {}).get("reason", "")).split())[:300]
        model = self.ran_on(info)
        text = ("Task %d (%s) failed on the environment, not on its code: %s. Its attempt and its work are kept. "
                "Repair the environment (temper doctor shows it; the setup: block of .claude/temper.config applies it), "
                "then check it again?" % (n, title, why or "no reason recorded"))
        again = self.opt("Check it again (Recommended)", "Run the task's test again on the kept work and gate it; no attempt is spent.",
                         move="redo", calls=[self.c("task test %d --phase green" % n), self.c("task gate %d --model %s" % (n, model))], oid="redo")
        # M9: the fault may be the code's (a bug that prints Connection refused): the gate reads the failed GREEN it has
        code = self.opt("It is the code", "Send the task back to its agent: the attempt is spent, as a failed test spends it.",
                        move="redo", calls=[self.c("task gate %d --model %s --no-env" % (n, model))], oid="it-is-the-code")
        opts = [again, code, self.save()]
        if (info.get("env_fault") or {}).get("again"):   # the same fault after a check again: never the same advice twice
            opts = [self.set_rec(opts[2], True), self.set_rec(again, False), code]
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=opts, qid="task.env")}

    def manual_task(self, n, plan):
        """A manual task (`**Test:** manual`) whose files are made: the person confirms each Case by hand."""
        r = self.r
        t = next((x for x in plan.get("tasks", []) if x["n"] == n), {"title": "", "block": ""})
        cases = []
        on = False
        for line in t.get("block", "").splitlines():
            if re.match(r"^\*\*Cases:\*\*", line):
                on = True
                inline = line.split(":**", 1)[1].strip()
                if inline:
                    cases.append(inline)
                continue
            if on and re.match(r"^\*\*\w+:\*\*", line):
                on = False
            m = re.match(r"^\s*[-*]\s+(?!\[[ xX]\])(\S.*)$", line) if on else None
            if m:
                cases.append(m.group(1).strip())
        if r.armed():
            return {"action": "auto", "stage": "build", "calls": [self.c("park --verdict PARKED-NEEDS-DECISION --reason %s" % shlex.quote(
                "Task %d is a manual task: it needs you to confirm it by hand" % n))],
                "say": "Task %d is a manual task; the armed run parks for you." % n}
        text = "Task %d (%s) is a manual task. Confirm by hand that each Case holds: %s." % (n, t.get("title", ""), "; ".join(cases) or "see the task")
        confirm = self.opt("Confirm", "Every Case holds; the task passes.", move="confirm",
                           calls=[self.c("task confirm %d --by '{answer}'" % n), self.c("task gate %d --model person" % n)],
                           answer=("Manual task", "Task %d: what name should the confirmation carry?" % n), oid="confirm")
        return {"action": "ask", "stage": "build", "ask": self.question("Manual task", text, stage="build", qid="task.manual", options=[
            confirm, self.opt("Stop", "Save the run for later.", move="pause", calls=[], stop=True, oid="save")])}

    def reopen_set(self, g, n):
        """Task n and the tasks that must reopen with it: a task of the group that has run (passed or running), depends on a
        task already taken, directly or not, and shares a declared file with it."""
        plan = self.r.plan or {"tasks": []}
        rt = self.r.groups.get("tasks") or {}
        by_n = {t["n"]: t for t in plan["tasks"] if t.get("group") == g["id"]}

        def deps(m, seen):
            out = set()
            for d in by_n[m]["depends"]:
                if d in by_n and d not in seen:
                    out |= {d} | deps(d, seen | {d})
            return out

        taken = [n]
        grew = True
        while grew:
            grew = False
            for m in sorted(by_n):
                if m in taken or (rt.get(str(m)) or {}).get("status") not in ("passed", "running"):
                    continue
                up = deps(m, {m})
                if any(t in up and set(by_n[m]["files"]) & set(by_n[t]["files"]) for t in taken):
                    taken.append(m)
                    grew = True
        return sorted(taken)

    def group_question(self, g):
        gid = g["id"]
        opts = []
        for k, t in enumerate(g.get("tasks", [])):
            n = t if isinstance(t, int) else t
            taken = self.reopen_set(g, n)
            others = [m for m in taken if m != n]
            names = ["Task %d" % m for m in taken]
            label = "Task %d" % n + (" (with %s)" % ", ".join("Task %d" % m for m in others) if others else "")
            what = names[0] if len(names) == 1 else "%s and %s" % (", ".join(names[:-1]), names[-1])
            opts.append(self.opt(label, "Re-runs %s; the other tasks of %s keep their work." % (what, gid), move="redo",
                                 calls=[self.c("group reopen %s %s --feedback {K}" % (gid, " ".join("--task %d" % m for m in taken)))],
                                 oid=choice_id(k, len(g.get("tasks", [])))))
        which = self.with_more(GROUP_HEADER, "Which task changes?", "build", opts[:3] if len(opts) > 4 else opts,
                               opts[3:] if len(opts) > 4 else [], "Which task changes? More tasks.", qid="group.change")
        q = self.question(GROUP_HEADER, "Group %s (%s) passed its check. Continue?" % (gid, g.get("title", "")), stage="build", qid="group.pass", options=[
            self.opt("Continue (Recommended)", "Go on to the next group, or to the merge.", move="advance", calls=[self.c("group continue %s" % gid)], oid="continue"),
            self.opt("Change", "Give feedback; only the tasks it concerns run again.",
                     do="Record each item the person typed with %s, then ask the change question (Which task changes?) in this action's `change`; its option runs the reopen call."
                        % self.c("evidence add --stage build --phase feedback --claim 'feedback #{K}: {text}'"), oid="change"),
            self.opt("Stop", "Save the run for later.", move="pause", calls=[], stop=True, oid="save")],
            extra={"change": which})
        return q

    @staticmethod
    def fail_text(ginfo, n=3):
        """9.8.4: the first FAIL lines of the group's Validate output, as the gate kept them ('' when none)."""
        lines = [str(x) for x in ((ginfo.get("gate") or {}).get("fail_lines") or []) if str(x).strip()][:n]
        return "; ".join(x if len(x) <= 160 else x[:157] + "..." for x in lines)

    def group_failed(self, g, ginfo, decide=False):
        gid = g["id"]
        gate = ginfo.get("gate") or {}
        reason = " ".join(str(gate.get("reason", "")).split())
        reason = reason if len(reason) <= 300 else reason[:297] + "..."
        fl = self.fail_text(ginfo)
        stepback = False
        if self.r.armed() and self.r.policy() and not decide:
            # 9.8.5 (U1): under the policy the run takes the recommended option itself when no person is needed for it;
            # a typed command, Save for later or a spent budget park it, as before
            q = self.group_failed(g, ginfo, decide=True)["ask"]
            rec = next((o for o in q["options"] + ((q.get("more") or {}).get("options") or []) if o.get("recommended")), None)
            stepback = bool(rec) and rec.get("move") == "back"   # M4 of WP08: an unattended run never steps back to Plan
            if rec and rec.get("calls") and not rec.get("answer_question") and not rec.get("stop") and not stepback:
                why = "policy: group %s failed its check (%s)" % (gid, reason[:200])
                calls = [c.replace("'{reason}'", "'%s'" % why.replace("'", "")) for c in rec["calls"]]
                return {"action": "auto", "stage": "build", "calls": calls,
                        "say": "Group %s failed its check; the policy takes \"%s\"." % (gid, self.bare(rec))}
        if self.r.armed() and not decide:  # nobody is there to answer: an armed run parks, as on every stop
            why = (reason[:300] + (" | " + fl if fl else ""))[:1200]   # 9.8.5 (S4): the whole failure, not its first 400 characters
            if stepback:
                why = ("a step back to Plan is yours to decide: " + why)[:1200]
            return {"action": "auto", "stage": "build",
                    "calls": [self.c('park --verdict PARKED-NEEDS-DECISION --reason %s' % shlex.quote("group %s failed its check: %s" % (gid, why)))],
                    "say": "Group %s failed its check; the armed run parks for you." % gid}
        plan = self.r.plan or {"tasks": []}
        # 9.8.4: how many times the group's check failed, and whether the whole failed while every part passed. A blind
        # rerun of every task was always the recommended answer; a measured run reran a group of 12 tasks five times.
        fails = int(ginfo.get("fails") or 1)
        all_passed = bool(g.get("tasks")) and all(tasks_md.task_done(t, self.r.groups) for t in plan.get("tasks", []) if t.get("n") in g.get("tasks", []))
        fixable = all_passed and bool(gate.get("ran"))
        # a fix of the merged tree that did not make the group pass is not recommended again: the run converges on the plan
        # (a step back) or on the person (Save for later), never on the same retry (an e2e run looped on it 131 times)
        tried = int(ginfo.get("fix_tries") or 0)
        reopen = [self.c("group reopen %s %s" % (gid, " ".join("--task %d" % n for n in g.get("tasks", []))))]
        opts = []
        empty = int(ginfo.get("fix_empty") or 0)   # 9.8.5 (S8): a fix agent that changed nothing: the code is not the cause
        timed = int(gate.get("timeout_s") or 0)
        limit = timed if fails < 2 and not empty else 0   # a second time-out points at the plan's command: offered, not recommended
        if timed:  # the gate ran out of time, not out of luck: the same checks again with twice the limit
            opts.append(self.opt("Run the gate again with twice the time" + (" (Recommended)" if limit else ""),
                                 "Group %s's checks run again, limit %d seconds." % (gid, 2 * timed),
                                 move="redo", calls=[self.c("group gate %s --timeout-s %d" % (gid, 2 * timed))], oid="twice-the-time"))
        fix_rec = fixable and not limit and not tried and not empty
        fix = self.opt("Fix the group's merged work" + (" (Recommended)" if fix_rec else ""),
                       "One Build fix agent works on %s's merged tree (every task's work together) until its check passes; the tasks keep their work." % gid,
                       move="redo", calls=[self.c("group fix %s" % gid)], oid="fix-group") if fixable else None
        back = self.r.can_loop("build", "plan")
        rerun_rec = not limit and not fixable and fails < 2 and not empty
        rerun = self.opt("Run the group's tasks again" + (" (Recommended)" if rerun_rec else ""), "Each task of %s runs again." % gid, move="redo", calls=reopen, oid="redo")
        plan_rec = not limit and not fix_rec and not rerun_rec and back
        loop = self.opt("Loop back to Plan" + (" (Recommended)" if plan_rec else ""), "The plan cannot be built as written.", move="back",
                        calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The plan cannot be built"], oid="back") if back else None
        save_rec = not limit and not fix_rec and not rerun_rec and not plan_rec
        save = self.set_rec(self.save(), save_rec)
        if fix_rec or limit:
            rest = [fix, rerun, loop]
        elif plan_rec:
            rest = [loop, fix, rerun]
        elif save_rec:
            rest = [save, fix, rerun]
        else:
            rest = [rerun, fix, loop]
        opts += [o for o in rest if o]
        if not save_rec:
            opts.append(save)
        # 9.8.5 (S6): when the cause is the group's command (a time-out again, or a fix that changed nothing), the person
        # types the command to run instead: one line of tasks.md changes, the passed tasks keep their work, no loop is spent
        cmd_cause = (timed and not limit) or empty
        patch = self.opt("Change the group's command" + (" (Recommended)" if cmd_cause else ""),
                         "Type the Validate command group %s should run (now: %s); its check runs again, the tasks keep their work, no loop is spent." % (
                             gid, (g.get("validate") or "none")[:120]),
                         move="redo", calls=[self.c("plan patch %s --cmd '{answer}'" % gid), self.c("group gate %s" % gid)],
                         answer=("Group command", "Group %s: what Validate command should it run? It runs the tests this group can break, within the time limit." % gid),
                         oid="change-command")
        if cmd_cause:
            for o in opts:
                self.set_rec(o, False)
            opts.insert(0, patch)
        else:
            opts.insert(len(opts) - 1, patch)
        opts.sort(key=lambda o: 0 if o.get("recommended") else 1)   # the recommended option first
        text = "Group %s failed its check" % gid + (" %d times" % fails if fails > 1 else "") + " (%s)." % reason
        if fl:
            text += " What failed: %s." % fl
        if empty:
            text += (" A fix agent changed nothing, so the cause is not in the group's code: the plan's command or the "
                     "environment is (temper doctor shows the environment).")
        elif tried and fixable:
            text += " A fix of its merged work did not make it pass" + (": the plan is the likelier cause." if back else ".")
        text += (" Change the group's command?" if cmd_cause else " Fix its merged work?" if fix_rec else " Loop back to Plan?" if plan_rec else
                 " Save the run for later?" if save_rec else " Run its tasks again?")
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=opts, qid="group.fail")}

    def group_fix_work(self, g, ginfo):
        """9.8.4: the person chose to fix a group whose check failed after every task passed: one Build fix agent works on the
        group's merged tree; the CLI commits what it changed on the group's branch, and the next action checks the group."""
        gid = g["id"]
        gate = ginfo.get("gate") or {}
        fl = [str(x) for x in gate.get("fail_lines") or []][:8]
        lines = ["Group fix: group %s's check failed after every one of its tasks passed. Work only in its worktree %s (the merged "
                 "work of the group, on branch %s); do not commit, the CLI commits what you change. Make its Validate command pass: %s." % (
                     gid, ginfo.get("worktree", ""), ginfo.get("branch", ""), g.get("validate") or "(none declared)"),
                 "Why the check failed: %s." % " ".join(str(gate.get("reason", "")).split())]
        if fl:
            lines.append("What failed (the first FAIL lines of its output): %s." % "; ".join(fl))
        a = self.agent("build", lines)
        # the commit clears the group's gate: the next action checks the group as an ordinary call, and a FAIL there asks
        # the group question again (that call records its verdict and prints its marker, so `temper go` goes on to ask)
        a["after"].append(self.c("group fix %s --commit" % gid))
        return {"action": "work", "stage": "build", "calls": [], "agents": [a],
                "say": "Build: one fix agent works on group %s's merged tree%s. %s" % (gid, on_model([a]), goes_on(False))}

    def parked(self, gid):
        r = self.r
        g = r.groups.get("groups", {}).get(gid) or {}
        tasks = sorted(int(n) for n, v in (r.groups.get("tasks") or {}).items()
                       if isinstance(v, dict) and v.get("group") == gid and v.get("status") in ("failed", "running"))
        targs = " ".join("--task %d" % n for n in tasks) or "--task {N}"
        foreign = g.get("parked_foreign") or []
        if r.armed():
            return {"action": "auto", "stage": "build",
                    "calls": [self.c('park --verdict PARKED-NEEDS-DECISION --reason %s' % shlex.quote("group %s is parked: %s" % (gid, str(g.get("parked_reason", ""))[:200])))],
                    "say": "Group %s is parked; the armed run parks for you." % gid}
        if foreign:
            wt = ""
            for n in tasks:
                wt = (r.groups.get("tasks", {}).get(str(n)) or {}).get("worktree") or wt
            wt = wt or g.get("worktree", "")
            fp = git("-C", wt, "rev-list", "--first-parent", "HEAD").split() if wt else []
            lines = ["git -C %s rebase --autostash --onto %s~1 %s" % (wt, s[:7], s[:7]) for s in foreign if not fp or s in fp] or \
                    ["git -C %s rebase --autostash --onto %s~1 %s" % (wt, s[:7], s[:7]) for s in foreign]
            csv = ",".join(s[:7] for s in foreign)
            opts = [self.opt("Take the commits out and run the task again (Recommended)", "Remove the agent's commits, newest first; the task runs again.",
                             move="redo", calls=lines + [self.c("group reopen %s %s" % (gid, targs))], oid="take-out"),
                    self.opt("Keep the agent's commits", "Keep them knowingly, with your reason (recorded like a skip).", move="keep",
                             calls=[self.c("group reopen %s %s --accept-foreign %s --reason '{reason}'" % (gid, targs, csv))],
                             reason=["The commits are right", "I accept the risk"], oid="keep-commits"),
                    self.save()]
            text = "Group %s is parked: a task agent made commits the CLI did not (%s). Take them out, or keep them?" % (gid, csv)
        elif any(isinstance((r.groups.get("tasks", {}).get(str(n)) or {}).get("blocked"), dict) for n in tasks):
            # 9.8.4: a task whose test needs a file it does not declare: no attempt on any model can build it as planned
            # (a benchmark run spent two Haiku and two Sonnet attempts on one), so the plan comes first
            b = [((r.groups.get("tasks", {}).get(str(n)) or {}).get("blocked"), n) for n in tasks]
            b = [(x, n) for x, n in b if isinstance(x, dict)]
            what = "; ".join("Task %d needs %s, which %s (%s)" % (
                n, x.get("needs"), ("Task %s declares" % ", ".join(str(o) for o in x.get("owners") or []) if x.get("owners") else "no task declares"),
                x.get("reason") or "no reason given") for x, n in b)
            back = r.can_loop("build", "plan")
            rerun = self.opt("Run the task again", "The blocked tasks run again as planned.", move="redo", calls=[self.c("group reopen %s %s" % (gid, targs))], oid="redo")
            save = self.save()
            if back:
                opts = [self.opt("Loop back to Plan (Recommended)", "Plan moves the change or the test into the task that owns the file.", move="back",
                                 calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The plan cannot be built"], oid="back"), rerun, save]
            else:
                opts = [self.set_rec(save, True), rerun]
            text = "Group %s is parked: %s. No attempt can build it as planned. %s" % (
                gid, what, "Loop back to Plan?" if back else "Save the run for later?")
        else:
            # 9.8.0 (round 5): a group that parks again after the person ran it again failed every model twice over: the
            # plan is the likelier cause, so Loop back to Plan is the recommended answer then (a measured run reran a
            # task whose gate ran a test a later task writes, and parked five times).
            again = r.can_loop("build", "plan") and any((r.groups.get("tasks", {}).get(str(n)) or {}).get("reopened") for n in tasks)
            rerun = self.opt("Run the task again" + ("" if again else " (Recommended)"), "The parked tasks run again, from Haiku.", move="redo",
                             calls=[self.c("group reopen %s %s" % (gid, targs))], oid="redo")
            opts = [] if again else [rerun]
            if r.can_loop("build", "plan"):
                opts.append(self.opt("Loop back to Plan" + (" (Recommended)" if again else ""), "The plan cannot be built as written.", move="back",
                                     calls=[self.c("state loop build plan --reason '{reason}'")], reason=["The plan cannot be built"], oid="back"))
            if again:
                opts.append(rerun)
            opts.append(self.save())
            text = ("Group %s is parked again after a rerun (%s). Loop back to Plan?" if again else
                    "Group %s is parked (%s). Run the task again?") % (gid, str(g.get("parked_reason", ""))[:200])
        return {"action": "ask", "stage": "build", "ask": self.question(GATE_HEADER, text, stage="build", options=opts, qid="group.parked")}
