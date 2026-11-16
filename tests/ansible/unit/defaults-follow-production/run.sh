#!/bin/bash
# The playbook defaults that restate what production runs - cert-manager, External Secrets, metrics-server, Istio,
# Gateway API, Cilium, local-path, the Kubernetes packages, containerd.io, the Argo CD chart, the data operators' charts - equal
# production's inventory (tests/ansible/copy/prod-inventory.txt): they build the Vagrant copy's node layer and a DR
# rebuild (task deploy:kubeadm). One moved without the other (two sources of truth) fails here, naming both - not at
# the end of a two-hour build. A pull request (CI's, an upgrade unit's) may move one: the unit moves the default with
# infra's chart, and production's inventory is read again after its apply - so there a default differing from production
# passes when the pull request itself moved it from its target's (origin/<target>, the clone step's fetch) and the
# target's still equals production (the copy proves it against infra's half). Its target not in the clone: refused.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_DFP'
import os, re, subprocess, sys
import yaml
P = "deploy/ansible/playbooks/"
EVENT, TARGET = os.environ.get("CI_PIPELINE_EVENT"), os.environ.get("CI_COMMIT_TARGET_BRANCH")
MAP = [
    (P + "setup-kubeadm.yml", "var", "cert_manager_version", r"argo-chart cert-manager cert-manager@(\S+)"),
    (P + "setup-kubeadm.yml", "var", "external_secrets_chart_version", r"argo-chart external-secrets external-secrets@(\S+)"),
    (P + "setup-kubeadm.yml", "var", "metrics_server_chart_version", r"argo-chart metrics-server metrics-server@(\S+)"),
    (P + "setup-kubeadm.yml", "var", "istio_version", r"argo-chart istiod istiod@(\S+)"),
    (P + "setup-istio.yml", "var", "istio_version", r"argo-chart istiod istiod@(\S+)"),
    (P + "setup-kubeadm.yml", "var", "gateway_api_version", r"crd gateway-api (\S+)"),
    (P + "setup-kubeadm.yml", "var", "cilium_version", r"helm kube-system/cilium cilium-(\S+) .*"),
    (P + "setup-kubeadm.yml", "var", "local_path_provisioner_version", r"image (?:docker\.io/)?rancher/local-path-provisioner (\S+)"),
    (P + "setup-kubeadm.yml", "var", "k8s_package_version", r"pkg kubeadm (\S+) .*"),
    (P + "setup-kubeadm.yml", "var", "containerd_io_version", r"pkg containerd\.io (\d+\.\d+\.\d+)-\S+ .*"),
    (P + "setup-argocd.yml", "var", "argocd_chart_default", r"helm argocd/argocd argo-cd-(\S+) .*"),
    (P + "setup-kubeadm.yml", "helm", "cnpg", r"argo-chart cnpg cloudnative-pg@(\S+)"),
    (P + "setup-kubeadm.yml", "helm", "strimzi", r"argo-chart strimzi strimzi-kafka-operator@(\S+)"),
    (P + "setup-kubeadm.yml", "helm", "scylla-operator", r"argo-chart scylla-operator scylla-operator@(\S+)"),
    (P + "setup-kubeadm.yml", "helm", "scylla-manager", r"argo-chart scylla-manager scylla-manager@(\S+)"),
]


def walk(ts):
    for t in ts or []:
        if isinstance(t, dict):
            yield t
            for k in ("block", "rescue", "always", "tasks"):
                yield from walk(t.get(k))


def default(text, kind, key):
    """The playbook's default: a play var (its default('...') where it reads an override), or a helm task's chart."""
    if kind == "var":
        m = re.search(r"^    %s: (.+?)\s*(#.*)?$" % re.escape(key), text, re.M)
        if not m:
            return None
        v = m.group(1).strip().strip('"')
        d = re.search(r"default\('([^']+)'\)", v)
        return d.group(1) if d else v
    for pl in yaml.safe_load(text):
        for t in walk(pl.get("tasks")):
            h = t.get("kubernetes.core.helm") or {}
            if h.get("name") == key and "chart_version" in h:
                return str(h["chart_version"])
    return None


def target_text(path):
    """A pull request's target's file, as the clone fetched it; None off a pull request."""
    if EVENT != "pull_request":
        return None
    r = subprocess.run(["git", "show", f"refs/remotes/origin/{TARGET}:{path}"], capture_output=True, text=True)
    if not TARGET or r.returncode != 0:
        print(f"FAIL a pull request, its target origin/{TARGET} not in this clone (the clone step's fetch_target_branch) "
              f"- {path} not judged")
        sys.exit(1)
    return r.stdout


same = lambda a, b: a is not None and b is not None and str(a).lstrip("v") == str(b).lstrip("v")
have = open("tests/ansible/copy/prod-inventory.txt").read().splitlines()
fails = 0
for path, kind, key, pat in MAP:
    d = default(open(path).read(), kind, key)
    live = sorted({m.group(1) for m in (re.fullmatch(pat, l) for l in have) if m})
    ok = len(live) == 1 and same(d, live[0])
    why = ""
    if not ok and len(live) == 1 and d is not None:
        t = target_text(path)
        if t is not None:
            td = default(t, kind, key)
            ok = same(td, live[0]) and not same(d, td)
            why = (f" (this pull request does not move it: its target's is {td} too)" if same(d, td) else
                   f" (this pull request moves it from {td}" + (", its target's - as production" if ok else "") + ")")
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {path.split('/')[-1]} {key}: default {d}, production {live or 'none'}{why}")
print("defaults-follow-production: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_DFP
