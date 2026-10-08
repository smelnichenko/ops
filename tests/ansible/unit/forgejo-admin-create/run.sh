#!/bin/bash
# The two tasks that create Forgejo's admin (setup-pi-services, setup-patroni), their scripts and stdin rendered by
# Ansible's templar, `su - forgejo -c` played by bash, forgejo and curl stubs recording what they are given. Forgejo's
# CLI takes a password only as an argument (any local user reads those in /proc): the admin is made with a random one
# (Forgejo says it), then its password set through Forgejo's API - the random one on curl's config descriptor, the real
# one in the request's body on stdin, exactly, with $( ), backticks, quotes and a backslash, nothing of it run; neither
# ever on a command line. A retry after the create (the user there, its random password unknown): a write:admin token
# from Forgejo's CLI (on its stdout) sets it, then every such token deleted with the real one - no password on any
# argument, a throwaway's either. A create failing otherwise fails, nothing more done. All on the task's stdin, no_log.
# Proven against Forgejo 15.0.9 itself (2026-10-08: the admin logged in with the password so set, a wrong one refused;
# the retry's token made, used and deleted).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/forgejo" <<'STUB'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
name = ("change-argv.json" if "change-password" in a else "token-argv.json" if "generate-access-token" in a
        else "argv.json")
json.dump(a, open(os.path.join(os.environ["W"], name), "w"))
if "create" in a:
    if os.environ.get("CREATE_FAILS"):  # another failure: the database locked
        sys.exit("Command error: CreateUser: database is locked")
    if os.environ.get("EXISTS"):  # a retry after the create: the user there
        sys.exit("Command error: CreateUser: user already exists [name: admin]")
    print("generated random password is 'Rnd0mPw4tEst'")
    print("New user 'admin' has been successfully created!")
if "generate-access-token" in a:
    # TOKEN_GARBAGE: an answer that is no token (a warning, an error said on stdout with exit 0)
    print("2026/10/08 11:00:00 ...s/setting/setting.go:42:loadRunModeFrom() [W] running as root" if os.environ.get(
        "TOKEN_GARBAGE") else "0123456789abcdef0123456789abcdef01234567")
STUB
# curl: each call's argv, the config it reads from -K, and its body from stdin (--data @-), one JSON line each (the
# last also in curl.json); a GET of the user's tokens answers a page as Forgejo does (limit, 30 by default; page, 1 by
# default) of 61: 59 of the user's own, then one an earlier retry left - past the first page - and one more
cat > "$W/bin/curl" <<'STUB'
#!/usr/bin/env python3
import json, os, sys, urllib.parse
a = sys.argv[1:]
conf = open(a[a.index("-K") + 1]).read() if "-K" in a else ""
body = sys.stdin.read() if "@-" in a else ""
call = {"argv": a, "config": conf, "body": body}
json.dump(call, open(os.path.join(os.environ["W"], "curl.json"), "w"))
open(os.path.join(os.environ["W"], "curl-calls"), "a").write(json.dumps(call) + "\n")
path, _, query = a[-1].partition("?")
if path.endswith("/tokens") and "-X" not in a:
    if os.environ.get("TOKENS_FAIL"):
        sys.exit(22)
    q = urllib.parse.parse_qs(query)
    limit, page = int(q.get("limit", ["30"])[0]), int(q.get("page", ["1"])[0])
    every = [{"id": 100 + i, "name": f"ci-{i}"} for i in range(59)] + [{"id": 7, "name": "password-reset-0badc0de"},
                                                                       {"id": 3, "name": "ci"}]
    print(json.dumps(every[(page - 1) * min(limit, 50):page * min(limit, 50)]))
STUB
chmod +x "$W/bin/forgejo" "$W/bin/curl"
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYFAC'
import json, os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render  # noqa: E402
from plays import load, tasks  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
# one with a quote (it broke out of the script's quoting), one without (root's shell ran its $( ) and ` at once)
PWS = ("p$(touch " + W + "/ran)`touch " + W + "/ran2`'\"\\x", "p$(touch " + W + "/ran)`touch " + W + "/ran2`")
# one script for both playbooks: a task file each imports - setup-patroni's on pi1, once (its database rebuilt, the
# admin made again); neither holds a copy of its own (two copies drifted apart once each fix had to land twice)
TASKS = "deploy/ansible/playbooks/tasks/forgejo-admin.yml"
for book, keywords in (("setup-pi-services", {}), ("setup-patroni", {"run_once": True, "delegate_to": "pi1"})):
    doc = load(f"deploy/ansible/playbooks/{book}.yml")
    imports = [t for t in tasks(doc) if str(t.get("ansible.builtin.import_tasks", "")).endswith("tasks/forgejo-admin.yml")]
    check(f"{book}: the admin's tasks imported once, as its play needs them; no copy of its own",
          ([{k: t.get(k) for k in keywords} for t in imports], sum("forgejo admin user create" in str(t)
                                                                    for t in tasks(doc))), ([keywords], 0))
for book in ("tasks/forgejo-admin",):
    t = [t for t in load(TASKS) if "forgejo admin user create" in str(t)] if os.path.exists(TASKS) else []
    check(f"{book}: one task creates the admin", len(t), 1)
    if len(t) != 1:
        continue
    t = t[0]
    sh = t["ansible.builtin.shell"]
    cmd = sh if isinstance(sh, str) else sh["cmd"]
    stdin = (sh.get("stdin") if isinstance(sh, dict) else None) or (t.get("args") or {}).get("stdin")
    check(f"{book}: the password not in the script, on stdin, no_log",
          ("forgejo_admin_password" in cmd, "forgejo_admin_password" in str(stdin), t.get("no_log")), (False, True, True))
    for n, PW in enumerate(PWS):
        v = dict(forgejo_admin_user="admin", forgejo_admin_email="a'b@example.org", forgejo_admin_password=PW)
        script = render(cmd, **v).replace("su - forgejo -c ", "bash -c ")
        add_nl = (sh.get("stdin_add_newline", True) if isinstance(sh, dict) else True)
        data = render(str(stdin), **v) + ("\n" if add_nl else "") if stdin else ""
        for f in ("argv.json", "curl.json", "curl-calls", "ran", "ran2"):
            os.path.exists(os.path.join(W, f)) and os.remove(os.path.join(W, f))
        r = subprocess.run(["bash", "-c", script], input=data, capture_output=True, text=True,
                           env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W))
        argv = json.load(open(os.path.join(W, "argv.json"))) if os.path.exists(os.path.join(W, "argv.json")) else []
        arg = lambda k: argv[argv.index(k) + 1] if k in argv else None
        cl = os.path.join(W, "curl-calls")
        every = [json.loads(x) for x in open(cl).read().splitlines()] if os.path.exists(cl) else []
        c = next((x for x in every if "PATCH" in x["argv"]), {})  # the password set
        body = json.loads(c["body"]) if c.get("body") else {}
        check(f"{book}: password {n + 1}: the admin made with a random one (no --password), the user and the e-mail "
              "exactly; then its password set through the API - the real one in the body exactly, the random one on "
              "curl's config, neither on a command line; nothing of them run",
              (r.returncode, "--password" in argv, "--random-password" in argv, arg("--username"), arg("--email"),
               body.get("password") == PW, body.get("must_change_password"), "admin:Rnd0mPw4tEst" in c.get("config", ""),
               any(PW in x or "Rnd0mPw4tEst" in x for e in every for x in e["argv"]),
               c.get("argv", [""])[-1].endswith("/api/v1/admin/users/admin"),
               os.path.exists(os.path.join(W, "ran")) or os.path.exists(os.path.join(W, "ran2"))),
              (0, False, True, "admin", "a'b@example.org", True, False, True, False, True, False))
    # a retry after the create (the user there, its random password unknown): a throwaway set, then the real one
    # through the API - the real one never on a command line
    v = dict(forgejo_admin_user="admin", forgejo_admin_email="a@b", forgejo_admin_password=PWS[0])
    script = render(cmd, **v).replace("su - forgejo -c ", "bash -c ")
    data = render(str(stdin), **v) + ("\n" if add_nl else "")
    def fresh():
        for f in ("argv.json", "change-argv.json", "token-argv.json", "curl.json", "curl-calls"):
            os.path.exists(os.path.join(W, f)) and os.remove(os.path.join(W, f))
    def calls():
        p = os.path.join(W, "curl-calls")
        return [json.loads(x) for x in open(p).read().splitlines()] if os.path.exists(p) else []
    fresh()
    r = subprocess.run(["bash", "-c", script], input=data, capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, EXISTS="1"))
    tok = json.load(open(os.path.join(W, "token-argv.json"))) if os.path.exists(os.path.join(W, "token-argv.json")) else []
    arg = lambda k: tok[tok.index(k) + 1] if k in tok else None
    cs = calls()
    patch = [c for c in cs if "PATCH" in c["argv"]]
    deleted = [c["argv"][-1].rsplit("/", 1)[1] for c in cs if "DELETE" in c["argv"]]
    esc = PWS[0].replace("\\", "\\\\").replace('"', '\\"')
    check(f"{book}: a retry, the user there: a write:admin token from Forgejo's CLI (no throwaway password set) sets the "
          "real one through the API - the token on curl's config; then the reset tokens deleted (only those) with the real "
          "password on curl's config; no password, no token on any command line",
          (r.returncode, os.path.exists(os.path.join(W, "change-argv.json")), arg("--scopes"), "--raw" in tok,
           (arg("--token-name") or "").startswith("password-reset-"),
           [("Authorization: token 0123456789abcdef0123456789abcdef01234567" in c["config"],
             json.loads(c["body"] or "{}").get("password") == PWS[0]) for c in patch],
           deleted, all(f'user = "admin:{esc}"' in c["config"] for c in cs if "PATCH" not in c["argv"]),
           any(PWS[0] in x or "0123456789abcdef0123456789abcdef01234567" in x for c in cs for x in c["argv"])),
          (0, False, "write:admin", True, True, [(True, True)], ["7"], True, False))
    # the reset tokens not read (the API failing): the task fails - a write:admin token never left unsaid
    fresh()
    r = subprocess.run(["bash", "-c", script], input=data, capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, EXISTS="1",
                                TOKENS_FAIL="1"))
    check(f"{book}: a retry whose reset tokens are not read: fails", r.returncode != 0, True)
    # the CLI's answer no token: fails, said - nothing sent to the API with it
    fresh()
    r = subprocess.run(["bash", "-c", script], input=data, capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, EXISTS="1",
                                TOKEN_GARBAGE="1"))
    check(f"{book}: a retry whose CLI answers no token: fails, said - nothing sent to the API",
          (r.returncode != 0, "no token in Forgejo's answer" in r.stdout + r.stderr, calls()), (True, True, []))
    # a create failing otherwise (not "already exists"): the task fails, said - no token made, nothing sent
    fresh()
    r = subprocess.run(["bash", "-c", script], input=data, capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W,
                                CREATE_FAILS="1"))
    check(f"{book}: a create failing otherwise: fails, said - no token, nothing sent to the API",
          (r.returncode != 0, "database is locked" in r.stdout + r.stderr,
           os.path.exists(os.path.join(W, "token-argv.json")), calls()), (True, True, False, []))
print("forgejo-admin-create: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYFAC
