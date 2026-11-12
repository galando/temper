"""run_env.py: how the CLI runs a command of a grouped Build (a task's test, a scenario's Test: command, a group's Validate
command, the integration suite).

  run_env.test_env(cwd)      the environment: this one, without the variables whose names say they hold a credential,
                             and with the folder the command runs in first on PYTHONPATH
  run_env.run_cmd(wt, timeout, cmd)   run cmd in wt (one string runs through bash -c), killing it at the timeout

A credential is no input of a test: a key, a token, a secret, a password or passphrase, credentials, an auth socket or
helper are left out; every other variable passes as it is, and git's GIT_CONFIG_COUNT, GIT_CONFIG_KEY_n and GIT_CONFIG_VALUE_n
pass together. PYTHONPATH puts the folder first so a package importable from
both the project root (an editable install) and the task's worktree resolves to the worktree's copy; other languages
ignore it. Standard library only.
"""
import os
import re
import signal
import subprocess

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
           if not GIT_CONFIG_FAMILY.match(k) and not CREDENTIAL_NAME.search(k.upper()) and k.upper() not in CREDENTIAL_NAMES}
    env.update(family)
    if cwd:
        old = env.get('PYTHONPATH')
        env['PYTHONPATH'] = os.path.abspath(cwd) + (os.pathsep + old if old else '')
    return env


def run_cmd(wt, timeout, cmd):
    """Returns (output bytes, exit). 124 is a timeout, 127 a command that could not start."""
    args = ['bash', '-c', cmd[0]] if len(cmd) == 1 else cmd
    try:
        p = subprocess.Popen(args, cwd=wt, env=test_env(wt), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
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
