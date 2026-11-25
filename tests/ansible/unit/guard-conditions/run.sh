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
# E06: the data tier waited for one workload at a time - each restarted, then off the old sidecar AND ready, in a
# bounded loop that stops the run before the apps (its behaviour: restart-mesh-order's one-at-a-time, slow and
# never-ready cases - the wait gone there, 10 checks red)
dl = next(t for t in tasks("deploy/ansible/playbooks/restart-mesh-workloads.yml") if t.get("register") == "_data")
cmd = dl["ansible.builtin.shell"]["cmd"]
check("E06 the data tier's loop: off the old sidecar and ready before the next, bounded, failing before the apps",
      [x for x in ('grep -qx "$kind $ns $name" <<< "$left"', '[ "$(ready "$kind" "$ns" "$name")" = True ]',
                   '[ "$n" -lt {{ data_tries }} ]', 'the apps not restarted"; exit 1') if x not in cmd], [])
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
# G04: the storage check's second pod reading something else than the marker fails it
rr = next(t for t in tasks("tests/ansible/copy/storage-check.yml") if t.get("register") == "_reread")
check("G04 the volume read back as written: on; another content or a pod not Succeeded: failed",
      (condition(rr["failed_when"], _reread={"stdout_lines": ["Succeeded", "m1"]}, marker="m1"),
       condition(rr["failed_when"], _reread={"stdout_lines": ["Succeeded", "other"]}, marker="m1"),
       condition(rr["failed_when"], _reread={"stdout_lines": ["Failed", "m1"]}, marker="m1")), (False, True, True))
# G05: the restore never recovers into the cluster it reads from
rc_ = task("tests/ansible/copy/restore-check.yml", "Its names are the fixed ones")["ansible.builtin.assert"]["that"]
ok_names = dict(recovered="upgrade-restore-check", _backup="upgrade-restore-check-1", cluster="schnappy-production-postgres")
check("G05 a side cluster of its own: on; recovering into the cluster itself: refused",
      (condition(rc_, **ok_names), condition(rc_, **dict(ok_names, cluster="upgrade-restore-check"))), (True, False))
# L01: every Postgres instance holding exactly the seeded rows
rows_t = next(t for t in tasks("tests/ansible/copy/data-check.yml") if t.get("register") == "_rows")
seeded = dict(rows=1000, expected_md5="abc")
check("L01 the seeded rows: done, on; another count or checksum: not done, failed",
      (condition(rows_t["until"], _rows={"stdout": "1000 abc\n"}, **seeded),
       condition(rows_t["failed_when"], _rows={"stdout": "1000 abc"}, **seeded),
       condition(rows_t["until"], _rows={"stdout": "999 abc"}, **seeded),
       condition(rows_t["failed_when"], _rows={"stdout": "1000 abd"}, **seeded)), (True, False, False, True))
# L02: ClickHouse's canary rows, compatibility and users as seeded
ch = next(t for t in tasks("tests/ansible/copy/survival-check.yml") if t.get("register") == "_ch")
def survival(lines):
    v = dict(rows=50, expected_md5="def", clickhouse_compat="", clickhouse_users="default,schnappy",
             clickhouse_format_pins={}, _ch={"rc": 0, "stdout_lines": lines})
    for n in ("_pins", "_formats", "_newer"):
        v[n] = as_loaded(render(ch["vars"][n], **v))
    return condition(ch["failed_when"], **v)
good = ["50 def", "compat= 24.8.14", "users=default,schnappy", "formats="]
check("L02 the canary as seeded: on; another count, checksum or user list: failed",
      (survival(good), survival(["49 def"] + good[1:]), survival(["50 deg"] + good[1:]),
       survival(good[:2] + ["users=default"] + good[3:])), (False, True, True, True))
# L03: Grafana's dashboards as seeded - or, its database moved since the seed, the canary gone and the rest there again
gf = next(t for t in tasks("tests/ansible/copy/survival-check.yml") if t.get("register") == "_grafana")
UIDS = ["infrastructure", "masi", "upgrade-check"]
def grafana(mode, uids, canary, db, seed_db="sqlite3"):
    import json
    v = dict(mode=mode, dashboard_uid="upgrade-check", dashboard_text="upgrade survival canary",
             _seed={"grafana_uids": UIDS, "grafana_db": seed_db},
             _grafana={"rc": 0, "stdout_lines": [json.dumps(uids), canary, db][:3 if db else 2]})
    # the task's vars as Ansible holds them: trusted templates, rendered only when read (lazily - the length clause
    # first, so two lines never reach the third)
    v.update(as_loaded(gf.get("vars") or {}))
    return condition(gf["failed_when"], **v)
C = "upgrade survival canary"
check("L03 the seed, its canary read: on; the same database after a change, every UID and the canary: on",
      (grafana("seed", UIDS, C, "sqlite3"), grafana("verify", UIDS, C, "sqlite3")), (False, False))
check("L03 the same database: the canary gone, or another dashboard gone: failed",
      (grafana("verify", UIDS[:2], "-", "sqlite3"), grafana("verify", UIDS[1:], C, "sqlite3")), (True, True))
check("L03 moved to another database: the canary gone, every other dashboard there again: on",
      grafana("verify", UIDS[:2], "-", "postgres"), False)
check("L03 moved: the canary still there (the old database read), or another dashboard lost with the old one: failed",
      (grafana("verify", UIDS, C, "postgres"), grafana("verify", ["masi"], "-", "postgres")), (True, True))
check("L03 seeded on Postgres (a copy built after the move), still there: every UID and the canary: on",
      grafana("verify", UIDS, C, "postgres", seed_db="postgres"), False)
check("L03 the database not said (two lines): failed", grafana("verify", UIDS, C, ""), True)
# L04/L05: Grafana's datasources - each the chart provisions there and healthy, in the copy's check and production's (the
# observability review, 2026-11-25: a check of only what Grafana listed passed one a new version failed to register).
# The task's script run as Ansible renders it, kubectl a stub answering Grafana's API
import subprocess, tempfile
STUB = """#!/bin/bash
cat > /dev/null
q="${@: -1}"
case $q in
  /api/datasources) python3 -c 'import json, os; print(json.dumps([{"uid": u} for u in os.environ["LISTED"].split()]))' ;;
  */health) u=${q#/api/datasources/uid/}; u=${u%/health}
    case " $BAD " in *" $u "*) echo '{"status": "ERROR"}' ;; *) echo '{"status": "OK"}' ;; esac ;;
esac
"""
CM = "apiVersion: 1\ndeleteDatasources:\n  - name: Prometheus\ndatasources:\n  - name: Mimir\n    uid: prometheus\n  - name: ClickHouse-Logs\n    uid: clickhouse-logs\n  - name: Tempo\n    uid: tempo\n"
def datasources(path, listed, bad=()):
    t = task(path, "Grafana - every datasource healthy")
    d = tempfile.mkdtemp()
    stub = os.path.join(d, "kubectl")
    open(stub, "w").write(STUB)
    os.chmod(stub, 0o755)
    prov = (t.get("environment") or {}).get("PROVISIONED")
    provisioned = render(prov, _ds_provisioned={"stdout": CM}) if prov else ""
    env = dict(os.environ, LISTED=" ".join(listed), BAD=" ".join(bad), PROVISIONED=provisioned)
    r = subprocess.run(["bash", "-c", render(t["ansible.builtin.shell"]["cmd"], kubectl=stub)], capture_output=True, text=True,
                       env=env, timeout=60)
    lines = r.stdout.splitlines()
    return lines, condition(t["until"], _datasources={"rc": r.returncode, "stdout_lines": lines})
ALL = ["prometheus", "clickhouse-logs", "tempo"]
for path in ("tests/ansible/copy/survival-check.yml", "deploy/ansible/playbooks/production-data-check.yml"):
    name = path.split("/")[-1]
    check(f"L04 {name}: every datasource provisioned listed and healthy: done", datasources(path, ALL),
          (["prometheus OK", "clickhouse-logs OK", "tempo OK"], True))
    check(f"L04 {name}: one provisioned that Grafana does not list: MISSING, not done", datasources(path, ["prometheus", "tempo"]),
          (["prometheus OK", "clickhouse-logs MISSING", "tempo OK"], False))
    check(f"L04 {name}: one listed and unhealthy: not done", datasources(path, ALL, bad=["tempo"])[1], False)
    check(f"L04 {name}: one listed and not provisioned: checked too", datasources(path, ALL + ["extra"])[0][-1], "extra OK")
    rd = task(path, "Grafana - the datasources provisioned")
    check(f"L05 {name}: the provisioned ones read from the ConfigMap; none there, or rc != 0: failed",
          (condition(rd["failed_when"], _ds_provisioned={"rc": 0, "stdout": CM}),
           condition(rd["failed_when"], _ds_provisioned={"rc": 0, "stdout": "apiVersion: 1\ndatasources: []\n"}),
           condition(rd["failed_when"], _ds_provisioned={"rc": 1, "stdout": CM})), (False, True, True))
# L06: the copy's Prometheus reconciled and available AT ITS GENERATION - a condition the old operator left (its
# observedGeneration behind the object's) satisfied the check (the observability review, 2026-11-25)
mc = "tests/ansible/copy/metrics-check.yml"
pr = task(mc, "Prometheus is reconciled by the operator and available")
check("L06 Reconciled and Available at the object's generation: done; either behind it, or either not True: not done",
      tuple(condition(pr["until"], _prom={"stdout": o}) for o in
            ("7/True/7/True/7", "8/True/7/True/8", "8/True/8/True/7", "7/False/7/True/7", "7/True/7/False/7", "True/True")),
      (True, False, False, False, False, False))
# L07: every rule group the PrometheusRule objects define loaded, as many rules, each healthy - the copy read only its
# targets, and with the operator's admission webhooks off a group a new operator or chart drops or breaks went unseen
# (the same review). The task's script run as Ansible renders it, kubectl a stub
PRULES = {"items": [
    {"metadata": {"namespace": "schnappy-infra", "name": "schnappy-alerts", "uid": "11111111-2222-3333-4444-555555555555"},
     "spec": {"groups": [{"name": "infra-a", "rules": [{"alert": "A1"}, {"alert": "A2"}]}, {"name": "infra-b", "rules": [{"alert": "B1"}]}]}},
    {"metadata": {"namespace": "kagent", "name": "kagent-alerts", "uid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"},
     "spec": {"groups": [{"name": "kagent", "rules": [{"alert": "K1"}]}]}}]}
def loaded(drop=(), fewer=(), unhealthy=(), extra=False):
    groups = []
    for r in PRULES["items"]:
        f = "/etc/prometheus/rules/x/%s-%s-%s.yaml" % (r["metadata"]["namespace"], r["metadata"]["name"], r["metadata"]["uid"])
        for g in r["spec"]["groups"]:
            if g["name"] in drop:
                continue
            rules = [{"name": x["alert"], "health": "err" if x["alert"] in unhealthy else "ok", "lastError": "boom"} for x in g["rules"]]
            groups.append({"name": g["name"], "file": f, "rules": rules[:-1] if g["name"] in fewer else rules})
    if extra:
        groups.append({"name": "stray", "file": "/etc/prometheus/rules/x/old-0.yaml", "rules": [{"name": "S", "health": "ok"}]})
    return {"data": {"groups": groups}}
import json as _json
def rules_check(prom_spec=None, **kw):
    t = task(mc, "Every rule group the PrometheusRules define loaded")
    d = tempfile.mkdtemp()
    for n, v in (("prom.json", {"spec": prom_spec if prom_spec is not None else {"ruleSelector": {}, "ruleNamespaceSelector": {}}}),
                 ("prules.json", PRULES), ("rules.json", loaded(**kw))):
        open(os.path.join(d, n), "w").write(_json.dumps(v))
    stub = os.path.join(d, "kubectl")
    open(stub, "w").write("""#!/bin/bash
case " $* " in
  *" get prometheus schnappy-prometheus "*) cat "%s/prom.json" ;;
  *" get prometheusrules "*) cat "%s/prules.json" ;;
  *"/api/v1/rules"*) cat "%s/rules.json" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
""" % (d, d, d))
    os.chmod(stub, 0o755)
    env = dict(os.environ, PATH=d + ":" + os.environ["PATH"])
    r = subprocess.run(["bash", "-c", render(t["ansible.builtin.shell"]["cmd"], kubeconfig="/x", proxy="/p")],
                       capture_output=True, text=True, env=env, timeout=60)
    return r.returncode, r.stdout
rc, out = rules_check()
check("L07 every group defined loaded, as many rules, all healthy: rc 0, the counts said", (rc, "3 groups defined, 3 loaded" in out), (0, True))
check("L07 a group the objects define not loaded: failed, named",
      (lambda r: (r[0] != 0, "NOT LOADED schnappy-infra/schnappy-alerts infra-b" in r[1]))(rules_check(drop=("infra-b",))), (True, True))
check("L07 a group loaded with fewer rules: failed, named",
      (lambda r: (r[0] != 0, "FEWER schnappy-infra/schnappy-alerts infra-a: 1 of 2" in r[1]))(rules_check(fewer=("infra-a",))), (True, True))
check("L07 a rule not healthy: failed, named with its error",
      (lambda r: (r[0] != 0, "UNHEALTHY kagent/kagent-alerts kagent K1: err boom" in r[1]))(rules_check(unhealthy=("K1",))), (True, True))
check("L07 the Prometheus selecting by labels (not every object): refused, said",
      (lambda r: (r[0] != 0, "SELECTORS" in r[1]))(rules_check(prom_spec={"ruleSelector": {"matchLabels": {"a": "b"}}})), (True, True))
check("L07 a group loaded that no object defines (an old file): no failure", rules_check(extra=True)[0], 0)
# K02: argo-sync-app.yml - the application named, and its own sync's end read: the operation started at or after the
# patch, Succeeded (an older operation's result, or a sync Failed, is no success)
asy = "deploy/ansible/playbooks/argo-sync-app.yml"
nm = task(asy, "The application named")["ansible.builtin.assert"]["that"]
check("K02 an application's name: on; one with a space or an option: refused",
      (condition(nm, app="schnappy-production-apps"), condition(nm, app="a b"), condition(nm, app="--all"), condition(nm, app="")),
      (True, False, False, False))
end = task(asy, "Its sync ended Succeeded")
T0 = "2026-11-25T16:30:00Z"
def synced(out):
    v = dict(_st={"rc": 0, "stdout": out}, _t0={"stdout": T0})
    return condition(end["until"], **v), condition(end["failed_when"], **v)
check("K02 its sync Succeeded after the patch: done, passed; Failed after it: done, failed",
      (synced("Succeeded|2026-11-25T16:30:05Z|successfully synced"), synced("Failed|2026-11-25T16:31:00Z|hook k6 failed")),
      ((True, False), (True, True)))
check("K02 an older operation's Succeeded (before the patch), or one still Running: not done",
      (synced("Succeeded|2026-11-25T16:00:00Z|old")[0], synced("Running|2026-11-25T16:30:05Z|")[0]), (False, False))
print("guard-conditions: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_GUARD_CONDITIONS
