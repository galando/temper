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
# (it ignores GIT_DIR, GIT_WORK_TREE, GIT_COMMON_DIR, GIT_INDEX_FILE, GIT_OBJECT_DIRECTORY
# and GIT_CONFIG), changes into its top folder and writes only to a path relative to it:
#   - by default .git/hooks/pre-commit;
#   - with --global, .git/temper-git-hooks/pre-commit, and it sets core.hooksPath to
#     .git/temper-git-hooks in the repository's own .git/config;
#   - when core.hooksPath is already set (husky, lefthook, the pre-commit framework),
#     <that folder>/pre-commit, because git ignores .git/hooks then. The folder is
#     accepted only when it lies inside the repository (a relative path, or an absolute
#     one inside the repository, which is turned relative), has no '..', and holds no
#     JSON file (a git hooks folder never does). For any other value the installer
#     prints the lines to add to your hook by hand and exits 1.
#
# Before it creates or writes anything, the installer follows every symlink in each path
# it will write and checks where that path really lands. A place in the repository's own
# .git folder is accepted. A place equal to or inside the plugin's own folder is refused.
# Any other place outside the repository is refused. A repository that lies inside the
# plugin's folder is refused outright. So nothing is written into the plugin's folder,
# except into the .git folder of a checkout of the plugin itself (developing Temper on
# its own repository).
#
# DEGRADATION CONTRACT: if the scripts are missing, or python3 is missing, the installed
# git hook skips the checks that need them (exit 0). Installing this never blocks a
# commit by itself.
#
# Usage:  bash scripts/guards/install.sh         # install into .git/hooks
#         bash scripts/guards/install.sh --global # install via core.hooksPath
set -euo pipefail

# Git reads these to reach another repository or config file. The installer works on the
# repository that holds the current folder only, so none of them may move where it writes.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_CONFIG

# This script's folder, and the plugin folder: that folder with the literal suffix
# /scripts/guards removed. The hook gets each path it runs written out in full, as
# literal text, at install time.
GUARD_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${GUARD_SCRIPTS%/scripts/guards}"
TEMPER_CLI="$PLUGIN_ROOT/scripts/temper"
SECRETS_SCRIPT="$PLUGIN_ROOT/scripts/guards/block-secrets.sh"
TESTS_RAN_SCRIPT="$PLUGIN_ROOT/scripts/guards/verify-tests-ran.sh"
Q_TEMPER_CLI="$(printf '%q' "$TEMPER_CLI")"
Q_SECRETS_SCRIPT="$(printf '%q' "$SECRETS_SCRIPT")"
Q_TESTS_RAN_SCRIPT="$(printf '%q' "$TESTS_RAN_SCRIPT")"
# The plugin folder with every symlink followed, for the write check below.
PLUGIN_REAL="$(cd "$PLUGIN_ROOT" && pwd -P)"

MODE="local"
[[ "${1:-}" == "--global" ]] && MODE="global"

# The hook itself. Fail-open by design: a missing script => skipped; a detected secret or
# a red commit gate => exit 1 (block). The three paths are literal text in the hook: no
# environment variable moves them, and the hook works none of them out at commit time.
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

# Git hooks are not guaranteed to run with CWD at the worktree root on every
# platform/version — pin it explicitly so 'temper gate commit' (which resolves
# .temper/ and .claude/temper.config relative to \$(pwd)) reads the right project.
cd "\$(git rev-parse --show-toplevel)" || exit 0

# 1. Secrets.
[[ -f "\$SECRETS_SCRIPT" ]] && { bash "\$SECRETS_SCRIPT" || exit 1; }

# 2. Every /temper gate must be green (or explicitly overridden) — the commit gate
# itself, computed by the temper CLI from the evidence ledger. Absent .temper/ state
# (repo doesn't use /temper for this commit, or CLI missing) => fail-open.
# Both checks below need python3. Without it they are skipped, so a missing tool never
# blocks a commit.
command -v python3 >/dev/null 2>&1 || exit 0
# A repository inside the plugin's own folder (a second checkout or worktree placed in it)
# is part of the plugin: the CLI refuses to run there, so the gate is skipped.
PLUGIN_DIR="\$(cd "\${TEMPER_CLI%/scripts/temper}" 2>/dev/null && pwd -P)" || PLUGIN_DIR=""
REPO_DIR="\$(pwd -P)"
[[ -n "\$PLUGIN_DIR" && "\${REPO_DIR#"\$PLUGIN_DIR"/}" != "\$REPO_DIR" ]] && exit 0
if [[ -x "\$TEMPER_CLI" && -d .temper ]]; then
  "\$TEMPER_CLI" gate commit || exit 1
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
  echo "the lines below (or point core.hooksPath at a folder inside this repository and" >&2
  echo "re-run this installer):" >&2
  echo "" >&2
  _hook_body >&2
  exit 1
}

# Resolve the TARGET repo (where to install the git hook). This is the current
# working directory's git toplevel — NOT the repo that ships these scripts. A user
# runs `bash /path/to/temper/scripts/guards/install.sh` from their own project.
TARGET_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$TARGET_ROOT" ]]; then
  echo "FAIL: not inside a git repository (cwd is not a worktree)." >&2
  echo "Run this from the project where you want the pre-commit hook installed." >&2
  exit 1
fi
cd "$TARGET_ROOT"
REPO_REAL="$(pwd -P)"

# A repository inside the plugin's own folder gets nothing: every place in it is part of
# the plugin.
if [[ "${REPO_REAL#"${PLUGIN_REAL%/}"/}" != "$REPO_REAL" ]]; then
  _refuse "this repository lies inside the plugin's own folder ($PLUGIN_REAL)."
fi

_real_path() { # _real_path <path relative to the cwd>: prints the absolute path with every
               # symlink followed; the parts that do not exist yet are kept as written
  local out rest comp link hops=0
  out="$(pwd -P)"
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

_check_target() { # _check_target <path relative to the repository top>: returns when that
                  # path, with every symlink followed, lands in a place this installer may
                  # write, and refuses (exit 1) otherwise
  local real top="${REPO_REAL%/}"
  real="$(_real_path "$1")" || _refuse "the path '$1' could not be resolved (a symlink loop?)."
  if [[ "${real#"$top"/.git/}" != "$real" ]]; then
    return 0
  fi
  if [[ "$real" == "$PLUGIN_REAL" || "${real#"${PLUGIN_REAL%/}"/}" != "$real" ]]; then
    _refuse "'$1' leads into the plugin's own folder ($real)."
  fi
  if [[ "$real" != "$top" && "${real#"$top"/}" == "$real" ]]; then
    _refuse "'$1' leads outside this repository ($real)."
  fi
}

# Pick the hooks folder, relative to the repository root. Two of the three are fixed text;
# the third is the configured core.hooksPath, checked before use.
HOOKS_FOLDER=""
if [[ "$MODE" == "global" ]]; then
  [[ -d .git ]] || _refuse "this checkout's .git is not a folder (a linked worktree or a submodule)."
  HOOKS_FOLDER=".git/temper-git-hooks"
  _check_target .git/config
else
  # Respect an EXISTING core.hooksPath (husky v9, lefthook, the pre-commit framework
  # all set it): git ignores .git/hooks/ entirely when core.hooksPath is set, so a hook
  # written there would be inert and never block a commit.
  EXISTING_HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || true)"
  if [[ -n "$EXISTING_HOOKS_PATH" ]]; then
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
    echo "Note: core.hooksPath is set ($EXISTING_HOOKS_PATH) — installing there, not .git/hooks (which git would ignore)." >&2
  else
    [[ -d .git ]] || _refuse "this checkout's .git is not a folder (a linked worktree or a submodule)."
    HOOKS_FOLDER=".git/hooks"
  fi
fi
# Where the folder really lands, checked before anything is created. (The hook file itself
# is never written through a symlink: a symlinked pre-commit is removed first, below.)
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

# Don't clobber an existing pre-commit hook silently. A Temper hook (recognizable by its
# "Temper native pre-commit hook" line, which every version carries, including the
# installs made when the scripts lived under the old scripts folder name) is safe to
# overwrite in place; anything else — husky, lefthook, or a hand-rolled hook — is backed
# up first so the user's prior setup is recoverable, not lost.
TEMPER_HOOK_LINE="Temper native pre-commit hook"
# Stale-path detection: a Temper hook carries the plugin paths embedded at ITS install
# time. A plugin upgrade moves that directory, and the hook's checks then fail open
# SILENTLY — every commit gate check becomes a no-op with no signal. Detect the mismatch
# and report it; the hook written below always carries the CURRENT paths, so re-running
# this installer is the repair.
if [[ -f "$PRECOMMIT" ]] && grep -qF "$TEMPER_HOOK_LINE" "$PRECOMMIT" 2>/dev/null; then
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
elif [[ -e "$PRECOMMIT" ]]; then
  BACKUP="$PRECOMMIT.bak.$(date +%Y%m%d%H%M%S 2>/dev/null || echo backup)"
  _check_target "$BACKUP"
  cp -p "$PRECOMMIT" "$BACKUP"   # set -e: a failed backup stops before anything is overwritten
  echo "Backed up existing pre-commit hook -> $BACKUP" >&2
  echo "(It was not a Temper hook. Temper will overwrite $PRECOMMIT; restore the backup to revert.)" >&2
fi
# A symlinked pre-commit is replaced by a regular file: writing through the link would
# change whatever file it points at.
[[ -L "$PRECOMMIT" ]] && rm -f "$PRECOMMIT"

_hook_body > "$PRECOMMIT"
chmod +x "$PRECOMMIT"

if [[ "$MODE" == "global" ]]; then
  git config --local core.hooksPath .git/temper-git-hooks 2>/dev/null || true
  echo "Installed Temper pre-commit hook via core.hooksPath -> $TARGET_ROOT/.git/temper-git-hooks"
else
  echo "Installed Temper pre-commit hook -> $TARGET_ROOT/$PRECOMMIT"
fi
echo "To uninstall: delete $PRECOMMIT in this repository (and unset core.hooksPath if --global was used)."
echo "A prior non-Temper hook, if any, was backed up next to it as pre-commit.bak.<timestamp>."
