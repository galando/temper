"""config_tidy.py: the config and its defaults, as `temper config show` prints them, and the one time question (WP29,
ADR 0023). Standard library only.

  python3 config_tidy.py show ""|--markdown CONFIG STATE   each key of scripts/defaults.py with its value and its source
                                                      (config, default, old name <key>), then each key of the file
                                                      that is gone or not read; --markdown: the table of every key
  python3 config_tidy.py tidy --apply|--keep CONFIG STATE   the two answers of config.tidy (exit 1 past Intent, in a fix
                                                      run or in a run that goes on by itself)

--apply drops each line whose value an earlier template shipped as a default (defaults.OLD) and each key no longer
read (defaults.GONE), moves a renamed key to its new name, turns autonomy.enabled: false into run.default: ask, keeps a
copy (.claude/temper.config.before-<version>) and writes the new template with the lines the person changed in place of
its own or after them, whatever upgrade.asked says (the question is asked once; the call, typed after Keep my file,
still does what it says). --keep appends `upgrade:` with `asked: "<version>"`, so the question is not asked again. An
unknown key is never an error: both keep it.
"""
import json
import os
import re
import sys

import config_yaml
import defaults

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(os.path.dirname(HERE), "templates", "temper.config.default")
# What a run notices when the line goes: the four that change a run come first in the question
WHAT = {"check.coverage-threshold": "no fixed floor: coverage may not drop against the base",
        "phases.design": "Design runs only when you ask for it",
        "packs": "two packs by default, security and tdd",
        "review.block-on": "high will block too"}
FIRST = ("check.coverage-threshold", "phases.design", "packs", "review.block-on", "autonomy.enabled")


def leaves(text):
    """[(dot path, raw value, line index)] of the file, in order, read as config_yaml reads it; an empty key that opens
    no block is a leaf with the raw value None. A key whose block is a list (`- name` lines, the block form of `packs:`
    in reference/pack.md) is one leaf whose raw value is its block as written, starting with a newline."""
    out, stack, skip = [], [(-1, "")], 0
    lines = text.splitlines()
    for i, raw in enumerate(lines):
        if i < skip:
            continue
        line = raw.split(" #", 1)[0].rstrip()
        if not line.strip() or line.strip().startswith("#") or ":" not in line:
            continue
        indent = len(line) - len(line.lstrip(" "))
        while len(stack) > 1 and indent <= stack[-1][0]:
            stack.pop()
        key, _, val = line.strip().partition(":")
        path = (stack[-1][1] + "." if stack[-1][1] else "") + key.strip()
        if val.strip():
            out.append((path, val.strip(), i))
            continue
        nxt = next((x for x in lines[i + 1:] if x.split(" #", 1)[0].strip() and not x.strip().startswith("#")), "")
        if len(nxt) - len(nxt.lstrip(" ")) > indent and nxt.strip().startswith("- "):
            skip = next((j for j in range(i + 1, len(lines)) if lines[j].strip()
                         and len(lines[j]) - len(lines[j].lstrip(" ")) <= indent), len(lines))
            while skip > i + 1 and not lines[skip - 1].strip():
                skip -= 1
            out.append((path, "\n" + "\n".join(lines[i + 1:skip]), i))
        elif len(nxt) - len(nxt.lstrip(" ")) > indent:
            stack.append((indent, path))
        else:
            out.append((path, None, i))
    return out


def value(raw):
    if raw is not None and raw.startswith("\n"):   # a block list: its entries, as cli_ctx.packs reads them
        return config_yaml.block_list(raw.split("\n")[1:])
    return config_yaml.parse_yaml_subset("k: %s" % raw).get("k") if raw is not None else None


def said(path, raw):
    """A kept pair as the call prints it: a block list by its entries."""
    return "%s: %s" % (path, "[%s]" % ", ".join("{ %s }" % e if ":" in e else e for e in value(raw))
                       if raw.startswith("\n") else raw)


def norm(v):
    if isinstance(v, list):
        return tuple(sorted(str(x).strip().lower() for x in v))
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v).strip().lower()


def vtuple(s):
    return tuple(int(x) for x in re.findall(r"\d+", str(s or ""))[:3])


def template_text():
    with open(TEMPLATE, encoding="utf-8") as f:
        return f.read()


def current(text):
    """WP32 (review findings R8-2, R8-3): the config of a project this version set up or asked: upgrade.asked of this
    version or a later one, or the first line of this version's template, which config init and Remove them write."""
    if vtuple(config_yaml.get(config_yaml.parse_yaml_subset(text), "upgrade.asked", "")) >= vtuple(defaults.VERSION):
        return True
    head = template_text().split("\n", 1)[0]
    return bool(head.strip()) and text.split("\n", 1)[0].rstrip() == head.rstrip()


def stale(text, every=False):
    """The lines the question offers to remove, [{path, raw, what}], the four that change a run first; none when the
    config already answered the question of that version (upgrade.asked). every: each such line whatever upgrade.asked
    says, the lines `--apply` removes (step 7 of WP29: a typed call after Keep my file does what it says)."""
    asked = () if every else vtuple(config_yaml.get(config_yaml.parse_yaml_subset(text), "upgrade.asked", ""))
    tpl = {p: norm(value(r)) for p, r, _ in leaves(template_text()) if r is not None}
    out = []
    for path, raw, _ in leaves(text):
        if raw is None:
            continue
        v = value(raw)
        if path in defaults.GONE and vtuple(defaults.GONE[path][2]) > asked:
            new, meaning, _ = defaults.GONE[path]
            if path == "autonomy.enabled":
                what = "becomes run.default: ask, your choice stays" if norm(v) == "false" else "no longer read"
            else:
                what = ("moves to %s" % new) if new else "no longer read: %s" % meaning
        elif any(norm(v) == norm(o) and vtuple(ver) > asked for o, ver in defaults.OLD.get(path, [])) and tpl.get(path) != norm(v):
            what = WHAT.get(path, "the same default lives in the CLI")
        else:
            continue
        out.append({"path": path, "raw": raw, "what": what})
    return sorted(out, key=lambda x: FIRST.index(x["path"]) if x["path"] in FIRST else len(FIRST))


def question_text(found):
    """The text of config.tidy: the count, the copy, at most eight lines with what changes, then `and M more`."""
    shown = ["%s (%s)" % (said(x["path"], x["raw"]), x["what"]) for x in found[:8]]   # a block list on one line
    more = len(found) - len(shown)
    return ("Your config holds %d lines that only repeat old defaults or are no longer read. Remove them so the new "
            "defaults apply? A copy is kept. %s%s." % (len(found), "; ".join(shown), "; and %d more" % more if more else ""))


def kept(text):
    """[(path, raw)] the person's own lines, after --apply: no old default, no gone key; a renamed key under its new
    name; autonomy.enabled false as run.default: ask; an empty key dropped."""
    gone = {x["path"] for x in stale(text, every=True)}
    have = {p for p, r, _ in leaves(text) if r is not None}
    out = []
    for path, raw, _ in leaves(text):
        if raw is None:
            continue
        if path in gone or path in defaults.GONE:
            new = defaults.GONE.get(path, ("", "", ""))[0]
            if path == "autonomy.enabled":
                if norm(value(raw)) == "false" and "run.default" not in have:
                    out.append(("run.default", "ask"))
            elif new and new not in have:
                out.append((new, raw))
            continue
        out.append((path, raw))
    return out


def rewrite(pairs):
    """The new template with each pair in place of its line, or under its block, or after the template."""
    lines = template_text().split("\n")
    own = {p: i for p, r, i in leaves("\n".join(lines)) if r is not None}
    tail = []
    for path, raw in pairs:
        if path in own and raw.startswith("\n"):   # a block list stays as written, in place of the template's line
            i = own[path]
            lines[i:i + 1] = [lines[i].split(":", 1)[0] + ":"] + raw.split("\n")[1:]
            own = {p: i for p, r, i in leaves("\n".join(lines)) if r is not None}
            continue
        if path in own:
            i = own[path]
            m = re.match(r"^(\s*[^:#]+:\s*)(.*?)(\s+#.*)?$", lines[i])
            if m and norm(value(m.group(2))) != norm(value(raw)):
                head, note = m.group(1) + raw, m.group(3) or ""
                col = len(m.group(1) + m.group(2)) + len(note) - len(note.lstrip())
                lines[i] = head + (" " * max(2, col - len(head)) + note.lstrip() if note else "")
            continue
        top = path.split(".")[0]
        at = next((i for i, x in enumerate(lines) if x.startswith(top + ":")), None)
        if at is not None and "." in path:
            end = at
            while end + 1 < len(lines) and lines[end + 1].startswith(" "):
                end += 1
            lines[end + 1:end + 1] = nested(path, raw)
            own = {p: i for p, r, i in leaves("\n".join(lines)) if r is not None}
        else:
            tail.append((path, raw))
    out = "\n".join(lines)
    block, prev = [], []
    for path, raw in tail:
        parts = path.split(".")
        same = 0
        while same < min(len(prev), len(parts) - 1) and prev[same] == parts[same]:
            same += 1
        block += ["%s%s:" % ("  " * d, parts[d]) for d in range(same, len(parts) - 1)]
        block.append("%s%s:%s%s" % ("  " * (len(parts) - 1), parts[-1], "" if raw.startswith("\n") else " ", raw))
        prev = parts[:-1]
    if block:
        out = out.rstrip("\n") + "\n" + "\n".join(block) + "\n"
    return out


def nested(path, raw, depth=1):
    parts = path.split(".")[1:]
    return ["%s%s:" % ("  " * (depth + d), parts[d]) for d in range(len(parts) - 1)] + \
           ("%s%s:%s%s" % ("  " * (depth + len(parts) - 1), parts[-1], "" if raw.startswith("\n") else " ", raw)).split("\n")


def refused(state_file):
    """Why the call may not run now, or "": past Intent, a fix run, or a run that goes on by itself."""
    try:
        with open(state_file, encoding="utf-8") as f:
            s = json.load(f)
    except (OSError, ValueError):
        return ""
    if not isinstance(s, dict) or not s.get("next_stage"):
        return ""
    if s.get("command") == "fix":
        return "a fix run is active"
    if s.get("next_stage") != "intent":
        return "the run is past Intent"
    if s.get("run_mode") == "autonomous":
        return "the run goes on by itself"
    return ""


def tidy(how, config, state_file):
    why = refused(state_file)
    if why:
        print("FAIL: config tidy runs only at the start of a /temper:temper run, at Intent: %s; nothing changed" % why,
              file=sys.stderr)
        return 1
    try:
        with open(config, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        print("FAIL: no config at %s" % config, file=sys.stderr)
        return 1
    if how == "--keep":
        with open(config, "a", encoding="utf-8") as f:
            f.write(("" if text.endswith("\n") or not text else "\n") + 'upgrade:\n  asked: "%s"\n' % defaults.VERSION)
        print("OK: kept %s as it is; upgrade.asked is %s, so the question is not asked again" % (config, defaults.VERSION))
        return 0
    found = stale(text, every=True)
    if not found:
        print("OK: nothing to remove: %s holds no old default and no key that is gone; nothing changed" % config)
        return 0
    copy, kept_copy = keep_copy(config, text)
    pairs = kept(text)
    with open(config, "w", encoding="utf-8") as f:
        f.write(rewrite(pairs))
    print("OK: removed %d lines (%s); kept your %d (%s); the old file is %s%s" % (
        len(found), ", ".join(x["path"] for x in found) or "none", len(pairs),
        ", ".join(said(*p) for p in pairs) or "none", copy, kept_copy))
    return 0


def keep_copy(config, text):
    """(the copy that holds the old text, a note): .claude/temper.config.before-<version>, written only when it does not
    exist yet. A copy is never overwritten: when one exists with other text, the old text goes to the first free
    .before-<version>.<n>."""
    base, n = "%s.before-%s" % (config, defaults.VERSION), 1
    while True:
        copy = base if n == 1 else "%s.%d" % (base, n)
        try:
            with open(copy, encoding="utf-8") as f:
                if f.read() == text:
                    return copy, " (the copy was there already, kept as it was)"
        except FileNotFoundError:
            with open(copy, "w", encoding="utf-8") as f:
                f.write(text)
            return copy, "" if n == 1 else " (%s was there already, kept as it was)" % base
        except (OSError, UnicodeDecodeError):
            pass
        n += 1


def match(path):
    """The key of the table a dot path of the file belongs to: itself, a pattern (models.<agent>), or the key whose
    block holds it (setup.env.X); None for a key the table lacks."""
    if path in defaults.KEYS:
        return path
    for k in defaults.KEYS:
        if "<" in k and re.fullmatch(re.sub(r"<[^>]+>", "[a-z0-9-]+", re.escape(k)), path):
            return k
        if path.startswith(k + "."):
            return k
    return None


def shown(v):
    if isinstance(v, list):
        return "[%s]" % ", ".join(json.dumps(x) if "*" in str(x) else str(x) for x in v)
    if isinstance(v, bool):
        return "true" if v else "false"
    return "(unset)" if v in ("", None) else str(v)


def show(config, markdown):
    if markdown:
        print("| Key | Default | What it sets |\n|---|---|---|")
        for k, (d, _lit, meaning) in defaults.KEYS.items():
            dv = "none" if d in ("", None) else "the table of `scripts/cli_ctx.py`" if "<" in k else "`%s`" % shown(d)
            print("| `%s` | %s | %s |" % (k, dv, meaning))
        return 0
    cfg = config_yaml.load(config)
    for k, (d, _lit, _m) in defaults.KEYS.items():
        if "<" in k:
            print("%-28s %-44s default" % (k, "the table of scripts/cli_ctx.py"))
            continue
        here, src, old = config_yaml._at(cfg, k), "config", config_yaml.old_name(cfg, k)
        if old:   # a renamed key under its old name, or run.default as ask when autonomy.enabled is false
            here, src = "ask" if old == "autonomy.enabled" else config_yaml._at(cfg, old), "old name %s" % old
        if here is config_yaml._TABLE or here == "":
            here, src = d, "default"
        print("%-28s %-44s %s" % (k, "(a block)" if isinstance(here, dict) else shown(here), src))
    try:
        with open(config, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        text = ""
    for path, raw, _ in leaves(text):
        if raw is None or path in defaults.KEYS:
            continue
        if path in defaults.GONE:
            new = {v: k for k, v in defaults.RENAMED.items()}.get(path, defaults.GONE[path][0])
            if not new or config_yaml.old_name(cfg, new) != path:   # else its new key's line names it
                print("gone: %s (not read; %s)" % (path, defaults.GONE[path][1]))
        elif match(path) is not None:
            if "<" in match(path):
                print("%-28s %-44s config" % (path, raw))
        else:
            print("not read: %s" % path)
    return 0


def main(argv):   # the CLI passes: show|tidy, the word after it ("" for none), the config file, the state file
    if len(argv) == 5 and argv[1] == "show" and argv[2] in ("", "--markdown"):
        return show(argv[3], argv[2] == "--markdown")
    if len(argv) == 5 and argv[1] == "tidy" and argv[2] in ("--apply", "--keep"):
        return tidy(argv[2], argv[3], argv[4])
    print("FAIL: usage: temper config show [--markdown] | temper config tidy --apply|--keep", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
