# Case file 75 (WP31): the words, the documents, the decision records and version 9.8.5.
# A user learns at most 12 words (scripts/words.json, one line each in the part The words of Getting Started), and no
# text a user reads holds a retired word (armed, park, phase, door, Autonomous Build, Stage by stage, preflight, band,
# hand back and their forms). A project that ran 9.8.4, or the base, is told once that a run now asks twice. Every
# version stamp says 9.8.5, with no bump. The pages say what the code does, the README in at most 80 lines and in its
# parts, and the decision records are on record.
# Sourced by test-temper.sh; its helpers (setup, fresh, nx, _ev, _ran_unattended, _base_known) are used here. Token: w31.
# The rows of done.md that WP31 turns green are the tokens D29c, D29d, D79b, D102, D103 and D108 of case file 46; the
# checks here carry no token of done.md. The texts the mod draws are held by the mod test words.test.tsx (spec test 4).
# A call the CLI does not have yet stays inside $( ... ) or ends in || true, so the file always runs to its end.

# --- the helpers of this file ---
# The retired words of the plan (WP31 mechanism step 2); scripts/words.json may add to them and never drops one.
_RETIRED75='["armed", "arm", "arms", "arming", "parked", "park", "parks", "phase", "phases", "door", "doors", "Autonomous Build", "Stage by stage", "preflight", "band", "hand back"]'
# The notice of mechanism step 3, the one line a project of 9.8.4 or of the base is told once.
_NOTICE75="Temper 9.8.5 asks twice: before any code is written, and at the commit. Pick Ask me at every stage at the first question for the old flow. What changed: docs/getting-started.md."
_clean75() { # an empty work folder
  cd "$WORKDIR" || exit 1
  find "$WORKDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  cd "$WORKDIR" || exit 1
}
_git75() { # a git repository in the work folder with one commit
  git init -q . 2>/dev/null; git config user.email t@example.com; git config user.name t
  printf 'x\n' > README.md; git add README.md; git commit -q -m init
}
_restore75() { # _restore75 <commit> <state>: the project as that Temper left it at that state (saved-old.json, WP07)
  _clean75; _git75
  local b
  b="$(python3 -I - "$TESTS_DIR/saved-old.json" "$1" "$2" "$WORKDIR" "$REPO_ROOT" "$(git rev-parse HEAD)" <<'PY'
import json, os, sys
saved, commit, state, work, plugin, head = sys.argv[1:7]
d = json.load(open(saved))[commit]["states"][state]
for rel, text in d["files"].items():
    p = os.path.join(work, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text.replace("@PROJECT@", work).replace("@PLUGIN@", plugin).replace("@HEAD@", head))
print(d.get("branch") or "master")
PY
)"
  git checkout -q -B "${b:-master}" 2>/dev/null
}
_told75() { # two nexts: told when the say of the first starts with the notice, quiet when no say holds it; then whether
            # the mark .temper/notice.json holds the version as its key, and whether a question of the first holds it
  local a b
  a="$("$TEMPER" next --json 2>/dev/null)"; b="$("$TEMPER" next --json 2>/dev/null)"
  printf '%s,%s,%s,%s' \
    "$(python3 -I -c 'import json,sys; d=json.loads(sys.argv[1] or "{}"); print("told" if str(d.get("say") or "").startswith(sys.argv[2]) else "quiet")' "$a" "$_NOTICE75" 2>/dev/null || echo "no json")" \
    "$(python3 -I -c 'import json,sys; d=json.loads(sys.argv[1] or "{}"); print("told" if "Temper 9.8.5 asks twice" in str(d.get("say") or "") else "quiet")' "$b" 2>/dev/null || echo "no json")" \
    "$(python3 -I -c 'import json,sys
try:
    d = json.load(open(".temper/notice.json"))
    print("mark" if isinstance(d, dict) and "9.8.5" in d else "mark without 9.8.5")
except (OSError, ValueError):
    print("no mark")' 2>/dev/null)" \
    "$(python3 -I -c 'import json,sys; d=json.loads(sys.argv[1] or "{}"); print("in a dialog" if "asks twice" in json.dumps(d.get("ask") or {}) + json.dumps(d.get("blocking_asks") or []) else "no dialog")' "$a" 2>/dev/null || echo "no json")"
}
# What a user reads that holds a retired word (spec tests 2 and 3), at most six places, or "none". Its own reading, apart
# from scripts/check_words.py: the retired list is that of words.json and the plan's, a whole word in any letter case,
# with code spans, code blocks, link targets and key names left out (a word joined to a name by a dot, a hyphen, a slash
# or an underscore is part of the name).
_hits75() { # _hits75 views|pages|options
  python3 -I - "$1" "$REPO_ROOT" "$_RETIRED75" <<'PY'
import json, os, re, sys
part, root, plan = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
def read(rel):
    try:
        return open(os.path.join(root, rel), encoding="utf-8").read()
    except OSError:
        return None
words = list(plan)
try:
    r = json.loads(read("scripts/words.json") or "{}").get("retired")
except (ValueError, AttributeError):
    r = None
if isinstance(r, dict):
    words += list(r.keys())
elif isinstance(r, list):
    for x in r:
        if isinstance(x, str):
            words.append(x)
        elif isinstance(x, (list, tuple)) and x and isinstance(x[0], str):
            words.append(x[0])
        elif isinstance(x, dict):
            words += [x[k] for k in ("word", "retired") if isinstance(x.get(k), str)]
            words += [w for w in x.get("words") or [] if isinstance(w, str)]
alts = sorted({re.escape(w.strip()).replace(r"\ ", r"\s+") for w in words if w.strip()}, key=len, reverse=True)
WORD = re.compile(r"(?<![\w./-])(?:%s)(?![\w/-]|\.\w)" % "|".join(alts), re.I)
def prose(t):
    t = re.sub(r"```.*?```", " ", t, flags=re.S)
    t = re.sub(r"`[^`\n]*`", " ", t)
    t = re.sub(r"\]\([^)\s]*\)", "]", t)
    return re.sub(r"https?://\S+", " ", t)
hits = []
def look(where, text):
    m = WORD.search(prose(text or ""))
    if m:
        hits.append("%s: %s" % (where, m.group(0)))
if part == "views":
    for f in ("view-fixtures.ts", "view-fixtures-2.ts"):
        t = read(os.path.join("scripts", "selftest", f)) or ""
        vs = json.loads(t[t.index("= {") + 2:]) if "= {" in t else {}
        for name, v in vs.items():
            texts = []
            def asks(o):
                if isinstance(o, dict):
                    for k, x in o.items():
                        if k in ("calls", "do"):
                            continue
                        if k in ("question", "header", "label", "description") and isinstance(x, str):
                            texts.append(x)
                        else:
                            asks(x)
                elif isinstance(o, list):
                    for x in o:
                        asks(x)
            def card(o):
                if isinstance(o, dict):
                    for k, x in o.items():
                        if k not in ("id", "file", "run_id", "tag", "kind"):
                            card(x)
                elif isinstance(o, list):
                    for x in o:
                        card(x)
                elif isinstance(o, str):
                    texts.append(o)
            asks(v.get("ask")); asks(v.get("blocking_asks"))
            nxt = v.get("next")
            if isinstance(nxt, dict) and isinstance(nxt.get("say"), str):
                texts.append(nxt["say"])
            if isinstance(v.get("status"), str):
                texts.append(v["status"])
            card(v.get("card"))
            for x in texts:
                if WORD.search(x):
                    hits.append("view %s: %s" % (name, WORD.search(x).group(0)))
                    break
elif part == "pages":
    for rel in ("README.md", "docs/getting-started.md", "docs/index.md", "docs/commands.md"):
        look(rel, read(rel))
    tpl = read("templates/temper.config.default") or ""
    look("the comments of the template",
         "\n".join(re.sub(r"^\s*[\w.-]+\s*:", " ", l.split("#", 1)[1]) for l in tpl.splitlines() if "#" in l))
    cmd = read("commands/temper.md") or ""
    args = cmd.split("## Arguments", 1)[1].split("\n## ", 1)[0] if "## Arguments" in cmd else ""
    look("the Arguments table of commands/temper.md", "\n".join(l for l in args.splitlines() if l.strip().startswith("|")))
    look("the description of the manifest", json.loads(read(".claude-plugin/plugin.json") or "{}").get("description", ""))
elif part == "options":
    for key, o in (json.loads(read(".claude-plugin/plugin.json") or "{}").get("userConfig") or {}).items():
        for f in ("title", "description"):
            look("userConfig %s %s" % (key, f), str(o.get(f) or ""))
print(", ".join(hits[:6]) or "none")
PY
}
_doc75() { # _doc75 <path>: the text of a file of the repository, white space joined, or "" when it is missing
  python3 -I -c 'import sys
try:
    print(" ".join(open(sys.argv[1], encoding="utf-8").read().split()))
except OSError:
    print("")' "$REPO_ROOT/$1"
}
_list75() { # _list75 <n>: the first n lines of the input joined by commas, or "none" when there is none
  local x; x="$(head -n "$1" | paste -sd, -)"; echo "${x:-none}"
}
_lacks75() { # _lacks75 <path> <text>...: ok when the file holds none of the texts, else "<path> holds <text>"
  local p="$1" t; shift
  for t in "$@"; do grep -qF -- "$t" "$REPO_ROOT/$p" 2>/dev/null && { echo "$p holds $t"; return; }; done
  echo ok
}

# --- 1. at most 12 words, each with its one line in Getting Started ---
assert_eq "w31 at most 12 words: scripts/words.json holds at most 12 entries under words, each with its line, and the part The words of docs/getting-started.md has one line for each and no other entry" \
  "ok" "$(python3 -I - "$REPO_ROOT" <<'PY'
import json, os, re, sys
root = sys.argv[1]
try:
    w = json.load(open(os.path.join(root, "scripts", "words.json"))).get("words")
except (OSError, ValueError, AttributeError):
    print("no scripts/words.json"); sys.exit(0)
if isinstance(w, dict):
    words = [(k, v) for k, v in w.items()]
else:
    words = []
    for x in w or []:
        if isinstance(x, dict):
            words.append((x.get("word"), x.get("line") or x.get("meaning") or x.get("text")))
        elif isinstance(x, (list, tuple)) and len(x) >= 2:
            words.append((x[0], x[1]))
        else:
            words.append((x, None))
if not words or len(words) > 12:
    print("%d words" % len(words)); sys.exit(0)
bad = [str(k) for k, v in words if not isinstance(k, str) or not isinstance(v, str) or not v.strip()]
if bad:
    print("no line for %s" % ", ".join(bad)); sys.exit(0)
try:
    gs = open(os.path.join(root, "docs", "getting-started.md"), encoding="utf-8").read()
except OSError:
    gs = ""
if "## The words" not in gs:
    print("no part ## The words"); sys.exit(0)
sec = gs.split("## The words", 1)[1].split("\n## ", 1)[0]
terms, header = [], False
for line in sec.splitlines():
    s = line.strip()
    if s.startswith("|"):
        if re.match(r"^\|[\s:|-]+\|?$", s):
            continue
        if not header:
            header = True
            continue
        terms.append(re.sub(r"[*`_]", "", s.strip("|").split("|")[0]).strip().lower())
    elif re.match(r"^[-*] ", s):
        terms.append(re.sub(r"[*`_]", "", re.split(r":|\s[-–—]\s|\|", s[2:], 1)[0]).strip().lower())
want = [k.strip().lower() for k, _ in words]
off = [k for k in want if terms.count(k) != 1] + sorted(set(terms) - set(want))
print("ok" if not off else "lines off for %s" % ", ".join(off))
PY
)"
# the words of mechanism step 1 (my addition: the spec names the 12)
assert_eq "w31 the words are the 12 of the spec: run, stage, intent, criterion, plan, task, gate, check, finding, repair, override, loop back" \
  "check,criterion,finding,gate,intent,loop back,override,plan,repair,run,stage,task" "$(python3 -I - "$REPO_ROOT/scripts/words.json" <<'PY'
import json, sys
try:
    w = json.load(open(sys.argv[1])).get("words")
except (OSError, ValueError, AttributeError):
    print("no scripts/words.json"); sys.exit(0)
ks = list(w.keys()) if isinstance(w, dict) else [x.get("word") if isinstance(x, dict) else (x[0] if isinstance(x, (list, tuple)) else x) for x in w or []]
print(",".join(sorted(str(k).strip().lower() for k in ks)))
PY
)"
assert_eq "w31 the retired list of scripts/words.json holds every word the plan retires, each with what replaces it" "ok" \
  "$(python3 -I - "$REPO_ROOT/scripts/words.json" "$_RETIRED75" <<'PY'
import json, sys
try:
    r = json.load(open(sys.argv[1])).get("retired")
except (OSError, ValueError, AttributeError):
    print("no scripts/words.json"); sys.exit(0)
have = {}
if isinstance(r, dict):
    have = {k.lower(): v for k, v in r.items()}
for x in r if isinstance(r, list) else []:
    if isinstance(x, str):
        have[x.lower()] = None
    elif isinstance(x, (list, tuple)) and x and isinstance(x[0], str):
        have[x[0].lower()] = x[1] if len(x) > 1 else None
    elif isinstance(x, dict):
        use = x.get("use") or x.get("replace") or x.get("instead") or x.get("with") or x.get("say")
        for w in [x.get(k) for k in ("word", "retired")] + list(x.get("words") or []):
            if isinstance(w, str):
                have[w.lower()] = use
missing = [w for w in json.loads(sys.argv[2]) if w.lower() not in have]
bare = [w for w in json.loads(sys.argv[2]) if w.lower() in have and not str(have[w.lower()] or "").strip()]
print("ok" if not missing and not bare else "missing %s; no replacement for %s" % (missing, bare))
PY
)"

# --- 2. no retired word in a question ---
assert_eq "w31 no retired word in a question: no view of the two fixture files holds one in its question, an option's label or description, its say, its status or its card" \
  "none" "$(_hits75 views)"

# --- 3. no retired word on a page a user reads ---
assert_eq "w31 no retired word on a page a user reads: README.md, Getting Started, docs/index.md, docs/commands.md, the comments of the template, the Arguments table of commands/temper.md and the description of the manifest" \
  "none" "$(_hits75 pages)"
# the plugin options a user sets in /config (mechanism step 2: the title of phaseModels says Models per stage)
assert_eq "w31 no retired word in a title or description of the manifest's userConfig" "none" "$(_hits75 options)"
# the word check of the gate: in quality-check.sh, and green
assert_eq "w31 the word check is in the gate: scripts/quality-check.sh runs scripts/check_words.py, and it exits 0" "runs it|0" \
  "$(grep -q 'check_words\.py' "$REPO_ROOT/scripts/quality-check.sh" && echo runs it || echo no)|$(cd "$REPO_ROOT" && python3 -I scripts/check_words.py >/dev/null 2>&1; echo $?)"
# the word check refuses what it must: in a copy, with a words.json of the test's own
_C75="$WORKDIR/words75"; rm -rf "$_C75"; mkdir -p "$_C75/scripts/selftest" "$_C75/docs" "$_C75/templates" "$_C75/commands" "$_C75/.claude-plugin"
cp "$REPO_ROOT/scripts/check_words.py" "$_C75/scripts/" 2>/dev/null
python3 -I - "$_C75" "$_RETIRED75" <<'PY'
import json, os, sys
c, retired = sys.argv[1], json.loads(sys.argv[2])
words = ["run", "stage", "intent", "criterion", "plan", "task", "gate", "check", "finding", "repair", "override", "loop back"]
def w(rel, text):
    with open(os.path.join(c, rel), "w", encoding="utf-8") as f:
        f.write(text)
w("scripts/words.json", json.dumps({"words": {x: "the line of %s" % x for x in words},
                                    "retired": {x: "a plain word" for x in retired}}, indent=1))
view = {"ask": {"question": {"header": "Temper gate", "question": "Plan: the check passed. Approve?",
                             "options": [{"label": "Approve and build", "description": "Runs by itself to the commit."}]}},
        "next": {"say": "Waiting for your answer."}, "status": "Plan: waiting.", "card": {"title": "APPROVE", "foot": ["Nothing is pushed."]}}
for f in ("view-fixtures.ts", "view-fixtures-2.ts"):
    w("scripts/selftest/" + f, "// generated\nexport const VIEWS: Record<string, unknown> = %s\n" % json.dumps({"plan-pass": view}))
w("docs/getting-started.md", "# Getting Started\n\n## The words\n\n| Word | Meaning |\n|---|---|\n" +
  "".join("| %s | the line |\n" % x for x in words) + "\n## What changed from 9.8.4\n\nThe commands.\n")
w("README.md", "# Temper\n\nA sparkline, an alarm, `phases.pipeline` and park-on-touch are names, not words.\n")
w("docs/index.md", "# Temper\n")
w("docs/commands.md", "# Commands\n\nThe key `phaseModels` sets the models per stage.\n")
w("templates/temper.config.default", "# Temper\nautonomy:\n  park-on-touch: []   # the sensitive paths\n")
w("commands/temper.md", "# temper\n\n## Arguments\n\n| Word | What |\n|---|---|\n| `status` | the run |\n\n## Start\n")
w(".claude-plugin/plugin.json", json.dumps({"description": "Gated plan, with a stage bar."}))
PY
_cw75() { (cd "$_C75" && python3 -I scripts/check_words.py 2>&1); }
_cwplant75() { # _cwplant75 <file> <text>: the exit and the fault lines of the check with the text added to the file
  local f="$_C75/$1" keep out rc
  keep="$(cat "$f")"; printf '\n%s\n' "$2" >> "$f"
  out="$(_cw75)"; rc=$?; printf '%s' "$keep" > "$f"
  printf '%s %s' "$rc" "$(printf '%s\n' "$out" | grep -c '^FAIL:')"
}
_d75="clean=$(_cw75 >/dev/null; echo $?)"
_d75+="|readme=$(_cwplant75 README.md 'The armed run parks here.')"
_d75+="|view=$(python3 -I -c 'import sys; p=sys.argv[1]; t=open(p).read(); open(p,"w").write(t.replace("Waiting for your answer.", "The run stopped for you in this phase."))' "$_C75/scripts/selftest/view-fixtures-2.ts"; _cw75 >/dev/null; echo $?)"
cp "$_C75/scripts/selftest/view-fixtures.ts" "$_C75/scripts/selftest/view-fixtures-2.ts"
_d75+="|template=$(_cwplant75 templates/temper.config.default '# Pick Stage by stage for the old flow.')"
_d75+="|thirteen=$(python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["words"]["approve"]="a word too many"; json.dump(d,open(p,"w"))' "$_C75/scripts/words.json"; _cw75 | grep -c '13 words')"
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["words"].pop("approve"); d["retired"].pop("park"); json.dump(d,open(p,"w"))' "$_C75/scripts/words.json"
_d75+="|park dropped=$(_cw75 | grep -c 'park')"
assert_eq "w31 the word check refuses a retired word on a page, in a view and in a comment, a 13th word and a retired word dropped from the list, and passes a name that holds one" \
  "clean=0|readme=1 1|view=1|template=1 1|thirteen=1|park dropped=1" "$_d75"
rm -rf "$_C75"

# --- 5. the notice is said once, to a project of 9.8.4 or of the base, and never to a new one ---
_n75=""
for _c in "7c7a1c1 parked" "10e965a review-finding"; do
  _restore75 ${_c}
  _n75+="$([[ ${_c%% *} == 7c7a1c1 ]] && echo 9.8.4 || echo base)=$(_told75)|"
done
_clean75; _git75; mkdir -p .temper/specs/older; printf '# Intent: an older run\n' > .temper/specs/older/intent.md
_n75+="specs=$(_told75)|"
_clean75; _git75; mkdir -p .temper/archive/older; printf '{}\n' > .temper/archive/older/gate-ledger.json
_n75+="archive=$(_told75)"
assert_eq "w31 the notice is said once: a project with .temper/specs or .temper/archive of an earlier run and no notice mark is told in the say of the first next, which starts with the notice, never in a question, and the mark is written" \
  "9.8.4=told,quiet,mark,no dialog|base=told,quiet,mark,no dialog|specs=told,quiet,mark,no dialog|archive=told,quiet,mark,no dialog" "$_n75"
# lane B of phase 8 (P8-T1): temper go carries it too, in front of its say and in its key notice, once
_restore75 7c7a1c1 parked
_g75='import json,sys
try:
    d = json.loads(sys.argv[1] or "{}")
except ValueError:
    d = {}
print("%s,%s" % ("say" if str(d.get("say") or "").startswith(sys.argv[2]) else "no say",
                 "notice" if d.get("notice") == sys.argv[2] else "no notice"))'
_n75="first=$(python3 -I -c "$_g75" "$("$TEMPER" go 2>/dev/null)" "$_NOTICE75")"
_n75+="|second=$(python3 -I -c "$_g75" "$("$TEMPER" go 2>/dev/null)" "$_NOTICE75")"
assert_eq "w31 temper go carries the notice once: its say starts with it and its key notice holds it, and a second go has neither" \
  "first=say,notice|second=no say,no notice" "$_n75"
_clean75; _git75; "$TEMPER" init >/dev/null 2>&1
_n75="init=$([[ -f .temper/notice.json ]] && echo mark || echo no mark)"
"$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1; _base_known
_n75+="|run=$(_told75)"
assert_eq "w31 the notice is never said to a project temper init just made: init writes the mark, and the run's first next says nothing of it" \
  "init=mark|run=quiet,quiet,mark,no dialog" "$_n75"
# The setup check asks an existing project for temper init once, as a new name joins _RUN_FILES (the trap of the spec):
# that init writes no mark for a project of an earlier Temper, which is still told; git ignores the mark, and state clear
# keeps it (my reading of "have temper init write it for a new project" and of "keep it out of what state clear removes")
_clean75; _git75; mkdir -p .temper/specs/older; printf '# Intent: an older run\n' > .temper/specs/older/intent.md
"$TEMPER" init >/dev/null 2>&1
_n75="after init=$(_told75)"
_n75+="|ignored=$(git check-ignore -q .temper/notice.json 2>/dev/null && echo yes || echo no)"
"$TEMPER" state init demo --feature "the demo thing" >/dev/null 2>&1; "$TEMPER" state clear >/dev/null 2>&1
_n75+="|state clear=$([[ -f .temper/notice.json ]] && echo kept || echo removed),$(_told75 | cut -d, -f1)"
assert_eq "w31 the notice survives the temper init the setup asks of an older project, git ignores its mark, and state clear keeps the mark" \
  "after init=told,quiet,mark,no dialog|ignored=yes|state clear=kept,quiet" "$_n75"

# --- 6. the stamps agree ---
assert_eq "w31 the stamps agree: the manifest says 9.8.5 as at the base, and so do .claude/CLAUDE.md, the README badge, docs/index.html (once), and docs/index.md and Getting Started wherever they state a version" \
  "manifest=9.8.5|base=9.8.5|CLAUDE.md=9.8.5|badge=9.8.5|index.html=9.8.5|index.md=ok|getting-started.md=ok" \
  "$(cd "$REPO_ROOT" && python3 -I - "$(git show 10e965a:.claude-plugin/plugin.json 2>/dev/null)" <<'PY'
import json, re, sys
def read(p):
    try:
        return open(p, encoding="utf-8").read()
    except OSError:
        return ""
try:
    base = json.loads(sys.argv[1]).get("version")
except ValueError:
    base = "unreadable"
m = re.search(r"^\*\*Version:\*\* ([0-9.]+)", read(".claude/CLAUDE.md"), re.M)
b = re.search(r"img\.shields\.io/badge/version-v([0-9.]+)-", read("README.md"))
html = re.findall(r'"version":\s*"([^"]*)"', read("docs/index.html"))
def stated(p):
    t = read(p)
    v = re.findall(r"\bversion\b[:*\s]*v?(\d+\.\d+\.\d+)", t, re.I) + re.findall(r"badge/version-v?(\d+\.\d+\.\d+)", t)
    off = sorted(set(x for x in v if x != "9.8.5"))
    return "ok" if not off else "states " + ",".join(off)
print("manifest=%s|base=%s|CLAUDE.md=%s|badge=%s|index.html=%s|index.md=%s|getting-started.md=%s" % (
    json.loads(read(".claude-plugin/plugin.json")).get("version"), base, m.group(1) if m else "none",
    b.group(1) if b else "none", ",".join(html) or "none", stated("docs/index.md"), stated("docs/getting-started.md")))
PY
)"

# --- 7. the pages match the code: one assert for each place of ux-onboarding.md part 7 a string can prove ---
_pl75="$(cd "$REPO_ROOT" && python3 -I - <<'PY'
import json
t = open("scripts/selftest/view-fixtures.ts", encoding="utf-8").read()
v = json.loads(t[t.index("= {") + 2:])["plan-pass"]
print("|".join(o["label"].replace(" (Recommended)", "") for o in v["ask"]["question"]["options"][:2]))
PY
)"
assert_eq "w31 the pages match the code, 1: docs/commands.md lists no Continue to Build, Open HTML review or Share HTML review as the plan question's options, and names the approval's first two options" \
  "no old list|names $_pl75" "$(python3 -I - "$REPO_ROOT/docs/commands.md" "$_pl75" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
old = re.search(r"^\s*\d+\.\s+(Continue to Build|Open HTML review|Share HTML review)\b", t, re.M)
labels = sys.argv[2].split("|")
print("%s|%s" % ("old list: " + old.group(1) if old else "no old list",
                 "names " + sys.argv[2] if all(l in t for l in labels) else "lacks " + ",".join(l for l in labels if l not in t)))
PY
)"
assert_eq "w31 the pages match the code, 1b: docs/commands.md shows no plan option of a confidence (Confidence: 94%)" "ok" \
  "$(_lacks75 docs/commands.md 'Confidence: 94%')"
assert_eq "w31 the pages match the code, 2: .claude/CLAUDE.md holds no enabled: false" "ok" "$(_lacks75 .claude/CLAUDE.md 'enabled: false')"
assert_eq "w31 the pages match the code, 2b: the template holds no enabled: false" "ok" "$(_lacks75 templates/temper.config.default 'enabled: false')"
assert_eq "w31 the pages match the code, 3: commands/temper.md asks for no HTML page too, and docs/mod.md speaks of no question for one page too" "ok|ok" \
  "$(_lacks75 commands/temper.md 'HTML page too')|$(_lacks75 docs/mod.md 'HTML page too' 'one page too')"
assert_eq "w31 the pages match the code, 4: agents/review.md names the default critical, high" "names it" \
  "$(grep -qF 'critical, high' "$REPO_ROOT/agents/review.md" && ! grep -qF '(default: `critical`)' "$REPO_ROOT/agents/review.md" && echo names it || echo another default)"
assert_eq "w31 the pages match the code, 5: docs/commands.md and the mod's GATE_MESSAGE do not say that Claude makes a typed change itself" \
  "commands=ok|gate message=ok" \
  "commands=$(_lacks75 docs/commands.md 'Claude makes it')|gate message=$(git -C "$REPO_ROOT" grep -h 'GATE_MESSAGE =' -- '*.ts' ':(exclude)*.test.ts' 2>/dev/null | grep -qiE 'make the change|makes the change|makes it' && echo says it || echo ok)"
assert_eq "w31 the pages match the code, 6: no command, brief or reference page asks who reviews the intent" "none" \
  "$(git -C "$REPO_ROOT" grep -il 'who reviews the intent' -- commands agents reference 2>/dev/null | _list75 3)"
assert_eq "w31 the pages match the code, 7: Getting Started shows no config key that nothing reads" "ok" \
  "$(_lacks75 docs/getting-started.md review.confidence-threshold check.live-scenarios tools.label-findings)"
assert_eq "w31 the pages match the code, 8: docs/enterprise.md names no key that nothing reads" "ok" \
  "$(_lacks75 docs/enterprise.md plan.default-depth branch.pattern branch.commit-style)"
assert_eq "w31 the pages match the code, 9: docs/packs.md says no 8 built-in" "ok" "$(_lacks75 docs/packs.md '8 built-in')"
assert_eq "w31 the pages match the code, 10: docs/context-hygiene.md holds neither 224 nor about 10 KB" "ok" \
  "$(_lacks75 docs/context-hygiene.md 224 'about 10 KB')"
assert_eq "w31 the pages match the code, 11: docs/trust.md says no ten Python scripts" "ok" "$(_lacks75 docs/trust.md 'ten Python scripts')"
assert_eq "w31 the pages match the code, 12: docs/commands.md and Getting Started show no emoji output that no code prints" "none" \
  "$(python3 -I - "$REPO_ROOT" <<'PY'
import os, sys
hits = []
for rel in ("docs/commands.md", "docs/getting-started.md"):
    try:
        t = open(os.path.join(sys.argv[1], rel), encoding="utf-8").read()
    except OSError:
        continue
    e = sorted({ch for ch in t if 0x1F000 <= ord(ch) <= 0x1FAFF or ord(ch) in (0x2705, 0x274C, 0x26A0)})
    if e:
        hits.append("%s: %s" % (rel, "".join(e[:5])))
print(", ".join(hits) or "none")
PY
)"

# --- 8. the validators of the directory, the README, the docs and the known limits ---
assert_eq "w31 validate-directory.sh, validate-readme.sh, validate-docs.sh and check-known-limits.sh exit 0" "0|0|0|0" \
  "$(bash "$REPO_ROOT/scripts/validate-directory.sh" >/dev/null 2>&1; echo $?)|$(bash "$REPO_ROOT/scripts/validate-readme.sh" >/dev/null 2>&1; echo $?)|$(bash "$REPO_ROOT/scripts/validate-docs.sh" >/dev/null 2>&1; echo $?)|$(bash "$REPO_ROOT/scripts/check-known-limits.sh" >/dev/null 2>&1; echo $?)"
# What only the mod holds (mechanism step 7, row D40): docs/trust.md says that with the mod off nothing but the page's
# rule holds that a person, not the model, picked an option, and check-known-limits.sh holds that sentence
assert_eq "w31 docs/trust.md says what only the mod holds, that a person and not the model picked an option, and check-known-limits.sh holds it with a need TRUST line" \
  "held" "$(python3 -I - "$REPO_ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
lim = open(os.path.join(root, "scripts", "check-known-limits.sh"), encoding="utf-8").read()
trust = " ".join(open(os.path.join(root, "docs", "trust.md"), encoding="utf-8").read().split()).lower()
needs = re.findall(r'^need TRUST "([^"]+)"', lim, re.M)
ok = [n for n in needs if "not the model" in n.lower() and "person" in n.lower() and " ".join(n.split()).lower() in trust]
print("held" if ok else "no need TRUST line on a person, not the model, that docs/trust.md holds")
PY
)"

# --- 11. the README has its parts (row D108 holds the count, the two headings and the figures) ---
assert_eq "w31 the README has its parts: its ## headings are Install, Commands, How it works, What the mod reads and writes and Read more, in this order, and no other but See it" \
  "Install|Commands|How it works|What the mod reads and writes|Read more" \
  "$(grep -E '^## ' "$REPO_ROOT/README.md" | sed 's/^## //;s/[[:space:]]*$//' | grep -vx 'See it' | tr '\n' '|' | sed 's/|$//')"
assert_eq "w31 the README has one line that starts **Cost and time:**, and it names the earlier measurements, or the scorecard when that file exists" \
  "1|names them" "$(python3 -I - "$REPO_ROOT" <<'PY'
import os, sys
root = sys.argv[1]
lines = [l for l in open(os.path.join(root, "README.md"), encoding="utf-8").read().splitlines() if l.startswith("**Cost and time:**")]
card = "docs/evidence/scorecard-9.8.5.json"
names = lines and ("docs/evidence/bench-2026-11.md" in lines[0] or (card in lines[0] and os.path.isfile(os.path.join(root, card))))
print("%d|%s" % (len(lines), "names them" if names else "names neither"))
PY
)"
assert_eq "w31 the README says how it works in at most 8 lines under How it works, the cost line aside, one of them the plain line Intent, Plan, Build, Review, Check" \
  "at most 8|plain line" "$(python3 -I - "$REPO_ROOT/README.md" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
sec = t.split("\n## How it works\n", 1)[1].split("\n## ", 1)[0] if "\n## How it works\n" in t else None
if sec is None:
    print("no part How it works"); sys.exit(0)
body = [l for l in sec.splitlines() if l.strip() and not l.startswith("**Cost and time:**")]
print("%s|%s" % ("at most 8" if len(body) <= 8 else "%d lines" % len(body),
                 "plain line" if any("Intent, Plan, Build, Review, Check" in l for l in body) else "no plain line"))
PY
)"
# the rest of mechanism step 4 that a string can hold (my addition)
assert_eq "w31 the README's top holds the promise, Commands names the words of /temper:temper, and Read more links Getting Started, the flow, the decision records, Trust, the CHANGELOG, Privacy and the license" \
  "promise|words=draft,init,pack,report,status|read more=ok" "$(python3 -I - "$REPO_ROOT/README.md" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
def part(h):
    return t.split("\n## %s\n" % h, 1)[1].split("\n## ", 1)[0] if "\n## %s\n" % h in t else ""
top = " ".join(t.split("\n## ", 1)[0].split()).lower()
cmds = part("Commands")
more = part("Read more")
need = ["docs/getting-started.md", "docs/flow.md", "docs/decisions", "docs/trust.md", "CHANGELOG.md", "privacy"]
lack = [n for n in need if n.lower() not in more.lower()] + ([] if re.search(r"LICENSE|\bMIT\b", more) else ["the license"])
print("%s|words=%s|read more=%s" % (
    "promise" if "you approve once before any code is written and once at the commit" in top else "no promise",
    ",".join(w for w in ("draft", "init", "pack", "report", "status") if re.search(r"\b%s\b" % w, cmds)),
    "ok" if not lack else "lacks " + ",".join(lack)))
PY
)"

# --- the rest of the mechanism that a string or one gate run can hold (my additions) ---
# step 2: the gate row park-on-touch paths is renamed sensitive paths (the key autonomy.park-on-touch keeps its name)
fresh; printf 'autonomy:\n  park-on-touch: ["**/auth/**"]\n' >> .claude/temper.config
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm base --no-verify >/dev/null 2>&1
"$TEMPER" state set base_sha "$(git rev-parse HEAD)" >/dev/null 2>&1
mkdir -p src/auth; echo x > src/auth/login.ts; git add src/auth/login.ts; git -c user.email=t@t -c user.name=t commit -qm auth --no-verify >/dev/null 2>&1
_ran_unattended; "$TEMPER" gate commit >/dev/null 2>&1
assert_eq "w31 the commit gate's row is named sensitive paths: a change under autonomy.park-on-touch fails it, and no row is named park-on-touch paths" \
  "sensitive paths=False|park-on-touch paths=absent" "$(python3 -I -c '
import json
r = {x["name"]: x["pass"] for x in json.load(open(".temper/gates.json")).get("commit", {}).get("requirements", [])}
print("sensitive paths=%s|park-on-touch paths=%s" % (r.get("sensitive paths", "absent"), r.get("park-on-touch paths", "absent")))' 2>&1)"
# step 6: .claude/CLAUDE.md
assert_eq "w31 .claude/CLAUDE.md: gate logic lives in the CLI (the script and its Python modules), never in a prompt; it names run.default, and no door" \
  "logic|run.default|doors=none" "$(python3 -I - "$REPO_ROOT/.claude/CLAUDE.md" <<'PY'
import re, sys
t = " ".join(open(sys.argv[1], encoding="utf-8").read().split())
print("%s|%s|doors=%s" % (
    "logic" if "gate logic lives in the CLI (the script and its Python modules), never in a prompt" in t else "no logic sentence",
    "run.default" if "run.default" in t else "no run.default",
    ",".join(sorted(set(m.lower() for m in re.findall(r"(?<![\w./-])doors?(?![\w/-])", t, re.I)))) or "none"))
PY
)"
# step 6: no page a user reads names a command that is gone (the pages of this package's list)
assert_eq "w31 no page a user reads names a command that is gone: /temper:intent, plan, design, build, review, check, status, init or pack" \
  "none" "$(git -C "$REPO_ROOT" grep -lE '/temper:(intent|plan|design|build|review|check|status|init|pack)([^[:alnum:]_-]|$)' -- \
     README.md .claude/CLAUDE.md CONTRIBUTING.md docs/getting-started.md docs/index.md docs/index.html docs/commands.md \
     docs/flow.md docs/mod.md docs/trust.md docs/auto-mode.md docs/grouped-build.md docs/packs.md docs/enterprise.md \
     docs/recommended-setup.md docs/context-hygiene.md docs/directory-submission.md docs/ai-native-sdlc.md \
     docs/methodology.md reference/autonomy.md 2>/dev/null | _list75 6)"
_PR75='#115([^0-9]|$)|pull request #?115([^0-9]|$)|(^|[^[:alnum:]])PR #?115([^0-9]|$)'
# the trap: on a page a user reads 9.8.5 is this release; only the CHANGELOG's part on a project of 9.8.4 names pull
# request 115, in its one closing line (mechanism step 9)
assert_eq "w31 no page a user reads names pull request 115, and the CHANGELOG entry of 9.8.5 names it on exactly one line" \
  "pages=none|changelog=1" \
  "pages=$(git -C "$REPO_ROOT" grep -liE "$_PR75" -- README.md 'docs/*.md' 'reference/*.md' 'commands/*.md' 'agents/*.md' \
     ':(exclude)docs/history' ':(exclude)docs/plans' ':(exclude)docs/decisions' ':(exclude)docs/evidence' 2>/dev/null | _list75 3)|changelog=$(awk '/^## v/ { n++ } n == 1' "$REPO_ROOT/CHANGELOG.md" | grep -ciE "$_PR75")"
# step 5: Getting Started walks the first run with the real texts of the fixtures
assert_eq "w31 Getting Started walks the first run with the CLI's texts: the approval card and the commit card of the fixtures, the approval's first two options, temper config show, python3, the comparison, and The words before what changed from 9.8.4" \
  "approval card|commit card|options|config show|python3|comparison|words, then 9.8.4" "$(cd "$REPO_ROOT" && python3 -I - <<'PY'
import json, re
t = open("scripts/selftest/view-fixtures.ts", encoding="utf-8").read()
v = json.loads(t[t.index("= {") + 2:])
try:
    gs = open("docs/getting-started.md", encoding="utf-8").read()
except OSError:
    gs = ""
labels = [o["label"].replace(" (Recommended)", "") for o in v["plan-pass"]["ask"]["question"]["options"][:2]]
heads = [l for l in gs.splitlines() if l.startswith("## ")]
w = [i for i, h in enumerate(heads) if h.strip() == "## The words"]
old = [i for i, h in enumerate(heads) if "9.8.4" in h]
print("|".join([
    "approval card" if v["plan-pass"]["card"]["title"] in gs else "no approval card",
    "commit card" if v["check-pass"]["card"]["title"] in gs else "no commit card",
    "options" if all(l in gs for l in labels) else "lacks " + ",".join(l for l in labels if l not in gs),
    "config show" if "temper config show" in gs else "no config show",
    "python3" if re.search(r"\bpython3\b", gs) else "no python3",
    "comparison" if "comparison.md" in gs else "no comparison",
    "words, then 9.8.4" if w and old and w[0] < old[-1] else "order %s" % heads[-4:]]))
PY
)"
# step 6: the listing page speaks of no README image but the badge until the videos are back
assert_eq "w31 docs/directory-submission.md speaks of no hero GIF" "ok" "$(_lacks75 docs/directory-submission.md 'GIF')"
# step 8: the decision records
assert_eq "w31 the decision records 0019 to 0025 are there, and 0025-one-route.md is in the house form and amends 0017" \
  "records=ok|0025=ok" "$(python3 -I - "$REPO_ROOT/docs/decisions" <<'PY'
import os, re, sys
d = sys.argv[1]
names = os.listdir(d)
want = ["0019-a-run-that-asks-twice.md", "0020-checks-judged-against-the-project.md",
        "0021-a-finding-is-repaired-in-its-stage.md", "0022-the-acceptance-tests-keep-their-own-writer.md",
        "0023-two-commands-and-defaults-in-code.md", "0024-what-9-8-5-removed.md", "0025-one-route.md"]
miss = [n[:4] for n in want if n not in names]
try:
    t = open(os.path.join(d, "0025-one-route.md"), encoding="utf-8").read()
except OSError:
    t = ""
lack = [x for x in ("**Status:** Accepted", "**Date:**", "## Context", "## Decision", "## Consequences") if x not in t]
if not re.search(r"^\*\*Amends:\*\*.*0017", t, re.M):
    lack.append("Amends 0017")
if not re.search(r"spec route", t, re.I):
    lack.append("the spec route")
print("records=%s|0025=%s" % ("ok" if not miss else "missing " + ",".join(miss),
                               "ok" if not lack else ("missing" if not t else "lacks " + ", ".join(lack))))
PY
)"
assert_eq "w31 the status lines of the decision records: 0002 rejected, 0003 and 0004 accepted, 0006 superseded by 0024, 0017 rejected, none proposed, and each record amended names the record that amends it" \
  "ok" "$(python3 -I - "$REPO_ROOT/docs/decisions" <<'PY'
import os, re, sys
d = sys.argv[1]
files = {n[:4]: os.path.join(d, n) for n in os.listdir(d) if re.match(r"^\d{4}-.*\.md$", n)}
def text(n):
    try:
        return open(files[n], encoding="utf-8").read()
    except (KeyError, OSError):
        return ""
def status(n):
    for l in text(n).splitlines():
        if "Status:" in l:
            return l.split("Status:", 1)[1].split(" · ")[0].replace("*", "").strip()
    return ""
faults = []
for n, want in (("0002", "Rejected (never built)"), ("0003", "Accepted"), ("0004", "Accepted"),
                ("0017", "Rejected: not built (9.8.5)")):
    if not status(n).startswith(want):
        faults.append("%s is %r" % (n, status(n)))
if not (status("0006").startswith("Superseded") and "0024" in status("0006")):
    faults.append("0006 is %r" % status("0006"))
faults += ["%s is proposed" % n for n in sorted(files) if status(n).lower().startswith("proposed")]
AMENDS = {"0005": ["0023"], "0009": ["0021"], "0011": ["0019", "0021"], "0012": ["0019", "0023"],
          "0013": ["0019", "0021"], "0016": ["0019"], "0018": ["0020"]}
for n, by in AMENDS.items():
    if not status(n).lower().startswith("accepted"):
        faults.append("%s is %r" % (n, status(n)))
    lines = " ".join(l for l in text(n).splitlines() if re.search(r"amended by", l, re.I))
    lack = [b for b in by if b not in lines]
    if lack:
        faults.append("%s names no Amended by %s" % (n, ",".join(lack)))
print("ok" if not faults else "; ".join(faults[:6]))
PY
)"
assert_eq "w31 ADR 0011 gives the task block budget as 2,048 bytes, and ADR 0020 holds what WP19 and WP20 decided (not measured, three times the base)" \
  "0011=ok|0020=ok" "$(python3 -I - "$REPO_ROOT/docs/decisions" <<'PY'
import os, re, sys
def text(n):
    for f in os.listdir(sys.argv[1]):
        if f.startswith(n + "-"):
            return " ".join(open(os.path.join(sys.argv[1], f), encoding="utf-8").read().split())
    return ""
a, b = text("0011"), text("0020")
print("0011=%s|0020=%s" % (
    "ok" if re.search(r"task block\s+2,?048", a) and not re.search(r"task block\s+1,?536", a) else "no task block 2,048",
    "ok" if re.search(r"not measured", b, re.I) and re.search(r"three times", b, re.I) else "lacks the decisions of WP19 and WP20"))
PY
)"
