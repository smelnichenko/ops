#!/bin/bash
# wave0-rehearsal.yml's guards before it deletes or writes on the node, each shell block run as the playbook holds it
# (rendered with Jinja, kubectl a stub) and every tool that changes files FENCED - find, tar, cp, rm, du, chown, mv log
# their call and exit 99, so nothing here touches this machine even when a guard is broken. Under `set -e` a test that
# fails inside an && list stops nothing unless it is the last one; each guard must stop the block itself:
#   Kafka's volume      "/" or no such directory: refused before find -delete; a real directory: find called
#   gateway's volumes   "/", no such directory or an empty archive refused before find -delete; a real directory
#                       with its archive: find called
#   etcd's data path    no hostPath, "/" (or no pod, or no mount) refused before the snapshot is copied; all three:
#                       cp called
#   the Postgres dumps  production's own cluster's dump among them, or the task fails (its failed_when, as Ansible
#                       evaluates it, with the play's names)
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import jinja2, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import jinja2, yaml' || { echo "wave0-guards: no python3 with jinja2 and yaml (PATH, repo venv)"; exit 2; }
# the playbook as Ansible loads it first: a free-form shell block it cannot split (a quote in a comment) never runs
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
"$AP" --syntax-check -i localhost, tests/ansible/upgrade/wave0-rehearsal.yml > /dev/null 2>&1 \
  || { echo "FAIL tests/ansible/upgrade/wave0-rehearsal.yml does not load:"; "$AP" --syntax-check -i localhost, tests/ansible/upgrade/wave0-rehearsal.yml 2>&1 | grep -A2 ERROR; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin" "$W/vol" "$W/work"
for t in find tar cp rm du chown mv; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/fenced.log"\nexit 99\n' "$t" "$W" > "$W/bin/$t"
done
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/sh
case "$*" in
  *"-l component=etcd"*) printf '%s' "${POD-}" ;;
  *hostPath.path*) printf '%s' "${HOST-}" ;;
  *mountPath*) printf '%s' "${MOUNT-}" ;;
  *"get pod kafka-0"*) printf '%s' "Pending/" ;;
esac
STUB
chmod +x "$W"/bin/*
echo data > "$W/work/pvc1.tar.gz"
: > "$W/work/pvc2.tar.gz"  # an archive the backup left empty
W=$W "$PY" - <<'PY'
import os, subprocess, sys
import jinja2, yaml
W = os.environ["W"]
tasks = {}
def walk(items):
    for t in items:
        tasks[t.get("name")] = t
        walk(t.get("block", []) + t.get("always", []) + t.get("rescue", []))
play = yaml.safe_load(open("tests/ansible/upgrade/wave0-rehearsal.yml"))[0]
walk(play["tasks"])
fails = 0
def run(task, env=None, **ctx):
    cmd = tasks[task]["ansible.builtin.shell"]["cmd"]
    ctx = dict(kubectl=os.path.join(W, "bin", "kubectl"), work_dir=os.path.join(W, "work"), **ctx)
    script = jinja2.Environment(undefined=jinja2.StrictUndefined).from_string(cmd).render(**ctx)
    log = os.path.join(W, "fenced.log")
    if os.path.exists(log):
        os.remove(log)
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], **(env or {})))
    fenced = open(log).read() if os.path.exists(log) else ""
    return r.returncode, r.stdout + r.stderr, fenced
def case(name, got, want):
    global fails
    fails += not got
    print(f"{'PASS' if got else 'FAIL'} {name}" + ("" if got else f"\n  {want}"))
KAFKA = "Kafka - the volume's content replaced by the backup's"
for d, label in (("/", "/"), (os.path.join(W, "nope"), "no such directory")):
    rc, out, fenced = run(KAFKA, _broker={"stdout": f"kafka-0 {d}"}, _kafka_node={"stdout": "n"})
    case(f"Kafka's volume {label}: refused, nothing deleted", rc != 0 and not fenced, f"rc {rc}, fenced: {fenced!r}")
rc, out, fenced = run(KAFKA, _broker={"stdout": f"kafka-0 {W}/vol"}, _kafka_node={"stdout": "n"})
case("Kafka's volume a directory: find called", fenced.startswith(f"find {W}/vol -mindepth 1 -delete"), repr(fenced))
GW = "Gateway - each volume's content replaced by the backup's, extended attributes too"
rc, out, fenced = run(GW, _gw={"stdout": "pvc1 /"})
case("gateway volume /: refused, nothing deleted", rc != 0 and not fenced, f"rc {rc}, fenced: {fenced!r}")
rc, out, fenced = run(GW, _gw={"stdout": f"pvc2 {W}/vol"})
case("gateway volume whose archive is empty: refused, nothing deleted", rc != 0 and not fenced,
     f"rc {rc}, fenced: {fenced!r}")
rc, out, fenced = run(GW, _gw={"stdout": f"pvc1 {W}/nope"})
case("gateway volume no such directory: refused, nothing deleted", rc != 0 and not fenced,
     f"rc {rc}, fenced: {fenced!r}")
rc, out, fenced = run(GW, _gw={"stdout": f"pvc1 {W}/vol"})
case("gateway volume a directory with its archive: find called", fenced.startswith(f"find {W}/vol -mindepth 1"),
     repr(fenced))
ETCD = "Etcd - the static pod's etcdutl restores it"
good = {"POD": "etcd-x", "HOST": f"{W}/vol", "MOUNT": "/var/lib/etcd"}
for missing in ("POD", "HOST", "MOUNT"):
    rc, out, fenced = run(ETCD, env=dict(good, **{missing: ""}))
    case(f"etcd without its {missing.lower()}: refused, nothing copied", rc != 0 and not fenced and "etcd" in out,
         f"rc {rc}, fenced: {fenced!r}, out: {out.strip()[-200:]}")
rc, out, fenced = run(ETCD, env=dict(good, HOST="/"))
case("etcd's data hostPath /: refused, nothing copied", rc != 0 and not fenced, f"rc {rc}, fenced: {fenced!r}")
rc, out, fenced = run(ETCD, env=good)
case("etcd with pod, hostPath and mount: the snapshot copied", fenced.startswith("cp "), repr(fenced))
ansible_env = jinja2.Environment()
ansible_env.filters["basename"] = os.path.basename  # Ansible's own basename filter
DUMPS = ansible_env.compile_expression(tasks["Postgres - the dumps of the backup"]["failed_when"])
dumps = lambda *names: bool(DUMPS(_dumps={"files": [{"path": "/b/" + n} for n in names]}, **{
    k: play["vars"][k] for k in ("pg_namespace", "pg_cluster")}))
case("the dumps: production's among them - goes on",
     not dumps("schnappy-production-schnappy-production-postgres.sql.gz", "schnappy-test-schnappy-test-postgres.sql.gz"),
     "failed")
case("the dumps: only the test environment's - fails", dumps("schnappy-test-schnappy-test-postgres.sql.gz"), "went on")
case("the dumps: none - fails", dumps(), "went on")
print("wave0-guards: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
