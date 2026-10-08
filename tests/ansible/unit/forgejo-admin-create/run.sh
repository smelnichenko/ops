#!/bin/bash
# The two tasks that create Forgejo's admin (setup-pi-services, setup-patroni), their scripts and stdin rendered by
# Ansible's templar, `su - forgejo -c` played by bash, forgejo and curl stubs recording what they are given. Forgejo's
# CLI takes a password only as an argument (any local user reads those in /proc): the admin is made with a random one
# (Forgejo says it), then its password set through Forgejo's API - the random one on curl's config descriptor, the real
# one in the request's body on stdin, exactly, with $( ), backticks, quotes and a backslash, nothing of it run; neither
# ever on a command line. All on the task's stdin, no_log. Proven against Forgejo 15.0.9 itself (2026-10-08: the admin
# logged in with the password so set, a wrong one refused).
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
name = "change-argv.json" if "change-password" in a else "argv.json"
json.dump(a, open(os.path.join(os.environ["W"], name), "w"))
if "create" in a:
    if os.environ.get("EXISTS"):  # a retry after the create: the user there
        sys.exit("Command error: CreateUser: user already exists [name: admin]")
    print("generated random password is 'Rnd0mPw4tEst'")
    print("New user 'admin' has been successfully created!")
STUB
# curl: its argv, the config it reads from -K, and its body from stdin (--data @-)
cat > "$W/bin/curl" <<'STUB'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
conf = open(a[a.index("-K") + 1]).read() if "-K" in a else ""
body = sys.stdin.read() if "@-" in a else ""
json.dump({"argv": a, "config": conf, "body": body}, open(os.path.join(os.environ["W"], "curl.json"), "w"))
print(200)
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
for book in ("setup-pi-services", "setup-patroni"):
    t = [t for t in tasks(load(f"deploy/ansible/playbooks/{book}.yml")) if "forgejo admin user create" in str(t)]
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
        for f in ("argv.json", "curl.json", "ran", "ran2"):
            os.path.exists(os.path.join(W, f)) and os.remove(os.path.join(W, f))
        r = subprocess.run(["bash", "-c", script], input=data, capture_output=True, text=True,
                           env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W))
        argv = json.load(open(os.path.join(W, "argv.json"))) if os.path.exists(os.path.join(W, "argv.json")) else []
        arg = lambda k: argv[argv.index(k) + 1] if k in argv else None
        c = json.load(open(os.path.join(W, "curl.json"))) if os.path.exists(os.path.join(W, "curl.json")) else {}
        body = json.loads(c["body"]) if c.get("body") else {}
        check(f"{book}: password {n + 1}: the admin made with a random one (no --password), the user and the e-mail "
              "exactly; then its password set through the API - the real one in the body exactly, the random one on "
              "curl's config, neither on a command line; nothing of them run",
              (r.returncode, "--password" in argv, "--random-password" in argv, arg("--username"), arg("--email"),
               body.get("password") == PW, body.get("must_change_password"), "admin:Rnd0mPw4tEst" in c.get("config", ""),
               any(PW in x or "Rnd0mPw4tEst" in x for x in c.get("argv", [])),
               c.get("argv", [""])[-1].endswith("/api/v1/admin/users/admin"),
               os.path.exists(os.path.join(W, "ran")) or os.path.exists(os.path.join(W, "ran2"))),
              (0, False, True, "admin", "a'b@example.org", True, False, True, False, True, False))
    # a retry after the create (the user there, its random password unknown): a throwaway set, then the real one
    # through the API - the real one never on a command line
    v = dict(forgejo_admin_user="admin", forgejo_admin_email="a@b", forgejo_admin_password=PWS[0])
    script = render(cmd, **v).replace("su - forgejo -c ", "bash -c ")
    data = render(str(stdin), **v) + ("\n" if add_nl else "")
    for f in ("argv.json", "change-argv.json", "curl.json"):
        os.path.exists(os.path.join(W, f)) and os.remove(os.path.join(W, f))
    r = subprocess.run(["bash", "-c", script], input=data, capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, EXISTS="1"))
    ch = json.load(open(os.path.join(W, "change-argv.json"))) if os.path.exists(os.path.join(W, "change-argv.json")) else []
    c = json.load(open(os.path.join(W, "curl.json"))) if os.path.exists(os.path.join(W, "curl.json")) else {}
    thrown = ch[ch.index("--password") + 1] if "--password" in ch else None
    check(f"{book}: a retry, the user there: a throwaway set, then the real password through the API - never on a "
          "command line", (r.returncode, thrown is not None and thrown != PWS[0], f"admin:{thrown}" in c.get("config", ""),
                           json.loads(c.get("body") or "{}").get("password") == PWS[0]), (0, True, True, True))
print("forgejo-admin-create: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYFAC
