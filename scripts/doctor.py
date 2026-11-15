"""doctor.py: `temper doctor`, what the environment of this project looks like. It only reads.

  python3 doctor.py PROJECT CONFIG

Prints three parts: the toolchain (the first line of each tool's version, or "not on PATH"), the setup block of
.claude/temper.config (its run line is shown, never run: it may start a service), and whether each service the block
names answers a TCP connect. It writes no file, no ledger, no state and no view. A variable whose name says it holds a
credential is never shown. Standard library only.
"""
import os
import shutil
import socket
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_env  # noqa: E402

DEFAULT_TOOLS = ("java", "mvn", "python3", "node", "git")
TOOL_LIMIT_S = 10
SERVICE_LIMIT_S = 2


def version(tool, cwd):
    if not shutil.which(tool):
        return "not on PATH"
    flag = "-version" if os.path.basename(tool) == "java" else "--version"
    try:
        p = subprocess.run([tool, flag], cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=TOOL_LIMIT_S)
    except subprocess.TimeoutExpired:
        return "no answer within %d s" % TOOL_LIMIT_S
    except OSError as e:
        return "could not start (%s)" % e
    lines = [l.strip() for l in p.stdout.decode("utf-8", "replace").splitlines() if l.strip()]
    return lines[0][:200] if lines else "(no version printed, exit %d)" % p.returncode


def answers(addr):
    host, _, port = addr.rpartition(":")
    try:
        with socket.create_connection((host or "127.0.0.1", int(port)), timeout=SERVICE_LIMIT_S):
            return True
    except (OSError, ValueError):
        return False


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    project, config = argv[1], argv[2]
    setup = run_env.load_setup(config)
    print("Toolchain:")
    for tool in setup.get("tools") or DEFAULT_TOOLS:
        print("  %s: %s" % (tool, version(tool, project)))
    if not setup:
        print("Setup block: none")
    else:
        print("Setup block:")
        if setup["run"]:
            print("  run: %s (not run by doctor: it may start a service)" % run_env.mask(setup["run"]))
        for k, v in setup["env"].items():
            print("  %s=%s" % (k, v))
        for k in setup["dropped"]:
            print("  left out (credential name): %s" % k)
    services = setup.get("services") or {}
    print("Services:" + ("" if services else " none named"))
    for name, addr in services.items():
        print("  %s %s: %s" % (name, addr, "answering" if answers(addr) else "not answering"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
