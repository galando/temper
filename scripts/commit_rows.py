#!/usr/bin/env python3
"""commit_rows.py: the rows of the commit gate of the temper CLI: overrides, blast radius, the touch patterns.

Code moved out of scripts/temper, one word for each block:

    python3 -I scripts/commit_rows.py WORD ARG...

Each word's function takes the arguments the block read as sys.argv, the word first in the place of the
program name. Nothing runs at import.
"""
import sys


def glob_touch_match(argv):
    import re, sys
    target, pat = argv[1].lstrip("./"), argv[2]
    out, i, n = [], 0, len(pat)
    while i < n:
        if pat[i:i+3] == "**/": out.append("(?:.*/)?"); i += 3
        elif pat[i:i+3] == "/**": out.append("(?:/.*)?"); i += 3
        elif pat[i:i+2] == "**": out.append(".*"); i += 2
        elif pat[i] == "*": out.append("[^/]*"); i += 1
        elif pat[i] == "?": out.append("[^/]"); i += 1
        else: out.append(re.escape(pat[i])); i += 1
    sys.exit(0 if re.match("^" + "".join(out) + "$", target) else 1)


WORDS = {n.replace("_", "-"): f for n, f in (
    ('glob_touch_match', glob_touch_match),
)}


def main():
    WORDS[sys.argv[1]](sys.argv[1:])


if __name__ == "__main__":
    main()
