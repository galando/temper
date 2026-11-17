#!/usr/bin/env python3
"""check_floor.py: the floor of the scripted runs (scripts/e2e/floor.json), 9.8.5 (WP05).

The floor holds, for each scripted scenario and mode, what a run with no model call did: the dialogs (and by stage and
by kind), the launches by agent type with `launch_total` their sum, the steps the CLI took by itself (`auto`), the steps
back, the hand backs of the run driver and the runs of the whole suite. Each has a `now` value, compared exactly, and
some a `final`, the number of docs/plans/one-go/done.md. The entry `replay` holds the same for the replay of the
measured run (`bun scripts/e2e/replay.ts`), and `replay_base` the numbers of the base (`10e965a`) on that replay.

  python3 scripts/check_floor.py [--floor FILE]                      the shape, and no `final` above its first value
  python3 scripts/check_floor.py --counts FILE [--floor FILE]         each scenario's counts against its `now`
  python3 scripts/check_floor.py --counts FILE --write [--floor FILE] the counts become the `now` values
  python3 scripts/check_floor.py --replay [LINE_FILE]                 the replay's last JSON line against `replay.now`
  python3 scripts/check_floor.py --replay-base [LINE_FILE]            the base column's JSON line against `replay_base`
  python3 scripts/check_floor.py --final [--floor FILE]               also: no `now` above its `final`

COUNTS is the JSON list scripts/e2e/run.ts writes: [{"scenario", "mode", "counts"}]. A replay line is read from the
file named, else from standard input; the last line that holds a JSON object is the one compared.

A scenario on scripts/selftest/expected-fail.txt may have a `final` and no `now`: it has none until it passes, and the
runner counts no listed scenario.

Nothing raises a `final`: a `final` above its value in the commit of the file that first added the key fails, read
from the history of the file in git (a key no commit holds yet is exempt). A rule that read only the file as it is would
be passed by the very commit that raises a value. A `final` removed, or set to a value that is no number, loosens
its bound and fails the same way. In `launches` of a `final`, a type it does not name stands at 0.
A count of `final` is an upper bound; `true` and `false` must be equal. Exit 0 when every rule holds, else 1 (2 for
a wrong call). Python 3 and git only.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FLOOR = os.path.join(HERE, "e2e", "floor.json")
COUNT_KEYS = ("dialogs", "by_stage", "by_kind", "launches", "launch_total", "auto", "back", "handbacks", "suite_runs")
# The keys of the replay entries (done.md row D58); the lists the replay prints are held as their lengths.
REPLAY_KEYS = ("questions", "agent_launches", "agent_launch_total", "loops_recommended", "manual_repairs", "setup_clicks",
               "agent_minutes_estimate", "shipped", "defect_in_commit", "bad_validate_line_in_plan_at_end")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def flat(d, pre=""):
    """{path: value} of a nested object, dicts walked, the path parts joined by '/'."""
    out = {}
    for k, v in d.items():
        p = "%s/%s" % (pre, k) if pre else str(k)
        if isinstance(v, dict):
            out.update(flat(v, p))
        else:
            out[p] = v
    return out


def finals(doc):
    """{path: value} of every `final` of a floor document."""
    out = {}
    for s, modes in (doc.get("scenarios") or {}).items():
        for m, e in (modes or {}).items():
            if isinstance(e, dict) and isinstance(e.get("final"), dict):
                out.update(flat(e["final"], "scenarios/%s/%s/final" % (s, m)))
    rp = doc.get("replay") or {}
    if isinstance(rp.get("final"), dict):
        out.update(flat(rp["final"], "replay/final"))
    return out


def git(cwd, *args):
    p = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else None


def first_values(path, pick):
    """{path: value} of each key at the commit of the file that first added it, oldest commit first."""
    d = os.path.dirname(os.path.abspath(path))
    top = (git(d, "rev-parse", "--show-toplevel") or "").strip()
    if not top:
        return {}
    rel = os.path.relpath(os.path.realpath(path), os.path.realpath(top))
    out = {}
    for c in (git(top, "log", "--reverse", "--format=%H", "--", rel) or "").split():
        text = git(top, "show", "%s:%s" % (c, rel))
        try:
            doc = json.loads(text or "")
        except ValueError:
            continue
        for k, v in pick(doc).items():
            out.setdefault(k, v)
    return out


def raised(cur, first, zero=()):
    """The lines for each value of cur above its value in first (a bool that differs; a key first does not hold is exempt),
    and for each value of first that cur dropped or holds as no number: a removed bound is a raised one. A type that a
    `launches` dict of `zero` (the paths of those still there) no longer names stands at 0, which lowers it."""
    out = []
    for k, f in sorted(first.items()):
        if f is None or k in cur or k.rsplit("/", 1)[0] in zero:
            continue
        out.append("%s is removed, its first committed value is %s: a final is never removed" % (k, json.dumps(f)))
    for k, v in sorted(cur.items()):
        if k not in first:
            continue
        f = first[k]
        if isinstance(v, bool) or isinstance(f, bool):
            if v != f:
                out.append("%s is %s, its first committed value is %s: a final is never changed" % (k, json.dumps(v), json.dumps(f)))
        elif isinstance(f, (int, float)) and not isinstance(v, (int, float)):
            out.append("%s is %s, its first committed value is %s: a final is never removed" % (k, json.dumps(v), f))
        elif isinstance(v, (int, float)) and isinstance(f, (int, float)) and v > f:
            out.append("%s is %s, above its first committed value %s: a final is never raised" % (k, v, f))
    return out


def launch_dicts(doc):
    """The paths of the `launches` dicts of the scenarios' finals (where a type not named stands at 0)."""
    return {"scenarios/%s/%s/final/launches" % (s, m) for s, modes in (doc.get("scenarios") or {}).items()
            for m, e in (modes or {}).items()
            if isinstance(e, dict) and isinstance(e.get("final"), dict) and isinstance(e["final"].get("launches"), dict)}


def within(now, final, where):
    """The lines for each value of now above its final (a bool must equal; in `launches` an unnamed type stands at 0)."""
    out = []
    for k, f in final.items():
        if k in ("launches", "agent_launches") and isinstance(f, dict):
            # a scenario's `launches`: a type its final does not name stands at 0. The replay's `agent_launches` bounds
            # only the types it names (done.md row D58 names the Plan agent alone, beside a total of 7)
            got = now.get(k) or {}
            for t in sorted(set(got) | set(f)):
                n, cap = got.get(t, 0), f.get(t, 0 if k == "launches" else None)
                if cap is not None and n > cap:
                    out.append("%s: %s.%s is %s, above its final %s" % (where, k, t, n, cap))
            continue
        if k not in now:
            out.append("%s: %s has a final and no now value" % (where, k))
            continue
        v = now[k]
        if isinstance(f, bool) or isinstance(v, bool):
            if v != f:
                out.append("%s: %s is %s, its final is %s" % (where, k, json.dumps(v), json.dumps(f)))
        elif isinstance(f, (int, float)) and isinstance(v, (int, float)) and v > f:
            out.append("%s: %s is %s, above its final %s" % (where, k, v, f))
    return out


def differ(want, got, where):
    """The lines for each key where got differs from want, naming both values."""
    out = []
    for k in sorted(set(want) | set(got)):
        if k not in want:
            out.append("%s: %s is %s and the floor holds no value for it" % (where, k, json.dumps(got[k], sort_keys=True)))
        elif k not in got:
            out.append("%s: %s is not counted, the floor holds %s" % (where, k, json.dumps(want[k], sort_keys=True)))
        elif want[k] != got[k]:
            out.append("%s: %s is %s, the floor holds %s" % (where, k, json.dumps(got[k], sort_keys=True), json.dumps(want[k], sort_keys=True)))
    return out


XFAIL_LIST = os.path.join(HERE, "selftest", "expected-fail.txt")


def xfail_listed(scenario, mode):
    """The scenario is on the expected to fail list in this mode (`e2e:<scenario>` or `e2e:<scenario>:<mode>`)."""
    try:
        lines = open(XFAIL_LIST, encoding="utf-8").read().splitlines()
    except OSError:
        return False
    for line in lines:
        words = line.split("#", 1)[0].split()
        if words and words[0] in ("e2e:%s" % scenario, "e2e:%s:%s" % (scenario, mode)):
            return True
    return False


def shape(doc):
    out = []
    if doc.get("version") != 1:
        out.append("the floor's version is not 1")
    for s, modes in (doc.get("scenarios") or {}).items():
        for m, e in (modes or {}).items():
            if m not in ("plain", "mod", "driver"):
                out.append("%s: no mode %s" % (s, m))
            if isinstance(e, dict) and "now" not in e and isinstance(e.get("final"), dict) and xfail_listed(s, m):
                continue   # 9.8.5 (WP06): a scenario on the expected to fail list has no now until it passes
            if not isinstance(e, dict) or not isinstance(e.get("now"), dict):
                out.append("%s [%s]: no now values" % (s, m))
                continue
            miss = [k for k in COUNT_KEYS if k not in e["now"]]
            if miss:
                out.append("%s [%s]: now holds no %s" % (s, m, ", ".join(miss)))
    for name in ("replay", "replay_base"):
        e = doc.get(name)
        vals = (e or {}).get("now") if name == "replay" else e
        if not isinstance(vals, dict):
            out.append("no %s entry" % name)
            continue
        miss = [k for k in REPLAY_KEYS if k not in vals]
        if miss:
            out.append("%s holds no %s" % (name, ", ".join(miss)))
    return out


def replay_line(path):
    text = open(path, encoding="utf-8").read() if path else sys.stdin.read()
    for line in reversed(text.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except ValueError:
                continue
    return None


def replay_values(line):
    """The keys of a replay entry, read off one line the replay printed: a list as its length."""
    out = {}
    for k in REPLAY_KEYS:
        if k in line:
            v = line[k]
            out[k] = len(v) if isinstance(v, list) else v
    return out


def main(argv):
    args = list(argv)
    floor = FLOOR
    counts = None
    line_file = None
    mode = "check"
    write = final = False
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--floor", "--counts") and i + 1 < len(args):
            if a == "--floor":
                floor = args[i + 1]
            else:
                counts = args[i + 1]
            i += 2
            continue
        if a in ("--replay", "--replay-base"):
            mode = a[2:]
            if i + 1 < len(args) and not args[i + 1].startswith("--"):
                line_file = args[i + 1]
                i += 1
        elif a == "--write":
            write = True
        elif a == "--final":
            final = True
        else:
            print("check_floor.py: unknown argument %s (see the header of this file)" % a, file=sys.stderr)
            return 2
        i += 1
    if write and counts is None:
        print("check_floor.py: --write needs --counts", file=sys.stderr)
        return 2
    doc = load(floor)
    problems = []

    if mode in ("replay", "replay-base"):
        line = replay_line(line_file)
        if line is None:
            print("FAIL floor: no JSON line of the replay to compare")
            return 1
        got = replay_values(line)
        want = (doc.get("replay") or {}).get("now") if mode == "replay" else doc.get("replay_base")
        name = "replay" if mode == "replay" else "replay_base"
        problems = differ(want or {}, {k: v for k, v in got.items() if k in (want or {})}, name)
        problems += ["%s: the replay printed no %s" % (name, k) for k in (want or {}) if k not in got]
        for p in problems:
            print("FAIL floor: %s" % p)
        print("floor: the %s entry %s" % (name, "differs" if problems else "agrees"))
        return 1 if problems else 0

    if counts is not None:
        runs = load(counts)
        scen = doc.setdefault("scenarios", {})
        for r in runs:
            s, m, c = r.get("scenario"), r.get("mode"), r.get("counts") or {}
            got = {k: c[k] for k in COUNT_KEYS if k in c}
            if write:
                e = scen.setdefault(s, {}).setdefault(m, {})
                e["now"] = got
                continue
            e = (scen.get(s) or {}).get(m)
            if not isinstance(e, dict) or not isinstance(e.get("now"), dict):
                problems.append("%s [%s]: the floor has no entry for it" % (s, m))
                continue
            problems += differ(e["now"], got, "%s [%s]" % (s, m))
        if write:
            doc["scenarios"] = {s: {m: scen[s][m] for m in ("plain", "mod", "driver") if m in scen[s]} for s in sorted(scen)}
            with open(floor, "w", encoding="utf-8") as f:
                json.dump(doc, f, indent=1, sort_keys=False)
                f.write("\n")
            print("floor: wrote the now values of %d runs to %s" % (len(runs), floor))
            return 0
        for p in problems:
            print("FAIL floor: %s" % p)
        print("floor: %d runs %s" % (len(runs), "differ" if problems else "agree with the floor"))
        return 1 if problems else 0

    problems += shape(doc)
    problems += raised(finals(doc), first_values(floor, finals), launch_dicts(doc))
    if final:
        for s, modes in sorted((doc.get("scenarios") or {}).items()):
            for m, e in sorted((modes or {}).items()):
                if isinstance(e, dict) and isinstance(e.get("final"), dict):
                    problems += within(e.get("now") or {}, e["final"], "%s [%s]" % (s, m))
        rp = doc.get("replay") or {}
        if isinstance(rp.get("final"), dict):
            problems += within(rp.get("now") or {}, rp["final"], "replay")
    for p in problems:
        print("FAIL floor: %s" % p)
    print("floor: %s" % ("FAIL" if problems else "every rule holds%s" % (" (final)" if final else "")))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
