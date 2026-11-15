"""doctor.py: `temper doctor`, what the environment of this project looks like. It only reads.

  python3 doctor.py PROJECT CONFIG                     the report (below)
  python3 doctor.py PROJECT CONFIG --propose           a setup block made from what the project says it needs, printed
  python3 doctor.py PROJECT CONFIG --propose --write   the same, added to the config (never over a setup block there)

The report prints three parts: the toolchain (the first line of each tool's version, or "not on PATH"), the setup block of
.claude/temper.config (its run line is shown, never run: it may start a service), and whether each service the block
names answers a TCP connect. It writes no file, no ledger, no state and no view. A variable whose name says it holds a
credential is never shown.

--propose reads facts, never runs a build: a Maven enforcer's JDK range or `<java.version>` with the project's own
`scripts/ensure-jdk*.sh --export` (else a JDK of that version in /usr/lib/jvm), a `*POSTGRES*PORT` variable the code reads with
a local Postgres cluster (`pg_lsclusters`), an `.nvmrc` (nvm selects it when installed). It proposes only what it found; with nothing found it
proposes nothing. --write is the person's choice at a question; the run line it writes is idempotent. Standard library only.
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
    var = find_var(project, r"\b([A-Z][A-Z0-9_]*POSTGRES[A-Z0-9_]*PORT)\b")
    if var and "postgres" not in kinds and shutil.which("pg_lsclusters"):   # a Compose service of the project wins
        try:
            out = subprocess.run(["pg_lsclusters", "-h"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=TOOL_LIMIT_S).stdout.decode()
        except (OSError, subprocess.TimeoutExpired):
            out = ""
        cl = [l.split() for l in out.splitlines() if len(l.split()) >= 3]
        if cl:
            ver, name, port = cl[0][:3]
            run.append("(pg_isready -q -h 127.0.0.1 -p %s || pg_ctlcluster %s %s start)" % (port, ver, name))
            env[var] = port
            services["postgres"] = "127.0.0.1:%s" % port
            facts.append("the code reads %s; a local Postgres %s cluster listens on %s" % (var, ver, port))
    # a Python virtual environment of the project
    venv = next((d for d in (".venv", "venv") if os.path.isfile(os.path.join(project, d, "bin", "activate"))), "")
    if venv:
        run.append(". %s/bin/activate" % venv)
        facts.append("%s/ is the project's Python environment" % venv)
        tools += [] if "python3" in tools else ["python3"]
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


def main(argv):
    if len(argv) >= 4 and argv[3] == "--propose":
        project, config = argv[1], argv[2]
        block, facts = propose(project)
        for f in facts:
            print("found: " + f)
        if not block:
            print("Nothing to propose: no need of the project was found that a setup block meets.")
            return 0
        if " #" in "\n".join(block):
            print("FAIL: the proposed run line holds ' #', which the config reader cuts", file=sys.stderr)
            return 1
        print("\n".join(block))
        if argv[4:] == ["--write"]:
            if run_env.load_setup(config):
                print("FAIL: %s has a setup block already; nothing was written" % config, file=sys.stderr)
                return 1
            os.makedirs(os.path.dirname(os.path.abspath(config)), exist_ok=True)
            old = read(config)
            with open(config, "a", encoding="utf-8") as f:
                f.write(("" if not old or old.endswith("\n") else "\n") + "\n# Proposed by temper doctor --propose, added by the person's choice.\n"
                        + "\n".join(block) + "\n")
            print("OK: the setup block is in %s" % config)
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
            print("  %s=%s" % (k, v))
        for k in setup["dropped"]:
            print("  left out (credential name): %s" % k)
    services = setup.get("services") or {}
    print("Services:" + ("" if services else " none named"))
    for name, addr in services.items():
        print("  %s %s: %s" % (name, addr, "answering" if answers(addr) else "not answering"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
