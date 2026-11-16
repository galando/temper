"""flow_view.py: the view the mod draws: .temper/view.json and the agents it names.

A module of the flow; scripts/flow.py is its facade. Standard library only.
"""

import json
import os
import re
import tempfile

import tasks_md

from flow_base import (
    DRIFT_HEADER, DRIFT_OPTIONS, DRIFT_PREFIX, FRESH_ROWS, GATE_HEADER, LABEL, TEMPER, VERSION, criteria, git, loop_at,
    plan_files, read_json)


def check_markers(run):
    rows = read_json(os.path.join(TEMPER, "evidence", "check.json"), [])
    kinds = [("compile", r"compile|build\b|type ?check|tsc|mypy"), ("tests", r"\btests?\b|unittest|pytest|jest"),
             ("coverage", r"coverage"), ("lint", r"lint|ruff|eslint|flake8"), ("security", r"security|secret|audit|semgrep|bandit|scan")]
    out = []
    for name, rx in kinds:
        # A scenario's trace row names its test; it is no run of a check (as in `temper gate check`).
        hits = [r for r in rows if isinstance(r, dict) and not r.get("scenario") and re.search(rx, str(r.get("claim", "")), re.I)]
        if not hits:
            out.append({"name": name, "state": "none", "detail": "", "lines": []})
            continue
        last = hits[-1]
        code = last.get("exit_code")
        state = "pass" if code == 0 else ("fail" if isinstance(code, int) else "info")
        if name == "coverage" and last.get("value") is not None:
            state = "pass" if code in (0, None) else state
        lines = [str(r.get("claim", ""))[:200] for r in hits if isinstance(r.get("exit_code"), int) and r.get("exit_code") != 0][-5:]
        out.append({"name": name, "state": state, "detail": str(last.get("claim", ""))[:200],
                    "value": last.get("value"), "lines": lines})
    return out



# 9.8.0: a failed row that only waits for the person's answer: the Intent's open Blocking questions, the Plan's Context
# check and the fresh review the person asked for, a criterion only the person can confirm at Check. The stage is waiting
# for the person, not failed, and the mod draws it so: a person read the red Intent before its first question as a fault.
PERSON_ROWS = ("blocking question open", "context map reviewed") + FRESH_ROWS


def manual_ids(run):
    """The ids of the intent's required criteria validated by hand."""
    if not run.spec or not os.path.isfile(os.path.join(run.spec, "intent.md")):
        return set()
    try:
        import acceptance
        lines = open(os.path.join(run.spec, "intent.md"), encoding="utf-8").read().splitlines()
        return {c["id"] for c in acceptance.parse_criteria(acceptance.section_lines(lines, "Success Criteria"))
                if c.get("id") and c.get("vtype") == "manual"}
    except Exception:
        return set()


def waits_on_person(row, stage, manual, records=()):
    """True for a failed row that is no fault of the work: it waits for the person's answer, or for a record the CLI
    writes itself next (Build's criteria with no CLI row yet)."""
    if row.get("name") in PERSON_ROWS:
        return True
    if stage == "build" and records and row.get("name") == "criteria validated":
        return True
    if stage == "check":
        ids = re.findall(r"\b([A-Z]+-\d+) has no supported passing evidence row", str(row.get("detail", "")))
        return bool(ids) and all(i in manual for i in ids)
    return False


def stage_marks(run, nxt):
    out = []
    seq = run.seq()
    here = run.stage
    for s in seq:
        v = run.verdict(s) if s != "rca" else None
        sk = run.skip(s)
        if here not in seq:
            mark = "todo"
        elif seq.index(s) < seq.index(here):
            # An earlier stage shows what it has: a skip, its verdict, or (a stage with no gate, RCA) passed. One with no
            # verdict and no skip did not pass: it shows as not done, never as passed.
            if sk and v != "PASS":
                mark = "skipped"
            elif v in ("PASS", "FAIL"):
                mark = "passed" if v == "PASS" else "failed"
            else:
                mark = "passed" if run.gate_of(s) is None else "todo"
        elif s == here:
            mark = "here"
        else:
            mark = "todo"
        manual = manual_ids(run) if s == "check" else set()
        records = run.missing_records(s) if s == "build" else []
        row = {"id": s, "label": LABEL.get(s, s), "mark": mark, "verdict": v,
               "failed": [dict({"name": x.get("name"), "detail": x.get("detail")}, **({"waits": True} if waits_on_person(x, s, manual, records) else {}))
                          for x in run.failed_rows(s)] if s != "rca" else []}
        if sk:
            row["skipped"] = {"reason": sk.get("reason"), "by": sk.get("by")}
        out.append(row)
    return out


def status_line(run, nxt):
    if not run.active:
        return "No run is active."
    label = LABEL.get(run.stage, run.stage)
    a = nxt.get("action")
    if a == "ask":
        if (nxt.get("ask") or {}).get("context"):
            return "%s: your answer to the Is this the right context for the plan? question is not recorded yet." % label
        return "%s: waiting for your answer to the %s question." % (label, (nxt.get("ask") or {}).get("question", {}).get("header", GATE_HEADER))
    if a == "auto":
        return nxt.get("say") or "%s: the armed run goes on." % label
    if a == "broken":
        return nxt.get("say")
    if run.state.get("parked") and a != "work":
        return "%s: parked for you." % label
    return nxt.get("say") or "%s: Claude is working on it." % label


def build_view(run):
    plan = run.plan or {"groups": [], "tasks": []}
    rg = run.groups.get("groups") or {}
    rt = run.groups.get("tasks") or {}
    ev = read_json(os.path.join(TEMPER, "evidence", "build.json"), [])
    groups = []
    for g in plan.get("groups", []):
        ginfo = rg.get(g["id"]) or {}
        tasks = []
        for n in g.get("tasks", []):
            t = next((x for x in plan.get("tasks", []) if x.get("n") == n), {})
            info = rt.get(str(n)) or {}
            phases = [str(r.get("phase")) for r in ev if isinstance(r, dict) and r.get("task") == n]
            state = tasks_md.display_state(info, ginfo, phases)
            attempts = info.get("attempts") or []
            tasks.append({"n": n, "title": t.get("title", ""), "files": t.get("files", []), "state": state,
                          "model": (attempts[-1].get("model") if attempts and isinstance(attempts[-1], dict) else None) or info.get("model"),
                          "attempts": len(attempts)})
        groups.append({"id": g["id"], "title": g.get("title", ""), "status": ginfo.get("status", "pending"),
                       "verdict": (ginfo.get("gate") or {}).get("verdict"), "tasks": tasks})
    return {"groups": groups, "integration": (run.groups.get("integration") or {}).get("verdict")}


def fresh_view(r):
    """The fresh review of the plan for the pane (9.7.6): the reader's paraphrase, the lenses not run, whether tasks.md changed
    after it, and its findings with their state; null when it does not apply to the run."""
    fr = r.fresh()
    if not fr["applies"]:
        return None
    return {"paraphrase": fr["paraphrase"], "missing": fr["missing"], "stale": fr["stale"],
            "findings": [{"id": f["id"], "severity": f["severity"], "lens": f["lens"], "claim": f["claim"], "state": f["state"],
                          "cite": f.get("cite")} for f in fr["findings"]]}


def plan_view(run):
    plan = run.plan or {"groups": [], "tasks": []}
    approved = run.state.get("approved_files")
    by_group = []
    for g in plan.get("groups", []):
        files = []
        for n in g.get("tasks", []):
            t = next((x for x in plan.get("tasks", []) if x.get("n") == n), {})
            files += [f for f in t.get("files", []) if f not in files]
        by_group.append({"id": g["id"], "title": g.get("title", ""), "files": files})
    return {"approved": isinstance(approved, list), "files": approved if isinstance(approved, list) else (plan_files(run.spec) if run.spec else []),
            "groups": by_group}


def usage(run):
    """The time Claude Code gave for each launch, summed, and by stage and by model (no token count since 9.7.4)."""
    rows = [r for r in run.usage if isinstance(r, dict)]
    num = lambda r, k: r[k] if isinstance(r.get(k), int) and not isinstance(r.get(k), bool) else 0

    def by(key):
        out = {}
        for r in rows:
            b = out.setdefault(r.get(key) or "unknown", {"ms": 0, "runs": 0})
            b["runs"] += 1
            b["ms"] += num(r, "ms")
            # a stage names the models its launches asked for
            if key == "stage" and r.get("model") and r.get("model") not in b.setdefault("models", []):
                b["models"].append(r.get("model"))
        return out
    return {"ms": sum(num(r, "ms") for r in rows), "by_stage": by("stage"), "by_model": by("model")}


def loops(run):
    """The run's steps back, each with its live budget (the one can_loop decides with, not the max_iterations stored at
    its first step) and the time of its latest step (the time every reader orders loops by)."""
    out = []
    for l in run.active_loops():
        frm, to = l.get("from_stage"), l.get("to_stage")
        out.append({"from": frm, "to": to, "reason": l.get("reason"),
                    "iteration": l.get("iteration"), "max": run.loop_budget(frm, to), "at": loop_at(l) or None})
    return out


def view(run, nxt):
    if not run.active:
        return {"version": VERSION, "run": None, "status": "No run is active.", "drift": drift_info()}
    r = run
    # 9.8.0: the agents the session may launch now (the mod launches no other: its session guard). An agent's `before`
    # call (a Build task's `task start`) changes the next action before the agent is launched: to `wait`, to a `work`
    # that names only the other tasks of the same launch (and a chain shortened by the task now running), or to the
    # question a manual task asks. While the run
    # stays at the same stage, the view keeps naming every agent it named there. That memory is .temper/agents-named.json
    # ({run, stage, agents}, written with the view): a view lost, written again, or written for an error mid-stage does not
    # forget it (the view written last was the memory before, and an older run's view still serves as one). The mod keeps
    # none (it is loaded again between turns).
    agents = [{"type": a.get("type") or "", "model": a.get("model") or "", "prompt": a.get("prompt") or ""}
              for a in (nxt.get("agents") or [])] if nxt.get("action") == "work" else []
    if nxt.get("action") in ("work", "wait", "ask", "auto"):
        for a in named_before(r):
            if isinstance(a, dict) and a not in agents:
                agents.append(a)
        agents = agents[:AGENTS_NAMED_MAX]   # the current action's first
    out = {
        "version": VERSION,
        "run": {"id": r.state.get("run_id"), "step": r.state.get("step"), "slug": r.slug, "title": r.title(),
                "command": r.command, "stage": r.stage, "mode": r.state.get("run_mode") or "interactive",
                "complexity": r.state.get("complexity"), "branch": r.state.get("branch"), "spec": r.spec,
                "feature": r.state.get("feature"), "parked": r.state.get("parked") or None},
        "stages": stage_marks(r, nxt),
        "status": status_line(r, nxt),
        "next": {"action": nxt.get("action"), "stage": nxt.get("stage"), "say": nxt.get("say"),
                 "calls": nxt.get("calls") or [] if nxt.get("action") in ("work", "auto") else [],
                 "steps": nxt.get("steps") or [] if nxt.get("action") == "work" else [],
                 "agents": agents},
        "ask": nxt.get("ask") if nxt.get("action") == "ask" else None,
        "blocking": nxt.get("blocking") or [],
        "blocking_asks": nxt.get("blocking_asks") or [],
        "context_map": nxt.get("context_map"),
        "context_check": nxt.get("context_check"),
        "restart": nxt.get("restart"),
        "drift": drift_info(),
        "guard": {"stage": r.stage, "spec": r.spec, "slug": r.slug, "fix_run": r.command == "fix",
                  "grouped": bool(r.groups), "armed": r.armed(), "autonomy_enabled": True,
                  "plan_files": plan_view(r)["files"], "step": r.state.get("step"), "run_id": r.state.get("run_id"),
                  "prefix": git("rev-parse", "--show-prefix"),
                  "adhoc_stage": (r.state.get("adhoc") or {}).get("stage") if isinstance(r.state.get("adhoc"), dict) else None,
                  "trivial_exit": r.stage == "intent" and int(r.state.get("step") or 0) == 0 and set(r.gates) <= {"intent"} and not r.overrides
                  and not any(os.path.isfile(os.path.join(r.spec, n)) for n in ("intent.md", "plan.md", "tasks.md", "design.md"))},
        "plan": plan_view(r),
        "fresh": fresh_view(r),
        "build": build_view(r),
        "findings": [{k: v for k, v in f.items() if k not in ("answer", "cite", "quote")} for f in r.findings()],   # the view's schema stays as it was
        "checks": [{"name": x.get("name"), "pass": bool(x.get("pass")), "detail": x.get("detail")} for x in r.rows("check")],
        "check_markers": check_markers(r),
        "criteria": criteria(r),
        "loops": loops(r),
        "skips": [{"stage": o.get("stage"), "reason": o.get("reason"), "by": o.get("by")} for o in r.overrides if isinstance(o, dict)],
        "usage": usage(r),
        "time": {"started": r.state.get("started") or r.state.get("created"), "updated": r.state.get("updated")},
    }
    return out


def drift_info():
    return {"id": "scope.drift", "kind": "drift", "header": DRIFT_HEADER, "prefix": DRIFT_PREFIX, "options": DRIFT_OPTIONS}


AGENTS_NAMED = "agents-named.json"
AGENTS_NAMED_MAX = 64   # a grouped Build names one agent per task (a chain counts once); more than a plan holds


def named_before(r):
    """The agents the run named at its current stage, from the record written with the view (or, for a run whose record
    predates it, the view written last)."""
    for name in (AGENTS_NAMED, "view.json"):
        d = read_json(os.path.join(TEMPER, name), {})
        if name == AGENTS_NAMED:
            run_id, stage, agents = d.get("run"), d.get("stage"), d.get("agents")
        else:
            pr = d.get("run") if isinstance(d.get("run"), dict) else {}
            run_id, stage, agents = pr.get("id"), pr.get("stage"), (d.get("next") or {}).get("agents") if isinstance(d.get("next"), dict) else None
        if run_id is not None and run_id == r.state.get("run_id") and stage == r.stage and isinstance(agents, list):
            return agents
    return []


def write_named(doc):
    """Keep the agents a view names at its stage (named_before reads them): only a view that names some writes the record,
    so a view of an error or of a question mid-stage leaves the memory as it was."""
    run, agents = doc.get("run"), (doc.get("next") or {}).get("agents") or []
    if not isinstance(run, dict) or not agents:
        return
    fd, tmp = tempfile.mkstemp(dir=TEMPER, prefix=".named.", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump({"run": run.get("id"), "stage": run.get("stage"), "agents": agents}, f, indent=1)
    os.replace(tmp, os.path.join(TEMPER, AGENTS_NAMED))


def write_view(doc):
    os.makedirs(TEMPER, exist_ok=True)
    try:
        write_named(doc)
    except OSError:
        pass   # the record is a memory for the mod's guard: a launch it forgets is refused, never let through
    fd, tmp = tempfile.mkstemp(dir=TEMPER, prefix=".view.", suffix=".tmp")
    os.chmod(tmp, 0o644)
    with os.fdopen(fd, "w") as f:
        json.dump(doc, f, indent=1)
        f.write("\n")
    os.replace(tmp, os.path.join(TEMPER, "view.json"))
