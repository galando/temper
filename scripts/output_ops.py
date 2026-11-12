"""output_ops.py: `temper output <stage>|G<n>` (9.8.4), the last output of a gate or a group gate, read only.

  python3 output_ops.py TEMPER_DIR G<n>      the group's last Validate run: its command, exit, the FAIL lines it kept and
                                             the tail of its output (the build ledger, phase `group`)
  python3 output_ops.py TEMPER_DIR STAGE     the stage gate's failed rows (gates.json), then the stage's last failed run the
                                             CLI recorded with its output (or its last run when none failed)

With the mod on, the session may run the CLI and a few reading commands, not printenv or a test runner, so it could not
look at a failure it was asked about. This prints what the CLI already recorded; it runs nothing and writes nothing.
Exit 1 when there is nothing recorded to show. Standard library only.
"""
import json
import os
import re
import sys

STAGES = ("intent", "plan", "design", "build", "review", "check", "commit", "rca", "fix", "pipeline")


def load(path, default):
    try:
        with open(path, encoding="utf-8") as fh:
            d = json.load(fh)
    except (OSError, ValueError):
        return default
    return d if isinstance(d, type(default)) else default


def show_run(r):
    cmd = r.get("cmd") or r.get("claim") or "(no command)"
    print("%s (exit %s)%s" % (cmd, r.get("exit_code"), " at %s" % r["ts"] if r.get("ts") else ""))
    lines = [str(x) for x in r.get("fail_lines") or []]
    if lines:
        print("What failed:")
        for x in lines:
            print(x)
    out = str(r.get("output") or "").rstrip("\n")
    if out:
        print("Output (its last %d characters, as recorded):" % len(out))
        print(out)


def main(argv):
    if len(argv) != 3:
        print("FAIL: usage: temper output <stage>|G<n>", file=sys.stderr)
        return 2
    tdir, what = argv[1], argv[2]
    if re.fullmatch(r"G\d+", what):
        rows = [r for r in load(os.path.join(tdir, "evidence", "build.json"), [])
                if isinstance(r, dict) and r.get("phase") == "group" and r.get("group") == what]
        gate = ((load(os.path.join(tdir, "groups.json"), {}).get("groups") or {}).get(what) or {}).get("gate") or {}
        if gate:
            print("Group %s gate: %s%s" % (what, gate.get("verdict"), " (%s)" % gate["reason"] if gate.get("reason") else ""))
        if not rows:
            print("%s: no Validate run is recorded" % what if not gate else "No Validate run of %s is recorded." % what)
            return 1
        show_run(rows[-1])
        return 0
    if what not in STAGES:
        print("FAIL: usage: temper output <stage>|G<n> (a stage is one of %s)" % ", ".join(STAGES), file=sys.stderr)
        return 2
    gate = load(os.path.join(tdir, "gates.json"), {}).get(what) or {}
    shown = False
    if gate:
        print("%s gate: %s" % (what.capitalize(), gate.get("verdict")))
        for q in gate.get("requirements") or []:
            if isinstance(q, dict) and not q.get("pass"):
                print("  %s: %s" % (q.get("name"), q.get("detail")))
        shown = True
    runs = [r for r in load(os.path.join(tdir, "evidence", "%s.json" % what), [])
            if isinstance(r, dict) and (r.get("output") or r.get("cmd")) and isinstance(r.get("exit_code"), int)]
    failed = [r for r in runs if r.get("exit_code") != 0]
    pick = failed[-1] if failed else (runs[-1] if runs else None)
    if pick is not None:
        print("Its last %s run:" % ("failed" if failed else "recorded"))
        show_run(pick)
        shown = True
    if not shown:
        print("%s: no gate verdict and no run recorded" % what)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
