#!/usr/bin/env bash
# vagrant-preload-floating.sh - production's images with a floating tag (latest, or a tag of at most two version
# numbers: postgresql:17, clickhouse-server:24.8-alpine, valkey:8.1-alpine, ...) copied from ten's image cache into
# the Vagrant kubeadm node's containerd, so the copy runs the bits ten runs - a fresh pull of the tag can be a newer
# build (for postgresql:17, the source the PostgreSQL 18 step's pg_upgrade starts from). A read-only export streamed
# over ssh, nothing written on ten. With pullPolicy IfNotPresent the kubelet then uses it.
#
# The list: tests/ansible/upgrade/prod-inventory.txt's image lines. An image ten does not hold (a job's, kept a day) is
# named and left to the kubelet's pull. Each one copied goes to .upgrade/floating-digests.txt ("<image> <digest>"):
# the full run's proof carries it, and production's steps refuse once ten's tag names another build
# (scripts/upgrade-production.py).
#
# Usage: scripts/vagrant-preload-floating.sh
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
cd "$ops"
mapfile -t images < <(awk '$1 == "image" {print $2 ":" $3}' tests/ansible/upgrade/prod-inventory.txt | python3 -c '
import re, sys
for line in sys.stdin:
    ref = line.strip()
    name, tag = ref.rsplit(":", 1)
    if name.startswith("git.pmon.dev/schnappy/"):
        continue  # scripts/vagrant-preload-images.sh
    if tag != "latest" and not re.fullmatch(r"v?\d+(\.\d+)?(-[a-z0-9]+)?", tag):
        continue  # a full version: the same bits wherever pulled
    parts = name.split("/")
    if "." not in parts[0] and ":" not in parts[0]:
        name = "docker.io/" + ("library/" + name if len(parts) == 1 else name)
    print(name + ":" + tag)')
[ "${#images[@]}" -gt 0 ] || { echo "no floating images in the inventory"; exit 1; }
mkdir -p .upgrade
digests=.upgrade/floating-digests.txt
: > "$digests.new"
missing=0
for img in "${images[@]}"; do
  # an image reference only (registry/path:tag), never anything a remote shell would read as more than a word: it goes
  # into commands run as root on ten
  if ! [[ $img =~ ^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9._-]+)?$ ]]; then
    echo "REFUSED: '$img' is not an image reference"; exit 1
  fi
  # shellcheck disable=SC2029  # $img is meant to expand here, into the remote command
  ten=$(ssh "${TEN_SSH:-sm@192.168.11.2}" "sudo -n ctr -n k8s.io images ls name=='$img'" \
    | awk -v i="$img" '$1 == i {print $3}')
  if [ -n "$ten" ]; then
    # shellcheck disable=SC2029
    ssh "${TEN_SSH:-sm@192.168.11.2}" "sudo -n ctr -n k8s.io images export --platform linux/amd64 - '$img'" \
      | vagrant ssh kubeadm -c 'sudo ctr -n k8s.io images import --platform linux/amd64 --digests -' > /dev/null 2>&1
    # the copy now holds ten's image under the tag: the same digest, or this fails
    copy=$(vagrant ssh kubeadm -c "sudo ctr -n k8s.io images ls name=='$img'" 2>/dev/null | tr -d '\r' \
      | awk -v i="$img" '$1 == i {print $3}')
    [ "$copy" = "$ten" ] || { echo "$img: the copy has ${copy:-nothing}, ten $ten"; exit 1; }
    echo "== $img: ten's $ten"
    echo "$img $ten" >> "$digests.new"
  else
    echo "== $img: not in ten's cache - left to the kubelet's pull"
    missing=$((missing + 1))
  fi
done
mv "$digests.new" "$digests"
echo "floating images: ${#images[@]}, from ten $(( ${#images[@]} - missing )), not on ten $missing"
