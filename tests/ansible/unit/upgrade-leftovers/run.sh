#!/bin/bash
# scripts/upgrade-leftovers.py - the objects a chart release dropped, deleted where Argo leaves them behind - against a
# git fixture for infra (a declared app's chart moved, an undeclared app's too) and ssh/vagrant stubbed (each kubectl
# answered from the case's files, every command recorded): the declared leftovers Argo marks as needing pruning
# deleted, CRDs only with no object of their kind (one with objects, or not read: nothing of the app's deleted), an
# undeclared one left and said, an object still shipped untouched; the wait - spec, comparison, a sync under way, an
# object not yet synced - until Argo runs the head's version, or the time up (nothing deleted); a change moving no
# declared app reads nothing; the copy reached as root with its admin kubeconfig through vagrant ssh, or plain ssh with
# VAGRANT_SSH_CONFIG; production through ssh ten; and the declarations themselves well formed.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
cat > "$W/handle" <<'HANDLE'
#!/bin/bash
# one kubectl command (the last argument), answered from $W and recorded
cmd=${*: -1}
echo "$STUB ${*:1:$#-1} | $cmd" >> "$W/calls"
case "$cmd" in
  *" get application "*)
    name=$(sed -E 's/.* get application ([^ ]+) .*/\1/' <<< "$cmd")
    n=$(cat "$W/looks.$name" 2>/dev/null || echo 0); echo $((n + 1)) > "$W/looks.$name"
    f="$W/app.$name.$n.json"; [ -e "$f" ] || f="$W/app.$name.json"
    [ -e "$f" ] || exit 1; cat "$f" ;;
  *" get "*"--all-namespaces -o name"*)
    crd=$(sed -E 's/.* get ([^ ]+) --all-namespaces.*/\1/' <<< "$cmd")
    [ ! -e "$W/inst.$crd.rc" ] || exit "$(cat "$W/inst.$crd.rc")"
    cat "$W/inst.$crd" 2>/dev/null; exit 0 ;;
  *" delete "*) echo "$cmd" >> "$W/deleted"; exit "$(cat "$W/delete.rc" 2>/dev/null || echo 0)" ;;
  *) exit 3 ;;
esac
HANDLE
chmod +x "$W/handle"
for b in ssh vagrant; do printf '#!/bin/bash\nW=%s STUB=%s exec %s/handle "$@"\n' "$W" "$b" "$W" > "$W/bin/$b"; chmod +x "$W/bin/$b"; done

# infra: base (scylla-operator v1.22.1, another app 1.0), head (v1.23.0, the other 2.0), only-other (the other alone)
I=$W/infra
mkdir -p "$I/clusters/production/argocd/apps"
app() {  # name chart revision
  printf 'apiVersion: argoproj.io/v1alpha1\nkind: Application\nmetadata:\n  name: %s\nspec:\n  sources:\n    - repoURL: https://charts.example\n      chart: %s\n      targetRevision: %s\n    - repoURL: https://git.example/infra.git\n      targetRevision: main\n      ref: values\n' "$1" "$2" "$3"
}
G() { git -C "$I" -c user.name=t -c user.email=t@t "$@" > /dev/null; }
G init -q -b main
app scylla-operator scylla-operator v1.22.1 > "$I/clusters/production/argocd/apps/scylla-operator.yaml"
app other other 1.0 > "$I/clusters/production/argocd/apps/other.yaml"
G add -A; G commit -qm base; G tag base
G checkout -q -b only-other
app other other 2.0 > "$I/clusters/production/argocd/apps/other.yaml"
G commit -qam other
G checkout -q -b head base
app scylla-operator scylla-operator v1.23.0 > "$I/clusters/production/argocd/apps/scylla-operator.yaml"
app other other 2.0 > "$I/clusters/production/argocd/apps/other.yaml"
G commit -qam head
G checkout -q -b removed base
G rm -q clusters/production/argocd/apps/scylla-operator.yaml; G commit -qm removed
# one file, two Applications (infra's kagent.yaml is so): the declared one second
G checkout -q -b multidoc base
G rm -q clusters/production/argocd/apps/scylla-operator.yaml
{ app kagent kagent 1.0; echo '---'; app scylla-operator scylla-operator v1.23.0; } > "$I/clusters/production/argocd/apps/bundle.yaml"
G add -A; G commit -qm multidoc
# main moved on since the unit branched: scylla-operator bumped on main alone
G checkout -q -b main-moved base
app scylla-operator scylla-operator v1.22.2 > "$I/clusters/production/argocd/apps/scylla-operator.yaml"
G commit -qam main-moved
# the declared app as a single-source Application
G checkout -q -b single base
printf 'apiVersion: argoproj.io/v1alpha1\nkind: Application\nmetadata:\n  name: scylla-operator\nspec:\n  source:\n    repoURL: https://charts.example\n    chart: scylla-operator\n    targetRevision: v1.23.0\n' > "$I/clusters/production/argocd/apps/scylla-operator.yaml"
G commit -qam single

W=$W I=$I python3 - <<'PYCHECK'
import json, os, shutil, subprocess
W, I = os.environ["W"], os.environ["I"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))

CRDS = ["scylladbclusters.scylla.scylladb.com", "remotekubernetesclusters.scylla.scylladb.com",
        "remoteowners.scylla.scylladb.com"]
ROLES = ["scylladb:controller:operator-remote", "scylladb:controller:aggregate-to-operator-remote"]
def res(kind, name, group, status="OutOfSync", prune=True, ns=None):
    r = {"group": group, "kind": kind, "name": name, "status": status}
    if prune:
        r["requiresPruning"] = True
    if ns:
        r["namespace"] = ns
    return r
LEFT = [res("CustomResourceDefinition", c, "apiextensions.k8s.io") for c in CRDS] + \
       [res("ClusterRole", r, "rbac.authorization.k8s.io") for r in ROLES]
SHIPPED = res("Deployment", "scylla-operator", "apps", status="Synced", prune=False, ns="scylla-operator")
def sources(rev):
    return [{"repoURL": "https://charts.example", "chart": "scylla-operator", "targetRevision": rev},
            {"repoURL": "https://git.example/infra.git", "targetRevision": "main", "ref": "values"}]
def application(rev="v1.23.0", compared=None, op=None, resources=None, operation=None, synced=None, sync="OutOfSync",
                health="Healthy", conditions=None):
    a = {"metadata": {"name": "scylla-operator"}, "spec": {"sources": sources(rev)},
         "status": {"sync": {"status": sync, "comparedTo": {"sources": sources(compared or rev)},
                             "revisions": [synced or rev, "f" * 40] if synced != [] else []},
                    "health": {"status": health}, "operationState": {"phase": op or "Succeeded"},
                    "resources": [SHIPPED] + (LEFT if resources is None else resources)}}
    if operation:
        a["operation"] = operation
    if conditions:
        a["status"]["conditions"] = conditions
    return a
# Argo after a failed render of the new spec: compared against it, nothing synced at it, sync and every resource Unknown,
# every tracked object marked requiresPruning (the target taken as empty), a ComparisonError
RENDER_FAILED = application(synced=[], sync="Unknown", conditions=[{"type": "ComparisonError", "message": "chart fetch failed"}],
                            resources=[dict(r, status="Unknown") for r in LEFT])
RENDER_FAILED["status"]["resources"] = [dict(SHIPPED, status="Unknown", requiresPruning=True)] + RENDER_FAILED["status"]["resources"][1:]

def run(case, base="base", head="head", on="ten", env=None, minutes="0.05"):
    for f in os.listdir(W):
        if f.startswith(("app.", "looks.", "inst.", "deleted", "calls", "delete.rc")):
            os.remove(os.path.join(W, f))
    for name, body in case.items():
        open(os.path.join(W, name), "w").write(body if isinstance(body, str) else json.dumps(body))
    e = {**os.environ, "PATH": f"{W}/bin:{os.environ['PATH']}", "UPGRADE_LEFTOVERS_INFRA": I, **(env or {})}
    e.pop("VAGRANT_SSH_CONFIG", None) if not (env or {}).get("VAGRANT_SSH_CONFIG") else None
    r = subprocess.run(["python3", "-I", "scripts/upgrade-leftovers.py", "--on", on, "--base", base, "--head", head,
                        "--minutes", minutes, "--poll", "0"], capture_output=True, text=True, env=e, timeout=120)
    read = lambda f: open(os.path.join(W, f)).read().splitlines() if os.path.exists(os.path.join(W, f)) else []
    return r.returncode, r.stdout + r.stderr, read("deleted"), read("calls")

def deleted_names(deleted):
    return [d.split()[3].strip("'") for d in deleted]

# ── the case it is for: every declared leftover deleted, CRDs checked empty first ─────────────────────────────
undeclared = res("ClusterRole", "someone-elses", "rbac.authorization.k8s.io")
rc, out, deleted, calls = run({"app.scylla-operator.json": application(resources=LEFT + [undeclared])})
check("the declared leftovers Argo marks as needing pruning deleted - the three CRDs, then the two ClusterRoles",
      (rc, deleted_names(deleted)), (0, CRDS + ROLES))
check("  each by its group-qualified type, waited for, a missing one no failure",
      deleted[0], "kubectl delete customresourcedefinition.apiextensions.k8s.io " + CRDS[0]
      + " --ignore-not-found --wait=true --timeout=120s")
check("  a ClusterRole's colon-bearing name passed as one word",
      deleted[3], "kubectl delete clusterrole.rbac.authorization.k8s.io " + ROLES[0]
      + " --ignore-not-found --wait=true --timeout=120s")
check("  every CRD's kind read empty, everywhere, before the first delete",
      [c.split(" | ")[1] for c in calls if "--all-namespaces" in c],
      [f"kubectl get {c} --all-namespaces -o name" for c in CRDS])
reads = [i for i, c in enumerate(calls) if "--all-namespaces" in c]
deletes = [i for i, c in enumerate(calls) if " delete " in c]
check("  the reads all came before any delete", bool(reads and deletes) and max(reads) < min(deletes), True)
check("  an undeclared leftover left and said, the object still shipped untouched",
      ("ClusterRole/someone-elses needs pruning but is not declared - left" in out,
       any("someone-elses" in d or "Deployment" in d for d in deleted)), (True, False))
check("  production reached through ssh ten, no prompt",
      calls[0].split(" | ")[0], "ssh -o BatchMode=yes -o ConnectTimeout=15 ten")

# ── a CRD with objects: refused, nothing of the app's deleted ────────────────────────────────────────────────
rc, out, deleted, _ = run({"app.scylla-operator.json": application(),
                           f"inst.{CRDS[1]}": "remotekubernetescluster.scylla.scylladb.com/east\n"})
check("a CRD whose kind still has an object: refused, and nothing deleted - not even the ClusterRoles",
      (rc, deleted, f"REFUSED - {CRDS[1]} still has 1 object(s)" in out), (1, [], True))
rc, out, deleted, _ = run({"app.scylla-operator.json": application(), f"inst.{CRDS[0]}.rc": "1"})
check("a CRD's objects not read: nothing deleted", (rc, deleted, "not read - nothing of scylla-operator's deleted" in out),
      (1, [], True))
rc, out, deleted, _ = run({"app.scylla-operator.json": application(), "delete.rc": "1"})
check("a delete that fails: the run fails at it, said", (rc, len(deleted), "deleting CustomResourceDefinition/" in out),
      (1, 1, True))

# ── only what needs pruning: a declared object the chart still ships stays ───────────────────────────────────
still = [res("CustomResourceDefinition", CRDS[0], "apiextensions.k8s.io", status="Synced", prune=False)] + LEFT[1:]
rc, _, deleted, _ = run({"app.scylla-operator.json": application(resources=still)})
check("a declared object Argo does not mark as needing pruning (still shipped) is not deleted",
      (rc, deleted_names(deleted)), (0, CRDS[1:] + ROLES))
rc, out, deleted, _ = run({"app.scylla-operator.json": application(resources=[])})
check("on its new version with nothing to prune: nothing deleted, said",
      (rc, deleted, "nothing declared left behind" in out), (0, [], True))

# ── the wait: Argo on the head's version first ───────────────────────────────────────────────────────────────
NOT_SYNCED = [res("Service", "webhook", "", prune=False, ns="scylla-operator")] + LEFT
rc, out, deleted, calls = run({"app.scylla-operator.0.json": application(rev="v1.22.1"),
                               "app.scylla-operator.1.json": application(compared="v1.22.1"),
                               "app.scylla-operator.2.json": application(op="Running"),
                               "app.scylla-operator.3.json": application(operation={"sync": {}}),
                               "app.scylla-operator.4.json": application(resources=NOT_SYNCED),
                               "app.scylla-operator.json": application()}, minutes="1")
check("waited through the old spec, an older comparison, a sync running or asked, an object not yet synced - then "
      "cleared on the second ready look", (rc, sum(" get application " in c for c in calls), deleted_names(deleted)),
      (0, 7, CRDS + ROLES))
check("  each new reason to wait said as it came", [l.split(" - ", 1)[1] for l in out.splitlines() if ": waiting - " in l],
      ["its spec still at ['v1.22.1'], the change's ['v1.23.0']", "not yet compared against the change's spec",
       "a sync under way", "1 object(s) not yet synced, e.g. Service/webhook"])
for n, (body, why) in enumerate([(application(rev="v1.22.1"), "its spec still at ['v1.22.1'], the change's ['v1.23.0']"),
                                 (application(compared="v1.22.1"), "not yet compared against the change's spec"),
                                 (application(op="Running"), "a sync under way"),
                                 (application(resources=NOT_SYNCED), "1 object(s) not yet synced, e.g. Service/webhook"),
                                 (RENDER_FAILED, "ComparisonError: chart fetch failed"),
                                 (dict(RENDER_FAILED, status=dict(RENDER_FAILED["status"], conditions=[])),
                                  "its sync status 'Unknown' (a render or fetch failed?)"),
                                 (application(health="Progressing"), "its health 'Progressing' - the new version not yet rolled out"),
                                 (application(synced="v1.22.1"), "its chart still synced at ['v1.22.1']")]):
    rc, out, deleted, _ = run({"app.scylla-operator.json": body}, minutes="0.001")
    check(f"never there ({why}): the time up, nothing deleted, why said", (rc, deleted, why in out), (1, [], True))
rc, out, deleted, _ = run({}, minutes="0.001")
check("its Application not read: the time up, nothing deleted", (rc, deleted, "its Application not read" in out),
      (1, [], True))

# ── two looks in a row; hooks ─────────────────────────────────────────────────────────────────────────────────
rc, _, deleted, calls = run({"app.scylla-operator.0.json": application(), "app.scylla-operator.1.json": application(op="Running"),
                             "app.scylla-operator.2.json": application(), "app.scylla-operator.json": application()}, minutes="1")
check("ready at one look, not at the next: nothing deleted until two looks in a row are ready",
      (rc, sum(" get application " in c for c in calls), deleted_names(deleted)), (0, 4, CRDS + ROLES))
HOOK = {"group": "batch", "kind": "Job", "name": "pre-upgrade", "hook": True, "requiresPruning": True}
rc, _, deleted, _ = run({"app.scylla-operator.json": application(resources=LEFT + [HOOK])})
check("a hook (no sync status, marked requiresPruning): no wait on it, never deleted", (rc, deleted_names(deleted)),
      (0, CRDS + ROLES))
rc, out, deleted, calls = run({"app.scylla-operator.json": RENDER_FAILED}, on="copy", minutes="0.001")
check("the copy, an app with an error condition: hard-refreshed once (the repo-server's cached failed render), "
      "nothing deleted", (rc, deleted, [c.split(" | ")[1].split(" -n argocd ")[1] for c in calls if "refresh=hard" in c]),
      (1, [], ["annotate applications.argoproj.io scylla-operator argocd.argoproj.io/refresh=hard --overwrite"]))

# ── what may be declared, what is given ────────────────────────────────────────────────────────────────────────
bad = os.path.join(W, "declared-bad.json")
json.dump({"scylla-operator": [{"release": "x", "source": "y", "why": "z", "objects": [
    {"kind": "ClusterRole", "name": "r"}, {"kind": "StatefulSet", "name": "data", "namespace": "scylla"}]}]}, open(bad, "w"))
rc, out, deleted, calls = run({"app.scylla-operator.json": application()}, env={"UPGRADE_LEFTOVERS_DECLARED": bad})
check("a declaration naming a kind never deleted here (a StatefulSet): refused before anything is read",
      (rc, calls, "REFUSED - declared, of a kind never deleted here: scylla-operator: StatefulSet/data in scylla" in out),
      (1, [], True))
for base in ("", "-x", "a b"):
    rc, out, _, calls = run({}, base=base)
    check(f"a base that is no revision ({base!r}): refused, nothing read",
          (rc, calls, "REFUSED - base" in out or "argument --base: expected one argument" in out), (2, [], True))

# ── the file shapes, the range ────────────────────────────────────────────────────────────────────────────────
rc, _, deleted, _ = run({"app.scylla-operator.json": application()}, head="multidoc")
check("a file of two Applications (as infra's kagent.yaml), the declared one second: read, and cleared",
      (rc, deleted_names(deleted)), (0, CRDS + ROLES))
rc, out, _, calls = run({"app.scylla-operator.json": application()}, base="main-moved", head="only-other")
check("main moved on since the change branched (a declared chart bumped on main alone): not the change's - "
      "the range from where they meet", (rc, calls, "no declared app moved by the change" in out), (0, [], True))
SRC1 = {"repoURL": "https://charts.example", "chart": "scylla-operator", "targetRevision": "v1.23.0"}
single = {"metadata": {"name": "scylla-operator"}, "spec": {"source": SRC1},
          "status": {"sync": {"status": "OutOfSync", "comparedTo": {"source": SRC1}, "revision": "v1.23.0"},
                     "health": {"status": "Healthy"}, "operationState": {"phase": "Succeeded"}, "resources": [SHIPPED] + LEFT}}
rc, _, deleted, _ = run({"app.scylla-operator.json": single}, head="single")
check("a single-source Application (spec.source, comparedTo.source, sync.revision): read, and cleared",
      (rc, deleted_names(deleted)), (0, CRDS + ROLES))
rc, _, deleted, _ = run({"app.scylla-operator.json": dict(single, status=dict(single["status"], sync=dict(
    single["status"]["sync"], revision="v1.22.1")))}, head="single", minutes="0.001")
check("  its chart still synced at the old version (sync.revision): nothing deleted", (rc, deleted), (1, []))

# ── what is deleted, and how ─────────────────────────────────────────────────────────────────────────────────
odd = [dict(LEFT[0], status="Unknown")] + LEFT[1:]
rc, _, deleted, _ = run({"app.scylla-operator.json": application(resources=odd)}, minutes="0.001")
check("a declared object marked requiresPruning but Unknown (never compared) in an app otherwise ready: no leftover - "
      "waited on, nothing deleted", (rc, deleted), (1, []))
roles = os.path.join(W, "declared-role.json")
json.dump({"scylla-operator": [{"release": "x", "source": "y", "why": "z", "objects": [
    {"kind": "Role", "name": "leader-election", "namespace": "scylla-operator"}]}]}, open(roles, "w"))
ROLE = res("Role", "leader-election", "rbac.authorization.k8s.io", ns="scylla-operator")
rc, _, deleted, _ = run({"app.scylla-operator.json": application(resources=[ROLE])}, env={"UPGRADE_LEFTOVERS_DECLARED": roles})
check("a namespaced declared object: deleted in its namespace",
      (rc, deleted), (0, ["kubectl delete role.rbac.authorization.k8s.io leader-election --ignore-not-found --wait=true "
                          "--timeout=120s -n scylla-operator"]))
two = os.path.join(W, "declared-two.json")
json.dump({"scylla-operator": json.load(open("scripts/upgrade-leftovers.json"))["scylla-operator"],
           "other": [{"release": "x", "source": "y", "why": "z", "objects": [{"kind": "ClusterRole", "name": "other-role"}]}]},
          open(two, "w"))
OTHER = {"metadata": {"name": "other"}, "spec": {"sources": [{"repoURL": "https://charts.example", "chart": "other",
                                                              "targetRevision": "1.0"}]}, "status": {}}
rc, out, deleted, _ = run({"app.scylla-operator.json": application(), "app.other.json": OTHER}, minutes="0.002",
                          env={"UPGRADE_LEFTOVERS_DECLARED": two})
check("two declared apps moved, one ready and one never: the ready one cleared, the other's time up and said, the run "
      "failed", (rc, deleted_names(deleted), "other: not on the change's version within" in out), (1, CRDS + ROLES, True))

# ── the clock ────────────────────────────────────────────────────────────────────────────────────────────────
import importlib.util  # noqa: E402
spec = importlib.util.spec_from_file_location("leftovers", "scripts/upgrade-leftovers.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
clock, sleeps = [1000.0], []
def fake_sleep(sec):
    sleeps.append(sec)
    clock[0] += sec
reads = [0]
def fake_kubectl(on, *args):
    reads[0] += 1
    if reads[0] > 1000:  # no sleep, or no deadline: the loop would spin for ever - a failure, not a hang
        raise RuntimeError("runaway")
    return 0, json.dumps(application(rev="v1.22.1"))
m.kubectl = fake_kubectl
m.say = lambda text: None
try:
    rc = m.wait_and_clear("ten", {"scylla-operator": ["v1.23.0"]}, {"scylla-operator": []}, 30, 20,
                          now=lambda: clock[0], sleep=fake_sleep)
except RuntimeError as e:
    rc = str(e)
check("the wait: a look every poll seconds, the time up at minutes x 60 s - not before, not much after",
      (rc, set(sleeps), 1800 <= clock[0] - 1000 < 1820), (1, {20}, True))
d = m.parser().parse_args(["--on", "ten", "--base", "a", "--head", "b"])
check("  by default 30 minutes, a look every 20 s", (d.minutes, d.poll), (30, 20))

# ── what the change moves ────────────────────────────────────────────────────────────────────────────────────
rc, out, deleted, calls = run({"app.scylla-operator.json": application()}, head="only-other")
check("a change moving no declared app: nothing read from the cluster, said",
      (rc, calls, "no declared app moved by the change" in out), (0, [], True))
rc, out, _, calls = run({"app.scylla-operator.json": application()}, head="removed")
check("a declared app's file removed by the change: no chart's leftover (root removes the app)", (rc, calls), (0, []))
rc, out, _, calls = run({}, base="base", head="no-such-branch")
check("a change not read (no such revision): failed, said, nothing read from the cluster",
      (rc, calls, "the change's apps not read" in out), (1, [], True))

# ── the copy ─────────────────────────────────────────────────────────────────────────────────────────────────
rc, _, deleted, calls = run({"app.scylla-operator.json": application()}, on="copy")
check("the copy: every app asked to refresh first (the change was just pushed), then the reads - through vagrant ssh "
      "to its node, as root with the admin kubeconfig",
      (rc, calls[:2]), (0, ["vagrant ssh kubeadm -c | sudo kubectl --kubeconfig /etc/kubernetes/admin.conf -n argocd "
                            "annotate applications.argoproj.io --all argocd.argoproj.io/refresh=normal --overwrite",
                            "vagrant ssh kubeadm -c | sudo kubectl --kubeconfig /etc/kubernetes/admin.conf "
                            "-n argocd get application scylla-operator -o json"]))
check("  production asked to refresh nothing - the reads and the deletes alone",
      [c for c in run({"app.scylla-operator.json": application()})[3] if "annotate" in c], [])
rc, _, _, calls = run({"app.scylla-operator.json": application()}, on="copy", env={"VAGRANT_SSH_CONFIG": f"{W}/ssh.cfg"})
check("  with VAGRANT_SSH_CONFIG: plain ssh with it", calls[0].split(" | ")[0], f"ssh -F {W}/ssh.cfg kubeadm")

# ── the declarations ─────────────────────────────────────────────────────────────────────────────────────────
data = json.load(open("scripts/upgrade-leftovers.json"))
shape = [(app, sorted(e), all(sorted(o) in (["kind", "name"], ["kind", "name", "namespace"]) for o in e["objects"]))
         for app, entries in data.items() for e in entries]
check("each declaration names its release, its source and why, and each object its kind and name",
      [s for s in shape if s[1] != ["objects", "release", "source", "why"] or not s[2]], [])
check("  scylla-operator's: the three CRDs and two ClusterRoles v1.23.0 dropped",
      sorted((o["kind"], o["name"]) for e in data["scylla-operator"] for o in e["objects"]),
      sorted([("CustomResourceDefinition", c) for c in CRDS] + [("ClusterRole", r) for r in ROLES]))
print("ALL PASS" if fails == 0 else f"{fails} FAILED")
raise SystemExit(1 if fails else 0)
PYCHECK
