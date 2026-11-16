# Case file 32 (the one go build, phase 1): sourced by test-temper.sh after the case files before it. The cases read
# files of the repository and run no CLI call. Tokens: tooling: (WP01), room: (WP02), flow: (WP03).

# --- tooling (WP01): the runner finds its case files, the shards, the fixtures, the helpers, names, changelog, gate, CI ---
_t32_sel="$REPO_ROOT/scripts/selftest"
_t32_files="$(cd "$_t32_sel" && for f in temper-cases-*.sh; do n="${f#temper-cases-}"; echo "${n%.sh}"; done | sort -n | tr '\n' ' ')"
_t32_list="$(bash "$_t32_sel/run-selftest.sh" --list 2>&1)"
assert_eq "tooling: the runner lists every case file once" "$_t32_files" \
  "$(printf '%s\n' $_t32_list | sort -n | tr '\n' ' ')"

_t32_shards=""
for _k in 1 2 3 4 5 6; do
  _t32_shards="$_t32_shards$(bash "$_t32_sel/run-selftest.sh" --shard "$_k/6" --list 2>&1 | sed "s/^/$_k:/")"$'\n'
done
assert_eq "tooling: six shards cover every case file once, pairs together" "$(printf '%s\n' "$_t32_list" | sort)|1|1" \
  "$(printf '%s' "$_t32_shards" | sed '/^$/d; s/^[0-9]*://' | sort)|$(printf '%s' "$_t32_shards" | grep -c '^[0-9]*:2 3$')|$(printf '%s' "$_t32_shards" | grep -c '^[0-9]*:8 9$')"

assert_eq "tooling: the fixture modules hold one view per line and are under 200,000 bytes" "ok|ok" \
  "$(python3 -I - "$_t32_sel/view-fixtures.ts" "$_t32_sel/view-fixtures-2.ts" <<'PY'
import json, os, sys
out = []
for p in sys.argv[1:]:
    lines = open(p, encoding="utf-8").read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    why = ""
    if os.path.getsize(p) >= 200000:
        why = "%d bytes" % os.path.getsize(p)
    elif not (lines[0].startswith("//") and lines[1].startswith("//")):
        why = "no two comment lines"
    elif not (lines[2].startswith("export const ") and lines[2].endswith("{")):
        why = "no export line"
    elif lines[-1] != "}":
        why = "no closing line"
    else:
        views = json.loads(open(p, encoding="utf-8").read().split("= ", 1)[1])
        body = lines[3:-1]
        if len(body) != len(views):
            why = "%d lines for %d views" % (len(body), len(views))
        else:
            for i, line in enumerate(body):
                one = json.loads("{" + line.rstrip(",") + "}")
                if list(one) != [sorted(views)[i]]:
                    why = "line %d holds no single view in key order" % (i + 4)
                    break
    out.append(why or "ok")
print("|".join(out))
PY
)"

assert_eq "tooling: case-helpers-5.sh holds no assertion" "0" "$(grep -c 'assert_' "$_t32_sel/case-helpers-5.sh")"

assert_eq "tooling: no script reads a name it does not define" "ok" \
  "$(cd "$REPO_ROOT" && python3 -I scripts/selftest/check-names.py 2>&1 | tail -1)"

_t32_cl="$REPO_ROOT/CHANGELOG.md"; _t32_old="$REPO_ROOT/docs/history/changelog-before-9.7.md"
assert_eq "tooling: the changelog starts at 9.7.0 and the older entries are in docs/history" "0|yes|1|1|1|## v9.8.5: a run that asks twice" \
  "$(grep -c '^## v9\.6' "$_t32_cl")|$([[ -f "$_t32_cl" && $(wc -c < "$_t32_cl") -lt 196608 ]] && echo yes || echo no)|$(grep -c '^## v9\.6\.8' "$_t32_old" 2>/dev/null || true)|$(grep -c '^## v5\.0\.1' "$_t32_old" 2>/dev/null || true)|$(grep -c '^## v9\.8\.5' "$_t32_cl")|$(grep '^## v9\.8\.5' "$_t32_cl")"

_t32_out="$(bash "$REPO_ROOT/scripts/verify.sh" bogus 2>&1)"; _t32_rc=$?
assert_eq "tooling: verify.sh names quick and full and refuses another word" "2|1|1" \
  "$_t32_rc|$(printf '%s' "$_t32_out" | grep -q 'quick' && echo 1 || echo 0)|$(printf '%s' "$_t32_out" | grep -q 'full' && echo 1 || echo 0)"

_t32_wf="$REPO_ROOT/.github/workflows/quality.yml"
assert_eq "tooling: the workflow cancels a superseded pull request run and ends in one gate job" "1|1|1|1" \
  "$(grep -c '^concurrency:' "$_t32_wf")|$(grep -c '^ *cancel-in-progress:' "$_t32_wf")|$(grep -c '^ *if: always()' "$_t32_wf")|$(awk '/^  changes:/ {on=1; next} /^  [a-z0-9_-]+:/ {on=0} on' "$_t32_wf" | grep -c 'github.base_ref' | sed 's/^[1-9][0-9]*$/1/')"

# --- room (WP02): the code moved out of scripts/temper into Python modules, and the room that leaves ---
_t32_cli="$REPO_ROOT/scripts/temper"
assert_eq "room: scripts/temper leaves 40,000 bytes free" "yes" \
  "$([[ $(wc -c < "$_t32_cli") -le 222144 ]] && echo yes || echo "no: $(wc -c < "$_t32_cli" | tr -d ' ') bytes")"
assert_eq "room: the CLI holds at most one Python heredoc" "yes" \
  "$([[ $(grep -c "<<'PY'" "$_t32_cli") -le 1 ]] && echo yes || echo "no: $(grep -c "<<'PY'" "$_t32_cli")")"
assert_eq "room: the new modules run isolated" "ok" \
  "$(python3 -I - "$REPO_ROOT" <<'PY'
import ast, os, re, sys
root = sys.argv[1]
mods = ("json_ops", "state_ops", "ledger_ops", "spec_text", "commit_rows", "report_ops", "groups_ops")
bad = []
for n, line in enumerate(open(os.path.join(root, "scripts", "temper"), encoding="utf-8"), 1):
    for m in mods:
        for hit in re.finditer(re.escape("$SCRIPTS_DIR/%s.py" % m), line):
            if not line[:hit.start()].endswith('python3 -I "'):
                bad.append("scripts/temper:%d starts %s without python3 -I" % (n, m))
for m in mods:
    path = os.path.join(root, "scripts", m + ".py")
    if not os.path.isfile(path):
        bad.append("%s.py is missing" % m)
        continue
    text = open(path, encoding="utf-8").read()
    if "sys.path" in text:
        bad.append("%s.py names sys.path" % m)
    if any(isinstance(x, ast.ImportFrom) and any(a.name == "*" for a in x.names) for x in ast.walk(ast.parse(text))):
        bad.append("%s.py has a star import" % m)
print("; ".join(bad) or "ok")
PY
)"
unset _t32_sel _t32_files _t32_list _t32_shards _t32_cl _t32_old _t32_out _t32_rc _t32_wf _t32_cli _k
