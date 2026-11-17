"""findings.py: how the author answers a finding without accepting it (9.7.6). Accepting stays the person's call.

  python3 findings.py contest LEDGER.json ID CITE QUOTE REASON TS   a contest the reviewer could check: CITE names a file in
                                                               the project (path, path:LINE or path:SYMBOL), and QUOTE
                                                               is the text there that shows the finding is wrong
  python3 findings.py escalate LEDGER.json ID REASON TS        the evidence is outside every file (a team rule, a spoken
                                                               decision): the person decides, with what only they know
  python3 findings.py count LEDGER.json SEVS open|resolved|accepted
                                                               how many findings of those severities (comma separated) are
                                                               in that state (open: neither resolved nor accepted)
  python3 findings.py open-claims LEDGER.json SEVS             the claims of those open findings, \x1f-joined, each with
                                                               its contest or escalation
  python3 findings.py fixed-by COMMIT STATE GROUPS            9.8.5 (WP18): prints the full id of COMMIT when evidence
                                                               resolve may name it, else one FAIL line (see fixed_by)
  python3 findings.py since-base BASE                          the commit gate's set: the files changed since BASE,
                                                               uncommitted and untracked, from the project folder
  python3 findings.py review-files STATE                       the files Review must read (review_files), one a line
  python3 findings.py read-check LEDGER STATE                  the row review completed: 1 or 0, a space, its detail

Both keep the finding open: the gate still counts it, and the gate question shows the contest or the escalation, so the
person accepts it or sends it back. A contest with no readable citation is refused: "This was intentional" is not
evidence. The citation is checked here, from the project folder: the file exists inside the project, the line exists, the
symbol is in the file, and the quote (at least 12 characters) is in the file, within 3 lines of a cited line. The quote is
what the person reads at the accept question. A comprehension finding (claim `[comprehension] ...`) is never contested or
escalated: when a reader with no context could not follow the plan, the plan is missing context. Standard library only.
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def finding_state(row):
    """The one state of a finding row, from the shape the CLI writes: 'resolved' (evidence resolve wrote `resolved`
    {fixed_by, ts}), 'accepted' (evidence accept wrote `accepted` {reason, author, ts}), else 'contested' or 'escalated'
    (this file wrote `contested` {cite, quote, reason, ts} or `escalated` {reason, ts}; the finding still counts), else
    'open'. The CLI refuses a second decision on a resolved or accepted finding, so at most one of the two is there."""
    if not isinstance(row, dict):
        return "open"
    for key in ("resolved", "accepted", "contested", "escalated"):
        if row.get(key):
            return key
    return "open"


def fail(msg):
    print("FAIL: %s" % msg, file=sys.stderr)
    return 1


def check_cite(cite, root, quote=""):
    """None when CITE names something a reviewer could read and QUOTE is there, else why not."""
    cite = (cite or "").strip()
    if not cite:
        return "a contest needs --cite <file>, <file>:<line> or <file>:<symbol>"
    m = re.match(r"^([^:]+?)(?::(.+))?$", cite)
    path, what = m.group(1).strip(), (m.group(2) or "").strip()
    if os.path.isabs(path) or ".." in path.replace("\\", "/").split("/"):
        return "the cited file must be a path inside the project, not '%s'" % path
    full = os.path.realpath(os.path.join(root, path))
    if not (full == root or full.startswith(root.rstrip("/") + "/")) or not os.path.isfile(full):
        return "no file %s in the project" % path
    try:
        text = open(full, encoding="utf-8", errors="replace").read()
    except OSError:
        return "%s cannot be read" % path
    quote = " ".join((quote or "").split())
    if len(quote) < 12:
        return "a contest needs --quote: at least 12 characters of the cited text, which the person reads"
    lines = text.splitlines()
    flat = lambda part: " ".join(" ".join(part).split())
    if what.isdigit():
        n = int(what)
        if not 1 <= n <= len(lines):
            return "%s has %d line(s), not line %s" % (path, len(lines), what)
        return None if quote in flat(lines[max(n - 4, 0):n + 3]) else "the quote is not within 3 lines of %s:%s" % (path, what)
    if what and what not in text:
        return "%s does not contain '%s'" % (path, what)
    return None if quote in flat(lines) else "%s does not contain the quote" % path


def mark(ledger, id_s, key, value):
    try:
        rows = json.load(open(ledger))
    except (OSError, ValueError):
        return fail("no ledger at %s" % ledger)
    try:
        idx = int(id_s)
    except ValueError:
        return fail("--id must be the 1-based number shown by 'temper evidence list'")
    if idx < 1 or idx > len(rows):
        return fail("no finding #%s in this stage (it has %d entries)" % (id_s, len(rows)))
    e = rows[idx - 1]
    if not isinstance(e, dict) or not e.get("severity"):
        return fail("finding #%s carries no severity, so it never counted against a gate" % id_s)
    if str(e.get("claim") or "").lstrip().lower().startswith("[comprehension]"):
        return fail("finding #%s is a comprehension finding: a reader with no context could not follow the plan, so the plan is "
                    "missing context. Fix the plan; it is never contested or escalated" % id_s)
    if finding_state(e) in ("resolved", "accepted"):
        return fail("finding #%s is already %s" % (id_s, finding_state(e)))
    e.pop("contested", None)
    e.pop("escalated", None)
    e[key] = value
    tmp = "%s.tmp.%d" % (ledger, os.getpid())
    with open(tmp, "w") as fh:
        json.dump(rows, fh, indent=2)
    os.replace(tmp, ledger)
    print("OK: %s finding #%s %s; it stays open until the person accepts it or it is fixed" % (e.get("severity"), id_s, key))
    return 0


def git(*args):
    """(exit code, stdout) of a git command; a missing git is exit 1."""
    try:
        r = subprocess.run(["git", "-c", "core.quotePath=false", "-c", "status.renames=false"] + list(args),
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        return 1, ""
    return r.returncode, r.stdout.decode("utf-8", "replace")


def load(path, kind=dict):
    try:
        d = json.load(open(path))
        return d if isinstance(d, kind) else kind()
    except (OSError, ValueError):
        return kind()


NO_REPAIR = ("  This run recorded no commit of its own (a fix run, or a Build with no groups). Until a later release "
             "records a repair commit, a finding ends by the person's accept, or by a loop back and a second Review.")


def fixed_by(name, state_path, groups_path):
    """9.8.5 (WP18): the full id of the commit `evidence resolve --fixed-by NAME` may name, or (None, why). All four
    hold: NAME is a commit; it is on this branch (an ancestor of HEAD); Review did not read it (it is no ancestor of the
    reviewed HEAD, the head of review_snapshot, written as the run enters Review); the CLI recorded it as its own
    (cli_commits of groups.json). No note and no commit made by hand resolves a finding."""
    rc, sha = git("rev-parse", "--verify", "--quiet", "%s^{commit}" % name) if not name.startswith("-") else (1, "")
    sha = sha.strip()
    if rc or not sha:
        return None, "'%s' names no commit: a finding is resolved only by a commit of the CLI" % name
    head = git("rev-parse", "HEAD")[1].strip()
    if git("merge-base", "--is-ancestor", sha, "HEAD")[0]:
        return None, "commit %s is not on this branch: it is no ancestor of HEAD %s" % (sha[:7], head[:7])
    seen = (load(state_path).get("review_snapshot") or {}).get("head") or ""
    if not seen:
        return None, "the run has no Review snapshot, so commit %s (HEAD %s) cannot follow the reviewed HEAD" % (
            sha[:7], head[:7])
    if not git("merge-base", "--is-ancestor", sha, seen)[0]:
        return None, "commit %s is the reviewed HEAD %s or an ancestor of it: Review read it already" % (sha[:7], seen[:7])
    if sha not in (load(groups_path).get("cli_commits") or []):
        return None, "commit %s is not one the CLI recorded (cli_commits); the reviewed HEAD is %s" % (sha[:7], seen[:7])
    return sha, None


def since_base(base):
    """The commit gate's set of changed files: what differs from BASE (base_sha), the tracked changes and the untracked
    files, each from the project folder, the ones blast_filter leaves out (Temper's own files, test output) left out."""
    import blast_filter
    names = []
    if base and not git("cat-file", "-e", base)[0]:
        names += git("diff", "--name-only", "--no-renames", "-z", base)[1].split("\0")
    ents = git("status", "--porcelain", "-z", "--untracked-files=all")[1].split("\0")
    i = 0
    while i < len(ents):
        e = ents[i]
        i += 1
        if len(e) >= 4:
            names.append(e[3:])
            i += 1 if e[0] in "RC" else 0
    top = git("rev-parse", "--show-toplevel")[1].strip()
    out = {os.path.relpath(os.path.join(top, n)) if top else n for n in names if n}
    return sorted(n for n in out if blast_filter.counts(n))


def review_files(state):
    """9.8.5 (WP18): the files Review must read, the set the row review completed compares: the commit gate's set less
    .temper/ and .claude/ and less files that no longer exist; after a small change that re-runs Review, that window's
    files until its gate."""
    import blast_filter
    done = state.get("adhoc_done") if isinstance(state.get("adhoc_done"), dict) else {}
    if "review" in (done.get("steps") or []):
        top = git("rev-parse", "--show-toplevel")[1].strip()
        names = [os.path.relpath(os.path.join(top, n)) if top else n for n in done.get("files") or []]
    else:
        names = since_base(state.get("base_sha") or "")
    return sorted({n for n in names if blast_filter.counts(n) and not n.startswith((".temper/", ".claude/"))
                   and os.path.lexists(n)})


def completion(ledger):
    """The latest row whose claim holds `review completed`, or None."""
    hits = [e for e in load(ledger, list) if isinstance(e, dict) and re.search("review completed", e.get("claim") or "", re.I)]
    return hits[-1] if hits else None


def unread(row, files):
    read = set((row or {}).get("read") or [])
    return [f for f in files if f not in read]


def names(files, n=5):
    return ", ".join(files[:n]) + (" and %d more" % (len(files) - n) if len(files) > n else "")


def read_check(ledger, state):
    """The row review completed: the latest completion row has exit 0 and its read list holds every file Review must
    read. A row with no read list (written before 9.8.5) names no file."""
    row = completion(ledger)
    if not row or row.get("exit_code") != 0:
        return 0, "no review completion evidence: an empty findings ledger is not a review"
    files = review_files(state)
    left = unread(row, files)
    if left:
        return 0, "read %d of %d changed files; not read: %s" % (len(files) - len(left), len(files), names(left))
    return 1, "read %d of %d changed files" % (len(files), len(files))


def rows_in(ledger, sevs_csv):
    sevs = {x for x in sevs_csv.split(",") if x}
    rows = json.load(open(ledger))   # an unreadable ledger fails here, as the gate's own read did: it never counts as none
    return [e for e in rows if isinstance(e, dict) and e.get("severity") in sevs]


def main(argv):
    if len(argv) == 5 and argv[1] == "count":
        want = argv[4]
        print(sum(1 for e in rows_in(argv[2], argv[3])
                  if (finding_state(e) not in ("resolved", "accepted") if want == "open" else finding_state(e) == want)))
        return 0
    if len(argv) == 4 and argv[1] == "open-claims":
        print("\x1f".join((e.get("claim") or "(no claim)") + {
            "contested": " (contested: %s)" % (e.get("contested") or {}).get("cite"),
            "escalated": " (escalated: only the person knows)"}.get(finding_state(e), "")
            for e in rows_in(argv[2], argv[3]) if finding_state(e) not in ("resolved", "accepted")))
        return 0
    if len(argv) == 8 and argv[1] == "contest":
        _, _, ledger, id_s, cite, quote, reason, ts = argv
        if not reason.strip():
            return fail("a contest needs --reason")
        why = check_cite(cite, os.path.realpath(os.getcwd()), quote)
        if why:
            return fail("%s. A contest must cite a file the reviewer could read; when the evidence is outside every file, "
                        "use temper evidence escalate" % why)
        return mark(ledger, id_s, "contested", {"cite": cite.strip(), "quote": " ".join(quote.split()), "reason": reason, "ts": ts})
    if len(argv) == 6 and argv[1] == "escalate":
        _, _, ledger, id_s, reason, ts = argv
        if not reason.strip():
            return fail("an escalation needs --reason: what only the person knows")
        return mark(ledger, id_s, "escalated", {"reason": reason, "ts": ts})
    if len(argv) == 5 and argv[1] == "fixed-by":
        sha, why = fixed_by(argv[2], argv[3], argv[4])
        if why:
            print("FAIL: %s" % why, file=sys.stderr)
            if not load(argv[4]).get("cli_commits"):
                print(NO_REPAIR, file=sys.stderr)
            return 1
        print(sha)
        return 0
    if len(argv) == 3 and argv[1] == "since-base":
        sys.stdout.write("".join(n + "\n" for n in since_base(argv[2])))
        return 0
    if len(argv) == 3 and argv[1] == "review-files":
        sys.stdout.write("".join(n + "\n" for n in review_files(load(argv[2]))))
        return 0
    if len(argv) == 4 and argv[1] == "read-check":
        print("%d %s" % read_check(argv[2], load(argv[3])))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
