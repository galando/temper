"""drift.py: where the code has moved away from the specs it was built from (9.7.6). Read only; run from the project folder.

  python3 drift.py SPECS_DIR [--json]

For each spec folder whose gate-ledger.json is committed (a finished run), it compares what the spec says with the tree
as it is now:

  missing file    a file the plan creates or changes (plan.md's Files to Create and Files to Modify tables, the File:
                  lines of tasks.md) is gone
  test gone       the test file a scenario's Test: line names is gone, so nothing proves that scenario any more
  changed since   a planned file has commits after the commit that recorded the spec's ledger: not drift by itself, but
                  the place to look when the code no longer does what the spec says

Only the differences are listed; a spec with none says "No drift detected". A spec that is still in progress (no
committed ledger) is skipped. Exit 0 always: drift is information for the person, never a gate. Standard library only.
"""
import json
import os
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


def spec_report(spec):
    ledger = os.path.join(spec, "gate-ledger.json")
    since = git("log", "-1", "--format=%H", "--", ledger)
    if not since:
        return None
    out = {"spec": spec, "since": since[:12], "missing": [], "tests_gone": [], "changed": []}
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
    return out


def text(reports):
    lines = ["# Spec drift", ""]
    if not reports:
        return "\n".join(lines + ["No finished spec to compare (no committed gate-ledger.json under the specs folder)."])
    for r in reports:
        lines.append("## %s (since %s)" % (os.path.basename(r["spec"]), r["since"]))
        rows = ["- missing file: %s (the plan creates or changes it)" % f for f in r["missing"]]
        rows += ["- test gone: %s (scenario '%s' has nothing that proves it)" % (t["file"], t["scenario"]) for t in r["tests_gone"]]
        rows += ["- changed since: %s (%d commit(s) after the spec)" % (c["file"], c["commits"]) for c in r["changed"]]
        lines += rows or ["No drift detected"]
        lines.append("")
    return "\n".join(lines).rstrip()


def main(argv):
    if len(argv) not in (2, 3) or (len(argv) == 3 and argv[2] != "--json"):
        print(__doc__, file=sys.stderr)
        return 2
    root = argv[1]
    reports = []
    if os.path.isdir(root):
        for name in sorted(os.listdir(root)):
            spec = os.path.join(root, name)
            if os.path.isdir(spec) and not os.path.islink(spec):
                r = spec_report(spec)
                if r is not None:
                    reports.append(r)
    print(json.dumps(reports) if len(argv) == 3 else text(reports))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
