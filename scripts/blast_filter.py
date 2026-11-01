"""blast_filter.py: which changed files count toward a run's blast radius (F21).

  git diff --name-only ... | python3 blast_filter.py project     names from the top of the repository in, names from the
                                                                 project folder out, the ones that do not count left out

Temper's own files never count as outside the declared files, nor toward autonomy.max-blast-radius: the project's
.claude/temper.config, the .claude/settings.json that /temper:init may write (matched by its path only, never opened),
.temper/ and .claude/worktrees/. Test and build output does not count either: coverage data, htmlcov/, .pytest_cache/,
__pycache__/, *.pyc, .nyc_output/, JaCoCo and surefire output, the mypy and ruff caches. A real source file named like one
(coverage.py) counts. Standard library only.
"""
import os
import re
import subprocess
import sys

OWN = {".claude/temper.config", ".claude/settings.json"}
OWN_PREFIX = (".temper/", ".claude/worktrees/")
OUTPUT_SEGMENTS = {"htmlcov", ".pytest_cache", "__pycache__", ".nyc_output", ".mypy_cache", ".ruff_cache"}
OUTPUT_NAME = re.compile(r"^(\.coverage(\..*)?|coverage\.xml|coverage\.json|\.coverage-.*|jacoco.*\.exec|.*\.pyc)$")
OUTPUT_PATH = re.compile(r"(^|/)target/(site/jacoco[^/]*|surefire-reports|jacoco[^/]*|failsafe-reports)(/|$)")


def counts(path):
    p = path[2:] if path.startswith("./") else path
    if p in OWN or p.startswith(OWN_PREFIX):
        return False
    segs = p.split("/")
    if any(s in OUTPUT_SEGMENTS for s in segs[:-1]):
        return False
    return not (OUTPUT_NAME.match(segs[-1]) or OUTPUT_PATH.search(p))


def main(argv):
    if len(argv) != 2 or argv[1] != "project":
        print(__doc__, file=sys.stderr)
        return 2
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode().strip()
    for line in sys.stdin:
        n = line.rstrip("\n")
        if not n:
            continue
        rel = os.path.relpath(os.path.join(top, n)) if top else n
        if counts(rel):
            print(rel)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
