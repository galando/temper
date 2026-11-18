"""hold_before_approval.py: PreToolUse (the file writers), hold a project file until the person approves the plan.

Rule 1 of Temper (9.8.5, WP12): before the approval a run writes only its spec folder and Temper's own run files. With
the mod loaded its stage rule refuses a project file write at Intent, Plan and Design; with no mod loaded this classic
hook holds the same rule for the tools that write a file. It refuses no path the mod's rule lets through at those
stages, so the two carriers hold one rule. A shell command that writes a file, and a /temper:fix run (before its
approval as after it), are outside it: the commit hook still refuses a commit of a project file before the approval.

The hook only ever refuses: on a hit it prints one JSON answer, permissionDecision "deny", with the reason, and on
anything else it prints nothing. It never changes a tool call's input.

DEGRADATION CONTRACT:
  - a tool that is not Write, Edit, MultiEdit or NotebookEdit                     => no output, exit 0
  - the folder is not in a Temper project (no `.temper` folder in it or above)    => no output, exit 0
  - no run, a fix run, a run from Build on, a state file it cannot read           => no output, exit 0
  - a path under `.temper/` (the run's spec folder is there), a worktree of the run, a path outside the project, or
    a decision record at Plan or Design                                           => no output, exit 0
  - a project file written at Intent, Plan or Design of a feature run             => the deny answer on stdout, exit 0
  - anything else, an input it cannot parse and an internal error included        => no output, exit 0 (FAIL-OPEN)
"""
import json
import os
import sys

WRITERS = ("Write", "Edit", "MultiEdit", "NotebookEdit")
BEFORE = {"intent": "Intent", "plan": "Plan", "design": "Design"}


def project(cwd):
    """The folder of the Temper project that holds cwd (the first one with a `.temper` folder), or None."""
    d = os.path.abspath(cwd or ".")
    while True:
        if os.path.isdir(os.path.join(d, ".temper")):
            return d
        up = os.path.dirname(d)
        if up == d:
            return None
        d = up


def held(root, stage, path):
    """True when the mod's stage rule refuses the write too: a project file, outside Temper's own files."""
    rel = os.path.relpath(path, root).replace(os.sep, "/")
    if rel == "." or rel.startswith(".temper/") or rel.startswith(".claude/worktrees/"):
        return False
    if stage in ("plan", "design") and rel.startswith("docs/decisions/") and rel.endswith(".md"):
        return False
    return True


def main():
    d = json.loads(sys.stdin.read())
    if d.get("tool_name") not in WRITERS:
        return
    ti = d.get("tool_input") or {}
    raw = ti.get("notebook_path") if d.get("tool_name") == "NotebookEdit" else ti.get("file_path")
    if not isinstance(raw, str) or not raw:
        return
    cwd = d.get("cwd") or os.getcwd()
    root = project(cwd)
    if root is None:
        return
    with open(os.path.join(root, ".temper", "build-state.json"), encoding="utf-8") as f:
        st = json.load(f)
    stage = st.get("next_stage") if isinstance(st, dict) else None
    if st.get("command", "temper") != "temper" or stage not in BEFORE:
        return
    path = os.path.normpath(os.path.join(cwd, raw))
    if path != root and not path.startswith(root + os.sep):
        return   # not a file of this project
    if not held(root, stage, path):
        return
    rel = os.path.relpath(path, root)
    reason = ("Temper: %s stage. Writing %s is not allowed until the user approves the plan and Build starts: "
              "before the approval a run writes only its spec folder. Do not look for another way. "
              "Next: finish the %s, then ask the question `temper next --json` gives (header `Temper gate`)."
              % (BEFORE[stage], rel, stage))
    sys.stdout.write(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                                        "permissionDecisionReason": reason}}) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
