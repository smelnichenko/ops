#!/bin/bash
# setup-pgbouncer.yml's role task as the playbook holds it (rendered by Ansible's templar), run with psql a stub that
# records its arguments, its environment and the SQL it is given: the password set for pgbouncer goes to Postgres as a
# SCRAM-SHA-256 verifier made on the Pi from the password file - never the password itself (Postgres logs a failed
# statement's text: log_min_error_statement = error on production, read 2026-10-08), on no command line; the verifier
# checked against RFC 5802/7677 with the salt it carries (4096 iterations, StoredKey and ServerKey of that password).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/psql" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$W/psql-argv"
env > "$W/psql-env"
cat > "$W/psql-sql"
STUB
chmod +x "$W/bin/psql"
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYSCRAM'
import base64, hashlib, hmac, os, re, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
book = yaml.safe_load(open("deploy/ansible/playbooks/setup-pgbouncer.yml"))
task = next(t for p in book for t in p.get("tasks") or [] if "ALTER ROLE pgbouncer" in str(t))
sh = task["ansible.builtin.shell"]
script = render(sh["cmd"], auth_secret_dir=W, haproxy_port=5000)
PW = "0123456789abcdef" * 4
open(os.path.join(W, "auth_user.password"), "w").write(PW + "\n")
r = subprocess.run([sh.get("executable", "/bin/sh"), "-c", script], input="THE-ADMIN-PASSWORD\n", capture_output=True,
                   text=True, env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W))
check("the task's script runs", r.returncode, 0)
read = lambda f: open(os.path.join(W, f)).read() if os.path.exists(os.path.join(W, f)) else ""
argv, env, sql = read("psql-argv"), read("psql-env"), read("psql-sql")
check("the password neither in psql's arguments, its environment nor its SQL", PW in argv + env + sql, False)
# the lookup runs as its owner (SECURITY DEFINER, reading pg_shadow): its search_path fixed - a caller's own schema
# first in it would otherwise resolve names the function uses to the caller's objects
fn = re.search(r"CREATE OR REPLACE FUNCTION public\.user_lookup.*?\$\$ LANGUAGE plpgsql([^;]*);", sql, re.S)
check("the lookup SECURITY DEFINER with its search_path fixed (pg_catalog, pg_temp)",
      bool(fn) and "SECURITY DEFINER" in fn.group(1) and re.search(r"SET search_path\s*=\s*pg_catalog,\s*pg_temp",
                                                                   fn.group(1)) is not None, True)
check("nor the verifier on its command line", "SCRAM-SHA-256$" in argv, False)
var = re.search(r"^\\getenv pw (\w+)$", sql, re.M)
check("the SQL reads the verifier from psql's environment, the ALTER takes it quoted by the server",
      (var is not None, "format('ALTER ROLE pgbouncer WITH PASSWORD %L', :'pw')" in sql), (True, True))
out = next((l.split("=", 1)[1] for l in env.splitlines() if var and l.startswith(var.group(1) + "=")), "")
v = re.fullmatch(r"SCRAM-SHA-256\$(\d+):([A-Za-z0-9+/=]+)\$([A-Za-z0-9+/=]+):([A-Za-z0-9+/=]+)", out)
check("a SCRAM-SHA-256 verifier", v is not None, True)
if v:
    it, salt = int(v.group(1)), base64.b64decode(v.group(2))
    salted = hashlib.pbkdf2_hmac("sha256", PW.encode(), salt, it)
    client = hmac.new(salted, b"Client Key", hashlib.sha256).digest()
    server = hmac.new(salted, b"Server Key", hashlib.sha256).digest()
    check("4096 iterations, a 16-byte salt", (it, len(salt)), (4096, 16))
    # a new salt each run (a fixed one makes every Postgres's verifier of this password the same)
    subprocess.run([sh.get("executable", "/bin/sh"), "-c", script], input="THE-ADMIN-PASSWORD\n", capture_output=True,
                   text=True, env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W))
    again = next((l.split("=", 1)[1] for l in read("psql-env").splitlines() if l.startswith(var.group(1) + "=")), "")
    check("each run its own salt", again.split("$")[1].split(":")[1] != v.group(2) if again.count("$") >= 2 else "no verifier",
          True)
    check("its StoredKey and ServerKey are the password's (RFC 5802)",
          (base64.b64decode(v.group(3)) == hashlib.sha256(client).digest(), base64.b64decode(v.group(4)) == server),
          (True, True))
print("pgbouncer-scram: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYSCRAM
