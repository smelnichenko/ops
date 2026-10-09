#!/bin/bash
# Guards no live run can make fail, their conditions evaluated as Ansible templates them (tests/ansible/unit/templar.py):
# the Vagrant-only guard (a production address refused, under any --tags), postgres-analyze's cluster list and major,
# PgBouncer installed but not running, restart-mesh's unknown owner, Cilium's live config against its render, local-path's
# hand-set paths, no kubelet downgrade.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=$(command -v python3)
"$PY" -c 'import yaml, jinja2' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - "$PWD" <<'PY_GUARD_CONDITIONS'
import os, sys
import yaml
ops = sys.argv[1]
sys.path.insert(0, os.path.join(ops, "tests", "ansible", "unit"))
from templar import condition, render, as_loaded
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def walk(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always", "tasks", "pre_tasks", "post_tasks"):
            yield from walk(t.get(k))
def tasks(path):
    doc = yaml.safe_load(open(os.path.join(ops, path)))
    return list(walk(doc))
def task(path, prefix):
    return next(t for t in tasks(path) if str(t.get("name", "")).startswith(prefix))
# D01/D02: the Vagrant guard
vo = tasks("tests/ansible/vagrant-only.yml")
that = vo[1]["ansible.builtin.assert"]["that"]
ok = lambda addrs: condition(that, _vagrant_only_addresses={"stdout": addrs})
check("D01 a Vagrant VM passes", ok("192.168.56.10 10.0.2.15"), True)
check("D01 a host with a production address refused, Vagrant one or not", (ok("192.168.56.10 192.168.11.2"), ok("192.168.11.2")), (False, False))
check("D02 both guard tasks run under any --tags", [("always" in (t.get("tags") or [])) for t in vo], [True, True])
# E07/E08: postgres-analyze
pa = "deploy/ansible/playbooks/postgres-analyze.yml"
fw = task(pa, "The CNPG clusters")["failed_when"]
check("E07 no cluster in the namespaces given: failed", condition(fw, _clusters={"rc": 0, "stdout_lines": []}, pg_namespaces="schnappy-test"), True)
check("E07 none, the inventory allowing none: not failed", condition(fw, _clusters={"rc": 0, "stdout_lines": []}, pg_namespaces="schnappy-test", postgres_analyze_allow_none=True), False)
until = task(pa, "Each cluster healthy")["until"]
pg = lambda v: {"rc": 0, "stdout_lines": ["True schnappy-production-postgres-1", v]}
check("E08 the old major still running: not done", condition(until, _pg=pg("170006"), pg_major=18), False)
check("E08 the major asked: done", condition(until, _pg=pg("180006"), pg_major=18), True)
# E09: PgBouncer installed, not running
pb = task("deploy/ansible/playbooks/setup-pi-services.yml", "PgBouncer installed here is running")["when"]
st = lambda load, active: {"status": {"LoadState": load, "ActiveState": active}}
check("E09 installed, failed: refused", condition(pb, _pgbouncer_state=st("loaded", "failed")), True)
check("E09 installed, active / not installed: on", (condition(pb, _pgbouncer_state=st("loaded", "active")), condition(pb, _pgbouncer_state=st("not-found", "inactive"))), (False, False))
# E05: restart-mesh - a pod with an old sidecar and no owner it can restart
mesh = task("deploy/ansible/playbooks/restart-mesh-workloads.yml", "Nothing old has an owner")["ansible.builtin.assert"]["that"]
check("E05 a bare pod with an old sidecar: refused", condition(mesh, _stale={"stdout_lines": ["none ns lonely-pod"]}), False)
check("E05 a Deployment's: restartable", condition(mesh, _stale={"stdout_lines": ["Deployment ns app"]}), True)
# E02: Cilium's live config against the render
k = "deploy/ansible/playbooks/setup-kubeadm.yml"
ct = task(k, "The same, key for key")
def cilium(live):
    v = dict(_cilium_rendered={"stdout": "data:\n  a: '1'\n  b: '2'\n"}, _cilium_live={"resources": [{"data": live}]})
    v.update({n: render(x, **v) for n, x in ct["vars"].items() if n != "_differ"})
    v["_differ"] = render(ct["vars"]["_differ"], **v)
    return condition(ct["ansible.builtin.assert"]["that"], **v)
check("E02 the live config as rendered: passes", cilium({"a": "1", "b": "2"}), True)
check("E02 a key set by hand: refused", cilium({"a": "1", "b": "2", "c": "x"}), False)
# E03: local-path's live paths
lp = task(k, "The live local-path node paths")["failed_when"]
paths = [{"node": "DEFAULT_PATH_FOR_NON_LISTED_NODES", "paths": ["/opt/local-path-provisioner"]}]
check("E03 a hand-set path: refused", condition(lp, _lpp_paths_before={"rc": 0, "stdout": '[{"node": "x", "paths": ["/mnt"]}]'}, local_path_node_paths=paths), True)
check("E03 upstream's path / none: on", (condition(lp, _lpp_paths_before={"rc": 0, "stdout": render("{{ p | to_json(sort_keys=True) }}", p=paths)}, local_path_node_paths=paths), condition(lp, _lpp_paths_before={"rc": 0, "stdout": "none"}, local_path_node_paths=paths)), (False, False))
# E01: no-downgrade - kubelet newer than the pin
nd = next(t for t in tasks("deploy/ansible/playbooks/tasks/no-downgrade.yml") if str(t.get("name", "")).startswith("No downgrade - kubelet"))
pk = lambda v: {"kubelet": [{"version": v}], "kubeadm": [{"version": v}], "kubectl": [{"version": v}]}
check("E01 kubelet 1.35.9 under a 1.34.12 pin: refused", condition(nd["ansible.builtin.assert"]["that"], ansible_facts={"packages": pk("1.35.9-1.1")}, item="kubelet", k8s_package_version="1.34.12-1.1"), False)
check("E01 the pinned version: on", condition(nd["ansible.builtin.assert"]["that"], ansible_facts={"packages": pk("1.34.12-1.1")}, item="kubelet", k8s_package_version="1.34.12-1.1"), True)
# E04: containerd's live config differing from the render fails the upgrade
cd = next(t for t in tasks("deploy/ansible/playbooks/upgrade-containerd.yml") if t.get("register") == "_config_diff")
check("E04 the live config differing: failed; the same: on",
      (condition(cd["failed_when"], _config_diff={"rc": 1}), condition(cd["failed_when"], _config_diff={"rc": 0})), (True, False))
# E06: the data tier's sidecars waited for until none is left
dl = next(t for t in tasks("deploy/ansible/playbooks/restart-mesh-workloads.yml") if t.get("register") == "_data_left")
check("E06 a data-tier workload left on the old sidecar: still waiting; none left: done",
      (condition(dl["until"], _data_left={"rc": 0, "stdout": "StatefulSet ns kafka"}),
       condition(dl["until"], _data_left={"rc": 0, "stdout": ""})), (False, True))
# K01: acme-check's certificate not Ready: the task fails (its script run against a kubectl stub)
import subprocess, tempfile
ac = task("deploy/ansible/playbooks/acme-check.yml", "The certificate, Ready")
def acme(ready):
    d = tempfile.mkdtemp()
    open(os.path.join(d, "kubectl"), "w").write("#!/bin/bash\ncat > /dev/null 2>&1 < /dev/null\n"
        'case "$*" in *"wait certificate"*) exit %d ;; esac\nexit 0\n' % (0 if ready else 1))
    os.chmod(os.path.join(d, "kubectl"), 0o755)
    script = render(ac["ansible.builtin.shell"]["cmd"], kubectl="kubectl", check_namespace="ns", check_name="c",
                    check_dns_name="x.example")
    return subprocess.run(["bash", "-c", script], env=dict(os.environ, PATH=d + ":" + os.environ["PATH"]),
                          capture_output=True).returncode
check("K01 the certificate not Ready: the task fails; Ready: passes", (acme(False) != 0, acme(True)), (True, 0))
print("guard-conditions: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_GUARD_CONDITIONS
