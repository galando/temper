#!/usr/bin/env python3
"""mutate.py RUN_DIR [--max N]: how strong are the tests an arm left behind? Standard library only.

Hidden tests say whether the code is right today. This asks what protects it tomorrow: plant one small bug at a time
(a mutant) in the lines the arm changed under the task's code folder, run the arm's OWN suite (the task's suite
folder as the arm left it), and count the mutants it catches. The score is caught / planted.

Mutants (on changed lines only): a comparison flipped (< <=, > >=, == !=, in / not in), + and - swapped, an integer
constant moved by one, `and` / `or` swapped, a `not` removed, a call statement deleted (an audit.record, a store
write). At most --max mutants (default 80), picked evenly from the sorted list so the sample is deterministic. Some
mutants are equivalent (no test could catch them); that lowers every arm's score alike.

Writes RUN_DIR/mutation.json and prints it. It never changes RUN_DIR/work: it works on a copy.
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

HERE = os.path.dirname(os.path.abspath(__file__))
CMP_SWAP = {ast.Lt: ast.LtE, ast.LtE: ast.Lt, ast.Gt: ast.GtE, ast.GtE: ast.Gt, ast.Eq: ast.NotEq, ast.NotEq: ast.Eq,
            ast.In: ast.NotIn, ast.NotIn: ast.In}


def git(cwd, *a):
    return subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True).stdout


def changed_lines(cwd, base, code_dir):
    """{path: set(line numbers)} of lines added or changed under code_dir, against base."""
    git(cwd, "add", "-A")
    out, path, lines = {}, None, None
    for line in git(cwd, "diff", "--cached", "-U0", base, "--", code_dir).splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
            if path and path.endswith(".py"):
                lines = out.setdefault(path, set())
            else:
                path = None
        elif line.startswith("@@") and path:
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            start, n = int(m.group(1)), int(m.group(2) or 1)
            lines.update(range(start, start + n))
    return {p: ls for p, ls in out.items() if ls}


def mutants_of(source, lines):
    """Every single node mutant of source on the given lines: [(description, new source)]."""
    tree = ast.parse(source)
    spots = []
    for node in ast.walk(tree):
        ln = getattr(node, "lineno", None)
        if ln not in lines:
            continue
        if isinstance(node, ast.Compare):
            for i, op in enumerate(node.ops):
                if type(op) in CMP_SWAP:
                    spots.append((node, ("cmp", i)))
        elif isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub)):
            spots.append((node, ("binop",)))
        elif isinstance(node, ast.Constant) and type(node.value) is int:
            spots.append((node, ("const",)))
        elif isinstance(node, ast.BoolOp):
            spots.append((node, ("boolop",)))
        elif isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            spots.append((node, ("not",)))
        elif isinstance(node, ast.Expr) and isinstance(node.value, ast.Call):
            spots.append((node, ("delcall",)))
    out = []
    for idx, (_, kind) in enumerate(spots):
        t2 = copy.deepcopy(tree)
        target = [n for n in ast.walk(t2)][[n for n in ast.walk(tree)].index(spots[idx][0])]
        desc = f"line {target.lineno}: {kind[0]}"
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
            out.append((desc, ast.unparse(ast.fix_missing_locations(t2))))
        except Exception:
            continue
    return out


def suite_passes(cwd, suite_dir, timeout=60):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    try:
        p = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", suite_dir, "-t", "."], cwd=cwd,
                           capture_output=True, text=True, timeout=timeout, env=env)
        return p.returncode == 0
    except subprocess.TimeoutExpired:
        return False


def main():
    run_dir = os.path.abspath(sys.argv[1])
    cap = int(sys.argv[sys.argv.index("--max") + 1]) if "--max" in sys.argv else 80
    run = json.load(open(os.path.join(run_dir, "run.json")))
    meta = json.load(open(os.path.join(HERE, "tasks", run["task"], "meta.json")))
    code_dir, suite_dir = meta.get("code_dir", "ledger"), meta.get("suite_dir", "unit")
    tmp = tempfile.mkdtemp(prefix="bench-mut-")
    try:
        w = os.path.join(tmp, "w")
        shutil.copytree(os.path.join(run_dir, "work"), w, symlinks=True, ignore=shutil.ignore_patterns("__pycache__"))
        result = {"task": run["task"], "arm": run["arm"], "rep": run["rep"]}
        if not suite_passes(w, suite_dir):
            result.update(planted=0, caught=0, score=None, note="the arm's own suite does not pass")
        else:
            planted = []
            for path, lines in sorted(changed_lines(w, run["base"], code_dir).items()):
                src = open(os.path.join(w, path)).read()
                planted += [(path, d, s) for d, s in mutants_of(src, lines)]
            if len(planted) > cap:
                step = len(planted) / cap
                planted = [planted[int(i * step)] for i in range(cap)]
            caught, survivors = 0, []
            for path, desc, src in planted:
                full = os.path.join(w, path)
                orig = open(full).read()
                open(full, "w").write(src)
                if suite_passes(w, suite_dir):
                    survivors.append(f"{path} {desc}")
                else:
                    caught += 1
                open(full, "w").write(orig)
            result.update(planted=len(planted), caught=caught,
                          score=round(caught / len(planted), 3) if planted else None, survivors=survivors)
        with open(os.path.join(run_dir, "mutation.json"), "w") as f:
            json.dump(result, f, indent=2)
            f.write("\n")
        print(json.dumps({k: v for k, v in result.items() if k != "survivors"}))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
