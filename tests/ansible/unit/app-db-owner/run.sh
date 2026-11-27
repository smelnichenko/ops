#!/bin/bash
# Forgejo and Keycloak logging into their databases as their own roles (tasks/app-db-owner.yml, files/app-db-owner.sql),
# never as the superuser: the roles made and given their databases on the Patroni leader (setup-patroni.yml) and on a
# first install (setup-pi-services.yml); Forgejo's app.ini and Keycloak's unit naming them; their passwords the
# inventory's own (.env FORGEJO_DB_ROLE_PASSWORD, KEYCLOAK_DB_ROLE_PASSWORD), never the superuser's; a config naming a
# login that does not work refused before it is written; the password reaching psql quoted for it (a quote or a
# backslash in it kept), the SQL quoting it again for Postgres. The SQL itself is proven against Postgres 17 (its
# major on the Pis) and the whole on the copy (tests/ansible/copy/forgejo-check.yml: the services' backends theirs, each
# database and everything in it its role's).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PYCHECK'
import re, sys, yaml, jinja2
fails = 0
def check(name, got, want):
    global fails
    if got == want:
        print("PASS " + name)
    else:
        fails += 1
        print(f"FAIL {name}\n    got:  {got!r}\n    want: {want!r}")
PB = "deploy/ansible/playbooks"
def plays(path):
    return yaml.safe_load(open(path)) or []
def tasks(play):
    out = []
    def walk(ts):
        for t in ts or []:
            out.append(t)
            for k in ("block", "rescue", "always"):
                walk(t.get(k))
    walk(play.get("tasks"))
    walk(play.get("handlers"))
    return out
def names(play):
    return [t.get("name", "") for t in tasks(play)]
svc = plays(f"{PB}/setup-pi-services.yml")[0]
ts = tasks(svc)
by = {t.get("name"): t for t in ts}
ini = by["Write Forgejo config"]["ansible.builtin.copy"]["content"]
check("Forgejo's app.ini: its own role and its own password", (re.search(r"^USER = (.*)$", ini, re.M).group(1),
      re.search(r"^PASSWD = (.*)$", ini, re.M).group(1), (svc.get("vars") or {}).get("forgejo_db_user")),
      ("{{ forgejo_db_user }}", "{{ forgejo_db_password }}", "forgejo"))
unit = by["Install Keycloak systemd service"]["ansible.builtin.copy"]["content"]
check("Keycloak's unit: its own role", (re.findall(r"Environment=KC_DB_USERNAME=(.*)", unit), (svc.get("vars") or {}).get("keycloak_db_user")),
      (["{{ keycloak_db_user }}"], "keycloak"))
check("  its password the inventory's own (the secrets file)", "KC_DB_PASSWORD={{ keycloak_db_password }}" in by["Keycloak's secrets, root only - written aside, put in place once their login works"]["ansible.builtin.copy"]["content"], True)
alnum = by.get("The roles' passwords are letters and digits", {}).get("ansible.builtin.assert", {}).get("that")
check("  the roles' passwords letters and digits (go-ini and systemd each read quotes, '#', a backslash their own way)", alnum,
      ["forgejo_db_user != 'forgejo' or forgejo_db_password is match('^[A-Za-z0-9]+$')",
       "keycloak_db_user != 'keycloak' or keycloak_db_password is match('^[A-Za-z0-9]+$')"])
check("the play maps neither password to the superuser's (the inventory gives them)",
      {k: v for k, v in (svc.get("vars") or {}).items() if k in ("forgejo_db_password", "keycloak_db_password")}, {})
creds = by["Its credentials are all there"]["ansible.builtin.assert"]["that"]
check("  both refused empty with the other credentials", [c for c in creds if "forgejo_db_password" in c or "keycloak_db_password" in c],
      ["forgejo_db_password | default('') | length > 0", "keycloak_db_password | default('') | length > 0"])
# a login that does not work: refused before the config naming it is written (a restart on it took the service down)
order = names(svc)
def first(pred):
    return next((i for i, t in enumerate(ts) if pred(t)), None)
fg = first(lambda t: "psql" in str(t.get("ansible.builtin.shell", "")) and "forgejo_db_user" in str(t.get("ansible.builtin.shell", "")))
check("Forgejo's login tried before its app.ini is written (its role, its database, through its own host)",
      fg is not None and fg < order.index("Write Forgejo config")
      and "forgejo-config" in (ts[fg].get("tags") or []) and "{{ forgejo_db_password }}" in str(ts[fg].get("ansible.builtin.shell", {}).get("stdin", "")), True)
kc = first(lambda t: "psql" in str(t.get("ansible.builtin.shell", "")) and "keycloak_db_user" in str(t.get("ansible.builtin.shell", "")))
fsh = str(ts[fg]["ansible.builtin.shell"]["cmd"]) if fg is not None else ""
USABLE = "not pg_has_role(current_user, c.relowner, 'USAGE')) || ' ' || has_schema_privilege('public', 'CREATE')"
check("  into its own database, through the host and port its config names - asking what it needs there (every relation "
      "its own or a role it has, CREATE on public), not a login alone", ("-d forgejo" in fsh, "forgejo_db_host_effective" in fsh,
      '-h "$host" -p "$port"' in fsh, USABLE in fsh, '-c "$q"' in fsh), (True, True, True, True, True))
fa = by.get("Forgejo's login works - or its config is not written", {})
check("  its result judged: psql's exit and its answer, else refused - under Patroni (the task and its judgement alike)",
      (fa.get("ansible.builtin.assert", {}).get("that"), ts[fg].get("failed_when"), ts[fg].get("when"), fa.get("when")),
      ("_forgejo_login.rc == 0 and _forgejo_login.stdout | trim == '0 true'", False, "_patroni_installed | bool", "_patroni_installed | bool"))
check("Keycloak's login tried as systemd reads its secrets file, before its unit names it",
      kc is not None and kc < order.index("Install Keycloak systemd service")
      and "EnvironmentFile=/etc/keycloak/secrets.env.new" in str(ts[kc]["ansible.builtin.shell"])
      and "keycloak-db-url" in (ts[kc].get("tags") or []), True)
ksh = str(ts[kc]["ansible.builtin.shell"]["cmd"]) if kc is not None else ""
check("  into its own database, through the host and port its URL names, asking what it needs; anything else fails the task",
      ("-d keycloak" in ksh, "keycloak_db_host_effective" in ksh, USABLE in ksh, ts[kc].get("failed_when") if kc is not None else None),
      (True, True, True, "_keycloak_login.rc != 0 or _keycloak_login.stdout | trim != '0 true'"))
sec = order.index("Keycloak's secrets, root only - written aside, put in place once their login works")
place = order.index("Keycloak's secrets in place - the ones just judged")
check("  its secrets written aside, judged, and only then put where Keycloak reads them - a refused run touches neither",
      (by["Keycloak's secrets, root only - written aside, put in place once their login works"]["ansible.builtin.copy"]["dest"],
       sec < kc < place < order.index("Install Keycloak systemd service"),
       by["Keycloak's secrets in place - the ones just judged"]["ansible.builtin.copy"].get("src"),
       by["Keycloak's secrets in place - the ones just judged"].get("diff")),
      ("/etc/keycloak/secrets.env.new", True, "/etc/keycloak/secrets.env.new", False))
check("  no comparison with the password Keycloak runs with now (that refused the switch itself)",
      [t.get("name") for t in ts if "/proc/$pid/environ" in str(t)], [])
# the roles made: on a first install after its databases, on the Patroni leader after its databases (and a restore)
inc = lambda t: (t.get("ansible.builtin.include_tasks") or t.get("ansible.builtin.import_tasks") or {})
def includes(play):
    return [i for i, t in enumerate(tasks(play)) if "app-db-owner.yml" in str(inc(t))]
fi = includes(svc)
check("a first install: the roles made after its databases, before Forgejo's config", len(fi) == 1
      and order.index("Create Forgejo and Keycloak databases (first install only)") < fi[0] < order.index("Write Forgejo config")
      and "not _patroni_installed" in str(ts[fi[0]].get("when")), True)
primary = next(p for p in plays(f"{PB}/setup-patroni.yml") if p.get("hosts") == "patroni_primary")
pi = includes(primary)
restore = names(primary).index("Restore the waiting Keycloak dump")
check("the Patroni leader: the roles made every run after its databases and BEFORE a waiting dump's restore (its tables "
      "are theirs: no role, the restore failed whole), and once more after it (an old dump's tables the superuser's)",
      (len(pi), pi[0] < restore < pi[-1], "when" not in tasks(primary)[pi[0]], tasks(primary)[pi[-1]].get("when")),
      (2, True, True, "_keycloak_dump.stat.exists"))
pat_assert = tasks(plays(f"{PB}/setup-patroni.yml")[0])[0]["ansible.builtin.assert"]["that"]
check("  setup-patroni refuses an empty role password before anything (its first play reloads Patroni)",
      [c for c in pat_assert if "_db_password" in c], ["forgejo_db_password | default('') | length > 0", "keycloak_db_password | default('') | length > 0"])
doc = plays(f"{PB}/forgejo-doctor.yml")[0]
check("forgejo-doctor's lock taken as Forgejo's role (it owns package_blob), never the superuser",
      ((doc.get("vars") or {}).get("_db_password"), "-U forgejo -d forgejo" in open(f"{PB}/forgejo-doctor.yml").read(),
       "-U postgres" in open(f"{PB}/forgejo-doctor.yml").read()), ("{{ forgejo_db_password }}", True, False))
check("test-forgejo-upgrade's empty database its role's (on PG 15+ public is the owner's: a postgres database refused Forgejo)",
      "CREATE DATABASE forgejo OWNER forgejo" in open("tests/ansible/test-forgejo-upgrade.yml").read(), True)
up = plays(f"{PB}/upgrade-forgejo.yml")[0]
dump = next((t for t in tasks(up) if "pg_dump" in str(t)), {})
check("upgrade-forgejo's dump: the superuser's login and its password (the role's would fail its authentication)",
      ((up.get("vars") or {}).get("forgejo_dump_password"), "-U postgres" in str(dump), str(dump.get("ansible.builtin.shell", {}).get("stdin"))),
      ("{{ postgres_admin_password }}", True, "{{ forgejo_dump_password }}"))
# the inventories
inv = {n: yaml.safe_load(open(f"deploy/ansible/inventory/{n}.yml"))["all"]["vars"] for n in ("production", "vagrant")}
check("production: each password from .env, its own key", (inv["production"].get("forgejo_db_password"), inv["production"].get("keycloak_db_password")),
      ("{{ lookup('env', 'FORGEJO_DB_ROLE_PASSWORD') }}", "{{ lookup('env', 'KEYCLOAK_DB_ROLE_PASSWORD') }}"))
v = inv["vagrant"]
check("the copy: each password its own, none the superuser's", bool(v.get("forgejo_db_password")) and bool(v.get("keycloak_db_password"))
      and len({v.get("forgejo_db_password"), v.get("keycloak_db_password"), v.get("postgres_admin_password")}) == 3, True)
# the password reaching psql: rendered as Ansible renders it, read back as psql reads a single-quoted \set value
own = yaml.safe_load(open(f"{PB}/tasks/app-db-owner.yml"))
t = next(x for x in own if x.get("name") == "Forgejo's and Keycloak's roles own their databases")
roles = next(x for x in own if x.get("name") == "The roles this run gives their databases")["ansible.builtin.set_fact"]["_app_db_roles"]
check("the task's roles by default: Forgejo's and Keycloak's, each with its own password",
      ("{'app': 'forgejo', 'pw': forgejo_db_password" in roles, "{'app': 'keycloak', 'pw': keycloak_db_password" in roles), (True, True))
sh_ = t["ansible.builtin.shell"]
check("  psql stops at the first error (no ON_ERROR_STOP: an ERROR then exit 0 - the leftover check never fails it)",
      "-v ON_ERROR_STOP=1" in sh_["cmd"], True)
judged = next(x for x in own if x.get("name") == "Each role owns its database (psql's error otherwise)")["ansible.builtin.assert"]
check("  each role's exit judged, its error shown with the password masked",
      (judged["that"], "replace(r.item.pw, '<the password>')" in judged["fail_msg"]),
      ("_app_db_owner.results | rejectattr('rc', 'equalto', 0) | list | length == 0", True))
check("  as postgres, each table waited for 3 s at most (lock_timeout survives the \\connect), tried again on a failure",
      (t.get("become_user"), (t.get("environment") or {}).get("PGOPTIONS"), t.get("until"), t.get("retries")),
      ("postgres", "-c lock_timeout=3s", "_app_db_owner.rc == 0", 10))
check("  the password on stdin alone; psql given a SCRAM verifier of it from its environment (\\getenv) - none in SQL text",
      (sh_["stdin"], "\\getenv pw APP_PW_VERIFIER" in sh_["cmd"], "item.pw" in sh_["cmd"], t.get("no_log")),
      ("{{ item.pw }}", True, False, True))
# the verifier the task's own Python makes: a valid SCRAM-SHA-256 verifier of the password it read (a client's keys,
# computed from the password, check against it as Postgres checks them)
import base64, hashlib, hmac, subprocess
code = re.search(r"python3 -c '(.*?)'\)", sh_["cmd"], re.S).group(1)
pw = "a'b\\c d$e`f\"g"
out = subprocess.run(["python3", "-c", code], input=pw + "\n", capture_output=True, text=True).stdout.strip()
m = re.fullmatch(r"SCRAM-SHA-256\$4096:([^$]+)\$([^:]+):(.+)", out)
salt = base64.b64decode(m.group(1)) if m else b""
salted = hashlib.pbkdf2_hmac("sha256", pw.encode(), salt, 4096)
check("  the verifier: SCRAM-SHA-256 of the password it read, a client's keys checking against it",
      bool(m) and base64.b64decode(m.group(2)) == hashlib.sha256(hmac.new(salted, b"Client Key", hashlib.sha256).digest()).digest()
      and base64.b64decode(m.group(3)) == hmac.new(salted, b"Server Key", hashlib.sha256).digest(), True)
sql = open(f"{PB}/files/app-db-owner.sql").read()
check("the SQL quotes the verifier for Postgres (format %L), never interpolates it raw",
      ("PASSWORD %L', :'app', :'pw')" in sql, re.findall(r":pw\b", sql)), (True, []))
check("  and fails when anything is left to another role", "NOT ALL OWNED" in sql and "SELECT 1/0" in sql, True)
copy = open("tests/ansible/copy/forgejo-check.yml").read()
check("the copy: the task run on a probe database of every kind of object (its own file), its role's work proven",
      ("app_db_roles: [{app: ownerprobe" in copy, "app-db-owner-probe.sql" in copy, "CREATE TYPE comp AS" in open("tests/ansible/copy/files/app-db-owner-probe.sql").read()),
      (True, True, True))
tf = open("Taskfile.yml").read()
check("  a wrong password for each refused on the copy (tests/ansible/copy/db-login-refused.sh), before the check reads it",
      0 < tf.find("tests/ansible/copy/db-login-refused.sh") < tf.find("tests/ansible/copy/forgejo-check.yml"), True)
print(f"app-db-owner: {'ALL-PASS' if not fails else f'{fails} FAILED'}")
sys.exit(1 if fails else 0)
PYCHECK
