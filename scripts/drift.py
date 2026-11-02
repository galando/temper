"""drift.py: where the code has moved away from the specs it was built from (9.7.6). Read only; run from the project folder.

  python3 drift.py SPECS_DIR [--run] [--json]

For each spec folder whose gate-ledger.json is committed (a finished run), it compares what the spec says with the tree
as it is now:

  missing file    a file the plan creates or changes (plan.md's Files to Create and Files to Modify tables, the File:
                  lines of tasks.md) is gone
  test gone       the test file a scenario's Test: line names is gone, so nothing proves that scenario any more
  changed since   a planned file has commits after the commit that recorded the spec's ledger: not drift by itself, but
                  the place to look when the code no longer does what the spec says
  behavior        (--run) a scenario's Test: command fails now: the code no longer does what the scenario says. Each runs
                  from the project folder, at most 300 seconds, without the environment's credential-named variables

Only the differences are listed; a spec with none says "No drift detected". A spec that is still in progress (no
committed ledger) is skipped. Exit 0 always: drift is information for the person, never a gate. Standard library only.
"""
import json
import os
import re
import subprocess
import sys

import acceptance
import flow
import gate_rows


def git(*args):
    try:
        return subprocess.run(["git"] + list(args), capture_output=True, text=True, timeout=30).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


CREDENTIAL = re.compile(r"(^|_)(KEY|TOKEN|SECRET|PASSWORD)(_|$)", re.I)


def run_test(cmd):
    """(exit code, last line) of a scenario's Test: command, run as the CLI runs one: from the project folder, no input,
    without credential-named variables, at most 300 seconds."""
    env = {k: v for k, v in os.environ.items() if not CREDENTIAL.search(k)}
    try:
        r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, timeout=300, env=env, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return 124, "timed out after 300 s"
    except OSError as e:
        return 127, str(e)
    tail = (r.stdout + r.stderr).strip().splitlines()
    return r.returncode, tail[-1][:160] if tail else ""


def spec_report(spec, run=False):
    ledger = os.path.join(spec, "gate-ledger.json")
    since = git("log", "-1", "--format=%H", "--", ledger)
    if not since:
        return None
    out = {"spec": spec, "since": since[:12], "missing": [], "tests_gone": [], "changed": [], "failing": []}
    for f in flow.plan_files(spec):
        if any(ch in f for ch in "*?["):
            continue
        if not os.path.exists(f):
            out["missing"].append(f)
            continue
        n = git("rev-list", "--count", "%s..HEAD" % since, "--", f)
        if n.isdigit() and int(n) > 0:
            out["changed"].append({"file": f, "commits": int(n)})
    intent = os.path.join(spec, "intent.md")
    if os.path.isfile(intent):
        with open(intent, encoding="utf-8") as fh:
            blocks = acceptance.scenario_blocks(fh.read().splitlines())
        for b in blocks:
            tf = gate_rows.test_file_of(b.get("cmd") or "")
            if tf and not os.path.exists(tf):
                out["tests_gone"].append({"scenario": b["name"], "file": tf})
            elif run and b.get("cmd") and b["cmd"].strip().lower() != "manual":
                code, last = run_test(b["cmd"])
                if code != 0:
                    out["failing"].append({"scenario": b["name"], "cmd": b["cmd"], "exit": code, "last": last})
    return out


def text(reports):
    lines = ["# Spec drift", ""]
    if not reports:
        return "\n".join(lines + ["No finished spec to compare (no committed gate-ledger.json under the specs folder)."])
    for r in reports:
        lines.append("## %s (since %s)" % (os.path.basename(r["spec"]), r["since"]))
        rows = ["- missing file: %s (the plan creates or changes it)" % f for f in r["missing"]]
        rows += ["- test gone: %s (scenario '%s' has nothing that proves it)" % (t["file"], t["scenario"]) for t in r["tests_gone"]]
        rows += ["- behavior: scenario '%s' fails now (%s, exit %d): %s" % (t["scenario"], t["cmd"], t["exit"], t["last"]) for t in r["failing"]]
        rows += ["- changed since: %s (%d commit(s) after the spec)" % (c["file"], c["commits"]) for c in r["changed"]]
        lines += rows or ["No drift detected"]
        lines.append("")
    return "\n".join(lines).rstrip()


def main(argv):
    flags = argv[2:]
    if len(argv) < 2 or any(f not in ("--json", "--run") for f in flags):
        print(__doc__, file=sys.stderr)
        return 2
    root, run = argv[1], "--run" in flags
    reports = []
    if os.path.isdir(root):
        for name in sorted(os.listdir(root)):
            spec = os.path.join(root, name)
            if os.path.isdir(spec) and not os.path.islink(spec):
                r = spec_report(spec, run)
                if r is not None:
                    reports.append(r)
    print(json.dumps(reports) if "--json" in flags else text(reports))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
