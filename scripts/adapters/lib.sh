#!/usr/bin/env bash
#
# lib.sh — shared helpers for the vendor-neutral adapter generators
# (generate-codex.sh, generate-cursor-plugin.sh, generate-gemini.sh).
#
# SOURCED, never executed directly. bash + python3-stdlib only, zero network,
# deterministic (same inputs -> byte-identical outputs).
#
# Does NOT touch scripts/generate-cursor.sh or .cursor/ (legacy, frozen —
# Decision 2, plan.md revision 2). This file introduces a NEW helper surface
# for the NEW native-plugin generators; it does not refactor the legacy one.
#
# Functions:
#   plugin_version                         -> X.Y.Z on stdout
#   strip_frontmatter                      stdin -> stdout (body only)
#   derive_description <file>              -> description string on stdout
#   list_sorted_dirs <parent-dir>          -> child dir names, one per line, LC_ALL=C sorted
#   list_sorted_md_names <dir>             -> *.md basenames (no extension), LC_ALL=C sorted
#   rewrite_claude_isms                    stdin -> stdout (Claude constructs neutralized)
#   gate_epilogue <stage>                  -> fixed gate-protocol epilogue text on stdout
#   stamp_header_md <source> <tier> <verified-date>    -> HTML-comment stamp block
#   stamp_header_toml <source> <tier> <verified-date>  -> '#'-comment stamp block
#   json_emit                              stdin (JSON text) -> stdout (normalized JSON)
#   render_skill <src-file> <skill-name> <tier-note> <verified-date> [stage]
#                                           -> full SKILL.md body on stdout
#
# Env expected by callers: REPO_ROOT must be set before sourcing (each
# generator resolves its own).

if [[ -z "${REPO_ROOT:-}" ]]; then
    echo "lib.sh: REPO_ROOT must be set before sourcing" >&2
    return 1 2>/dev/null || exit 1
fi

command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required" >&2; exit 1; }

# --- plugin_version -----------------------------------------------------
plugin_version() {
    python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" \
        "$REPO_ROOT/.claude-plugin/plugin.json"
}

# --- strip_frontmatter ----------------------------------------------------
# Strip a leading YAML frontmatter block (--- ... ---) from stdin, emit the
# rest unchanged. NOTE: uses `python3 -c` (script as an argv string), not
# `python3 - <<PY ... PY` (a heredoc attached to `python3 -` becomes ITS
# stdin, i.e. the interpreter reads the heredoc as the *script* to run and
# leaves the real piped input at EOF before the script body ever calls
# sys.stdin.read() — a real bug confirmed present in the legacy, frozen
# generate-cursor.sh; every function here avoids that pattern deliberately).
strip_frontmatter() {
    python3 -c "$(cat <<'PY'
import re, sys
text = sys.stdin.read()
m = re.match(r'^---\s*\n.*?\n---\s*\n?', text, re.DOTALL)
if m:
    sys.stdout.write(text[m.end():])
else:
    sys.stdout.write(text)
PY
)"
}

# --- derive_description ---------------------------------------------------
# frontmatter `description:` -> else first markdown heading -> else empty.
derive_description() {
    python3 - "$1" <<'PY'
import re, sys
path = sys.argv[1]
desc = None
try:
    text = open(path, encoding='utf-8').read()
except OSError:
    sys.exit(0)
m = re.match(r'^---\s*\n(.*?)\n---\s*\n', text, re.DOTALL)
if m:
    fm = m.group(1)
    dm = re.search(r'^description:\s*["\']?(.*?)["\']?\s*$', fm, re.MULTILINE)
    if dm:
        desc = dm.group(1).strip().strip('"').strip("'")
if not desc:
    for line in text.splitlines():
        s = line.strip()
        if s.startswith('#'):
            desc = s.lstrip('#').strip()
            break
if desc:
    print(desc.replace('"', '\\"'))
PY
}

# --- sorted enumeration (bash-3.2-safe: no associative/mapfile assumptions) -
list_sorted_dirs() {
    # $1 = parent dir; prints immediate child directory names, LC_ALL=C sorted.
    local parent="$1"
    find "$parent" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | LC_ALL=C sort
}

list_sorted_md_names() {
    # $1 = dir containing *.md files; prints basenames without .md, LC_ALL=C sorted.
    local dir="$1"
    ( shopt -s nullglob; for f in "$dir"/*.md; do basename "$f" .md; done ) | LC_ALL=C sort
}

# --- rewrite_claude_isms ---------------------------------------------------
# One python3 pass applying the shared Claude->neutral rewrite table
# (plan.md "Transform rules"): AskUserQuestion, Agent-subprocess spawn
# instructions, $CLAUDE_PLUGIN_ROOT, and /temper:{stage} cross-references.
# Purely textual/deterministic — no model call, no judgment.
rewrite_claude_isms() {
    python3 -c "$(cat <<'PY'
import re, sys
text = sys.stdin.read()

# 1. $CLAUDE_PLUGIN_ROOT -> repo-relative path. Trailing-slash form first so
#    "$CLAUDE_PLUGIN_ROOT/scripts/temper" -> "scripts/temper" (not "./scripts/temper").
text = text.replace('$CLAUDE_PLUGIN_ROOT/', '')
text = text.replace('${CLAUDE_PLUGIN_ROOT}/', '')
text = re.sub(r'\$\{?CLAUDE_PLUGIN_ROOT\}?', '.', text)

# 2. Agent(...) subprocess-spawn call sites -> inline-execution instruction.
text = re.sub(
    r'Agent\((agents/[a-zA-Z0-9_-]+\.md)\)',
    r'run \1 inline in the current context (no subprocess)',
    text,
)
# Prose mentions of the Agent-subprocess pattern.
text = re.sub(r'\bisolated Agent subprocess(es)?\b', r'inline execution in the current context', text)
text = re.sub(r'\bAgent subprocess(es)?\b', 'inline execution', text)
text = re.sub(r'\bAgent-subprocess\b', 'inline-execution', text)
text = re.sub(r'\bsubagents?\b', 'focused inline passes', text)

# 3. AskUserQuestion -> plain ask-and-wait instruction.
text = re.sub(r'\bAskUserQuestion\b', 'ask the user directly and wait for their answer', text)

# 4. /temper:{stage} cross-references -> vendor-neutral phrasing (no assumed
#    slash-command syntax, since Codex/Cursor skills are not invoked that way).
text = re.sub(r'/temper:([a-zA-Z][a-zA-Z0-9_-]*)', r'the Temper "\1" stage', text)
# Bare "/temper" (the unified command) -> neutral phrasing too.
text = re.sub(r'(?<![:\w])/temper\b(?!["\w:-])', 'the Temper unified pipeline', text)

sys.stdout.write(text)
PY
)"
}

# --- gate_epilogue ----------------------------------------------------------
# Fixed gate-protocol epilogue: single source of truth appended to every
# generated stage skill/command (SC4/SC8 — no generated file may reimplement
# verdict logic; every gate reference is an instruction to run the CLI).
gate_epilogue() {
    local stage="${1:-}"
    if [[ -n "$stage" ]]; then
        cat <<EOF

## Gate Protocol (do not skip)

Record evidence for every claim as you work, then compute — never self-assert — the
verdict:

\`\`\`
scripts/temper evidence add --stage $stage --claim "<what you're proving>" \\
  --cmd "<the exact command you ran>" --exit <code> --label PROVEN
scripts/temper gate $stage
\`\`\`

Paths above are relative to this plugin's own installed root (wherever the
marketplace source resolved this repo on disk), not necessarily your project's working
directory — resolve \`scripts/temper\` to that location if your shell's cwd differs.
EOF
    else
        cat <<'EOF'

## Gate Protocol (do not skip)

Every stage's verdict is computed by the CLI from an evidence ledger, never
self-asserted:

```
scripts/temper evidence add --stage <stage> --claim "..." --cmd "..." --exit <code> --label PROVEN
scripts/temper gate <stage>
```

Paths above are relative to this plugin's own installed root (wherever the
marketplace source resolved this repo on disk), not necessarily your project's working
directory — resolve `scripts/temper` to that location if your shell's cwd differs.
EOF
    fi
}

# --- stamp headers (md/toml — JSON has no comments, see json manifests) -----
stamp_header_md() {
    # $1 = repo-relative source path, $2 = tier note, $3 = plugin version,
    # $4 = upstream-schema verification date (YYYY-MM or "n/a" if not applicable)
    local src="$1" tier="$2" version="$3" verified="$4"
    cat <<EOF
<!--
  AUTO-GENERATED — do not hand-edit. Regenerate via the adapter generator script.
  Source: $src
  Plugin version: $version
  Tier: $tier
  Upstream schema verified: $verified
-->

EOF
}

stamp_header_toml() {
    local src="$1" tier="$2" version="$3" verified="$4"
    cat <<EOF
# AUTO-GENERATED — do not hand-edit. Regenerate via the adapter generator script.
# Source: $src
# Plugin version: $version
# Tier: $tier
# Upstream schema verified: $verified

EOF
}

# --- json_emit ---------------------------------------------------------------
# Shared JSON *serializer* (not schema) — deterministic re-emit of stdin JSON.
# Does NOT sort keys: determinism comes from insertion order in the producing
# python dict, which also preserves human-intended field order. indent=2,
# ensure_ascii=False, single trailing newline.
json_emit() {
    python3 -c 'import json,sys; json.dump(json.load(sys.stdin), sys.stdout, indent=2, ensure_ascii=False); print()'
}

# --- render_skill --------------------------------------------------------
# Shared Codex+Cursor transform: source command/skill markdown -> a full
# SKILL.md body (frontmatter + stamp + gate epilogue + rewritten content).
# $1 = source file (repo-relative or absolute), $2 = skill name (e.g. temper-build),
# $3 = tier note, $4 = verified date, $5 = stage name for the gate epilogue (optional;
#      omit for temper-core, which has no single stage).
render_skill() {
    local src_file="$1" skill_name="$2" tier_note="$3" verified_date="$4" stage="${5:-}"
    local version rel_src desc body
    version=$(plugin_version)
    rel_src="${src_file#"$REPO_ROOT"/}"
    desc=$(derive_description "$src_file")
    [[ -z "$desc" ]] && desc="Temper: $skill_name"

    printf -- '---\n'
    printf 'name: %s\n' "$skill_name"
    printf 'description: "%s"\n' "$desc"
    printf -- '---\n\n'
    stamp_header_md "$rel_src" "$tier_note" "$version" "$verified_date"

    body=$(strip_frontmatter < "$src_file" | rewrite_claude_isms)
    printf '%s\n' "$body"
    gate_epilogue "$stage"
}
