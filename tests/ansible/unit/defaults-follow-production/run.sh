#!/bin/bash
# The playbook defaults that restate what production runs - cert-manager, External Secrets, metrics-server, Istio,
# Gateway API, Cilium, local-path, the Kubernetes packages, containerd.io, the Argo CD chart, the data operators' charts - equal
# production's inventory (tests/ansible/copy/prod-inventory.txt): they build the Vagrant copy's node layer and a DR
# rebuild (task deploy:kubeadm). One moved without the other (two sources of truth) fails here, naming both - not at
# the end of a two-hour build. A pull request (CI's, an upgrade unit's) may move one: the unit moves the default with
# infra's chart, and production's inventory is read again after its apply - so there a default differing from production
# passes when the pull request itself moved it from its target's (origin/<target>, the clone step's fetch) and the
# target's still equals production (the copy proves it against infra's half). Its target not in the clone: refused.
# A branch's push (ops' CI runs on pushes, not pull requests, since 2026-11-24) holds no target - the clone step fetches
# one for a pull request only, and the CI's read token cannot read ops - so there a default differing from production
# passes, said: main's push judges it against production after the apply. Comparing with main would fail only when main
# already differs from production, which main's own push fails anyway. Main's push and a run without CI: equal, or fail.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
exec python3 - <<'PY_DFP'
import os, re, subprocess, sys
sys.path.insert(0, "tests/ansible/unit")
import renovate_preset
P = "deploy/ansible/playbooks/"
EVENT, TARGET = os.environ.get("CI_PIPELINE_EVENT"), os.environ.get("CI_COMMIT_TARGET_BRANCH")
BRANCH = os.environ.get("CI_COMMIT_BRANCH") if EVENT == "push" and os.environ.get("CI_COMMIT_BRANCH") != "main" else None
# each default: its playbook, its play var, production's version in the inventory, and how the preset's Renovate must
# read it - (datasource, depName) as production's own dependency is named (infra's Argo app's chart: Renovate's argocd
# manager names a chart by its name, an OCI one by registry/path; else the registry or tag the version comes from), so the
# default moves in that dependency's unit (a typo, depName=cnpg, is another dependency or none) - or why it is left by
# hand. Read by no manager, a default stays behind when Renovate moves infra's chart: the unit's branch passes here
# (a branch's push passes a default differing from production), ops' main fails once production's inventory is read
# after the apply (the data operators' charts, 2026-11-17's review)
MAP = [
    (P + "setup-kubeadm.yml", "cert_manager_version", r"argo-chart cert-manager cert-manager@(\S+)", ("helm", "cert-manager")),
    (P + "setup-kubeadm.yml", "external_secrets_chart_version", r"argo-chart external-secrets external-secrets@(\S+)",
     ("helm", "external-secrets")),
    (P + "setup-kubeadm.yml", "metrics_server_chart_version", r"argo-chart metrics-server metrics-server@(\S+)",
     ("helm", "metrics-server")),
    (P + "setup-kubeadm.yml", "istio_version", r"argo-chart istiod istiod@(\S+)", ("helm", "istiod")),
    (P + "setup-istio.yml", "istio_version", r"argo-chart istiod istiod@(\S+)", ("helm", "istiod")),
    (P + "setup-kubeadm.yml", "gateway_api_version", r"crd gateway-api (\S+)",
     ("git-tags", "https://github.com/kubernetes-sigs/gateway-api")),
    (P + "setup-kubeadm.yml", "cilium_version", r"helm kube-system/cilium cilium-(\S+) .*", ("helm", "cilium")),
    (P + "setup-kubeadm.yml", "local_path_provisioner_version", r"image (?:docker\.io/)?rancher/local-path-provisioner (\S+)",
     ("docker", "rancher/local-path-provisioner")),
    (P + "setup-kubeadm.yml", "k8s_package_version", r"pkg kubeadm (\S+) .*", ("docker", "registry.k8s.io/kube-apiserver")),
    (P + "setup-kubeadm.yml", "containerd_io_version", r"pkg containerd\.io (\d+\.\d+\.\d+)-\S+ .*",
     "the runner refuses a containerd unit - no proof path on the copy yet; upgrade-containerd.yml by hand"),
    (P + "setup-argocd.yml", "argocd_chart_default", r"helm argocd/argocd argo-cd-(\S+) .*", ("helm", "argo-cd")),
    (P + "setup-woodpecker.yml", "woodpecker_chart_version", r"argo-chart woodpecker woodpecker@(\S+)",
     ("docker", "ghcr.io/woodpecker-ci/helm/woodpecker")),
    (P + "setup-kubeadm.yml", "cnpg_chart_version", r"argo-chart cnpg cloudnative-pg@(\S+)", ("helm", "cloudnative-pg")),
    (P + "setup-kubeadm.yml", "strimzi_chart_version", r"argo-chart strimzi strimzi-kafka-operator@(\S+)",
     ("helm", "strimzi-kafka-operator")),
    (P + "setup-kubeadm.yml", "scylla_operator_chart_version", r"argo-chart scylla-operator scylla-operator@(\S+)",
     ("helm", "scylla-operator")),
    (P + "setup-kubeadm.yml", "scylla_manager_chart_version", r"argo-chart scylla-manager scylla-manager@(\S+)",
     ("helm", "scylla-manager")),
]


def locate(text, key):
    """The default, a play var: (its line, 0-based, its value) - None unless one line alone holds it."""
    at = [(i, m.group(1).strip().strip('"')) for i, l in enumerate(text.splitlines())
          for m in [re.match(r"^    %s: (.+?)\s*(#.*)?$" % re.escape(key), l)] if m]
    return at[0] if len(at) == 1 else None


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
value = lambda found: found[1] if found else None
have = open("tests/ansible/copy/prod-inventory.txt").read().splitlines()
texts, readings = {}, {}
fails = 0
for path, key, pat, reading in MAP:
    text = texts.setdefault(path, open(path).read())
    found = locate(text, key)
    d = value(found)
    live = sorted({m.group(1) for m in (re.fullmatch(pat, l) for l in have) if m})
    ok = len(live) == 1 and same(d, live[0])
    why = ""
    if not ok and len(live) == 1 and d is not None and BRANCH:
        ok = True
        why = f" (branch {BRANCH}'s push: passes here - main's push judges it against production after the apply)"
    elif not ok and len(live) == 1 and d is not None:
        t = target_text(path)
        if t is not None:
            td = value(locate(t, key))
            ok = same(td, live[0]) and not same(d, td)
            why = (f" (this pull request does not move it: its target's is {td} too)" if same(d, td) else
                   f" (this pull request moves it from {td}" + (", its target's - as production" if ok else "") + ")")
    fails += not ok
    name = path.split("/")[-1]
    print(f"{'PASS' if ok else 'FAIL'} {name} {key}: default {d}, production {live or 'none'}{why}")
    if isinstance(reading, str):
        print(f"SKIP {name} {key}: not Renovate's - {reading}")
        continue
    reads = readings.setdefault(path, renovate_preset.reads(path, text))
    read = next(((r["datasource"], r["depName"]) for r in reads if found and r["line"] == found[0]), None)
    fails += read != reading
    print(f"{'PASS' if read == reading else 'FAIL'} {name} {key}: read by the preset's Renovate as {read}"
          + (" - production's dependency, so moved with it in the same unit" if read == reading else
             f" - NOT {reading}: annotate it '# renovate: datasource=... depName=...' as production's chart is named"))
print("defaults-follow-production: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_DFP
