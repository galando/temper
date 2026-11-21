#!/usr/bin/env python3
"""check-names.py: no script reads a name it does not define.

    python3 -I scripts/selftest/check-names.py [FILE...]

With no FILE it checks every tracked scripts/*.py of the plugin folder it sits in (git ls-files). It imports
nothing it checks: the standard symtable module reads each file's scopes. A name a scope reads as a global must be
bound at module level (assigned, imported, a function or a class, or assigned in a function under a global
statement) or be a builtin. A star import fails the file, since no reader can tell which names it binds.
Prints one line per unknown name and exits 1, or prints ok and exits 0. A file that does not parse fails too.
"""
import ast
import builtins
import os
import subprocess
import symtable
import sys

MODULE_NAMES = {"__file__", "__name__", "__doc__", "__spec__", "__loader__", "__package__", "__builtins__",
                "__annotations__", "__path__", "__cached__", "__dict__", "__module__", "__qualname__", "__class__"}
KNOWN = set(dir(builtins)) | MODULE_NAMES


def scopes(table):
    yield table
    for child in table.get_children():
        yield from scopes(child)


def bound_at_module(top):
    names = set()
    for sym in top.get_symbols():
        if sym.is_assigned() or sym.is_imported() or sym.is_namespace() or sym.is_parameter():
            names.add(sym.get_name())
    for table in scopes(top):
        if table is top:
            continue
        for sym in table.get_symbols():
            if sym.is_declared_global() and (sym.is_assigned() or sym.is_imported() or sym.is_namespace()):
                names.add(sym.get_name())
    return names


def check(path, display):
    try:
        with open(path, encoding="utf-8") as f:
            src = f.read()
        tree = ast.parse(src, display)
        top = symtable.symtable(src, display, "exec")
    except (OSError, SyntaxError, ValueError) as e:
        return ["%s: does not parse: %s" % (display, e)]
    bad = []
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and any(a.name == "*" for a in node.names):
            bad.append("%s:%d: a star import (from %s import *)" % (display, node.lineno, node.module or "."))
    bound = bound_at_module(top)
    seen = set()
    for table in scopes(top):
        for sym in table.get_symbols():
            name = sym.get_name()
            if not sym.is_referenced() or name in bound or name in KNOWN:
                continue
            reads_global = sym.is_global() if table is not top else not (sym.is_assigned() or sym.is_imported())
            if reads_global and name not in seen:
                seen.add(name)
                bad.append("%s: %s reads %s, which the module never binds" % (display, table.get_name(), name))
    return bad


def tracked(root):
    out = subprocess.run(["git", "-C", root, "ls-files", "-z", "--", "scripts/*.py"],
                         capture_output=True, check=False).stdout.decode("utf-8", "replace")
    return [p for p in out.split("\0") if p]


def main(argv):
    here = os.path.dirname(os.path.realpath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    files = [(p, p) for p in argv] if argv else [(os.path.join(root, p), p) for p in tracked(root)]
    if not files:
        print("FAIL: no Python script to check (is %s a git work tree?)" % root)
        return 1
    bad = []
    for path, display in files:
        bad.extend(check(path, display))
    if bad:
        print("\n".join(bad))
        print("FAIL: %d unknown name(s) in %d file(s) checked" % (len(bad), len(files)))
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
