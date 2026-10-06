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
# Where it writes. The installer changes into the target repository and writes only to
# a path relative to it, so it can never write into the plugin's own folders:
#   - by default .git/hooks/pre-commit;
#   - with --global, .git/temper-git-hooks/pre-commit, and it sets core.hooksPath to
#     .git/temper-git-hooks;
#   - when core.hooksPath is already set (husky, lefthook, the pre-commit framework),
#     <that folder>/pre-commit, because git ignores .git/hooks then. The folder is
#     accepted only when it lies inside the repository (a relative path, or an absolute
#     one inside the repository, which is turned relative), has no '..', and holds no
#     JSON file (a git hooks folder never does). For any other value the installer
#     prints the lines to add to your hook by hand and exits 1.
#
# DEGRADATION CONTRACT: if the scripts are missing, the installed git hook
# is a no-op (exit 0). Installing this never blocks a commit by itself.
#
# Usage:  bash scripts/guards/install.sh         # install into .git/hooks
#         bash scripts/guards/install.sh --global # install via core.hooksPath
set -euo pipefail

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

MODE="local"
[[ "${1:-}" == "--global" ]] && MODE="global"

# The hook itself. Fail-open by design: a missing script => skipped; a detected secret or
# a red commit gate => exit 1 (block). The three paths are literal text in the hook: no
# environment variable moves them, and the hook works none of them out at commit time.
_hook_body() {
  cat <<HOOK
#!/usr/bin/env bash
# Temper native pre-commit hook (installed by scripts/guards/install.sh).
# Fail-open: missing scripts never block. Only a detected violation blocks.
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

# Pick the hooks folder, relative to the repository root. Two of the three are fixed text;
# the third is the configured core.hooksPath, checked before use.
HOOKS_FOLDER=""
if [[ "$MODE" == "global" ]]; then
  [[ -d .git ]] || _refuse "this checkout's .git is not a folder (a linked worktree or a submodule)."
  HOOKS_FOLDER=".git/temper-git-hooks"
  mkdir -p .git/temper-git-hooks
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
    mkdir -p "$HOOKS_FOLDER"
  else
    [[ -d .git ]] || _refuse "this checkout's .git is not a folder (a linked worktree or a submodule)."
    HOOKS_FOLDER=".git/hooks"
    mkdir -p .git/hooks
  fi
fi

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
  git config core.hooksPath .git/temper-git-hooks 2>/dev/null || true
  echo "Installed Temper pre-commit hook via core.hooksPath -> $TARGET_ROOT/.git/temper-git-hooks"
else
  echo "Installed Temper pre-commit hook -> $TARGET_ROOT/$PRECOMMIT"
fi
echo "To uninstall: delete $PRECOMMIT in this repository (and unset core.hooksPath if --global was used)."
echo "A prior non-Temper hook, if any, was backed up next to it as pre-commit.bak.<timestamp>."
