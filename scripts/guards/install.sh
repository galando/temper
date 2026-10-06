#!/usr/bin/env bash
#
# install.sh — wire the Temper guardrails pack into a NATIVE git pre-commit hook.
#
# Why a native git hook? Claude Code's settings.json has NO "PreCommit" event
# (PreToolUse/PostToolUse/Stop/... only — PreCommit is an open feature request).
# A settings.json block therefore CANNOT deterministically block `git commit`.
# The only deterministic commit gate — one that fires on a raw `git commit`
# regardless of whether the agent is involved — is a real git hook. This
# installer installs one (via core.hooksPath, falling back to .git/hooks/).
#
# The scripts themselves remain usable from both worlds:
#   - PreToolUse/PostToolUse blocks (settings-guardrails.json) — in-agent edits/writes
#   - native git pre-commit (this installer)      — the real commit gate
#
# DEGRADATION CONTRACT: if the scripts are missing, the installed git hook
# is a no-op (exit 0). Installing this never blocks a commit by itself.
#
# Usage:  bash scripts/guards/install.sh         # install into .git/hooks
#         bash scripts/guards/install.sh --global # install into core.hooksPath
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"   # where the Temper hook scripts live
MODE="local"
[[ "${1:-}" == "--global" ]] && MODE="global"

# Resolve the TARGET repo (where to install the git hook). This is the current
# working directory's git toplevel — NOT the repo that ships these scripts. A user
# runs `bash /path/to/temper/scripts/guards/install.sh` from their own project.
TARGET_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$TARGET_ROOT" ]]; then
  echo "FAIL: not inside a git repository (cwd is not a worktree)." >&2
  echo "Run this from the project where you want the pre-commit hook installed." >&2
  exit 1
fi
# The plugin folder (the parent of scripts/) and its own hooks folder, where the mod lives.
# A git hook is never written there, whatever core.hooksPath says.
PLUGIN_DIR="$(dirname "$(dirname "$HOOKS_DIR")")"
PLUGIN_HOOKS_FOLDER="$PLUGIN_DIR/hooks"

# Resolve the git hooks location.
if [[ "$MODE" == "global" ]]; then
  # core.hooksPath: a single shared dir. Create a temper dir and point git at it.
  TARGET_DIR="$TARGET_ROOT/.git/hooks-temper"
  mkdir -p "$TARGET_DIR"
else
  # Respect an EXISTING core.hooksPath (husky v9, lefthook, the pre-commit framework
  # all set it): git ignores .git/hooks/ entirely when core.hooksPath is set, so a hook
  # written there would be inert and never block a commit. Install into the configured
  # dir instead (resolved relative to the worktree root if it's a relative path).
  EXISTING_HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || true)"
  if [[ -n "$EXISTING_HOOKS_PATH" ]]; then
    case "$EXISTING_HOOKS_PATH" in
      /*) TARGET_DIR="$EXISTING_HOOKS_PATH" ;;
      *)  TARGET_DIR="$TARGET_ROOT/$EXISTING_HOOKS_PATH" ;;
    esac
    echo "Note: core.hooksPath is set ($EXISTING_HOOKS_PATH) — installing there, not .git/hooks (which git would ignore)." >&2
  else
    TARGET_DIR="$TARGET_ROOT/.git/hooks"
  fi
  mkdir -p "$TARGET_DIR"
fi

case "$(cd "$TARGET_DIR" && pwd)/" in
  "$PLUGIN_HOOKS_FOLDER"/*)
    echo "FAIL: the git hooks folder ($TARGET_DIR) is the Temper plugin's own hooks folder; refusing to write there." >&2
    exit 1 ;;
esac
PRECOMMIT="$TARGET_DIR/pre-commit"

# Don't clobber an existing pre-commit hook silently. A Temper-managed hook
# (recognizable by its marker line) is safe to overwrite in place; anything
# else — husky, lefthook, or a hand-rolled hook — is backed up first so the
# user's prior setup is recoverable, not lost.
TEMPER_MARKER="installed by scripts/guards/install.sh"
# Stale-path detection: a Temper hook carries the plugin path embedded at ITS
# install time. A plugin upgrade moves that directory, and the hook's
# `[[ -d ... ]] || exit 0` guard then fails open SILENTLY — every commit gate
# check becomes a no-op with no signal. Detect the mismatch and report it; the
# heredoc below always re-embeds the CURRENT path, so re-running this installer
# is the repair.
if [[ -f "$PRECOMMIT" ]] && grep -qF "$TEMPER_MARKER" "$PRECOMMIT" 2>/dev/null; then
  EMBEDDED_PATH="$(sed -n 's/^TEMPER_HOOKS_DIR="\${TEMPER_HOOKS_DIR:-\(.*\)}"$/\1/p' "$PRECOMMIT" 2>/dev/null || true)"
  if [[ -n "$EMBEDDED_PATH" && "$EMBEDDED_PATH" != "$HOOKS_DIR" ]]; then
    echo "Warning: installed pre-commit hook points at a stale plugin path:" >&2
    echo "  embedded: $EMBEDDED_PATH" >&2
    echo "  current:  $HOOKS_DIR" >&2
    echo "  (The hook has been failing open — its gate checks were no-ops.)" >&2
    echo "  Re-embedding the current path now." >&2
  fi
fi
if [[ -f "$PRECOMMIT" ]] && ! grep -qF "$TEMPER_MARKER" "$PRECOMMIT" 2>/dev/null; then
  BACKUP="$PRECOMMIT.bak.$(date +%Y%m%d%H%M%S 2>/dev/null || echo backup)"
  cp -p "$PRECOMMIT" "$BACKUP"
  echo "Backed up existing pre-commit hook -> $BACKUP" >&2
  echo "(It was not a Temper hook. Temper will overwrite $PRECOMMIT; restore the backup to revert.)" >&2
fi

# Write a pre-commit hook that invokes the Temper scripts. Fail-open by design:
# missing scripts => exit 0; a detected secret or not-green check => exit 1 (block).
# HOOKS_DIR is the canonical location of the Temper scripts at install time and is
# embedded into the hook; TEMPER_HOOKS_DIR overrides it if the scripts move later.
cat > "$PRECOMMIT" <<HOOK
#!/usr/bin/env bash
# Temper native pre-commit hook (installed by scripts/guards/install.sh).
# Fail-open: missing scripts never block. Only a detected violation blocks.
set -uo pipefail
TEMPER_HOOKS_DIR="\${TEMPER_HOOKS_DIR:-$HOOKS_DIR}"

# Git hooks are not guaranteed to run with CWD at the worktree root on every
# platform/version — pin it explicitly so 'temper gate commit' (which resolves
# .temper/ and .claude/temper.config relative to \$(pwd)) reads the right project.
cd "\$(git rev-parse --show-toplevel)" || exit 0

# Absent scripts dir => no-op (degradation contract).
[[ -d "\$TEMPER_HOOKS_DIR" ]] || exit 0

# 1. Secrets.
[[ -f "\$TEMPER_HOOKS_DIR/block-secrets.sh" ]] && { bash "\$TEMPER_HOOKS_DIR/block-secrets.sh" || exit 1; }

# 2. Every /temper gate must be green (or explicitly overridden) — the commit gate
# itself, computed by the temper CLI from the evidence ledger. Absent .temper/ state
# (repo doesn't use /temper for this commit, or CLI missing) => fail-open.
TEMPER_BIN="\$(dirname "\$TEMPER_HOOKS_DIR")/temper"
if [[ -x "\$TEMPER_BIN" && -d .temper ]]; then
  "\$TEMPER_BIN" gate commit || exit 1
elif [[ -f "\$TEMPER_HOOKS_DIR/verify-tests-ran.sh" ]]; then
  # Fallback for a project that only installed the guardrails pack without the CLI.
  bash "\$TEMPER_HOOKS_DIR/verify-tests-ran.sh" || exit 1
fi

exit 0
HOOK

chmod +x "$PRECOMMIT"

if [[ "$MODE" == "global" ]]; then
  git config core.hooksPath ".git/hooks-temper" 2>/dev/null || true
  echo "Installed Temper pre-commit hook via core.hooksPath -> $TARGET_DIR"
else
  echo "Installed Temper pre-commit hook -> $PRECOMMIT"
fi
echo "To uninstall: rm -f $PRECOMMIT (and unset core.hooksPath if --global was used)."
echo "A prior non-Temper hook, if any, was backed up alongside as $PRECOMMIT.bak.* ."
