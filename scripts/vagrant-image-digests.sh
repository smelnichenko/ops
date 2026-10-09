#!/usr/bin/env bash
# vagrant-image-digests.sh - the images the Vagrant copy runs, by digest: "<name> <tag> <digest>" per line - pinned as
# its workloads' specs name them (a chart that pins in two keys, tag: <tag>@sha256:..., composes the full reference
# only there), else by tag at the digest its running container runs (its status' imageID: a registry's digest; an image
# imported with none, the copy's preload of production's own builds, has no such digest - skipped). The full run keeps
# each step's (.upgrade/step-digests/<step>.txt, right after the step - its proof is recorded a step later), the step's
# proof records its own images' digests, and production's pre-pull pulls by them and points the tag at them.
# With VAGRANT_SSH_CONFIG set, plain ssh with that config; else vagrant ssh. Bounded both ways: keep-alives on the
# connection (Vagrant's own config sets none - a stalled VM held the full run, which reads this after every step) and
# the API server's request timeout.
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
cd "$ops"
alive=(-o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ConnectTimeout=30)
on() {
  if [ -n "${VAGRANT_SSH_CONFIG:-}" ]; then ssh -F "$VAGRANT_SSH_CONFIG" "${alive[@]}" "$1" "$2"
  else vagrant ssh "$1" -c "$2" -- "${alive[@]}"; fi
}
on kubeadm 'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf --request-timeout=60s get pods,cronjobs -A -o json' \
  | tr -d '\r' \
  | python3 -c '
import json, sys
seen = set()
for o in json.load(sys.stdin)["items"]:
    spec = o["spec"]["jobTemplate"]["spec"]["template"]["spec"] if o["kind"] == "CronJob" else o["spec"]
    status = o.get("status") or {}
    running = {s.get("name"): s.get("imageID") or "" for s in status.get("containerStatuses", [])
               + status.get("initContainerStatuses", [])}
    for c in spec.get("containers", []) + spec.get("initContainers", []):
        ref, _, digest = c["image"].partition("@")
        if not digest:  # by tag: the digest its container runs, a registry digest only
            digest = running.get(c.get("name"), "").partition("@")[2]
        if not digest.startswith("sha256:"):
            continue
        name, tag = (ref.rsplit(":", 1) if ":" in ref.split("/")[-1] else (ref, "latest"))
        if (name, tag, digest) not in seen:
            seen.add((name, tag, digest))
            print(name, tag, digest)'
