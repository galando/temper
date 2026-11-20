#!/usr/bin/env python3
"""baseline.py: the environment check, the baseline and the limits (9.8.5, WP20).

  python3 baseline.py ROOT CONFIG SPEC start [--again] [--env-only]   `temper baseline start`: always exits 0
  python3 baseline.py ROOT CONFIG SPEC clean                         `temper baseline clean`: the worktree goes
  python3 baseline.py ROOT CONFIG SPEC accept-red --reason R         `temper baseline accept-red`: the person's answer
  python3 baseline.py ROOT CONFIG SPEC limit CMD DEFAULT             the limit of a command (limit_for), printed
  python3 baseline.py ROOT CONFIG SPEC timeout CMD LIMIT             a time out of a command: twice its limit is kept
  python3 baseline.py ROOT CONFIG SPEC skip-row LEDGER               the row `tests pass` as a recorded skip, or nothing
  python3 baseline.py ROOT CONFIG SPEC run STARTED                   the suite's own process (what start starts)
  python3 baseline.py ROOT CONFIG SPEC plan [--cmd C]                `temper baseline plan`: always exits 0 (WP21)
  python3 baseline.py ROOT CONFIG SPEC skip --cmd C --reason R       `temper baseline skip`: the person's answer
  python3 baseline.py ROOT CONFIG SPEC wait CMD                      waits while the plan's command CMD runs
  python3 baseline.py ROOT CONFIG SPEC like-base CMD LINES_JSON      exit 0: a failed gate run of CMD fails as on the base

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
the seconds the same suite took on the base (`seconds_over` counts as measured), and of a limit kept in `limits` (a
doubled limit `timeout` kept, or the person's more time).

WP21, the plan's commands: `plan` runs each group's Validate and the Integration line of tasks.md once on the current
code, in the same worktree, after the suite (it waits for a suite still running), one after another in a process of its
own (or in the foreground with TEMPER_BASELINE_FOREGROUND), each under Build's limit for it (limit_for of the group
gate's default, TEMPER_TASK_TEST_TIMEOUT_S or 600 s, and of integrate's, TEMPER_INTEGRATION_TIMEOUT_S or 3,600 s). Left
out: a text equal to the suite the baseline ran (or to the owner's test text), a command that names a file a task
declares and the base lacks, and every task Test and scenario Test (they fail on the base by design). Only a command
with no result runs, so a second call is cheap; `--cmd C` runs C again. Each result goes into `plan` under the command's
text: {"result", "exit", "seconds", "class", "kind", "why", "fail_lines", "tail", "where", "limit"}, judged by the exit
code alone: 0 `pass`, 124 `timeout` (class command), 125 the setup line and 127 or a first word that does not resolve
the environment's (class environment), any other `fails like the base` on a red base, else `fail` (class command). The
first word of each step of every command of the plan, the task Tests and the scenario Tests too, is resolved in one
shell call under the setup block (doctor.needs): one that does not resolve is a fault of the environment, which turns
the base red. Then the worktree goes. `skip` is the person's skip of one command, with a reason: an override row named
plan-command.
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


def update(root, fn):
    """Read, change and write the file under a lock of its folder: the suite's process and the plan's commands both
    write it (WP21). fn changes the dict in place."""
    p = path(root)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    fd = None
    try:
        import fcntl
        fd = os.open(os.path.dirname(p), os.O_RDONLY)
        fcntl.flock(fd, fcntl.LOCK_EX)
    except (ImportError, OSError):
        pass
    try:
        d = read(root)
        fn(d)
        write(d, root)
        return d
    finally:
        if fd is not None:
            os.close(fd)


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
    kept = (d.get("limits") or {}).get(norm(cmd)) if isinstance(d.get("limits"), dict) else None
    if num(kept):   # a limit kept for this very command: a doubled time out, or the person's more time (WP21)
        base = max(base, float(kept))
    p = next((e for c, e in (d.get("plan") or {}).items() if norm(c) == norm(cmd) and isinstance(e, dict)
              and e.get("result") == "pass" and num(e.get("seconds"))), None) if isinstance(d.get("plan"), dict) else None
    if p:   # WP21 mechanism 5: a plan command that passed on the base, three times its seconds
        base = max(base, 3 * float(p["seconds"]))
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
    if not read(root):
        return
    try:
        twice = 2 * int(float(limit))
    except (TypeError, ValueError):
        return

    def keep(d):
        lim = d.get("limits") if isinstance(d.get("limits"), dict) else {}
        lim[norm(cmd)] = max(twice, int(lim.get(norm(cmd)) or 0) if num(lim.get(norm(cmd))) else twice)
        d["limits"] = lim
    update(root, keep)


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
    """The baseline's own fields under "baseline:<key>", written under the store's lock (WP22)."""
    if not key:
        return

    def put(d):
        e = d.get("baseline:" + key) if isinstance(d.get("baseline:" + key), dict) else {}
        e.update(fields)
        e["ts"] = now()
        d["baseline:" + key] = e
    run_env.store_change(store_path(root), put)


def base_result(root, cmd):
    """What the base gave for cmd (WP22, the flaky recheck): ("pass", set()) when it passed there (the plan's command of
    that text, or the suite the baseline ran); ("red", the masked fail lines) when it failed there as the base does (a
    failure known at the base counts as the base's pass); None when the base did not run it or says nothing."""
    d = read(root)
    if not d:
        return None
    e = (d.get("plan") or {}).get(cmd) if isinstance(d.get("plan"), dict) else None
    if isinstance(e, dict):
        if e.get("result") == "pass":
            return "pass", set()
        if e.get("result") == "fails like the base":
            return "red", {mask(x) for x in list(e.get("fail_lines") or []) + list(d.get("fail_lines") or [])}
        return None
    if not same_suite(cmd, d):
        return None
    if d.get("result") == "green":
        return "pass", set()
    if d.get("result") == "red" and d.get("kind") == "red-base" and d.get("fail_lines"):
        return "red", {mask(x) for x in d.get("fail_lines") or []}
    return None


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
    if not isinstance(a, dict) or not a.get("reason") or a.get("kind") != doc.get("kind"):
        return   # an answer given at another kind of red (a fault of the environment, or a red suite) asks again
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

    def put(d):   # the plan's commands and the kept limits are written by other processes meanwhile (WP21)
        keep = {k: d[k] for k in ("plan", "limits") if isinstance(d.get(k), dict)}
        d.clear()
        d.update(doc, **keep)
    update(root, put)
    if doc.get("result") == "red":   # WP23: a red base is one failure record of class environment
        failed_record(root, "base", "suite", doc.get("kind"), doc.get("why"), doc.get("run") or doc.get("cmd") or "",
                      doc.get("exit_code"), doc.get("fail_lines"), "base" if doc.get("kind") == "red-base" else "exit")


def failed_record(root, scope, check, kind, why, cmd, rc, lines, by, key=""):
    """WP23: one record of scripts/failure.py; it never fails the baseline."""
    try:
        import failure
        try:
            st = json.load(open(os.path.join(root, ".temper", "build-state.json"))).get("next_stage") or "plan"
        except (OSError, ValueError, AttributeError):
            st = "plan"
        failure.record(st, scope, check, kind or "red-base", why or "", cmd=cmd, exit=rc if isinstance(rc, int) else None,
                       fail_lines=lines or [], class_by=by, key=key, root=root)
    except Exception:
        pass


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
    if env_only:
        doc["env_only"] = True   # a door: no red base question, a fault of the environment check included
    if again:
        doc["again"] = True   # WP22: the person's Run it again is a fresh run, whatever the store holds
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


def picked(out, rc, keep=8):
    """The lines that say what failed, picked by pattern (task_ops.fail_lines without its fallback to the last lines); at
    most `keep` of them, every one with keep None."""
    lines = run_env.fail_lines(out if isinstance(out, bytes) else str(out).encode(), keep, rc)
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
    os.makedirs(os.path.join(folder, ".temper", "check"), exist_ok=True)   # where the run text writes its coverage

    def measure(out):
        c = det.get("coverage") or {}
        extra = b""
        if c.get("report"):
            extra, _ = run_env.run_cmd(folder, 300, [c["report"]], setup)
        return {"coverage": check_run.coverage_value(folder, det, (out + b"\n" + extra).decode("utf-8", "replace"))}
    info = {"measure": measure}
    out, rc, reused = run_env.run_cached(folder, LIMIT_S, [own["run"]], setup, info, fresh=bool(doc.get("again")), root=root)
    info["coverage"] = (info.get("extra") or {}).get("coverage") if isinstance(info.get("extra"), dict) else None
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
    whole = "\n".join(info.get("fail_lines") or []).encode() + b"\n" + out   # every line, a reused run's too
    doc.update(result="red", kind=kind, exit_code=rc, fail_lines=picked(whole, rc, None),
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


def clean(root, quiet=False):
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
    if not quiet:
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
    a = {"by": "the person", "reason": reason, "ts": now(), "kind": d.get("kind")}
    d.update(answer="go-on-anyway", answered=a)
    write(d, root)
    store_put(root, d.get("key") or "", answer=a)
    rc, out = cli(root, "override", "base-suite", "--reason", reason)
    sys.stdout.write(out)
    return rc


# ---- WP21: the plan's commands, once on the base ----------------------------------------------------------------------
PLACEHOLDER = re.compile(r"^\{\S[^{}]*\}$")   # a template's unfilled `{full suite command}` is no command
GROUP_LIMIT_S = os.environ.get("TEMPER_TASK_TEST_TIMEOUT_S") or 600       # the group gate's default (scripts/temper)
INTEGRATION_LIMIT_S = os.environ.get("TEMPER_INTEGRATION_TIMEOUT_S") or 3600   # integrate's default


def real(cmd):
    cmd = (cmd or "").strip()
    return bool(cmd) and cmd != "manual" and not PLACEHOLDER.match(cmd)


def spec_of(root, spec):
    return os.path.join(root, spec) if spec and not os.path.isabs(spec) else spec


def plan_of(root, spec):
    """(commands, every, declared): commands is [(cmd, where, default limit)] distinct, in plan order, the group
    Validates then the Integration line; every is each command of the plan (the task and scenario Tests too); declared
    is the files the tasks declare."""
    import acceptance
    import tasks_md
    sp = spec_of(root, spec)
    if not sp or not os.path.isfile(os.path.join(sp, "tasks.md")):
        return [], [], []
    plan = tasks_md.parse(os.path.join(sp, "tasks.md"))
    found = [(g["validate"], "%s Validate" % g["id"], GROUP_LIMIT_S) for g in plan["groups"]]
    found.append((plan.get("integration") or "", "Integration", INTEGRATION_LIMIT_S))
    out = {}
    for cmd, where, lim in found:
        cmd = (cmd or "").strip()
        if real(cmd):
            if cmd in out:
                out[cmd][1] += ", " + where
            else:
                out[cmd] = [cmd, where, lim]
    try:
        lines = open(os.path.join(sp, "intent.md"), encoding="utf-8").read().splitlines()
    except OSError:
        lines = []
    every = list(dict.fromkeys([c for c in out] + [t["test"].strip() for t in plan["tasks"] if real(t.get("test"))]
                               + [b["cmd"].strip() for b in acceptance.scenario_blocks(lines) if real(b.get("cmd"))]))
    return [tuple(v) for v in out.values()], every, sorted({f for t in plan["tasks"] for f in t["files"]})


def suite_texts(root, config, spec, d):
    """The texts of the suite the baseline ran, or of the owner of the suite command as it stands
    (check_run.suite_owner: the plan's Integration line when the project names no suite): a plan command equal to one
    runs no second time."""
    mine = [x for x in (d.get("cmd"), d.get("run")) if x]
    if not mine:
        own = owner_of(root, config, spec)
        mine = [x for x in (own.get("test"), own.get("run")) if x]
    return {norm(x) for x in mine}


def new_files(root, cmds, declared):
    """The declared files a command names (the path, or a stem of four letters or more) that the base does not hold."""
    named = [f for f in declared for st in [os.path.splitext(os.path.basename(f))[0]]
             if any(f in c or (len(st) >= 4 and st in c) for c in cmds)]
    if not named:
        return set()
    _, ls, _ = git(root, "ls-tree", "-r", "--name-only", "HEAD")
    have = set(ls.splitlines())
    return {f for f in named if f not in have}


def to_run(root, config, spec, d=None):
    """[(cmd, where, default limit)] of the plan's commands that run on the base, and the left out ones."""
    d = read(root) if d is None else d
    cmds, _, declared = plan_of(root, spec)
    suite = suite_texts(root, config, spec, d) if cmds else set()
    fresh = new_files(root, [c for c, _, _ in cmds], declared)
    out = []
    for c, where, lim in cmds:
        if norm(c) in suite:
            continue
        if any(f in c or (len(st) >= 4 and st in c) for f in fresh for st in [os.path.splitext(os.path.basename(f))[0]]):
            continue
        out.append((c, where, lim))
    return out


def entry_alive(e):
    pid = e.get("pid")
    if isinstance(pid, int):
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    return time.time() - _ts(e.get("started")) < 60


def pending(root, config, spec, d=None):
    """The plan's commands that have no result yet (one that was running in a process that is gone has none). None
    with no commit to run on."""
    d = read(root) if d is None else d
    if git(root, "rev-parse", "--verify", "-q", "HEAD")[0] != 0:
        return []
    have = d.get("plan") if isinstance(d.get("plan"), dict) else {}
    out = []
    for c, where, lim in to_run(root, config, spec, d):
        e = have.get(c)
        if not isinstance(e, dict) or (e.get("result") == "running" and not entry_alive(e)):
            out.append((c, where, lim))
    return out


def failed(root, config, spec, d=None):
    """[(cmd, entry)] of the plan's commands, as the plan stands, that failed or timed out on the base and that nobody
    skipped, in plan order (a result on record is asked about, whatever would run now)."""
    d = read(root) if d is None else d
    have = d.get("plan") if isinstance(d.get("plan"), dict) else {}
    if not have:
        return []
    out = []
    for c, where, _ in plan_of(root, spec)[0]:
        e = have.get(c)
        if isinstance(e, dict) and e.get("result") in ("fail", "timeout") and not e.get("skipped"):
            out.append((c, dict(e, where=where)))
    return out


def judge(cmd, out, rc, secs, limit, red, missing):
    """The result of one plan command, by its exit code alone (the output is kept, never read for the verdict)."""
    tail = run_env.strip_banner(out[-2048:].decode("utf-8", "replace"))
    e = {"result": "pass", "exit": rc, "seconds": round(secs, 1), "class": None, "kind": "", "why": "", "fail_lines": [],
         "tail": tail, "limit": limit}
    if rc == 0:
        return e
    gone = sorted(p for p in run_env.programs(cmd) if p in missing)
    e["fail_lines"] = run_env.fail_lines(out, None, rc)   # every one, as like_base compares them
    if rc == 124:
        e.update(result="timeout", kind="timeout", why="it did not end within its limit of %d s" % limit)
    elif rc == 125:
        e.update(result="fail", kind="setup-line", why="the setup line of the config failed (exit 125)")
    elif rc == 127 or gone:
        e.update(result="fail", kind="program-missing", why="%s is not found in the shell (exit %d)" % (
            ", ".join(gone) or "a program it starts", rc))
    elif red:
        e.update(result="fails like the base", kind="red-base", why="exit %d; the base is red too, so this tells nothing" % rc)
    else:
        e.update(result="fail", kind="fails-on-base", why="exit %d on the current code" % rc)
    e["class"] = "environment" if e["kind"] in ("setup-line", "program-missing") else "command"
    return e


def plan_start(root, config, spec, again=""):
    """`temper baseline plan`: the commands with no result run, in a process of their own; exits 0 always."""
    if git(root, "rev-parse", "--verify", "-q", "HEAD")[0] != 0:
        print("OK: no commit to run the plan's commands on; nothing ran")
        return 0
    started = now(fine=True)

    def mark(d):
        p = d.get("plan") if isinstance(d.get("plan"), dict) else {}
        if again:
            p.pop(again, None)
        d["plan"] = p
        for c, where, lim in pending(root, config, spec, d):
            p[c] = {"result": "running", "where": where, "started": started}
            if c == again:
                p[c]["fresh"] = True   # WP22: the person's Run it again runs whatever the store holds
    d = update(root, mark)
    todo = [c for c, e in d["plan"].items() if isinstance(e, dict) and e.get("started") == started]
    if not todo and not plan_of(root, spec)[1]:
        print("OK: every command of the plan has its result on the current code, or is left out; nothing ran")
        return 0
    if os.environ.get("TEMPER_BASELINE_FOREGROUND"):
        plan_run(root, config, spec, started)
    else:
        subprocess.Popen([sys.executable, "-E", "-s", os.path.abspath(__file__), root, config or "", spec or "", "plan-run",
                          started], cwd=root, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    print("OK: %d command(s) of the plan %s on the current code%s" % (
        len(todo), "ran" if os.environ.get("TEMPER_BASELINE_FOREGROUND") else "run in their own process",
        "" if todo else "; the programs of every command of the plan are checked"))
    return 0


def plan_run(root, config, spec, started):
    """The plan's commands marked by `started`: wait for a suite still running and for an earlier call's commands (the
    worktree is one), check the programs of the whole plan, run each in the worktree, then remove the worktree when no
    other call runs in it."""
    def mine(d):
        p = d.get("plan") if isinstance(d.get("plan"), dict) else {}
        return [c for c, e in p.items() if isinstance(e, dict) and e.get("started") == started and e.get("result") == "running"]

    def own(d):
        for c in mine(d):
            d["plan"][c]["pid"] = os.getpid()

    def others(d, older=True):   # the plan's commands another call runs (an older one, or any) in the one worktree
        p = d.get("plan") if isinstance(d.get("plan"), dict) else {}
        return [c for c, e in p.items() if isinstance(e, dict) and e.get("result") == "running" and entry_alive(e)
                and e.get("started") != started and (not older or str(e.get("started") or "") < started)]
    d = update(root, own)
    t0, until = time.time(), None
    while (d.get("result") == "running" and alive(d)) or (mine(d) and others(d)):
        if d.get("result") == "running" and alive(d):   # the suite, up to the baseline's own limit
            if time.time() - t0 >= LIMIT_S:
                break
        else:   # the older call runs its commands one after another, each up to its own limit (integrate's is an hour)
            if until is None:
                try:
                    lims = {c: lim for c, _, lim in plan_of(root, spec)[0]}
                except Exception:
                    lims = {}
                until = time.time() + sum(limit_for(c, lims.get(c, GROUP_LIMIT_S), root) + 30 for c in others(d))
            if time.time() >= until:
                break
        time.sleep(0.5)
        d = read(root)
    try:
        _plan_run(root, config, spec, started, d, mine(d))
    except Exception as e:   # a baseline call never fails a run: each command left says why
        def why(d):
            for c in mine(d):
                d["plan"][c] = {"result": "unknown", "why": "it could not run: %s" % str(e)[:200]}
        update(root, why)
    if not others(read(root), older=False):   # the last call that runs in the worktree removes it
        clean(root, quiet=True)
    return 0


def _plan_run(root, config, spec, started, d, todo):
    import doctor
    setup = run_env.load_setup(config) if config and os.path.isfile(config) else {}
    red = d.get("result") == "red"
    folder, why = worktree(root) if todo else (root, "")   # nothing to run: the programs only, in the project
    if not folder:
        raise RuntimeError(why)
    _, every, _ = plan_of(root, spec)
    faults, _, _ = doctor.needs(folder, setup, every)
    # a program the plan starts: a path into the tree may be a file a task makes, so only a bare name or an absolute
    # path is looked up
    faults = [f for f in faults if f.get("kind") == "program-missing" and f.get("file") == "the suite command"
              and ("/" not in f["need"] or f["need"].startswith("/"))]
    missing = {f["need"] for f in faults}
    where = {c: (w, lim) for c, w, lim in to_run(root, config, spec, d)}
    for c in todo:
        w, lim = where.get(c, ("", GROUP_LIMIT_S))
        limit = limit_for(c, lim, root)
        info = {}
        fresh = bool(((d.get("plan") or {}).get(c) or {}).get("fresh"))
        out, rc, _ = run_env.run_cached(folder, limit, [c], setup, info, fresh=fresh, root=root)   # WP22: the store
        e = dict(judge(c, out, rc, float(info.get("seconds") or 0), limit, red, missing), where=w, ended=now(),
                 **{k: v for k, v in run_env.row_fields(info).items() if k in ("tree", "reused")})
        if e["result"] != "pass":   # WP23: a plan command that fails on the base is one failure record
            failed_record(root, "plan-command", "validate", e.get("kind"), "%s: %s" % (c[:160], e.get("why")), c, rc,
                          e.get("fail_lines"), "base" if e.get("kind") in ("red-base", "fails-on-base") else "exit",
                          info.get("key") or "")

        def put(d, c=c, e=e):
            d.setdefault("plan", {})[c] = e
        update(root, put)
    if faults:
        def env(d):
            known = {(x.get("kind"), x.get("need")) for x in d.get("env") or [] if isinstance(x, dict)}
            add = [dict(f, file="the plan", why="%s is not found in the shell; a command of the plan starts it" % f["need"])
                   for f in faults if ("program-missing", f["need"]) not in known]
            d["env"] = list(d.get("env") or []) + add
            if add and d.get("result") != "red":
                d.update(result="red", kind="program-missing", why="; ".join(f["why"] for f in add))
        update(root, env)


def wait(root, cmd):
    """Waits while the plan's command cmd runs on the base (the first group gate of its group), up to its limit."""
    t0 = time.time()
    while time.time() - t0 < LIMIT_S:
        e = (read(root).get("plan") or {}).get(cmd)
        if not (isinstance(e, dict) and e.get("result") == "running" and entry_alive(e)):
            return 0
        time.sleep(0.5)
    return 0


FAIL_CAP = 8   # the fail lines a cut list keeps (run_env.fail_lines); a run's list from run_cached is whole


def like_base(root, cmd, lines):
    """Whether a failed run of the plan's command cmd at its gate shows only the failures it showed on the base, on a
    base the person went on from (its result `fails like the base`, or cmd is the suite the baseline ran): every fail
    line is one of the base's, digits left out. No line to compare with is no match. A list longer than FAIL_CAP is
    whole (run_cached keeps every line; a cut one holds FAIL_CAP at most)."""
    d = read(root)
    e = (d.get("plan") or {}).get(cmd) if isinstance(d.get("plan"), dict) else None
    e = e if isinstance(e, dict) and e.get("result") == "fails like the base" else None
    suite = d.get("result") == "red" and norm(cmd) in [norm(x) for x in (d.get("cmd"), d.get("run")) if x]
    if d.get("answer") != "go-on-anyway" or not (e or suite):
        return False
    base = {mask(x) for x in list((e or {}).get("fail_lines") or []) + list(d.get("fail_lines") or [])}
    got = [x for x in lines if str(x).strip()]
    if len(got) == FAIL_CAP:   # a list cut at its cap may hide a new failure: no match
        return False
    return bool(base) and bool(got) and all(mask(x) in base for x in got)


def skip(root, cmd, reason):
    """The person's skip of one plan command, with a reason: an override row named plan-command."""
    reason = " ".join(str(reason or "").split())
    if not cmd or not reason:
        print("FAIL: usage: temper baseline skip --cmd '<command>' --reason '<why>'", file=sys.stderr)
        return 1
    rc, out = cli(root, "override", "plan-command", "--reason", "%s (the plan's command: %s)" % (reason, cmd[:200]))
    sys.stdout.write(out)
    if rc != 0:
        return rc

    def put(d):
        p = d.get("plan") if isinstance(d.get("plan"), dict) else {}
        e = p.get(cmd) if isinstance(p.get(cmd), dict) else {"result": "not run"}
        e["skipped"] = {"by": "the person", "reason": reason, "ts": now()}
        p[cmd] = e
        d["plan"] = p
    update(root, put)
    return 0


# ---- the recorded skip: the row `tests pass` of a red base the person went on from ----------------------------------
def mask(line):
    return re.sub(r"\d+", "#", " ".join(str(line).split()))


def skip_row(root, ledger, config=""):
    """The row `tests pass` with the state skipped (WP19's third state), as one JSON line, when every failed test run of
    the ledger runs the base's suite and shows only the base's fail lines (all of them, when the base showed none); else
    nothing: the row fails as before. Only after the person went on anyway, in this run."""
    d = read(root)
    if d.get("answer") != "go-on-anyway" or not (d.get("kind") == "red-base" or (
            isinstance(d.get("exit_code"), int) and d.get("exit_code") not in (125, 127))):
        return ""   # a fault of the environment check, a setup line or a program that did not start ran no test on the base
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
        # every fail line counts, so a new one after the eighth is no skip: the row's whole list and its output's tail
        got = picked(("\n".join(map(str, r.get("fail_lines") or [])) + "\n" + str(r.get("output") or "")).encode(),
                     r.get("exit_code"), None)
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
    if sub == "plan":
        try:
            return plan_start(root, config, spec, rest[rest.index("--cmd") + 1] if "--cmd" in rest[:-1] else "")
        except Exception as e:   # a baseline call never fails a run
            print("OK: the plan's commands could not start: %s" % str(e)[:200])
            return 0
    if sub == "plan-run" and rest:
        return plan_run(root, config, spec, rest[0])
    if sub == "skip":
        arg = lambda k: rest[rest.index(k) + 1] if k in rest[:-1] else ""
        return skip(root, arg("--cmd"), arg("--reason"))
    if sub == "wait" and rest:
        return wait(root, rest[0])
    if sub == "like-base" and len(rest) == 2:
        try:
            lines = json.loads(rest[1])
        except ValueError:
            lines = []
        return 0 if like_base(root, rest[0], lines if isinstance(lines, list) else []) else 1
    if sub == "skip-row" and rest:
        r = skip_row(root, rest[0], config)
        if r:
            print(r)
        return 0
    print("FAIL: usage: temper baseline start [--again] [--env-only] | clean | accept-red --reason '<why>' | plan [--cmd C] "
          "| skip --cmd C --reason '<why>'", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
