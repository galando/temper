#!/usr/bin/env python3
"""budget.py: the one budget of a run (9.8.5, WP10, ADR 0019 decision 1). Every repeat that follows a failed check spends
one entry of `.temper/budget.json`: 2 for one failure (its key) and 6 for one run, plus what the person granted.

  python3 budget.py spend <words of a temper call>    the CLI's dispatcher, before a call of SPENDS: prints nothing and
                                                      exits 0 when the call spends nothing; appends one entry and prints
                                                      `OK: repeat ...`; or prints `BLOCKED: ...`, writes nothing, exits 1
  python3 budget.py room <key>                        prints {"used", "limit", "run_used", "run_limit", "ok"} as JSON
  python3 budget.py grant --key K --reason R          the person's answer at the question run.budget: two more for K
                                                      and for the run
  python3 budget.py revise --key plan-revise:R --reason T
                                                      the before call of a launch of the narrow revise agent (WP27,
                                                      `temper budget revise`): it spends one of plan-revise:<reason>;
                                                      a launch the call before it paid for (paid_by) counts for its
                                                      reason and not again for the run: one launch, one spend
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
KEY_RE = re.compile(r"^(?:gate:[a-z]+|group:G\d+|task:\d+|acceptance|pipeline|plan-revise:[a-z][a-z-]*)$")

# The calls that spend, by their first words: the kind of their entry, and when they spend (key_of holds the rule).
SPENDS = (
    (("state", "loop"), "step back", "the gate of <from> is FAIL and not skipped: gate:<from>; from Build, a group whose "
                                     "check is FAIL or that is parked: group:<G>, or tasks with no groups: gate:build"),
    (("state", "redo"), "run again", "the gate of the stage is FAIL and not skipped: gate:<stage>; at Pipeline, not "
                                     "when a CI fix round paid for that failure (one round is one entry)"),
    (("group", "fix"), "group fix", "with no flag: group:<G>"),
    (("group", "reopen"), "tasks again", "the group's gate is FAIL or the group is parked: group:<G>"),
    (("group", "gate"), "more time", "with --timeout-s, at a group gate that is FAIL already, when the base did not measure "
                                     "the group's suite (WP20): group:<G>; with no flag at a gate that is FAIL: group:<G>, "
                                     "check again (rule 9: group fix --commit, group reopen and plan patch clear it first)"),
    (("plan", "patch"), "plan patch", "always: group:<G>, task:<N>, or gate:build for the Integration line (WP25: spent by "
                                      "scripts/plan_patch.py once every check of the patch holds)"),
    (("plan", "amend"), "plan amend", "always: task:<N> (WP25: the amendment by rule, spent by scripts/plan_amend.py once "
                                      "every check of it holds)"),
    (("task", "retry"), "task again", "always: task:<N>"),
    (("task", "start"), "task relaunch", "of a task whose gate failed (its record holds a failed attempt): task:<N> "
                                         "(BLACKBOX-3: attempts 2 and 3 of a failing task are the two counted repeats of "
                                         "its one failure; a task's first start, and the start after `group reopen`, "
                                         "spend nothing)"),
    (("task", "test"), "check again", "--phase green of a task that holds env_fault: task:<N>"),
    (("acceptance", "reopen"), "test corrected", "always: acceptance"),
    (("state", "set", "pipeline_round"), "CI fix", "always: pipeline (the entry marks the failed Pipeline it answers)"),
    (("state", "set", "next_stage"), "step back", "to a stage before the one the run is at: as state loop "
                                                  "<that stage> <to>"),
    (("integrate",), "merge again", "the integration record is FAIL and no repeat of gate:build paid for it: gate:build"),
    (("check", "run"), "run anyway", "with --fresh (WP22, the person's Run it anyway): gate:check; `group gate G --fresh` "
                                     "spends group:<G>, `integrate --fresh` gate:build"),
    (("budget", "revise"), "revise", "always: --key plan-revise:<reason> (WP27: a launch of the narrow revise agent, its "
                                     "before call; the flow launches the planner after two before the approval). A launch "
                                     "that the person's run again or a step back into Plan paid for counts for its reason, "
                                     "not again for the run (paid_by)"),
    (("repair", "start"), "repair", "the gate of --stage is FAIL and not skipped, or it is Review: gate:<stage> (WP24: the repair "
                                    "in the stage, spent by scripts/repair_ops.py once every condition holds)"),
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
        self.pending = []   # the entries the calls before this one of a list would write (refused_seq)

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
            v = self._run.cfg(key)
        else:
            import config_yaml
            v = str(config_yaml.get(config_yaml.load(os.path.join(".claude", "temper.config")), key))
        return int(v) if re.fullmatch(r"\d+", v.strip()) else default


def integration(facts):
    """The integration record when it is FAIL, with the mark an entry of gate:build carries when it pays for it."""
    i = facts.groups().get("integration") if isinstance(facts.groups().get("integration"), dict) else {}
    if i.get("verdict") != "FAIL":
        return None
    return "%s|%s" % (i.get("ts", ""), i.get("reason", ""))


def stages(facts):
    """The run's own stage sequence as the CLI orders it (_run_seq of scripts/temper): a fix run's, else the full
    one."""
    from flow_base import SEQ
    return list(SEQ["fix"]) if facts.state().get("command") == "fix" else list(SEQ["temper"]) + ["pipeline"]


def failure(stage, facts):
    """The failed verdict of a stage as the mark an entry carries when it pays for it (its time and its failed rows);
    None when the gate did not fail."""
    if not facts.failed(stage):
        return None
    r = facts.run()
    g = r.gates.get(r.gate_of(stage)) if isinstance(r.gates.get(r.gate_of(stage)), dict) else {}
    return "%s|%s" % (g.get("ts", ""), ";".join(str(x.get("detail") or x.get("name")) for x in r.failed_rows(stage)))


def paid(key, mark, facts):
    """Whether an entry of the key already paid for the failure of this mark."""
    return bool(mark) and any(x.get("key") == key and x.get("of") == mark for x in record(facts)["used"])


def key_of(words, facts):
    """(key, kind) when the call of these words (after `temper`) spends now, else None."""
    w = [str(x) for x in words] + ["", "", "", ""]
    a, b, c, e = w[:4]
    if a == "state" and b in ("loop", "redo"):
        if b == "redo" and c == "pipeline" and paid("pipeline", failure("pipeline", facts), facts):
            return None   # the CI fix round that answers this failure paid for it: CI read again is part of the round
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
    if a == "budget" and b == "revise":
        key = next((y for x, y in zip(words, list(words[1:])) if x == "--key"), "")
        return (key, "revise") if key.startswith("plan-revise:") and KEY_RE.match(key) else None
    if a == "repair" and b == "start":
        st = next((y for x, y in zip(words, list(words[1:])) if x == "--stage"), "")
        return ("gate:" + st, "repair") if st and (facts.failed(st) or st == "review") else None   # a passed Review: the click
    if a == "state" and b == "set" and c == "pipeline_round":
        return "pipeline", "CI fix"
    if a == "state" and b == "set" and c == "next_stage":
        # a step back by next_stage is the step back of state loop (cmd_state_set calls _go_back as it does)
        cur, seq = str(facts.state().get("next_stage") or ""), stages(facts)
        back = cur in seq and e in seq and seq.index(e) < seq.index(cur)
        return key_of(["state", "loop", cur, e], facts) if back else None
    if "--fresh" in [str(x) for x in words] and (a, b) in (("check", "run"), ("group", "gate"), ("integrate", b)):
        # WP22: a run whatever the reuse store holds is one counted repeat, always
        key = "gate:check" if a == "check" else "gate:build" if a == "integrate" else (
            "group:" + c if re.fullmatch(r"G\d+", c) else None)
        return (key, "run anyway") if key else None
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
        if (group.get("gate") or {}).get("verdict") != "FAIL":
            return None
        if not more:   # rule 9: the paid ways back (group fix --commit, reopen, plan patch) clear the gate before its check,
            return "group:" + c, "check again"   # so a check of a gate that is FAIL still is a repeat nobody paid for yet
        # WP20: a time out of a suite the base measured is no repeat (its limit came from the base); else one is spent
        import baseline
        val = next((g.get("validate") or "" for g in (facts.run().plan or {}).get("groups") or [] if g.get("id") == c), "")
        return None if val and baseline.measured(val) else ("group:" + c, "more time")
    if a == "plan" and b == "patch":
        key = "task:" + e if c == "task" and e.isdigit() else "gate:build" if c == "integration" else (
            "group:" + c if re.fullmatch(r"G\d+", c) else None)
        return (key, "plan patch") if key else None
    if a == "plan" and b == "amend":
        return ("task:" + e, "plan amend") if c == "task" and e.isdigit() else None
    if a == "task" and b == "retry":
        return ("task:" + c, "task again") if c.isdigit() else None
    if a == "task" and b == "start":
        # BLACKBOX-3: a failed task the flow starts again is one counted repeat of its failure (D08: 2 per failure, then
        # one question); its first start, and the start of a task `group reopen` set back to its first attempt, spend
        # nothing. The failed attempt is the record's (groups.json, the one read the Run class reads too).
        t = (facts.groups().get("tasks") or {}).get(c)
        failed = isinstance(t, dict) and (t.get("status") == "failed" or any(
            isinstance(x, dict) and x.get("outcome") == "FAIL" for x in t.get("attempts") or []))
        return ("task:" + c, "task relaunch") if c.isdigit() and failed else None
    if a == "task" and b == "test":
        green = any(x == "--phase" and y == "green" for x, y in zip(words, list(words[1:]))) or "--phase=green" in words
        task = (facts.groups().get("tasks") or {}).get(c)
        return ("task:" + c, "check again") if green and isinstance(task, dict) and task.get("env_fault") else None
    if a == "acceptance" and b == "reopen":
        return "acceptance", "test corrected"
    if a == "integrate":
        mark = integration(facts)
        return ("gate:build", "merge again") if mark and not paid("gate:build", mark, facts) else None
    return None


def paid_by(facts):
    """The entry that already paid for this launch of the revise agent, else None (one launch, one spend). The person's run
    again at a failed plan gate, or a step back into Plan that answers a failure, spent one entry, and the revise agent is
    what that call launches. It is the record's latest entry, written by the latest step into Plan (the same reason), and
    no launch of Plan ran since (the plan gate has no verdict)."""
    used = record(facts)["used"]
    e = used[-1] if used else {}
    if e.get("kind") not in ("run again", "step back") or str(e.get("key") or "").startswith("plan-revise:"):
        return None
    from flow_base import loop_at
    r = facts.run()
    redo = facts.state().get("redo") if isinstance(facts.state().get("redo"), dict) else {}
    back = r.loop_into("plan")
    steps = ([(str(redo.get("ts") or ""), redo.get("reason"))] if redo.get("stage") == "plan" else []) + (
        [(loop_at(back), back.get("reason"))] if back else [])
    if not steps or r.verdict("plan") is not None:
        return None
    why = max(steps, key=lambda x: x[0])[1]
    return e if " ".join(str(why or "").split())[:200] == e.get("why") else None


def fits(key, kind, facts):
    """(room of the key, whether one more entry of it fits): the key's own limit, and the run's unless the launch was paid."""
    rm = room(key, facts)
    paid = kind == "revise" and paid_by(facts) is not None
    return rm, rm["used"] < rm["limit"] and (paid or rm["run_used"] < rm["run_limit"])


def record(facts):
    """The record of this run: a record of another run id, or one that cannot be read, counts as empty."""
    rid = facts.state().get("run_id") or ""
    d = read_json(PATH, {})
    if not rid or d.get("run") != rid:
        return {"v": 1, "run": rid, "used": list(facts.pending), "grants": []}
    return {"v": 1, "run": rid, "used": [x for x in d.get("used") or [] if isinstance(x, dict)] + list(facts.pending),
            "grants": [x for x in d.get("grants") or [] if isinstance(x, dict)]}


def room(key, facts):
    d = record(facts)
    n = lambda x: int(x.get("n") or 0) if str(x.get("n") or 0).isdigit() else 0
    used = sum(1 for x in d["used"] if x.get("key") == key)
    limit = facts.limit("budget.per-failure", PER_FAILURE) + sum(n(x) for x in d["grants"] if x.get("key") == key)
    run_used = sum(1 for x in d["used"] if not x.get("paid_by"))   # a paid launch counts for its key only
    run_limit = facts.limit("budget.per-run", PER_RUN) + sum(n(x) for x in d["grants"])
    return {"used": used, "limit": limit, "run_used": run_used, "run_limit": run_limit,
            "ok": used < limit and run_used < run_limit}


def kinds(key, facts):
    return [str(x.get("kind")) for x in record(facts)["used"] if x.get("key") == key]


def what(key):
    """The key in the person's words."""
    kind, _, name = key.partition(":")
    return {"gate": name.capitalize(), "group": "Group %s's check" % name, "task": "Task %s" % name,
            "acceptance": "The acceptance test", "pipeline": "The CI fix",
            "plan-revise": "The revision of the plan (%s)" % name.replace("-", " ")}.get(kind, key)


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


def entry(key, kind, words, facts):
    """The entry a call that spends writes."""
    why = next((y for x, y in zip(words, list(words[1:])) if x == "--reason"), "") or " ".join(str(x) for x in words)
    e = {"key": key, "kind": kind, "stage": facts.state().get("next_stage") or "",
         "why": " ".join(str(why).split())[:200], "ts": now()}
    # the failure this repeat answers: a merge after a failed integrate, or the CI read again in the same fix round,
    # spends nothing more
    mark = integration(facts) if key == "gate:build" else failure("pipeline", facts) if key == "pipeline" else None
    if mark:
        e["of"] = mark
    paid = paid_by(facts) if kind == "revise" else None
    if paid:
        e["paid_by"] = "%s %s" % (paid.get("key"), paid.get("ts"))
    return e


def spend(words, facts):
    """(exit code, line) of one call: the entry is written only when the call spends and both limits have room."""
    hit = key_of(words, facts) if facts.state().get("run_id") else None
    if hit is None:
        return 0, ""
    key, kind = hit
    if kind == "run anyway" and facts.run().armed():   # WP22 step 11: the person's option; a run on its own never takes it
        return 1, "BLOCKED: Run it anyway (--fresh) is the person's answer at a question; a run that goes on by itself never takes it"
    rm, ok = fits(key, kind, facts)
    if rm["used"] >= rm["limit"]:
        return 1, "BLOCKED: %s was repeated %d times (limit %d); the person grants more at the question" % (
            key, rm["used"], rm["limit"])
    if not ok:
        return 1, "BLOCKED: this run made %d repeats (limit %d); the person grants more at the question" % (
            rm["run_used"], rm["run_limit"])
    d = record(facts)
    e = entry(key, kind, words, facts)
    d["used"].append(e)
    os.makedirs(TEMPER, exist_ok=True)
    save(d)
    return 0, "OK: repeat %d of %d for %s (%d of %d in this run%s)" % (
        rm["used"] + 1, rm["limit"], key, rm["run_used"] + (0 if e.get("paid_by") else 1), rm["run_limit"],
        "; paid by %s" % e["paid_by"] if e.get("paid_by") else "")


def grant(argv, facts):
    key = next((y for x, y in zip(argv, argv[1:]) if x == "--key"), "")
    reason = " ".join(next((y for x, y in zip(argv, argv[1:]) if x == "--reason"), "").split())
    if not KEY_RE.match(key) or not reason:
        print("FAIL: usage: temper budget grant --key gate:<stage>|group:G<n>|task:<n>|acceptance|pipeline|plan-revise:<reason> "
              "--reason '<why>'",
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
    if sub == "revise":   # WP27: one launch of the revise agent; refused (exit 1, nothing written) at the limit
        w = ["budget"] + argv[1:]
        rc, line = spend(w, facts) if key_of(w, facts) else (1, "FAIL: usage: temper budget revise --key plan-revise:<reason> "
                                                                "--reason R")
        if line:
            print(line)
        return rc
    if sub == "show" and len(argv) <= 2:
        return show(facts)
    print("FAIL: usage: temper budget | temper budget grant --key K --reason R", file=sys.stderr)
    return 2


def words_of(call, cli):
    """The words after `temper` of a command line the flow writes, else None."""
    try:
        w = shlex.split(call)
    except ValueError:
        return None
    at = next((i for i, x in enumerate(w) if x == cli or x == "temper" or x.endswith("/temper")), None)
    return w[at + 1:] if at is not None else None


def key_in(call, cli, facts):
    """The key a call (a command line the flow writes) spends now, else None."""
    w = words_of(call, cli)
    hit = key_of(w, facts) if w is not None else None
    return hit[0] if hit else None


def refused(calls, cli, facts):
    """The key of the first call of a list, run in order, that the budget refuses: each call before it counted as
    spent, so the calls of one option are checked together against both limits; else None."""
    saved = facts.pending
    facts.pending = []
    try:
        for call in calls:
            w = words_of(call, cli)
            hit = key_of(w, facts) if w is not None else None
            if hit and not fits(hit[0], hit[1], facts)[1]:
                return hit[0]
            if hit:
                facts.pending = facts.pending + [entry(hit[0], hit[1], w, facts)]
        return None
    finally:
        facts.pending = saved


if __name__ == "__main__":
    sys.exit(main(sys.argv))
