#!/usr/bin/env bash
#
# install.sh — wire the Temper guardrails pack into a NATIVE git pre-commit hook.
#
# Why a native git hook? Claude Code's settings.json has NO "PreCommit" event
# (PreToolUse/PostToolUse/Stop/... only — PreCommit is an open feature request).
# A settings.json block therefore CANNOT deterministically block `git commit`.
# The only deterministic commit gate — one that fires on a raw `git commit`
# regardless of whether the agent is involved — is a real git hook. This
# installer installs one into the repository's git hooks folder.
#
# The scripts themselves remain usable from both worlds:
#   - PreToolUse/PostToolUse blocks (settings-guardrails.json) — in-agent edits/writes
#   - native git pre-commit (this installer)      — the real commit gate
#
# Where it writes. The installer works on the repository that holds the current folder
# (it clears every GIT_* variable first, so GIT_DIR, GIT_WORK_TREE, GIT_CONFIG and the
# rest cannot move it), changes into its top folder and writes only to:
#   - by default .git/hooks/pre-commit;
#   - in a linked worktree or a submodule (where .git is a file), the hooks folder git
#     names for it (git rev-parse --git-path hooks), and only when that folder is the
#     hooks folder of the repository's own git folder (git rev-parse --git-common-dir)
#     and that git folder is not inside the plugin's folder. When that folder already
#     holds the current Temper hook, the installer says so and writes nothing;
#   - with --global, .git/temper-git-hooks/pre-commit, and it sets core.hooksPath to
#     .git/temper-git-hooks in the repository's own .git/config. When core.hooksPath is
#     already set to anything else, --global refuses: the default mode installs into
#     that folder instead, and replacing the setting would switch its hooks off;
#   - when core.hooksPath is already set (husky, lefthook, the pre-commit framework),
#     <that folder>/pre-commit, because git ignores .git/hooks then. The folder is
#     accepted only when it lies inside the repository (a relative path, or an absolute
#     one inside the repository, which is turned relative), has no '..', and holds no
#     JSON file (a git hooks folder never does). For any other value the installer
#     prints the lines to add to your hook by hand and exits 1.
#
# Before it creates or writes anything, the installer follows every symlink in each path
# it will write and checks where that path really lands. A place in the repository's own
# git folder is accepted. A place equal to or inside the plugin's own folder is refused.
# Any other place outside the repository is refused. A repository that lies inside the
# plugin's folder is refused outright, and so is a run from a folder inside the plugin's
# folder when the repository's top is not the plugin's folder (an installed copy has no
# .git). Inside or equal is decided by folder identity (device and inode), not by how a
# path is spelled, so letter case and symlinks cannot hide the plugin's folder. So nothing
# is written into the plugin's folder, except into the .git folder of a checkout of the
# plugin itself (developing Temper on its own repository).
#
# The hook file is never written in place: the new hook is written to a new file in the
# hooks folder and then moved over pre-commit, so a pre-commit that is a symlink or a hard
# link to another file leaves that file as it was.
#
# A pre-commit hook that is not Temper's is copied to pre-commit.bak.<timestamp> first,
# and the Temper hook runs that copy before its own checks (its failure fails the commit,
# as it did before Temper). With --global, an existing .git/hooks/pre-commit stays where
# it is and the Temper hook runs it the same way.
#
# DEGRADATION CONTRACT: if the scripts are missing, or python3 is missing, the installed
# git hook skips the checks that need them (exit 0). Installing this never blocks a
# commit by itself.
#
# Usage:  bash scripts/guards/install.sh         # install into .git/hooks
#         bash scripts/guards/install.sh --global # install via core.hooksPath
set -euo pipefail

# cd prints the folder it changes to when CDPATH is set, which would spoil every folder this
# script works out with cd and pwd.
unset CDPATH

# Git reads GIT_* variables to reach another repository or config file (GIT_DIR,
# GIT_WORK_TREE, GIT_COMMON_DIR, GIT_CONFIG, GIT_CONFIG_PARAMETERS and more). The installer
# works on the repository that holds the current folder only, so every one of them is cleared.
while IFS= read -r _git_var; do
  unset "$_git_var" 2>/dev/null || true
done < <(compgen -e | grep '^GIT_' || true)
unset _git_var

# This script's own file, with every symlink followed (a link in a bin folder, or a chain of
# links), the same way the temper CLI finds itself; never an environment variable. The
# plugin folder is that file's folder with the literal suffix /scripts/guards removed. The
# hook gets each path it runs written out in full, as literal text, at install time.
_self="${BASH_SOURCE[0]}"
_hops=0
while [[ -L "$_self" ]]; do
  _hops=$((_hops + 1))
  if [[ $_hops -gt 40 ]]; then
    echo "FAIL: this installer is reached through too many symlinks (a loop?)." >&2
    exit 1
  fi
  _link_dir="$(cd -P "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" == /* ]] || _self="$_link_dir/$_self"
done
GUARD_SCRIPTS="$(cd "$(dirname "$_self")" && pwd)"
unset _self _hops _link_dir
PLUGIN_ROOT="${GUARD_SCRIPTS%/scripts/guards}"
TEMPER_CLI="$PLUGIN_ROOT/scripts/temper"
SECRETS_SCRIPT="$PLUGIN_ROOT/scripts/guards/block-secrets.sh"
TESTS_RAN_SCRIPT="$PLUGIN_ROOT/scripts/guards/verify-tests-ran.sh"
Q_TEMPER_CLI="$(printf '%q' "$TEMPER_CLI")"
Q_SECRETS_SCRIPT="$(printf '%q' "$SECRETS_SCRIPT")"
Q_TESTS_RAN_SCRIPT="$(printf '%q' "$TESTS_RAN_SCRIPT")"
# The hook this one replaces, run first by the Temper hook, in %q form ('' for none).
PRIOR_Q="''"

MODE="local"
[[ "${1:-}" == "--global" ]] && MODE="global"

# The hook itself. Fail-open by design: a missing script => skipped; a detected secret, a
# failing earlier hook or a red commit gate => exit 1 (block). The paths are literal text in
# the hook: no environment variable moves them, and the hook works none of them out at
# commit time.
_hook_body() {
  cat <<HOOK
#!/usr/bin/env bash
# Temper native pre-commit hook (installed by scripts/guards/install.sh).
# Fail-open: a missing script or a missing python3 never blocks. Only a detected violation blocks.
# The paths below were written in full at install time. A plugin upgrade moves them;
# re-run the installer then (it reports a stale path and writes the current one).
set -uo pipefail
TEMPER_CLI=$Q_TEMPER_CLI
SECRETS_SCRIPT=$Q_SECRETS_SCRIPT
TESTS_RAN_SCRIPT=$Q_TESTS_RAN_SCRIPT
# The pre-commit hook this one took the place of ('' when there was none).
PRIOR_HOOK=$PRIOR_Q

# 0. That earlier hook runs first, as git ran it before Temper, and its failure fails the
# commit. A plain sh script runs under the name git calls this hook by, so a hook that finds
# its own files from that name (husky's does) still works. A recorded hook that is gone is
# reported and skipped.
if [[ -n "\$PRIOR_HOOK" ]]; then
  if [[ -f "\$PRIOR_HOOK" && -x "\$PRIOR_HOOK" ]]; then
    case "\$(head -n 1 "\$PRIOR_HOOK")" in
      '#!/bin/sh'|'#!/usr/bin/env sh')
        sh -c 'temper_prior_hook=\$1; shift; . "\$temper_prior_hook"' "\$0" "\$PRIOR_HOOK" "\$@" || exit \$? ;;
      *)
        "\$PRIOR_HOOK" "\$@" || exit \$? ;;
    esac
  elif [[ ! -e "\$PRIOR_HOOK" ]]; then
    echo "Temper: the earlier pre-commit hook \$PRIOR_HOOK is gone, so it was skipped." >&2
  fi
fi

# Git hooks are not guaranteed to run with CWD at the worktree root on every
# platform/version — pin it explicitly so 'temper gate commit' (which resolves
# .temper/ and .claude/temper.config relative to \$(pwd)) reads the right project.
cd "\$(git rev-parse --show-toplevel)" || exit 0

# 1. Secrets in the staged files (--staged: this is a commit, not an agent's tool call).
[[ -f "\$SECRETS_SCRIPT" ]] && { bash "\$SECRETS_SCRIPT" --staged || exit 1; }

# 2. Every /temper gate must be green (or explicitly overridden) — the commit gate
# itself, computed by the temper CLI from the evidence ledger. Absent .temper/ state
# (repo doesn't use /temper for this commit, or CLI missing) => fail-open.
# Both checks below need python3. Without it they are skipped, so a missing tool never
# blocks a commit.
command -v python3 >/dev/null 2>&1 || exit 0
# A repository inside the plugin's own folder (a second checkout or worktree placed in it)
# is part of the plugin: the CLI refuses to run there, so the gate is skipped. Each folder
# above the repository is compared with the plugin folder by identity (device and inode).
PLUGIN_DIR="\${TEMPER_CLI%/scripts/temper}"
REPO_DIR="\$(pwd -P)"
if [[ -d "\$PLUGIN_DIR" ]] && ! [[ "\$REPO_DIR" -ef "\$PLUGIN_DIR" ]]; then
  UP_DIR="\$REPO_DIR"
  while [[ "\$UP_DIR" == /?* ]]; do
    UP_DIR="\${UP_DIR%/*}"
    [[ "\${UP_DIR:-/}" -ef "\$PLUGIN_DIR" ]] && exit 0
  done
fi
if [[ -x "\$TEMPER_CLI" && -d .temper ]]; then
  "\$TEMPER_CLI" gate commit
  GATE_RC=\$?
  if [[ \$GATE_RC -eq 3 ]]; then
    echo "Temper: the commit gate was skipped because the temper CLI refused this project's .temper folder (its reason is above)." >&2
    exit 0
  fi
  [[ \$GATE_RC -eq 0 ]] || exit 1
elif [[ -f "\$TESTS_RAN_SCRIPT" ]]; then
  # Fallback for a project that only installed the guardrails pack without the CLI.
  bash "\$TESTS_RAN_SCRIPT" || exit 1
fi

exit 0
HOOK
}

_refuse() { # _refuse <reason> -> prints the reason and the hook to add by hand, exits 1
  echo "FAIL: $1" >&2
  echo "Nothing was written. To use the Temper commit gate, make your pre-commit hook run" >&2
  echo "the lines between the BEGIN and END lines below (or point core.hooksPath at a folder" >&2
  echo "inside this repository and re-run this installer)." >&2
  echo "----- BEGIN Temper pre-commit hook lines -----" >&2
  PRIOR_Q="''" _hook_body >&2
  echo "----- END Temper pre-commit hook lines -----" >&2
  exit 1
}

# The plugin folder must be found, and its CLI must run: otherwise a hook written now
# would skip every check without a word.
if [[ -z "$PLUGIN_ROOT" || "$PLUGIN_ROOT" == "$GUARD_SCRIPTS" ]]; then
  _refuse "this installer is not in a plugin's scripts/guards folder ($GUARD_SCRIPTS), so the hook would run nothing."
fi
if [[ ! -f "$TEMPER_CLI" || ! -x "$TEMPER_CLI" ]]; then
  _refuse "the temper CLI next to this installer ($TEMPER_CLI) is missing or not executable, so the hook would check nothing."
fi
# The plugin folder with every symlink followed, for the write checks below.
PLUGIN_REAL="$(cd -P "$PLUGIN_ROOT" && pwd)"

_same_or_inside() { # _same_or_inside <absolute path> <folder>: 0 when the path, or a folder
                    # above it, is that folder. Compared by identity (device and inode), so
                    # letter case and symlinks cannot hide it.
  local p="$1"
  while :; do
    [[ -e "$p" && "$p" -ef "$2" ]] && return 0
    [[ "$p" == /?* ]] || return 1
    p="${p%/*}"
    p="${p:-/}"
  done
}

# Resolve the TARGET repo (where to install the git hook). This is the current
# working directory's git toplevel — NOT the repo that ships these scripts. A user
# runs `bash /path/to/temper/scripts/guards/install.sh` from their own project.
START_REAL="$(pwd -P)"
TARGET_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$TARGET_ROOT" ]]; then
  echo "FAIL: not inside a git repository (cwd is not a worktree)." >&2
  echo "Run this from the project where you want the pre-commit hook installed." >&2
  exit 1
fi
cd "$TARGET_ROOT"
REPO_REAL="$(pwd -P)"

# The plugin's own folder is a project only when it is the top of this git work tree
# (developing Temper on its own repository). A repository inside it gets nothing: every
# place in it is part of the plugin. Neither does a run from a folder inside it when the
# repository's top is somewhere else (an installed copy of the plugin has no .git).
if ! [[ "$REPO_REAL" -ef "$PLUGIN_REAL" ]]; then
  if _same_or_inside "$REPO_REAL" "$PLUGIN_REAL"; then
    _refuse "this repository lies inside the plugin's own folder ($PLUGIN_REAL)."
  fi
  if _same_or_inside "$START_REAL" "$PLUGIN_REAL"; then
    _refuse "the current folder lies inside the plugin's own folder ($PLUGIN_REAL), which is not the top of this repository. Run this installer from your project's folder."
  fi
fi

# The repository's own git folder, where every write is accepted: its .git folder when that
# is a real folder (a linked worktree or a submodule sets it further down).
GIT_OWN=""
if [[ -d .git && ! -L .git ]]; then
  GIT_OWN="$REPO_REAL/.git"
fi

_real_path() { # _real_path <path, absolute or relative to the cwd>: prints the absolute path
               # with every symlink followed; the parts that do not exist yet are kept as written
  local out rest comp link hops=0
  if [[ "${1:0:1}" == "/" ]]; then out="/"; else out="$(pwd -P)"; fi
  rest="$1"
  while [[ -n "$rest" ]]; do
    comp="${rest%%/*}"
    if [[ "$comp" == "$rest" ]]; then rest=""; else rest="${rest#*/}"; fi
    case "$comp" in
      ''|.) continue ;;
      ..) out="${out%/*}"; [[ -n "$out" ]] || out="/"; continue ;;
    esac
    if [[ -L "${out%/}/$comp" ]]; then
      hops=$((hops + 1))
      [[ $hops -le 40 ]] || return 1
      link="$(readlink "${out%/}/$comp")" || return 1
      if [[ "${link:0:1}" == "/" ]]; then out="/"; fi
      rest="$link${rest:+/$rest}"
    else
      out="${out%/}/$comp"
    fi
  done
  printf '%s\n' "$out"
}

_check_target() { # _check_target <path, relative to the repository top or absolute>: returns
                  # when that path, with every symlink followed, lands in a place this installer
                  # may write, and refuses (exit 1) otherwise
  local real
  real="$(_real_path "$1")" || _refuse "the path '$1' could not be resolved (a symlink loop?)."
  if [[ -n "$GIT_OWN" ]] && _same_or_inside "$real" "$GIT_OWN"; then
    return 0
  fi
  if _same_or_inside "$real" "$PLUGIN_REAL"; then
    _refuse "'$1' leads into the plugin's own folder ($real)."
  fi
  if ! _same_or_inside "$real" "$REPO_REAL"; then
    _refuse "'$1' leads outside this repository ($real)."
  fi
}

# A Temper hook carries "# Temper native pre-commit hook" as its second line; every version
# does, including the installs made when the scripts lived under the old scripts folder name.
TEMPER_HOOK_LINE="Temper native pre-commit hook"
_is_temper_hook() { # _is_temper_hook <file>
  [[ -f "$1" && "$(sed -n 2p "$1" 2>/dev/null)" == "# $TEMPER_HOOK_LINE"* ]]
}
_prior_of() { # _prior_of <Temper hook file>: prints its PRIOR_HOOK value as written (%q form),
              # or nothing when it has none or the value is not one this installer writes
  local v
  v="$(sed -n 's/^PRIOR_HOOK=//p' "$1" 2>/dev/null | head -1 || true)"
  if [[ "$v" == "''" || "$v" =~ ^/([A-Za-z0-9._/+@:,=%~-]|\\.)*$ ]]; then
    printf '%s\n' "$v"
  fi
}
_is_current_hook() { # _is_current_hook <file>: the file is exactly the hook this installer
                     # writes now (with the earlier hook it records)
  local prior
  _is_temper_hook "$1" || return 1
  prior="$(_prior_of "$1")"
  [[ "$(cat "$1" 2>/dev/null)" == "$(PRIOR_Q="${prior:-''}" _hook_body)" ]]
}

# Pick the hooks folder: relative to the repository root, or (linked worktree, submodule)
# the absolute hooks folder of the repository's own git folder.
HOOKS_FOLDER=""
WORKTREE_HOOKS=0
EXISTING_HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || true)"
if [[ "$MODE" == "global" ]]; then
  [[ -d .git ]] || _refuse "this checkout's .git is not a folder (a linked worktree or a submodule)."
  # Another value is a hooks folder in use (husky, lefthook): replacing it would switch its
  # hooks off. The default mode installs into that folder instead.
  if [[ -n "$EXISTING_HOOKS_PATH" && "$EXISTING_HOOKS_PATH" != ".git/temper-git-hooks" ]]; then
    _refuse "core.hooksPath is already set to '$EXISTING_HOOKS_PATH'. --global would replace it and switch the hooks in that folder off. Run this installer without --global: it installs into that folder."
  fi
  HOOKS_FOLDER=".git/temper-git-hooks"
  _check_target .git/config
elif [[ -n "$EXISTING_HOOKS_PATH" ]]; then
  # Respect an EXISTING core.hooksPath (husky v9, lefthook, the pre-commit framework
  # all set it): git ignores .git/hooks/ entirely when core.hooksPath is set, so a hook
  # written there would be inert and never block a commit.
  rel="$EXISTING_HOOKS_PATH"
  if [[ "${rel:0:1}" == "/" ]]; then
    # An absolute path is accepted only inside this repository, and then made relative.
    [[ "${rel#"$TARGET_ROOT"/}" != "$rel" ]] || _refuse "core.hooksPath is set to '$EXISTING_HOOKS_PATH', which is outside this repository."
    rel="${rel#"$TARGET_ROOT"/}"
  fi
  while [[ "${rel:0:2}" == "./" ]]; do rel="${rel:2}"; done
  while [[ -n "$rel" && "${rel: -1}" == "/" ]]; do rel="${rel%/}"; done
  if ! [[ "$rel" =~ ^[A-Za-z0-9._][A-Za-z0-9._/-]*$ ]] || [[ "$rel" =~ [.][.] ]]; then
    _refuse "core.hooksPath is set to '$EXISTING_HOOKS_PATH'; this installer writes only to a folder inside this repository whose path has no '..', no '~' and no unusual characters."
  fi
  HOOKS_FOLDER="$rel"
  echo "Note: core.hooksPath is set ($EXISTING_HOOKS_PATH), so the hook goes there, not into .git/hooks (which git would ignore)." >&2
elif [[ -d .git ]]; then
  HOOKS_FOLDER=".git/hooks"
else
  # A linked worktree or a submodule: .git is a file, and git keeps the hooks in the
  # repository's own git folder. Ask git where they go.
  HOOKS_GIT="$(git rev-parse --git-path hooks 2>/dev/null || true)"
  COMMON_GIT="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n "$HOOKS_GIT" && -n "$COMMON_GIT" ]] || _refuse "git did not say where this checkout's hooks go."
  [[ "${HOOKS_GIT:0:1}" == "/" ]] || HOOKS_GIT="$REPO_REAL/$HOOKS_GIT"
  [[ "${COMMON_GIT:0:1}" == "/" ]] || COMMON_GIT="$REPO_REAL/$COMMON_GIT"
  COMMON_REAL="$(cd -P "$COMMON_GIT" 2>/dev/null && pwd)" || _refuse "the repository's git folder ($COMMON_GIT) could not be read."
  if _is_current_hook "$HOOKS_GIT/pre-commit"; then
    echo "The Temper pre-commit hook is already installed for this worktree: $HOOKS_GIT/pre-commit"
    echo "(git runs the repository's hooks in every worktree of it, so nothing was written)."
    exit 0
  fi
  if [[ "${HOOKS_GIT##*/}" != "hooks" ]] || ! [[ "${HOOKS_GIT%/*}" -ef "$COMMON_REAL" ]]; then
    _refuse "git's hooks folder for this checkout ($HOOKS_GIT) is not the hooks folder of the repository's own git folder ($COMMON_REAL)."
  fi
  if _same_or_inside "$COMMON_REAL" "$PLUGIN_REAL"; then
    _refuse "this checkout's repository keeps its git folder inside the plugin's own folder ($COMMON_REAL)."
  fi
  GIT_OWN="$COMMON_REAL"
  HOOKS_FOLDER="$COMMON_REAL/hooks"
  WORKTREE_HOOKS=1
fi
# Where the folder really lands, checked before anything is created. (The hook file itself
# is never written in place: the new hook is moved over it, below.)
_check_target "$HOOKS_FOLDER"
mkdir -p "$HOOKS_FOLDER"

# A git hooks folder holds hook scripts, never a JSON file. One that does may be a plugin's
# own hooks folder reached through a symlink or a core.hooksPath; refuse to write there.
while IFS= read -r -d '' entry; do
  if [[ "${entry%.json}" != "$entry" ]]; then
    _refuse "the hooks folder '$HOOKS_FOLDER' holds a JSON file, so it is not a plain git hooks folder."
  fi
done < <(find "$HOOKS_FOLDER/" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

case "$HOOKS_FOLDER" in
  .git/hooks)            PRECOMMIT=".git/hooks/pre-commit" ;;
  .git/temper-git-hooks) PRECOMMIT=".git/temper-git-hooks/pre-commit" ;;
  *)                     PRECOMMIT="$HOOKS_FOLDER/pre-commit" ;;
esac
_abs() { # _abs <path relative to the repository top or absolute>: prints it absolute
  if [[ "${1:0:1}" == "/" ]]; then printf '%s\n' "$1"; else printf '%s\n' "$REPO_REAL/$1"; fi
}

# The new files are made in the hooks folder and moved into place, so no existing file is
# ever written through. Whatever is left of them on an early exit is removed.
TMP_HOOK=""
TMP_BACKUP=""
trap '[[ -z "$TMP_HOOK" ]] || rm -f "$TMP_HOOK"; [[ -z "$TMP_BACKUP" ]] || rm -f "$TMP_BACKUP"' EXIT

# Don't clobber an existing pre-commit hook silently. A Temper hook is safe to replace
# (the earlier hook it records is kept). Anything else (husky, lefthook, or a hand-rolled
# hook) is backed up first, and the Temper hook runs the backup before its own checks, so
# the user's prior setup keeps working and stays recoverable.
# Stale-path detection: a Temper hook carries the plugin paths embedded at ITS install
# time. A plugin upgrade moves that directory, and the hook's checks then fail open
# SILENTLY — every commit gate check becomes a no-op with no signal. Detect the mismatch
# and report it; the hook written below always carries the CURRENT paths, so re-running
# this installer is the repair.
if _is_temper_hook "$PRECOMMIT"; then
  EMBEDDED_PATH="$(sed -n 's/^TEMPER_CLI=//p' "$PRECOMMIT" 2>/dev/null | head -1 || true)"
  if [[ -z "$EMBEDDED_PATH" ]]; then
    # An install from before 9.6.5 embedded the scripts folder instead of each path.
    EMBEDDED_PATH="$(sed -n 's/^TEMPER_HOOKS_DIR="\${TEMPER_HOOKS_DIR:-\(.*\)}"$/\1/p' "$PRECOMMIT" 2>/dev/null | head -1 || true)"
  fi
  if [[ -n "$EMBEDDED_PATH" && "$EMBEDDED_PATH" != "$Q_TEMPER_CLI" ]]; then
    echo "Warning: installed pre-commit hook points at a stale plugin path:" >&2
    echo "  embedded: $EMBEDDED_PATH" >&2
    echo "  current:  $TEMPER_CLI" >&2
    echo "  (The hook has been failing open — its gate checks were no-ops.)" >&2
    echo "  Re-embedding the current path now." >&2
  fi
  KEPT_PRIOR="$(_prior_of "$PRECOMMIT")"
  if [[ -n "$KEPT_PRIOR" ]]; then
    PRIOR_Q="$KEPT_PRIOR"
  elif grep -q '^PRIOR_HOOK=' "$PRECOMMIT" 2>/dev/null; then
    echo "Warning: the earlier hook recorded in $PRECOMMIT could not be read, so the new hook does not run it." >&2
  fi
elif [[ -e "$PRECOMMIT" ]]; then
  BACKUP="$PRECOMMIT.bak.$(date +%Y%m%d%H%M%S 2>/dev/null || echo backup)"
  _check_target "$BACKUP"
  TMP_BACKUP="$(mktemp "$HOOKS_FOLDER/.pre-commit.bak.temper.XXXXXX")"
  cp -p "$PRECOMMIT" "$TMP_BACKUP"   # set -e: a failed backup stops before anything is replaced
  mv -f "$TMP_BACKUP" "$BACKUP"
  TMP_BACKUP=""
  PRIOR_Q="$(printf '%q' "$(_abs "$BACKUP")")"
  echo "Backed up existing pre-commit hook -> $BACKUP" >&2
  echo "(It was not a Temper hook. The Temper hook runs this backup first, then its own checks; to go back, move the backup to $PRECOMMIT.)" >&2
elif [[ "$MODE" == "global" && -x .git/hooks/pre-commit ]] && ! _is_temper_hook .git/hooks/pre-commit; then
  # --global points git away from .git/hooks; the hook there keeps running from the Temper hook.
  PRIOR_Q="$(printf '%q' "$REPO_REAL/.git/hooks/pre-commit")"
  echo "Note: .git/hooks/pre-commit stays where it is; the Temper hook runs it first." >&2
fi

TMP_HOOK="$(mktemp "$HOOKS_FOLDER/.pre-commit.temper.XXXXXX")"
_hook_body > "$TMP_HOOK"
printf -v HOOK_MODE '%o' $(( 0777 & ~$(umask) ))
chmod "$HOOK_MODE" "$TMP_HOOK"
mv -f "$TMP_HOOK" "$PRECOMMIT"
TMP_HOOK=""

# husky (v9) writes its generated hooks folder again whenever it sets its hooks up.
if [[ "${HOOKS_FOLDER##*/}" == "_" && -f "$HOOKS_FOLDER/h" ]]; then
  echo "Note: husky writes $HOOKS_FOLDER again when it sets up its hooks (for example on npm install); run this installer again after that." >&2
fi

if [[ "$MODE" == "global" ]]; then
  git config --local core.hooksPath .git/temper-git-hooks 2>/dev/null || true
  echo "Installed Temper pre-commit hook via core.hooksPath -> $TARGET_ROOT/.git/temper-git-hooks"
elif [[ $WORKTREE_HOOKS -eq 1 ]]; then
  echo "Installed Temper pre-commit hook -> $PRECOMMIT (the repository's hooks folder, which git uses in every worktree)"
else
  echo "Installed Temper pre-commit hook -> $TARGET_ROOT/$PRECOMMIT"
fi
echo "To uninstall: delete $PRECOMMIT in this repository (and unset core.hooksPath if --global was used)."
echo "A prior non-Temper hook, if any, was backed up next to it as pre-commit.bak.<timestamp>, and the Temper hook runs it first; move it back to pre-commit to restore it."
