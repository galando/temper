"""runs.py: which recorded test runs count at a gate, and voiding a false pass (9.8.5, Q3).

  python3 runs.py build LEDGER              "red green after": the Build gate's failing-first counts
  python3 runs.py check LEDGER [ROOT [SPEC]] "n|red claims": the Check gate's passing runs and the claims whose last run failed
  python3 runs.py void LEDGER ID REASON     marks the passing run #ID void, with the reason; the row stays, it counts no more

A run counts when the CLI ran it (`temper evidence run`, a task test, a group check, integrate, Check) or the person
confirmed it. A row an agent wrote with `temper evidence add --exit N` is a claim: the CLI never saw that exit code (a
source run kept a GREEN an agent recorded after a run that had failed before it started), so it counts at no gate, and
no key of the config makes it count (WP30).

A void row never counts. Only a pass can be voided: voiding a failure would make a gate easier to pass.
Standard library only.
"""
import json
import os
import re
import sys
import time


def load(path):
    try:
        rows = json.load(open(path, encoding="utf-8"))
        return rows if isinstance(rows, list) else []
    except (OSError, ValueError):
        return []


def counts(r):
    return isinstance(r, dict) and not r.get("voided") and r.get("executed_by") in ("cli", "person")


def is_test(r):
    return bool(re.search("test", r.get("claim") or "", re.I))


def build(rows):
    rows = [r for r in rows if counts(r) and is_test(r)]
    red = [i for i, r in enumerate(rows) if r.get("phase") == "red" and r.get("exit_code") not in (0, None)]
    green = [i for i, r in enumerate(rows) if r.get("phase") == "green" and r.get("exit_code") == 0]
    after = sum(1 for i in green if red and i > red[0])
    return "%d %d %d" % (len(red), len(green), after)


def own_suite(root="", spec=""):
    """The commands that are the project's suite (check_run.suite_owner: the config's, the detected, the plan's
    Integration line), its plain and its coverage form. Empty when none is known: then the suite is the one the Check
    agent finds and runs with `temper evidence run --claim tests` (agents/check.md)."""
    if not root:
        return set()
    import check_run
    if spec and not os.path.isabs(spec):
        spec = os.path.join(root, spec)
    o = check_run.suite_owner(root, None, spec)
    return {c for c in (o.get("test"), o.get("run")) if c}


def suite_runs(rows, own=()):
    """The runs the row `tests pass` reads (rule 5): a run the CLI made or the person confirmed, of a test claim, no
    scenario's trace and no acceptance run (a correction names its tests: 'corrected after the lock: test_...'), and,
    when the suite is known, a run of the suite's own command: a run of another command under the suite's claim (an
    agent's `evidence run --claim tests -- true`) stands for no run of the suite."""
    return [r for r in rows if counts(r) and not r.get("scenario") and isinstance(r.get("exit_code"), int)
            and is_test(r) and not (r.get("claim") or "").startswith("acceptance (written before Build)")
            and (not own or r.get("cmd") in own)]


def check(rows, own=()):
    runs = suite_runs(rows, own)
    last = {}
    for r in runs:
        last[" ".join(str(r.get("claim")).lower().split())] = r
    red = [k for k, r in last.items() if r.get("exit_code") != 0]
    return "%d|%s" % (sum(1 for r in runs if r.get("exit_code") == 0), "; ".join(red)[:300])


def void(path, id_s, reason):
    rows = load(path)
    reason = " ".join((reason or "").split())
    if not reason:
        return "FAIL: temper evidence void needs --reason '<why this pass is false>'"
    try:
        idx = int(id_s)
    except ValueError:
        return "FAIL: --id must be the 1-based number shown by 'temper evidence list'"
    if idx < 1 or idx > len(rows) or not isinstance(rows[idx - 1], dict):
        return "FAIL: no row #%s in this stage (it has %d)" % (id_s, len(rows))
    r = rows[idx - 1]
    if r.get("voided"):
        return "FAIL: row #%s is void already" % id_s
    if r.get("exit_code") != 0:
        return "FAIL: row #%s is not a pass (exit %s); only a pass is voided, so a gate never gets easier" % (id_s, r.get("exit_code"))
    r["voided"] = {"reason": reason, "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(rows, f, indent=2)
    os.replace(tmp, path)
    return "OK: row #%s is void (%s); it stays in the ledger and counts no more" % (id_s, reason)


def main(argv):
    if len(argv) == 3 and argv[1] == "build":
        print(build(load(argv[2])))
        return 0
    if len(argv) in (3, 4, 5) and argv[1] == "check":   # check LEDGER [ROOT [SPEC]]: the suite of ROOT's config and plan
        print(check(load(argv[2]), own_suite(*argv[3:5])))
        return 0
    if len(argv) == 5 and argv[1] == "void":
        out = void(argv[2], argv[3], argv[4])
        print(out, file=sys.stderr if out.startswith("FAIL") else sys.stdout)
        return 1 if out.startswith("FAIL") else 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
