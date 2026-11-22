"""doctor.py: `temper doctor`, what the environment of this project looks like. It only reads.

  python3 doctor.py PROJECT CONFIG                     the report (below)
  python3 doctor.py PROJECT CONFIG --propose           a setup block made from what the project says it needs, printed
  python3 doctor.py PROJECT CONFIG --propose --write --expect HASH   the block the red base question showed (WP20),
                                                       written when its hash is HASH, refused when the proposal changed

`needs(project, setup, commands)` (WP20) is the environment check of the baseline: what the project's files and the
config name (a JDK, a Node version, the config's tools and services), checked against one shell call under the setup
block (limit 5 s) and a connect to each service; it never calls propose (no docker, no walk of the files).

The report prints three parts: the toolchain (the first line of each tool's version, or "not on PATH"), the setup block of
.claude/temper.config (its run line is shown, never run: it may start a service), and whether each service the block
names answers a TCP connect. It writes no file, no ledger, no state and no view. A variable whose name says it holds a
credential is never shown.

--propose reads facts, never runs a build: the JDK a Maven, Gradle, .java-version or .tool-versions file asks for; the
project's CI (GitHub Actions setup-java and setup-node, a job's database services and the variables that point at them,
.gitlab-ci.yml image tags, .devcontainer features); Docker Compose services when a Docker daemon answers, else a local
Postgres cluster; a Python .venv; an .nvmrc. It proposes only what it found. --write adds a block only as the person's
answer to the question that showed it whole (--expect its hash), and never over a block that is there (WP21: no
command is run to check a block; the baseline that runs after the answer is its check). Standard library only.
"""
import os
import re
import shutil
import socket
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_env  # noqa: E402

DEFAULT_TOOLS = ("java", "mvn", "python3", "node", "git")
TOOL_LIMIT_S = 10
SERVICE_LIMIT_S = 2


def version(tool, cwd):
    if not shutil.which(tool):
        return "not on PATH"
    flag = "-version" if os.path.basename(tool) == "java" else "--version"
    try:
        p = subprocess.run([tool, flag], cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=TOOL_LIMIT_S)
    except subprocess.TimeoutExpired:
        return "no answer within %d s" % TOOL_LIMIT_S
    except OSError as e:
        return "could not start (%s)" % e
    lines = [l.strip() for l in run_env.strip_banner(p.stdout.decode("utf-8", "replace")).splitlines() if l.strip()]
    return lines[0][:200] if lines else "(no version printed, exit %d)" % p.returncode


def answers(addr):
    host, _, port = addr.rpartition(":")
    try:
        with socket.create_connection((host or "127.0.0.1", int(port)), timeout=SERVICE_LIMIT_S):
            return True
    except (OSError, ValueError):
        return False


SKIP_DIRS = {".git", "node_modules", "target", "build", "dist", ".temper", ".claude", ".venv", "venv", "__pycache__", ".gradle"}
TEXT_EXT = (".java", ".kt", ".xml", ".yml", ".yaml", ".properties", ".py", ".ts", ".js", ".sh", ".toml", ".env", ".json", ".cfg")


def read(path, limit=400000):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read(limit)
    except OSError:
        return ""


def find_var(project, pattern, max_files=6000):
    """The first name matching pattern that a source or config file of the project names, or ""."""
    n = 0
    for d, dirs, files in os.walk(project):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith(".")]
        for f in files:
            if not f.endswith(TEXT_EXT):
                continue
            n += 1
            if n > max_files:
                return ""
            m = re.search(pattern, read(os.path.join(d, f)))
            if m:
                return m.group(1)
    return ""


def listed(folder):
    """The names in a folder, sorted ([] when it is not there)."""
    try:
        return sorted(os.listdir(folder))
    except OSError:
        return []


def docker_ready(cwd):
    """docker is on PATH and its daemon answers (a container can have the program and no daemon)."""
    if not shutil.which("docker"):
        return False
    try:
        return subprocess.run(["docker", "info"], cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=TOOL_LIMIT_S).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


CONTAINER_PORT = {"postgres": 5432, "mysql": 3306, "mariadb": 3306, "redis": 6379}
# what an image needs to start at all; the passwords are throwaway test values, never a credential of the project
SERVICE_ENV = {"postgres": ["POSTGRES_HOST_AUTH_METHOD=trust"], "mysql": ["MYSQL_ALLOW_EMPTY_PASSWORD=yes"],
               "mariadb": ["MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes"]}


def kind_of(image):
    return next((k for k in ("postgres", "mariadb", "mysql", "redis") if k in (image or "").lower()), "")


def ci_facts(project):
    """What the project's CI says it runs on: {'java': (N, file) or None, 'node': (N, file) or None,
    'services': [(name, kind, host port, image, file)], 'env': {NAME: value or 'service:<name>'}}. Read from GitHub
    Actions workflows (setup-java, setup-node, job services, env), .gitlab-ci.yml (an image tag such as temurin-24) and
    .devcontainer/devcontainer.json. Plain text matching: no YAML reader is needed for these fields."""
    out = {"java": None, "node": None, "services": [], "env": {}}
    wf = os.path.join(project, ".github", "workflows")
    files = [os.path.join(wf, f) for f in listed(wf) if f.endswith((".yml", ".yaml"))]
    files += [p for p in (os.path.join(project, ".gitlab-ci.yml"), os.path.join(project, ".devcontainer", "devcontainer.json"),
                          os.path.join(project, ".devcontainer.json")) if os.path.isfile(p)]
    for path in files:
        text, rel = read(path), os.path.relpath(path, project)
        for pat, key in ((r"java-version:\s*['\"]?(\d+)", "java"), (r"(?:temurin|openjdk|jdk|java)[-:]?(\d{2})\b", "java"),
                         (r"node-version:\s*['\"]?(\d+)", "node"), (r"features/node[^}]*?\"version\":\s*\"(\d+)", "node"),
                         (r"features/java[^}]*?\"version\":\s*\"(\d+)", "java")):
            m = re.search(pat, text, re.S)
            if m and not out[key]:
                n = int(m.group(1))
                if (key == "java" and 8 <= n <= 40) or (key == "node" and 10 <= n <= 40):
                    out[key] = (n, rel)
        if rel.endswith((".yml", ".yaml")):
            for name, kind, port, image in ci_services(text):
                if not any(s[0] == name for s in out["services"]):
                    out["services"].append((name, kind, port, image, rel))
            for m in re.finditer(r"(?m)^\s+([A-Z][A-Z0-9_]*):\s*(.+?)\s*$", text):
                var, val = m.group(1), m.group(2).strip("'\"")
                svc = re.search(r"job\.services\.([\w.-]+)\.ports", val)
                if svc:
                    out["env"].setdefault(var, "service:" + svc.group(1))
                elif (re.search(r"(POSTGRES|MYSQL|MARIADB|REDIS|DATABASE|DB)", var) and re.search(r"(PORT|HOST)$", var)
                      and re.match(r"^(\d{2,5}|localhost|127\.0\.0\.1)$", val)):
                    out["env"].setdefault(var, val)   # a database's local port or host only: a CI job also sets deploy and API values
    return out


def ci_services(text):
    """[(service, kind, host port, image)] of the database and cache services a GitHub Actions job declares: an indented
    `services:` block whose entries have an `image:` and a published port (or the image's own port)."""
    out, lines = [], text.splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r"^(\s+)services:\s*$", lines[i])
        if not m:
            i += 1
            continue
        ind = len(m.group(1))
        i += 1
        name, image, port, nind = None, "", "", None
        def flush():
            k = kind_of(image)
            if name and k:
                out.append((name, k, port or str(CONTAINER_PORT[k]), image))
        while i < len(lines) and (not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > ind):
            l = lines[i]
            cur = len(l) - len(l.lstrip())
            nm = re.match(r"^\s+([A-Za-z0-9._-]+):\s*$", l)
            if nm and (nind is None or cur == nind):
                flush()
                nind, name, image, port = cur, nm.group(1), "", ""
            im = re.match(r"^\s+image:\s*['\"]?([^'\"\s]+)", l)
            if im:
                image = im.group(1)
            pm = re.match(r"^\s+-\s*['\"]?(\d+):\d+", l)
            if pm and not port:
                port = pm.group(1)
            i += 1
        flush()
    return out


def local_postgres():
    """(version, cluster, port) of the first local Postgres cluster (pg_lsclusters), or None."""
    if not shutil.which("pg_lsclusters"):
        return None
    try:
        out = subprocess.run(["pg_lsclusters", "-h"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=TOOL_LIMIT_S).stdout.decode()
    except (OSError, subprocess.TimeoutExpired):
        return None
    cl = [l.split() for l in out.splitlines() if len(l.split()) >= 3]
    return tuple(cl[0][:3]) if cl else None


def compose_services(text):
    """[(service, kind, host port)] of a compose file's database and cache services (postgres, mysql, mariadb, redis)
    that publish a port. Read by indentation, as compose files are written; no YAML reader is needed."""
    out, name, image, port = [], None, "", ""
    def flush():
        kind = next((k for k in ("postgres", "mysql", "mariadb", "redis") if k in image.lower()), "")
        if name and kind and port:
            out.append((name, kind, port))
    on = False
    for line in text.splitlines():
        if re.match(r"^services:\s*$", line):
            on = True
            continue
        if on and re.match(r"^\S", line):
            break
        m = re.match(r"^  ([A-Za-z0-9._-]+):\s*$", line) if on else None
        if m:
            flush()
            name, image, port = m.group(1), "", ""
            continue
        if on and name:
            im = re.match(r"^\s+image:\s*['\"]?([^'\"\s]+)", line)
            if im:
                image = im.group(1)
            pm = re.match(r"^\s+-\s*['\"]?(?:[\d.]+:)?(\d+):\d+", line)
            if pm and not port:
                port = pm.group(1)
    flush()
    return out


def java_major(text):
    m = re.search(r'version "(\d+)', text)
    return int(m.group(1)) if m else 0


# ---- the environment check (WP20): what the project's files and the config name, against the shell, in under 5 s -----
NEEDS_LIMIT_S = 5
BUILTINS = {"cd", "echo", "true", "false", "export", "test", "[", "exit", "set", "source", ".", "eval", "unset", "printf",
            "exec", "env", "time", "command", "builtin", ":", "if", "then", "fi", "do", "done", "for", "while", "(", "{"}


def _major(text):
    m = re.search(r"(\d+)", str(text or ""))
    return int(m.group(1)) if m else 0


def stated(project, setup):
    """What the project's own files and the config state it needs: {"java": (N, file) or None, "node": (N, file) or
    None, "tools": [(program, file)], "services": [(name, address, file)]}. Read as propose() reads them; nothing
    runs."""
    out = {"java": None, "node": None, "tools": [], "services": []}

    def need(key, n, f):
        if n and (out[key] is None or n > out[key][0]):
            out[key] = (n, f)
    for d in [""] + listed(project):
        for name in ("pom.xml", "build.gradle", "build.gradle.kts"):
            p = os.path.join(project, d, name)
            if d.startswith(".") or not os.path.isfile(p):
                continue
            t = read(p)
            m = (re.search(r"<requireJavaVersion>\s*<version>\s*\[?(\d+)", t) or re.search(r"<(?:java\.version|maven\.compiler\.release)>(\d+)<", t)
                 or re.search(r"JavaLanguageVersion\.of\(\s*(\d+)", t)
                 or re.search(r"(?:source|target)Compatibility\s*=\s*(?:JavaVersion\.VERSION_|['\"])(\d+)", t))
            if m:
                need("java", int(m.group(1)), os.path.relpath(p, project))
    for vf, pat in ((".java-version", r"^\s*(?:\D*?)(\d+)"), (".tool-versions", r"(?m)^\s*java\s+\D*?(\d+)")):
        m = re.search(pat, read(os.path.join(project, vf)))
        if m:
            need("java", int(m.group(1)), vf)
    m = re.search(r"(?m)^\s*nodejs\s+\D*?(\d+)", read(os.path.join(project, ".tool-versions")))
    if m:
        need("node", int(m.group(1)), ".tool-versions")
    ci = ci_facts(project)
    for key in ("java", "node"):
        if ci[key]:
            need(key, ci[key][0], ci[key][1])
    pkg = read(os.path.join(project, "package.json"))
    m = re.search(r'"engines"\s*:\s*\{[^}]*"node"\s*:\s*"[^"\d]*(\d+)', pkg)
    if m:
        need("node", int(m.group(1)), "package.json")
    cfg = os.path.join(".claude", "temper.config")
    out["tools"] = [(t, cfg) for t in (setup or {}).get("tools") or [] if t]
    out["services"] = [(n, a, cfg) for n, a in ((setup or {}).get("services") or {}).items()]
    return out


def needs(project, setup, commands=()):
    """The environment check: (faults, notes, tools). It only reads, and makes one shell call under the setup block
    (limit 5 s) that resolves each program the commands start and the config's tools, and prints the version line of
    java and node when a file names one; then it connects to each service of the setup block, all at once, 2 s each.
    A fault is {"kind", "file", "need", "have", "why"}: kind program-missing, tool-version, service-down or
    setup-line. A shell call over 5 s gives no fault and the note `not checked in 5 s`. `tools` are the version
    lines, part of the baseline's key."""
    import threading
    st = stated(project, setup)
    faults, notes, tools = [], [], {}
    progs = []   # (program, folder it runs in, the file that names it)
    for c in commands:
        folder = ""
        for toks in run_env.steps(c):   # quotes respected: a `;` inside quotes names no program
            if not toks:
                continue
            if toks[0] == "cd" and len(toks) > 1:
                folder = os.path.join(folder, toks[1])
                continue
            if toks[0] not in BUILTINS and not any((toks[0], folder) == (x[0], x[1]) for x in progs):
                progs.append((toks[0], folder, "the suite command"))
    for t, f in st["tools"]:
        if not any(p == t for p, _, _ in progs):
            progs.append((t, "", f))
    if st["java"] and not any(p == "java" for p, _, _ in progs):
        progs.append(("java", "", st["java"][1]))
    if st["node"] and not any(p == "node" for p, _, _ in progs):
        progs.append(("node", "", st["node"][1]))
    import shlex
    lines = ['__w() { if command -v "$1" >/dev/null 2>&1; then echo "which $2 yes"; else echo "which $2 no"; fi; }']
    for i, (p, folder, _) in enumerate(progs):
        lines.append(("(cd %s 2>/dev/null && __w %s %d)" % (shlex.quote(folder), shlex.quote(p), i)) if "/" in p and folder
                     else "__w %s %d" % (shlex.quote(p), i))
    if st["java"]:
        # R6-1: the JVM's version line, not its first line: with JAVA_TOOL_OPTIONS set it prints `Picked up ...` first
        lines.append('__j="$(java -version 2>&1)"; echo "version java $(printf \'%s\\n\' "$__j" | grep -m 1 \'version "\' '
                     '|| printf \'%s\\n\' "$__j" | head -n 1)"')
    if st["node"]:
        lines.append('echo "version node $(node --version 2>&1 | head -n 1)"')
    out, rc = run_env.run_cmd(project, NEEDS_LIMIT_S, ["\n".join(lines)], setup)
    text = out.decode("utf-8", "replace")
    if rc == 124:
        notes.append("not checked in 5 s")
        return faults, notes, tools
    if rc == 125:
        m = re.search(r"temper-setup: FAIL \(exit (\d+)\)", text)
        faults.append({"kind": "setup-line", "file": os.path.join(".claude", "temper.config"), "need": "the setup line runs",
                       "have": "exit %s" % (m.group(1) if m else "?"),
                       "why": "the setup line of .claude/temper.config failed (%s)" % (m.group(0) if m else "temper-setup: FAIL")})
        return faults, notes, tools
    for line in text.splitlines():
        m = re.match(r"^which (\d+) no$", line.strip())
        if m and int(m.group(1)) < len(progs):
            p, folder, f = progs[int(m.group(1))]
            faults.append({"kind": "program-missing", "file": f, "need": p, "have": "not on the PATH",
                           "why": "%s is not on the PATH of the shell (%s needs it)" % (p, f)})
        m = re.match(r"^version (java|node) (.*)$", line.strip())
        if m:
            tools[m.group(1)] = m.group(2).strip()[:120]
    missing = {x["need"] for x in faults}
    for key, label in (("java", "JDK"), ("node", "Node")):
        if not st[key] or key in missing:
            continue
        n, f = st[key]
        have = java_major(tools.get(key, "")) if key == "java" else _major(tools.get(key, ""))
        if have and have < n:
            faults.append({"kind": "tool-version", "file": f, "need": str(n), "have": str(have),
                           "why": "%s needs %s %d; the shell has %s %d" % (f, label, n, label, have)})
    res = {}

    def probe(name, addr):
        res[name] = answers(addr)
    threads = [threading.Thread(target=probe, args=(n, a)) for n, a, _ in st["services"]]
    for t in threads:
        t.start()
    for t in threads:
        t.join(SERVICE_LIMIT_S + 1)
    for n, a, f in st["services"]:
        if not res.get(n):
            faults.append({"kind": "service-down", "file": f, "need": "%s at %s" % (n, a), "have": "no answer",
                           "why": "the service %s at %s does not answer (%s names it)" % (n, a, f)})
    if not (st["java"] or st["node"] or st["tools"] or st["services"]):
        notes.append("the project's files name no tool version and the config names no service")
    return faults, notes, tools


def propose(project):
    """(block lines, facts): a setup block made from what the project says it needs."""
    run, env, services, tools, facts = [], {}, {}, [], []
    poms = [p for p in [os.path.join(project, "pom.xml")] + [os.path.join(project, d, "pom.xml") for d in listed(project)] if os.path.isfile(p)]
    need = 0
    for pom in poms:
        text = read(pom)
        m = re.search(r"<requireJavaVersion>\s*<version>\s*\[?(\d+)", text) or re.search(r"<(?:java\.version|maven\.compiler\.release)>(\d+)<", text)
        if m:
            need = max(need, int(m.group(1)))
            facts.append("%s needs JDK %s" % (os.path.relpath(pom, project), m.group(1)))
    if poms:
        tools += ["java", "mvn"]
    # Gradle: a toolchain or a source compatibility names the JDK (9.8.5)
    gradles = [p for d in [""] + listed(project) for p in (os.path.join(project, d, "build.gradle"), os.path.join(project, d, "build.gradle.kts"))
               if os.path.isfile(p)]
    for gf in gradles:
        m = re.search(r"JavaLanguageVersion\.of\(\s*(\d+)", read(gf)) or re.search(r"(?:source|target)Compatibility\s*=\s*(?:JavaVersion\.VERSION_|['\"])(\d+)", read(gf))
        if m:
            need = max(need, int(m.group(1)))
            facts.append("%s needs JDK %s" % (os.path.relpath(gf, project), m.group(1)))
    if gradles:
        tools += [t for t in ["java", "./gradlew" if os.path.isfile(os.path.join(project, "gradlew")) else "gradle"] if t not in tools]
    # a version file of jenv, asdf or mise names the JDK too
    for vf, pat in ((".java-version", r"^\s*(?:\D*?)(\d+)"), (".tool-versions", r"(?m)^\s*java\s+\D*?(\d+)")):
        m = re.search(pat, read(os.path.join(project, vf)))
        if m:
            need = max(need, int(m.group(1)))
            facts.append("%s names JDK %s" % (vf, m.group(1)))
            tools += [] if "java" in tools else ["java"]
    ci = ci_facts(project)   # 9.8.5: what the project's CI and devcontainer say it runs on
    if ci["java"]:
        need = max(need, ci["java"][0])
        facts.append("%s runs on JDK %d" % (ci["java"][1], ci["java"][0]))
        tools += [] if "java" in tools else ["java"]
    if need:
        have = java_major(version("java", project)) if shutil.which("java") else 0
        here = os.path.join(project, "scripts")
        script = next((os.path.join(here, f) for f in listed(here) if re.match(r"^ensure-jdk.*\.sh$", f) and "--export" in read(os.path.join(here, f))), "")
        if script:
            rel = os.path.relpath(script, project)
            run.append('eval "$(%s --export)"' % rel)
            facts.append("%s --export sets the JDK" % rel)
        elif have < need:
            # the system's JDK folder only: the CLI reads no home folder
            homes = [os.path.join("/usr/lib/jvm", f) for f in listed("/usr/lib/jvm")
                     if re.match(r"^.*-%d(\D|$)" % need, f) and os.path.isdir(os.path.join("/usr/lib/jvm", f))]
            if homes:
                run.append('export JAVA_HOME=%s PATH="%s/bin:$PATH"' % (homes[0], homes[0]))
                facts.append("JDK %d is installed at %s (the shell has %s)" % (need, homes[0], have or "none"))
            else:
                facts.append("JDK %d is needed and none was found: install it, then run temper doctor --propose again" % need)
    kinds = set()
    # Docker Compose: the databases and caches the project runs as services, started when docker is there (9.8.5)
    compose = next((os.path.join(project, f) for f in ("compose.yaml", "compose.yml", "docker-compose.yml", "docker-compose.yaml")
                    if os.path.isfile(os.path.join(project, f))), "")
    ready = bool(compose) and docker_ready(project)
    if compose and not ready and compose_services(read(compose)):
        facts.append("%s runs database services, and docker does not answer here (no program, or no daemon): they are not "
                     "started by the block" % os.path.relpath(compose, project))
    if compose and ready:
        found = compose_services(read(compose))
        if found:
            run.append("docker compose -f %s up -d %s" % (os.path.relpath(compose, project), " ".join(n for n, _, _ in found)))
            kinds.update(k for _, k, _ in found)
            for name, kind, port in found:
                services[name] = "127.0.0.1:%s" % port
                var = find_var(project, r"\b([A-Z][A-Z0-9_]*%s[A-Z0-9_]*PORT)\b" % {"postgres": "POSTGRES", "mysql": "MYSQL", "mariadb": "MYSQL", "redis": "REDIS"}[kind])
                if var and var not in env:
                    env[var] = port
                facts.append("%s runs %s (%s) on port %s" % (os.path.relpath(compose, project), name, kind, port))
    # the CI's services: started with docker when its daemon answers, else by a local server of that kind (9.8.5)
    for name, kind, port, image, src in ci["services"]:
        if kind in kinds:
            continue
        if docker_ready(project):
            cname = "temper-%s" % name
            run.append("(docker start %s >/dev/null 2>&1 || docker run -d --name %s -p %s:%s %s%s >/dev/null)" % (
                cname, cname, port, CONTAINER_PORT[kind], " ".join("-e %s" % e for e in SERVICE_ENV.get(kind, [])) + " " if SERVICE_ENV.get(kind) else "", image))
            services[name] = "127.0.0.1:%s" % port
            kinds.add(kind)
            facts.append("%s runs %s (%s) on port %s: docker starts it" % (src, name, image, port))
        elif kind == "postgres" and local_postgres():
            ver, cname, port = local_postgres()
            run.append("(pg_isready -q -h 127.0.0.1 -p %s || pg_ctlcluster %s %s start)" % (port, ver, cname))
            services[name] = "127.0.0.1:%s" % port
            kinds.add(kind)
            facts.append("%s runs %s (%s): the local Postgres %s cluster on %s stands in for it" % (src, name, image, ver, port))
        elif kind == "redis" and shutil.which("redis-server"):
            run.append("(redis-cli -p %s ping >/dev/null 2>&1 || redis-server --port %s --daemonize yes >/dev/null)" % (port, port))
            services[name] = "127.0.0.1:%s" % port
            kinds.add(kind)
            facts.append("%s runs redis on port %s: the local redis-server starts it" % (src, port))
        elif kind in ("mysql", "mariadb") and shutil.which("mysqld") and shutil.which("service"):
            run.append("(mysqladmin -h 127.0.0.1 -P 3306 ping >/dev/null 2>&1 || service mysql start >/dev/null)")
            services[name] = "127.0.0.1:3306"
            kinds.add(kind)
            facts.append("%s runs %s: the local MySQL server starts it (port 3306)" % (src, kind))
        elif kind != "postgres":
            facts.append("%s runs %s (%s), and neither docker nor a local server of that kind is here" % (src, name, image))
    var = find_var(project, r"\b([A-Z][A-Z0-9_]*POSTGRES[A-Z0-9_]*PORT)\b") or next(
        (v for v, val in ci["env"].items() if val.startswith("service:") and "POSTGRES" in v), "")
    if var and "postgres" not in kinds and local_postgres():   # a Compose or CI service of the project wins
        ver, name, port = local_postgres()
        run.append("(pg_isready -q -h 127.0.0.1 -p %s || pg_ctlcluster %s %s start)" % (port, ver, name))
        env[var] = port
        services["postgres"] = "127.0.0.1:%s" % port
        facts.append("the code reads %s; a local Postgres %s cluster listens on %s" % (var, ver, port))
    for var, value in ci["env"].items():
        svc = re.match(r"^service:(\w[\w.-]*)$", value)
        if svc:
            addr = services.get(svc.group(1)) or next((a for n, a in services.items() if n.startswith(svc.group(1))), "")
            if addr:
                env.setdefault(var, addr.rsplit(":", 1)[1])
        elif not run_env.is_credential(var):
            env.setdefault(var, value)
    # a Python virtual environment of the project
    venv = next((d for d in (".venv", "venv") if os.path.isfile(os.path.join(project, d, "bin", "activate"))), "")
    if venv:
        # by the main checkout's path: a worktree of the clone (Build's, the baseline's) holds no ignored folder (U13)
        run.append('. "$(dirname "$(git rev-parse --git-common-dir)")/$(git rev-parse --show-prefix)%s/bin/activate"' % venv)
        facts.append("%s/ is the project's Python environment" % venv)
        tools += [] if "python3" in tools else ["python3"]
    if ci["node"] and shutil.which("node") and java_major('version "%s' % version("node", project).lstrip("v")) != ci["node"][0]:
        homes = [os.path.join("/opt", f) for f in listed("/opt") if re.match(r"^node-?v?%d(\D|$)" % ci["node"][0], f)]
        if homes and os.path.isdir(os.path.join(homes[0], "bin")):
            run.append('export PATH="%s/bin:$PATH"' % homes[0])
            facts.append("%s runs on Node %d, installed at %s" % (ci["node"][1], ci["node"][0], homes[0]))
        else:
            facts.append("%s runs on Node %d; the shell has another and none was found in /opt" % (ci["node"][1], ci["node"][0]))
    if os.path.isfile(os.path.join(project, "package.json")):
        tools += ["node", "npm"]
        if os.path.isfile(os.path.join(project, ".nvmrc")):
            # the shell checks for nvm when the line runs (the CLI reads no home folder)
            run.append('{ [ ! -s "$HOME/.nvm/nvm.sh" ] || { . "$HOME/.nvm/nvm.sh" && nvm use >/dev/null; }; }')
            facts.append(".nvmrc names the Node version (nvm, when it is installed, selects it)")
    if not (run or env):
        return [], facts
    block = ["setup:"]
    if run:
        block.append("  run: " + " && ".join(run))
    if env:
        block += ["  env:"] + ["    %s: %s" % kv for kv in env.items()]
    if services:
        block += ["  services:"] + ["    %s: %s" % kv for kv in services.items()]
    if tools:
        block.append("  tools: [%s]" % ", ".join(tools))
    return block, facts


def parts(block):
    """{'run': str, 'env': {name: value}} of a proposed block (its own lines, so no YAML reader is needed)."""
    out, sec = {"run": "", "env": {}}, ""
    for l in block:
        if l.startswith("  run: "):
            out["run"] = l[len("  run: "):]
        elif re.match(r"^  \w+:$", l):
            sec = l.strip()[:-1]
        elif sec == "env" and l.startswith("    "):
            k, _, v = l.strip().partition(": ")
            out["env"][k] = v
    return out


def block_hash(block):
    import hashlib
    return hashlib.sha256("\n".join(block).encode("utf-8")).hexdigest()


def setup_of(block):
    """The setup a block of config lines means, read the way the CLI reads the config (run_env.load_setup)."""
    import tempfile
    fd, path = tempfile.mkstemp(prefix="temper-candidate-", suffix=".config")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("\n".join(block) + "\n")
        return run_env.load_setup(path)
    finally:
        os.remove(path)


def write_block(config, block, how):
    """Adds the block at the end of the config, as shown: nothing but the block and the blank line before it (WP21: the
    rest of the config stays byte equal), and `how` is said in the output only."""
    if run_env.load_setup(config):
        print("FAIL: %s has a setup block already; nothing was written" % config, file=sys.stderr)
        return 1
    os.makedirs(os.path.dirname(os.path.abspath(config)), exist_ok=True)
    old = read(config)
    with open(config, "a", encoding="utf-8") as f:
        f.write(("" if not old or old.endswith("\n") else "\n") + "\n" + "\n".join(block) + "\n")
    print("OK: the setup block is in %s (%s, by the person's choice)" % (config, how))
    return 0


def main(argv):
    if len(argv) >= 4 and argv[3] == "--propose":
        project, config = argv[1], argv[2]
        block, facts = propose(project)
        for f in facts:
            print("found: " + f)
        if not block:
            print("Nothing to propose: no need of the project was found that a setup block meets.")
            return 0
        if argv[4:6] == ["--write", "--expect"] and len(argv) == 7:
            # WP20: the block the red base question showed, written as shown: refused when the proposal changed since
            if block_hash(block) != argv[6]:
                print("FAIL: the proposed block changed since the question showed it; nothing was written (ask again)",
                      file=sys.stderr)
                return 1
            if " #" in "\n".join(block):
                print("FAIL: the run line holds ' #', which the config reader cuts", file=sys.stderr)
                return 1
            print("\n".join(block))
            return write_block(config, block, "Proposed by temper doctor --propose, as the red base question showed it")
        print("\n".join(block))
        if argv[4:]:
            # WP21: a block is written only as the person's answer to the question that showed it (its hash)
            print("FAIL: --write needs --expect <the hash of the block the question showed>; nothing was written "
                  "(the config is the person's)", file=sys.stderr)
            return 1
        return 0
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    project, config = argv[1], argv[2]
    setup = run_env.load_setup(config)
    print("Toolchain:")
    for tool in setup.get("tools") or DEFAULT_TOOLS:
        print("  %s: %s" % (tool, version(tool, project)))
    if not setup:
        print("Setup block: none")
    else:
        print("Setup block:")
        if setup["run"]:
            print("  run: %s (not run by doctor: it may start a service)" % run_env.mask(setup["run"]))
        for k, v in setup["env"].items():
            print("  " + run_env.shown_var(k, v))
        for k in setup["dropped"]:
            print("  left out (credential name): %s" % k)
    services = setup.get("services") or {}
    print("Services:" + ("" if services else " none named"))
    for name, addr in services.items():
        print("  %s %s: %s" % (name, addr, "answering" if answers(addr) else "not answering"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
