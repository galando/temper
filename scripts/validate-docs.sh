#!/usr/bin/env bash
# validate-docs.sh — Validate documentation consistency
# Offline-safe, no network calls.
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required but not found in PATH"; exit 1; }

# With CDPATH set, cd prints the folder it enters, and the path below would hold it twice.
unset CDPATH
# The plugin folder: this script sits in its scripts folder, so strip that literal suffix.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${HERE%/scripts}"
[[ "$REPO_ROOT" != "$HERE" ]] || { echo "FAIL: cannot find the plugin folder from $HERE"; exit 1; }
PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# 1. docs/commands.md names every command the plugin ships. The command list is the one in
# .claude-plugin/plugin.json, where each command file is spelled out in full, plus every
# commands/<name>.md file that git ls-files prints (tracked, plus new files git does not
# ignore; no glob). A command file that plugin.json does not list fails too.
COMMANDS_MD="$REPO_ROOT/docs/commands.md"
PJ="$REPO_ROOT/.claude-plugin/plugin.json"

if [[ -f "$COMMANDS_MD" && -f "$PJ" ]]; then
  # Extract command names from commands.md (e.g., /temper, /temper:plan, etc.)
  MD_CMDS=$(grep -oE '/temper(:[a-z]+)?' "$COMMANDS_MD" | sort -u || true)
  # One line per command (its slash command name), BAD for a plugin.json entry that is not a
  # plain .md name in the commands folder, UNLISTED for a command file plugin.json leaves out.
  PJ_CMDS=$( (cd "$REPO_ROOT" && git ls-files -z -co --exclude-standard -- commands 2>/dev/null || true) | python3 -c "
import json, re, sys
PRE = './commands/'
def slash(stem):
    return '/temper' if stem == 'temper' else '/temper:' + stem
listed = set()
for c in json.load(open(sys.argv[1])).get('commands', []):
    name = c[len(PRE):] if isinstance(c, str) and c.startswith(PRE) else ''
    m = re.fullmatch(r'([a-z0-9-]+)\.md', name)
    if not m:
        print('BAD ' + str(c))
    else:
        listed.add(name)
        print(slash(m.group(1)))
for rel in sorted(set(sys.stdin.read().split('\0'))):
    parts = rel.split('/')
    if len(parts) == 2 and parts[0] == 'commands' and parts[1].endswith('.md') and parts[1] not in listed:
        print('UNLISTED ' + rel)
        print(slash(parts[1][:-len('.md')]))
" "$PJ" 2>/dev/null || echo "BAD plugin.json could not be read")
  BAD_CMDS=$(printf '%s\n' "$PJ_CMDS" | sed -n 's/^BAD //p')
  UNLISTED_CMDS=$(printf '%s\n' "$PJ_CMDS" | sed -n 's/^UNLISTED //p')
  FILE_CMDS=$(printf '%s\n' "$PJ_CMDS" | grep -v -e '^BAD ' -e '^UNLISTED ' | sort -u || true)

  if [[ -n "$BAD_CMDS" ]]; then
    fail "plugin.json command entries that are not a plain .md name in the commands folder:"
    echo "$BAD_CMDS" | sed 's/^/  /'
  fi
  if [[ -n "$UNLISTED_CMDS" ]]; then
    fail "command files that .claude-plugin/plugin.json does not list:"
    echo "$UNLISTED_CMDS" | sed 's/^/  /'
  fi
  MISSING_IN_MD=$(comm -23 <(echo "$FILE_CMDS") <(echo "$MD_CMDS") || true)
  if [[ -n "$MISSING_IN_MD" ]]; then
    fail "Commands in plugin.json or the commands folder but missing from docs/commands.md:"
    echo "$MISSING_IN_MD" | sed 's/^/  /'
  else
    ok
  fi
else
  fail "docs/commands.md or .claude-plugin/plugin.json not found"
fi

# 2. All markdown links in docs/ resolve to existing files.
# Resolve each link relative to the DIRECTORY OF THE FILE THAT CONTAINS IT — the way
# GitHub and Jekyll actually resolve a relative link. (Resolving from docs/ root instead
# passes a link that 404s in a subdirectory file, e.g. `decisions/x.md` written inside
# docs/decisions/y.md — the exact bug this check exists to catch.) Skip .html (Jekyll).
# The docs files come from git ls-files, and a link target is looked up in that list, never
# joined onto a folder and opened. A target with '..' is reported as broken: it leaves docs/,
# which is the root of the published site, so it would not resolve there either.
BROKEN_LINKS=$( (cd "$REPO_ROOT" && git ls-files -z -co --exclude-standard -- docs 2>/dev/null || true) | python3 -c "
import os, posixpath, re, sys
root = sys.argv[1]
listed = [p for p in sys.stdin.read().split('\0') if p]
if not listed:
    print('NO-LIST')
    sys.exit(0)
present = {p for p in listed
           if p.startswith('docs/') and '..' not in p.split('/') and os.path.isfile(os.path.join(root, p))}
folders = set()
for p in present:
    d = posixpath.dirname(p)
    while d:
        folders.add(d)
        d = posixpath.dirname(d)
out = set()
for src in sorted(present):
    if not src.endswith('.md'):
        continue
    for line in open(os.path.join(root, src), encoding='utf-8', errors='replace'):
        for link in re.findall(r'\]\(([^)]+)\)', line):
            if re.search(r'http|mailto|\.html', link):
                continue
            link = link.strip()
            target = link.split('#', 1)[0]
            if not target:
                continue
            if '..' in target:
                out.add(link + ' (in ' + src + ', uses ..)')
                continue
            if target.startswith('/'):
                target = posixpath.normpath('docs' + target)
            else:
                target = posixpath.normpath(posixpath.join(posixpath.dirname(src), target))
            if target in present or target + '.md' in present or target in folders:
                continue
            out.add(link + ' (in ' + src + ')')
print('\n'.join(sorted(out)))
" "$REPO_ROOT" || echo "(the link check could not run)")

if [[ -z "$BROKEN_LINKS" ]]; then
  ok
elif [[ "$BROKEN_LINKS" == "NO-LIST" ]]; then
  fail "docs/ link check needs a git checkout (git ls-files listed nothing)"
else
  fail "Broken internal links in docs/:"
  echo "$BROKEN_LINKS" | sort -u | sed 's/^/  /'
fi

# 3. getting-started.md contains installation instructions
GS="$REPO_ROOT/docs/getting-started.md"
if [[ -f "$GS" ]]; then
  if grep -qi "install\|setup\|getting started" "$GS"; then
    ok
  else
    fail "docs/getting-started.md missing install/setup instructions"
  fi
else
  fail "docs/getting-started.md not found"
fi

# 4. index.html contains basic structure tags
INDEX="$REPO_ROOT/docs/index.html"
if [[ -f "$INDEX" ]]; then
  for tag in "<html" "<head" "<body"; do
    if grep -q "$tag" "$INDEX"; then
      ok
    else
      fail "docs/index.html missing $tag tag"
    fi
  done
else
  fail "docs/index.html not found"
fi

# 5. No token-optimization advice in the project CLAUDE.md's *rendered* text.
# Tokenomics is retired (docs/history/tokenomics.md); an external tool used to re-inject
# a TOKENOMICS block of standing advice into every session's context.
#
# This checks what the file actually contributes to context, i.e. after HTML comments are
# stripped — not the raw source. A raw grep passes a comment that quotes the marker
# syntax, because the quoted close-delimiter ends the comment early and spills the rest
# back into view. That exact bug shipped once. See docs/context-hygiene.md.
PROJECT_CLAUDE_MD="$REPO_ROOT/.claude/CLAUDE.md"
if [[ -f "$PROJECT_CLAUDE_MD" ]]; then
  TOKENOMICS_LEAK=$(python3 -c "
import re, sys
src = open(sys.argv[1]).read()
visible = re.sub(r'<!--.*?-->', '', src, flags=re.DOTALL)
# Anything a stray delimiter left behind is a leak by definition.
markers = ['TOKENOMICS:START', 'TOKENOMICS:END', '-->', '<!--']
advice = ['Token Optimization', 'prefer Sonnet', '/compact after turn', 'context snowballs']
hits = [m for m in markers + advice if m.lower() in visible.lower()]
print('; '.join(hits))
" "$PROJECT_CLAUDE_MD" 2>/dev/null)
  if [[ -n "$TOKENOMICS_LEAK" ]]; then
    fail ".claude/CLAUDE.md leaks token-optimization advice into rendered context ($TOKENOMICS_LEAK) — tokenomics is retired (docs/history/tokenomics.md)"
  else
    ok
  fi
else
  fail ".claude/CLAUDE.md not found"
fi

# 6. Regression guard: the choreography removed in v8's context pass stays removed.
# This does not judge prose quality — it cannot. It pins the specific micro-management
# patterns that were cut (fixed subagent arithmetic, attention-percentage budgets), so
# reintroducing one is a deliberate act with a failing check attached rather than a quiet
# drift back. See docs/context-hygiene.md.
CHOREO=$(grep -rnE 'groups of ~[0-9]+|max [0-9]+ parallel|[0-9]+% of attention|[Ww]eight [0-9]+% changed' \
  "$REPO_ROOT/reference" "$REPO_ROOT/packs" 2>/dev/null || true)
if [[ -z "$CHOREO" ]]; then
  ok
else
  fail "choreography patterns reintroduced (v8 context pass removed these):"
  echo "$CHOREO" | sed 's/^/  /'
fi

# 7. Grouped Build docs: the user guide exists, says opt-in + experimental, names every run state
# file, is linked from getting-started.md, and ADR 0011 is Accepted.
GB="$REPO_ROOT/docs/grouped-build.md"
ADR="$REPO_ROOT/docs/decisions/0011-grouped-build.md"
if [[ -f "$GB" ]] && grep -qi 'experimental' "$GB" && grep -q 'opt-in' "$GB" \
   && grep -q '\.temper/groups\.json' "$GB" && grep -q '\.temper/usage\.json' "$GB" && grep -q '\.temper/\.lock/' "$GB" \
   && grep -q 'temper group report --json' "$GB" && grep -q 'temper report --json' "$GB" \
   && grep -q 'grouped-build.md' "$REPO_ROOT/docs/getting-started.md" \
   && [[ -f "$ADR" ]] && grep -q '^\*\*Status:\*\* Accepted' "$ADR" && grep -q 'D-07' "$ADR"; then
  ok
else
  fail "grouped Build docs incomplete (docs/grouped-build.md, link in getting-started.md, ADR 0011 Accepted with D-01..D-07)"
fi

echo ""
echo "=== validate-docs.sh ==="
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
