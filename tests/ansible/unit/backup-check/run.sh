#!/bin/bash
# tests/ansible/copy/backup-check.yml's three judgments, each task's shell and environment rendered by Ansible's
# templar as the playbook holds them and run against a kubectl stub:
#   - the schedule's resource policy read as Velero reads it - no policy skips nothing; production's (the ephemeral
#     types, infra clusters/production/velero/values.yaml) read whole; a quote in the ConfigMap read, not run; refused:
#     a ConfigMap of two keys, a version but v1, a condition but volumeTypes, an action but skip;
#   - the volumes the backup must hold: each running pod's emptyDirs, minus its backup-volumes-excludes - all of them
#     "skipped" when the policy skips emptyDir;
#   - the verdict: every expected volume Completed (one of a pod gone since not counted), none not Completed, no skipped
#     volume copied, something exercised;
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
# kubectl: `get pods` prints $PODS; `get podvolumebackups` $PVBS; `get pods -A ... uid` $UIDS
with open(f"{W}/bin/kubectl", "w") as f:
    f.write("""#!/bin/bash
case "$*" in
  *" get podvolumebackups.velero.io "*) cat "$PVBS" ;;
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


# --- the policy ---------------------------------------------------------------------------------------------------
POLICY = "The volume types the policy skips"
PRODUCTION = """version: v1
volumePolicies:
  - conditions:
      volumeTypes: [emptyDir, configMap, secret, projected, downwardAPI]
    action:
      type: skip
"""


def cm(data, **meta):
    return {"stdout": json.dumps({"kind": "ConfigMap", "metadata": {"name": "p", **meta}, "data": data})}


check("no resource policy (its read skipped): nothing skipped", run(POLICY, _policy_cm={"skipped": True})[:2], (0, "[]"))
check("production's policy: the ephemeral types skipped", run(POLICY, _policy_cm=cm({"policy.yaml": PRODUCTION}))[:2],
      (0, json.dumps(sorted(["emptyDir", "configMap", "secret", "projected", "downwardAPI"]))))
check("a quote in the ConfigMap (an annotation's): read, not run",
      run(POLICY, _policy_cm=cm({"policy.yaml": PRODUCTION}, annotations={"note": "it's'; touch " + W + "/ran; '"}))[:2]
      + (os.path.exists(f"{W}/ran"),),
      (0, json.dumps(sorted(["emptyDir", "configMap", "secret", "projected", "downwardAPI"])), False))
for what, data, says in (
        ("two keys", {"a.yaml": PRODUCTION, "b.yaml": PRODUCTION}, "exactly one key"),
        ("version v2", {"p.yaml": PRODUCTION.replace("v1", "v2")}, "not v1"),
        ("a capacity condition", {"p.yaml": PRODUCTION.replace("volumeTypes: [emptyDir, configMap, secret, projected, downwardAPI]",
                                                               "capacity: '0,1Gi'")}, "does not read"),
        ("volumeTypes beside another condition", {"p.yaml": PRODUCTION.replace(
            "      volumeTypes:", "      capacity: '0,1Gi'\n      volumeTypes:")}, "does not read"),
        ("an fs-backup action", {"p.yaml": PRODUCTION.replace("type: skip", "type: fs-backup")}, "does not read")):
    rc, out, err = run(POLICY, _policy_cm=cm(data))
    check(f"refused: {what}", (rc != 0, says in err, out), (True, True, ""))

# --- the volumes the backup must hold -----------------------------------------------------------------------------
VOLUMES = "The volumes the backup must hold, and those it must skip - the emptyDirs of the pods running now"
SCHEDULE = {"stdout": json.dumps({"spec": {"template": {"includedNamespaces": ["schnappy-production"]}}})}


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
rc, out, err = run(VOLUMES, files={"PODS": PODS}, _schedule=SCHEDULE, _skipped_types={"stdout": "[]"})
check("no emptyDir skipped: each running pod's emptyDirs expected, its excludes not, no other volume type",
      (rc, json.loads(out or "{}")), (0, {"expected": [
          {"uid": "u1", "pod": "schnappy-production/valkey-0", "volume": "data"},
          {"uid": "u2", "pod": "schnappy-production/valkey-1", "volume": "data"}], "skipped": []}))
rc, out, err = run(VOLUMES, files={"PODS": PODS}, _schedule=SCHEDULE,
                   _skipped_types={"stdout": json.dumps(["configMap", "emptyDir"])})
check("emptyDir skipped by the policy: the same volumes listed as skipped, none expected",
      (rc, [v["volume"] for v in json.loads(out or "{}").get("expected", ["?"])],
       [v["pod"] + ":" + v["volume"] for v in json.loads(out or "{}").get("skipped", [])]),
      (0, [], ["schnappy-production/valkey-0:data", "schnappy-production/valkey-1:data"]))

# --- the verdict --------------------------------------------------------------------------------------------------
VERDICT = "Every expected volume backed up and Completed, no skipped one copied, something exercised"
CREATED = {"result": {"metadata": {"name": "upgrade-check-1"}}}
E1 = {"uid": "u1", "pod": "schnappy-production/valkey-0", "volume": "data"}
E2 = {"uid": "u2", "pod": "schnappy-production/valkey-1", "volume": "data"}


def pvb(name, volume, phase):
    return {"spec": {"pod": {"namespace": "schnappy-production", "name": name}, "volume": volume},
            "status": {"phase": phase}}


def verdict(expected, skipped, pvbs, alive="u1 u2"):
    rc, out, err = run(VERDICT, files={"PVBS": json.dumps({"items": pvbs}), "UIDS": alive}, _created=CREATED,
                       _expected_volumes={"stdout": json.dumps({"expected": expected, "skipped": skipped})})
    return rc, out


both = [pvb("valkey-0", "data", "Completed"), pvb("valkey-1", "data", "Completed")]
check("every expected volume Completed: passed", verdict([E1, E2], [], both)[0], 0)
rc, out = verdict([E1, E2], [], both[:1])
check("one expected volume of a running pod not backed up: failed, named", (rc, "valkey-1:data" in out), (1, True))
check("  its pod gone since: not counted", verdict([E1, E2], [], both[:1], alive="u1")[0], 0)
# not Completed, of a volume nothing expected (its pod gone since the list): failed on its own, not as a missing one
rc, out = verdict([E1], [], [both[0], pvb("valkey-1", "data", "Failed")], alive="u1")
check("a volume backup not Completed: failed, named", (rc, "data Failed" in out, "missing -" in out), (1, True, True))
rc, out = verdict([], [E1, E2], [both[0]])
check("a volume the policy skips copied all the same: failed, named", (rc, "copied though skipped" in out
                                                                       and "valkey-0:data" in out), (1, True))
check("every volume skipped, none copied: passed", verdict([], [E1, E2], [])[0], 0)
check("nothing expected and nothing skipped (no emptyDir at all): failed - nothing exercised", verdict([], [], [])[0], 1)

# --- the kopia epoch job: only when a volume was copied -----------------------------------------------------------
EPOCH = ts["The test repository closes its index epochs hourly"]
check("the epoch job runs when a volume is expected, not when every one is skipped",
      [condition(EPOCH["when"], _expected_volumes={"stdout": json.dumps(v)})
       for v in ({"expected": [E1], "skipped": []}, {"expected": [], "skipped": [E1]})], [True, False])
print("backup-check: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_BACKUP_CHECK
