#!/usr/bin/env python3
"""notice.py: the one time notice of 9.8.5 (WP31), said once to a project that ran an earlier Temper.

A project of 9.8.4 (what users have), or one that ran the head of pull request #115, holds `.temper/specs` or
`.temper/archive` and no mark. The first `temper next` puts the notice in front of its `say` and writes the mark,
`.temper/notice.json`, with the version as its key; `temper go` keeps it in front of the `say` it prints, so both
carriers show it once, as a line of text and never in a question. `temper init` writes the mark for a new project
(neither folder there), so a new project is never told. `state clear` keeps the mark; git ignores it (`_RUN_FILES`).

  python3 notice.py init    write the mark when the project has neither .temper/specs nor .temper/archive

Standard library only. Fail open: a mark that cannot be read or written never stops a command.
"""
import json
import os
import sys

VERSION = "9.8.5"
TEXT = ("Temper 9.8.5 asks twice: before any code is written, and at the commit. Pick Ask me at every stage at the "
        "first question for the old flow. What changed: docs/getting-started.md.")
TEMPER = ".temper"
MARK = os.path.join(TEMPER, "notice.json")


def _older():
    return any(os.path.isdir(os.path.join(TEMPER, d)) for d in ("specs", "archive"))


def _marked():
    try:
        with open(MARK, encoding="utf-8") as f:
            d = json.load(f)
        return isinstance(d, dict) and VERSION in d
    except (OSError, ValueError):
        return False


def _write(now):
    if not os.path.isdir(TEMPER) or os.path.islink(TEMPER) or os.path.islink(MARK):
        return False
    try:
        with open(MARK, "w", encoding="utf-8") as f:
            json.dump({VERSION: now or "told"}, f)
            f.write("\n")
        return True
    except OSError:
        return False


def take(now=""):
    """The notice when it is due (an older project, no mark), with the mark written; else ''."""
    if _marked() or not _older():
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
