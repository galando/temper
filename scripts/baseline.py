#!/usr/bin/env python3
"""baseline.py: the environment check, the baseline and the limits (9.8.5, WP20).

  python3 baseline.py ROOT CONFIG SPEC start [--again] [--env-only]   `temper baseline start`: always exits 0
  python3 baseline.py ROOT CONFIG SPEC clean                         `temper baseline clean`: the worktree goes
  python3 baseline.py ROOT CONFIG SPEC accept-red --reason R         `temper baseline accept-red`: the person's answer
  python3 baseline.py ROOT CONFIG SPEC limit CMD DEFAULT             the limit of a command (limit_for), printed
  python3 baseline.py ROOT CONFIG SPEC timeout CMD LIMIT             a time out of a command: twice its limit is kept
  python3 baseline.py ROOT CONFIG SPEC skip-row LEDGER               the row `tests pass` as a recorded skip, or nothing
  python3 baseline.py ROOT CONFIG SPEC run STARTED                   the suite's own process (what start starts)

A fault of the environment or of the base is named before any agent is paid for. `start` writes
.temper/evidence/baseline.json and returns in seconds: no commit gives `unknown`; the environment check (doctor.needs:
the tools and services the project's files and the config name, in under 5 s) gives `red` with the kind of its first
fault and runs no suite; no owner of the suite command (check_run.suite_owner) gives `unknown`; else the suite runs in
its own process (TEMPER_BASELINE_FOREGROUND=1 keeps it in this one), in the detached worktree
.claude/worktrees/temper-baseline at HEAD, the place Build uses: `green` on exit 0, `red` on any other exit (its kind
setup-line on 125, program-missing on 127, service-down when a declared service does not answer right after the run,
else red-base), `unknown` on a time out with `seconds_over`, and on exit 5 when the runner found no test to run. The limit is Check's (TEMPER_CHECK_TIMEOUT_S, 1,800 s),
or TEMPER_BASELINE_TIMEOUT_S when it is set.

The file: {"key", "head", "cmd", "run", "source", "result", "kind", "why", "seconds", "seconds_over", "coverage",
"fail_lines", "tail", "env", "notes", "pid", "started", "ended", "answer", "answered", "limits", "plan"}. `key` is the
base tree, the command, the setup block and the tool versions; the person's answer to a red base ("go on anyway") is
kept in the reuse store (temper-results.json in the git common folder) under it, so a later run with the same key asks
nothing and records its own skip. A fix run records a red base of kind red-base with the answer `fix-run`. A green run
is kept there too, with its seconds and coverage. `limit_for(cmd, default)` is the larger of the default and three times
the seconds the same suite took on the base (`seconds_over` counts as measured), and of a doubled limit `timeout` kept.
Standard library only.
"""
import hashlib
import json
import math
import os
import re
import shlex
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import run_env  # noqa: E402

REL = os.path.join(".temper", "evidence", "baseline.json")
WT = os.path.join(".claude", "worktrees", "temper-baseline")
# the suite's limit on the base: Check's (TEMPER_CHECK_TIMEOUT_S, 1,800 s), unless TEMPER_BASELINE_TIMEOUT_S names its own
LIMIT_S = float(os.environ.get("TEMPER_BASELINE_TIMEOUT_S") or os.environ.get("TEMPER_CHECK_TIMEOUT_S") or 1800)
NO_TESTS = re.compile(r"NO TESTS RAN|no tests ran|collected 0 items|^Ran 0 tests", re.M)
FAULT_ORDER = ("setup-line", "program-missing", "tool-version", "service-down")
RUNNERS = {"bash", "sh", "python", "python3", "node", "npx", "npm", "make", "yarn", "pnpm", "bun", "uv", "poetry", "go",
           "cargo", "dotnet", "deno", "ruby", "bundle", "rake", "php", "perl"}
SHELL_WORDS = {"cd", "echo", "true", "false", "export", "test", "[", "exit", "set", "source", ".", "eval", "unset", "printf",
               "exec", "env", "time", "command", ":"}


def now(fine=False):
    t = time.time()
    s = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t))
    return s + (".%06dZ" % int((t % 1) * 1e6) if fine else "Z")


def path(root=None):
    return os.path.join(root or os.getcwd(), REL)


def read(root=None):
    try:
        d = json.load(open(path(root), encoding="utf-8"))
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def write(doc, root=None):
    p = path(root)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = "%s.tmp.%d" % (p, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1)
        f.write("\n")
    os.replace(tmp, p)


def num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def git(root, *args):
    p = subprocess.run(["git", "-C", root] + list(args), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE)
    return p.returncode, p.stdout.decode("utf-8", "replace").strip(), p.stderr.decode("utf-8", "replace").strip()


# ---- the limits -------------------------------------------------------------------------------------------------------
def norm(cmd):
    return " ".join(str(cmd or "").split())


def form(cmd):
    """The suite a command runs, flags left out: each step's folder (cd) and program, and for a runner its first word."""
    out, folder = [], ""
    for seg in re.split(r"&&|\|\||;|\|", cmd or ""):
        toks = [t for t in seg.split() if not re.match(r"^\w+=", t)]
        if not toks:
            continue
        if toks[0] == "cd" and len(toks) > 1:
            folder = toks[1]
            continue
        if toks[0] in SHELL_WORDS:
            continue
        w = [toks[0]] + ([t for t in toks[1:] if not t.startswith("-")][:1] if toks[0] in RUNNERS else [])
        out.append((folder, tuple(w)))
    return tuple(out)


def same_suite(cmd, d):
    """Whether cmd runs the suite the baseline measured: the same text, or the same steps with other flags."""
    mine = [x for x in (d.get("cmd"), d.get("run")) if x]
    return bool(mine) and (norm(cmd) in [norm(x) for x in mine] or (bool(form(cmd)) and form(cmd) in [form(x) for x in mine]))


def alive(d):
    pid = d.get("pid")
    if not isinstance(pid, int):
        return d.get("result") == "running" and time.time() - _ts(d.get("started")) < 60
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def _ts(s):
    try:
        return time.mktime(time.strptime(str(s)[:19], "%Y-%m-%dT%H:%M:%S")) - time.timezone
    except (ValueError, OverflowError):
        return 0.0


def limit_for(cmd, default, root=None):
    """The limit of cmd in seconds: the larger of the site's default and three times the seconds the same suite took on
    the base (`seconds_over` counts as measured), and of the doubled limit a time out kept. A baseline still running is
    waited for, up to its own limit, when it runs that suite: the limit needs the measured time."""
    try:
        base = float(default)
    except (TypeError, ValueError):
        base = 600.0
    d = read(root)
    if not d or not same_suite(cmd, d):
        return int(math.ceil(base))
    t0 = time.time()
    while d.get("result") == "running" and alive(d) and time.time() - t0 < LIMIT_S:
        time.sleep(0.5)
        d = read(root)
    secs = d.get("seconds") if num(d.get("seconds")) else d.get("seconds_over") if num(d.get("seconds_over")) else None
    out = base
    if secs:
        out = max(out, 3 * float(secs))
    kept = (d.get("limits") or {}).get(norm(cmd)) if isinstance(d.get("limits"), dict) else None
    if num(kept):
        out = max(out, float(kept))
    return int(math.ceil(out))


def measured(cmd, root=None):
    """Whether the base measured the time of cmd's suite (a time out of it is then no repeat of the budget)."""
    d = read(root)
    return bool(d and same_suite(cmd, d) and (num(d.get("seconds")) or num(d.get("seconds_over"))))


def timed_out(cmd, limit, root=None):
    """A time out of cmd at limit: twice the limit is kept in `limits`, the next run's limit."""
    d = read(root)
    if not d:
        return
    lim = d.get("limits") if isinstance(d.get("limits"), dict) else {}
    try:
        lim[norm(cmd)] = 2 * int(float(limit))
    except (TypeError, ValueError):
        return
    d["limits"] = lim
    write(d, root)


# ---- the reuse store --------------------------------------------------------------------------------------------------
def store_path(root):
    return run_env._store(root)


def store_get(root, key):
    p = store_path(root)
    try:
        d = json.load(open(p))
        e = d.get("baseline:" + key) if isinstance(d, dict) and key else None
        return e if isinstance(e, dict) else {}
    except (OSError, ValueError):
        return {}


def store_put(root, key, **fields):
    p = store_path(root)
    if not p or not key:
        return
    try:
        d = json.load(open(p))
        d = d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        d = {}
    e = d.get("baseline:" + key) if isinstance(d.get("baseline:" + key), dict) else {}
    e.update(fields)
    e["ts"] = now()
    d["baseline:" + key] = e
    try:
        tmp = "%s.tmp.%d" % (p, os.getpid())
        json.dump(d, open(tmp, "w"))
        os.replace(tmp, p)
    except OSError:
        pass


# ---- start ------------------------------------------------------------------------------------------------------------
def command_of(root):
    try:
        return str(json.load(open(os.path.join(root, ".temper", "build-state.json"))).get("command") or "temper")
    except (OSError, ValueError, AttributeError):
        return "temper"


def owner_of(root, config, spec):
    import check_run
    import config_yaml
    cfg = config_yaml.load(config) if config and os.path.isfile(config) else None
    return check_run.suite_owner(root, cfg, os.path.join(root, spec) if spec and not os.path.isabs(spec) else spec)


def make_key(tree, run, setup, tools):
    return hashlib.sha256(json.dumps([tree, run, setup or {}, tools or {}], sort_keys=True).encode("utf-8")).hexdigest()


def cli(root, *args):
    """The CLI's own call (the override row of a kept answer and of the person's)."""
    p = subprocess.run([os.path.join(HERE, "temper")] + list(args), cwd=root, stdin=subprocess.DEVNULL,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout.decode("utf-8", "replace")


def kept_answer(root, doc):
    """A later run on the same key: the stored answer is this run's too, with its own skip row."""
    if doc.get("result") != "red" or doc.get("answer"):
        return
    a = store_get(root, doc.get("key") or "").get("answer")
    if not isinstance(a, dict) or not a.get("reason"):
        return
    doc["answer"] = "go-on-anyway"
    doc["answered"] = dict(a, kept=True)
    cli(root, "override", "base-suite", "--reason", "%s (your answer of %s on the same base, kept)" % (
        a.get("reason"), str(a.get("ts") or "")[:10]))


def finish(root, doc, started):
    """Write the result, unless a newer start owns the file now."""
    cur = read(root)
    if cur and cur.get("started") != started:
        return
    doc["ended"] = now()
    if doc.get("result") == "red" and doc.get("kind") == "red-base" and command_of(root) == "fix" and not doc.get("answer"):
        doc["answer"] = "fix-run"   # in a fix run the red suite may be the bug: recorded, not asked
    kept_answer(root, doc)
    write(doc, root)


def start(root, config, spec, again=False, env_only=False):
    cur = read(root)
    if cur.get("result") == "running" and alive(cur):
        if not again:
            print("OK: the baseline is running already (started %s)" % cur.get("started"))
            return 0
        stop_running(cur)
    started = now(fine=True)
    doc = {"started": started, "result": "unknown", "why": "the environment check is running", "env": [], "limits": {},
           "plan": {}}
    write(doc, root)   # this start owns the file from now on: an older run of the suite that ends later writes nothing
    rc, head, _ = git(root, "rev-parse", "--verify", "-q", "HEAD")
    if rc != 0 or not head:
        doc["why"] = "no commit: the baseline runs on the current commit, and there is none"
        write(doc, root)
        print("OK: baseline unknown: %s" % doc["why"])
        return 0
    doc["head"] = head
    setup = run_env.load_setup(config) if config and os.path.isfile(config) else {}
    own = owner_of(root, config, spec)
    doc.update(cmd=own["test"], run=own["run"], source=own["source"])
    import doctor
    faults, notes, tools = doctor.needs(root, setup, [x for x in (own["test"], own["run"]) if x])
    doc.update(env=faults, notes=notes)
    _, tree, _ = git(root, "rev-parse", "HEAD^{tree}")
    doc["key"] = make_key(tree, own["run"], setup, tools)
    if faults:
        faults.sort(key=lambda f: FAULT_ORDER.index(f["kind"]) if f["kind"] in FAULT_ORDER else 9)
        doc.update(result="red", kind=faults[0]["kind"], why="; ".join(f["why"] for f in faults))
        finish(root, doc, started)
        print("OK: baseline red before any suite run: %s" % doc["why"])
        return 0
    if env_only:
        kept = store_get(root, doc["key"])
        if kept.get("result") == "green":
            doc.update(result="green", seconds=kept.get("seconds"), coverage=kept.get("coverage"), reused=kept.get("ts"),
                       why="a door: the environment was checked; the store holds a green run of this base of %s" % kept.get("ts"))
        else:
            doc["why"] = "a door into a later stage: only the environment was checked, no suite ran on the base"
        doc["env_only"] = True
        finish(root, doc, started)
        print("OK: baseline (the environment check only): %s" % doc["result"])
        return 0
    if not own["run"]:
        doc["why"] = own["why"]
        finish(root, doc, started)
        print("OK: baseline unknown: %s" % doc["why"])
        return 0
    doc["result"] = "running"
    write(doc, root)
    if os.environ.get("TEMPER_BASELINE_FOREGROUND"):
        run(root, config, spec, started)
        print("OK: baseline %s" % read(root).get("result"))
        return 0
    # trap 2: the suite runs in its own process, which holds none of this call's pipes, so the call returns at once
    subprocess.Popen([sys.executable, "-E", "-s", os.path.abspath(__file__), root, config or "", spec or "", "run", started],
                     cwd=root, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    print("OK: baseline running in its own process (%s)" % own["run"][:120])
    return 0


def worktree(root):
    """The detached worktree at HEAD (made again), and the project's folder in it; ("", why) when it cannot be made."""
    wt = os.path.join(root, WT)
    if os.path.exists(wt) or os.path.lexists(wt):
        git(root, "worktree", "remove", "--force", wt)
    git(root, "worktree", "prune")
    rc, out, err = git(root, "worktree", "add", "--detach", "-q", wt, "HEAD")
    if rc != 0:
        return "", "the worktree %s could not be made: %s" % (WT, (err or out)[:200])
    _, common, _ = git(root, "rev-parse", "--git-common-dir")
    _, pre, _ = git(root, "rev-parse", "--show-prefix")
    ex = os.path.join(common if os.path.isabs(common) else os.path.join(root, common), "info", "exclude")
    line = "/%s.claude/worktrees/" % pre
    try:
        os.makedirs(os.path.dirname(ex), exist_ok=True)
        if line not in open(ex).read().splitlines() if os.path.exists(ex) else True:
            open(ex, "a").write(line + "\n")
    except OSError:
        pass
    return os.path.join(wt, pre).rstrip("/"), ""


def picked(out, rc):
    """The lines that say what failed, picked by pattern (task_ops.fail_lines without its fallback to the last lines)."""
    lines = run_env.fail_lines(out if isinstance(out, bytes) else str(out).encode(), 8, rc)
    pats = (run_env.FAIL_LINE,) + tuple(run_env.SUMMARY)
    return [x for x in lines if x.startswith("the command did not finish") or any(p.search(x) for p in pats)]


def run(root, config, spec, started):
    cur = read(root)
    if cur.get("started") != started:
        return 0
    doc = dict(cur, pid=os.getpid())
    write(doc, root)
    try:
        _run(root, config, spec, started, doc)
    except Exception as e:   # the file always says something: a baseline never fails a run
        doc.update(result="unknown", why="the baseline could not run: %s" % str(e)[:200])
        finish(root, doc, started)
    return 0


def _run(root, config, spec, started, doc):
    import check_run
    setup = run_env.load_setup(config) if config and os.path.isfile(config) else {}
    own = owner_of(root, config, spec)
    folder, why = worktree(root)
    if not folder:
        doc.update(result="unknown", why=why)
        return finish(root, doc, started)
    det = own.get("det") or {}

    def measure(out):
        c = det.get("coverage") or {}
        extra = b""
        if c.get("report"):
            extra, _ = run_env.run_cmd(folder, 300, [c["report"]], setup)
        return check_run.coverage_value(folder, det, (out + b"\n" + extra).decode("utf-8", "replace"))
    info = {"measure": measure}
    out, rc, reused = run_env.run_cached(folder, LIMIT_S, [own["run"]], setup, info)
    doc["tail"] = check_run.strip_banner(out[-2048:].decode("utf-8", "replace"))
    if reused:
        doc["reused"] = reused
    if rc == 124:
        doc.update(result="unknown", seconds_over=int(LIMIT_S), why="the suite ran over its limit of %d s" % int(LIMIT_S))
        return finish(root, doc, started)
    doc["seconds"] = info.get("seconds")
    if rc == 0:
        doc.update(result="green", coverage=info.get("coverage"), why="")
        store_put(root, doc.get("key"), result="green", seconds=doc["seconds"], coverage=doc["coverage"])
        return finish(root, doc, started)
    if rc == 5 and NO_TESTS.search(doc["tail"]):
        # unittest and pytest exit 5 when they find no test: nothing failed, and nothing was measured either
        doc.update(result="unknown", exit_code=rc, why="the suite found no test to run on the current code (exit 5)")
        return finish(root, doc, started)
    kind = {125: "setup-line", 127: "program-missing"}.get(rc, "")
    if not kind:
        import doctor
        down = [n for n, a in (setup.get("services") or {}).items() if not doctor.answers(a)]
        kind = "service-down" if down else "red-base"
        if down:
            doc["env"] = [{"kind": "service-down", "file": os.path.join(".claude", "temper.config"), "need": n,
                           "have": "no answer", "why": "the service %s does not answer after the run" % n} for n in down]
    doc.update(result="red", kind=kind, exit_code=rc, fail_lines=picked(out, rc),
               why="%s exited %d on the current code" % (own["run"][:200], rc))
    return finish(root, doc, started)


def stop_running(d):
    pid = d.get("pid")
    if isinstance(pid, int) and pid != os.getpid():
        try:
            os.killpg(pid, signal.SIGTERM)
        except OSError:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass


def clean(root):
    d = read(root)
    if d.get("result") == "running":
        stop_running(d)
    wt = os.path.join(root, WT)
    if os.path.lexists(wt) and not os.path.isdir(wt):
        return 0
    if os.path.isdir(wt):
        git(root, "worktree", "remove", "--force", wt)
        if os.path.isdir(wt):
            import shutil
            shutil.rmtree(wt, ignore_errors=True)
    git(root, "worktree", "prune")
    print("OK: the baseline's worktree is gone")
    return 0


def accept_red(root, reason):
    reason = " ".join(str(reason or "").split())
    d = read(root)
    if not reason:
        print("FAIL: usage: temper baseline accept-red --reason '<why>'", file=sys.stderr)
        return 1
    if d.get("result") != "red":
        print("FAIL: the base is not red (%s); there is nothing to go on from" % (d.get("result") or "no baseline"), file=sys.stderr)
        return 1
    a = {"by": "the person", "reason": reason, "ts": now()}
    d.update(answer="go-on-anyway", answered=a)
    write(d, root)
    store_put(root, d.get("key") or "", answer=a)
    rc, out = cli(root, "override", "base-suite", "--reason", reason)
    sys.stdout.write(out)
    return rc


# ---- the recorded skip: the row `tests pass` of a red base the person went on from ----------------------------------
def mask(line):
    return re.sub(r"\d+", "#", " ".join(str(line).split()))


def skip_row(root, ledger, config=""):
    """The row `tests pass` with the state skipped (WP19's third state), as one JSON line, when every failed test run of
    the ledger runs the base's suite and shows only the base's fail lines (all of them, when the base showed none); else
    nothing: the row fails as before. Only after the person went on anyway, in this run."""
    d = read(root)
    if d.get("answer") != "go-on-anyway":
        return ""
    try:
        ov = json.load(open(os.path.join(root, ".temper", "overrides.json")))
    except (OSError, ValueError):
        ov = []
    if not any(isinstance(x, dict) and x.get("stage") == "base-suite" for x in (ov if isinstance(ov, list) else [])):
        return ""
    try:
        rows = json.load(open(ledger))
        rows = rows if isinstance(rows, list) else []
    except (OSError, ValueError):
        return ""
    import runs
    last = {}
    for r in rows:
        if (isinstance(r, dict) and runs.counts(r, "ignore") and not r.get("scenario") and isinstance(r.get("exit_code"), int)
                and runs.is_test(r) and not str(r.get("claim") or "").startswith("acceptance (written before Build)")):
            last[" ".join(str(r.get("claim")).lower().split())] = r
    red = [r for r in last.values() if r.get("exit_code") != 0]
    if not red:
        return ""
    base = {mask(x) for x in d.get("fail_lines") or []}
    ref = d
    if not (d.get("cmd") or d.get("run")):   # a file that names no command: the suite's owner now is the base's
        own = owner_of(root, config, "")
        ref = {"cmd": own["test"], "run": own["run"]}
    now_lines = []
    for r in red:
        if not same_suite(r.get("cmd") or "", ref):
            return ""
        got = picked(str(r.get("output") or "").encode(), r.get("exit_code"))
        if base and (not got or any(mask(x) not in base for x in got)):
            return ""
        now_lines += got
    why = (d.get("answered") or {}).get("reason") or ""
    if base:
        detail = ("skipped: the same failures as on the base, which you went on from (%s): before %s; after %s"
                  % (why, "; ".join(d.get("fail_lines")[:4]), "; ".join(dict.fromkeys(now_lines))[:400]))
    else:
        detail = ("skipped: the base failed with no line that names a test, so the whole suite is information for this "
                  "run (%s)" % why)
    return json.dumps({"name": "tests pass", "pass": None, "state": "skipped", "detail": detail[:900]})


def main(argv):
    if len(argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    root, config, spec, sub, rest = os.path.abspath(argv[1]), argv[2], argv[3], argv[4], argv[5:]
    if config and not os.path.isabs(config):
        config = os.path.join(root, config)
    if sub == "start":
        try:
            return start(root, config, spec, "--again" in rest, "--env-only" in rest)
        except Exception as e:   # trap 2: start never fails a run, and its file is always there after it
            try:
                write({"result": "unknown", "why": "the baseline could not start: %s" % str(e)[:200], "started": now(),
                       "env": [], "limits": {}, "plan": {}}, root)
            except OSError:
                pass
            print("OK: baseline unknown: %s" % str(e)[:200])
            return 0
    if sub == "run" and rest:
        return run(root, config, spec, rest[0])
    if sub == "clean":
        return clean(root)
    if sub == "accept-red":
        reason = rest[rest.index("--reason") + 1] if "--reason" in rest and rest.index("--reason") + 1 < len(rest) else ""
        return accept_red(root, reason)
    if sub == "limit" and len(rest) == 2:
        print(limit_for(rest[0], rest[1], root))
        return 0
    if sub == "timeout" and len(rest) == 2:
        timed_out(rest[0], rest[1], root)
        return 0
    if sub == "skip-row" and rest:
        r = skip_row(root, rest[0], config)
        if r:
            print(r)
        return 0
    print("FAIL: usage: temper baseline start [--again] [--env-only] | clean | accept-red --reason '<why>'", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
