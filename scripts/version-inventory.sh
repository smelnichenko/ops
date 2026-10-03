#!/usr/bin/env bash
# version-inventory.sh — print every versioned component of a kubeadm node, one sorted line each:
#   <kind> <name> <version>
# Read-only. Runs ON the node (production `ten` or the Vagrant kubeadm VM) with kubectl access, so the same output
# from both can be diffed: the upgrade test's baseline is valid only when the two inventories are identical.
#
#   ssh ten 'bash -s' < scripts/version-inventory.sh > prod.txt
#   vagrant ssh kubeadm -c 'sudo bash -s' < scripts/version-inventory.sh > vagrant.txt
#   diff prod.txt vagrant.txt
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
[ -r "$KUBECONFIG" ] || KUBECONFIG="$HOME/.kube/config"

{
  echo "os debian $(cat /etc/debian_version)"

  # host packages that make up the node
  # installed only ("ii", or "hi" when held): dpkg also remembers removed packages ("rc"), which run nothing
  dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' \
    containerd containerd.io runc cri-tools kubeadm kubelet kubectl kubernetes-cni 2>/dev/null \
    | awk '$1=="ii" {print "pkg", $2, $3} $1=="hi" {print "pkg", $2, $3, "(held)"}' || true
  for bin in /usr/local/bin/containerd /usr/local/bin/nerdctl /usr/local/bin/buildkitd; do
    [ -x "$bin" ] && echo "binary $bin $("$bin" --version 2>/dev/null | head -1 | awk '{print $NF}')"
  done
  echo "containerd-unit $(systemctl show containerd -p FragmentPath --value)"

  # Helm releases: chart and app version
  helm list -A -o json 2>/dev/null \
    | python3 -c 'import json,sys
for r in json.load(sys.stdin): print("helm", r["namespace"]+"/"+r["name"], r["chart"], r["app_version"])'

  # Argo CD Applications that render an upstream chart (they are not Helm releases)
  if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
    kubectl get applications.argoproj.io -A -o json \
      | python3 -c 'import json,sys
for a in json.load(sys.stdin)["items"]:
    for s in a["spec"].get("sources") or [a["spec"].get("source",{})]:
        if s.get("chart"): print("argo-chart", a["metadata"]["name"], s["chart"]+"@"+str(s.get("targetRevision")))'
  fi

  # every container image that runs or is set to run (digests dropped: the tag is the version): pods not finished,
  # each CronJob's template, each Job no CronJob owns. A finished pod runs nothing, like a removed package: a CronJob
  # keeps its last runs' pods for hours, with the image they ran - after its image moves too.
  kubectl get pods,cronjobs,jobs -A -o json \
    | python3 -c 'import json,sys
seen=set()
for o in json.load(sys.stdin)["items"]:
    meta=o["metadata"]
    if meta["namespace"]=="woodpecker" and meta["name"].startswith("wp-"): continue
    if o["kind"]=="Pod":
        if o["status"].get("phase") in ("Succeeded","Failed"): continue
        spec=o["spec"]
    elif o["kind"]=="CronJob":
        spec=o["spec"]["jobTemplate"]["spec"]["template"]["spec"]
    else:
        if any(r["kind"]=="CronJob" for r in meta.get("ownerReferences",[])): continue
        spec=o["spec"]["template"]["spec"]
    for c in spec.get("containers",[])+spec.get("initContainers",[]):
        img=c["image"].split("@")[0]
        if img not in seen: seen.add(img); print("image", img.rsplit(":",1)[0], img.rsplit(":",1)[1] if ":" in img.split("/")[-1] else "latest")'

  # CRD groups that carry a bundle/operator version
  kubectl get crd gateways.gateway.networking.k8s.io \
    -o jsonpath='{"crd gateway-api "}{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{"\n"}' 2>/dev/null || true
  kubectl get crd prometheuses.monitoring.coreos.com \
    -o jsonpath='{"crd prometheus-operator "}{.metadata.annotations.operator\.prometheus\.io/version}{"\n"}' 2>/dev/null || true

  echo "k8s server $(kubectl version -o json | python3 -c 'import json,sys;print(json.load(sys.stdin)["serverVersion"]["gitVersion"])')"
} | LC_ALL=C sort -u
