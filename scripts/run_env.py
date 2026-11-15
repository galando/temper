"""run_env.py: how the CLI runs a command of a grouped Build (a task's test, a scenario's Test: command, a group's Validate
command, the integration suite).

  run_env.test_env(cwd)      the environment: this one, without the variables whose names say they hold a credential,
                             and with the folder the command runs in first on PYTHONPATH
  run_env.run_cmd(wt, timeout, cmd)   run cmd in wt (one string runs through bash -c), killing it at the timeout

A credential is no input of a test: a key, a token, a secret, a password or passphrase, credentials, an auth socket or
helper are left out; every other variable passes as it is, and git's GIT_CONFIG_COUNT, GIT_CONFIG_KEY_n and GIT_CONFIG_VALUE_n
pass together. PYTHONPATH puts the folder first so a package importable from
both the project root (an editable install) and the task's worktree resolves to the worktree's copy; other languages
ignore it.

  run_env.load_setup(config=None)   the setup block of .claude/temper.config ($TEMPER_SETUP_CONFIG, which the CLI sets, else
                             $TEMPER_CONFIG, else ./.claude/temper.config):
                             {} without one, else {'run', 'env', 'services', 'tools', 'dropped'}

The setup block (setup: run: <one shell line>, env:, services:, tools:) is the project's environment contract: run_cmd
runs the line in the same shell before the command (so its exports reach it), prints `temper-setup: OK`, and adds env.
A failing line prints `temper-setup: FAIL (exit N)` and exits 125 without running the command. A variable of env whose
name says it holds a credential is never set; it is listed in `dropped`. Without a block, nothing changes.
Standard library only.
"""
import os
import re
import signal
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import config_yaml  # noqa: E402

CREDENTIAL_NAME = re.compile(r'PASSWORD|PASSWD|PASSPHRASE|CREDENTIAL|APIKEY|ASKPASS|(?:^|_)(?:KEYS?|TOKENS?|SECRETS?|AUTH|PAT)(?:_|$)')
CREDENTIAL_NAMES = {'GPG_AGENT_INFO', 'GNUPGHOME', 'KRB5CCNAME'}
# git's own configuration through the environment: GIT_CONFIG_COUNT and its GIT_CONFIG_KEY_n and GIT_CONFIG_VALUE_n pairs.
# They pass whole or not at all: "_KEY_" reads as a credential above, and a count whose keys are gone makes every git call
# fail with "unable to parse command-line config" (9.8.4: Claude Code cloud sessions configure git this way).
# When one of its keys carries a credential (an extra header, a helper, a password or token), the family is left out whole.
GIT_CONFIG_FAMILY = re.compile(r'^GIT_CONFIG_(?:COUNT|KEY_\d+|VALUE_\d+)$')
GIT_CONFIG_SECRET_KEY = re.compile(r'extraheader|helper|password|passwd|token|secret|askpass', re.I)


def test_env(cwd=None):
    family = {k: v for k, v in os.environ.items() if GIT_CONFIG_FAMILY.match(k)}
    if any(GIT_CONFIG_SECRET_KEY.search(v) for k, v in family.items() if k.startswith('GIT_CONFIG_KEY_')):
        family = {}
    env = {k: v for k, v in os.environ.items()
           if not GIT_CONFIG_FAMILY.match(k) and k != 'TEMPER_SETUP_CONFIG' and not CREDENTIAL_NAME.search(k.upper()) and k.upper() not in CREDENTIAL_NAMES}
    env.update(family)
    if cwd:
        old = env.get('PYTHONPATH')
        env['PYTHONPATH'] = os.path.abspath(cwd) + (os.pathsep + old if old else '')
    return env


# 9.8.5 (Q6): text a JVM or a runtime prints at its start, which says nothing about the run (a row's detail once was
# `ng.disabledSchemes= WARNING: A terminally deprecated method in sun.misc.Unsafe has been called`)
BANNER = re.compile(r"^(?:NOTE: )?Picked up (?:JAVA_TOOL_OPTIONS|_JAVA_OPTIONS|JDK_JAVA_OPTIONS):|^WARNING: (?:A terminally deprecated method|"
                    r"sun\.misc\.Unsafe|Please consider reporting this|A restricted method|Use --enable-native-access|"
                    r"Restricted methods will be blocked|.*will be removed in a future release|An illegal reflective access|"
                    r"Illegal reflective access|All illegal access operations)")


def strip_banner(text):
    return "\n".join(l for l in text.split("\n") if not BANNER.search(l.strip()))


def is_credential(name):
    return bool(CREDENTIAL_NAME.search(name.upper())) or name.upper() in CREDENTIAL_NAMES


def _yaml_text(v):
    return ('true' if v else 'false') if isinstance(v, bool) else str(v)


def load_setup(config=None):
    path = (config or os.environ.get('TEMPER_SETUP_CONFIG') or os.environ.get('TEMPER_CONFIG')
            or os.path.join('.claude', 'temper.config'))
    blk = config_yaml.load(path).get('setup')
    if not isinstance(blk, dict) or not blk:
        return {}
    env, dropped = {}, []
    for k, v in (blk.get('env') if isinstance(blk.get('env'), dict) else {}).items():
        if is_credential(k):
            dropped.append(k)
        else:
            env[k] = _yaml_text(v)
    services = blk.get('services') if isinstance(blk.get('services'), dict) else {}
    tools = blk.get('tools') if isinstance(blk.get('tools'), list) else []
    run = blk.get('run', '')
    return {'run': _yaml_text(run) if run not in ('', None) else '', 'env': env,
            'services': {k: _yaml_text(v) for k, v in services.items()}, 'tools': [str(t) for t in tools],
            'dropped': dropped}


def mask(text):
    """The run line as shown to an agent or a person: a NAME=value whose NAME is a credential reads NAME=<left out>."""
    return re.sub(r'\b([A-Za-z_]\w*)=(\S+)', lambda m: m.group(1) + '=<left out>' if is_credential(m.group(1)) else m.group(0),
                  text or '')


# The run line runs in the same bash as the command. The EXIT trap turns any end of the line that is not a success (an
# `exit 3` in it, or a non-zero last status) into `temper-setup: FAIL (exit N)` and exit 125, so the command never runs.
SETUP_SCRIPT = ('__temper_ok=0; trap \'__rc=$?; [ "$__temper_ok" = 1 ] || { echo "temper-setup: FAIL (exit $__rc)"; exit 125; }\' EXIT\n'
                '%s\n'
                '__rc=$?; [ "$__rc" = 0 ] || exit "$__rc"\n'
                '__temper_ok=1; trap - EXIT; echo "temper-setup: OK"\n')


def setup_args(cmd, setup):
    """(args, extra env) for cmd under the setup block."""
    if not setup:
        return (['bash', '-c', cmd[0]] if len(cmd) == 1 else cmd), {}
    extra = dict(setup.get('env') or {})
    pre = SETUP_SCRIPT % setup['run'] if setup.get('run') else ''
    if len(cmd) == 1:
        return ['bash', '-c', pre + cmd[0]], extra
    return ['bash', '-c', pre + 'exec "$@"', 'temper-setup'] + list(cmd), extra


def run_cmd(wt, timeout, cmd, setup=None):
    """Returns (output bytes, exit). 124 is a timeout, 127 a command that could not start, 125 a failed setup line."""
    if setup is None:
        setup = load_setup()
    args, extra = setup_args(cmd, setup)
    env = test_env(wt)
    env.update(extra)
    try:
        p = subprocess.Popen(args, cwd=wt, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             start_new_session=True)
        try:
            out, _ = p.communicate(timeout=float(timeout))
            rc = p.returncode if p.returncode >= 0 else 128 - p.returncode
        except subprocess.TimeoutExpired:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            out, _ = p.communicate()
            rc = 124
    except OSError as e:
        out, rc = ('%s\n' % e).encode(), 127
    return out, rc
