#!/usr/bin/env python3
"""notice.py: the one time notice of 9.8.5 (WP31), said once to a project that ran an earlier Temper.

A project of 9.8.4 (what users have), or one that ran the head of pull request #115, holds `.temper/specs` or
`.temper/archive`, no mark, and a config that is not of this version (WP32: neither upgrade.asked of 9.8.5 nor the
first line of its template, config_tidy.current; a new worktree or clone of a 9.8.5 project has its committed spec
folders but not the ignored mark). The first `temper next` puts the notice in front of its `say` and writes the mark,
`.temper/notice.json`, with the version as its key; `temper go` keeps it in front of the `say` it prints, so both
carriers show it once, as a line of text and never in a question. `temper init` writes the mark for a new project
(neither folder there), so a new project is never told. `state clear` keeps the mark; git ignores it (`_RUN_FILES`).

The clone holds the same mark (NEW-FLOW-2): `temper-marks.json` in the folder `git rev-parse --git-common-dir` names,
which every worktree of the clone shares and no checkout holds. It is read before the config is: a new worktree of a
project whose config is not committed, or of a 9.8.4 project with nothing to tidy, is not told again. It also holds the
answer to the one time config question (config_tidy.py). A fresh clone has no such file and falls back to the config.

  python3 notice.py init    write the mark when the project is not an older one (neither folder, or a config of 9.8.5)

Standard library only. Fail open: a mark that cannot be read or written never stops a command.
"""
import json
import os
import subprocess
import sys

VERSION = "9.8.5"
TEXT = ("Temper 9.8.5 asks twice: before any code is written, and at the commit. Pick Ask me at every stage at the "
        "first question for the old flow. What changed: docs/getting-started.md.")
TEMPER = ".temper"
MARK = os.path.join(TEMPER, "notice.json")
SHARED = "temper-marks.json"   # in the clone's own folder (git rev-parse --git-common-dir), shared by its worktrees


def _shared_file():
    """The clone's mark file, or "" outside a git repository."""
    try:
        p = subprocess.run(["git", "rev-parse", "--git-common-dir"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=10)
        d = p.stdout.decode("utf-8", "replace").strip()
        return os.path.join(os.path.abspath(d), SHARED) if p.returncode == 0 and d else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def shared(key):
    """What the clone's mark file holds under key (a dict, {} when there is none or it cannot be read)."""
    try:
        with open(_shared_file(), encoding="utf-8") as f:
            d = json.load(f)
        v = d.get(key) if isinstance(d, dict) else None
        return v if isinstance(v, dict) else {}
    except (OSError, ValueError):
        return {}


def mark_shared(key, name, value):
    """Writes {name: value} under key in the clone's mark file, the other keys kept. Never fails a command."""
    path = _shared_file()
    if not path or os.path.islink(path):
        return False
    try:
        try:
            with open(path, encoding="utf-8") as f:
                d = json.load(f)
        except (OSError, ValueError):
            d = {}
        d = d if isinstance(d, dict) else {}
        d[key] = dict(d[key] if isinstance(d.get(key), dict) else {}, **{name: value or "told"})
        with open(path + ".tmp", "w", encoding="utf-8") as f:
            json.dump(d, f)
            f.write("\n")
        os.replace(path + ".tmp", path)
        return True
    except OSError:
        return False


def _older():
    """A spec or archive folder, and a config this version did not set up or ask (WP32, review finding R8-2): the folders
    are committed, so a new worktree or clone of a project that ran only 9.8.5 has them, and its config says 9.8.5."""
    if not any(os.path.isdir(os.path.join(TEMPER, d)) for d in ("specs", "archive")):
        return False
    try:
        with open(os.path.join(".claude", "temper.config"), encoding="utf-8") as f:
            text = f.read()
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import config_tidy
        return not config_tidy.current(text)
    except Exception:
        return True


def _local():
    try:
        with open(MARK, encoding="utf-8") as f:
            d = json.load(f)
        return isinstance(d, dict) and VERSION in d
    except (OSError, ValueError):
        return False


def _marked():
    """The mark of this checkout, else the clone's (then written here too, so the next call reads one file)."""
    if _local():
        return True
    got = shared("notice").get(VERSION)
    if got:
        _write_local(str(got))
    return bool(got)


def _write_local(now):
    if not os.path.isdir(TEMPER) or os.path.islink(TEMPER) or os.path.islink(MARK):
        return False
    try:
        with open(MARK, "w", encoding="utf-8") as f:
            json.dump({VERSION: now or "told"}, f)
            f.write("\n")
        return True
    except OSError:
        return False


def _write(now):
    """Both marks; the checkout's own decides whether the notice is said (as before the clone's mark)."""
    done = _write_local(now)
    mark_shared("notice", VERSION, now)
    return done


def take(now=""):
    """The notice when it is due (an older project, no mark), with the mark written; else ''."""
    if _local() or not _older() or _marked():   # the clone's mark last: it costs a call of git
        return ""
    return TEXT if _write(now) else ""


def put(out, text):
    """The notice in front of the say of one next (a dict), when there is one to say."""
    if text and isinstance(out, dict) and not str(out.get("say") or "").startswith(text):
        out["say"] = (text + " " + str(out.get("say") or "")).rstrip()
    return out


def main(argv):
    if len(argv) >= 2 and argv[1] == "init":
        if not _older() and not _marked():
            _write(argv[2] if len(argv) > 2 else "")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
