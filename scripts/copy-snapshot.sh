#!/usr/bin/env bash
# copy-snapshot.sh - the Vagrant copy built once and reverted per run (plan 125): a build takes 49 min, a revert ~5.
#   save    at the end of test:copy:build, the copy as built (no change on it): the VMs halted, one internal libvirt
#           snapshot per domain (disk-only, the domains shut off), the build's records (.copy/: copy-built, copy-refs,
#           argo-apps.txt, scrape-pools.json, vagrant-inventory-build.txt, vagrant-inventory.txt) and what it was built
#           to - its age, production's inventory and the Pis' versions, ops' copy-building files - in .copy/snapshot/;
#           then the VMs up again and ready.
#   status  fresh, or stale and why (exit 3); production's inventory read now (scripts/production-inventory.sh - its
#           tracked record rewritten, as the build does).
#   revert  at a run's start: stale - exit 3, nothing touched (the caller builds); else the VMs halted, each domain
#           reverted, booted cold (as the build's last boot), ready, the records back, Argo settled; infra's or
#           platform's main moved since (CD's promotions do): main mirrored, its images preloaded, settled, the
#           records rewritten - the run's change is then its own diff.
#   drop    the copy destroyed (vagrant-libvirt deletes a domain's snapshots first), the record gone: the next run builds.
# Stale: no record; older than COPY_SNAPSHOT_MAX_AGE (default 24 h - the copy's clocks, short-lived tokens, leases);
# production's inventory or the Pis' versions read now differ from the snapshot's (production moved: the copy must be
# built at it); ops' copy-building files differ (the Vagrantfile, deploy/ansible, the copy's own playbooks and scripts -
# the working tree's, as the build ran them); a domain or its snapshot missing. A stale snapshot is never reused.
#
# Usage: scripts/copy-snapshot.sh save | status | revert | drop
# Env:   COPY_SNAPSHOT_MAX_AGE (seconds); VIRSH (default "virsh -c qemu:///system"); VAGRANT (default vagrant);
#        COPY_ANSIBLE (default deploy/ansible/venv/bin/ansible-playbook); COPY_INVENTORY_READ (default
#        scripts/production-inventory.sh); COPY_DIR (default .copy)
set -euo pipefail
cd "$(dirname "$0")/.."
SNAP=copy-built
C=${COPY_DIR:-.copy}
D=$C/snapshot
MAX_AGE=${COPY_SNAPSHOT_MAX_AGE:-86400}
read -r -a VIRSH <<< "${VIRSH:-virsh -c qemu:///system}"
VAGRANT=${VAGRANT:-vagrant}
PLAY=${COPY_ANSIBLE:-deploy/ansible/venv/bin/ansible-playbook}
INV_READ=${COPY_INVENTORY_READ:-scripts/production-inventory.sh}
DOMAINS=(ops_kubeadm ops_pi1 ops_pi2)
RECORDS=(copy-built copy-refs argo-apps.txt scrape-pools.json vagrant-inventory-build.txt vagrant-inventory.txt)
say() { echo "copy-snapshot: $*"; }
die() { say "$*"; exit 1; }

inv_id() {  # production's inventory and the Pis' versions as last read (the tracked record)
  cat tests/ansible/copy/prod-inventory.txt tests/ansible/copy/pi-versions.yml | sha256sum | cut -d' ' -f1
}
tree_id() {  # ops' files that build the copy, their working tree's content (the build ran those) - the inventory apart
  git ls-files -z -- Vagrantfile deploy/ansible tests/ansible/copy scripts/copy-*.sh scripts/vagrant-* \
    ':!tests/ansible/copy/prod-inventory.txt' ':!tests/ansible/copy/pi-versions.yml' \
    | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
}
has_snap() { "${VIRSH[@]}" snapshot-list "$1" --name 2> /dev/null | grep -qxF "$SNAP"; }
play() { (cd deploy/ansible && "${PLAY#deploy/ansible/}" -i inventory/vagrant.yml "$@"); }
ready() { play ../../tests/ansible/copy/vms-ready.yml; }
settle() {  # Argo: every app green and every pod ready, the recorded apps exactly
  play ../../tests/ansible/copy/argo-settled.yml -e expect_apps=true -e "restart_stage=revert-$(date +%Y%m%d%H%M%S)" \
    -e restart_quiet=120 -e stable_polls=2 -e poll_seconds=5 "$@"
}

stale() {  # the reasons the snapshot cannot be reused, one a line; nothing: fresh
  [ -f "$D/meta" ] || { echo "no snapshot record"; return; }
  local created inv tree now
  created=$(awk '$1 == "created" { print $2 }' "$D/meta"); inv=$(awk '$1 == "inventory" { print $2 }' "$D/meta")
  tree=$(awk '$1 == "tree" { print $2 }' "$D/meta"); now=$(date +%s)
  [ -n "$created" ] && [ $((now - created)) -le "$MAX_AGE" ] || echo "older than $MAX_AGE s"
  [ "$inv" = "$(inv_id)" ] || echo "production's inventory or the Pis' versions moved since it was built"
  [ "$tree" = "$(tree_id)" ] || echo "ops' copy-building files changed since it was built"
  for d in "${DOMAINS[@]}"; do has_snap "$d" || echo "domain $d or its snapshot missing"; done
  for r in "${RECORDS[@]}"; do [ -f "$D/$r" ] || echo "its record $r missing"; done
}

case "${1:-}" in
  save)
    [ "$(scripts/copy-refs.sh change)" = no ] || die "the copy carries a change - only a copy as built is saved"
    for r in "${RECORDS[@]}"; do [ -f "$C/$r" ] || die "the build's record $C/$r missing - not saved"; done
    rm -rf "$D"; mkdir -p "$D"
    "$VAGRANT" halt
    for d in "${DOMAINS[@]}"; do
      st=$("${VIRSH[@]}" domstate "$d") || die "no domain $d"
      [ "$st" = "shut off" ] || die "$d is '$st' after the halt - not saved"
      if has_snap "$d"; then "${VIRSH[@]}" snapshot-delete "$d" "$SNAP" > /dev/null; fi
      "${VIRSH[@]}" snapshot-create-as "$d" "$SNAP" --atomic > /dev/null
    done
    for r in "${RECORDS[@]}"; do cp "$C/$r" "$D/$r"; done
    # the record last: a save cut short leaves none - stale, never half a snapshot taken for whole
    printf 'created %s\ninventory %s\ntree %s\n' "$(date +%s)" "$(inv_id)" "$(tree_id)" > "$D/meta.tmp"
    mv "$D/meta.tmp" "$D/meta"
    say "saved ($(date -u +%FT%TZ)): ${DOMAINS[*]}"
    "$VAGRANT" up --no-provision
    ready
    settle ;;
  status)
    "$INV_READ" > /dev/null || die "production's inventory not read - nothing judged"
    why=$(stale)
    if [ -z "$why" ]; then say "fresh"; exit 0; fi
    say "stale: $(echo "$why" | paste -sd ';' | sed 's/;/; /g')"; exit 3 ;;
  revert)
    "$INV_READ" > /dev/null || die "production's inventory not read - not reverted"
    why=$(stale)
    if [ -n "$why" ]; then say "stale - the copy is built: $(echo "$why" | paste -sd ';' | sed 's/;/; /g')"; exit 3; fi
    "$VAGRANT" halt
    for d in "${DOMAINS[@]}"; do
      st=$("${VIRSH[@]}" domstate "$d") || die "no domain $d"
      [ "$st" = "shut off" ] || die "$d is '$st' after the halt - not reverted"
      "${VIRSH[@]}" snapshot-revert "$d" "$SNAP"
    done
    for r in "${RECORDS[@]}"; do cp "$D/$r" "$C/$r"; done
    "$VAGRANT" up --no-provision
    ready
    settle
    # main moved since the snapshot (CD's promotions): mirrored and settled now, the build's records with it
    moved=""
    for r in infra platform; do
      [ "$(awk -v r="$r" '$1 == r { print $2 }' "$C/copy-built")" = "$(git -C "../$r" rev-parse main)" ] || moved="$moved $r"
    done
    if [ -n "$moved" ]; then
      say "main moved since the snapshot:$moved - mirrored, settled"
      scripts/copy-main-current.sh ../infra ../platform
      env -i HOME="$HOME" PATH="$PATH" scripts/vagrant-gitops-mirror.py --infra-ref main --platform-ref main
      scripts/vagrant-preload-images.sh ../infra ../platform main main
      scripts/copy-refs.sh set main main
      for r in infra platform; do echo "$r $(git -C "../$r" rev-parse main)"; done > "$C/copy-built"
      settle -e expect_mirror=true
      scripts/vagrant-inventory.sh
      cp "$C/vagrant-inventory.txt" "$C/vagrant-inventory-build.txt"
    fi
    say "reverted: the copy as built $(date -u -d "@$(awk '$1 == "created" { print $2 }' "$D/meta")" +%FT%TZ)${moved:+, main caught up}" ;;
  drop)
    rm -rf "$D"
    "$VAGRANT" destroy -f
    say "dropped: the next run builds" ;;
  *) echo "usage: $0 save | status | revert | drop" >&2; exit 2 ;;
esac
