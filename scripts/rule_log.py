#!/usr/bin/env python3
"""rule_log.py: the record of what a rule decided in a run that goes on by itself (9.8.5, WP11, ADR 0019 decision 3).

  python3 rule_log.py append KIND STAGE WHAT     adds {"kind", "stage", "what", "ts"} to .temper/rule-log.json
  python3 rule_log.py show                       prints the record as JSON

The kinds `advance`, `repair`, `group fix` and `covered` are what a rule did: they are written only while the run state
says the run goes on by itself (run_mode autonomous, started at an earlier stage than STAGE) and no stop is open. The
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
RULE_KINDS = ("advance", "repair", "group fix", "covered")
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


def append(kind, stage, what):
    if kind not in RULE_KINDS + ALWAYS:
        print("FAIL: rule_log.py: unknown kind %r" % kind, file=sys.stderr)
        return 2
    if kind in RULE_KINDS and not unattended(read_json(STATE, {}), stage):
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
    return 0


def main(argv):
    if len(argv) == 5 and argv[1] == "append":
        try:
            return append(argv[2], argv[3], argv[4])
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
