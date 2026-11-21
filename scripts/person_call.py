"""person_call.py: the CLI's own check of a call only the person may cause, before the word runs (WP32, rules 3, 4, 8, 11).

  python3 -E -s person_call.py WORD ARG...     the words of a temper call; exit 1 and the reason on stderr when the CLI
                                               refuses it, else exit 0 with nothing printed

The mod refuses these calls unless the person's answer to the CLI's question maps to them (the list personOnly of its
rules). With the mod off, the CLI holds what it can compute from the run's files:

  - while the run goes on by itself and no stop is open (Run.armed), a person only call is refused: a plan patch, a
    budget grant, clearing a ledger, archiving or starting over the run (state archive, init) and the commit hook's
    removal (guards uninstall). At a stop the run is parked, so the person's option at the question passes (as budget.py
    refuses Run it anyway in such a run), and so does a Scope drift answer to the question asked (repair_ops.answer_of).
    `state clear` is not refused: the restart question (Start over) is open whenever a run is, so the CLI cannot tell
    the person's answer from a session's call; only the mod holds it;
  - a start of the run that goes on by itself (state set run_mode autonomous) where the approval offers none: at risk H
    with no fresh review of the plan as it is (flow_run.Run.may_run_alone, the one reading the flow offers it by);
  - clearing a ledger that holds an open finding, in every mode: the CLI resolves a finding (repair close), and the
    person keeps one with evidence accept; a cleared ledger would only erase it;
  - after the approval, the run's branch (the branch the commit hook gates) is never moved off the branch checked out;
  - base_sha, the commit the run's diff is read against, is a full commit id of the history of HEAD, never a name such
    as HEAD that moves with every commit.

Who typed a call that passes, the CLI cannot know (docs/trust.md). A defect here never stops the call it guards: it says
so on stderr and lets the call go on. Standard library only.
"""
import json
import os
import re
import subprocess
import sys

TEMPER = ".temper"
# the person only calls this file refuses in a run that goes on by itself (the words after the script)
UNATTENDED = (("plan", "patch"), ("budget", "grant"), ("evidence", "clear"), ("state", "archive"), ("state", "init"),
              ("guards", "uninstall"))


def load(path, default):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, type(default)) else default
    except (OSError, ValueError):
        return default


def armed():
    """Whether the run goes on by itself here, with no stop open: Run.armed, the one reading of it (scripts/flow_run.py).
    False when the run's files cannot be read (a check that fails never stops the call)."""
    try:
        from flow_run import Run
        return Run({}).armed()
    except Exception:
        return False


def git(*args):
    p = subprocess.run(["git"] + list(args), capture_output=True, text=True)
    return p.returncode, p.stdout.strip()


def open_findings(stage):
    """The open findings of a stage's ledger: a row with a severity that the CLI has neither resolved nor accepted."""
    import findings
    rows = load(os.path.join(TEMPER, "evidence", "%s.json" % stage), [])
    return [r for r in rows if isinstance(r, dict) and r.get("severity") and r.get("claim") != "review completed"
            and findings.finding_state(r) not in ("resolved", "accepted")]


def refusal(words):
    """The reason the CLI refuses the call, or ''."""
    w = [str(x) for x in words]
    if any(tuple(w[:len(k)]) == k for k in UNATTENDED) and armed():
        return ("BLOCKED: temper %s is the person's answer at a question; a run that goes on by itself never makes it (no "
                "stop is open)" % " ".join(w[:2]))
    if w[:2] == ["evidence", "clear"]:
        stage = next((y for x, y in zip(w, w[1:]) if x == "--stage"), "")
        opens = open_findings(stage) if re.fullmatch(r"[a-z]+", stage) else []
        if opens:
            return ("FAIL: the %s ledger holds %d open finding(s) (%s); a cleared ledger would erase them. The CLI resolves a "
                    "finding (temper repair close), and the person keeps one with temper evidence accept"
                    % (stage, len(opens), str(opens[0].get("claim"))[:120]))
    if w[:4] == ["state", "set", "run_mode", "autonomous"]:
        from flow_run import Run
        if not Run({}).may_run_alone():
            return ("FAIL: at risk H the run goes on by itself only after the fresh review ran on the plan as it is and "
                    "left no open finding at high; the approval offers no such option")
    state = load(os.path.join(TEMPER, "build-state.json"), {})
    if w[:3] == ["state", "set", "branch"] and len(w) > 3 and state.get("plan_hash"):
        here = git("rev-parse", "--abbrev-ref", "HEAD")[1]
        if w[3] != here:
            return ("FAIL: after the approval the run's branch is the branch it stands on (%s): the commit hook gates it, "
                    "and the run's commit goes to it; got '%s'" % (here or "none", w[3]))
    if w[:3] == ["state", "set", "base_sha"] and len(w) > 3:
        v = w[3]
        if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", v) or git("rev-parse", "--verify", "--quiet", v + "^{commit}")[1] != v \
                or git("merge-base", "--is-ancestor", v, "HEAD")[0] != 0:
            return ("FAIL: base_sha is the full id of a commit of the history of HEAD (as git rev-parse HEAD prints it), "
                    "never a name that moves; got '%s'" % v)
    return ""


def main(argv):
    try:
        why = refusal(argv[1:])
    except Exception as e:   # a defect here never stops the call it guards, and says so
        print("WARN: the person only check could not run (%s); the call goes on" % e, file=sys.stderr)
        return 0
    if why:
        print(why, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
