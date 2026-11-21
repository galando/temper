#!/usr/bin/env python3
"""repair_ops.py: a finding repaired in its stage (9.8.5, WP24, ADR 0021). One High or critical finding of Review, or one
failed row of Check whose class is code, is repaired where it was found: the CLI opens a window, a fresh Build agent
fixes and commits nothing, the CLI commits and runs its checks again on the new tree, a reader that did not write the
fix confirms each finding in rows written after the commit and after its launch mark, and only then does the CLI
resolve it, for that commit. A repair that made things worse is reverted, and the run asks (repair.stop).

  python3 repair_ops.py CLI CONFIG start --stage review|check [--again]   open the window (can_start holds every condition)
  python3 repair_ops.py CLI CONFIG test ID --phase red|green -- CMD...     the fixer's test of a finding marked proof: test
  python3 repair_ops.py CLI CONFIG commit                                 the CLI's commit of the repair, then its checks again
  python3 repair_ops.py CLI CONFIG mark                                   the recheck's launch mark (its before call)
  python3 repair_ops.py CLI CONFIG close                                  resolve what the recheck confirmed; revert when worse
  python3 repair_ops.py CLI CONFIG revert                                 the CLI's own commit back to the reviewed tree
  python3 repair_ops.py CLI CONFIG status                                 the open repair and the closed ones, as JSON
  python3 repair_ops.py CLI CONFIG carve                                  the commit gate's carve out (prints its rows, exit 0)
  python3 repair_ops.py CLI CONFIG answer CLAIM                           the question a Scope drift answer answers (answer_of)

CLI is the path of scripts/temper, which runs the checks again (integrate, gate build, check run); CONFIG the project's
config file. The run state keeps `repair` (the open window), `repairs` (the closed ones, each with its number `n`) and
`repair_stop` (what the run asks about, until the run moves). Run in the project folder; standard library only.
"""
import base64
import hashlib
import json
import os
import random
import re
import shlex
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

TEMPER = ".temper"
STATE = os.path.join(TEMPER, "build-state.json")
GROUPS = os.path.join(TEMPER, "groups.json")
GATES = os.path.join(TEMPER, "gates.json")
REVIEW = os.path.join(TEMPER, "evidence", "review.json")
ACC_LOCK = os.path.join(TEMPER, "evidence", "acceptance-lock.json")
LOCK = os.path.join(TEMPER, ".lock")
STAGES = ("review", "check")
LARGE = 300   # a diff over this many changed lines gets a full Review in the place of the recheck
# the rows a repair may answer: at Review the open blocking findings; at Check the rows a run of the code fails
REVIEW_ROWS = ("no blocking findings",)
CHECK_ROWS = ("tests pass", "scenarios traced to tests", "acceptance evidence", "coverage",
              "acceptance tests written before Build")
MANIFEST = re.compile(r"(^|/)(package(-lock)?\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb?|"
                      r"Cargo\.(toml|lock)|go\.(mod|sum)|Gemfile(\.lock)?|composer\.(json|lock)|poetry\.lock|Pipfile(\.lock)?|"
                      r"pyproject\.toml|uv\.lock|requirements[^/]*\.txt|setup\.(py|cfg)|pom\.xml|build\.gradle(\.kts)?|"
                      r"settings\.gradle(\.kts)?|gradle\.lockfile|[^/]*\.csproj|packages\.lock\.json|mix\.(exs|lock))$")
CI_FILE = re.compile(r"(^|/)(\.github/workflows/|\.circleci/|\.buildkite/)|(^|/)(\.gitlab-ci\.yml|Jenkinsfile|azure-pipelines\.yml|"
                     r"\.travis\.yml|bitbucket-pipelines\.yml|\.drone\.yml)$")
ANSWER = r"^drift (\S+): (Add to plan|Allow once)\b"   # a Scope drift answer that widens the approved set
RECHECK = re.compile(r"^\s*recheck #(\d+):\s*(fixed|not fixed)\b", re.I)


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def load(path, kind=dict):
    try:
        d = json.load(open(path))
        return d if isinstance(d, kind) else kind()
    except (OSError, ValueError):
        return kind()


def save(path, d):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def git(*args, env=None):
    """(exit code, stdout) of a git command."""
    try:
        r = subprocess.run(["git", "-c", "core.quotePath=false"] + list(args), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, env=env)
    except OSError:
        return 1, ""
    return r.returncode, r.stdout.decode("utf-8", "surrogateescape")


def out(*args):
    return git(*args)[1].strip()


class Lock:
    """The CLI's lock (.temper/.lock, its owner inside), as scripts/temper takes it: held around a write of the run's
    files, never while a check or `git commit` runs (the commit hook starts the CLI, which takes it too)."""

    def __enter__(self):
        tok = "%d.%d" % (os.getpid(), random.randrange(1 << 30))
        end = time.time() + 120
        while True:
            new = "%s.new.%s" % (LOCK, tok)
            if not os.path.exists(LOCK):
                try:
                    os.mkdir(new)
                    with open(os.path.join(new, "owner"), "w") as f:
                        f.write(tok)
                    os.rename(new, LOCK)
                    if open(os.path.join(LOCK, "owner")).read() == tok:
                        self.tok = tok
                        return self
                except OSError:
                    pass
            shutil.rmtree(new, ignore_errors=True)
            try:   # an owner that is gone leaves a lock nobody frees
                os.kill(int(open(os.path.join(LOCK, "owner")).read().split(".")[0]), 0)
            except ProcessLookupError:
                dead = "%s.dead.%d" % (LOCK, os.getpid())
                try:
                    os.rename(LOCK, dead)
                    shutil.rmtree(dead, ignore_errors=True)
                except OSError:
                    pass
                continue
            except (OSError, ValueError):
                pass
            if time.time() > end:
                raise SystemExit("FAIL: %s is held past 120 s; nothing was written. Run the call again" % LOCK)
            time.sleep(0.02)

    def __exit__(self, *exc):
        try:
            if open(os.path.join(LOCK, "owner")).read() == self.tok:
                gone = "%s.free.%d" % (LOCK, os.getpid())
                os.rename(LOCK, gone)
                shutil.rmtree(gone, ignore_errors=True)
        except OSError:
            pass
        return False


def change_state(fn):
    """Read, change and write the run state under the lock; returns what fn returns."""
    with Lock():
        d = load(STATE)
        res = fn(d)
        save(STATE, d)
        return res


def run_of(config):
    from flow_run import Run
    return Run({"config_file": config})


def cli(path, *words):
    """(exit code, output) of a call of the CLI: the checks run again on the new tree."""
    try:
        r = subprocess.run([path] + list(words), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except OSError as e:
        return 1, str(e)
    return r.returncode, r.stdout.decode("utf-8", "replace")


# ---- what a repair reads -----------------------------------------------------------------------------------------------

def is_test(p, gate=False):
    """A test file: with gate, the commit gate's pattern, what a repair may commit beside the plan (step 6.3) and so what
    can_start lets stand outside the plan; else also a shell test, as task_ops reads it, for the one test rule and the
    recheck (F8: the gate's pattern stays the base's)."""
    import commit_rows
    return bool(commit_rows.TEST_RE.search(p) or (not gate and re.search(r"_test\.sh$", p)))


def step_of(d):
    return d.get("step")


def this_round(d, stage):
    """The repairs of the stage since the run last came to it (a step back or a move counts one step)."""
    return [x for x in d.get("repairs") or [] if isinstance(x, dict) and x.get("stage") == stage
            and x.get("step") == step_of(d)]


def manual_ids(r):
    """The ids of the required, open criteria of intent.md that only the person confirms (Validate type manual, or code
    or metric with no command in backticks: acceptance.by_person)."""
    if not r.spec or not os.path.isfile(os.path.join(r.spec, "intent.md")):
        return []
    try:
        import acceptance
        lines = open(os.path.join(r.spec, "intent.md"), encoding="utf-8").read().splitlines()
        return [c["id"] for c in acceptance.parse_criteria(acceptance.section_lines(lines, "Success Criteria"))
                if c.get("id") and acceptance.by_person(c) and not c.get("placeholder")]
    except Exception:
        return []


def triage_code(row):
    """The triage of a failing locked acceptance test blames the code, for this very failure."""
    t = load(ACC_LOCK).get("triage") or {}
    digest = hashlib.sha256(str(row.get("detail", "")).encode("utf-8")).hexdigest()[:16]
    return isinstance(t, dict) and t.get("verdict") == "code" and t.get("failure") == digest


def row_class(r, row):
    """What a failed row of Check is, for a repair: `code` (a run of the code failed), else why it is no repair's."""
    import approval
    import failure
    name, detail = str(row.get("name") or ""), " ".join(str(row.get("detail") or "").split())
    if name == approval.ROW:
        return "the approval: the intent or the plan changed after the person approved it"
    if name.startswith("acceptance tests written before Build"):
        return "code" if triage_code(row) else "a locked acceptance test the triage does not blame on the code"
    if re.search(r"no passing test-run evidence|not run|not measured", detail):
        return "not measured: a check that was not measured is never repaired by rule (it has no evidence)"
    if name == "acceptance evidence" and any(re.search(r"\b%s has no supported passing evidence row" % re.escape(i), detail)
                                             for i in manual_ids(r)):
        return "a criterion only the person can confirm"
    if name not in CHECK_ROWS:
        return "the row %s is not on the repairable list" % name
    check = failure.ROW_CHECK.get(name, "row:%s" % name)
    recs = [x for x in failure.open_records(scope="gate:check") if x.get("check") == check]
    cls = recs[-1].get("class") if recs else "code"
    if cls == "environment":
        return "an environment fault (SETUP, class environment): nothing in the code is wrong"
    if cls != "code":
        return "a failure whose class is %s, not code" % cls
    return "code"


def failed_rows(r, stage):
    return [x for x in r.failed_rows(stage) if isinstance(x, dict)]


def targets(r, stage):
    """The findings a repair at the stage answers: the open ones at review.block-on; at a passed Review, the open ones at
    high or above, which the person may repair on the click (mechanism 14)."""
    if stage != "review":
        return []
    if r.verdict(stage) == "FAIL":
        return r.open_findings()
    return [f for f in r.findings() if f["state"] == "open" and f["severity"] in ("critical", "high")]


def can_start(r, stage, again=False):
    """None when a repair may open at the stage now, else why not: the one place for every condition, which the flow,
    the question and the call all ask."""
    d = r.state
    if stage not in STAGES:
        return "a repair is made at Review or Check, never at %s: the final commit meets every gate" % (stage or "no stage")
    if r.command == "fix":
        return "a fix run never repairs by rule: its Fix agent commits nothing, so no reviewed HEAD exists"
    if r.stage != stage:
        return "the run is at %s, not at %s" % (r.stage or "no stage", stage)
    if isinstance(d.get("repair"), dict):
        return "repair %s is open already" % d["repair"].get("n")
    if d.get("adhoc"):
        return "a small change is open at %s" % (d.get("adhoc") or {}).get("stage")
    v = r.verdict(stage)
    opens = targets(r, stage)
    if (v != "FAIL" and not (again and v == "PASS" and opens)) or r.skip(stage) is not None:
        return ("the %s gate passed: there is nothing to repair" % stage.capitalize()) if v == "PASS" else (
            "the %s gate has no failed verdict (%s)" % (stage.capitalize(), "skipped by the person" if r.skip(stage) else v or "none"))
    rows = failed_rows(r, stage)
    if stage == "review":
        if any(x.get("name") == "review completed" for x in rows):
            return "Review did not record its completion (an unfinished Review runs again; it is never repaired)"
        bad = [x.get("name") for x in rows if x.get("name") not in REVIEW_ROWS]
        if bad:
            return "the failed row %s is not on the repairable list (no blocking findings)" % bad[0]
        if not opens:
            return "no open finding at review.block-on: no blocking finding on record to repair"
        hot = [f for f in opens if f.get("answer") in ("contested", "escalated")]
        if hot:
            return "finding #%d is %s: the person decides it" % (hot[0]["id"], hot[0]["answer"])
        import sensitive
        pats = sensitive.patterns_of(r.cfg("autonomy.park-on-touch"))
        near = [f for f in opens if f.get("file") and any(sensitive.match(f["file"], p) for p in pats)]
        if near:
            return "finding #%d is on %s, a sensitive path (autonomy.park-on-touch): nothing there is repaired by rule" % (
                near[0]["id"], near[0]["file"])
        plan = allowed_files(r)
        far = [f for f in opens if f.get("file") and os.path.normpath(f["file"]) not in plan and not is_test(f["file"], gate=True)]
        if far:
            return "finding #%d is on %s, a file outside the plan: its fix needs the plan changed, which no rule does" % (
                far[0]["id"], far[0]["file"])
    else:
        led = [x for x in load(os.path.join(TEMPER, "evidence", "check.json"), list) if isinstance(x, dict)]
        last = max((i for i, x in enumerate(led) if str(x.get("claim", "")).startswith("tests: the suite")), default=-1)
        if any(str(x.get("claim", "")).startswith("setup fault: ") for x in led[last + 1:]):
            return "an environment fault (a setup fault: row after the last run of the suite): nothing in the code is wrong"
        for x in rows:
            cls = row_class(r, x)
            if cls != "code":
                return "the failed row %s is no repair's: %s" % (x.get("name"), cls)
    seq = r.seq()
    skipped = [o for o in r.overrides if isinstance(o, dict) and o.get("stage") in seq]
    if skipped:
        return "a stage of the run was skipped (overridden by the person: %s): no repair by rule on a skipped check" % skipped[-1]["stage"]
    if r.sensitive():
        return "the plan touches a sensitive path (%s), risk H: nothing there is repaired by rule (autonomy.park-on-touch)" % (
            ", ".join(r.sensitive()[:3]))
    head = out("rev-parse", "HEAD")
    seen = (d.get("review_snapshot") or {}).get("head") if isinstance(d.get("review_snapshot"), dict) else ""
    if not seen or head != seen:
        return "HEAD %s is not the reviewed HEAD %s: a repair starts from the tree Review read" % (head[:7], (seen or "none")[:7])
    import run_env
    if run_env.tree_key(os.getcwd()) != out("rev-parse", "HEAD^{tree}"):
        return "the tree is dirty: uncommitted changes beside the reviewed HEAD; a repair starts from a clean tree"
    branch, cur = d.get("branch") or "", out("rev-parse", "--abbrev-ref", "HEAD")
    if not branch or cur != branch:
        return "the run is not on its own branch (%s; HEAD is on %s)" % (branch or "none", cur or "none")
    integ = r.groups.get("integration") if isinstance(r.groups.get("integration"), dict) else {}
    if integ.get("verdict") != "PASS":
        return "Build was not integrated (temper integrate): a repair reruns the integration, so it needs one"
    done = this_round(d, stage)
    if not again and done:
        return "one repair by rule a stage: repair %s ran at %s; the person may repair again" % (done[-1].get("n"), stage)
    if again and len(done) >= 2:
        return "the one repair more on the person's click was taken (repairs %s)" % ", ".join(str(x.get("n")) for x in done)
    rm = r.room("gate:%s" % stage)
    if not rm["ok"]:
        import budget
        return "the budget has no room: %s" % budget.count_line("gate:%s" % stage, rm)
    return None


def offer(r, stage):
    """Whether the gate question offers Repair again (the person's click): exactly where its call, `repair start --again`,
    may start (can_start). True when recommended (no repair of this failure ran yet), False when offered only, None when
    not offered."""
    if r.command != "temper" or stage not in STAGES or can_start(r, stage, again=True):
        return None
    return not this_round(r.state, stage)


# ---- the files a repair changed ----------------------------------------------------------------------------------------

def digests(paths):
    out_ = {}
    for p in paths:
        try:
            out_[p] = hashlib.sha256(open(p, "rb").read()).hexdigest()
        except OSError:
            out_[p] = "DELETED"
    return out_


def guarded_files(spec, config):
    """The files a repair may never change that git status does not list: the spec folder, the config, the git hooks."""
    files = []
    for root in [spec] + [h for h in hook_dirs()]:
        if root and os.path.isdir(root):
            for dp, _, fs in os.walk(root):
                files += [os.path.join(dp, f) for f in fs if not f.endswith(".sample")]
    if config and os.path.isfile(config):
        files.append(os.path.relpath(config))
    return sorted(set(os.path.normpath(f) for f in files))


def hook_dirs():
    hp = out("config", "core.hooksPath")
    gp = out("rev-parse", "--git-path", "hooks")
    return [x for x in (hp, gp) if x]


def snapshot(spec, config):
    return digests(guarded_files(spec, config))


def keep(spec, config):
    """A copy of each file a repair may never change (the spec folder, the config, the git hooks): git cannot give back
    one it does not track."""
    out_ = {}
    for p in guarded_files(spec, config):
        try:
            out_[p] = base64.b64encode(open(p, "rb").read()).decode("ascii")
        except OSError:
            pass
    return out_


def changed(w, spec, config):
    """The files changed since the window opened: what git status lists (adhoc_ops.dirty), what was committed since its
    base, and any file of the spec folder, the config or the git hooks whose digest moved."""
    import adhoc_ops
    now_ = adhoc_ops.dirty()
    was = w.get("dirty") or {}
    files = {p for p, h in now_.items() if was.get(p) != h}
    files |= {p for p in was if p not in now_}
    snap = w.get("snap") or {}
    cur = snapshot(spec, config)
    files |= {p for p in set(snap) | set(cur) if snap.get(p) != cur.get(p)}
    return sorted(files)


def refused_file(p, r, spec, config, allowed):
    """Why a changed file is no repair's to commit, or None."""
    import sensitive
    norm = os.path.normpath(p)
    if spec and (norm == os.path.normpath(spec) or norm.startswith(os.path.normpath(spec) + "/")):
        locked = load(ACC_LOCK).get("files") or {}
        return "%s is %s" % (p, "a locked acceptance test" if norm in locked else "a file of the run's spec folder")
    if config and norm == os.path.normpath(os.path.relpath(config)):
        return "%s is the config" % p
    if norm == ".git" or norm.startswith(".git/") or any(norm.startswith(os.path.normpath(h) + "/") for h in hook_dirs()):
        return "%s is under the git folder (a hook)" % p
    if norm.startswith(".temper/"):
        return "%s is a file of Temper's own run state" % p
    if norm in (load(ACC_LOCK).get("files") or {}):
        return "%s is a locked acceptance test" % p
    if any(sensitive.match(norm, x) for x in sensitive.patterns_of(r.cfg("autonomy.park-on-touch"))):
        return "%s is under a sensitive path (autonomy.park-on-touch)" % p
    if MANIFEST.search(norm):
        return "%s is a dependency manifest or lockfile" % p
    if CI_FILE.search(norm):
        return "%s is a CI file" % p
    if norm in allowed or is_test(norm, gate=True):
        return None
    return "%s is outside the approved file set" % p


def allowed_files(r):
    """The approved set a repair commits by rule: the plan's files, approved_files, and each file the person added to the
    plan or allowed once by answering a question the CLI asked (a row the CLI marked `answer` as it wrote it: answer_of),
    never a row that only reads like one (lane E: the fixer could write that row itself)."""
    import flow_base
    files = set(r.state.get("approved_files") or []) | set(flow_base.plan_files(r.spec) if r.spec else [])
    for x in load(os.path.join(TEMPER, "evidence", "build.json"), list):
        m = re.match(ANSWER, str((x or {}).get("claim") or ""), re.I)
        if m and isinstance(x, dict) and x.get("answer"):
            files.add(m.group(1))
    return {os.path.normpath(f) for f in files}


def answer_of(claim):
    """The question a Scope drift answer that widens the approved set answers (`drift P: Add to plan|Allow once`, an
    evidence add of the Build ledger), as the mark the CLI writes on its row: `scope.drift` for a drift ask of P with no
    answer yet, `repair.stop` for the stop of an open repair on P, `commit.fail` for the commit gate's failed scope row
    that names P; '' for any other claim. Inside a repair window that is not committed, such an answer to no question is
    refused (ValueError): the fixer never writes the person's answer (outside one the row is kept unmarked, as before, and
    no repair reads it), and so is one in a run that goes on by itself with no stop open (WP32). That a person gave the
    answer only the mod holds (docs/trust.md)."""
    m = re.match(ANSWER, claim or "", re.I)
    if not m:
        return ""
    path = m.group(1)
    rows = [x for x in load(os.path.join(TEMPER, "evidence", "build.json"), list) if isinstance(x, dict)]
    asked = [i for i, x in enumerate(rows) if x.get("phase") == "drift" and str(x.get("claim") or "").startswith("drift ask %s\n" % path)]
    if asked and not any(re.match(r"drift %s: (Add to plan|Revert|Allow once)\b" % re.escape(path), str(x.get("claim") or ""))
                         for x in rows[asked[-1] + 1:]):
        return "scope.drift"
    d = load(STATE)
    st = d.get("repair_stop") if isinstance(d.get("repair_stop"), dict) else {}
    if st.get("kind") == "drift" and st.get("path") == path:
        return "repair.stop"
    g = load(GATES).get("commit") or {}
    for x in g.get("requirements") or [] if isinstance(g, dict) else []:
        n = re.match(r"changed outside declared files: (.+)$", str((x or {}).get("detail") or ""))
        if (x or {}).get("name") == "blast radius" and not x.get("pass") and n and path in [
                f.strip() for f in re.sub(r"\s*\(and \d+ more\)$", "", n.group(1)).split(",")]:
            return "commit.fail"
    w = d.get("repair") if isinstance(d.get("repair"), dict) else {}
    if w and not w.get("commit"):
        raise ValueError("%s is a Scope drift answer to no question the CLI asked (no open drift ask of %s, no stop of the "
                         "repair on it): inside repair %s only the person's answer to that question adds a file" % (
                             claim, path, w.get("n")))
    import person_call
    if person_call.armed():   # WP32 (rule 4): a run that goes on by itself never answers for the person
        raise ValueError("%s is a Scope drift answer to no question the CLI asked (no open drift ask of %s): a run that goes "
                         "on by itself never answers one" % (claim, path))
    return ""


def staged_files(*base):
    """The staged paths (against base, else HEAD), read with -z so git quotes no name: as adhoc_ops.dirty reads them."""
    return [p for p in git("diff", "--cached", "--name-only", "--no-renames", "-z", *base)[1].split("\0") if p]


def removed_test_lines(base, files):
    """The lines a diff removes from a test file that existed at the base, and the test files it deletes."""
    lines = []
    for f in files:
        if not is_test(f) or git("cat-file", "-e", "%s:%s" % (base, f))[0]:
            continue
        if not os.path.exists(f):
            lines.append("%s: the whole file is deleted" % f)
            continue
        diff = git("diff", "--no-color", "-U0", base, "--", f)[1]
        lines += ["%s: %s" % (f, l[1:]) for l in diff.splitlines() if l.startswith("-") and not l.startswith("---")]
    return lines


def id_args():
    ok = all(git("-c", "user.useConfigOnly=true", "var", v)[0] == 0 for v in ("GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"))
    return [] if ok else ["-c", "user.name=Temper", "-c", "user.email=temper@localhost"]


def diff_lines(base, head):
    n = 0
    for l in out("diff", "--numstat", base, head).splitlines():
        a, b = (l.split("\t") + ["0", "0"])[:2]
        n += (int(a) if a.isdigit() else 0) + (int(b) if b.isdigit() else 0)
    return n


def ledger():
    return [x for x in load(REVIEW, list)]


def note_cli_commit(sha):
    with Lock():
        g = load(GROUPS)
        g.setdefault("cli_commits", []).append(sha)
        save(GROUPS, g)


def snapshot_review():
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "state_ops.py"), "review-code", "save", STATE],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def rule_log(stage, what, by_rule=True):
    """A repair's entry: a rule starts and closes it in every mode (rule 10), but the person's Repair again is theirs."""
    try:
        import rule_log as rl
        rl.append("repair", stage, what, by_rule=by_rule)
    except Exception:
        pass


def gate_rows():
    """{stage: {row name: passed}} of the gates as recorded."""
    g = load(GATES)
    return {s: {str(x.get("name")): x.get("pass") is True for x in (g.get(s) or {}).get("requirements") or [] if isinstance(x, dict)}
            for s in ("build", "review", "check")}


def passed_now():
    return ["%s:%s" % (s, n) for s, rows in gate_rows().items() for n, ok in rows.items() if ok]


# ---- the words -----------------------------------------------------------------------------------------------------------

def start(r, stage, again):
    why = can_start(r, stage, again)
    if why:
        print("FAIL: no repair at %s: %s" % (stage or "this stage", why), file=sys.stderr)
        return 1
    import adhoc_ops
    import budget
    rc, line = budget.spend(["repair", "start", "--stage", stage] + (["--again"] if again else []), budget.Facts(r))
    if rc:
        print(line, file=sys.stderr)
        return 1
    opens = targets(r, stage)
    rows = [x.get("name") for x in failed_rows(r, stage)]

    def open_it(d):
        n = 1 + max([int(x.get("n") or 0) for x in d.get("repairs") or [] if isinstance(x, dict)] or [0])
        save(STATE, d)
        adhoc_ops.open_window(STATE, stage, "repair %d at %s" % (n, stage))
        d.clear()
        d.update(load(STATE))
        d["adhoc"]["kind"] = "repair"
        dirty = d["adhoc"].get("files") or {}
        d.pop("repair_stop", None)
        d["repair"] = {"n": n, "stage": stage, "step": step_of(d), "again": bool(again), "base": out("rev-parse", "HEAD"),
                       "base_tree": out("rev-parse", "HEAD^{tree}"), "findings": [f["id"] for f in opens], "rows": rows,
                       "before": {"blocking": len(opens), "failed": rows, "passed": passed_now()},
                       "ledger_rows": len(ledger()), "dirty": dirty, "snap": snapshot(r.spec, r.ctx.get("config_file")),
                       "keep": keep(r.spec, r.ctx.get("config_file")), "tests": [], "ts": now()}
        return d["repair"]
    w = change_state(open_it)
    what = "; ".join(f["claim"] for f in opens[:3]) or "; ".join(rows)
    rule_log(stage, "repair %d at %s started%s: %s" % (w["n"], stage.capitalize(), " on the person's click" if again else "", what),
             by_rule=not again)
    print("OK: repair %d open at %s (%s); a fresh Build agent fixes it, then temper repair commit" % (w["n"], stage, line or "no repeat"))
    return 0


def test(argv):
    """repair test ID --phase red|green -- CMD: the CLI runs the command; a RED counts when it fails on an assertion (the
    task gate's rule), a GREEN only when the test files the command names are unchanged since the RED."""
    if "--" not in argv or "--phase" not in argv:
        print("FAIL: usage: temper repair test ID --phase red|green -- <command>", file=sys.stderr)
        return 2
    cmd = argv[argv.index("--") + 1:]
    head = argv[:argv.index("--")]
    phase = head[head.index("--phase") + 1] if head.index("--phase") + 1 < len(head) else ""
    fid = next((x for x in head if x.isdigit()), "")
    if phase not in ("red", "green") or not fid or not cmd:
        print("FAIL: usage: temper repair test ID --phase red|green -- <command>", file=sys.stderr)
        return 2
    w = load(STATE).get("repair")
    if not isinstance(w, dict) or w.get("commit"):
        print("FAIL: no repair is open for a test (temper repair start opens one)", file=sys.stderr)
        return 1
    import run_env
    import task_ops
    text = " ".join(shlex.quote(c) for c in cmd) if len(cmd) > 1 else cmd[0]
    output, rc = run_env.run_cmd(os.getcwd(), 600, list(cmd))
    named = sorted({t for c in cmd for t in shlex.split(c) if os.path.isfile(t)})
    row = {"id": int(fid), "phase": phase, "cmd": text, "exit_code": rc, "hashes": digests(named), "ts": now()}
    if phase == "red":
        # As the task gate's red_staged (adversarial review R7c): a RED counts only on the code as the window found it, so
        # a RED made after the fix is no failing-first proof. Test files may change; any other file may not.
        import adhoc_ops
        was, cur = w.get("dirty") or {}, adhoc_ops.dirty()
        moved = sorted(p for p in set(was) | set(cur) if was.get(p) != cur.get(p) and not is_test(p))
        row["ok"] = task_ops.red_ok(row) and not moved
        if moved:
            row["why"] = "the RED run came after a change to %s: write the test first, see it fail, then the fix" % ", ".join(moved[:3])
    else:
        reds = [x for x in w.get("tests") or [] if x.get("id") == int(fid) and x.get("phase") == "red" and x.get("ok")]
        row["ok"] = (rc == 0 and bool(reds) and reds[-1].get("hashes") == row["hashes"] and bool(named)
                     and reds[-1].get("cmd") == text)   # the GREEN runs the command the RED ran

    def add(d):
        d["repair"].setdefault("tests", []).append(row)
    change_state(add)
    sys.stdout.write(output.decode("utf-8", "replace")[-2000:] if isinstance(output, bytes) else str(output)[-2000:])
    print("%s: %s of finding #%s (exit %s)%s" % ("OK" if row["ok"] else "NOTE", phase.upper(), fid, rc,
                                                "" if row["ok"] else ": it does not count%s" % (
                                                    " (%s)" % row["why"] if row.get("why") else "")))
    return 0


def stop(kind, why, **extra):
    """What the run asks about now (repair.stop or scope.drift), until the person answers or the run moves."""
    def put(d):
        d["repair_stop"] = dict({"kind": kind, "why": " ".join(str(why).split())[:600],
                                 "n": (d.get("repair") or {}).get("n") or (d.get("repairs") or [{}])[-1].get("n"),
                                 "stage": d.get("next_stage"), "ts": now()}, **extra)
    change_state(put)


def close_window(d, outcome, **extra):
    """The open repair goes into `repairs` with its outcome; the window closes."""
    w = d.pop("repair", None) or {}
    w = {k: v for k, v in w.items() if k not in ("snap", "token", "keep")}
    w.update(extra, outcome=outcome, closed=now())
    d.setdefault("repairs", []).append(w)
    if isinstance(d.get("adhoc"), dict) and d["adhoc"].get("kind") == "repair":
        d.pop("adhoc", None)
    return w


def commit(r, cli_path):
    d = load(STATE)
    w = d.get("repair")
    if not isinstance(w, dict):
        print("FAIL: no repair is open (temper repair start opens one)", file=sys.stderr)
        return 1
    if w.get("commit"):
        print("OK: repair %s is committed already (%s)" % (w["n"], w["commit"][:7]))
        return 0
    asked = [x["path"] for x in r.drifts() if not (x["choice"] and x["delivered"])]
    if asked:   # the fixer asked about a file (temper drift ask): the person answers scope.drift and the fixer runs again first
        print("OK: repair %s is not committed: the fixer asked about %s; the run asks the person first" % (w["n"], ", ".join(asked)))
        return 0
    change_state(lambda d: d.pop("repair_stop", None))   # the person answered what it asked (scope.drift): commit again
    head = out("rev-parse", "HEAD")
    if head != w.get("base"):
        why = ("HEAD moved since repair %s opened: %s is a commit the CLI did not make (the window opened at %s); the run "
               "stops" % (w["n"], head[:7], str(w.get("base"))[:7]))
        stop("moved", why)
        print("FAIL: %s" % why, file=sys.stderr)
        return 1
    config = r.ctx.get("config_file")
    staged = staged_files(w["base"])
    files = sorted(set(changed(w, r.spec, config)) | set(staged))   # the commit takes the whole index: check all of it
    if not files:
        change_state(lambda d: close_window(d, "unchanged", changed=0))
        stop("unchanged", "repair %s changed nothing, so nothing was committed and no recheck runs" % w["n"])
        rule_log(w["stage"], "repair %s at %s changed nothing" % (w["n"], w["stage"].capitalize()))
        print("OK: repair %s changed nothing (changed: 0): nothing to commit, no recheck; the run asks" % w["n"])
        return 0
    allowed = allowed_files(r)
    bad = [(f, refused_file(f, r, r.spec, config, allowed)) for f in files]
    bad = sorted([(f, y) for f, y in bad if y], key=lambda x: x[1].endswith("outside the approved file set"))   # F9: no answer lifts these
    if bad:
        stop("drift", "; ".join(y for _, y in bad), path=bad[0][0], files=[f for f, _ in bad])
        print("STOP: repair %s is not committed: %s; the change stays in the work tree and the run asks" % (
            w["n"], "; ".join(y for _, y in bad)))
        return 0
    gone = removed_test_lines(w["base"], files)
    if gone:
        stop("tests", "repair %s removes lines of a test file that existed at the reviewed HEAD: %s" % (
            w["n"], "; ".join(gone[:6])), lines=gone[:20])
        print("STOP: repair %s is not committed: it removes test lines (%s); the run asks" % (w["n"], "; ".join(gone[:3])))
        return 0
    git("add", "-A", "--", *files)
    rc, tree = git("write-tree")
    tree = tree.strip()
    change_state(lambda d: d["repair"].update(token={"parent": head, "tree": tree}))
    slug = r.slug or "run"
    p = subprocess.run(["git"] + id_args() + ["commit", "-q", "-m", "fix(%s): repair %s at %s" % (slug, w["n"], w["stage"])],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    sha = out("rev-parse", "HEAD")

    def clear(d):
        (d.get("repair") or {}).pop("token", None)
    change_state(clear)
    if p.returncode != 0 or sha == head:
        git("reset", "-q")
        why = "the commit hook refused repair %s: %s" % (w["n"], " ".join(p.stdout.decode("utf-8", "replace").split())[:300])
        stop("hook", why)
        print("FAIL: %s" % why, file=sys.stderr)
        return 1
    note_cli_commit(sha)
    lines = diff_lines(w["base"], sha)
    diff = out("diff", "--no-color", w["base"], sha)
    if r.spec and os.path.isdir(r.spec):
        with open(os.path.join(r.spec, "repair-%s.diff" % w["n"]), "w", encoding="utf-8") as f:
            f.write(diff + "\n")
    named = {str(x.get("file")) for x in r.findings() if x["id"] in (w.get("findings") or [])}
    code = [f for f in files if not is_test(f)]
    if w["stage"] == "check" and not code:
        recheck = "none"
    elif lines > LARGE or (w["stage"] == "review" and any(f not in named for f in code)):
        recheck = "full"
    else:
        recheck = "narrow"
    change_state(lambda d: d["repair"].update(commit=sha, tree=out("rev-parse", "HEAD^{tree}"), files=files, lines=lines,
                                              changed=len(files), committed=now(), recheck=recheck))
    snapshot_review()
    print("OK: repair %s committed as %s (%d file(s), %d line(s) changed); the checks run again on the new tree" % (
        w["n"], sha[:7], len(files), lines))
    runs = {}
    for words in (["integrate"], ["gate", "build"]) + ((["check", "run"], ["gate", "check"]) if w["stage"] == "check" else ()):
        rc, text = cli(cli_path, *words)
        runs[" ".join(words)] = rc
        sys.stdout.write(text[-1500:])
    g = load(GATES)
    ok = (load(GROUPS).get("integration") or {}).get("verdict") == "PASS" and (g.get("build") or {}).get("verdict") == "PASS"
    if w["stage"] == "check":
        ok = ok and (g.get("check") or {}).get("verdict") == "PASS"
    change_state(lambda d: d["repair"].update(reruns="passed" if ok else "failed", runs=runs))
    print("OK: the checks ran again on %s: %s; %s" % (sha[:7], "they passed" if ok else "a check failed", {
        "none": "a diff of test files alone needs no recheck: temper repair close", "full": "a full Review reads it",
        "narrow": "a reader that did not write it rechecks the diff"}[recheck]))
    return 0


def mark():
    d = load(STATE)
    w = d.get("repair")
    if not isinstance(w, dict) or not w.get("commit"):
        print("FAIL: no committed repair to recheck", file=sys.stderr)
        return 1
    change_state(lambda d: d["repair"].update(mark={"rows": len(ledger()), "ts": now()}))
    print("OK: the recheck of repair %s is launched: only rows written from now on count" % w["n"])
    return 0


def rows_after(w):
    m = w.get("mark") or {}
    rows = ledger()
    return [(i + 1, x) for i, x in enumerate(rows) if i >= int(m.get("rows") or 0) and isinstance(x, dict)
            and str(x.get("ts") or "") >= str(m.get("ts") or "") and str(x.get("ts") or "") >= str(w.get("committed") or "")]


def broke(w):
    """The rows that passed before the repair and fail now, with what they say."""
    before = set((w.get("before") or {}).get("passed") or [])
    g = load(GATES)
    out_ = []
    for s in ("build", "review", "check"):
        for x in (g.get(s) or {}).get("requirements") or []:
            if isinstance(x, dict) and x.get("pass") is False and "%s:%s" % (s, x.get("name")) in before:
                out_.append("%s: %s" % (x.get("name"), " ".join(str(x.get("detail") or "").split())[:300]))
    if out_:
        try:
            import failure
            lines = [l for x in failure.open_records() for l in x.get("fail_lines") or []]
            if lines:
                out_.append("failing: %s" % " | ".join(lines[:4]))
        except Exception:
            pass
    return out_


def close(r, cli_path):
    d = load(STATE)
    w = d.get("repair")
    if not isinstance(w, dict) or not w.get("commit"):
        print("FAIL: no committed repair to close (temper repair commit makes it)", file=sys.stderr)
        return 1
    need = w.get("recheck") in ("narrow", "full")
    if need and not w.get("mark"):
        print("FAIL: the recheck of repair %s was not launched (no launch mark): nothing is resolved" % w["n"], file=sys.stderr)
        return 1
    after = rows_after(w) if need else []
    verdicts = {}
    for _, x in after:
        m = RECHECK.match(str(x.get("claim") or ""))
        if m:
            verdicts[int(m.group(1))] = m.group(2).lower()
    complete = any(re.search("review completed", str(x.get("claim") or ""), re.I) and x.get("exit_code") == 0 for _, x in after)
    block = [s.strip().lower() for s in re.split(r"[\x1f,\s\[\]]+", r.cfg("review.block-on")) if s.strip()]
    new = [x for _, x in after if str(x.get("severity") or "").lower() in block and not RECHECK.match(str(x.get("claim") or ""))]
    rows = ledger()
    fixed, held = [], []
    for fid in w.get("findings") or []:
        e = rows[fid - 1] if 0 < fid <= len(rows) and isinstance(rows[fid - 1], dict) else {}
        why = None
        if verdicts.get(fid) != "fixed":
            why = "the recheck did not confirm it"
        elif not complete:
            why = "the recheck did not complete"
        elif w.get("reruns") != "passed":
            why = "the checks on the repair tree did not pass"
        elif str(e.get("proof") or "none") == "test":
            ts = [x for x in w.get("tests") or [] if x.get("id") == fid]
            reds = [i for i, x in enumerate(ts) if x.get("phase") == "red" and x.get("ok")]
            greens = [i for i, x in enumerate(ts) if x.get("phase") == "green" and x.get("ok")]
            if not reds or not greens or greens[-1] < reds[0]:
                why = "a behaviour finding needs a RED before the fix and a GREEN after it, on unchanged test files"
        (held if why else fixed).append((fid, why))
    before = int((w.get("before") or {}).get("blocking") or 0)
    left = len(targets(run_of(r.ctx.get("config_file")), w["stage"])) - len(fixed)
    worse = broke(w)
    if w.get("reruns") != "passed" and not worse:
        g = load(GATES)
        worse.append("the checks on the repair tree failed: %s" % "; ".join(
            "%s: %s" % (x.get("name"), " ".join(str(x.get("detail") or "").split())[:240])
            for s in ("build", "check") for x in (g.get(s) or {}).get("requirements") or []
            if isinstance(x, dict) and x.get("pass") is False and (s == "build" or w["stage"] == "check")) or "integrate failed")
    if w["stage"] == "review" and left >= before:
        worse.append("the open blocking findings are not fewer (%d before, %d after)" % (before, max(left, 0)))
    if new:
        worse.append("the recheck names a new blocking finding: %s" % str(new[0].get("claim"))[:200])
    if need and not complete:
        worse.append("the recheck did not complete (no completion row after its launch)")
    if w["stage"] == "check":
        still = [x for x in (w.get("before") or {}).get("failed") or [] if not gate_rows()["check"].get(x, True)]
        if still:
            worse.append("the failed rows still fail: %s" % ", ".join(still))
    answer = ", ".join("#%d %s" % (fid, verdicts.get(fid, "not rechecked")) for fid in w.get("findings") or []) or (
        "no recheck: a diff of test files alone" if not need else "rechecked")
    files = ", ".join(w.get("files") or [])
    claims = "; ".join(str(rows[f - 1].get("claim"))[:120] for f in w.get("findings") or []
                       if 0 < f <= len(rows) and isinstance(rows[f - 1], dict)) or "; ".join(w.get("rows") or [])
    head = "repair %s at %s (%s; files %s, %s lines changed): the recheck: %s" % (
        w["n"], w["stage"].capitalize(), claims, files, w.get("lines"), answer)
    if worse:
        why = "; ".join(worse)
        rule_log(w["stage"], "%s; reverted: %s" % (head, why))
        return revert(r, cli_path, why)
    resolved, kept = [], {}
    if fixed:
        import findings
        sha, bad = findings.fixed_by(w["commit"], STATE, GROUPS)
        if bad:
            print("NOTE: %s" % bad)
        else:
            with Lock():
                rows = ledger()
                for fid, _ in fixed:
                    e = rows[fid - 1]
                    if isinstance(e, dict) and not e.get("resolved") and not e.get("accepted"):
                        e["resolved"] = {"fixed_by": sha, "ts": now(), "recheck": "recheck #%d: fixed" % fid, "repair": w["n"]}
                        resolved.append(fid)
                        kept[str(fid)] = row_key(e)
                save(REVIEW, rows)
    done = ", ".join("#%d" % f for f in resolved)
    change_state(lambda d: close_window(d, "resolved" if resolved and not held else "closed", resolved=resolved,
                                        resolved_rows=kept, held=[[f, y] for f, y in held], recheck_answer=answer, complete=complete or not need))
    rule_log(w["stage"], "%s; %s" % (head, "resolved %s" % done if resolved else "nothing resolved"))
    print("OK: repair %s closed: %s%s" % (w["n"], "resolved %s" % done if resolved else "nothing resolved",
                                         "; open: %s" % "; ".join("#%d (%s)" % (f, y) for f, y in held) if held else ""))
    return 0


def revert(r, cli_path, why="the person reverted it"):
    """The CLI's own commit back to the reviewed tree (a token with the repair commit as parent, through the carve out),
    or, for a repair that was not committed, the work tree back to its base. Then the checks on that tree, the Review
    snapshot again, and the question repair.stop that names what broke."""
    d = load(STATE)
    w = d.get("repair")
    if not isinstance(w, dict):
        print("FAIL: no repair is open to revert", file=sys.stderr)
        return 1
    base_tree = w.get("base_tree")
    if not w.get("commit"):
        kept, config = w.get("keep") or {}, r.ctx.get("config_file")
        # every path changed() names: what git status lists and each guarded file (the spec folder, the config, the git
        # hooks) whose digest moved, a guarded file the fixer created among them (in neither kept nor snap: removed)
        files = [f for f in changed(w, r.spec, config) if not os.path.isabs(f)]
        for f in files:
            if f in kept:   # a file a repair may never change, as it was when the window opened
                os.makedirs(os.path.dirname(f) or ".", exist_ok=True)
                with open(f, "wb") as fh:
                    fh.write(base64.b64decode(kept[f]))
            elif git("cat-file", "-e", "%s:%s" % (w["base"], f))[0] == 0:
                git("checkout", "-q", w["base"], "--", f)
            elif os.path.isfile(f) and f not in (w.get("snap") or {}) and f not in (w.get("dirty") or {}):
                os.remove(f)
        left = changed(w, r.spec, config)
        change_state(lambda d: close_window(d, "reverted", reverted="work tree", why=why))
        stop("worse", "repair %s at %s was taken back before any commit: %s%s" % (
            w["n"], w["stage"].capitalize(), why, "; still not as it was: %s" % ", ".join(left[:6]) if left else ""))
        print("OK: repair %s reverted: the work tree is the reviewed tree again" % w["n"] if not left else
              "STOP: repair %s reverted, but %s still differ from the reviewed tree; the run asks" % (w["n"], ", ".join(left[:6])))
        return 0
    head = out("rev-parse", "HEAD")
    import run_env
    if head != w["commit"] or run_env.tree_key(os.getcwd()) != out("rev-parse", "HEAD^{tree}"):
        why_ = "the revert of repair %s takes back only its own commit on a clean tree: %s" % (w["n"], (
            "HEAD %s is not the repair commit %s" % (head[:7], w["commit"][:7]) if head != w["commit"] else "the tree is dirty"))
        stop("moved", why_)
        print("FAIL: %s" % why_, file=sys.stderr)
        return 1
    git("read-tree", "--reset", "-u", base_tree)
    change_state(lambda d: d["repair"].update(token={"parent": head, "tree": base_tree}))
    p = subprocess.run(["git"] + id_args() + ["commit", "-q", "--allow-empty", "-m",
                       "revert(%s): repair %s at %s" % (r.slug or "run", w["n"], w["stage"])],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    sha = out("rev-parse", "HEAD")
    change_state(lambda d: (d.get("repair") or {}).pop("token", None))
    if p.returncode != 0 or sha == head or out("rev-parse", "HEAD^{tree}") != base_tree:
        stop("hook", "the revert of repair %s did not land: %s" % (w["n"], " ".join(p.stdout.decode("utf-8", "replace").split())[:300]))
        print("FAIL: the revert of repair %s did not land" % w["n"], file=sys.stderr)
        return 1
    note_cli_commit(sha)
    change_state(lambda d: close_window(d, "reverted", reverted=sha, why=why))
    snapshot_review()
    for words in (["integrate"], ["gate", "build"]) + ((["check", "run"], ["gate", "check"]) if w["stage"] == "check" else ()):
        cli(cli_path, *words)
    stop("worse", "repair %s at %s was reverted: %s" % (w["n"], w["stage"].capitalize(), why))
    print("OK: repair %s reverted by %s: the tree is the reviewed tree again (%s)" % (w["n"], sha[:7], why))
    return 0


def carve():
    """The commit gate's carve out (ADR 0009 amended by ADR 0021): the one commit of a repair window passes with the row
    `repair commit` when the token is set, HEAD is its parent, the staged tree is its tree, the run is at Review or Check
    on its own branch, and every staged file is approved or a test (or the revert's, back to the reviewed tree). Exit 1
    when it does not apply: the whole gate runs."""
    d = load(STATE)
    w = d.get("repair") if isinstance(d.get("repair"), dict) else {}
    tok = w.get("token") if isinstance(w.get("token"), dict) else None
    if not tok or d.get("next_stage") not in STAGES or d.get("command", "temper") != "temper":
        return 1
    if not d.get("branch") or out("rev-parse", "--abbrev-ref", "HEAD") != d.get("branch"):
        return 1
    if out("rev-parse", "HEAD") != tok.get("parent") or out("write-tree") != tok.get("tree"):
        return 1
    staged = staged_files()
    if not w.get("commit"):
        r = run_of(None)
        allowed = allowed_files(r)
        if any(f not in allowed and not is_test(f, gate=True) for f in staged):
            return 1
    elif tok.get("tree") != w.get("base_tree"):
        return 1
    print(json.dumps([{"name": "repair commit", "pass": True,
                       "detail": "the CLI's own commit of repair %s at %s: %d staged file(s), the tree it wrote" % (
                           w.get("n"), d.get("next_stage"), len(staged))}]))
    return 0


def closed_chain(state, frm, to):
    """True when the tree `to` follows from `frm` by repair commits the CLI recorded, whose checks ran again and whose
    recheck completed (or that needed none): the commit gate's tree row reads it (ADR 0021)."""
    seen, cur = set(), frm
    reps = [x for x in state.get("repairs") or [] if isinstance(x, dict) and x.get("commit")]
    while cur != to and cur not in seen:
        seen.add(cur)
        nxt = next((x for x in reps if x.get("base_tree") == cur and x.get("outcome") in ("resolved", "closed")
                    and x.get("reruns") == "passed" and (x.get("complete") or x.get("recheck") == "none")), None)
        if nxt is None:
            return False
        cur = nxt.get("tree")
    return cur == to


def row_key(e):
    """What names one finding row whatever its id: its claim, severity, file and time (a later round can reuse the id)."""
    return hashlib.sha256(json.dumps([e.get(k) for k in ("claim", "severity", "file", "ts")]).encode()).hexdigest()[:16]


def recheck_after(state, sha, fid=None):
    """WP18's fifth condition of `evidence resolve`: the commit is one the CLI recorded as its repair, and a recheck row was
    written after it (in the ledger, or the repair was closed with its recheck complete). A hand resolve names its finding
    (fid): only `repair close` resolves one, so it takes no finding while the repair is open, and after the close only one
    the close resolved (rule 8)."""
    w = [x for x in (state.get("repairs") or []) + [state.get("repair") or {}] if isinstance(x, dict) and x.get("commit") == sha]
    if not w:
        return "commit %s is not one the CLI recorded as its repair" % sha[:7]
    if fid is not None and fid not in (w[-1].get("resolved") or []):
        return "repair close resolves a finding by its repair commit %s, for what its recheck confirmed, and it did not resolve #%s" % (
            sha[:7], fid)
    # adversarial review R8b: the id must still name the row the close resolved, not a finding of a later Review round
    # that took the same id after a step back emptied the ledger
    kept = w[-1].get("resolved_rows") if isinstance(w[-1].get("resolved_rows"), dict) else None
    if fid is not None and kept is not None:
        rows = ledger()
        e = rows[fid - 1] if 0 < fid <= len(rows) and isinstance(rows[fid - 1], dict) else {}
        if kept.get(str(fid)) != row_key(e):
            return "finding #%s is not the row repair %s resolved: a finding of a later Review is resolved only by its own repair" % (
                fid, w[-1].get("n"))
    if w[-1].get("closed") or w[-1].get("outcome") in ("resolved", "closed"):
        return None if w[-1].get("complete") and w[-1].get("outcome") in ("resolved", "closed") else (
            "repair commit %s was closed with no completed recheck" % sha[:7])
    t = str(w[-1].get("committed") or "")
    if not any(isinstance(x, dict) and RECHECK.match(str(x.get("claim") or "")) and str(x.get("ts") or "") >= t for x in ledger()):
        return "no recheck row follows repair commit %s" % sha[:7]
    return None


def status():
    d = load(STATE)
    print(json.dumps({"repair": {k: v for k, v in (d.get("repair") or {}).items() if k not in ("snap", "keep")} or None,
                      "repairs": d.get("repairs") or [], "stop": d.get("repair_stop")}, indent=1))
    return 0


def main(argv):
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    cli_path, config, word, rest = argv[1], argv[2], argv[3], argv[4:]
    if word == "carve":
        return carve()
    if word == "status":
        return status()
    if word == "test":
        return test(rest)
    if word == "answer":   # `temper evidence add` of a Scope drift answer: the question it answers (answer_of)
        try:
            print(answer_of(" ".join(rest)))
            return 0
        except ValueError as e:
            print("FAIL: %s" % e, file=sys.stderr)
            return 1
    r = run_of(config)
    if not r.active:
        print("FAIL: no active run (temper state init first)", file=sys.stderr)
        return 1
    if word == "start":
        stage = rest[rest.index("--stage") + 1] if "--stage" in rest and rest.index("--stage") + 1 < len(rest) else ""
        return start(r, stage, "--again" in rest)
    if word == "commit":
        return commit(r, cli_path)
    if word == "mark":
        return mark()
    if word == "close":
        return close(r, cli_path)
    if word == "revert":
        return revert(r, cli_path, "the person chose Revert the repair")
    print("FAIL: usage: temper repair start --stage review|check [--again] | test ID --phase red|green -- CMD | commit | "
          "mark | close | revert | status", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
