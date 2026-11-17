"""preflight.py: the plan gate's "preflight" row: the Validates and the Integration line of the plan, run once on HEAD.

  python3 preflight.py row SPEC PROJECT CONFIG LEDGER    prints the row as JSON (a stored result while it is current)
  python3 preflight.py run SPEC PROJECT CONFIG LEDGER    runs the commands again and stores the result (temper plan preflight)

Each distinct Validate and Integration command runs in a detached worktree of HEAD, which is removed after. No task
Test and no scenario Test runs: they need code that is not written yet (WP08, F4). A command is sorted into one class:
passes, environment fault, command fault, needs new code or not checked. Only the two faults fail the row.
plan.preflight-timeout (default 300 s) is one limit for the whole row: each command gets what is left of it, and a
command over it is not checked (a time out is no environment fault, WP08 M15): the row passes and names the three ways
on.
plan.preflight-skip "<reason>" skips the run, once in the ledger.
The result is stored in .temper/preflight.json with a key made of HEAD, the command texts, the setup block and the time
limit; the gate reads a stored pass while that key is unchanged, and a stored failure runs again (WP08 M16).
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

import hashlib

import config_yaml
import maven_loop
import run_env
import tasks_md

DEFAULT_TIMEOUT = 300
PLACEHOLDER = re.compile(r"^\{\S[^{}]*\}$")   # a template's unfilled `{full suite command}` is no command
CLASSES = ("passes", "needs new code", "not checked", "environment fault", "command fault")
WAYS_ON = ("    ways on: a longer plan.preflight-timeout, another command (temper plan patch), "
           "or a skip with a reason (plan.preflight-skip)")
ENV_PATTERNS = (r"Unsupported class file major version", r"release version \d+ not supported", r"invalid target release",
                r"Connection refused", r"could not connect to server")
CMD_PATTERNS = (r"Rule violated for bundle", r"Coverage checks have not been met", r"Unknown lifecycle phase",
                r"Unrecognized option", r"unrecognized arguments")


def row(ok, detail):
    return {"name": "preflight", "pass": ok, "detail": detail}


def commands(spec):
    """[(command, None)] distinct, in plan order: each group's Validate and the Integration line. A task Test and a
    scenario Test need code that is not written yet, so neither runs here (WP08, F4)."""
    plan = tasks_md.parse(os.path.join(spec, "tasks.md"))
    found = [(g["validate"], None) for g in plan["groups"]]
    found.append((plan.get("integration") or "", None))
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


def env_fault(out, rc, cmd, limit=None, timeout_is_env=True):
    """The reason a failed run is an environment fault, or "". timeout_is_env=False (the task gate): a time-out is the code's."""
    if rc == 0:
        return ""
    if "temper-setup: FAIL" in out:
        m = re.search(r"temper-setup: FAIL \(exit \d+\)", out)
        return "the setup block failed (%s)" % (m.group(0) if m else "temper-setup: FAIL")
    if rc == 124 and timeout_is_env:
        return "time limit %s s" % limit if limit is not None else "time limit"
    m = re.search(r"^.*which is not in the allowed range (\S+?)\.?\s*$", out, re.M)
    if m:
        v = re.search(r"version (\d[\w.+-]*)", m.group(0))
        return "needs JDK %s (found %s)" % (m.group(1), v.group(1) if v else "unknown")
    for pat in ENV_PATTERNS:
        hit = re.search(pat, out)
        if hit:
            return hit.group(0)
    if rc == 127:
        for name in re.findall(r"([^\s:]+): command not found", out):
            if name in programs(cmd):
                return "%s: command not found" % name
    if "in offline mode" in out and "Cannot access" in out:
        return "a dependency is not cached (offline mode)"
    return ""


def classify(cmd, out, rc, limit, declared, wt, spent=False):
    """(class, reason) for one run. A time out is not checked, never an environment fault (WP08, M15): over the limit,
    or (spent) over what the earlier commands left of the one total limit."""
    if rc == 0:
        return "passes", ""
    if rc == 124:
        return "not checked", ("the total limit of %s s was spent" if spent else "over %s s") % limit
    why = env_fault(out, rc, cmd, limit)
    if why:
        return "environment fault", why
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


def store_key(project, cmds, limit, config):
    head = git(project, "rev-parse", "HEAD").stdout.decode("utf-8", "replace").strip()
    setup = json.dumps(run_env.load_setup(config), sort_keys=True)
    text = json.dumps([head, [c for c, _ in cmds], setup, limit])   # the spec's commands are part of the key
    return hashlib.sha256(text.encode("utf-8")).hexdigest(), head


def make_row(spec, project, config, ledger, fresh=False):
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
    key, head = store_key(project, cmds, limit, config)
    store = os.path.join(project, ".temper", "preflight.json")   # run state, beside gates.json
    if not fresh:
        try:
            kept = json.load(open(store, encoding="utf-8"))
            if kept.get("key") == key and kept["row"].get("pass") is True:   # a stored failure runs again (WP08, M16)
                return kept["row"]
        except (OSError, ValueError, KeyError, AttributeError):
            pass
    runs = run_classes(project, cmds, declared, limit, run_env.load_setup(config))
    result = format_row(runs)
    faults = [{"cmd": c, "files": f, "why": w} for c, f, cls, w, _ in (runs or []) if cls == "environment fault"]
    try:
        json.dump({"key": key, "head": head, "row": result, "env_faults": faults, "limit": limit},
                  open(store, "w", encoding="utf-8"), indent=2)
    except OSError:
        pass
    return result


def run_all(project, cmds, declared, limit, setup):
    return format_row(run_classes(project, cmds, declared, limit, setup))


def run_classes(project, cmds, declared, limit, setup):
    """[(cmd, files, class, why, output)] of each command on a throwaway worktree of HEAD, or None with no commit.
    limit is one total: each command gets what the earlier ones left of it, and one that finds none left does not
    run."""
    tmp = tempfile.mkdtemp(prefix="temper-preflight-")
    wt = os.path.join(tmp, "base")
    if git(project, "worktree", "add", "--detach", wt, "HEAD").returncode != 0:
        shutil.rmtree(tmp, ignore_errors=True)
        return None
    results, used = [], 0.0
    try:
        for cmd, files in cmds:
            left = limit - used
            if left <= 0:
                results.append((cmd, files, "not checked", "the total limit of %s s was spent" % limit, ""))
                continue
            start = time.monotonic()
            if files is not None and maven_loop.is_maven(cmd):
                raw, rc = maven_loop.run(wt, left, cmd, files, setup)
            else:
                raw, rc = run_env.run_cmd(wt, left, [cmd], setup)
            used += time.monotonic() - start
            out = raw.decode("utf-8", "replace")
            cls, why = classify(cmd, out, rc, limit, declared, wt, spent=left < limit)
            results.append((cmd, files, cls, why, out))
    finally:
        git(project, "worktree", "remove", "--force", wt)
        git(project, "worktree", "prune")
        shutil.rmtree(tmp, ignore_errors=True)
    return results


def format_row(runs):
    if runs is None:
        return row(True, "skipped: no commit to run on")
    results = [(c, cls, w, o) for c, _, cls, w, o in runs]
    counts = ["%d %s" % (n, c) for c in CLASSES for n in [sum(1 for r in results if r[1] == c)] if n]
    lines = ["%d command(s): %s" % (len(results), ", ".join(counts))]
    for cmd, cls, why, out in results:
        if cls == "not checked":
            lines.append("not checked: %s `%s`" % (why, cmd[:120]))
            lines.append(WAYS_ON)
        elif cls != "passes":
            lines.append("%s `%s`%s" % (cls, cmd[:120], ": " + why if why else ""))
            if cls != "needs new code":
                lines.append(quote(out))
    return row(not any(r[1] in ("environment fault", "command fault") for r in results), "\n".join(lines))


def verify(project, setup):
    """9.8.5: does a candidate setup block fix the environment faults of the stored preflight? (ok, lines): each command
    that failed on the environment runs again, on a throwaway worktree of HEAD, under the candidate. ok when none of them
    is an environment fault any more (a pass, or needs new code). No stored fault: nothing to check against."""
    try:
        kept = json.load(open(os.path.join(project, ".temper", "preflight.json"), encoding="utf-8"))
    except (OSError, ValueError):
        kept = {}
    faults = kept.get("env_faults") or []
    if not faults:
        return False, ["no environment fault is stored to check against: run the plan gate (or temper plan preflight) first"]
    runs = run_classes(project, [(f["cmd"], f.get("files")) for f in faults], [], int(kept.get("limit") or DEFAULT_TIMEOUT), setup)
    if runs is None:
        return False, ["no commit to run on"]
    lines = ["%s `%s`: was environment fault (%s), now %s%s" % ("ok" if cls != "environment fault" else "still failing", c[:120],
             f.get("why", ""), cls, (": " + w) if w else "") for (c, _, cls, w, _), f in zip(runs, faults)]
    return all(cls != "environment fault" for _, _, cls, _, _ in runs), lines


def main(argv):
    if len(argv) == 6 and argv[1] in ("row", "run"):
        print(json.dumps(make_row(*argv[2:], fresh=argv[1] == "run")))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
