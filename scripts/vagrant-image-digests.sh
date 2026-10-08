#!/usr/bin/env bash
# vagrant-image-digests.sh - the images the Vagrant copy runs pinned by digest, as its workloads' specs name them:
# "<name> <tag> <digest>" per line. A chart that pins in two keys (tag: <tag>@sha256:...) composes the full reference
# only there. The full run keeps each step's (.upgrade/step-digests/<step>.txt, right after the step - its proof is
# recorded a step later), the step's proof records its own images' digests, and production's pre-pull pulls by them.
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
    for c in spec.get("containers", []) + spec.get("initContainers", []):
        ref, _, digest = c["image"].partition("@")
        if not digest.startswith("sha256:"):
            continue
        name, tag = (ref.rsplit(":", 1) if ":" in ref.split("/")[-1] else (ref, "latest"))
        if (name, tag, digest) not in seen:
            seen.add((name, tag, digest))
            print(name, tag, digest)'
