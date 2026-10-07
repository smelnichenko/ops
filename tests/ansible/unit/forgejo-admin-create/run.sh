#!/bin/bash
# The two tasks that create Forgejo's admin (setup-pi-services, setup-patroni), their scripts and stdin rendered by
# Ansible's templar, `su - forgejo -c` played by bash, forgejo a stub recording its arguments: a password with $( ),
# backticks, quotes and a backslash reaches Forgejo's --password exactly, nothing of it run (templated into the script,
# root's shell expanded $ and ` in it before su ran); the user and the e-mail too. Forgejo's CLI takes the password
# only as an argument: it goes on stdin, read by forgejo's own shell, with no_log (a module's stdin is logged on its
# host).
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
json.dump(sys.argv[1:], open(os.path.join(os.environ["W"], "argv.json"), "w"))
STUB
chmod +x "$W/bin/forgejo"
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
        script = render(cmd, **v).replace("su - forgejo -c ", "bash -c ", 1)
        add_nl = (sh.get("stdin_add_newline", True) if isinstance(sh, dict) else True)
        data = render(str(stdin), **v) + ("\n" if add_nl else "") if stdin else ""
        for f in ("argv.json", "ran", "ran2"):
            os.path.exists(os.path.join(W, f)) and os.remove(os.path.join(W, f))
        r = subprocess.run(["bash", "-c", script], input=data, capture_output=True, text=True,
                           env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W))
        argv = json.load(open(os.path.join(W, "argv.json"))) if os.path.exists(os.path.join(W, "argv.json")) else []
        arg = lambda k: argv[argv.index(k) + 1] if k in argv else None
        check(f"{book}: Forgejo given password {n + 1}, the user and the e-mail exactly, nothing of them run",
              (r.returncode, arg("--password") == PW, arg("--username"), arg("--email"),
               os.path.exists(os.path.join(W, "ran")) or os.path.exists(os.path.join(W, "ran2"))),
              (0, True, "admin", "a'b@example.org", False))
print("forgejo-admin-create: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYFAC
