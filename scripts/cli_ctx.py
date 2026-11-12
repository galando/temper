"""cli_ctx.py: the facts only the CLI knows, and `temper next`, in one Python process.

  python3 cli_ctx.py next --plugin DIR --cli PATH --config-file FILE --now TS --run-files "A B ..."
  python3 cli_ctx.py models --plugin DIR --config-file FILE [--source]
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

AGENT_STAGES = ["intent", "plan", "design", "build", "review", "check", "pipeline", "rca", "fix"]
TASK_DEFAULT = "claude-haiku-5-5"
ESCALATION_DEFAULT = "sonnet"
RISK_TASK_MODEL = "sonnet"   # 9.8.4: the task model of a complex or risk H plan (the same as the CLI's _resolve_task_model)


def frontmatter_model(path):
    """The `model:` line of a brief's frontmatter, or ''."""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except (OSError, UnicodeDecodeError):
        return ""
    fences = 0
    for line in lines:
        if re.match(r"^---\s*$", line):
            fences += 1
            if fences == 2:
                break
            continue
        if fences == 1 and line.startswith("model:"):
            return line[len("model:"):].strip()
    return ""


def risky_run(state_file=os.path.join(".temper", "build-state.json")):
    """9.8.4: the active run's plan is complex or rated risk H. Its tasks are built on RISK_TASK_MODEL unless the config
    names a task model: a measured complex run built 12 tasks on haiku five times, each passing its own gate."""
    try:
        with open(state_file, encoding="utf-8") as fh:
            st = json.load(fh)
    except (OSError, ValueError):
        return False
    return isinstance(st, dict) and (str(st.get("complexity") or "").lower() == "complex" or str(st.get("risk") or "").upper() == "H")


def resolve(plugin, cfg):
    """{name: (model, source)} for every stage, the task and its escalation. source is `config` (an override in
    .claude/temper.config) or `brief` (the model: line of the stage's own brief); a stage with no model is left out."""
    out = {}
    for s in AGENT_STAGES:
        over = str(config_yaml.get(cfg, "models." + s, "") or "")
        if over:
            out[s] = (over, "config")
            continue
        m = frontmatter_model(os.path.join(plugin, "agents", s + ".md"))
        if m:
            out[s] = (m, "brief")
    over = str(config_yaml.get(cfg, "build.grouped.task-model", "") or "")
    if over:
        out["task"] = (over, "config")
    elif risky_run():
        out["task"] = (RISK_TASK_MODEL, "risk")
    else:
        m = frontmatter_model(os.path.join(plugin, "agents", "build-task.md"))
        out["task"] = (m, "brief") if m else (TASK_DEFAULT, "default")
    over = str(config_yaml.get(cfg, "build.grouped.escalation-model", "") or "")
    out["task-escalation"] = (over, "config") if over else (ESCALATION_DEFAULT, "default")
    return out


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
    if len(argv) < 2 or argv[1] not in ("next", "models", "view"):
        print(__doc__, file=sys.stderr)
        return 2
    plugin = option(argv, "--plugin")
    config_file = option(argv, "--config-file")
    cfg = config_yaml.load(config_file)
    found = resolve(plugin, cfg)
    if argv[1] == "models":
        for name, (model, source) in found.items():
            print("%s=%s%s" % (name, model, " (%s)" % source if "--source" in argv else ""))
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
    ctx = {"plugin": plugin, "cli": option(argv, "--cli"), "config_file": config_file, "models": models,
           "task_model": models.get("task", ""), "escalation_model": models.get("task-escalation", ""),
           "now": option(argv, "--now"), "setup": setup_calls(plugin, config_file, option(argv, "--run-files"))}
    print(flow.run_next(ctx))
    flow.run_view({"plugin": plugin, "cli": ctx["cli"], "config_file": config_file, "now": ctx["now"], "models": models,
                   "task_model": ctx["task_model"], "escalation_model": ctx["escalation_model"]})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
