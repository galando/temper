#!/usr/bin/env python3
"""cli_words.py: the CLI words that take the place of the calls of the flow that were no CLI calls (9.8.5, WP16).

  python3 cli_words.py GROUPS take-out G SHA...      `temper group take-out G SHA...`: the commits the CLI did not make,
                                                     taken out of the group's branch newest first (each one a rebase of
                                                     its worktree onto its parent), only when they are commits the CLI
                                                     recorded as not its own and the newest of that branch
  python3 cli_words.py GROUPS feedback G --text T    `temper group feedback G --text T`: the person's change of a passed
                                                     group, recorded as the next `feedback #K` row of the Build ledger;
                                                     the question after it (Which task changes?) carries K
  python3 drift.py SPECS ask --path P --why W --change C
                                                     `temper drift ask`: a Build or Fix agent records a file outside the
                                                     plan that it needs (drift_ask below): the CLI asks the Scope drift
                                                     question about it before anything else of the stage

Each was a line the session ran as it was written (a rebase, a feedback row whose number the session counted, a DRIFT
section the session read from an agent's panel). A CLI word checks what it is given, and the mod's run driver runs it
like any other call of the CLI. Runs in the project folder; standard library only. The rows go through the CLI's own
`evidence add`, so the ledger has one writer.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPER = os.path.join(HERE, "temper")


def fail(text):
    print("FAIL: %s" % text, file=sys.stderr)
    return 1


def git(*args):
    p = subprocess.run(["git"] + list(args), capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else ""


def read_json(path, default):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, type(default)) else default
    except (OSError, ValueError):
        return default


def evidence(stage, phase, claim):
    p = subprocess.run([TEMPER, "evidence", "add", "--stage", stage, "--phase", phase, "--claim", claim], capture_output=True, text=True)
    if p.returncode != 0:
        return fail("evidence add: %s" % (p.stderr or p.stdout).strip()[-300:])
    return 0


def take_out(groups, g, shas):
    """The two conditions of the question that offered it, checked again here: the commits are ones the CLI recorded as
    not its own for this group, and they are the newest of a worktree of the group (its own, or a task's)."""
    d = read_json(groups, {})
    grp = (d.get("groups") or {}).get(g)
    if not re.fullmatch(r"G\d+", g or "") or not isinstance(grp, dict) or not shas:
        return fail("usage: temper group take-out G<n> SHA... (a group of the run, and the commits to take out)")
    known = list(((d.get("integration") or {}).get("foreign") or {}).get(g) or []) + list(grp.get("parked_foreign") or [])
    full = []
    for s in shas:
        hit = sorted({x for x in known if isinstance(x, str) and re.fullmatch(r"[0-9a-f]{4,40}", s) and x.startswith(s)})
        if len(hit) != 1:
            return fail("%s is no commit the CLI recorded as not its own in group %s" % (s, g))
        full.append(hit[0])
    tasks = [t for t in (d.get("tasks") or {}).values() if isinstance(t, dict) and t.get("group") == g]
    trees = [w for w in [grp.get("worktree")] + [t.get("worktree") for t in tasks] if w and os.path.isdir(w)]
    for wt in trees:
        tip = git("-C", wt, "rev-list", "--first-parent", "-n", str(len(full)), "HEAD").split()
        if set(tip) != set(full):
            continue
        for x in tip:   # newest first
            p = subprocess.run(["git", "-C", wt, "rebase", "--autostash", "--onto", x + "~1", x], capture_output=True, text=True)
            if p.returncode != 0:
                return fail("git rebase of %s in %s: %s" % (x[:7], wt, (p.stderr or p.stdout).strip()[-300:]))
        print("OK: took %s out of group %s's branch" % (", ".join(x[:7] for x in tip), g))
        return 0
    if not trees:
        return fail("group %s has no worktree, so its commits cannot be taken out here" % g)
    return fail("%s are not the newest commits of group %s's branch, so they cannot be taken out here" % (", ".join(s[:7] for s in full), g))


def feedback(g, argv):
    if not re.fullmatch(r"G\d+", g or "") or len(argv) != 2 or argv[0] != "--text" or not argv[1].strip():
        return fail("usage: temper group feedback G<n> --text '<what should change>'")
    rows = read_json(os.path.join(".temper", "evidence", "build.json"), [])
    k = next_feedback(rows)
    text = " ".join(argv[1].split())[:2000]
    if evidence("build", "feedback", "feedback #%d: Group %s: %s" % (k, g, text)):
        return 1
    print("OK: feedback #%d recorded for group %s" % (k, g))
    return 0


def next_feedback(rows):
    """The number the next `feedback #K` row of the Build ledger takes."""
    nums = [int(m.group(1)) for x in rows if isinstance(x, dict) for m in [re.match(r"feedback #(\d+)", str(x.get("claim") or ""))] if m]
    return max(nums) + 1 if nums else 1


def drift_ask(argv):
    """`temper drift ask --path P --why W --change C`: one row of the Build ledger (a fix run's Fix is judged by the
    build gate, and the scope row reads that ledger). A path of the plan, or one with a space or a quote, is refused."""
    import flow_base
    args = dict(zip(argv[0::2], argv[1::2])) if len(argv) == 6 else {}
    path, why, change = (" ".join(str(args.get(k) or "").split()) for k in ("--path", "--why", "--change"))
    if not (path and why and change) or set(args) != {"--path", "--why", "--change"}:
        return fail("usage: temper drift ask --path P --why '<why it is needed>' --change '<what would change>'")
    if re.search(r"[\s'\"]", path) or path.startswith("/") or ".." in path.split("/"):
        return fail("the path %s is not a plain path of the project" % path)
    state = read_json(os.path.join(".temper", "build-state.json"), {})
    stage = state.get("next_stage")
    w = state.get("repair") if isinstance(state.get("repair"), dict) else {}
    fixer = w and not w.get("commit") and w.get("stage") == stage and (state.get("adhoc") or {}).get("kind") == "repair"
    if stage not in ("build", "fix") and not fixer:   # WP24: the fixer of an open repair is held to Build's rule
        return fail("a drift is asked at Build or Fix, or by the fixer of an open repair; the run is at %s" % (stage or "no stage"))
    spec = state.get("spec_path") or ""
    if spec and path in flow_base.plan_set(state, spec):
        return fail("%s is a file of the plan: no drift to ask" % path)
    if fixer:   # lane E: a file no answer lets a repair commit (a manifest, a CI file, the config, the spec folder, a
        import repair_ops   # sensitive path) is refused here, so the person is never asked a question that cannot take effect
        config = os.path.join(".claude", "temper.config")   # a run reads the project's own config (scripts/temper)
        no = repair_ops.refused_file(path, repair_ops.run_of(config), spec, config, {os.path.normpath(path)})
        if no:
            return fail("%s, which no answer lets a repair commit: the fix needs a step back (stop, commit nothing, and say so)" % no)
    if evidence("build", "drift", "drift ask %s\nWhy: %s\nChange: %s" % (path, why[:300], change[:300])):
        return 1
    print("OK: the Scope drift question about %s comes next; stop here and return" % path)
    return 0


def main(argv):
    if len(argv) >= 3 and argv[1] == "take-out":
        return take_out(argv[0], argv[2], argv[3:])
    if len(argv) >= 3 and argv[1] == "feedback":
        return feedback(argv[2], argv[3:])
    return fail("usage: temper group take-out G<n> SHA... | temper group feedback G<n> --text T")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
