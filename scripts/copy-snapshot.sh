#!/usr/bin/env bash
# copy-snapshot.sh - the Vagrant copy's base layers built once and reverted per run (plan 125). The snapshot is the
# copy as test:copy:build leaves it at its cold-boot halt: the Pis and the node built (_copy:base - Debian, the Pi stack
# at production's versions, Gluster, the store, keepalived, the node's kubeadm and hardening), Argo not yet on it. A
# run reverts to it and boots it cold, as the build's own cold boot, then builds the Argo layer as the build does
# (test:copy:argo: Vault seeded, main mirrored, every app settled, the checks' data seeded, its records written fresh) -
# no state of a former run (a mirror push, a restart history, a CronJob's missed run, the Mimir data a check seeds) is
# in the snapshot to tell it from a build. Saves the base's ~21 min of the build's 49.
#   save    in test:copy:build, at its cold-boot halt: every domain shut off by its own shutdown (a forced power-off is
#           no snapshot - refused), one internal libvirt snapshot each, the record last. Never fails the build: a save
#           that fails drops what it made and says so - the run goes on.
#   revert  in test:copy:ready: stale - exit 3, nothing touched (the caller builds); else every domain halted and
#           reverted, left shut off for the caller's cold boot. Any failure after the stale check drops the snapshot and
#           exits 3: the same run builds, never a broken snapshot reused for a day.
#   status  the record against now (read-only: production's inventory as last read, not read again here).
#   drop    the copy destroyed (vagrant-libvirt deletes a domain's snapshots first), the record gone: the next run builds.
# Stale: no record; older than COPY_SNAPSHOT_MAX_AGE (default 24 h); production's inventory or the Pis' versions as the
# run read them (test:copy:inventory, before this) differ from the build's; the files that build the base differ (the
# Vagrantfile, deploy/ansible, the Pis' apt pins, the Taskfile's _copy:base and _vagrant:pi-* steps - the working tree's);
# a domain or its snapshot missing. COPY_SNAPSHOT=off: never saved, every run builds. The domains by the UUIDs vagrant
# holds (.vagrant/machines/<m>/libvirt/id) - never by a name another checkout's VMs could carry.
#
# Usage: scripts/copy-snapshot.sh save | revert | status | drop
# Env:   COPY_SNAPSHOT (off), COPY_SNAPSHOT_MAX_AGE (seconds), VIRSH (default "virsh -c qemu:///system"),
#        VAGRANT (default vagrant), COPY_DIR (default .copy)
set -euo pipefail
cd "$(dirname "$0")/.."
SNAP=copy-base
C=${COPY_DIR:-.copy}
D=$C/snapshot
MAX_AGE=${COPY_SNAPSHOT_MAX_AGE:-86400}
read -r -a VIRSH <<< "${VIRSH:-virsh -c qemu:///system}"
VAGRANT=${VAGRANT:-vagrant}
MACHINES=(kubeadm pi1 pi2)
say() { echo "copy-snapshot: $*"; }
die() { say "$*"; exit 1; }
v() { timeout 30 "${VIRSH[@]}" "$@"; }  # a libvirt that hangs fails here, as copy-host-guard.sh's calls do

uuid() {  # the libvirt domain vagrant holds for a machine; none: not created
  local f=.vagrant/machines/$1/libvirt/id
  [ -s "$f" ] && cat "$f"
}
inv_id() { cat tests/ansible/copy/prod-inventory.txt tests/ansible/copy/pi-versions.yml | sha256sum | cut -d' ' -f1; }
tree_id() {  # what builds the base: its files (the working tree's) and the Taskfile's base steps
  {
    git ls-files -z -- Vagrantfile deploy/ansible tests/ansible/copy/pi-apt-versions.yml tests/ansible/vagrant-only.yml \
      tests/ansible/vagrant-only-play.yml tests/ansible/isolate-pis.yml scripts/copy-host-guard.sh | xargs -0 sha256sum
    python3 -c 'import sys, yaml, json
t = yaml.safe_load(open("Taskfile.yml"))["tasks"]
print(json.dumps({k: v for k, v in t.items() if k == "_copy:base" or k.startswith("_vagrant:pi")}, sort_keys=True))'
  } | sha256sum | cut -d' ' -f1
}
snap_state() {  # has | none | error (a libvirt that does not answer is no "missing")
  local out
  out=$(v snapshot-list "$1" --name 2>&1) || { echo error; return; }
  if printf '%s\n' "$out" | grep -qxF "$SNAP"; then echo has; else echo none; fi
}
stale() {  # why the snapshot cannot be reused, one a line; nothing: fresh; exit 1: libvirt not answering
  [ "${COPY_SNAPSHOT:-on}" != off ] || { echo "COPY_SNAPSHOT=off"; return; }
  [ -f "$D/meta" ] || { echo "no snapshot record"; return; }
  local created inv tree m u s
  created=$(awk '$1 == "created" { print $2 }' "$D/meta")
  inv=$(awk '$1 == "inventory" { print $2 }' "$D/meta"); tree=$(awk '$1 == "tree" { print $2 }' "$D/meta")
  [ -n "$created" ] && [ $(($(date +%s) - created)) -le "$MAX_AGE" ] || echo "older than $MAX_AGE s"
  [ "$inv" = "$(inv_id)" ] || echo "production's inventory or the Pis' versions moved since it was built"
  [ "$tree" = "$(tree_id)" ] || echo "the files that build the base changed since"
  for m in "${MACHINES[@]}"; do
    u=$(uuid "$m") || { echo "$m not created"; continue; }
    [ "$(awk -v m="$m" '$1 == "domain" && $2 == m { print $3 }' "$D/meta")" = "$u" ] || { echo "$m is another domain than the snapshot's"; continue; }
    s=$(snap_state "$u")
    [ "$s" != error ] || { say "libvirt does not answer for $m - nothing judged" >&2; exit 1; }
    [ "$s" = has ] || echo "$m's snapshot missing"
  done
}
drop_record() { rm -rf "$D"; }

case "${1:-}" in
  save)
    [ "${COPY_SNAPSHOT:-on}" != off ] || { say "COPY_SNAPSHOT=off - not saved"; exit 0; }
    scripts/copy-lock.sh
    drop_record
    saved=()
    fail() {  # a save that fails never fails the build: what it made dropped, said, the run goes on
      local u
      for u in "${saved[@]}"; do v snapshot-delete "$u" "$SNAP" > /dev/null 2>&1 || say "the snapshot of $u not deleted - delete it by hand"; done
      drop_record
      say "NOT SAVED: $* - the next run builds again"; exit 0
    }
    for m in "${MACHINES[@]}"; do
      u=$(uuid "$m") || fail "$m not created"
      st=$(v domstate "$u" --reason) || fail "no domain for $m"
      [ "$st" = "shut off (shutdown)" ] || fail "$m is '$st' - only a domain shut down by itself is snapshotted (a forced power-off is a crash)"
    done
    mkdir -p "$D"
    for m in "${MACHINES[@]}"; do
      u=$(uuid "$m")
      [ "$(snap_state "$u")" != has ] || v snapshot-delete "$u" "$SNAP" > /dev/null || fail "$m's old snapshot not deleted"
      v snapshot-create-as "$u" "$SNAP" --atomic > /dev/null || fail "$m's snapshot not made"
      saved+=("$u")
      echo "domain $m $u" >> "$D/meta.tmp"
    done
    # the record last: a save cut short leaves none - stale, never half a snapshot taken for whole
    printf 'created %s\ninventory %s\ntree %s\n' "$(date +%s)" "$(inv_id)" "$(tree_id)" >> "$D/meta.tmp"
    mv "$D/meta.tmp" "$D/meta"
    say "saved $(date -u +%FT%TZ): the base of ${MACHINES[*]}" ;;
  status)
    why=$(stale)
    if [ -z "$why" ]; then say "fresh"; exit 0; fi
    say "stale: $(echo "$why" | paste -sd ';' | sed 's/;/; /g')"; exit 3 ;;
  revert)
    scripts/copy-lock.sh
    why=$(stale)
    if [ -n "$why" ]; then say "stale - the copy is built: $(echo "$why" | paste -sd ';' | sed 's/;/; /g')"; exit 3; fi
    broken() { say "REVERT FAILED: $* - the snapshot dropped, the copy is built"; drop_record; exit 3; }
    "$VAGRANT" halt || broken "the halt failed"
    for m in "${MACHINES[@]}"; do
      u=$(uuid "$m")
      st=$(v domstate "$u") || broken "no domain for $m"
      [ "$st" = "shut off" ] || broken "$m is '$st' after the halt"
      v snapshot-revert "$u" "$SNAP" || broken "$m not reverted"
      [ "$(v domstate "$u")" = "shut off" ] || broken "$m not shut off after its revert"
    done
    say "reverted: the base as built $(date -u -d "@$(awk '$1 == "created" { print $2 }' "$D/meta")" +%FT%TZ) - shut off for the cold boot" ;;
  drop)
    scripts/copy-lock.sh
    drop_record
    "$VAGRANT" destroy -f
    say "dropped: the next run builds" ;;
  *) echo "usage: $0 save | revert | status | drop" >&2; exit 2 ;;
esac
