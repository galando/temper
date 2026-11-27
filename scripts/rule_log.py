#!/usr/bin/env python3
"""rule_log.py: the record of what a rule decided in a run that goes on by itself (9.8.5, WP11, ADR 0019 decision 3).

  python3 rule_log.py append KIND STAGE WHAT     adds {"kind", "stage", "what", "ts"} to .temper/rule-log.json
  python3 rule_log.py append KIND STAGE WHAT --by-rule    the same, for a step a rule takes in every mode (see append)
  python3 rule_log.py show                       prints the record as JSON

The kinds `advance`, `repair`, `group fix`, `covered` and `amend` (WP25) are what a rule did: they are written only while the run state
says the run goes on by itself (run_mode autonomous, started at an earlier stage than STAGE) and no stop is open, or,
for a step a rule takes in every mode (a repair in the stage, scripts/repair_ops.py; the run again of a timed out group
check; the acceptance tests the flow skips, scripts/check_run.py), in every mode while no stop is open (--by-rule). The
kinds `stop`, `answer` and `ended` are always written: a stop, the person's answer to it, and the end of the unattended
run. Nothing but the CLI calls this; the record is the CLI's (the mod guards the file). Runs in the project folder;
standard library only. A record that cannot be read or written never stops the call that writes it.
"""
import datetime
import json
import os
import sys

TEMPER = ".temper"
PATH = os.path.join(TEMPER, "rule-log.json")
STATE = os.path.join(TEMPER, "build-state.json")
RULE_KINDS = ("advance", "repair", "group fix", "covered", "amend")   # WP25: amend, the plan amendment by rule
ALWAYS = ("stop", "answer", "ended")


def read_json(path, default):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, type(default)) else default
    except (OSError, ValueError):
        return default


def entries():
    return [x for x in read_json(PATH, []) if isinstance(x, dict)]


def unattended(state, stage):
    """The run goes on by itself at this stage: the person started it at an earlier one, and no stop is open."""
    start = state.get("unattended_from")
    return state.get("run_mode") == "autonomous" and bool(start) and start != stage and not state.get("parked")


def append(kind, stage, what, by_rule=False):
    """by_rule: the caller knows a rule took this step whatever the mode (a repair the CLI starts and closes by itself after
    the approval, in a run that asks at every stage too): written while no stop is open (rule 10)."""
    if kind not in RULE_KINDS + ALWAYS:
        print("FAIL: rule_log.py: unknown kind %r" % kind, file=sys.stderr)
        return 2
    state = read_json(STATE, {})
    if kind in RULE_KINDS and not unattended(state, stage) and not (by_rule and not state.get("parked")):
        return 0
    rows = entries()
    rows.append({"kind": kind, "stage": stage or "run", "what": " ".join(str(what).split())[:300] or kind,
                 "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")})
    os.makedirs(TEMPER, exist_ok=True)
    tmp = "%s.tmp.%d" % (PATH, os.getpid())
    with open(tmp, "w") as f:
        json.dump(rows, f, indent=1)
        f.write("\n")
    os.replace(tmp, PATH)
    if kind in ("repair", "group fix", "stop"):   # WP23: the step a rule took is written on the open failure records
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import failure
            failure.set_step([x["id"] for x in failure.open_records(stage=stage) if not x.get("step")], rows[-1]["what"])
        except Exception:
            pass
    return 0


def main(argv):
    if len(argv) in (5, 6) and argv[1] == "append" and argv[5:] in ([], ["--by-rule"]):
        try:
            return append(argv[2], argv[3], argv[4], by_rule=argv[5:] == ["--by-rule"])
        except OSError as e:
            print("WARN: the rule log could not be written (%s)" % e, file=sys.stderr)
            return 0
    if len(argv) == 2 and argv[1] == "show":
        print(json.dumps(entries(), indent=1))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
