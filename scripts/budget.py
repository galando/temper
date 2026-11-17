#!/usr/bin/env python3
"""budget.py: the one budget of a run (9.8.5, WP10, ADR 0019 decision 1). Every repeat that follows a failed check spends
one entry of `.temper/budget.json`: 2 for one failure (its key) and 6 for one run, plus what the person granted.

  python3 budget.py spend <words of a temper call>    the CLI's dispatcher, before a call of SPENDS: prints nothing and
                                                      exits 0 when the call spends nothing; appends one entry and prints
                                                      `OK: repeat ...`; or prints `BLOCKED: ...`, writes nothing, exits 1
  python3 budget.py room <key>                        prints {"used", "limit", "run_used", "run_limit", "ok"} as JSON
  python3 budget.py grant --key K --reason R          the person's answer at the question run.budget: two more for K
                                                      and for the run
  python3 budget.py [show]                            the record, as text (`temper budget`)

When a call spends is read from the recorded verdicts and skips (the Run class of the flow, so the rule exists once),
from groups.json and from the record, never from an argument: no flag and no variable exempts a call. The flow reads the
same table (Run.room, Builder.next), so it never offers a call this refuses. Runs in the project folder; standard
library only.
"""
import datetime
import json
import os
import re
import shlex
import sys

TEMPER = ".temper"
PATH = os.path.join(TEMPER, "budget.json")
PER_FAILURE, PER_RUN, GRANT = 2, 6, 2
KEY_RE = re.compile(r"^(?:gate:[a-z]+|group:G\d+|task:\d+|acceptance|pipeline)$")

# The calls that spend, by their first words: the kind of their entry, and when they spend (key_of holds the rule).
SPENDS = (
    (("state", "loop"), "step back", "the gate of <from> is FAIL and not skipped: gate:<from>; from Build, a group whose "
                                     "check is FAIL or that is parked: group:<G>, or tasks with no groups: gate:build"),
    (("state", "redo"), "run again", "the gate of the stage is FAIL and not skipped: gate:<stage>"),
    (("group", "fix"), "group fix", "with no flag: group:<G>"),
    (("group", "reopen"), "tasks again", "the group's gate is FAIL or the group is parked: group:<G>"),
    (("group", "gate"), "more time", "with --timeout-s, at a group gate that is FAIL already: group:<G>"),
    (("plan", "patch"), "plan patch", "always: group:<G>, task:<N>, or gate:build for the Integration line"),
    (("task", "retry"), "task again", "always: task:<N>"),
    (("task", "test"), "check again", "--phase green of a task that holds env_fault: task:<N>"),
    (("acceptance", "reopen"), "test corrected", "always: acceptance"),
    (("state", "set", "pipeline_round"), "CI fix", "always: pipeline"),
    (("integrate",), "merge again", "the integration record is FAIL and no repeat of gate:build paid for it: gate:build"),
)


def read_json(path, default):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, type(default)) else default
    except (OSError, ValueError):
        return default


class Facts:
    """What a row reads. The flow passes its Run; the CLI reads the files here, and builds a Run only when a row needs
    the verdict and the skip of a stage."""

    def __init__(self, run=None):
        self._run, self._groups, self._state = run, None, None

    def run(self):
        if self._run is None:
            from flow_run import Run
            self._run = Run({})
        return self._run

    def failed(self, stage):
        r = self.run()
        return r.verdict(stage) == "FAIL" and r.skip(stage) is None

    def groups(self):
        if self._run is not None:
            return self._run.groups
        if self._groups is None:
            self._groups = read_json(os.path.join(TEMPER, "groups.json"), {})
        return self._groups

    def state(self):
        if self._run is not None:
            return self._run.state
        if self._state is None:
            self._state = read_json(os.path.join(TEMPER, "build-state.json"), {})
        return self._state

    def limit(self, key, default):
        if self._run is not None:
            v = self._run.cfg(key, str(default))
        else:
            import config_yaml
            v = str(config_yaml.get(config_yaml.load(os.path.join(".claude", "temper.config")), key, default))
        return int(v) if re.fullmatch(r"\d+", v.strip()) else default


def integration(facts):
    """The integration record when it is FAIL, with the mark an entry of gate:build carries when it pays for it."""
    i = facts.groups().get("integration") if isinstance(facts.groups().get("integration"), dict) else {}
    if i.get("verdict") != "FAIL":
        return None
    return "%s|%s" % (i.get("ts", ""), i.get("reason", ""))


def key_of(words, facts):
    """(key, kind) when the call of these words (after `temper`) spends now, else None."""
    w = [str(x) for x in words] + ["", "", "", ""]
    a, b, c, e = w[:4]
    if a == "state" and b in ("loop", "redo"):
        if c and facts.failed(c):
            return "gate:" + c, "step back" if b == "loop" else "run again"
        if b != "loop" or c != "build":
            return None
        # a step back from Build answers what holds Build (row D08: the planner launched again for the same failure is a
        # repeat of it): a failed or parked group, or tasks with no groups, which Build cannot run
        held = [g for g, x in sorted((facts.groups().get("groups") or {}).items()) if isinstance(x, dict) and (
            (x.get("gate") or {}).get("verdict") == "FAIL" or x.get("status") == "parked")]
        if held:
            return "group:" + held[0], "step back"
        plan = facts.run().plan or {}
        return ("gate:build", "step back") if plan.get("tasks") and not plan.get("groups") else None
    if a == "state" and b == "set" and c == "pipeline_round":
        return "pipeline", "CI fix"
    group = (facts.groups().get("groups") or {}).get(c) if a == "group" else None
    group = group if isinstance(group, dict) else {}
    if a == "group" and not re.fullmatch(r"G\d+", c):
        return None
    if a == "group" and b == "fix":
        return ("group:" + c, "group fix") if not any(str(x).startswith("-") for x in words[2:]) else None
    if a == "group" and b == "reopen":
        failed = (group.get("gate") or {}).get("verdict") == "FAIL" or group.get("status") == "parked"
        return ("group:" + c, "tasks again") if failed else None
    if a == "group" and b == "gate":
        more = "--timeout-s" in words or any(str(x).startswith("--timeout-s=") for x in words)
        return ("group:" + c, "more time") if more and (group.get("gate") or {}).get("verdict") == "FAIL" else None
    if a == "plan" and b == "patch":
        key = "task:" + e if c == "task" and e.isdigit() else "gate:build" if c == "integration" else (
            "group:" + c if re.fullmatch(r"G\d+", c) else None)
        return (key, "plan patch") if key else None
    if a == "task" and b == "retry":
        return ("task:" + c, "task again") if c.isdigit() else None
    if a == "task" and b == "test":
        green = any(x == "--phase" and y == "green" for x, y in zip(words, list(words[1:]))) or "--phase=green" in words
        task = (facts.groups().get("tasks") or {}).get(c)
        return ("task:" + c, "check again") if green and isinstance(task, dict) and task.get("env_fault") else None
    if a == "acceptance" and b == "reopen":
        return "acceptance", "test corrected"
    if a == "integrate":
        mark = integration(facts)
        paid = any(x.get("key") == "gate:build" and x.get("of") == mark for x in record(facts)["used"])
        return ("gate:build", "merge again") if mark and not paid else None
    return None


def record(facts):
    """The record of this run: a record of another run id, or one that cannot be read, counts as empty."""
    rid = facts.state().get("run_id") or ""
    d = read_json(PATH, {})
    if not rid or d.get("run") != rid:
        return {"v": 1, "run": rid, "used": [], "grants": []}
    return {"v": 1, "run": rid, "used": [x for x in d.get("used") or [] if isinstance(x, dict)],
            "grants": [x for x in d.get("grants") or [] if isinstance(x, dict)]}


def room(key, facts):
    d = record(facts)
    n = lambda x: int(x.get("n") or 0) if str(x.get("n") or 0).isdigit() else 0
    used = sum(1 for x in d["used"] if x.get("key") == key)
    limit = facts.limit("budget.per-failure", PER_FAILURE) + sum(n(x) for x in d["grants"] if x.get("key") == key)
    run_used, run_limit = len(d["used"]), facts.limit("budget.per-run", PER_RUN) + sum(n(x) for x in d["grants"])
    return {"used": used, "limit": limit, "run_used": run_used, "run_limit": run_limit,
            "ok": used < limit and run_used < run_limit}


def kinds(key, facts):
    return [str(x.get("kind")) for x in record(facts)["used"] if x.get("key") == key]


def what(key):
    """The key in the person's words."""
    kind, _, name = key.partition(":")
    return {"gate": name.capitalize(), "group": "Group %s's check" % name, "task": "Task %s" % name,
            "acceptance": "The acceptance test", "pipeline": "The CI fix"}.get(kind, key)


def count_line(key, rm):
    """What the question at the limit shows: the failure's count, or the run's."""
    if rm["used"] >= rm["limit"]:
        return "%s was repeated %d times (limit %d)" % (what(key), rm["used"], rm["limit"])
    return "This run made %d repeats (limit %d)" % (rm["run_used"], rm["run_limit"])


def save(d):
    tmp = "%s.tmp.%d" % (PATH, os.getpid())
    with open(tmp, "w") as f:
        json.dump(d, f, indent=1)
        f.write("\n")
    os.replace(tmp, PATH)


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def spend(words, facts):
    """(exit code, line) of one call: the entry is written only when the call spends and both limits have room."""
    hit = key_of(words, facts) if facts.state().get("run_id") else None
    if hit is None:
        return 0, ""
    key, kind = hit
    rm = room(key, facts)
    if rm["used"] >= rm["limit"]:
        return 1, "BLOCKED: %s was repeated %d times (limit %d); the person grants more at the question" % (
            key, rm["used"], rm["limit"])
    if not rm["ok"]:
        return 1, "BLOCKED: this run made %d repeats (limit %d); the person grants more at the question" % (
            rm["run_used"], rm["run_limit"])
    d = record(facts)
    why = next((y for x, y in zip(words, list(words[1:])) if x == "--reason"), "") or " ".join(str(x) for x in words)
    entry = {"key": key, "kind": kind, "stage": facts.state().get("next_stage") or "",
             "why": " ".join(str(why).split())[:200], "ts": now()}
    mark = integration(facts) if key == "gate:build" else None
    if mark:
        entry["of"] = mark   # the failed integrate this repeat answers: a merge after it spends nothing more
    d["used"].append(entry)
    os.makedirs(TEMPER, exist_ok=True)
    save(d)
    return 0, "OK: repeat %d of %d for %s (%d of %d in this run)" % (rm["used"] + 1, rm["limit"], key,
                                                                     rm["run_used"] + 1, rm["run_limit"])


def grant(argv, facts):
    key = next((y for x, y in zip(argv, argv[1:]) if x == "--key"), "")
    reason = " ".join(next((y for x, y in zip(argv, argv[1:]) if x == "--reason"), "").split())
    if not KEY_RE.match(key) or not reason:
        print("FAIL: usage: temper budget grant --key gate:<stage>|group:G<n>|task:<n>|acceptance|pipeline --reason '<why>'",
              file=sys.stderr)
        return 1
    d = record(facts)
    if not d["run"]:
        print("FAIL: no active run (temper state init first)", file=sys.stderr)
        return 1
    d["grants"].append({"key": key, "n": GRANT, "reason": reason[:300], "ts": now()})
    os.makedirs(TEMPER, exist_ok=True)
    save(d)
    rm = room(key, facts)
    print("OK: two more repeats for %s and for the run (%d of %d for it; %d of %d in this run)" % (
        key, rm["used"], rm["limit"], rm["run_used"], rm["run_limit"]))
    return 0


def show(facts):
    d = record(facts)
    keys = list(dict.fromkeys(x.get("key") for x in d["used"] + d["grants"]))
    total = room("", facts)
    print("Budget of this run: %d of %d repeats used (%d for one failure)." % (
        total["run_used"], total["run_limit"], facts.limit("budget.per-failure", PER_FAILURE)))
    for k in keys:
        rm = room(k, facts)
        print("  %s: %d of %d (%s)" % (k, rm["used"], rm["limit"], ", ".join(kinds(k, facts)) or "none spent"))
    for g in d["grants"]:
        print("  granted %s more for %s: %s" % (g.get("n"), g.get("key"), g.get("reason")))
    return 0


def main(argv):
    facts = Facts()
    sub = argv[1] if len(argv) > 1 else "show"
    if sub == "spend":
        try:
            rc, line = spend(argv[2:], facts)
        except Exception as e:   # a defect here never stops the call it guards, and says so
            print("WARN: the budget could not be read (%s); the call goes on uncounted" % e, file=sys.stderr)
            return 0
        if line:
            print(line)
        return rc
    if sub == "room" and len(argv) == 3:
        print(json.dumps(room(argv[2], facts)))
        return 0
    if sub == "grant":
        return grant(argv[2:], facts)
    if sub == "show" and len(argv) <= 2:
        return show(facts)
    print("FAIL: usage: temper budget | temper budget grant --key K --reason R", file=sys.stderr)
    return 2


def key_in(call, cli, facts):
    """The key a call (a command line the flow writes) spends now, else None."""
    try:
        w = shlex.split(call)
    except ValueError:
        return None
    at = next((i for i, x in enumerate(w) if x == cli or x == "temper" or x.endswith("/temper")), None)
    hit = key_of(w[at + 1:], facts) if at is not None else None
    return hit[0] if hit else None


def refused(call, cli, facts):
    """The key of a call the budget refuses now, else None."""
    key = key_in(call, cli, facts)
    return key if key and not room(key, facts)["ok"] else None


if __name__ == "__main__":
    sys.exit(main(sys.argv))
