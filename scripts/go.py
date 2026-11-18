"""go.py: `temper go` (9.8.0). The CLI does its own steps and hands the session only what needs it.

Before 9.8.0 the session ran `temper next --json`, read the whole run view (2,000 characters on average), ran the
action's calls, and asked `next` again: one turn per step, each re-reading the whole conversation. In a measured run, 59
of 88 tool calls were such mechanical steps. `temper go` runs them inside the CLI:

  - an `auto` action (an armed run's move, a step with nothing to decide): its calls, then on
  - a `work` action with calls and no agents and no steps (a gate to run, a group to start, check run): its calls, then on
  - a `work` action with agents: its calls first, then it stops and returns the agents to launch

It stops, printing one compact JSON object, at the first point that needs the session:

  {"action": "work", "stage", "say", "ran": [...], "agents": [{type, model, prompt, before, after, ...}], "steps": [...]}
  {"action": "ask", "stage", "say", "ran": [...], "ask": {the CLI's question, as `next` gives it}, "blocking", "gate"}
  {"action": "wait" | "none" | "broken" | "error", "stage", "say", "ran": [...], ...}

`temper go --taken-up` (WP11), the first call after /temper:temper was typed with no words, first records a stop of a run
that goes on by itself (`temper park`), so its stage asks the person once.

It never runs a call only the person may cause: those are the calls of an option of a question, which the session runs
from the person's answer (and the mod checks word for word). It runs only the calls of the CLI's own actions, which the
mod lets through today. A call that fails stops it, unless it recorded a verdict (9.8.5, WP09): `gate`, `task gate`,
`group gate` and `integrate` print `VERDICT: <scope> <PASS or FAIL or PARKED>` on stdout once the verdict is recorded,
and a call whose own marker is there is no failure, whatever its exit code: the verdict is what the next question asks
about. `verdicts` lists the markers read, in order. The full view still goes to .temper/view.json for the mod and
/temper:status.
Standard library only.
"""
import json
import re
import subprocess
import sys

MAX_STEPS = 60
MARKER = re.compile(r"^VERDICT: (\S+) (PASS|FAIL|PARKED)$")


def scope_of(call, cli):
    """The scope a call of the CLI records a verdict for (a task gate: its task, and None for any group), else ''."""
    m = re.match(re.escape(cli) + r" (?:gate ([a-z]+)|task gate (\d+)|group gate (G\d+)|(integrate))(?:\s|$)", call)
    if not m:
        return ""
    return "gate:" + m.group(1) if m.group(1) else "task:" + m.group(2) if m.group(2) else (
        "group:" + m.group(3) if m.group(3) else "integrate")


def recorded(call, cli, out):
    """{"scope", "verdict"} when the call is one of the four that record a verdict and the last marker line of its
    stdout names its scope (a task gate's own task, or any group: a parked group refuses it); else None. Text alone
    is none."""
    want = scope_of(call, cli)
    found = [m for m in (MARKER.match(line) for line in (out or "").splitlines()) if m]
    if not want or not found:
        return None
    scope, verdict = found[-1].group(1), found[-1].group(2)
    group = re.fullmatch(r"group:G\d+", scope) is not None
    if verdict == "PARKED" and not group:
        return None
    if scope == want or (want.startswith("task:") and group):
        return {"scope": scope, "verdict": verdict}
    return None


def short(call, cli):
    return call.replace(cli + " ", "temper ", 1) if call.startswith(cli + " ") else call


def brief(call, cli):
    """9.8.0: an agent's gate call prints its failed rows only (`--brief`); the question after it names them, and the
    passed rows (3,000 to 7,000 characters a gate in the measured runs) were read again on every later turn."""
    return call + " --brief" if re.fullmatch(re.escape(cli) + r" gate [a-z]+", call) else call


SLIM_KEYS = ("id", "kind", "move", "recommended", "calls", "steps", "do", "stop", "reason", "reason_question", "reason_ids",
             "answer_question", "answer_ids")


def slim(a):
    """9.8.0: a question as the session needs it: `question` to ask exactly, its id and kind, and per option only what the
    answer runs (its label, calls, steps, do, stop, reason and name questions, each with its ids beside it) and what a
    reader selects it by (its id, kind, move and recommended: 9.8.5 keeps these few short keys, the price of selecting
    by field and never by label). The description is in `question` too, and the run id, step and stage are the mod's, read from view.json."""
    if not isinstance(a, dict) or "question" not in a:
        return a
    out = dict({k: a[k] for k in ("id", "kind") if a.get(k)}, question=a["question"])
    out["options"] = [dict({"label": o.get("label")}, **{k: o[k] for k in SLIM_KEYS if o.get(k)}) for o in a.get("options") or []]
    for k in ("more", "accept"):
        if a.get(k):
            out[k] = slim(a[k])
    return out


def compact(n, ran, cli, verdicts=()):
    out = {"action": n.get("action"), "stage": n.get("stage"), "say": n.get("say", ""),
           "ran": [short(c, cli) for c in ran], "verdicts": list(verdicts)}
    act = n.get("action")
    if act == "work":
        out["agents"] = [dict(a, after=[brief(c, cli) for c in a.get("after") or []], **({"gate": brief(a["gate"], cli)} if a.get("gate") else {}))
                         for a in n.get("agents") or []]
        if n.get("steps"):
            out["steps"] = n["steps"]
        if n.get("gate"):
            out["gate"] = n["gate"]
    elif act == "ask":
        if n.get("ask"):
            out["ask"] = slim(n["ask"])
        if n.get("gate"):
            out["gate"] = n["gate"]
        if n.get("blocking_asks"):   # 9.8.0: each Blocking question ready to ask, with the call that records its answer
            out["blocking"] = n["blocking_asks"]
    elif act == "wait":
        out["tasks"] = n.get("tasks") or []
    elif act == "broken":
        out["restart"] = n.get("restart")
    if n.get("setup"):
        out["setup"] = n["setup"]
    return out


def taken_up(cli, root, ran):
    """WP11: `temper go --taken-up` (the run was taken up again with no words): a run that goes on by itself records a
    stop first, so its stage asks the person its question once."""
    p = subprocess.run([cli, "next", "--json"], cwd=root, capture_output=True, text=True)
    try:
        armed = bool((json.loads(p.stdout).get("run") or {}).get("armed"))
    except (ValueError, AttributeError):
        armed = False
    if armed:
        c = "%s park --verdict PARKED-NEEDS-DECISION --reason 'the run was taken up again'" % cli
        subprocess.run(["bash", "-c", c], cwd=root, capture_output=True, text=True)
        ran.append(c)


def main(cli, root, flags=()):
    ran = []
    verdicts = []
    last = None
    if "--taken-up" in flags:
        taken_up(cli, root, ran)
    for _ in range(MAX_STEPS):
        p = subprocess.run([cli, "next", "--json"], cwd=root, capture_output=True, text=True)
        try:
            n = json.loads(p.stdout)
        except ValueError:
            print(json.dumps({"action": "error", "say": "temper next failed: %s" % (p.stderr or p.stdout)[-300:],
                              "ran": [short(c, cli) for c in ran], "verdicts": verdicts}))
            return 1
        act = n.get("action")
        mechanical = act == "auto" or (act == "work" and not n.get("agents") and not n.get("steps"))
        calls = n.get("calls") or []
        if act in ("auto", "work") and calls and (mechanical or n.get("agents")):
            key = json.dumps([act, n.get("stage"), calls], sort_keys=True)
            if key == last:   # the same calls again: they changed nothing, so stop rather than loop
                out = compact(n, ran, cli, verdicts)
                out["action"], out["say"] = "error", "temper go: the same calls would run twice (%s); run them by hand" % "; ".join(short(c, cli) for c in calls)
                print(json.dumps(out))
                return 1
            last = key
            for c in calls:
                r = subprocess.run(["bash", "-c", c], cwd=root, capture_output=True, text=True)
                ran.append(c)
                v = recorded(c, cli, r.stdout)
                if v is not None:
                    verdicts.append(v)
                if r.returncode != 0 and v is None:
                    out = compact(n, ran, cli, verdicts)
                    out["action"] = "error"
                    out["say"] = "the call %s failed (exit %d): %s" % (short(c, cli), r.returncode, (r.stderr or r.stdout).strip()[-300:])
                    print(json.dumps(out))
                    return 1
            if mechanical:
                continue
            n = dict(n, calls=[])
        print(json.dumps(compact(n, ran, cli, verdicts)))
        return 0
    print(json.dumps({"action": "error", "say": "temper go: more than %d steps without a stop" % MAX_STEPS,
                      "ran": [short(c, cli) for c in ran], "verdicts": verdicts}))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3:]))
