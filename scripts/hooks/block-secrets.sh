#!/usr/bin/env bash
#
# block-secrets.sh — PreToolUse / pre-commit secret detector.
#
# Deterministic, non-model: blocks a commit/edit when a known secret pattern is matched.
#
# DEGRADATION CONTRACT (non-negotiable):
#   - Detected secret pattern  => exit 2  (BLOCK — the one fail-closed path)
#   - No match                 => exit 0  (pass)
#   - Internal error / missing => exit 0  (FAIL-OPEN. A script bug or missing input must
#                                          never block a commit. Only a *detected* secret
#                                          blocks.)
#
# Inputs: reads staged files (git) when run as a pre-commit hook, or the file passed on
# stdin / via $CLAUDE_FILE_PATH when run as a PreToolUse hook. Falls back to scanning
# whatever text is available; absence of input => exit 0.
set -uo pipefail

# Fail-open wrapper: any unhandled error exits 0, never 2.
_main() {
  # High-precision patterns. Conservative: favor false-negatives over false-positives.
  # A broad pattern that blocks legitimate commits is a developer-workflow DoS.
  local -a patterns=(
    'AKIA[0-9A-Z]{16}'                       # AWS access key ID
    'gh[ps]_[0-9A-Za-z]{36}'                 # GitHub token (pat/secret)
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'     # private key header
    # Live API keys: vendor-specific formats only (H-1). A bare sk-[20+] catches
    # documentation/fixture strings and is a DX DoS. Anthropic live keys are
    # sk-ant-...{50,}; OpenAI live keys are sk-[A-Za-z0-9]{48} (legacy) /
    # sk-proj-... Newer OpenAI keys carry sk-proj- / sk-svcacct- prefixes.
    'sk-ant-[A-Za-z0-9_-]{50,}'              # Anthropic live API key
    'sk-proj-[A-Za-z0-9_-]{40,}'             # OpenAI project API key
    'sk-svcacct-[A-Za-z0-9_-]{40,}'          # OpenAI service-account key
    'sk-[A-Za-z0-9]{48}'                     # OpenAI legacy live API key (exact length)
  )

  # Gather the text to scan.
  local text=""
  if [[ -n "${CLAUDE_FILE_PATH:-}" && -f "${CLAUDE_FILE_PATH}" ]]; then
    text+=$(cat "${CLAUDE_FILE_PATH}" 2>/dev/null || true)$'\n'
  fi
  # stdin (PreToolUse often pipes the tool payload / file content).
  if [[ ! -t 0 ]]; then
    text+=$(cat 2>/dev/null || true)$'\n'
  fi
  # Staged files (pre-commit). Best-effort; ignore git failures.
  if command -v git >/dev/null 2>&1; then
    local staged
    staged=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
    if [[ -n "$staged" ]]; then
      while IFS= read -r f; do
        [[ -f "$f" ]] && text+=$(cat "$f" 2>/dev/null || true)$'\n'
      done <<<"$staged"
    fi
  fi

  # Nothing to scan => pass.
  [[ -z "$text" ]] && return 0

  local joined
  joined=$(IFS='|'; echo "${patterns[*]}")
  local match
  # grep -E for alternation. -o to report the matched token.
  match=$(printf '%s' "$text" | grep -Eo "$joined" 2>/dev/null | head -1 || true)
  if [[ -n "$match" ]]; then
    echo "BLOCK: detected likely secret pattern: '${match}'" >&2
    echo "Refusing commit/edit. Remove the secret or place it in an env var / secrets store." >&2
    return 2
  fi
  return 0
}

_main "$@"
