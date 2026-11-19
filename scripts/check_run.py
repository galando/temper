"""check_run.py: Check, run by the CLI (9.8.0). Before 9.8.0 a Sonnet agent ran the suite and typed the results into the
ledger; a row it forgot (coverage recorded as 'none') failed the gate for no fault of the code. Now the CLI runs the
commands and records what they gave, and the agent is only the fallback for a stack the CLI cannot read.

  python3 check_run.py detect ROOT [TEST_CMD] [COVERAGE_CMD]    the commands it would run, as JSON ({} when none)
  python3 check_run.py run ROOT SPEC LEDGER BASE COMMAND [TEST_CMD] [COVERAGE_CMD] [KEY]
                                                                run them, record the rows, print one line each
  python3 check_run.py build-checks ROOT SPEC LEDGER BASE COMMAND [TEST_CMD COVERAGE_CMD KEY [nosuite]]
                                                                the checks when Build ends (WP23): the same rows into the
                                                                Build ledger (the suite as `Integration suite`, in the
                                                                owner's run text, the plan's line only when nothing else
                                                                names a suite); exits with the suite's exit code
  python3 check_run.py ahead ROOT SPEC BASE COMMAND [TEST_CMD COVERAGE_CMD KEY]
                                                                the same run while Review reads the change, through the
                                                                reuse store (run_env.run_cached), then the planted bugs
                                                                (.temper/evidence/mutation.json)
  python3 check_run.py coverage-verdict                         the coverage rule on one JSON object on standard input
  python3 check_run.py owner ROOT [SPEC]                        who owns the suite command (WP20, suite_owner), one JSON
                                                                line {"test", "run", "source", "why"}

What `run` records in the Check ledger, every row `executed_by: cli`:
  - tests       the suite (with coverage on in the same run when the stack allows it), its exit and output tail
  - coverage    one row with the verdict of the coverage rule (WP19, coverage_verdict): the total, the rule, the floor
                and the state; exit 0 for pass, 1 for fail, null for not measured (no coverage command, a coverage
                program that could not start, no base value). KEY is check.coverage-threshold when the project's
                config holds it.
  - scenario    each intent.md scenario's `Test:` command, its real exit (a scenario row is a real run, not a trace)
  - regression  (fix runs) the tests the fix added or changed, run on the code before the fix: they must FAIL there,
                or they do not prove the fix
`run` plants no bug. The planted bug score is information beside Review: `ahead` plants one small bug at a time in
the lines this run changed, and only when three runs of the suite fit the budget. Python is read as a syntax tree (a
comparison flipped, + and - swapped, a constant moved by one, `and`/`or` swapped, a `not` dropped, a call statement
deleted); JavaScript, TypeScript, Java, Kotlin, Go, C#, Rust, Swift, Scala, C, C++, PHP and Ruby as text (a
comparison, == and !=, && and ||, + and -, true and false, a number moved by one). Coverage says a line ran; this says
a test would notice it break. Capped at 40 planted bugs, the budget, and 60 s after Check starts (mutation.stop).
Standard library only.
"""
import ast
import copy
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

import acceptance
import run_env

SKIP_DIRS = {".git", ".temper", ".claude", "node_modules", "__pycache__", ".venv", "venv", "dist", "build", "target", ".tox"}
TEST_DIR_NAMES = run_env.TEST_DIR_NAMES
MUTANT_CAP = 40
MUTATION_BUDGET_S = float(os.environ.get("TEMPER_MUTATION_BUDGET_S", "300"))
SUITE_TIMEOUT_S = float(os.environ.get("TEMPER_CHECK_TIMEOUT_S", "1800"))
LCOV_SUMMARY = ".temper/check/coverage/coverage-summary.json"
LCOV = ".temper/check/coverage/lcov.info"
COVERAGE_CAP = 80.0   # the floor of the changed lines is the base total, never more than this
CHANGED_MIN = 10      # the changed executable lines the rule of the changed lines needs
STOP_AFTER_S = 60     # the planted bugs go on at most this long after Check starts (mutation.stop)


def _ok(root, args):
    try:
        return subprocess.run(args, cwd=root, capture_output=True, timeout=60).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def _py_files(root):
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith(".")]
        for f in files:
            if f.endswith(".py"):
                yield os.path.relpath(os.path.join(d, f), root)


def _py_test_dirs(root):
    """Top-level folders that hold test_*.py or *_test.py files, the usual names first."""
    found = []
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name)
        if not os.path.isdir(p) or name in SKIP_DIRS or name.startswith("."):
            continue
        for d, dirs, files in os.walk(p):
            dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
            if any(re.match(r"^test_.*\.py$|^.*_test\.py$", f) for f in files):
                found.append(name)
                break
    return sorted(found, key=lambda n: (n not in TEST_DIR_NAMES, n))


def detect(root, test_cmd="", cov_cmd=""):
    """The commands Check runs: {"stack", "test", "coverage": {"run", "report", "kind"} | None, "hint"}; {} when unknown."""
    if test_cmd:
        out = {"stack": "configured", "test": test_cmd, "coverage": None, "hint": "set check.commands.coverage to measure coverage",
               "mutation": True}
        if cov_cmd:   # the command that runs the suite with coverage on and prints a total line (TOTAL ... 85%)
            out["coverage"] = {"run": cov_cmd, "kind": "configured"}
        return out
    j = lambda *p: os.path.join(root, *p)
    if any(True for _ in _py_files(root)):
        dirs = _py_test_dirs(root)
        pytest = _ok(root, ["python3", "-m", "pytest", "--version"]) and (
            os.path.exists(j("pytest.ini")) or os.path.exists(j("conftest.py")) or "pytest" in _read(j("pyproject.toml"))
            or "pytest" in _read(j("setup.cfg")) or "pytest" in _read(j("tox.ini")) or bool(dirs))
        if pytest:
            runner = ["-m", "pytest", "-q"]
            test = "python3 -m pytest -q"
        elif dirs:
            runner = None
            test = " && ".join("python3 -m unittest discover -s %s -t ." % d for d in dirs)
        else:
            return {}
        cov = None
        if _ok(root, ["python3", "-m", "coverage", "--version"]):
            omit = ",".join(["%s/*" % d for d in dirs] + [".temper/*", ".claude/*", "*/test_*.py", "*_test.py"])
            base = "python3 -m coverage run --source=. --omit='%s'" % omit
            if runner:
                run = "%s %s" % (base, " ".join(runner))
            else:
                run = " && ".join("%s -a -m unittest discover -s %s -t ." % (base, d) for d in dirs)
                run = "rm -f .coverage && " + run
            cov = {"run": run, "report": "python3 -m coverage json -o .temper/check/coverage.json", "kind": "coverage.py",
                   "file": ".temper/check/coverage.json"}
        return {"stack": "python", "test": test, "coverage": cov, "mutation": True,
                "hint": "" if cov else "install coverage.py (pip install coverage) to measure coverage"}
    if os.path.exists(j("package.json")):
        try:
            pkg = json.load(open(j("package.json")))
        except (OSError, ValueError):
            pkg = {}
        t = (pkg.get("scripts") or {}).get("test", "")
        if not t or "no test specified" in t:
            return {}
        deps = dict(pkg.get("dependencies") or {}, **(pkg.get("devDependencies") or {}))
        cov = None
        if "jest" in deps:
            cov = {"run": "npx jest --coverage --coverageReporters=json-summary --coverageReporters=lcovonly "
                          "--coverageDirectory=.temper/check/coverage", "kind": "jest", "file": LCOV_SUMMARY, "lcov": LCOV}
        elif "vitest" in deps:
            cov = {"run": "npx vitest run --coverage --coverage.reporter=json-summary --coverage.reporter=lcovonly "
                          "--coverage.reportsDirectory=.temper/check/coverage", "kind": "vitest", "file": LCOV_SUMMARY, "lcov": LCOV}
        elif "c8" in deps:
            cov = {"run": "npx c8 --reporter=json-summary --reporter=lcovonly --report-dir=.temper/check/coverage npm test --silent",
                   "kind": "c8", "file": LCOV_SUMMARY, "lcov": LCOV}
        if not cov and "--experimental-test-coverage" in t:   # node --test prints its own coverage table
            cov = {"run": "npm test --silent", "kind": "node-test"}
        return {"stack": "node", "test": "npm test --silent", "coverage": cov, "mutation": True,
                "hint": "" if cov else "add jest, vitest or c8 (or node --test --experimental-test-coverage) to measure coverage"}
    if os.path.exists(j("go.mod")):
        return {"stack": "go", "test": "go test ./...", "coverage": {"run": "go test ./... -coverprofile=.temper/check/cover.out",
                "report": "go tool cover -func=.temper/check/cover.out", "kind": "go", "file": ".temper/check/cover.out"}, "hint": "",
                "mutation": True}
    if os.path.exists(j("Cargo.toml")):
        return {"stack": "rust", "test": "cargo test", "coverage": None, "mutation": True, "hint": "set check.commands.coverage (cargo llvm-cov) to measure coverage"}
    if os.path.exists(j("pom.xml")):
        return {"stack": "maven", "test": "mvn -q verify", "coverage": None, "mutation": True, "hint": "set check.commands.coverage (JaCoCo) to measure coverage"}
    if os.path.exists(j("build.gradle")) or os.path.exists(j("build.gradle.kts")):
        g = "./gradlew" if os.path.exists(j("gradlew")) else "gradle"
        return {"stack": "gradle", "test": "%s test" % g, "coverage": None, "mutation": True, "hint": "set check.commands.coverage (JaCoCo) to measure coverage"}
    return {}


def det_for(root, test_cmd="", cov_cmd=""):
    """The commands Check runs (WP22): detect() in the root, else those of the owner of the suite command when it found
    them one folder down (suite_owner, WP20), so Check runs the owner's text, the key of the run the base, a group and
    integrate made of it; {} when neither."""
    det = detect(root, test_cmd, cov_cmd)
    if det or test_cmd:
        return det
    o = suite_owner(root, {}, "")
    return o["det"] if o.get("source") == "detected" else {}


def _read(p):
    try:
        return open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


# ---- the owner of the suite command (WP20) --------------------------------------------------------------------------
def suite_owner(root, cfg=None, spec=""):
    """Who says which command is the project's suite: {"test", "run", "source", "why", "det"}. In this order: the
    config's check.commands.test (with check.commands.coverage); detect() in the root; detect() of the one folder one
    level down that answers (none when two do), with `cd <folder> && ` in front of each command and the folder in
    front of its coverage file; the plan's **Integration:** line once tasks.md exists; else none, with the reason.
    `run` is the coverage form or the test text again; `det` is what coverage_value() reads."""
    import config_yaml
    if cfg is None:
        cfg = config_yaml.load(os.path.join(root, ".claude", "temper.config"))
    test = str(config_yaml.get(cfg, "check.commands.test", "") or "").strip()
    cov = str(config_yaml.get(cfg, "check.commands.coverage", "") or "").strip()
    if test:
        return {"test": test, "run": cov or test, "source": "configured", "why": "check.commands.test of the config",
                "det": detect(root, test, cov)}
    det = detect(root)
    if det:
        c = det.get("coverage") or {}
        return {"test": det["test"], "run": c.get("run") or det["test"], "source": "detected",
                "why": "the %s files in the project's root" % det.get("stack"), "det": det}
    found = []
    for name in sorted(os.listdir(root)) if os.path.isdir(root) else []:
        if name in SKIP_DIRS or name.startswith(".") or not os.path.isdir(os.path.join(root, name)):
            continue
        d = detect(os.path.join(root, name))
        if d:
            found.append((name, d))
    if len(found) == 1:
        name, d = found[0]
        pre = "cd %s && " % name
        c = dict(d.get("coverage") or {})
        for k in ("run", "report"):
            if c.get(k):
                c[k] = pre + c[k]
        for k in ("file", "lcov"):   # trap 7: the report is written under that folder
            if c.get(k):
                c[k] = os.path.join(name, c[k])
        if c:   # and the paths inside the report are that folder's (_line_hits)
            c["dir"] = name
        det = dict(d, test=pre + d["test"], coverage=c or None)
        return {"test": det["test"], "run": c.get("run") or det["test"], "source": "detected",
                "why": "the %s files in %s/, the one folder one level down that has them" % (d.get("stack"), name), "det": det}
    tasks = os.path.join(spec, "tasks.md") if spec else ""
    if tasks and os.path.isfile(tasks):
        m = re.search(r"^\*\*Integration:\*\*\s*`([^`]+)`", _read(tasks), re.M)
        if m and m.group(1).strip() and m.group(1).strip() != "manual":
            line = m.group(1).strip()
            return {"test": line, "run": line, "source": "plan", "why": "the Integration line of %s" % tasks,
                    "det": detect(root, line)}
    why = ("%s each have build files, one folder down, and nothing says which is the suite: set check.commands.test"
           % " and ".join("%s/" % n for n, _ in found)) if found else "no test command is configured and none was found: set check.commands.test"
    return {"test": "", "run": "", "source": "none", "why": why, "det": {}}


def coverage_value(root, det, out_text):
    """The total line coverage the run left, or None."""
    cov = det.get("coverage") or {}
    kind, f = cov.get("kind"), os.path.join(root, cov.get("file", "")) if cov.get("file") else ""
    try:
        if kind == "coverage.py" and f and os.path.exists(f):
            return round(float(json.load(open(f))["totals"]["percent_covered"]), 1)
        if kind in ("jest", "vitest", "c8") and f and os.path.exists(f):
            return round(float(json.load(open(f))["total"]["lines"]["pct"]), 1)
    except (OSError, ValueError, KeyError, TypeError):
        return None
    m = re.findall(r"total:?\s+\(statements\)\s+([\d.]+)%|TOTAL\s+.*?\s([\d.]+)%\s*$|all files\s*\|\s*([\d.]+)", out_text, re.M | re.I)
    for g in reversed(m):
        v = next((x for x in g if x), None)
        if v:
            return round(float(v), 1)
    return None


strip_banner = run_env.strip_banner


# ---- coverage judged against the project (WP19) ---------------------------------------------------------------------
def _num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def _pct(x):
    return ("%.1f" % x).rstrip("0").rstrip(".")


def coverage_verdict(measure, base, changed, threshold, base_why=""):
    """The coverage rule, in this order: the key check.coverage-threshold when the project's config holds it; no coverage
    command, or a coverage program that could not start (exit 127): not measured; no base value: not measured; ten or
    more changed executable lines with line data: their share that ran reaches the base total (at most 80); else the
    total is not below the base total by more than 1 point; else not measured. Decided by the probe and the exit code,
    never by output text. Returns {"state": "pass" | "fail" | "not measured", "rule", "value", "floor", "why"}."""
    m = measure if isinstance(measure, dict) else {}
    total, hint, note = _num(m.get("total")), str(m.get("hint") or ""), str(m.get("note") or "")

    def v(state, rule, value, floor, why):
        return {"state": state, "rule": rule, "value": value, "floor": floor, "why": why}
    if threshold not in (None, ""):
        key, t = "check.coverage-threshold", _num(threshold)
        out = "remove that line from .claude/temper.config and coverage is judged against the project"
        if t is None:
            return v("fail", "threshold", total, None, "%s is %r, not a number: %s" % (key, str(threshold)[:60], out))
        if total is None:
            return v("not measured", "threshold", None, t, "no coverage total was recorded (%s asks for %s%%)%s"
                     % (key, _pct(t), ": " + (note or hint) if (note or hint) else ""))
        if total >= t:
            return v("pass", "threshold", total, t, "total %s%% reaches %s%%, the value of %s" % (_pct(total), _pct(t), key))
        return v("fail", "threshold", total, t, "total %s%% is below %s%%, the value of %s in the project's config: %s"
                 % (_pct(total), _pct(t), key, out))
    if not m.get("command", True):
        return v("not measured", None, None, None, hint or "this stack has no coverage command: set check.commands.coverage")
    if m.get("exit") == 127:
        return v("not measured", None, None, None, "the coverage program could not start (exit 127)" + ("; " + hint if hint else ""))
    b = _num(base)
    if b is None:
        return v("not measured", None, total, None, "no base value: " + (base_why or "no baseline was taken for this run"))
    ch = changed if isinstance(changed, dict) else {}
    ran, missed = int(ch.get("ran") or 0), int(ch.get("missed") or 0)
    if ch and ran + missed >= CHANGED_MIN:
        floor, share = min(b, COVERAGE_CAP), round(100.0 * ran / (ran + missed), 1)
        ok = share >= floor
        return v("pass" if ok else "fail", "changed lines", share, floor, "%d of %d changed lines ran (%s%%), %s the floor %s%% "
                 "(the base total %s%%, at most 80)" % (ran, ran + missed, _pct(share), "at or above" if ok else "below",
                                                        _pct(floor), _pct(b)))
    if total is not None:
        floor = round(b - 1, 1)
        ok = total >= floor
        return v("pass" if ok else "fail", "total", total, floor, "total %s%% against the base total %s%% (it may be at most 1 "
                 "point lower)%s" % (_pct(total), _pct(b), "" if ok else ": a drop of %s points" % _pct(b - total)))
    return v("not measured", None, None, None, note or "no coverage total in the report")


def base_value(path):
    """(the base total, why there is none) from the baseline (.temper/evidence/baseline.json, written by WP20), only when
    it ran on the code of the run's base commit (base_sha of the run state beside it; .temper/ and .claude/ aside): one
    taken again later, past `integrate`, measured the change."""
    d = acc_read(path)
    c = _num(d.get("coverage"))
    temper = os.path.dirname(os.path.dirname(os.path.abspath(path)))
    sha = acc_read(os.path.join(temper, "build-state.json")).get("base_sha")
    if c is not None and d.get("head") and sha and d["head"] != sha and subprocess.run(
            ["git", "diff", "--quiet", d["head"], sha, "--", ".", ":(exclude).temper", ":(exclude).claude"],
            cwd=os.path.dirname(temper), capture_output=True).returncode == 1:
        return None, "the baseline ran on %s, not on the run's base %s" % (str(d["head"])[:12], str(sha)[:12])
    if c is not None:
        return c, ""
    if not d:
        return None, "no baseline was taken for this run"
    if d.get("result") == "red":
        return None, "the base was red, so it gave no coverage total"
    return None, "the baseline recorded no coverage total"


def _line_hits(root, det):
    """{path: (lines that ran, lines that did not)} from the coverage report's line data: coverage.py's JSON, Go's
    profile, lcov.info of jest, vitest and c8. {} when the tool gives none."""
    cov = det.get("coverage") or {}
    kind, hits, sub = cov.get("kind"), {}, cov.get("dir") or ""

    def add(p, line, n):
        r, m = hits.setdefault(os.path.normpath(os.path.join(sub, p)), (set(), set()))
        (r if n else m).add(line)
    if kind == "coverage.py":
        for p, f in (json.load(open(os.path.join(root, cov["file"]))).get("files") or {}).items():
            for line in f.get("executed_lines") or []:
                add(os.path.normpath(p), line, 1)
            for line in f.get("missing_lines") or []:
                add(os.path.normpath(p), line, 0)
    elif kind == "go":
        mod = re.search(r"^module\s+(\S+)", _read(os.path.join(root, sub, "go.mod")), re.M)
        for line in _read(os.path.join(root, cov["file"])).splitlines():
            m = re.match(r"^(.+?):(\d+)\.\d+,(\d+)\.\d+ \d+ (\d+)$", line)
            if m:
                p = m.group(1)
                if mod and p.startswith(mod.group(1) + "/"):
                    p = p[len(mod.group(1)) + 1:]
                for n in range(int(m.group(2)), int(m.group(3)) + 1):
                    add(p, n, int(m.group(4)))
    elif cov.get("lcov"):
        p = None
        for line in _read(os.path.join(root, cov["lcov"])).splitlines():
            if line.startswith("SF:"):
                p = os.path.relpath(os.path.join(root, sub, line[3:].strip()), os.path.join(root, sub))
            elif line.startswith("DA:") and p:
                n, c = (line[3:].split(",") + ["0"])[:2]
                add(p, int(n), int(float(c or 0)))
    return {p: (r, m - r) for p, (r, m) in hits.items()}


def line_data(root, det, base):
    """{"ran", "missed"}: the changed executable lines (a line the report lists as run or as missed) that ran and that did
    not; None when the tool gives no line data."""
    try:
        hits = _line_hits(root, det)
    except (OSError, ValueError, KeyError, TypeError):
        return None
    if not hits or not base:
        return None
    ran = missed = 0
    for p, lines in changed_lines(root, base).items():
        r, m = hits.get(p, (set(), set()))
        ran, missed = ran + len(lines & r), missed + len(lines & m)
    return {"ran": ran, "missed": missed}


def measure_of(root, det, base):
    """The coverage a passing suite run left (WP22): the report command, the total and the changed lines, kept with the
    pass in the store, so a reused run gives them too."""
    cov = det.get("coverage") or {}

    def measure(out):
        rout = run_env.run_cmd(root, 300, [cov["report"]])[0] if cov.get("report") else b""
        total = coverage_value(root, det, (out + b"\n" + rout).decode("utf-8", "replace"))
        return {"coverage": total, "changed": line_data(root, det, base) if total is not None else None, "base": base,
                "report": rout[-2048:].decode("utf-8", "replace")}
    return measure


def coverage_row(root, det, cmd, out, rc, cov_exit, base, threshold, extra=None):
    """The one coverage row of the ledger: the verdict's fields beside what it was judged on, so the gate judges it again
    with the config and the baseline as they are then."""
    cov = det.get("coverage")
    ok = cov and rc == 0 and cov_exit != 127
    m = extra if isinstance(extra, dict) else {}
    total = m.get("coverage") if ok and "coverage" in m else coverage_value(root, det, out.decode("utf-8", "replace")) if ok else None
    changed = (m.get("changed") if m.get("base") == base else None) if "coverage" in m else (
        line_data(root, det, base) if total is not None else None)
    note = "the suite failed, so no coverage was taken" if cov and rc != 0 and cov_exit != 127 else ""
    measure = {"total": total, "command": bool(cov), "exit": cov_exit, "hint": det.get("hint") or "", "note": note}
    b, why = base_value(os.path.join(root, ".temper", "evidence", "baseline.json"))
    v = coverage_verdict(measure, b, changed, threshold, why)
    code = {"pass": 0, "fail": 1}.get(v["state"])
    return row("coverage", cmd if cov else "", code, v["why"], value=total, artifact=(cov or {}).get("file"), rule=v["rule"],
               floor=v["floor"], state=v["state"], share=v["value"] if v["rule"] == "changed lines" else None, changed=changed,
               command=bool(cov), cov_exit=cov_exit, hint=measure["hint"], note=note)




def setup_fault(out, rc, cmd):
    """Why a run failed on its environment, not on the code ("" when it did not): the project's own setup marker
    (`temper-check: SETUP: ...`), else a sure sign of run_env.env_fault (a time-out stays the code's)."""
    text = out.decode("utf-8", "replace") if isinstance(out, bytes) else str(out or "")
    if rc == 0:
        return ""
    m = re.search(r"^[\w.-]+: SETUP: (.+)$", text, re.M)   # a project script's marker: `temper-check: SETUP: no Postgres ...`
    if m:
        return " ".join(m.group(1).split())[:200]
    return run_env.env_fault(text, rc, cmd)


def row(claim, cmd, rc, out, **kw):
    r = {"claim": claim, "cmd": cmd, "exit_code": rc, "artifact": None, "sha256": None, "value": None, "severity": None,
         "phase": "check", "scenario": None, "criterion": None, "label": "PROVEN" if rc == 0 else "HEURISTIC",
         "executed_by": "cli", "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
         "output": strip_banner((out or b"").decode("utf-8", "replace") if isinstance(out, bytes) else str(out or ""))[-2048:]}
    r.update(kw)
    return r


# ---- mutation ----------------------------------------------------------------------------------------------------
CMP_SWAP = {ast.Lt: ast.LtE, ast.LtE: ast.Lt, ast.Gt: ast.GtE, ast.GtE: ast.Gt, ast.Eq: ast.NotEq, ast.NotEq: ast.Eq,
            ast.In: ast.NotIn, ast.NotIn: ast.In}


SOURCE_EXT = run_env.SOURCE_EXT
is_test_path = run_env.is_test_path   # WP22: the runner reads them too (a byproduct is never a source or test file)


def changed_lines(root, base):
    """{path: set(line numbers)} of added or changed lines in non-test source files, against base (uncommitted work too)."""
    out, path = {}, None
    try:
        diff = subprocess.run(["git", "diff", "-U0", base, "--", "."], cwd=root, capture_output=True, text=True).stdout
        new = subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=root, capture_output=True, text=True).stdout
    except OSError:
        return {}
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("@@") and path:
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            start, n = int(m.group(1)), int(m.group(2) or 1)
            out.setdefault(path, set()).update(range(start, start + n))
    for p in new.splitlines():
        if p.endswith((".py",) + TEXT_EXT):
            try:
                out[p] = set(range(1, len(open(os.path.join(root, p), encoding="utf-8").read().splitlines()) + 1))
            except OSError:
                pass
    return {p: ls for p, ls in out.items() if p.endswith((".py",) + TEXT_EXT) and ls and not is_test_path(p)
            and not p.startswith((".temper/", ".claude/"))}


def mutants_of(source, lines):
    tree = ast.parse(source)
    nodes = list(ast.walk(tree))
    spots = []
    for i, node in enumerate(nodes):
        if getattr(node, "lineno", None) not in lines:
            continue
        if isinstance(node, ast.Compare):
            spots += [(i, ("cmp", k)) for k, op in enumerate(node.ops) if type(op) in CMP_SWAP]
        elif isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub)):
            spots.append((i, ("binop",)))
        elif isinstance(node, ast.Constant) and type(node.value) is int:
            spots.append((i, ("const",)))
        elif isinstance(node, ast.BoolOp):
            spots.append((i, ("boolop",)))
        elif isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            spots.append((i, ("not",)))
        elif isinstance(node, ast.Expr) and isinstance(node.value, ast.Call):
            spots.append((i, ("delcall",)))
    out = []
    for i, kind in spots:
        t2 = copy.deepcopy(tree)
        target = list(ast.walk(t2))[i]
        if kind[0] == "cmp":
            target.ops[kind[1]] = CMP_SWAP[type(target.ops[kind[1]])]()
        elif kind[0] == "binop":
            target.op = ast.Sub() if isinstance(target.op, ast.Add) else ast.Add()
        elif kind[0] == "const":
            target.value = target.value + 1
        elif kind[0] == "boolop":
            target.op = ast.Or() if isinstance(target.op, ast.And) else ast.And()
        elif kind[0] == "not":
            for parent in ast.walk(t2):
                for field, val in ast.iter_fields(parent):
                    if val is target:
                        setattr(parent, field, target.operand)
                    elif isinstance(val, list) and target in val:
                        val[val.index(target)] = target.operand
        elif kind[0] == "delcall":
            target.value = ast.Constant(value=None)
        try:
            out.append(("line %d: %s" % (target.lineno, kind[0]), ast.unparse(ast.fix_missing_locations(t2))))
        except Exception:
            continue
    return out


# 9.8.0: mutants for C-style languages (JavaScript, TypeScript, Java, Kotlin, Go, C#, Rust, Swift, Scala, C, C++, PHP,
# Ruby), on the text of a changed line. Only an operator with a space on each side counts, so a generic (List<String>),
# an arrow (=>, ->), a shift (<<) or an increment (++) is never touched; string contents are masked first, and a comment
# line is skipped.
TEXT_EXT = (".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".java", ".kt", ".go", ".cs", ".rs", ".swift", ".scala",
            ".c", ".cc", ".cpp", ".h", ".hpp", ".php", ".rb")
_OPS = [(" <= ", " < "), (" >= ", " > "), (" < ", " <= "), (" > ", " >= "), (" === ", " !== "), (" !== ", " === "),
        (" == ", " != "), (" != ", " == "), (" && ", " || "), (" || ", " && "), (" + ", " - "), (" - ", " + ")]
_WORDS = [(re.compile(r"\btrue\b"), "false"), (re.compile(r"\bfalse\b"), "true")]
_NUM = re.compile(r"(?<![\w.])(\d+)(?![\w.])")
_COMMENT = re.compile(r"^\s*(//|#|/\*|\*|--)")


def _mask(line):
    """The line with the inside of each string literal replaced by spaces (same length), so no match lands in a string."""
    out, q, i = list(line), None, 0
    while i < len(line):
        ch = line[i]
        if q:
            if ch == "\\":
                out[i] = " "
                if i + 1 < len(line):
                    out[i + 1] = " "
                i += 2
                continue
            if ch == q:
                q = None
            else:
                out[i] = " "
        elif ch in "\"'`":
            q = ch
        i += 1
    return "".join(out)


def text_mutants(source, lines):
    """[(description, new source)]: one change at one place of one changed line each."""
    src = source.split("\n")
    out = []
    for ln in sorted(lines):
        if ln < 1 or ln > len(src):
            continue
        line = src[ln - 1]
        if not line.strip() or _COMMENT.match(line):
            continue
        masked = _mask(line)
        spots = []
        for old, new in _OPS:
            start = 0
            while True:
                k = masked.find(old, start)
                if k < 0:
                    break
                spots.append((k, len(old), new, "%s->%s" % (old.strip(), new.strip())))
                start = k + 1
        for rx, new in _WORDS:
            for m in rx.finditer(masked):
                spots.append((m.start(), m.end() - m.start(), new, "%s->%s" % (m.group(0), new)))
        for m in _NUM.finditer(masked):
            spots.append((m.start(1), len(m.group(1)), str(int(m.group(1)) + 1), "const"))
        seen = set()
        for k, n, new, what in spots:
            if (k, n) in seen:
                continue
            seen.add((k, n))
            mutated = line[:k] + new + line[k + n:]
            out.append(("line %d: %s" % (ln, what), "\n".join(src[:ln - 1] + [mutated] + src[ln:])))
    return out


def _stopped(root):
    """True once Check started more than STOP_AFTER_S ago: `check run` writes the time into .temper/check/mutation.stop."""
    try:
        return time.time() > float(open(os.path.join(root, ".temper", "check", "mutation.stop")).read().strip())
    except (OSError, ValueError):
        return False


def mutation(root, base, test_cmd, suite_s):
    """(score percent | None, planted, caught, survivors, note)."""
    planted = []
    for path, lines in sorted(changed_lines(root, base).items()):
        try:
            text = open(os.path.join(root, path), encoding="utf-8").read()
            planted += [(path, d, s) for d, s in (mutants_of(text, lines) if path.endswith(".py") else text_mutants(text, lines))]
        except (OSError, SyntaxError, ValueError, UnicodeDecodeError):
            continue
    if not planted:
        return None, 0, 0, [], "no changed source lines to mutate"
    if len(planted) > MUTANT_CAP:
        step = len(planted) / MUTANT_CAP
        planted = [planted[int(i * step)] for i in range(MUTANT_CAP)]
    tmp = tempfile.mkdtemp(prefix="temper-mut-")
    caught, survivors, ran, t0 = 0, [], 0, time.time()
    per = max(30.0, 3 * suite_s)
    try:
        w = os.path.join(tmp, "w")
        shutil.copytree(root, w, symlinks=True, ignore=shutil.ignore_patterns(".git", "__pycache__", ".temper", ".claude", "node_modules"))
        if os.path.isdir(os.path.join(root, "node_modules")):   # the dependencies are read, never changed: a link will do
            os.symlink(os.path.join(root, "node_modules"), os.path.join(w, "node_modules"))
        for path, desc, src in planted:
            if time.time() - t0 > MUTATION_BUDGET_S or _stopped(root):
                break
            full = os.path.join(w, path)
            orig = open(full, encoding="utf-8").read()
            open(full, "w", encoding="utf-8").write(src)
            _, rc = run_env.run_cmd(w, per, [test_cmd])
            open(full, "w", encoding="utf-8").write(orig)
            ran += 1
            if rc != 0:
                caught += 1
            else:
                survivors.append("%s %s" % (path, desc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if ran < 3:
        return None, ran, caught, survivors, ("only %d mutant(s) in the changed lines" % ran if ran == len(planted)
                                              else "only %d mutant(s) ran in the time budget" % ran)
    return round(100.0 * caught / ran, 1), ran, caught, survivors, ""


# ---- regression proof (fix runs) ---------------------------------------------------------------------------------
def regression(root, base, test_cmd):
    """(rc, detail): rc 0 when the tests the fix added or changed FAIL on the code at base (they prove the fix)."""
    try:
        names = subprocess.run(["git", "diff", "--name-only", base, "--", "."], cwd=root, capture_output=True, text=True).stdout.split()
        names += subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=root, capture_output=True, text=True).stdout.split()
    except OSError:
        return 1, "git is not available"
    tests = sorted({n for n in names if is_test_path(n) and os.path.exists(os.path.join(root, n))
                    and not n.startswith((".temper/", ".claude/"))})
    if not tests:
        return 1, "the fix changed no test: a fix needs a regression test that fails without it"
    tmp = tempfile.mkdtemp(prefix="temper-reg-")
    try:
        w = os.path.join(tmp, "w")
        if subprocess.run(["git", "worktree", "add", "--detach", "-q", w, base], cwd=root, capture_output=True).returncode != 0:
            return 1, "could not check out the code before the fix (%s)" % base[:12]
        for t in tests:
            os.makedirs(os.path.dirname(os.path.join(w, t)) or w, exist_ok=True)
            shutil.copy2(os.path.join(root, t), os.path.join(w, t))
        out, rc = run_env.run_cmd(w, SUITE_TIMEOUT_S, [test_cmd])
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", w], cwd=root, capture_output=True)
        shutil.rmtree(tmp, ignore_errors=True)
    if rc == 0:
        return 1, "the new or changed tests (%s) pass on the code before the fix too, so they do not prove it" % ", ".join(tests)[:200]
    return 0, "the new or changed tests (%s) fail on the code before the fix and pass with it" % ", ".join(tests)[:200]


# ---- acceptance tests written before Build (agents/acceptance.md) --------------------------------------------------
def _digests(folder, root):
    out = {}
    for d, dirs, files in os.walk(folder):
        dirs[:] = [x for x in dirs if x != "__pycache__"]
        for f in sorted(files):
            if f.endswith((".pyc", ".pyo")):
                continue
            p = os.path.join(d, f)
            import hashlib
            out[os.path.relpath(p, root)] = hashlib.sha256(open(p, "rb").read()).hexdigest()
    return out


def acc_read(lockfile):
    try:
        d = json.load(open(lockfile))
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def acc_write(lockfile, d):
    os.makedirs(os.path.dirname(lockfile), exist_ok=True)
    tmp = "%s.tmp.%d" % (lockfile, os.getpid())
    with open(tmp, "w") as f:
        json.dump(d, f, indent=2)
    os.replace(tmp, lockfile)


def acc_copy_dir(lockfile):
    """Where the lock keeps a copy of the locked files, so `acceptance restore` can put them back."""
    return os.path.join(os.path.dirname(lockfile), "acceptance-locked")


# The signs that a test command cannot run at all, as opposed to tests that fail (the expected state at the lock): the
# shell found no program, the test runner itself is not installed, or the runner found no test to run.
CANNOT_RUN = re.compile(r"command not found|No module named '?(pytest|nose2?|tox|hypothesis)'?\b|Cannot find module '(jest|vitest|mocha)'|"
                        r"\bNO TESTS RAN\b|^Ran 0 tests\b|no tests ran\b|No tests found", re.M | re.I)


def cannot_run(root, cmd, timeout=300):
    """9.8.0 (round 5): why the acceptance command cannot run here, or None. A measured run locked `python3 -m pytest` with
    pytest not installed: Check could never pass, and only the person could reopen the lock. Tests that fail are fine (the
    feature is not built yet); a timeout is no proof either way, and passes."""
    out, rc = run_env.run_cmd(root, timeout, [cmd])
    text = out.decode("utf-8", "replace")[-4000:]
    if rc == 124:
        return None
    m = CANNOT_RUN.search(text)
    if rc in (126, 127) or m or ("pytest" in cmd and rc in (4, 5)):
        line = (m.group(0) if m else "exit %d" % rc).strip()
        return "the command cannot run here (%s)" % line[:120]
    return None


def acc_lock(root, spec, lockfile, cmd):
    folder = os.path.join(root, spec, "acceptance")
    files = _digests(folder, root) if os.path.isdir(folder) else {}
    if not any(re.search(r"test", os.path.basename(f), re.I) for f in files):
        print("FAIL: no test file in %s/acceptance" % spec, file=sys.stderr)
        return 1
    if not cmd.strip():
        print("FAIL: usage: temper acceptance lock --cmd '<command that runs the acceptance folder>'", file=sys.stderr)
        return 1
    # 9.8.0: every state the intent lists (`**States:** a, b`) is named in some acceptance test, so a state no test brings
    # a record into (a canceled one read back) cannot pass unseen.
    try:
        itext = open(os.path.join(root, spec, "intent.md"), encoding="utf-8").read()
    except OSError:
        itext = ""
    sm = re.search(r"^\*\*States:\*\*\s*(.+?)\s*$", itext, re.M)
    if sm:
        states = [x.strip(" `'\".").lower() for x in sm.group(1).split(",") if x.strip(" `'\".")]
        body = " ".join(open(os.path.join(root, f), encoding="utf-8", errors="replace").read().lower() for f in files)
        missing = [x for x in states if x not in body]
        if missing:
            print("FAIL: no acceptance test names the state(s) %s that intent.md lists (**States:**); add a test that brings a record into each and reads it back" % ", ".join(missing), file=sys.stderr)
            return 1
    why = cannot_run(root, cmd)
    if why:
        print("FAIL: %s: lock the acceptance tests with a command that runs in this project (the runner the project's own "
              "tests use), and lock again" % why, file=sys.stderr)
        return 1
    d = acc_read(lockfile)
    same = d.get("spec") == spec
    # A lock is taken once. Only the person reopens it (the Build or Check question's "Correct the acceptance test"), so a builder
    # cannot change a locked test and lock it again.
    if same and d.get("cmd") and not d.get("reopened"):
        print("FAIL: the acceptance tests are locked already; only the person reopens them (Correct the acceptance test, at the %s "
              "question)" % stage_label(root), file=sys.stderr)
        return 1
    corrections = list(d.get("corrections") or []) if same else []
    if same and d.get("reopened"):
        corrections.append(dict(d["reopened"], changed=sorted(f for f in set(files) | set(d.get("files", {}))
                                                         if files.get(f) != d.get("files", {}).get(f))))
    import shutil
    cp = acc_copy_dir(lockfile)
    shutil.rmtree(cp, ignore_errors=True)
    for rel in files:
        dst = os.path.join(cp, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(root, rel), dst)
    out = {"spec": spec, "cmd": cmd, "files": files, "launches": d.get("launches", 0) if same else 0,
           "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    if corrections:
        out["corrections"] = corrections
    acc_write(lockfile, out)
    print("OK: %d acceptance file(s) locked; Check runs: %s" % (len(files), cmd))
    return 0


def acc_reopen(spec, lockfile, reason):
    """The person says a locked test is wrong (the question of the stage the run is at): the lock opens for one correction, which the
    acceptance writer makes and locks again. The report and the gate row show the reason."""
    d = acc_read(lockfile)
    if d.get("spec") != spec or not d.get("cmd"):
        print("FAIL: no locked acceptance tests in this run", file=sys.stderr)
        return 1
    if not reason.strip():
        print("FAIL: usage: temper acceptance reopen --reason '<why the test is wrong>'", file=sys.stderr)
        return 1
    d["reopened"] = {"reason": reason.strip()[:300], "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    acc_write(lockfile, d)
    print("OK: the acceptance tests are open for one correction: %s" % reason.strip()[:300])
    return 0


def acc_triage(spec, lockfile, text):
    """The triage of a failing locked test (agents/acceptance.md, Triage): `code: why` or `test: why`. It only sets which
    option the question of the stage recommends; the person decides. Kept with a digest of the failure it read, so a new
    failure gets a new triage."""
    d = acc_read(lockfile)
    m = re.match(r"^\s*(code|test)\s*[:-]\s*(.+)$", text or "", re.S | re.I)
    if d.get("spec") != spec or not d.get("cmd") or not m:
        print("FAIL: usage: temper acceptance triage --reason 'code: <why>' | 'test: <why>' (a locked run)", file=sys.stderr)
        return 1
    d["triage"] = {"verdict": m.group(1).lower(), "reason": " ".join(m.group(2).split())[:300],
                   "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    acc_write(lockfile, d)
    if d["triage"]["verdict"] == "test":   # WP23: a locked test the triage calls wrong is a record of class plan
        try:
            root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(lockfile))))
            _failures().triaged_test(stage_label(root).lower(), root)
        except Exception:
            pass
    print("OK: triage recorded: the %s looks wrong" % d["triage"]["verdict"])
    return 0


def acc_triaged(spec, lockfile, failure):
    """After the triage agent: which failure it read (the flow's digest of the acceptance row), so the triage counts
    for that failure only. No triage recorded: the agent did not finish, and the question is asked without one."""
    d = acc_read(lockfile)
    if d.get("spec") != spec:
        return 0
    t = d.get("triage") if isinstance(d.get("triage"), dict) else {}
    d["triage"] = dict(t, failure=failure.strip()) if t.get("verdict") else {"failure": failure.strip(), "verdict": ""}
    acc_write(lockfile, d)
    print("OK: triage of failure %s %s" % (failure.strip()[:12], "recorded" if t.get("verdict") else "not given"))
    return 0


def acc_restore(root, spec, lockfile):
    """Put the locked acceptance files back as they were locked (a builder changed one): no decision, the person's lock holds."""
    d = acc_read(lockfile)
    if d.get("spec") != spec or not d.get("cmd"):
        print("FAIL: no locked acceptance tests in this run", file=sys.stderr)
        return 1
    import shutil
    cp = acc_copy_dir(lockfile)
    folder = os.path.join(root, spec, "acceptance")
    missing = [rel for rel in d.get("files", {}) if not os.path.isfile(os.path.join(cp, rel))]
    if missing:
        print("FAIL: the lock kept no copy of %s; restore them by hand" % ", ".join(missing[:3]), file=sys.stderr)
        return 1
    now = _digests(folder, root) if os.path.isdir(folder) else {}
    for rel in now:
        if rel not in d.get("files", {}):
            os.remove(os.path.join(root, rel))
    for rel in d.get("files", {}):
        dst = os.path.join(root, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(cp, rel), dst)
    print("OK: %d acceptance file(s) restored as they were locked" % len(d.get("files", {})))
    return 0


def acc_skip(spec, lockfile, reason):
    if not reason.strip():
        print("FAIL: usage: temper acceptance skip --reason '<why>'", file=sys.stderr)
        return 1
    d = acc_read(lockfile)
    acc_write(lockfile, {"spec": spec, "skipped": reason.strip(), "launches": d.get("launches", 0),
                         "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
    print("OK: no acceptance tests for this run: %s" % reason.strip())
    return 0


# The launches of the acceptance writer a run allows: to write the tests before Build (a writer that cannot lock does not
# hold Build up: the flow records the skip), and to correct a test each time the person reopens the lock (then the
# question of the stage is the person's again). flow.py reads both.
ACC_MAX_LAUNCHES = 2
ACC_MAX_CORRECTIONS = 2


def acc_start(spec, lockfile):
    """One launch of the acceptance writer (its agent's `before` call): of the writer before Build, or, while the person's
    reopen stands, of the correction. Past the limit it is refused, and nothing is counted."""
    d = acc_read(lockfile)
    if d.get("spec") != spec:
        d = {"spec": spec, "launches": 0}
    if isinstance(d.get("reopened"), dict):
        n = int(d["reopened"].get("launches", 0))
        if n >= ACC_MAX_CORRECTIONS:
            print("FAIL: the acceptance writer was launched %d times for this correction; the %s question is the person's"
                  % (n, stage_label(os.getcwd())), file=sys.stderr)
            return 1
        d["reopened"]["launches"] = n + 1
        acc_write(lockfile, d)
        print("OK: acceptance correction launch %d" % (n + 1))
        return 0
    if d.get("cmd") or d.get("skipped"):
        print("FAIL: the acceptance tests are %s already; no writer is launched" % ("locked" if d.get("cmd") else "skipped"), file=sys.stderr)
        return 1
    if int(d.get("launches", 0)) >= ACC_MAX_LAUNCHES:
        print("FAIL: the acceptance writer was launched %d times and locked no test; skip them (temper acceptance skip --reason)" % int(d.get("launches", 0)), file=sys.stderr)
        return 1
    d["launches"] = int(d.get("launches", 0)) + 1
    acc_write(lockfile, d)
    print("OK: acceptance launch %d" % d["launches"])
    return 0


def acc_run(root, spec, lockfile):
    """The acceptance row(s) for the checks when Build ends and for Check: [] when this run has no lock."""
    d = acc_read(lockfile)
    if not spec or d.get("spec") != os.path.relpath(spec, root) or not (d.get("cmd") or d.get("skipped")):
        return []
    if d.get("skipped"):
        return [row("acceptance (written before Build): skipped", "", 0, d["skipped"], label="HEURISTIC")]
    if d.get("reopened"):
        return [row("acceptance (written before Build)", d["cmd"], 1,
                    "reopened to correct a test (%s); not locked again" % d["reopened"].get("reason", ""))]
    now = _digests(os.path.join(spec, "acceptance"), root) if os.path.isdir(os.path.join(spec, "acceptance")) else {}
    changed = sorted(f for f in set(now) | set(d.get("files", {})) if now.get(f) != d.get("files", {}).get(f))
    if changed:
        return [row("acceptance (written before Build)", d["cmd"], 1,
                    "changed after they were locked: %s" % ", ".join(changed)[:300])]
    info = {}   # WP22: its tests live under .temper/, outside the digest, so the lock's file digests are in its key
    import baseline   # WP20: the limit from the base's time of the same suite and from a kept limit, at least Check's
    out, rc, _ = run_env.run_cached(root, baseline.limit_for(d["cmd"], SUITE_TIMEOUT_S, root), [d["cmd"]], info=info,
                                    extra={"lock": d.get("files") or {}}, root=root)
    fixed = [c.get("reason", "") for c in d.get("corrections") or [] if isinstance(c, dict)]
    name = "acceptance (written before Build)" + (", corrected after the lock: %s" % "; ".join(fixed)[:200] if fixed else "")
    return [row(name, d["cmd"], rc, out, **run_env.row_fields(info))]


# ---- run -----------------------------------------------------------------------------------------------------------
def plan_line(spec):
    """The plan's **Integration:** text (WP23: the owner of the suite only when the config and detect name none)."""
    m = re.search(r"^\*\*Integration:\*\*\s*`([^`]+)`", _read(os.path.join(spec, "tasks.md")) if spec else "", re.M)
    line = m.group(1).strip() if m else ""
    return "" if line == "manual" else line


def stage_label(root):
    """The stage the run is at, in the person's words, for a text that names its question (Build or Check)."""
    st = acc_read(os.path.join(root, ".temper", "build-state.json")).get("next_stage")
    return {"build": "Build", "fix": "Build", "review": "Review", "check": "Check"}.get(st, "Build")


def _failures():
    import failure
    return failure


# the limit of a run of the checks: at Build TEMPER_INTEGRATION_TIMEOUT_S (an hour), at Check SUITE_TIMEOUT_S
LIMIT_S = {"build": lambda: float(os.environ.get("TEMPER_INTEGRATION_TIMEOUT_S") or 3600), "check": lambda: SUITE_TIMEOUT_S}


def run(root, spec, ledger, base, command, test_cmd="", cov_cmd="", threshold="", info=None, stage="check", suite=True):
    """Check's run (stage check), or the checks when Build ends (stage build, `build-checks`, WP23): the suite in the
    owner's run text with its coverage, the coverage row, each scenario test, the locked acceptance tests and a fix's
    regression proof, each through the reuse store and recorded in the stage's ledger; every failed run is one failure
    record. Returns the suite's exit code at Build (0 when the person's skip of a red base covers it), else 0; 3 at Check
    with no test command."""
    det = det_for(root, test_cmd, cov_cmd)
    line = plan_line(spec)   # WP23 mechanism 2: at Build and at Check, so a run never ends at Check for want of a command
    if not det and line:   # the plan's line owns the suite only when the config and detect name none
        det = detect(root, line)
    if not det and stage != "build":
        print("UNKNOWN: no test command for this project; set check.commands.test")
        return 3
    try:
        rows = json.load(open(ledger))
        rows = rows if isinstance(rows, list) else []
    except (OSError, ValueError):
        rows = []
    os.makedirs(os.path.join(root, ".temper", "check"), exist_ok=True)
    ran = []   # (check, the row's index in the ledger)

    def add(r_, check=None):
        rows.append(r_)
        if check:
            ran.append((check, len(rows) - 1))
    cov = det.get("coverage")
    out, rc, out_rc = b"", 0, 0
    if det and suite:
        # the suite, with coverage on in the same run when the stack allows it
        cmd = cov["run"] if cov else det["test"]
        import baseline
        limit = baseline.limit_for(cmd, LIMIT_S[stage](), root)   # WP20: three times the base's time of the same suite, at least
        # WP22: through the reuse store; a kept pass of the same key (a group's Validate of the same text on the same
        # content, integrate's run on the tree Check judges) is used, with what it measured
        sinfo = {"measure": measure_of(root, det, base), "need_extra": True} if cov else {}
        out, rc, _ = run_env.run_cached(root, limit, [cmd], info=sinfo, root=root)
        if rc == 124:   # WP20 mechanism 14: twice the limit is kept, the next run's limit, so the kept time out runs again
            baseline.timed_out(cmd, limit, root)
        cov_exit = rc if cov else None
        if cov and rc == 127 and cmd != det["test"]:   # the coverage program could not start: the suite runs without it
            sinfo = {}
            out, rc, _ = run_env.run_cached(root, limit, [det["test"]], info=sinfo, root=root)
            cmd = det["test"]
        suite_s = float(sinfo.get("seconds") or 0)
        if isinstance(info, dict):
            info.update(suite_s=suite_s, rc=rc, det=det)
        extra = sinfo.get("extra") if isinstance(sinfo.get("extra"), dict) else {}
        if extra.get("report"):
            out = out + b"\n" + extra["report"].encode("utf-8")
        kw = dict(run_env.row_fields(sinfo), fail_lines=sinfo.get("fail_lines") or run_env.fail_lines(out, rc=rc)) if rc else \
            run_env.row_fields(sinfo)
        out_rc = rc
        if stage == "build":
            if line and line != cmd:
                kw["plan_cmd"] = line
            if rc != 0 and baseline.like_base(root, cmd, kw.get("fail_lines") or []):   # WP21: only the base's failures
                kw["state"], out_rc = "skipped", 0
                print("NOTE: the integration suite failed (exit %d) only as it failed on the base, which you went on from" % rc)
            add(row("Integration suite", cmd, rc, out, phase="integration", **kw), None if out_rc == 0 and rc else "suite")
        else:
            add(row("tests: the suite (run by the CLI)", cmd, rc, out, **kw), "suite")
        if stage == "build":
            show(out, rc)
            if out_rc:   # the reason integrate records
                print("REASON: integration suite failed (exit %d): %s" % (rc, cmd[:300]))
        print("tests: exit %d, %.1f s (%s)" % (rc, suite_s, cmd[:120]))
        why = setup_fault(out, rc, cmd)
        if why:   # the suite row stays red: the gate fails as before, and the question says SETUP
            add(row("setup fault: " + why, cmd, 1, b"", label="HEURISTIC"))
            print("SETUP: %s" % why)
        c = coverage_row(root, det, cov["run"] if cov else "", out, rc, cov_exit, base, threshold, extra)
        c.update({k: v for k, v in run_env.row_fields(sinfo).items() if k in ("tree", "key", "reused")})
        add(c, "coverage")
        print("coverage: %s: %s" % (c["state"], c["output"]))
    # each scenario's Test: command
    intent = os.path.join(spec, "intent.md") if spec else ""
    if intent and os.path.exists(intent):
        for b in acceptance.scenario_blocks(open(intent, encoding="utf-8").read().splitlines()):
            if not b.get("cmd", "").strip():
                continue
            i = {}
            import baseline
            sout, src, _ = run_env.run_cached(root, baseline.limit_for(b["cmd"], LIMIT_S[stage](), root), [b["cmd"]], info=i,
                                              root=root)
            add(row("scenario test at integration" if stage == "build" else "scenario: %s -> %s" % (b["name"], b["cmd"][:120]),
                    b["cmd"], src, sout, phase="scenario", scenario=b["name"], **run_env.row_fields(i)), "scenario")
            print("scenario '%s': exit %d%s" % (b["name"][:60], src, ", %.1f s" % float(i.get("seconds") or 0) if stage == "build" else ""))
    # the acceptance tests written before Build, as they were locked
    lockfile = os.path.join(root, ".temper", "evidence", "acceptance-lock.json")
    for r_ in acc_run(root, spec, lockfile):
        add(r_, "acceptance")
        print("acceptance: exit %s" % r_["exit_code"])
        why = setup_fault(r_.get("output") or "", r_["exit_code"] if isinstance(r_["exit_code"], int) else 1, r_.get("cmd") or "")
        if why and not any(str(x.get("claim", "")).startswith("setup fault: ") for x in rows[-3:]):
            add(row("setup fault: " + why, r_.get("cmd") or "", 1, b"", label="HEURISTIC"))
            print("SETUP: %s" % why)
    # regression proof of a fix
    if command == "fix" and base and det:
        rrc, detail = regression(root, base, det["test"])
        add(row("regression proof", det["test"], rrc, detail), "regression")
        print("regression: %s" % detail)
    tmp = "%s.tmp.%d" % (ledger, os.getpid())
    with open(tmp, "w") as f:
        json.dump(rows, f, indent=2)
    os.replace(tmp, ledger)
    if not isinstance(info, dict) or not info.get("ahead"):
        record(stage, rows, ran, root)
    return out_rc if stage == "build" else 0


def record(stage, rows, ran, root):
    """One failure record per failed run (WP23); a pass of the same check on another key resolves the open ones."""
    try:
        f = _failures()
        for check, i in ran:
            r_ = rows[i]
            if r_.get("exit_code") == 0 or (check == "coverage" and r_.get("state") != "fail"):
                if r_.get("exit_code") == 0:
                    f.resolve_pass("gate:%s" % stage, check, r_.get("key") or "", root)
                continue
            f.of_row(stage, "gate:%s" % stage, check, r_, i, root=root,
                     kind="coverage-drop" if check == "coverage" else None)
    except Exception as e:   # the record never fails a check: the rows and the verdict stand
        print("NOTE: the failure record was not written: %s" % str(e)[:160])


def show(out, rc, keep=12):
    """A suite's output for the orchestrator: a passing run its last lines, a failing one all of it."""
    lines = out.decode("utf-8", "replace").splitlines(True)
    if rc == 0 and len(lines) > keep:
        sys.stdout.write("[the first %d lines of the passing output are not shown]\n" % (len(lines) - keep))
        lines = lines[-keep:]
    sys.stdout.write("".join(lines))
    sys.stdout.flush()


# ---- ahead: Check's run made while Review reads the change ------------------------------------------------------------
# Review writes no code, so the CLI runs Check's commands through the reuse store in the background while the Review
# agent works, into a throwaway ledger: the store is warm, and `check run` finds each entry by its key (a call while
# that run goes on waits on the key's lock, then reads the entry). Then, and only here, the planted bugs run (WP19):
# when three runs of the suite fit MUTATION_BUDGET_S, into .temper/evidence/mutation.json. `check run` never waits for
# them.
def mutation_path(root):
    return os.path.join(root, ".temper", "evidence", "mutation.json")


def planted_write(root, tree, state, why="", **kw):
    d = dict({"state": state, "why": why, "ran": 0, "caught": 0, "survivors": [], "tree": tree,
              "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}, **kw)
    acc_write(mutation_path(root), d)


def planted(root):
    """The planted bug score as the card and the view show it: {"state", "text"} of mutation.json when it measured the
    tree as it is now; None when there is none, or it is of another tree."""
    d = acc_read(mutation_path(root))
    if not d.get("state") or d.get("tree") != run_env.tree_key(root, root=root):
        return None
    if d["state"] == "measured":
        n, c = int(d.get("ran") or 0), int(d.get("caught") or 0)
        return {"state": "measured", "text": "%d of %d planted bugs caught" % (c, n)}
    if d["state"] == "running":
        return {"state": "running", "text": "the planted bugs are still running"}
    return {"state": d["state"], "text": "no planted bug score: %s" % (d.get("why") or "not run")}


def plant(root, base, info, before):
    """The planted bugs of the tree `before`, beside Review: only on a green suite and when three runs of it fit."""
    det, suite_s = info.get("det") or {}, float(info.get("suite_s") or 0)
    if not det.get("mutation") or not base:
        return planted_write(root, before, "not run", "no base to read the changed lines against")
    if info.get("rc") != 0:
        return planted_write(root, before, "not run", "the suite failed (exit %s)" % info.get("rc"))
    if 3 * suite_s >= MUTATION_BUDGET_S:
        return planted_write(root, before, "not run", "three runs of the suite take %.1f s, not under the budget of %s s"
                             % (3 * suite_s, _pct(MUTATION_BUDGET_S)))
    planted_write(root, before, "running")
    score, ran, caught, surv, note = mutation(root, base, det["test"], suite_s)
    if score is None:
        return planted_write(root, before, "not run", note, ran=ran, caught=caught, survivors=surv)
    return planted_write(root, before, "measured", "", ran=ran, caught=caught, survivors=surv)


def ahead(root, spec, base, command, test_cmd="", cov_cmd="", threshold=""):
    for f in (os.path.join(root, ".temper", "check", "mutation.stop"), mutation_path(root)):
        if os.path.exists(f):
            os.remove(f)
    before = run_env.tree_key(root, root=root)
    fd, tmp = tempfile.mkstemp(prefix="temper-ahead-", suffix=".json")
    os.close(fd)
    open(tmp, "w").write("[]")
    import contextlib, io
    info = {"ahead": True}   # a throwaway ledger: its failures are recorded by the run that writes the stage's ledger
    try:
        with contextlib.redirect_stdout(io.StringIO()):   # the regression proof of a fix is no store run: check run makes it
            rc = run(root, spec, tmp, base, "", test_cmd, cov_cmd, threshold, info)
    finally:
        os.remove(tmp)
    if rc == 0 and run_env.tree_key(root, root=root) == before:
        plant(root, base, info, before)
    elif rc == 0:
        planted_write(root, before, "not run", "the tree changed while the suite ran")
    return 0


def main(argv):
    if len(argv) >= 5 and argv[1] == "acceptance":   # acceptance ROOT SPEC lock|skip|start [TEXT]
        root, spec, sub = argv[2], argv[3], argv[4]
        lockfile = os.path.join(root, ".temper", "evidence", "acceptance-lock.json")
        text = argv[5] if len(argv) > 5 else ""
        if sub == "lock":
            return acc_lock(root, spec, lockfile, text)
        if sub == "skip":
            return acc_skip(spec, lockfile, text)
        if sub == "start":
            return acc_start(spec, lockfile)
        if sub == "reopen":
            return acc_reopen(spec, lockfile, text)
        if sub == "restore":
            return acc_restore(root, spec, lockfile)
        if sub == "triage":
            return acc_triage(spec, lockfile, text)
        if sub == "triaged":
            return acc_triaged(spec, lockfile, text)
    if len(argv) >= 3 and argv[1] == "owner":   # owner ROOT [SPEC] (WP20): one JSON line
        o = suite_owner(argv[2], None, argv[3] if len(argv) > 3 else "")
        print(json.dumps({k: o[k] for k in ("test", "run", "source", "why")}))
        return 0
    if len(argv) >= 3 and argv[1] == "detect":
        print(json.dumps(detect(argv[2], argv[3] if len(argv) > 3 else "", argv[4] if len(argv) > 4 else "")))
        return 0
    if len(argv) == 2 and argv[1] == "coverage-verdict":   # one JSON object on standard input (case 60, w19 rule table)
        d = json.loads(sys.stdin.read() or "{}")
        print(json.dumps(coverage_verdict(d.get("measure"), d.get("base"), d.get("changed"), d.get("threshold"),
                                          d.get("base_why") or "")))
        return 0
    if len(argv) >= 6 and argv[1] == "ahead":   # ahead ROOT SPEC BASE COMMAND [TEST_CMD COV_CMD KEY]
        return ahead(*argv[2:6], *argv[6:9])
    if len(argv) >= 7 and argv[1] == "run":
        # the planted bugs beside Review go on at most STOP_AFTER_S from now; this run never waits for them
        stop = os.path.join(argv[2], ".temper", "check", "mutation.stop")
        os.makedirs(os.path.dirname(stop), exist_ok=True)
        open(stop, "w").write("%d\n" % (time.time() + STOP_AFTER_S))
        return run(*argv[2:7], *argv[7:10])
    if len(argv) >= 7 and argv[1] == "build-checks":   # build-checks ROOT SPEC LEDGER BASE COMMAND [TEST COV KEY [nosuite]]
        a = (argv[7:11] + ["", "", "", ""])[:4]
        return run(*argv[2:7], *a[:3], stage="build", suite=a[3] != "nosuite")
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
