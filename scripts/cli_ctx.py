"""cli_ctx.py: the facts only the CLI knows, and `temper next`, in one Python process.

  python3 cli_ctx.py next --plugin DIR --cli PATH --config-file FILE --now TS --run-files "A B ..."
  python3 cli_ctx.py models --plugin DIR --config-file FILE [--state-file FILE] [--source] [--all | NAME]
                                                                               (WP27: the table of models, by agent and
                                                                               class, with the config keys over it)
  python3 cli_ctx.py packs --plugin DIR --config-file FILE --stage S   (WP29: the pack files of a stage's agent)
  python3 cli_ctx.py view --plugin DIR --cli PATH --config-file FILE --now TS   (9.8.0: the view every other command
                                                                               writes, with the models `next` resolves)

`temper next` used to start a shell for each stage's model, one for each setup check, and two Python
processes (the action, then the view). It starts one now: the models and the setup calls are worked out
here, the action is printed, and .temper/view.json is written from the same process. The output is the
same, byte for byte (a self test case compares both for every view fixture state). Standard library only.
"""
import json
import os
import re
import subprocess
import sys

import config_yaml

# WP27: one table of the models every agent of a run is launched on, by its class: `standard`, or `high` for a run of tier
# complex or of risk H (risky). The two columns are equal on purpose: the planner stays on Opus until a bench round says
# otherwise (decision 4 of docs/plans/one-go/README.md section 3), and the `high` column is what lets that round, or a
# person, set a cheaper planner below risk H and keep Opus at risk H. After WP27 the table has one writer: the bench block
# of WP32. `task` is a Build task agent (agents/build-task.md), `task-escalation` its attempt after the second.
AGENTS = ["intent", "plan", "plan-revise", "plan-review", "design", "acceptance", "build", "review", "check", "pipeline",
          "rca", "fix", "task", "task-escalation"]
TABLE = {a: ("opus", "opus") if a in ("plan", "design", "rca") else ("sonnet", "sonnet") for a in AGENTS}
OLD_KEYS = {"task": "build.grouped.task-model", "task-escalation": "build.grouped.escalation-model"}   # still read


def risky(state):
    """The class of a run is `high` when its tier is complex or its risk is H (9.8.4 measured a complex run that built 12
    tasks on haiku five times, each passing its own gate). The first planner launch has neither yet: it is `standard`."""
    return isinstance(state, dict) and (str(state.get("complexity") or "").lower() == "complex"
                                        or str(state.get("risk") or "").upper() == "H")


def risky_run(state_file=os.path.join(".temper", "build-state.json")):
    try:
        with open(state_file, encoding="utf-8") as fh:
            return risky(json.load(fh))
    except (OSError, ValueError):
        return False


def resolve(plugin, cfg, state=None, state_file=os.path.join(".temper", "build-state.json")):
    """{name: (model, source)} for every agent of the table, in its order. In this order: models.high.<agent> when the
    class is high; models.<agent>; for task and task-escalation the old keys build.grouped.task-model and
    build.grouped.escalation-model; the table. source is `config` or `table`. The plugin folder is not read: no brief
    holds a default of its own (every brief's model line equals the table's standard value, a case checks it)."""
    high = risky(state) if state is not None else risky_run(state_file)
    out = {}
    for a in AGENTS:
        keys = (["models.high." + a] if high else []) + ["models." + a] + ([OLD_KEYS[a]] if a in OLD_KEYS else [])
        over = next((str(v) for v in (config_yaml.get(cfg, k, "") for k in keys) if v and not isinstance(v, dict)), "")
        out[a] = (over, "config") if over else (TABLE[a][1 if high else 0], "table")
    return out


# WP29: the stages whose agent follows packs; Plan also takes the packs of Build (reference/plan.md)
PACK_STAGES = ("plan", "design", "build", "review", "check", "rca", "fix")


def packs(plugin, config_file, stage):
    """([rules file], [entry as written]) of the packs of the config (the table's [security, tdd] with no `packs:` line)
    that apply at the stage: the project's .claude/packs/<name>/rules.md when it exists, else the plugin's; kept when the
    file's `phases:` is all, is absent or holds the stage (`phases: []` is no stage: the guardrails pack). Nothing in the
    home folder is read. An entry in braces (a link, a phases list) is handed on as written; reference/pack.md says what
    an agent does with it."""
    if stage not in PACK_STAGES:
        return [], []
    try:
        with open(config_file, encoding="utf-8") as f:
            text = [x.split(" #", 1)[0].rstrip() for x in f.read().splitlines()]
    except OSError:
        text = []
    at = next((i for i, x in enumerate(text) if re.match(r"^packs:", x)), None)
    raw = text[at].partition(":")[2].strip() if at is not None else ""
    names = []
    if raw.startswith("[") and raw.endswith("]"):
        names = [x.strip() for x in re.findall(r"\s*(\{[^}]*\}|[^,]+)", raw[1:-1]) if x.strip()]
    elif raw:
        names = [raw]
    elif at is not None:   # a block list (reference/pack.md): `- name`, or `- name: x` with its keys, as one entry
        names = ["{ %s }" % n if ":" in n and not n.startswith("{") else n for n in config_yaml.block_list(text[at + 1:])]
    if at is None:
        names = [str(x) for x in config_yaml.get({}, "packs").split("\x1f") if x]
    want = (stage, "build") if stage == "plan" else (stage,)
    files, entries = [], []
    for n in names:
        if n.startswith("{"):
            entries.append(n)
            continue
        n = n.strip("\"'")
        mine = os.path.join(".claude", "packs", n, "rules.md")
        path = mine if os.path.isfile(mine) else os.path.join(plugin, "packs", n, "rules.md")
        try:
            with open(path, encoding="utf-8") as f:
                head = f.read(2000)
        except OSError:
            continue
        m = re.search(r"(?m)^phases:[ \t]*(.*)$", head.split("\n---", 1)[0] if head.startswith("---") else "")
        ph = m.group(1).strip().strip("[]").replace(",", " ").split() if m else ["all"]   # `phases: []`: no stage
        if "all" in ph or any(s in ph for s in want):
            files.append(path)
    return files, entries


def git_out(*args):
    try:
        r = subprocess.run(["git"] + list(args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def excludes_current(run_files):
    """True when the clone's info/exclude lists every run file init writes (or this is no git repository)."""
    common = git_out("rev-parse", "--git-common-dir")
    if not common:
        return True
    prefix = git_out("rev-parse", "--show-prefix") or ""
    pre = re.sub(r"([\[\]\\*?])", r"\\\1", prefix)
    try:
        with open(os.path.join(common, "info", "exclude"), encoding="utf-8", errors="replace") as f:
            have = set(f.read().splitlines())
    except OSError:
        have = set()
    want = ["/%s.temper/%s" % (pre, p) for p in run_files.split()] + ["/%s.claude/worktrees/" % pre]
    return all(w in have for w in want)


def setup_calls(plugin, config_file, run_files):
    """The setup a project still lacks, as the calls that make it, one per entry (the same checks the shell made)."""
    calls = []
    if not os.path.isfile(config_file):
        calls.append("%s/scripts/temper config init" % plugin)
    if not (os.path.isdir(os.path.join(os.getcwd(), ".temper")) and excludes_current(run_files)):
        calls.append("%s/scripts/temper init" % plugin)
    if git_out("rev-parse", "--git-dir") is None:
        return calls
    hdir = git_out("rev-parse", "--git-path", "hooks") or ""
    hook = hdir + "/pre-commit"
    ok = hook.endswith("/temper-gate/pre-commit") and os.path.isfile(hook)
    if ok:
        try:
            with open(hook, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            text = ""
        second = text.split("\n")[1] if text.count("\n") >= 1 else ""
        ok = (second.startswith("# Temper native pre-commit hook") and plugin + "/scripts/temper" in text
              and '"--cached", "--name-only", "--no-renames"' in text and "python3 -I " in text
              and "gate commit --from-hook" in text)
    if not ok:
        calls.append("%s/scripts/temper guards install" % plugin)
    return calls


def option(argv, name, default=""):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default


def main(argv):
    if len(argv) < 2 or argv[1] not in ("next", "models", "view", "packs"):
        print(__doc__, file=sys.stderr)
        return 2
    plugin = option(argv, "--plugin")
    config_file = option(argv, "--config-file")
    if argv[1] == "packs":   # WP29: `temper packs --stage S`, the pack files an agent of that stage reads
        stage = option(argv, "--stage")
        if stage not in PACK_STAGES + ("intent",):
            print("FAIL: usage: temper packs --stage <%s>" % "|".join(PACK_STAGES), file=sys.stderr)
            return 1
        files, entries = packs(plugin, config_file, stage)
        print("\n".join(files + ["Pack entries: %s" % ", ".join(entries)] * bool(entries)) or "no pack applies at %s" % stage)
        return 0
    cfg = config_yaml.load(config_file)
    found = resolve(plugin, cfg, state_file=option(argv, "--state-file") or os.path.join(".temper", "build-state.json"))
    if argv[1] == "models":   # `temper model`: one agent's model, or every line (with its source)
        names = [x for i, x in enumerate(argv[2:], 2) if not x.startswith("--") and argv[i - 1] not in (
            "--plugin", "--config-file", "--state-file")]
        if names and names[0] not in found:
            print("FAIL: unknown agent '%s' (one of: %s, or --all)" % (names[0], " ".join(AGENTS)), file=sys.stderr)
            return 1
        for name, (model, source) in found.items():
            if not names or name == names[0]:
                print("%s%s%s" % ("" if names else name + "=", model, " (%s)" % source if "--source" in argv else ""))
        return 0
    import flow
    models = {k: v[0] for k, v in found.items()}
    if argv[1] == "view":
        # 9.8.0: the view every other command writes, with the same models `next` resolves. Before, it was written without
        # them, so a Build task's prompt in the view named its model as `haiku` where `next` named `claude-haiku-5-5`, and
        # the mod refused the launch of the agent `next` had named.
        flow.run_view({"plugin": plugin, "cli": option(argv, "--cli"), "config_file": config_file, "now": option(argv, "--now"),
                       "models": models, "task_model": models.get("task", ""), "escalation_model": models.get("task-escalation", "")})
        return 0
    import notice   # WP31: the one time notice, said in front of the say of the first next of an older project
    ctx = {"plugin": plugin, "cli": option(argv, "--cli"), "config_file": config_file, "models": models,
           "task_model": models.get("task", ""), "escalation_model": models.get("task-escalation", ""),
           "now": option(argv, "--now"), "setup": setup_calls(plugin, config_file, option(argv, "--run-files"))}
    ctx["notice"] = notice.take(ctx["now"])
    print(flow.run_next(ctx))
    flow.run_view({"plugin": plugin, "cli": ctx["cli"], "config_file": config_file, "now": ctx["now"], "models": models,
                   "task_model": ctx["task_model"], "escalation_model": ctx["escalation_model"], "asked": True,
                   "notice": ctx["notice"]})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
