#!/bin/bash
# The playbook defaults that restate what Argo CD (or a step's playbook) runs in production - cert-manager, External
# Secrets, metrics-server, Istio, Gateway API, Cilium, local-path, the Kubernetes packages, the Argo CD chart, the data
# operators' charts - equal production's inventory at the baseline and after every step, the step's default lines
# applied: a step that moves the one and not the other (two sources of truth) fails here, naming both.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_DFI'
import importlib.machinery, importlib.util, re, sys, yaml
def load(name, path):
    L = importlib.machinery.SourceFileLoader(name, path)
    m = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, L))
    L.exec_module(m)
    return m
inv = load("inv", "scripts/upgrade-expected-inventory.py")
dflt = load("dflt", "scripts/upgrade-defaults.py")
P = "deploy/ansible/playbooks/"
MAP = [
    (P + "setup-kubeadm.yml", "var", "cert_manager_version", r"argo-chart cert-manager cert-manager@(\S+)"),
    (P + "setup-kubeadm.yml", "var", "external_secrets_chart_version", r"argo-chart external-secrets external-secrets@(\S+)"),
    (P + "setup-kubeadm.yml", "var", "metrics_server_chart_version", r"argo-chart metrics-server metrics-server@(\S+)"),
    (P + "setup-kubeadm.yml", "var", "istio_version", r"argo-chart istiod istiod@(\S+)"),
    (P + "setup-istio.yml", "var", "istio_version", r"argo-chart istiod istiod@(\S+)"),
    (P + "setup-kubeadm.yml", "var", "gateway_api_version", r"crd gateway-api (\S+)"),
    (P + "setup-kubeadm.yml", "var", "cilium_version", r"helm kube-system/cilium cilium-(\S+) .*"),
    (P + "setup-kubeadm.yml", "var", "local_path_provisioner_version", r"image rancher/local-path-provisioner (\S+)"),
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
norm = lambda v: str(v).lstrip("v")
read = lambda p: open(p).read()
names = dflt.step_names()
fails, compared = [], 0
for i in range(-1, len(names)):
    done = names[:i + 1]
    have = inv.expected(done)
    try:
        files = dflt.applied(read, [s for s in done if dflt.default_lines(s)])
    except ValueError as e:
        fails.append(f"after {done[-1] if done else 'the baseline'}: the steps' default lines do not apply - {e}")
        break
    for path, kind, key, pat in MAP:
        text = files.get(path) or read(path)
        live = [re.fullmatch(pat, l) for l in have]
        live = [m.group(1) for m in live if m]
        if len(live) != 1 or live[0] == "*":
            continue
        d = default(text, kind, key)
        compared += 1
        if d is None or norm(d) != norm(live[0]):
            fails.append(f"after {done[-1] if done else 'the baseline'}: {path.split('/')[-1]} {key} = {d}, production runs {live[0]}")
print(("PASS" if compared > 400 else "FAIL") + f" compared {compared} (default, inventory) pairs over the baseline and {len(names)} steps")
for f in fails[:25]:
    print("FAIL " + f)
print("defaults-follow-inventory: " + ("ALL-PASS" if not fails and compared > 400 else f"{len(fails)} FAILED"))
sys.exit(1 if fails or compared <= 400 else 0)
PY_DFI
