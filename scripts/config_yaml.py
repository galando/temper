"""config_yaml.py: the small YAML subset of .claude/temper.config, read the one way the CLI and
flow.py both read it. Standard library only.

  python3 config_yaml.py <config file> <dot.path> [default]   prints the value, as `temper config get`; with no
                                                              default, the default of scripts/defaults.py (WP29)
"""
import sys

try:
    import defaults
except ImportError:   # a copy of the CLI without the table (a test's throwaway plugin): no default but the caller's
    defaults = type("defaults", (), {"RENAMED": {}, "default": staticmethod(lambda path: None)})

_TABLE = object()   # get() with no default: the table's

# A deliberately small YAML subset: nested maps by indentation, scalars, and
# INLINE flow lists ([a, b, c]) only — the v7 config never needs block-style
# '- item' lists, so that form is intentionally not supported here.
# as_text=True keeps every scalar as the text the file writes (quotes taken off), never an int, a float or a bool: a value of
# setup.env reaches a command as written (U18: `PYTHON_VERSION: 3.10` once came out as 3.1); every other reader keeps numbers.
def parse_yaml_subset(text, as_text=False):
    root = {}
    stack = [(-1, root)]
    for raw in text.splitlines():
        line = raw.split(' #', 1)[0].rstrip()
        if not line.strip() or line.strip().startswith('#'):
            continue
        indent = len(line) - len(line.lstrip(' '))
        stripped = line.strip()
        while len(stack) > 1 and indent <= stack[-1][0]:
            stack.pop()
        parent = stack[-1][1]
        if ':' not in stripped:
            continue
        key, _, val = stripped.partition(':')
        key, val = key.strip(), val.strip()
        if val == '':
            # M8: a key written twice is one map: a second `autonomy:` block adds to the first, never drops it
            container = parent[key] if isinstance(parent.get(key), dict) else {}
            parent[key] = container
            stack.append((indent, container))
        elif val.startswith('[') and val.endswith(']'):
            items = [i.strip().strip('"\'') for i in val[1:-1].split(',') if i.strip()]
            parent[key] = items
        elif as_text:
            parent[key] = val[1:-1] if len(val) >= 2 and val[0] == val[-1] and val[0] in '"\'' else val
        elif val in ('true', 'false'):
            parent[key] = (val == 'true')
        else:
            try:
                parent[key] = int(val)
            except ValueError:
                try:
                    parent[key] = float(val)
                except ValueError:
                    # One pair of matching quotes around the whole value is taken off; a
                    # quote that ends a value ('fmt "{file}"') is part of it.
                    if len(val) >= 2 and val[0] == val[-1] and val[0] in '"\'':
                        val = val[1:-1]
                    parent[key] = val
    return root


def load(path, as_text=False):
    """The parsed config, or {} when the file is missing or unreadable; as_text: scalars as written (parse_yaml_subset)."""
    try:
        with open(path) as f:
            return parse_yaml_subset(f.read(), as_text)
    except (OSError, UnicodeDecodeError):
        return {}


def _at(d, path):
    cur = d
    for k in path.split("."):
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return _TABLE
    return cur


def block_list(lines):
    """The entries of a block list, the lines under a key with no value up to the next line that is not indented: `- name`
    is one entry, and `- name: x` with the keys under it is one entry `name: x, link: y` (reference/pack.md)."""
    names = []
    for raw in lines:
        x = raw.split(" #", 1)[0].rstrip()
        if x.strip() and not x.startswith(" "):
            break
        if x.strip().startswith("- "):
            names.append(x.strip()[2:].strip())
        elif x.strip() and names and ":" in names[-1]:
            names[-1] += ", " + x.strip()
    return names


def old_name(d, path):
    """The old key a value the config lacks at path is read from, or None: the old name of a renamed key
    (defaults.RENAMED), or autonomy.enabled for run.default when it is false, which reads as ask (the flow's
    Run.run_default and `state may-start` read it so)."""
    if _at(d, path) is not _TABLE:
        return None
    if path in defaults.RENAMED and _at(d, defaults.RENAMED[path]) is not _TABLE:
        return defaults.RENAMED[path]
    if path == "run.default" and str(_at(d, "autonomy.enabled")).strip().lower() == "false":
        return "autonomy.enabled"
    return None


def get(d, path, default=_TABLE):
    """The value at a dot path as the CLI prints it: a list joined by \x1f, a bool as true or false. WP29: with no
    default given, a key the config lacks is read under its old name (old_name: defaults.RENAMED, and run.default as
    ask when autonomy.enabled is false), else the table's default (defaults.KEYS, "" for a key it lacks); a default
    the caller gives wins over both."""
    cur = _at(d, path)
    old = old_name(d, path) if default is _TABLE else None
    if old == "autonomy.enabled":
        return "ask"
    if old:
        cur = _at(d, old)
    if cur is _TABLE or cur == "":
        if default is not _TABLE:
            return default
        cur = defaults.default(path)
        if cur is None:
            return ""
    if isinstance(cur, list):
        return "\x1f".join(str(i) for i in cur)
    if isinstance(cur, bool):
        return "true" if cur else "false"  # bash compares lowercase; never Python's True/False
    return cur


if __name__ == "__main__":
    # R0-R1-4 (U18): a value of setup.env prints as the file writes it (3.10, never the float 3.1), as a command gets it
    print(get(load(sys.argv[1], as_text=sys.argv[2].startswith("setup.env.")), sys.argv[2], *sys.argv[3:4]))
