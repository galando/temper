"""config_yaml.py: the small YAML subset of .claude/temper.config, read the one way the CLI and
flow.py both read it. Standard library only.

  python3 config_yaml.py <config file> <dot.path> <default>   prints the value, as `temper config get`
"""
import sys

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
            container = {}
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


def get(d, path, default=""):
    """The value at a dot path as the CLI prints it: a list joined by \x1f, a bool as true or false."""
    cur = d
    for k in path.split("."):
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return default
    if isinstance(cur, list):
        return "\x1f".join(str(i) for i in cur)
    if isinstance(cur, bool):
        return "true" if cur else "false"  # bash compares lowercase; never Python's True/False
    return cur if cur != "" else default


if __name__ == "__main__":
    print(get(load(sys.argv[1]), sys.argv[2], sys.argv[3]))
