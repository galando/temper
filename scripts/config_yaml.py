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
def parse_yaml_subset(text):
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


def load(path):
    """The parsed config, or {} when the file is missing or unreadable."""
    try:
        with open(path) as f:
            return parse_yaml_subset(f.read())
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


def get(d, path, default=_TABLE):
    """The value at a dot path as the CLI prints it: a list joined by \x1f, a bool as true or false. WP29: with no
    default given, a key the config lacks is read under its old name (defaults.RENAMED), else the table's default
    (defaults.KEYS, "" for a key it lacks); a default the caller gives wins over both."""
    cur = _at(d, path)
    if cur is _TABLE and default is _TABLE and path in defaults.RENAMED:
        cur = _at(d, defaults.RENAMED[path])
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
    print(get(load(sys.argv[1]), sys.argv[2], *sys.argv[3:4]))
