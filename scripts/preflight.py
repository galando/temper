"""preflight.py: the plan gate's "preflight" row: every command of the plan, run once on the clean base (HEAD).

  python3 preflight.py row SPEC PROJECT CONFIG LEDGER    prints the row as JSON

Each distinct Validate, task Test, Integration and scenario Test command runs in a detached worktree of HEAD (a Maven task
Test through maven_loop, as Build runs it), which is removed after. A command is sorted into one class: passes, environment
fault, command fault or needs new code (the tests of new code fail on the base). Only the two faults fail the row.
plan.preflight-timeout (default 300 s) limits each command; plan.preflight-skip "<reason>" skips the run, once in the ledger.
Standard library only.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

import acceptance
import config_yaml
import maven_loop
import run_env
import tasks_md

DEFAULT_TIMEOUT = 300
PLACEHOLDER = re.compile(r"^\{\S[^{}]*\}$")   # a template's unfilled `{full suite command}` is no command
CLASSES = ("passes", "needs new code", "environment fault", "command fault")
ENV_PATTERNS = (r"Unsupported class file major version", r"release version \d+ not supported", r"invalid target release",
                r"Connection refused", r"could not connect to server")
CMD_PATTERNS = (r"Rule violated for bundle", r"Coverage checks have not been met", r"Unknown lifecycle phase",
                r"Unrecognized option", r"unrecognized arguments")


def row(ok, detail):
    return {"name": "preflight", "pass": ok, "detail": detail}


def commands(spec):
    """[(command, maven task files or None)] distinct, in plan order."""
    plan = tasks_md.parse(os.path.join(spec, "tasks.md"))
    found = [(g["validate"], None) for g in plan["groups"]]
    found += [(t["test"], t["files"]) for t in plan["tasks"] if not t["manual"]]
    found.append((plan.get("integration") or "", None))
    try:
        lines = open(os.path.join(spec, "intent.md"), encoding="utf-8").read().splitlines()
        found += [(b["cmd"], None) for b in acceptance.scenario_blocks(lines)]
    except OSError:
        pass
    seen, out = set(), []
    for cmd, files in found:
        cmd = (cmd or "").strip()
        if cmd and cmd != "manual" and not PLACEHOLDER.match(cmd) and cmd not in seen:
            seen.add(cmd)
            out.append((cmd, files))
    return out, sorted({f for t in plan["tasks"] for f in t["files"]})


def programs(cmd):
    out = set()
    for seg in re.split(r"&&|\|\||;|\|", cmd):
        toks = [t for t in seg.split() if not re.match(r"^\w+=", t)]
        if toks:
            out.add(toks[0])
    return out


def classify(cmd, out, rc, limit, declared, wt):
    """(class, reason) for one run."""
    if rc == 0:
        return "passes", ""
    if "temper-setup: FAIL" in out:
        return "environment fault", "the setup block failed"
    if rc == 124:
        return "environment fault", "time limit %s s" % limit
    m = re.search(r"^.*which is not in the allowed range (\S+?)\.?\s*$", out, re.M)
    if m:
        v = re.search(r"version (\d[\w.+-]*)", m.group(0))
        return "environment fault", "needs JDK %s (found %s)" % (m.group(1), v.group(1) if v else "unknown")
    for pat in ENV_PATTERNS:
        if re.search(pat, out):
            return "environment fault", re.search(pat, out).group(0)
    if rc == 127:
        for name in re.findall(r"([^\s:]+): command not found", out):
            if name in programs(cmd):
                return "environment fault", "%s: command not found" % name
    if "in offline mode" in out and "Cannot access" in out:
        return "environment fault", "a dependency is not cached (offline mode)"
    for pat in CMD_PATTERNS:
        if re.search(pat, out):
            return "command fault", re.search(pat, out).group(0)
    if re.search(r"Tests run: \d+, Failures: 0, Errors: 0[\s\S]*BUILD FAILURE", out):
        return "command fault", "the tests pass and the build fails"
    for f in declared:
        stem = os.path.splitext(os.path.basename(f))[0]
        if not os.path.exists(os.path.join(wt, f)) and (f in cmd or f in out or (len(stem) >= 4 and (stem in cmd or stem in out))):
            return "needs new code", "%s is not on the base" % f
    return "needs new code", ""


def quote(out):
    lines = out.splitlines()
    keep = lines[-20:] + [l for l in lines[:-20] if "Failed to execute goal" in l or "Rule violated" in l]
    return "\n".join("    " + l[:240] for l in keep)


def git(project, *args):
    return subprocess.run(("git", "-C", project) + args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def note_skip(ledger, reason):
    claim = "preflight skipped: " + reason
    try:
        data = json.load(open(ledger, encoding="utf-8"))
    except (OSError, ValueError):
        data = []
    if any(isinstance(e, dict) and e.get("claim") == claim for e in data):
        return
    data.append({"claim": claim, "cmd": None, "exit_code": None, "artifact": None, "sha256": None, "value": None,
                 "severity": None, "phase": None, "scenario": None, "criterion": None, "label": "HEURISTIC",
                 "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
    os.makedirs(os.path.dirname(os.path.abspath(ledger)), exist_ok=True)
    json.dump(data, open(ledger, "w", encoding="utf-8"), indent=2)


def make_row(spec, project, config, ledger):
    cfg = config_yaml.load(config)
    skip = config_yaml.get(cfg, "plan.preflight-skip", "")
    if skip != "":
        if not isinstance(skip, str) or skip in ("true", "false"):
            return row(False, "plan.preflight-skip needs a reason text (plan.preflight-skip: \"the suite takes 40 minutes\")")
        note_skip(ledger, skip)
        return row(True, "skipped by the person: " + skip)
    if git(project, "rev-parse", "--verify", "-q", "HEAD").returncode != 0:
        return row(True, "skipped: no commit to run on")
    try:
        limit = int(config_yaml.get(cfg, "plan.preflight-timeout", DEFAULT_TIMEOUT))
    except (TypeError, ValueError):
        limit = DEFAULT_TIMEOUT
    cmds, declared = commands(spec)
    tmp = tempfile.mkdtemp(prefix="temper-preflight-")
    wt = os.path.join(tmp, "base")
    if git(project, "worktree", "add", "--detach", wt, "HEAD").returncode != 0:
        shutil.rmtree(tmp, ignore_errors=True)
        return row(True, "skipped: no commit to run on")
    results = []
    try:
        for cmd, files in cmds:
            if files is not None and maven_loop.is_maven(cmd):
                raw, rc = maven_loop.run(wt, limit, cmd, files)
            else:
                raw, rc = run_env.run_cmd(wt, limit, [cmd])
            out = raw.decode("utf-8", "replace")
            cls, why = classify(cmd, out, rc, limit, declared, wt)
            results.append((cmd, cls, why, out))
    finally:
        git(project, "worktree", "remove", "--force", wt)
        git(project, "worktree", "prune")
        shutil.rmtree(tmp, ignore_errors=True)
    counts = ["%d %s" % (n, c) for c in CLASSES for n in [sum(1 for r in results if r[1] == c)] if n]
    lines = ["%d command(s): %s" % (len(results), ", ".join(counts))]
    for cmd, cls, why, out in results:
        if cls != "passes":
            lines.append("%s `%s`%s" % (cls, cmd[:120], ": " + why if why else ""))
            if cls != "needs new code":
                lines.append(quote(out))
    return row(not any(r[1] in ("environment fault", "command fault") for r in results), "\n".join(lines))


def main(argv):
    if len(argv) == 6 and argv[1] == "row":
        print(json.dumps(make_row(*argv[2:])))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
