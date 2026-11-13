#!/bin/bash
# The playbook defaults that restate what production runs - cert-manager, External Secrets, metrics-server, Istio,
# Gateway API, Cilium, local-path, the Kubernetes packages, the Argo CD chart, the data operators' charts - equal
# production's inventory (tests/ansible/copy/prod-inventory.txt): they build the Vagrant copy's node layer and a DR
# rebuild (task deploy:kubeadm). One moved without the other (two sources of truth) fails here, naming both - not at
# the end of a two-hour build.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_DFP'
import re, sys
import yaml
P = "deploy/ansible/playbooks/"
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
    (P + "setup-argocd.yml", "var", "argocd_chart_version", r"helm argocd/argocd argo-cd-(\S+) .*"),
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


have = open("tests/ansible/copy/prod-inventory.txt").read().splitlines()
fails = 0
for path, kind, key, pat in MAP:
    d = default(open(path).read(), kind, key)
    live = sorted({m.group(1) for m in (re.fullmatch(pat, l) for l in have) if m})
    ok = d is not None and len(live) == 1 and str(d).lstrip("v") == live[0].lstrip("v")
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {path.split('/')[-1]} {key}: default {d}, production {live or 'none'}")
print("defaults-follow-production: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_DFP
