"""maven_loop.py: a Maven task test that runs only what the task declared (F22).

  python3 maven_loop.py run WORKTREE TIMEOUT 'DECLARED COMMAND' FILE...    exits with Maven's code, or 3 when a class has no new report

A Maven test command (mvn, mvnd or mvnw) of a task runs the task's declared test classes only: every declared test file, as
one -Dtest= list (a #method the declared command names for a class is kept), offline, with the usual check plugins skipped,
on mvnd when it is on the PATH and mvn otherwise. The flags the task declared are kept. A green run needs a surefire report
made by this run for each class: a class that left none did not run, however Maven exited. Standard library only.
"""
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

import run_env

SKIP_FLAGS = ["-o", "-B", "-Dcheckstyle.skip=true", "-Dspotbugs.skip=true", "-Denforcer.skip=true", "-Dlicense.skip=true",
              "-Drat.skip=true", "-Dfmt.skip=true", "-Dspotless.check.skip=true", "-Dmaven.javadoc.skip=true",
              "-DfailIfNoTests=false", "-Dsurefire.failIfNoSpecifiedTests=false"]
MAVEN = re.compile(r"^\s*(\./)?(mvnd?|mvnw)(\s|$)")
TEST_FILE = re.compile(r"(^|/)src/test/java/(.+)/([A-Z][\w$]*)\.java$")


def is_maven(cmd):
    return bool(MAVEN.match(cmd))


def classes_of(files):
    """[(fully qualified name, simple name)] for each declared test file under src/test/java."""
    out = []
    for f in files:
        m = TEST_FILE.search(f)
        if m:
            out.append((m.group(2).replace("/", ".") + "." + m.group(3), m.group(3)))
    return out


def build(declared, classes):
    """The command to run: mvn or mvnd, the skip flags, the flags the task declared, the goals, and the -Dtest= list."""
    toks = shlex.split(declared)
    methods = {}
    kept, goals = [], []
    for t in toks[1:]:
        if t.startswith("-Dtest="):
            for spec in t[len("-Dtest="):].split(","):
                cls, _, meth = spec.partition("#")
                if meth:
                    methods.setdefault(cls, []).append(meth)
        elif t.startswith("-") and t not in SKIP_FLAGS:
            kept.append(t)
        elif not t.startswith("-"):
            goals.append(t)
    exe = "mvnd" if shutil.which("mvnd") else "mvn"
    sel = ",".join(("%s#%s" % (s, "+".join(methods[s])) if s in methods else s) for _, s in classes)
    return [exe] + SKIP_FLAGS + kept + (["-Dtest=" + sel] if sel else []) + (goals or ["test"])


def reports_made(worktree, classes, since):
    """The classes with no surefire report newer than the start of the run."""
    missing = []
    for fqcn, _ in classes:
        ok = False
        for root in (worktree, ):
            for name in ("TEST-%s.xml" % fqcn, "%s.txt" % fqcn):
                p = os.path.join(root, "target", "surefire-reports", name)
                try:
                    if os.path.getmtime(p) >= since:
                        ok = True
                except OSError:
                    pass
        if not ok:
            missing.append(fqcn)
    return missing


def run(worktree, timeout, declared, files):
    classes = classes_of(files)
    cmd = build(declared, classes)
    since = time.time() - 1
    try:
        p = subprocess.run(cmd, cwd=worktree, env=run_env.test_env(worktree), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=float(timeout))
        out, rc = p.stdout, p.returncode
    except subprocess.TimeoutExpired as e:
        return (e.stdout or b"") + b"\nmaven_loop: timed out\n", 124
    except OSError as e:
        return ("%s\n" % e).encode(), 127
    if rc == 0 and classes:
        missing = reports_made(worktree, classes, since)
        if missing:
            return out + ("\nmaven_loop: no new surefire report for %s: the class did not run\n" % ", ".join(missing)).encode(), 3
    return out, rc


def main(argv):
    if len(argv) < 5 or argv[1] != "run":
        print(__doc__, file=sys.stderr)
        return 2
    out, rc = run(argv[2], argv[3], argv[4], argv[5:])
    sys.stdout.buffer.write(out)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
