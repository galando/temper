"""check_run.py: Check, run by the CLI (9.8.0). Before 9.8.0 a Sonnet agent ran the suite and typed the results into the
ledger; a row it forgot (coverage recorded as 'none') failed the gate for no fault of the code. Now the CLI runs the
commands and records what they gave, and the agent is only the fallback for a stack the CLI cannot read.

  python3 check_run.py detect ROOT [TEST_CMD] [COVERAGE_CMD]    the commands it would run, as JSON ({} when none)
  python3 check_run.py run ROOT SPEC LEDGER BASE COMMAND [TEST_CMD] [COVERAGE_CMD]
                                                                run them, record the rows, print one line each

What `run` records in the Check ledger, every row `executed_by: cli`:
  - tests       the suite (with coverage on in the same run when the stack allows it), its exit and output tail
  - coverage    the total line coverage, with the report as its artifact; when no coverage tool is there, a row that
                names what to install (the gate row says the measurement is missing, and Check runs again once it is)
  - scenario    each intent.md scenario's `Test:` command, its real exit (a scenario row is a real run, not a trace)
  - mutation    the mutation score of the tests on the lines this run changed (Python): one small bug at a time is
                planted (a comparison flipped, + and - swapped, a constant moved by one, `and`/`or` swapped, a `not`
                dropped, a call statement deleted) and the suite must catch it. Coverage says a line ran; this says a
                test would notice it break. Capped at 40 mutants and a time budget; skipped when nothing changed.
  - regression  (fix runs) the tests the fix added or changed, run on the code before the fix: they must FAIL there,
                or they do not prove the fix
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
TEST_DIR_NAMES = ("tests", "test", "unit", "spec")
MUTANT_CAP = 40
MUTATION_BUDGET_S = float(os.environ.get("TEMPER_MUTATION_BUDGET_S", "300"))
SUITE_TIMEOUT_S = float(os.environ.get("TEMPER_CHECK_TIMEOUT_S", "1800"))


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
               "mutation": any(True for _ in _py_files(root))}
        if cov_cmd:
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
            cov = {"run": "npx jest --coverage --coverageReporters=json-summary --coverageDirectory=.temper/check/coverage",
                   "kind": "jest", "file": ".temper/check/coverage/coverage-summary.json"}
        elif "vitest" in deps:
            cov = {"run": "npx vitest run --coverage --coverage.reporter=json-summary --coverage.reportsDirectory=.temper/check/coverage",
                   "kind": "vitest", "file": ".temper/check/coverage/coverage-summary.json"}
        elif "c8" in deps:
            cov = {"run": "npx c8 --reporter=json-summary --report-dir=.temper/check/coverage npm test --silent",
                   "kind": "c8", "file": ".temper/check/coverage/coverage-summary.json"}
        return {"stack": "node", "test": "npm test --silent", "coverage": cov,
                "hint": "" if cov else "add jest, vitest or c8 to measure coverage"}
    if os.path.exists(j("go.mod")):
        return {"stack": "go", "test": "go test ./...", "coverage": {"run": "go test ./... -coverprofile=.temper/check/cover.out",
                "report": "go tool cover -func=.temper/check/cover.out", "kind": "go", "file": ".temper/check/cover.out"}, "hint": ""}
    if os.path.exists(j("Cargo.toml")):
        return {"stack": "rust", "test": "cargo test", "coverage": None, "hint": "set check.commands.coverage (cargo llvm-cov) to measure coverage"}
    if os.path.exists(j("pom.xml")):
        return {"stack": "maven", "test": "mvn -q test", "coverage": None, "hint": "set check.commands.coverage (JaCoCo) to measure coverage"}
    if os.path.exists(j("build.gradle")) or os.path.exists(j("build.gradle.kts")):
        g = "./gradlew" if os.path.exists(j("gradlew")) else "gradle"
        return {"stack": "gradle", "test": "%s test" % g, "coverage": None, "hint": "set check.commands.coverage (JaCoCo) to measure coverage"}
    return {}


def _read(p):
    try:
        return open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


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
    m = re.findall(r"total:?\s+\(statements\)\s+([\d.]+)%|TOTAL\s+.*?\s([\d.]+)%\s*$|All files\s*\|\s*([\d.]+)", out_text, re.M)
    for g in reversed(m):
        v = next((x for x in g if x), None)
        if v:
            return round(float(v), 1)
    return None


def row(claim, cmd, rc, out, **kw):
    r = {"claim": claim, "cmd": cmd, "exit_code": rc, "artifact": None, "sha256": None, "value": None, "severity": None,
         "phase": "check", "scenario": None, "criterion": None, "label": "PROVEN" if rc == 0 else "HEURISTIC",
         "executed_by": "cli", "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
         "output": (out or b"")[-2048:].decode("utf-8", "replace") if isinstance(out, bytes) else str(out or "")[-2048:]}
    r.update(kw)
    return r


# ---- mutation ----------------------------------------------------------------------------------------------------
CMP_SWAP = {ast.Lt: ast.LtE, ast.LtE: ast.Lt, ast.Gt: ast.GtE, ast.GtE: ast.Gt, ast.Eq: ast.NotEq, ast.NotEq: ast.Eq,
            ast.In: ast.NotIn, ast.NotIn: ast.In}


SOURCE_EXT = (".py", ".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".go", ".java", ".kt", ".rb", ".rs", ".cs", ".php", ".swift", ".scala", ".sh")


def is_test_path(p):
    """A test source file: a test file name (test_x.py, x_test.go, x.test.ts, x.spec.js, XTest.java), or a source file in a
    tests folder. Never a compiled or cached file."""
    if "__pycache__" in p or not p.endswith(SOURCE_EXT):
        return False
    b = os.path.basename(p)
    return bool(re.match(r"^test_.*\.py$|^.*_test\.(py|go)$|^conftest\.py$|^.*\.(test|spec)\.[cm]?[jt]sx?$|^.*Tests?\.(java|kt|cs)$|^.*_spec\.rb$", b)) or any(
        part in TEST_DIR_NAMES for part in p.split("/")[:-1])


def changed_lines(root, base):
    """{path: set(line numbers)} of added or changed lines in non-test .py files, against base (uncommitted work too)."""
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
        if p.endswith(".py"):
            try:
                out[p] = set(range(1, len(open(os.path.join(root, p), encoding="utf-8").read().splitlines()) + 1))
            except OSError:
                pass
    return {p: ls for p, ls in out.items() if p.endswith(".py") and ls and not is_test_path(p)
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


def mutation(root, base, test_cmd, suite_s):
    """(score percent | None, planted, caught, survivors, note)."""
    planted = []
    for path, lines in sorted(changed_lines(root, base).items()):
        try:
            planted += [(path, d, s) for d, s in mutants_of(open(os.path.join(root, path), encoding="utf-8").read(), lines)]
        except (OSError, SyntaxError, ValueError):
            continue
    if not planted:
        return None, 0, 0, [], "no changed Python lines to mutate"
    if len(planted) > MUTANT_CAP:
        step = len(planted) / MUTANT_CAP
        planted = [planted[int(i * step)] for i in range(MUTANT_CAP)]
    tmp = tempfile.mkdtemp(prefix="temper-mut-")
    caught, survivors, ran, t0 = 0, [], 0, time.time()
    per = max(30.0, 3 * suite_s)
    try:
        w = os.path.join(tmp, "w")
        shutil.copytree(root, w, symlinks=True, ignore=shutil.ignore_patterns(".git", "node_modules", "__pycache__", ".temper", ".claude"))
        for path, desc, src in planted:
            if time.time() - t0 > MUTATION_BUDGET_S:
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


# ---- run -----------------------------------------------------------------------------------------------------------
def run(root, spec, ledger, base, command, test_cmd="", cov_cmd=""):
    det = detect(root, test_cmd, cov_cmd)
    if not det:
        print("UNKNOWN: no test command for this project; set check.commands.test")
        return 3
    try:
        rows = json.load(open(ledger))
        rows = rows if isinstance(rows, list) else []
    except (OSError, ValueError):
        rows = []
    os.makedirs(os.path.join(root, ".temper", "check"), exist_ok=True)
    cov = det.get("coverage")
    # the suite, with coverage on in the same run when the stack allows it
    cmd = cov["run"] if cov else det["test"]
    t0 = time.time()
    out, rc = run_env.run_cmd(root, SUITE_TIMEOUT_S, [cmd])
    suite_s = time.time() - t0
    if cov and cov.get("report") and rc == 0:
        rout, _ = run_env.run_cmd(root, 300, [cov["report"]])
        out = out + b"\n" + rout
    rows.append(row("tests: the suite (run by the CLI)", cmd, rc, out))
    print("tests: exit %d, %.1f s (%s)" % (rc, suite_s, cmd[:120]))
    if cov:
        val = coverage_value(root, det, out.decode("utf-8", "replace"))
        if val is not None and rc == 0:
            rows.append(row("coverage", cmd, 0, b"", value=val, artifact=cov.get("file")))
            print("coverage: %s%%" % val)
        else:
            print("coverage: not measured (%s)" % ("the suite failed" if rc else "no total in the report"))
    else:
        rows.append(row("coverage tool missing: " + (det.get("hint") or "no coverage command"), "", 1, b""))
        print("coverage: not measured: %s" % det.get("hint"))
    # each scenario's Test: command
    intent = os.path.join(spec, "intent.md") if spec else ""
    if intent and os.path.exists(intent):
        for b in acceptance.scenario_blocks(open(intent, encoding="utf-8").read().splitlines()):
            if not b.get("cmd", "").strip():
                continue
            sout, src = run_env.run_cmd(root, SUITE_TIMEOUT_S, [b["cmd"]])
            rows.append(row("scenario: %s -> %s" % (b["name"], b["cmd"][:120]), b["cmd"], src, sout, phase="scenario", scenario=b["name"]))
            print("scenario '%s': exit %d" % (b["name"][:60], src))
    # mutation score on the changed lines (Python), only on a green suite
    if det.get("mutation") and rc == 0 and base:
        score, ran, caught, surv, note = mutation(root, base, det["test"], suite_s)
        if score is None:
            rows.append(row("mutation: not measured (%s)" % note, "", 0, b"", label="HEURISTIC"))
            print("mutation: not measured (%s)" % note)
        else:
            rows.append(row("mutation score", "%d mutants of the changed lines" % ran, 0, "\n".join(surv), value=score))
            print("mutation: %s%% (%d of %d caught)" % (score, caught, ran))
    # regression proof of a fix
    if command == "fix" and base:
        rrc, detail = regression(root, base, det["test"])
        rows.append(row("regression proof", det["test"], rrc, detail))
        print("regression: %s" % detail)
    tmp = "%s.tmp.%d" % (ledger, os.getpid())
    with open(tmp, "w") as f:
        json.dump(rows, f, indent=2)
    os.replace(tmp, ledger)
    return 0


def main(argv):
    if len(argv) >= 3 and argv[1] == "detect":
        print(json.dumps(detect(argv[2], argv[3] if len(argv) > 3 else "", argv[4] if len(argv) > 4 else "")))
        return 0
    if len(argv) >= 7 and argv[1] == "run":
        return run(argv[2], argv[3], argv[4], argv[5], argv[6], argv[7] if len(argv) > 7 else "", argv[8] if len(argv) > 8 else "")
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
