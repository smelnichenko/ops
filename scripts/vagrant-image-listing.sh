#!/usr/bin/env bash
# vagrant-image-listing.sh - the images the Vagrant copy's node holds, crictl's own listing (JSON: each image's ID and
# the digests it is named by). The full run keeps it beside each step's digests (.upgrade/step-digests/<step>.images.json,
# right after the step); the step's proof records from it the image ID behind each of its proven digests: the copy had
# our registry's images imported (docker save re-packs the manifest - another digest, the same build), and production's
# done then judges those by the ID ten runs. With VAGRANT_SSH_CONFIG set, plain ssh with that config; else vagrant ssh.
# Bounded as vagrant-image-digests.sh is: keep-alives on the connection.
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
cd "$ops"
alive=(-o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ConnectTimeout=30)
if [ -n "${VAGRANT_SSH_CONFIG:-}" ]; then ssh -F "$VAGRANT_SSH_CONFIG" "${alive[@]}" kubeadm 'sudo crictl images --digests -o json'
else vagrant ssh kubeadm -c 'sudo crictl images --digests -o json' -- "${alive[@]}"; fi | tr -d '\r'
