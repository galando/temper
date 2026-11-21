"""defaults.py: every setting of .claude/temper.config, its default and its reader, in one table (WP29, ADR 0023).

A new project's config holds about 10 live lines (templates/temper.config.default); every other setting has its
default here, and `temper config show` prints each key, its value and where the value comes from.

  KEYS    {dot path: (default, literal, meaning)}: the default a reader gets when the config does not set the key; the
          literal a reader is found by in the CLI's scripts (scripts/check_config_keys.py proves each has one); one line
          of meaning. A path with <agent> stands for each agent of the table of models of scripts/cli_ctx.py.
  OLD     {dot path: [(value, version)]}: values an earlier template shipped as live lines, retired at that version. The
          one time question (config.tidy, scripts/config_tidy.py) offers to remove a line that only repeats one.
  GONE    {dot path: (replacement, meaning, version)}: a key no longer read. A replacement is a key the value moves to
          (`config tidy --apply`) and that `config get` reads under the old name while the new one is absent; the one
          exception is autonomy.enabled, whose false reads as run.default: ask. An empty replacement: the line goes.

Pure data: no import, so config_yaml.py reads it without a cycle. Standard library only.
"""

VERSION = "9.8.5"

KEYS = {
    "run.default": ("to-commit", "run.default",
                    "the approval's first option: to-commit (the run goes on by itself to the commit), ask, or "
                    "never-unattended"),
    "packs": (["security", "tdd"], "^packs:",
              "the packs whose rules the agents follow; the CLI names their files in each prompt (`temper packs`)"),
    "review.block-on": (["critical", "high"], "review.block-on", "the finding levels that fail the Review gate"),
    "autonomy.park-on-touch": (["**/auth/**", "**/payment/**", "**/billing/**"], "autonomy.park-on-touch",
                               "sensitive paths: a plan that touches one is risk H, named at the approval, and nothing "
                               "there is repaired by rule"),
    "models.plan": ("opus", "models.", "the planner's model, over the table of `scripts/cli_ctx.py`"),
    "models.task": ("sonnet", "models.", "the model of the Build task agents; haiku costs less and takes longer"),
    "models.<agent>": ("the table", "models.", "the model of one agent, over the table of `scripts/cli_ctx.py`"),
    "models.high.<agent>": ("the table", "models.high.", "the model of one agent in a run of tier complex or risk H"),
    "check.commands.test": ("", "check.commands.test", "the test command Check runs instead of the one it detects"),
    "check.commands.coverage": ("", "check.commands.coverage", "the coverage command Check runs instead of the one it "
                                "detects"),
    "check.coverage-threshold": ("", "check.coverage-threshold", "a coverage floor, read only when set; with none, "
                                 "coverage may not drop against the base"),
    "setup.run": ("", "get('run'", "one shell line the CLI runs before each command it runs"),
    "setup.env": ("", "get('env')", "variables set for each command; a credential name is never set or shown"),
    "setup.services": ("", "get('services')", "services that must answer (name: host:port) before the checks run"),
    "setup.tools": ("", "get('tools')", "programs the commands need"),
    "build.grouped.max-parallel": (4, "build.grouped.max-parallel", "Build tasks running at once"),
    "build.grouped.max-groups": (2, "build.grouped.max-groups", "groups working at once"),
    "build.grouped.keep-days": (30, "build.grouped.keep-days", "days an earlier attempt's work is kept (0: always)"),
    "build.red-before-code": (False, "build.red-before-code", "true: a task's failing run counts only on the code as "
                              "the attempt found it, with no stub"),
    "autonomy.max-blast-radius": (15, "autonomy.max-blast-radius", "the plan gate splits a group that declares more "
                                  "files than this"),
    "budget.per-failure": (2, "budget.per-failure", "repeats for one failed check"),
    "budget.per-run": (6, "budget.per-run", "repeats in one run"),
    "plan.context-check": ("auto", "plan.context-check", "auto: ask when the Context Map has an ignore or a gap; "
                           "always; off"),
    "plan.fresh-review": ("ask", "plan.fresh-review", "a reader with no context reads the plan: ask, auto, always or "
                          "off"),
    "plan.fresh-review-twice": (True, "plan.fresh-review-twice", "a risk H plan gets two fresh readers"),
    "plan.fresh-review-rounds": (3, "plan.fresh-review-rounds", "launches of the fresh review in one run, at most"),
    "phases.pipeline": (True, "phases.pipeline", "false: no Pipeline stage after a commit that opened a pull request"),
    "protect.paths": ("", "protect.paths", "paths no agent edit may change (the guardrails pack)"),
    "format.cmd": ("", "format.cmd", "a formatter run on each agent edit, {file} for the file (the guardrails pack)"),
    "upgrade.asked": ("", "upgrade.asked", "the version whose one time config question was answered Keep my file"),
}

# The values the templates of 9.8.4 (7c7a1c1) and of the base (10e965a) shipped as live lines that are no default now,
# or that only repeat one. A value the new template states itself (block-on [critical, high], park-on-touch) is no line
# to remove: it is the template's own.
OLD = {
    "packs": [(["quality", "tdd", "security", "git", "performance"], VERSION)],
    "review.block-on": [(["critical"], VERSION)],
    "check.coverage-threshold": [(80, VERSION)],
    "plan.context-check": [("auto", VERSION)],
    "plan.fresh-review": [("ask", VERSION)],
    "plan.fresh-review-twice": [(True, VERSION)],
    "plan.fresh-review-rounds": [(3, VERSION)],
    "phases.pipeline": [(True, VERSION)],
    "autonomy.max-blast-radius": [(15, VERSION)],
}

GONE = {
    "autonomy.enabled": ("run.default", "false reads as run.default: ask, and stays ask", VERSION),
    "build.grouped.task-model": ("models.task", "read as models.task", VERSION),
    "build.grouped.escalation-model": ("models.task-escalation", "read as models.task-escalation", VERSION),
    "stack": ("", "the CLI detects the stack", VERSION),
    "tools.mode": ("", "an agent uses a connected tool when there is one", VERSION),
    "tools.ocr.timeout": ("", "never read", VERSION),
    "tools.ocr.replace-defect-subagent": ("", "never read", VERSION),
    "tools.label-findings": ("", "never read", VERSION),
    "phases.design": ("", "Design runs only when you ask for it", VERSION),
    "feedback.enabled": ("", "one budget of repeats counts every loop back", VERSION),
    "loops.max-per-type": ("", "one budget of repeats (budget.per-failure)", VERSION),
    "fix.max-loops": ("", "one budget of repeats", VERSION),
    "autonomy.policy": ("", "run.default chooses the run", VERSION),
    "autonomy.budget.max-total-loops": ("", "one budget of repeats (budget.per-run)", VERSION),
    "autonomy.budget.max-stages": ("", "one budget of repeats (budget.per-run)", VERSION),
    "plan.preflight-timeout": ("", "the plan's commands run once on the base", VERSION),
    "plan.preflight-skip": ("", "the plan's commands run once on the base", VERSION),
    "plan.default-depth": ("", "never read", VERSION),
    "check.mutation-threshold": ("", "the planted bug score is information", VERSION),
    "check.environment": ("", "Check decides from file names", VERSION),
    "check.live-scenarios": ("", "never read", VERSION),
    "check.debt-tracking": ("", "never read", VERSION),
    "review.confidence-threshold": ("", "never read", VERSION),
    "review.auto-fix": ("", "a finding is repaired in its stage", VERSION),
    "branch.pattern": ("", "never read", VERSION),
    "branch.commit-style": ("", "never read", VERSION),
    # WP30: each with its reader
    "evidence.claimed-runs": ("", "a run an agent only claimed counts at no gate", VERSION),
    "tools.ocr.mode": ("", "the external review engine is gone", VERSION),
    "bands.window": ("", "the control bands are gone", VERSION),
    "bands.min-points": ("", "the control bands are gone", VERSION),
    "bands.drift-run": ("", "the control bands are gone", VERSION),
    "bands.metrics": ("", "the control bands are gone", VERSION),
    "bands.tiers.1sigma": ("", "the control bands are gone", VERSION),
    "bands.tiers.2sigma": ("", "the control bands are gone", VERSION),
    "bands.tiers.3sigma": ("", "the control bands are gone", VERSION),
}

# The old names `config get` still reads: a key moved to its replacement (autonomy.enabled is read by its own rule).
RENAMED = {new: old for old, (new, _m, _v) in GONE.items() if new and old != "autonomy.enabled"}


def default(path):
    """The table's default of a dot path, or None when the table has no such key."""
    e = KEYS.get(path)
    return None if e is None else e[0]
