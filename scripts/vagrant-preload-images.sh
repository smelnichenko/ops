#!/usr/bin/env bash
# vagrant-preload-images.sh — put production's application images (git.pmon.dev/schnappy/*) into the Vagrant
# kubeadm node's containerd, so the upgrade test runs exactly what ten runs without any registry credential in the
# VMs. The host's docker (logged in to git.pmon.dev) pulls each image; `docker save` streams it into the node's
# k8s.io namespace. The charts use pullPolicy IfNotPresent with fixed commit tags, so the kubelet never pulls.
#
# The image list is read from the infra values Argo syncs in Vagrant (production's own values, at the mirrored ref).
#
# Usage: scripts/vagrant-preload-images.sh [infra checkout, default ../infra] [platform checkout, default ../platform]
#                                          [infra ref, default main] [platform ref, default main]
# (the refs an upgrade step's mirror run used: scripts/vagrant-gitops-mirror.py --infra-ref/--platform-ref)
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
infra=${1:-$ops/../infra}
platform=${2:-$ops/../platform}
infra_ref=${3:-main}
platform_ref=${4:-main}

# production's values plus the chart default they rely on (schnappy-data's apt-cacher-ng image)
mapfile -t images < <({ for f in schnappy-production-apps schnappy-infra-data; do
                          git -C "$infra" show "$infra_ref:clusters/production/$f/values.yaml"; echo "---"; done
                        git -C "$platform" show "$platform_ref:helm/schnappy-data/values.yaml"; } \
                     | python3 -c '
import sys, yaml
def walk(n):
    if isinstance(n, dict):
        r, t = n.get("repository"), n.get("tag")
        if isinstance(r, str) and r.startswith("git.pmon.dev/") and t:
            print(f"{r}:{t}")
        for v in n.values(): walk(v)
    elif isinstance(n, list):
        for v in n: walk(v)
    elif isinstance(n, str) and n.startswith("git.pmon.dev/") and ":" in n.split("/")[-1]:
        print(n)  # a whole image reference in one string
for doc in yaml.safe_load_all(sys.stdin): walk(doc)' | sort -u)
[ "${#images[@]}" -gt 0 ] || { echo "no git.pmon.dev images found in the production values"; exit 1; }

cd "$ops"
for img in "${images[@]}"; do
  echo "== $img"
  if ! docker pull -q "$img"; then
    # The registry lacks it but ten runs it from its image cache (2026-10-02: apt-cacher-ng:1.0, built by hand once,
    # gone from the registry - a rebuilt ten could not pull it either). Copy ten's exact image: a read-only export
    # streamed over ssh, nothing written on ten.
    echo "WARNING: $img is not in the registry - copying it from ten's image cache"
    # shellcheck disable=SC2029  # $img is meant to expand here, into the remote command
    ssh "${TEN_SSH:-sm@192.168.11.2}" "sudo -n ctr -n k8s.io images export --platform linux/amd64 - '$img'" \
      | vagrant ssh kubeadm -c 'sudo ctr -n k8s.io images import --digests -' 2>/dev/null | grep -v '^$' | tail -1
    continue
  fi
  docker save "$img" | vagrant ssh kubeadm -c 'sudo ctr -n k8s.io images import --digests -' 2>/dev/null | grep -v '^$' | tail -1
done
vagrant ssh kubeadm -c 'sudo ctr -n k8s.io images ls -q | grep "^git.pmon.dev/schnappy/"' 2>/dev/null | tr -d '\r'
