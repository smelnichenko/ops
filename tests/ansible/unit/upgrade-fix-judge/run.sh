#!/bin/bash
# scripts/upgrade-fix-judge.py - what the fix agent may change in a file, judged on the parsed YAML (its fix reaches
# production in the run that proves it, unseen) - against real git, one repository per case: the file as it was on the
# proven head, the agent's version on top, the judge run as plain_fix runs it. The cases are the change's second review's
# (2026-11-21): each bypass of the line patterns it replaced refused - an image swapped to another registry, an Istio hub,
# an image repository, a new document in flow style, a new key quoted or not, a widened Role, mTLS, a NetworkPolicy off,
# runAsUser 0, readOnlyRootFilesystem dropped, an Argo application's prune, project or repository, a one-way store's
# version in another unit, an unknown tag, a control character, a command - and what a fix is allowed: a version moved, an
# image's tag, an Argo chart's version and Helm values, a value renamed or dropped, the store's own unit's version.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
REAL=$PWD
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 - "$REAL" "$W" <<'PYJUDGE'
import os, subprocess, sys
REAL, W = sys.argv[1], sys.argv[2]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def g(repo, *args):
    return subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-C", repo, *args], capture_output=True, text=True, check=True).stdout.strip()
n = 0
def judge(old, new, path="clusters/production/x/values.yaml", store=""):
    """(exit, its reason) of the judge on old -> new"""
    global n
    n += 1
    repo = os.path.join(W, f"r{n}")
    subprocess.run(["git", "init", "-q", repo], check=True)
    f = os.path.join(repo, path); os.makedirs(os.path.dirname(f), exist_ok=True)
    open(f, "w", newline="").write(old); g(repo, "add", "-A"); g(repo, "commit", "-qm", "proven")
    proven = g(repo, "rev-parse", "HEAD")
    open(f, "w", newline="").write(new); g(repo, "commit", "-qam", "the agent's fix")
    tip = g(repo, "rev-parse", "HEAD")
    r = subprocess.run(["python3", "-I", os.path.join(REAL, "scripts/upgrade-fix-judge.py"), repo, proven, tip, path],
                       capture_output=True, text=True, env={**os.environ, "FIX_STORE": store,
                                                            "FIX_STORES_TABLE": os.path.join(REAL, "scripts/upgrade-stores.json")})
    return r.returncode, r.stderr.strip()
def refused(old, new, why, **kw):
    rc, err = judge(old, new, **kw)
    return rc == 1 and why in err, err if rc != 1 or why not in err else ""
APP = ("apiVersion: argoproj.io/v1alpha1\nkind: Application\nmetadata:\n  name: prometheus\nspec:\n  project: default\n"
       "  source:\n    repoURL: https://prometheus-community.github.io/helm-charts\n    chart: kube-prometheus-stack\n"
       "    targetRevision: 92.1.0\n    helm:\n      valuesObject:\n        alertmanager:\n          enabled: true\n"
       "  destination:\n    server: https://kubernetes.default.svc\n  syncPolicy:\n    automated:\n      prune: false\n")
ETCD = ("apiVersion: batch/v1\nkind: CronJob\nspec:\n  jobTemplate:\n    spec:\n      template:\n        spec:\n"
        "          hostNetwork: true\n          containers:\n          - name: etcd\n            image: registry.k8s.io/etcd:3.6.16-0\n"
        "            command: [\"etcdctl\"]\n")
# ── allowed ───────────────────────────────────────────────────────────────────────────────────────────────────────────
STRIMZI = APP.replace("prometheus-community.github.io/helm-charts", "strimzi.io/charts").replace("kube-prometheus-stack", "strimzi-kafka-operator").replace("92.1.0", "1.2.0")
DIGEST = "sha256:" + "a" * 64
for name, old, new, kw in (
        ("a version moved (image.tag)", "image:\n  repository: istio/proxyv2\n  tag: 1.31.4\n", "image:\n  repository: istio/proxyv2\n  tag: 1.32.0\n", {}),
        ("an image's tag moved in one line, its name kept (the etcd backup's)", ETCD, ETCD.replace("3.6.16-0", "3.6.17-0"), {}),
        ("a library image's tag moved, its flavour kept (nginx:1.27-alpine)", "image: nginx:1.27-alpine\n", "image: nginx:1.29-alpine\n", {}),
        ("an Argo application's chart version (targetRevision)", APP, APP.replace("92.1.0", "93.0.0"), {"path": "clusters/production/argocd/apps/prometheus.yaml"}),
        ("a value renamed beside itself inside an Argo application's Helm values", APP, APP.replace("alertmanager:\n          enabled", "alertmanager:\n          active"), {"path": "clusters/production/argocd/apps/prometheus.yaml"}),
        ("a value renamed beside itself (the chart renamed it)", "foo:\n  oldName: true\n  keep: 1\n", "foo:\n  newName: true\n  keep: 1\n", {}),
        ("a one-way store's version in that store's own unit", "scylla:\n  image: scylladb/scylla:2026.2.3\n", "scylla:\n  image: scylladb/scylla:2026.3.1\n", {"store": "scylladb"}),
        ("Vault's version in Vault's own unit (ops vars)", 'vault_version: "1.21.4"\n', 'vault_version: "1.21.5"\n', {"path": "deploy/ansible/vars/vault.yml", "store": "vault"}),
        ("a comment added, a version moved (comments are no values)", "v: 1.0.0\n", "# why\nv: 1.0.1\n", {})):
    rc, err = judge(old, new, **kw)
    check(f"allowed: {name}", (rc, err), (0, ""))
# ── refused ───────────────────────────────────────────────────────────────────────────────────────────────────────────
NEITHER = "neither a newer version of its shape nor the same image's newer tag"
for name, old, new, why, kw in (
        ("an image swapped to another registry (the etcd backup: host network, etcd's certificates)", ETCD, ETCD.replace("registry.k8s.io/etcd", "evil.example/etcd"), NEITHER, {}),
        ("its command changed", ETCD, ETCD.replace('["etcdctl"]', '["sh"]'), NEITHER, {}),
        ("an image's tag removed (latest)", ETCD, ETCD.replace(":3.6.16-0", ""), NEITHER, {}),
        ("a digest-pinned image's tag moved (its digest is Renovate's)", f"image: x/y:1.0.0@{DIGEST}\n", f"image: x/y:1.0.1@{DIGEST}\n", NEITHER, {}),
        ("a downgrade (rclone 1.75.2 -> 1.40.0)", "image: rclone/rclone:1.75.2\n", "image: rclone/rclone:1.40.0\n", NEITHER, {}),
        ("a retention cut (168h -> 1h: Velero deletes the older backups)", "ttl: 168h\n", "ttl: 1h\n", NEITHER, {}),
        ("a bare number (a retention, a count: 7 -> 1)", "retention: 7\n", "retention: 1\n", NEITHER, {}),
        ("a chart range (1.x: every later release lands without a unit)", STRIMZI.replace("1.2.0", "1.2.0"), STRIMZI.replace("1.2.0", "1.x"), NEITHER, {"path": "clusters/production/argocd/apps/strimzi.yaml", "store": "kafka"}),
        ("an IPv4 address changed", 'production_ten_ip: "192.168.1.10"\n', 'production_ten_ip: "192.168.1.66"\n', NEITHER, {"path": "deploy/ansible/vars/hosts.yml"}),
        ("a file mode loosened ('0400' -> '0444')", "- name: unseal keys\n  file:\n    mode: '0400'\n", "- name: unseal keys\n  file:\n    mode: '0444'\n", NEITHER, {"path": "deploy/ansible/playbooks/setup-vault-pi.yml"}),
        ("a play's serial (1 -> 2)", "- hosts: vault\n  serial: 1\n", "- hosts: vault\n  serial: 2\n", NEITHER, {"path": "deploy/ansible/playbooks/upgrade-vault.yml"}),
        ("a base-60 number (9100 == 2:31:40 to YAML 1.1, a string to Helm)", "port: 9100\n", "port: 2:31:40\n", NEITHER, {}),
        ("Istio's hub changed (a privileged DaemonSet's images)", "hub: docker.io/istio\ntag: 1.31.4\n", "hub: evil.example/istio\ntag: 1.31.4\n", "a security path", {}),
        ("an image repository changed", "image:\n  repository: istio/proxyv2\n  tag: 1.31.4\n", "image:\n  repository: evil/proxyv2\n  tag: 1.31.4\n", "a security path", {}),
        ("a new document in flow style", "a: 1\n", "a: 1\n--- {apiVersion: batch/v1, kind: Job}\n", "documents where there were", {}),
        ("a new key (a chart's extra objects)", "a: 1\n", "a: 1\nextraObjects: [{kind: Job}]\n", "a new value", {}),
        ("a quoted kind key (a document made a resource)", "a: 1\n", 'a: 1\n"kind": Job\n', "a document's kind changed", {}),
        ("a new quoted key", "a: 1\n", 'a: 1\n"extraManifests": []\n', "a new value", {}),
        ("a duplicate key (Helm takes the last: ScyllaDB's release line moved past a check reading the first)",
         "agentVersion: 3.4.0\nversion: 2026.1.16\n", "agentVersion: 3.4.0\nversion: 2026.1.16\nversion: 2026.2.0\n", "a duplicate key", {}),
        ("an alias added (YAML that expands what it holds)", "a: 1.0.0\n", "a: 1.0.0\nx: &x [1, 1]\ny: [*x, *x]\n", "an alias added", {}),
        ("a Role widened", "apiVersion: rbac.authorization.k8s.io/v1\nkind: Role\nrules:\n- resources: [pods]\n  verbs: [get]\n",
         "apiVersion: rbac.authorization.k8s.io/v1\nkind: Role\nrules:\n- resources: ['*']\n  verbs: ['*']\n", "a Role changed", {}),
        ("a namespace's sidecar injection label dropped", "apiVersion: v1\nkind: Namespace\nmetadata:\n  labels:\n    istio.io/rev: default\n    team: x\n",
         "apiVersion: v1\nkind: Namespace\nmetadata:\n  labels:\n    team: x\n", "a Namespace changed", {}),
        ("mTLS loosened (mode STRICT -> PERMISSIVE)", "mtls:\n  mode: STRICT\n", "mtls:\n  mode: PERMISSIVE\n", "a security path", {}),
        ("a mode changed outside a security path", "mesh:\n  mode: STRICT\n", "mesh:\n  mode: PERMISSIVE\n", NEITHER, {}),
        ("NetworkPolicies off", "networkPolicies:\n  enabled: true\n", "networkPolicies:\n  enabled: false\n", "a security path", {}),
        ("runAsUser 0", "securityContext:\n  runAsUser: 1000\n", "securityContext:\n  runAsUser: 0\n", "a security path", {}),
        ("a backup turned off by its value dropped (cnpg.backup: the chart's default is off)", "cnpg:\n  backup: true\n  instances: 2\n", "cnpg:\n  instances: 2\n", "dropped", {}),
        ("readOnlyRootFilesystem dropped", "securityContext:\n  readOnlyRootFilesystem: true\n  runAsNonRoot: true\n", "securityContext:\n  runAsNonRoot: true\n", "dropped", {}),
        ("a value renamed into an env var's key (any key there means something)", "env:\n  PILOT_AUTO_SEND_UNHEALTHY_ENDPOINTS: 'false'\n",
         "env:\n  PILOT_ENABLE_XDS_IDENTITY_CHECK: 'false'\n", "a new value", {}),
        ("a value renamed to an ALL_CAPS key", "pilot:\n  OLD_KEY: x\n", "pilot:\n  NEW_KEY: x\n", "a new value", {}),
        ("a value moved to another parent (it could land anywhere)", "a:\n  k: x\n  m: y\nb:\n  j: z\n", "a:\n  m: y\nb:\n  j: z\n  k: x\n", "a new value", {}),
        ("a value renamed in a free-form map, its keys lower case (a label: any key there means something)", "labels:\n  team: x\n", "labels:\n  owner: x\n", "a new value", {}),
        ("a version's shape changed (1.31 -> 1.32.0: another kind of value)", "tag: 1.31\n", "tag: 1.32.0\n", NEITHER, {}),
        ("a version's flavour changed (17-alpine -> 18-bookworm: another image)", "image: postgres:17-alpine\n", "image: postgres:18-bookworm\n", NEITHER, {"store": "postgres"}),
        ("a play's any_errors_fatal renamed ignore_errors (ops: versions alone)", "- hosts: vault\n  any_errors_fatal: true\n",
         "- hosts: vault\n  ignore_errors: true\n", "a new value", {"path": "deploy/ansible/playbooks/upgrade-vault.yml"}),
        ("an Argo application's prune turned on", APP, APP.replace("prune: false", "prune: true"), "Argo CD Application", {"path": "clusters/production/argocd/apps/root.yaml"}),
        ("an Argo application's project changed", APP, APP.replace("project: default", "project: other"), "Argo CD Application", {"path": "clusters/production/argocd/apps/root.yaml"}),
        ("an Argo application's repository changed", APP, APP.replace("prometheus-community.github.io", "evil.example"), "Argo CD Application", {"path": "clusters/production/argocd/apps/root.yaml"}),
        ("a one-way store's version in a unit not its", "scylla:\n  image: scylladb/scylla:2026.2.3\n", "scylla:\n  image: scylladb/scylla:2026.3.1\n", "one-way store scylladb", {}),
        ("the store's operator, its path in camelCase (scyllaOperator is scylla's)", "scyllaOperator:\n  version: 1.18.0\n", "scyllaOperator:\n  version: 1.19.0\n", "one-way store scylladb", {}),
        ("a store's version written apart from its image (equal to the image's tag)", "scylla:\n  image: scylladb/scylla:2026.1.16\nmember:\n  version: 2026.1.16\n",
         "scylla:\n  image: scylladb/scylla:2026.1.16\nmember:\n  version: 2026.2.0\n", "one-way store scylladb", {}),
        ("Strimzi's chart through its Argo application (the chart a sibling of targetRevision)", STRIMZI, STRIMZI.replace("1.2.0", "2.0.0"), "one-way store kafka", {"path": "clusters/production/argocd/apps/strimzi.yaml"}),
        ("Vault's version in Kafka's unit", 'vault_version: "1.21.4"\n', 'vault_version: "1.21.5"\n', "one-way store vault", {"path": "deploy/ansible/vars/vault.yml", "store": "kafka"}),
        ("a tag added (!vault: encrypted content, its version alone read)", "a: 1.0.0\n", "a: !vault 1.0.1\n", "an explicit tag added", {}),
        ("a carriage return in a line it adds (a key hidden from git)", "v: 1.0.0\n", "v: 1.0.1\r  extra: evil\n", "a control or non-ASCII character", {}),
        ("a value's type changed (a list where a value was)", "port: 8080\n", "port: [8080]\n", "a new value", {})):
    ok, err = refused(old, new, why, **kw)
    check(f"refused: {name}", (ok, err), (True, ""))
print("upgrade-fix-judge: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYJUDGE
