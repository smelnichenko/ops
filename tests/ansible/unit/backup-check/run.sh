#!/bin/bash
# tests/ansible/copy/backup-check.yml's judgments, each task as Ansible renders it from the playbook, the shells run
# against a kubectl stub:
#   - whether the schedule leaves pods out (excludedResources: pods - production's since 2026-11-13): read from its
#     template, nothing assumed;
#   - the backup started: the schedule's template, 1 h to live; narrowed to one workload only where it copies volumes
#     (pods left out: the whole namespace, manifests only);
#   - the volumes it must hold where pods are backed up: each running selected pod's emptyDirs, minus its
#     backup-volumes-excludes; not asked where pods are left out;
#   - the verdict: pods left out - no volume backup at all, something backed up; pods backed up - every expected volume
#     Completed (one of a pod gone since not counted), none not Completed, at least one expected; either way an empty
#     backup fails;
# and the kopia epoch job only when a volume was copied.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY_BACKUP_CHECK'
import atexit, json, os, shutil, subprocess, sys, tempfile
sys.path.insert(0, "tests/ansible/unit")
from plays import load, tasks  # noqa: E402
from templar import as_loaded, condition, render  # noqa: E402
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


F = "tests/ansible/copy/backup-check.yml"
play = load(F)[0]
ts = {t.get("name"): t for t in tasks(load(F))}
pv = play["vars"]
W = tempfile.mkdtemp()
atexit.register(shutil.rmtree, W, True)
os.makedirs(f"{W}/bin")
# kubectl: `get pods` prints $PODS; `get podvolumebackups` $PVBS; `get pods -A ... uid` $UIDS; the backup's items $ITEMS
with open(f"{W}/bin/kubectl", "w") as f:
    f.write("""#!/bin/bash
case "$*" in
  *" get podvolumebackups.velero.io "*) cat "$PVBS" ;;
  *" get backups.velero.io "*itemsBackedUp*) cat "$ITEMS" ;;
  *" get pods -A "*) cat "$UIDS" ;;
  *" get pods "*) cat "$PODS" ;;
  *) echo "kubectl stub: $*" >&2; exit 9 ;;
esac
""")
os.chmod(f"{W}/bin/kubectl", 0o755)


def run(name, files=None, **variables):
    """The task's shell and environment as Ansible renders them, run with the stub first on PATH: (rc, stdout, stderr)."""
    t = ts[name]
    variables = {**as_loaded(pv), **variables}
    variables["kubectl"] = render(pv["kubectl"], **variables)
    cmd = render(t["ansible.builtin.shell"]["cmd"], **variables)
    env = {k: str(render(v, **variables)) for k, v in (t.get("environment") or {}).items()}
    for k, text in (files or {}).items():
        open(f"{W}/{k}", "w").write(text)
        env[k] = f"{W}/{k}"
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True,
                       env={**os.environ, **env, "PATH": f"{W}/bin:" + os.environ["PATH"]})
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def schedule(**template):
    return {"stdout": json.dumps({"spec": {"template": {"includedNamespaces": ["schnappy-production"], **template}}})}


PODS_OUT = schedule(excludedResources=["pods"], defaultVolumesToFsBackup=False)
PODS_IN = schedule(defaultVolumesToFsBackup=True)

# --- what the schedule leaves out ---------------------------------------------------------------------------------
fact = ts["Whether the schedule leaves pods out - then no volume is read at all"]["ansible.builtin.set_fact"]["_pods_out"]
check("pods left out read from the schedule's template: pods excluded (either field) yes; none excluded, or others only, no",
      [str(render(fact, _schedule=s)).strip() for s in (PODS_OUT, schedule(excludedNamespaceScopedResources=["pods"]),
                                                       PODS_IN, schedule(excludedResources=["events"]))],
      ["True", "True", "False", "False"])
# a cluster-wide schedule (the weekly: namespaces "*") is checked only with pods left out
WIDE = ts["A cluster-wide schedule is checked only with pods left out"]["ansible.builtin.assert"]["that"]
wide = lambda **t: {"stdout": json.dumps({"spec": {"template": {"includedNamespaces": ["*"], **t}}})}
check("a cluster-wide schedule: passed with pods left out, refused backing up pods; a namespaced one either way",
      [condition(WIDE, _schedule=sc, _pods_out=o) for sc, o in ((wide(excludedResources=["pods"]), True), (wide(), False),
                                                                (PODS_IN, False))],
      [True, False, True])

# --- the backup started -------------------------------------------------------------------------------------------
start = ts["Start a backup from it"]["kubernetes.core.k8s"]["definition"]["spec"]
sel = pv["backup_selector"]
check("the backup: the schedule's template, 1 h to live; narrowed to one workload only where volumes are copied",
      [render(start, _schedule=s, _pods_out=o, backup_selector=sel) for s, o in ((PODS_OUT, True), (PODS_IN, False))],
      [{**json.loads(PODS_OUT["stdout"])["spec"]["template"], "ttl": "1h"},
       {**json.loads(PODS_IN["stdout"])["spec"]["template"], "ttl": "1h", "labelSelector": {"matchLabels": sel}}])

# --- the volumes the backup must hold (pods backed up) ------------------------------------------------------------
VOLUMES = "The volumes the backup must hold - the emptyDirs of the pods running now"
check("the volumes not asked where pods are left out", [condition(ts[VOLUMES]["when"], _pods_out=o) for o in (True, False)],
      [False, True])


def pod(uid, name, volumes, excludes=None):
    meta = {"uid": uid, "namespace": "schnappy-production", "name": name}
    if excludes:
        meta["annotations"] = {"backup.velero.io/backup-volumes-excludes": excludes}
    return {"metadata": meta, "spec": {"volumes": volumes}}


PODS = json.dumps({"items": [
    pod("u1", "valkey-0", [{"name": "data", "emptyDir": {}}, {"name": "tmp", "emptyDir": {}},
                           {"name": "conf", "configMap": {"name": "c"}}, {"name": "pvc", "persistentVolumeClaim": {}}],
        excludes="tmp"),
    pod("u2", "valkey-1", [{"name": "data", "emptyDir": {}}])]})
rc, out, err = run(VOLUMES, files={"PODS": PODS}, _schedule=PODS_IN)
check("pods backed up: each running pod's emptyDirs expected, its excludes not, no other volume type",
      (rc, json.loads(out or "{}")), (0, {"expected": [
          {"uid": "u1", "pod": "schnappy-production/valkey-0", "volume": "data"},
          {"uid": "u2", "pod": "schnappy-production/valkey-1", "volume": "data"}]}))

# --- the verdict --------------------------------------------------------------------------------------------------
VERDICT = "Every expected volume backed up and Completed - none at all where pods are left out - and something backed up"
CREATED = {"result": {"metadata": {"name": "upgrade-check-1"}}}
E1 = {"uid": "u1", "pod": "schnappy-production/valkey-0", "volume": "data"}
E2 = {"uid": "u2", "pod": "schnappy-production/valkey-1", "volume": "data"}


def pvb(name, volume, phase):
    return {"spec": {"pod": {"namespace": "schnappy-production", "name": name}, "volume": volume},
            "status": {"phase": phase}}


def verdict(pods_out, expected, pvbs, alive="u1 u2", items="120", skipped_task=False):
    exp = {"skipped": True} if skipped_task else {"stdout": json.dumps({"expected": expected})}
    rc, out, err = run(VERDICT, files={"PVBS": json.dumps({"items": pvbs}), "UIDS": alive, "ITEMS": items},
                       _created=CREATED, _pods_out=pods_out, _expected_volumes=exp)
    return rc, out


both = [pvb("valkey-0", "data", "Completed"), pvb("valkey-1", "data", "Completed")]
check("pods left out (the volumes task skipped), no volume backup, items backed up: passed",
      verdict(True, [], [], skipped_task=True)[0], 0)
rc, out = verdict(True, [], [both[0]], skipped_task=True)
check("  a volume backup though pods are left out: failed, named", (rc, "valkey-0:data" in out), (1, True))
check("  nothing backed up (no item): failed", verdict(True, [], [], items="0", skipped_task=True)[0], 1)
check("pods backed up, every expected volume Completed: passed", verdict(False, [E1, E2], both)[0], 0)
rc, out = verdict(False, [E1, E2], both[:1])
check("  one expected volume of a running pod not backed up: failed, named", (rc, "valkey-1:data" in out), (1, True))
check("    its pod gone since: not counted", verdict(False, [E1, E2], both[:1], alive="u1")[0], 0)
# not Completed, of a volume nothing expected (its pod gone since the list): failed on its own, not as a missing one
rc, out = verdict(False, [E1], [both[0], pvb("valkey-1", "data", "Failed")], alive="u1")
check("  a volume backup not Completed: failed, named", (rc, "data Failed" in out, "missing -" in out), (1, True, True))
check("  no emptyDir among the selected pods (nothing exercised): failed", verdict(False, [], [])[0], 1)
check("  nothing backed up (no item): failed", verdict(False, [E1, E2], both, items="0")[0], 1)

# --- the kopia epoch job: only when a volume was copied -----------------------------------------------------------
EPOCH = ts["The test repository closes its index epochs hourly"]
check("the epoch job runs when a volume is expected - not when none is, nor where pods are left out (its task skipped)",
      [condition(EPOCH["when"], _expected_volumes=v) for v in
       ({"stdout": json.dumps({"expected": [E1]})}, {"stdout": json.dumps({"expected": []})}, {"skipped": True})],
      [True, False, False])
print("backup-check: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_BACKUP_CHECK
