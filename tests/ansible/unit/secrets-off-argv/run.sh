#!/bin/bash
# No secret is templated into a shell or command task's script or a task's environment: a script reaches the remote
# shell's command line, the environment Ansible passes reaches sudo's (env VAR=value python), and any local user reads
# those in /proc - and a quote in a password templated into a root shell breaks out of its quoting. Secrets go on stdin
# (read, or a JSON document) with no_log (a module's arguments, stdin among them, are logged on its host), into a file
# of the run's own, or are read on the host from their root-only file. Named: a Jinja expression naming a password,
# passphrase, secret, token, API or private key or credentials (not a path to one) - or a variable that holds one, set
# by the play, a block or the task, directly or through another - in a shell/command script (free form, cmd: or argv:),
# in environment:, in an argument a module puts on a command line (expect's command, git's repo, helm's set_values,
# pip's extra_args), or on stdin without no_log. Excepted, each for its reason below.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PY'
import re, sys
from ansible.parsing.mod_args import FREEFORM_ACTIONS
sys.path.insert(0, "tests/ansible/unit")
import yaml  # noqa: E402
from plays import actions, files, load, plays  # noqa: E402
SECRET = re.compile(r"\{\{[^}]*\b\w*(password|passwd|passphrase|secret|token|api_key|apikey|private_key|credentials?"
                    r"|encrypt\w*_key|unseal\w*|jwt)\w*\b[^}]*\}\}", re.I)
# a file lookup reads the file: what it names is the secret, not a path to one
FILE_LOOKUP = re.compile(r"lookup\(\s*['\"](ansible\.builtin\.)?file['\"]")
# where a secret is, how many - not the secret
NOT_A_SECRET = re.compile(r"_(dir|file|path|name|ttl|policy|role|shares|threshold)\b", re.I)
JINJA = re.compile(r"\{\{.*?\}\}|\{%.*?%\}", re.S)
# arguments a module puts on a command line
ARGV_ARGS = {"ansible.builtin.expect": ("command",), "ansible.builtin.git": ("repo",),
             "kubernetes.core.helm": ("set_values",), "ansible.builtin.pip": ("extra_args",)}
# (file, task name): why it cannot go another way
ALLOWED = {}


def holders(scope):
    """The variables of a scope that hold a secret - templated in, directly or through another such variable."""
    text = {k: yaml.safe_dump(v, width=10000) for k, v in (scope or {}).items()}
    held = {k for k, t in text.items() if secrets(t)}
    while True:
        more = {k for k, t in text.items() if k not in held and refers(t, held)}
        if not more:
            return held
        held |= more


def refers(text, names):
    return any(re.search(rf"\b{re.escape(n)}\b", j) for j in JINJA.findall(str(text or "")) for n in names)


def secrets(text, held=()):
    found = [m.group(0) for m in SECRET.finditer(str(text or ""))
             if not NOT_A_SECRET.search(m.group(0)) or FILE_LOOKUP.search(m.group(0))]
    return found + ([f"(a variable holding one: {sorted(n for n in held if refers(text, [n]))})"]
                    if held and refers(text, held) else [])


def named(task, scope=None):
    """The templated secrets a task puts on a command line (its script, its environment, a module's argument that
    builds one) or in its host's log (stdin without no_log) - with `scope`, the variables its play and blocks set."""
    held = holders({**(scope or {}), **(task.get("vars") or {})})
    out = []
    for k, v in actions(task):
        if k in FREEFORM_ACTIONS:
            script = v if isinstance(v, str) else " ".join([str(v.get("cmd") or "")] + [str(a) for a in v.get("argv") or []]) \
                if isinstance(v, dict) else ""
            out += [f"script {s}" for s in secrets(script, held)]
            stdin = (v.get("stdin") if isinstance(v, dict) else None) or (task.get("args") or {}).get("stdin")
            if task.get("no_log") is not True:
                out += [f"stdin without no_log {s}" for s in secrets(stdin, held)]
        for a in ARGV_ARGS.get(k, ()) if isinstance(v, dict) else ():
            out += [f"argument {a} {s}" for s in secrets(yaml.safe_dump(v.get(a), width=10000), held)]
    if isinstance(task.get("environment"), dict):
        out += [f"environment {k}={s}" for k, v in task["environment"].items() for s in secrets(v, held)]
    return out


def walk(items, scope):
    """(task, the variables set around it) - a block's vars reach its tasks."""
    for t in items or []:
        if isinstance(t, dict):
            yield t, scope
            inner = {**scope, **(t.get("vars") or {})}
            for k in ("block", "rescue", "always"):
                yield from walk(t.get(k), inner)


def judged(doc):
    """What can put a secret on a command line, each with the variables set around it: each play (its environment
    reaches every task of it) and each task."""
    out = []
    for p in plays(doc):
        out.append((p, {}))
        for k in ("pre_tasks", "tasks", "post_tasks", "handlers"):
            out += list(walk(p.get(k), p.get("vars") or {}))
    if not plays(doc) and isinstance(doc, list):
        out += list(walk(doc, {}))
    return out


fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else ":\n  " + "\n  ".join(map(str, got if isinstance(got, list) else [got]))))


check("a password templated into a script: named",
      bool(named({"ansible.builtin.shell": "curl -u admin:{{ admin_password }} x"})), True)
check("one in a task's environment: named", bool(named({"ansible.builtin.shell": "x", "environment":
                                                         {"P": "{{ db_password }}"}})), True)
check("one in a play's environment: named", [n for t, sc in judged([{"hosts": "all", "environment": {"T": "{{ vault_token }}"},
                                                                     "tasks": [{"ansible.builtin.shell": "x"}]}])
                                            for n in named(t, sc)], ["environment T={{ vault_token }}"])
check("one on stdin with no_log, a path to one: not named",
      named({"ansible.builtin.shell": {"cmd": "cat {{ secret_dir }}/x", "stdin": "{{ db_password }}"}, "no_log": True})
      + named({"ansible.builtin.shell": "cat x", "args": {"stdin": "{{ db_password }}"}, "no_log": True}), [])
check("one on stdin without no_log (logged on its host): named",
      [bool(named({"ansible.builtin.shell": {"cmd": "cat", "stdin": "{{ db_password }}"}})),
       bool(named({"ansible.builtin.shell": "cat", "args": {"stdin": "{{ db_password }}"}}))], [True, True])
check("one through a variable - the task's, a block's, the play's, through another variable: named",
      [bool(named({"vars": {"c": "mc alias set x {{ minio_secret_key }}"}, "ansible.builtin.shell": "{{ c }}"})),
       bool([n for t, sc in judged([{"hosts": "all", "tasks": [{"vars": {"k": "{{ a_password }}"}, "block": [
           {"ansible.builtin.shell": "x {{ k }}"}]}]}]) for n in named(t, sc)]),
       bool([n for t, sc in judged([{"hosts": "all", "vars": {"k": "{{ a_token }}", "o": {"cmd": ["sh", "{{ k }}"]}},
                                     "tasks": [{"ansible.builtin.shell": "run '{{ o | to_json }}'"}]}])
             for n in named(t, sc)])], [True, True, True])
check("the unseal keys on stdin without no_log, a token file's content read by a lookup onto a script: named",
      [bool(named({"ansible.builtin.shell": {"cmd": "cat > f", "stdin": "{{ _unseal_keys.content | b64decode }}"}})),
       bool(named({"ansible.builtin.shell": "vault login {{ lookup('ansible.builtin.file', vault_token_file) }}"})),
       bool(named({"ansible.builtin.shell": "cat {{ vault_token_file }}"}))], [True, True, False])
# a chain of three variables: each holds the one before (the holders' fixpoint followed to its end)
check("through a chain of three variables: named", bool([n for t, sc in judged([{"hosts": "all", "vars": {
    "a": "{{ a_password }}", "b": "x {{ a }}", "c": "y {{ b }}"}, "tasks": [{"ansible.builtin.shell": "run {{ c }}"}]}])
    for n in named(t, sc)]), True)
# every section a play runs: pre_tasks, tasks, post_tasks, handlers
check("a secret in each section a play runs - pre_tasks, post_tasks, handlers: named",
      [bool([n for t, sc in judged([{"hosts": "all", k: [{"ansible.builtin.shell": "x {{ db_password }}"}]}])
             for n in named(t, sc)]) for k in ("pre_tasks", "post_tasks", "handlers")], [True, True, True])
check("a variable holding no secret, one named alike in plain text: not named",
      named({"vars": {"k": "{{ minio_url }}"}, "ansible.builtin.shell": "echo k {{ k }}"}), [])
check("a module that puts an argument on a command line (git's repo): named; a passphrase too",
      [bool(named({"ansible.builtin.git": {"repo": "https://u:{{ forgejo_token }}@x/r.git", "dest": "/d"}})),
       bool(named({"ansible.builtin.shell": "x {{ key_passphrase }}"}))], [True, True])
# and none read at run time onto another program's command line: a script's `curl -H "Authorization: Bearer $t"` or
# `x --token "$(cat /etc/x/token)"` puts it in /proc as surely as a templated one. A builtin's arguments (printf, echo,
# read) never reach an exec: curl takes the header from a descriptor (-K <(printf ...)), a file (-H @f) or stdin.
BUILTINS = {"printf", "echo", "read", "local", "export", "declare", "readonly", "set", "test", "[", "[[", "return"}
KEYWORDS = {"if", "elif", "while", "until", "!", "then", "do", "else", "time"}
# a secret on the command line: an authorization header of a variable (Bearer, token, Basic), a file's secret read in
# place by $( ), an option for one given a variable (--password "$x", --token=${T}, -p"$db_pass" - a variable named for
# one: -p is a port's too), curl's user:password with a variable password (-u, --user - curl's lower case alone: psql's
# -U is a user), vault login's token, a URL's credentials (https://u:${token}@host)
ARGV_SECRET = re.compile(r"(Bearer|Authorization:\s*(token|Basic))\s+\$"
                         r"|\$\(\s*(cat|<)\s*[^)]*(token|password|passwd|secret|private|\.key)\b[^)]*\)"
                         r"|--(password|passwd|token|secret)[= ]+\"?\$"
                         r"|(^|\s)-p\s*\"?\$\{?\w*(pass|pw|secret|token)"
                         r"|(^|\s)(?-i:-u|--user)[= ]*[\"']?[^\s\"':]*:[\"']?\$"
                         r"|(?<=\blogin\s)[\"']?(token=)?\$"
                         r"|://[^/\s:@]+:\$\{?\w+\}?@"
                         # Vault's token header, curl's bearer option, a -token= flag; a secret store's answer
                         # (vault kv get, vault read) handed over as an argument
                         r"|X-Vault-Token:\s*\$|--oauth2-bearer[= ]+\"?\$|(^|\s)-token[= ]+\"?\$"
                         r"|\$\(\s*vault\s+(kv\s+get|read)\b", re.I)


def argv_reads(script):
    """The lines of a shell script that hand a secret read at run time to another program's argv."""
    out, logical = [], ""
    for line in str(script or "").splitlines():
        logical += line.rstrip("\\") + " "
        if line.rstrip().endswith("\\"):
            continue
        cmd = logical.strip()
        logical = ""
        for m in ARGV_SECRET.finditer(cmd):
            # the command whose argv it lands on: the one its segment starts with - a $( )'s result is its outer
            # command's argument, a <( )'s inner command its own
            seg = re.split(r"&&|\|\||;|\||<\(|\bthen\b|\bdo\b|\{", cmd[:m.start()])[-1]
            words = [w for w in seg.split() if not re.match(r"^\w+=", w)]
            while words and words[0] in KEYWORDS:  # the shell's own words: the command is the next
                words.pop(0)
            if words and words[0] not in BUILTINS and not words[0].endswith("()"):
                out.append(cmd)
                break
    return out


check("a run-time token on another program's argv: named; on a builtin's, a descriptor's or a path's: not",
      [bool(argv_reads('curl -sf -H "Authorization: Bearer $(cat /etc/caddy/cluster-token)" x')),
       bool(argv_reads('curl -sf --cacert "$ca" \\\n  -H "Authorization: Bearer $token" \\\n  "$api"')),
       bool(argv_reads('vault login "$(cat /etc/vault-unseal/root-token)"')),
       bool(argv_reads('x=1; curl -K <(printf \'header = "Authorization: Bearer %s"\\n\' "$token") "$api"')),
       bool(argv_reads('read -r token < /etc/caddy/cluster-token')),
       bool(argv_reads('cat /etc/caddy/cluster-token > /dev/null')),
       bool(argv_reads('VAULT_TOKEN=$(cat /etc/vault-unseal/root-token)')),
       bool(argv_reads('if ! VAULT_TOKEN=$(cat /etc/vault-unseal/root-token 2> /dev/null); then exit 1; fi')),
       bool(argv_reads('if ! vault login "$(cat /etc/vault-unseal/root-token)"; then exit 1; fi')),
       # a secret read at run time into a variable, then given as an option's value
       bool(argv_reads('forgejo admin user change-password --username "$user" --password "$rnd"')),
       bool(argv_reads('mysql -u root -p"$db_pass" -e "select 1"')),
       bool(argv_reads('x --token="${TOKEN}" y')),
       bool(argv_reads('ssh -p "$port" host')),
       bool(argv_reads('docker login --password-stdin -u u < "$f"')),
       # once missed: another header's scheme, curl's user:password, vault login's token, a URL's credentials
       bool(argv_reads('curl -sf -H "Authorization: token $t" "$api"')),
       bool(argv_reads('curl -sf -u "$user:$pass" "$api"')),
       bool(argv_reads('curl -sf --user admin:"$pw" "$api"')),
       bool(argv_reads('vault login "$T"')),
       bool(argv_reads('git clone "https://u:${token}@git.example.org/r.git"')),
       bool(argv_reads('psql -U postgres -c "select 1"')),
       bool(argv_reads('vault login -method=userpass username=admin')),
       bool(argv_reads('git clone "https://git.example.org/r.git"')),
       # once missed: Vault's token header, curl's bearer, a -token= flag, a secret store's answer as an argument -
       # and the same read into a variable (no argv)
       bool(argv_reads('curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$addr/v1/x"')),
       bool(argv_reads('curl -sf --oauth2-bearer "$t" "$api"')),
       bool(argv_reads('consul acl token read -token="$CONSUL_HTTP_TOKEN"')),
       bool(argv_reads('python3 -c "x" "$(vault kv get -format=json secret/a)"')),
       bool(argv_reads('s=$(vault kv get -format=json secret/a)'))],
      [True, True, True, False, False, False, False, False, True, True, True, True, False, False,
       True, True, True, True, True, False, False, False, True, True, True, True, False])


def scripts(doc):
    """Every shell script a playbook runs or writes: its shell/command tasks' scripts and the files it writes that
    start #! (copy or template content)."""
    for t, _ in judged(doc):
        for k, v in actions(t):
            if k in FREEFORM_ACTIONS:
                yield t.get("name"), v if isinstance(v, str) else str((v or {}).get("cmd") or "") if isinstance(v, dict) else ""
            elif k in ("ansible.builtin.copy", "ansible.builtin.template") and isinstance(v, dict) \
                    and str(v.get("content") or "").startswith("#!"):
                yield t.get("name"), v["content"]


import glob  # noqa: E402
reads = [f"{f}: {n}: {line[:120]}" for f in files("deploy/ansible") for n, sc in scripts(load(f))
         for line in argv_reads(sc)]
reads += [f"{f}: {line[:120]}" for f in sorted(glob.glob("deploy/ansible/playbooks/scripts/*") + glob.glob("scripts/*.sh")
                                               + ["bootstrap.sh"]) for line in argv_reads(open(f, errors="replace").read())]
# the full run's own playbooks (tests/ansible/upgrade: every step runs them, on a copy holding production's
# secrets) too - each read named below in a pod's own shell (kubectl exec ... sh -c), the pod's env var on its client's
# argv in that pod: whether its ClickHouse client reads the password from its environment is not known here (24.8 to
# 25.x, not measured), Grafana's curl the same - left, each named, none more
POD_READS = {
    ("tests/ansible/upgrade/metrics-check.yml", "Container logs reach ClickHouse (Fluent Bit -> logs.podlogs, rows of the last two minutes)"),
    ("tests/ansible/upgrade/survival-check.yml", "ClickHouse - the canary table, its rows written and merged into one part (seed)"),
    ("tests/ansible/upgrade/survival-check.yml", "ClickHouse - exactly the seeded rows, the compatibility setting as the step files say, the version"),
    ("tests/ansible/upgrade/survival-check.yml", "Grafana - the canary dashboard (seed)"),
    ("tests/ansible/upgrade/survival-check.yml", "Grafana - every dashboard UID, and the canary's content"),
    ("tests/ansible/upgrade/survival-check.yml", "Grafana - every datasource healthy"),
    ("tests/ansible/upgrade/wave0-rehearsal.yml", "ClickHouse - the canary's frozen parts restored into a new table of its schema"),
}
pod_seen = set()
for f in files("tests/ansible/upgrade"):
    for n, sc in scripts(load(f)):
        for line in argv_reads(sc):
            if (f, n) in POD_READS:
                pod_seen.add((f, n))
            else:
                reads.append(f"{f}: {n}: {line[:120]}")
# Python scripts: a URL carrying a credential (f"http://{user}:{password}@...") lands on git's argv
PY_URL = re.compile(r"://\{[^}]+\}:\{[^}]*(pass|token|secret)[^}]*\}@", re.I)
reads += [f"{f}: {line.strip()[:120]}" for f in sorted(glob.glob("scripts/*.py") + glob.glob("deploy/ansible/playbooks/scripts/*.py"))
          for line in open(f, errors="replace") if PY_URL.search(line)]
check("no secret read onto another program's command line in a playbook's scripts, the full run's playbooks, the ops "
      "scripts (Python's among them), bootstrap.sh", reads, [])
check("every in-pod read left still there (one gone is dropped from the list, not kept)", sorted(POD_READS - pod_seen), [])
# the mirror's push: its credentials from a helper reading its environment - git asked as a push asks, the password
# with a quote and a $ given back exactly (git's credential protocol: no command line)
import importlib.util, os, subprocess  # noqa: E401,E402
spec = importlib.util.spec_from_file_location("mirror", "scripts/vagrant-gitops-mirror.py")
mirror = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mirror)
r = subprocess.run(["git", "-c", "credential.helper=", "-c", "credential.helper=" + mirror.CRED_HELPER, "credential", "fill"],
                   input="protocol=http\nhost=x\n\n", capture_output=True, text=True,
                   env=dict(os.environ, MIRROR_USER="u1", MIRROR_PASSWORD="p'w$x", GIT_TERMINAL_PROMPT="0"))
check("the mirror's credential helper: git given the user and the password from its environment, exactly",
      (r.returncode, "username=u1" in r.stdout.splitlines(), "password=p'w$x" in r.stdout.splitlines()), (0, True, True))
# the realm seed's two Vault answers read one after the other from stdin - its parse on two documents as vault prints them
seed = next(t for p in load("tests/ansible/upgrade/keycloak-realm.yml") if isinstance(p, dict)
            for t in p.get("tasks") or [] if t.get("name") == "Read the Keycloak and Grafana secrets from the Vagrant Vault")
code = str(seed["ansible.builtin.shell"]).split("python3 -c '", 1)[1].rsplit("'", 1)[0]
doc = lambda d: json.dumps({"request_id": "x", "data": {"data": d, "metadata": {}}}, indent=2) + "\n"
import json  # noqa: E402
r = subprocess.run(["python3", "-c", "\n".join(l[8:] if l.startswith(" " * 8) else l for l in code.splitlines())],
                   input=doc({"admin_password": "a"}) + doc({"admin_password": "g"}), capture_output=True, text=True)
check("the realm seed's two Vault answers parsed from stdin, each its own",
      json.loads(r.stdout or "{}") if r.returncode == 0 else r.stderr[-200:],
      {"keycloak": {"admin_password": "a"}, "grafana": {"admin_password": "g"}})
check("a Python URL with a credential: named; one without: not",
      [bool(PY_URL.search('url = f"http://{user}:{password}@{host}/r.git"')),
       bool(PY_URL.search('url = f"http://{host}/schnappy/{name}.git"'))], [True, False])
bad, used = [], set()
for f in files("deploy/ansible", "tests/ansible/upgrade"):
    for t, scope in judged(load(f)):
        for n in named(t, scope):
            if (f, t.get("name")) in ALLOWED:
                used.add((f, t.get("name")))
            else:
                bad.append(f"{f}: {t.get('name')}: {n}")
check("no secret on a command line in deploy/ansible or the full run's playbooks (beyond the excepted)", bad, [])
check("every exception still needed (one whose task changed is dropped, not kept)", sorted(set(ALLOWED) - used), [])
print("secrets-off-argv: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
