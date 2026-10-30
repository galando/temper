"""guards_ops.py: turning the Temper commit gate off (F30).

  python3 guards_ops.py uninstall

Removes the Temper pre-commit hook and its temper-gate folder from the repository's git folder, the older hook file a 9.6.5
install left there, and unsets core.hooksPath only when it points at Temper's folder and no hook of anyone else is left in it.
A Temper line in a hook of your own is named and never changed. A second run changes nothing. It reads no Claude Code settings
file and nothing in the home folder: only the repository's own git folder. Standard library only.
"""
import os
import subprocess
import sys

GATE = "temper-gate"
OLDER = "temper-pre-commit"
MARK = "# Temper native pre-commit hook"
LINES = (GATE + "/pre-commit", OLDER)
GIT_HOOK_NAMES = ("applypatch-msg", "pre-applypatch", "post-applypatch", "pre-commit", "pre-merge-commit", "prepare-commit-msg", "commit-msg",
                  "post-commit", "pre-rebase", "post-checkout", "post-merge", "pre-push", "post-rewrite", "pre-auto-gc", "reference-transaction")


def git(*args):
    r = subprocess.run(["git"] + list(args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return r.stdout.decode("utf-8", "replace").strip() if r.returncode == 0 else None


def is_temper_hook(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().split("\n")[1:2] == [MARK + " (installed by scripts/guards/install.sh)."] or MARK in f.read(400)
    except (OSError, IndexError):
        return False


def has_mark(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return MARK in f.read(600)
    except OSError:
        return False


def uninstall():
    common = git("rev-parse", "--git-common-dir")
    if common is None:
        print("FAIL: not a git repository: there is no Temper commit gate here", file=sys.stderr)
        return 1
    common = os.path.realpath(common)
    gate_dir = os.path.join(common, GATE)
    done = []
    kept = os.path.join(gate_dir, "pre-commit")
    if os.path.islink(gate_dir):
        print("Temper: %s is a symlink; it is left alone." % gate_dir)
    elif os.path.isfile(kept) and has_mark(kept):
        os.remove(kept)
        done.append("removed the Temper hook %s" % kept)
    elif os.path.isfile(kept):
        print("Temper: %s is not Temper's hook; it is left alone." % kept)
    older = os.path.join(common, OLDER)
    if os.path.isfile(older) and not os.path.islink(older):
        os.remove(older)
        done.append("removed the older Temper hook %s" % older)
    left = []
    if os.path.isdir(gate_dir) and not os.path.islink(gate_dir):
        left = [n for n in os.listdir(gate_dir) if n != "."]
        if not left:
            os.rmdir(gate_dir)
            done.append("removed the folder %s" % gate_dir)
    hooks_path = git("config", "--get", "core.hooksPath")
    if hooks_path:
        target = hooks_path if os.path.isabs(hooks_path) else os.path.join(git("rev-parse", "--show-toplevel") or ".", hooks_path)
        names_ours = os.path.realpath(target) == os.path.realpath(gate_dir) or os.path.basename(hooks_path.rstrip("/")) == GATE
        others = [n for n in left if n in GIT_HOOK_NAMES]
        if names_ours and not others:
            subprocess.run(["git", "config", "--unset", "core.hooksPath"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            done.append("unset core.hooksPath (it named Temper's folder)")
        elif names_ours:
            print("Temper: core.hooksPath still names %s, which holds other hooks (%s); it is left as it is." % (gate_dir, ", ".join(others)))
    # A Temper line in a hook of your own: named, never changed.
    own = git("rev-parse", "--git-path", "hooks")
    if own and os.path.isdir(own):
        for n in sorted(os.listdir(own)):
            p = os.path.join(own, n)
            try:
                text = open(p, encoding="utf-8", errors="replace").read() if os.path.isfile(p) else ""
            except OSError:
                continue
            if any(x in text for x in LINES) and not has_mark(p):
                print("Temper: your hook %s runs the Temper hook (a line that names %s). Remove that line yourself; it is not changed here." % (p, GATE))
    for line in done:
        print("OK: " + line)
    if not done:
        print("OK: nothing to change: the Temper commit gate is not installed here")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "uninstall":
        return uninstall()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
