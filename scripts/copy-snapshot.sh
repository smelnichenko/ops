#!/usr/bin/env bash
# copy-snapshot.sh - the Vagrant copy's base layers built once and reverted per run. The snapshot is the copy as
# test:copy:build leaves it at its cold-boot halt: the Pis and the node built (_copy:base - Debian, the Pi stack at
# production's versions, Gluster, the store, keepalived, the node's kubeadm and hardening), Argo not yet on it. A run
# reverts to it and boots it cold, as the build's own cold boot, then builds the Argo layer as the build does
# (test:copy:argo: Vault seeded, main mirrored, every app settled, the checks' data seeded, its records written fresh) -
# no state of a former run (a mirror push, a restart history, a CronJob's missed run, the Mimir data a check seeds) is
# in the snapshot to tell it from a build. Saves the base's ~21 min of the build's 49.
#   begin    _copy:base, after its destroy: the record dropped, the host's disk checked, what builds the base hashed NOW
#            (production's inventory as this build read it, the files) into pending - a file changed while the base
#            builds is no file the base was built from.
#   based    _copy:base's last step: the base this build made is complete (save refuses without it - a copy halted
#            after a run, its Argo layer on it, is never saved as a base).
#   save     test:copy:build, at its cold-boot halt: every domain shut off by its own shutdown (a forced power-off is no
#            snapshot - refused), the hashes still pending's, one internal libvirt snapshot each; the record UNPROVEN.
#            Never fails the build: a save that fails drops what it made and says so - the run goes on.
#   proven   test:copy:build's last step: the base booted cold and the Argo layer built on it (its inventory against
#            production's) - the record reusable from now. A build that failed on its base leaves none.
#   revert   test:copy:ready: stale - exit 3, nothing touched (the caller builds); else every domain halted, any managed
#            save image removed, reverted, left shut off for the caller's cold boot. A step that fails drops the record
#            and exits 3 (the same run builds); libvirt not answering in time is no verdict - the record dropped, exit 1.
#   forget   the record dropped, said (test:copy:ready when the reverted base did not come up: never reused for a day).
#   used     the copy halted after a run (the cycle): its Argo layer and the last unit on it - change, check and playbook
#            refuse it (unused) until ready or a build lays a fresh Argo layer (layered).
#   status   the record against now (read-only: production's inventory as last read, not read again here).
#   drop     the copy destroyed (vagrant-libvirt deletes a domain's snapshots first), the record gone: the next run builds.
#   disk     the host's free space on libvirt's pool against COPY_DISK_NEED_GB (exit 1 short).
# Stale: no proven record; older than COPY_SNAPSHOT_MAX_AGE (default 24 h); production's inventory lines the base holds
# (os, k8s, pkg, containerd-unit, pi, kube-system's helm releases) or the Pis' versions as the run read them differ from
# the build's; the files that build the base differ (the Vagrantfile, deploy/ansible - untracked files too - the Pis' apt
# pins and their script, the Taskfile's _copy:base, _vagrant:pi-* and test:copy:build); a domain or its snapshot gone, or
# another domain under a machine's name; the host's disk short; COPY_SNAPSHOT=off (never saved, every run builds). The
# machines are the Vagrantfile's; the domains by the UUIDs vagrant holds (.vagrant/machines/<m>/libvirt/id) - never by a
# name another checkout's VMs could carry. A hash that cannot be computed fails closed (stale, NOT SAVED).
#
# Usage: scripts/copy-snapshot.sh begin | based | save | proven | revert | forget <why> | used | layered | unused |
#                                 status | drop | disk
# Env:   COPY_SNAPSHOT (off), COPY_SNAPSHOT_MAX_AGE (seconds), COPY_DISK_NEED_GB (350: three 100 GiB disks at full size
#        and their snapshots), VIRSH (default "virsh -c qemu:///system"), VAGRANT (default vagrant), COPY_DIR (.copy),
#        COPY_POOL_PATH (libvirt's default pool's path; read from libvirt when unset)
set -euo pipefail
cd "$(dirname "$0")/.."
SNAP=copy-base
C=${COPY_DIR:-.copy}
D=$C/snapshot
MAX_AGE=${COPY_SNAPSHOT_MAX_AGE:-86400}
NEED_GB=${COPY_DISK_NEED_GB:-350}
read -r -a VIRSH <<< "${VIRSH:-virsh -c qemu:///system}"
VAGRANT=${VAGRANT:-vagrant}
say() { echo "copy-snapshot: $*"; }
die() { say "$*"; exit 1; }
v() { timeout 30 "${VIRSH[@]}" "$@"; }        # a read: a libvirt that hangs fails here, as copy-host-guard.sh's calls do
vlong() { timeout 600 "${VIRSH[@]}" "$@"; }   # a snapshot made, reverted or deleted: a large qcow2 takes its time
# the Vagrantfile's machines (its define lines, as copy-host-guard.sh reads them)
mapfile -t MACHINES < <(sed -n 's/^[[:space:]]*config\.vm\.define[[:space:]]*"\([A-Za-z0-9_-]*\)".*/\1/p' Vagrantfile)
[ "${#MACHINES[@]}" -gt 0 ] || die "no machine in the Vagrantfile"

uuid() {  # the libvirt domain vagrant holds for a machine; none: not created
  local f=.vagrant/machines/$1/libvirt/id
  [ -s "$f" ] && cat "$f"
}
inv_id() {  # the inventory lines the base holds, and the Pis' versions
  local lines
  lines=$(awk '$1 ~ /^(os|k8s|pkg|containerd-unit|pi)$/ || ($1 == "helm" && $2 ~ /^kube-system\//)' tests/ansible/copy/prod-inventory.txt) \
    || return 1
  [ -n "$lines" ] || return 1
  { printf '%s\n' "$lines"; cat tests/ansible/copy/pi-versions.yml; } | sha256sum | cut -d' ' -f1
}
base_files() {  # the files that build the base, each its hash and path (the working tree's, untracked too)
  git ls-files -z --cached --others --exclude-standard -- Vagrantfile deploy/ansible tests/ansible/copy/pi-apt-versions.yml \
    scripts/pi-apt-pin.sh tests/ansible/vagrant-only.yml tests/ansible/vagrant-only-play.yml tests/ansible/isolate-pis.yml \
    scripts/copy-host-guard.sh | sort -zu | xargs -0 sha256sum
}
base_steps() {  # the Taskfile's base steps, as JSON
  python3 -c 'import sys, yaml, json
t = yaml.safe_load(open("Taskfile.yml"))["tasks"]
print(json.dumps({k: v for k, v in t.items() if k in ("_copy:base", "test:copy:build") or k.startswith("_vagrant:pi")}, sort_keys=True))'
}
tree_id() {  # what builds the base: its files and the Taskfile's base steps, one hash (as every saved record holds it)
  local files steps
  files=$(base_files) || return 1
  steps=$(base_steps) || return 1
  [ -n "$files" ] && [ -n "$steps" ] || return 1
  printf '%s\n%s\n' "$files" "$steps" | sha256sum | cut -d' ' -f1
}
tree_list() {  # the same, a line each: every file's hash and path, and the base steps' hash as "Taskfile.yml:base-steps" -
  # kept beside the record, so a stale verdict names what changed
  local files steps
  files=$(base_files) || return 1
  steps=$(base_steps) || return 1
  [ -n "$files" ] && [ -n "$steps" ] || return 1
  printf '%s\n%s  Taskfile.yml:base-steps\n' "$files" "$(printf '%s\n' "$steps" | sha256sum | cut -d' ' -f1)"
}
tree_changed() {  # the files that build the base and differ from the record's list ($1: the list's file) - at most five
  local changed n
  changed=$(diff <(sort "$1") <(tree_list | sort) | awk '/^[<>]/ {print $3}' | sort -u)
  n=$(printf '%s\n' "$changed" | grep -c .)
  printf '%s%s' "$(printf '%s\n' "$changed" | head -5 | paste -sd ',' | sed 's/,/, /g')" "$([ "$n" -gt 5 ] && echo " (and $((n - 5)) more)")"
}
pool_path() {
  [ -z "${COPY_POOL_PATH:-}" ] || { echo "$COPY_POOL_PATH"; return 0; }
  v pool-dumpxml default | sed -n 's#.*<path>\(.*\)</path>.*#\1#p' | head -1
}
disk_short() {  # empty: enough; else why (the free space, the need)
  local p free
  p=$(pool_path) && [ -n "$p" ] || { echo "libvirt's pool path not read"; return 0; }
  free=$(df -BG --output=avail "$p" | tail -1 | tr -dc 0-9) && [ -n "$free" ] || { echo "the free space of $p not read"; return 0; }
  [ "$free" -ge "$NEED_GB" ] || echo "the host's disk short: ${free} GB free on $p, ${NEED_GB} GB needed"
}
snap_state() {  # has | none | gone (no such domain) - libvirt answering is checked before (uri)
  local out
  if ! out=$(v snapshot-list "$1" --name 2>&1); then
    case "$out" in *"ailed to get domain"*|*"o domain with matching"*) echo gone ;; *) echo error ;; esac
    return
  fi
  if grep -qxF "$SNAP" <<< "$out"; then echo has; else echo none; fi
}
stale() {  # why the snapshot cannot be reused, one a line; nothing: fresh; exit 1: libvirt not answering
  [ "${COPY_SNAPSHOT:-on}" != off ] || { echo "COPY_SNAPSHOT=off"; return; }
  [ -f "$D/meta" ] || { [ -f "$D/meta.unproven" ] && echo "its base never proven (the build that saved it failed after)" \
    || echo "no snapshot record"; return; }
  v uri > /dev/null 2>&1 || { say "libvirt does not answer - nothing judged" >&2; exit 1; }
  local created inv tree m u s now_inv now_tree
  created=$(awk '$1 == "created" { print $2 }' "$D/meta")
  inv=$(awk '$1 == "inventory" { print $2 }' "$D/meta"); tree=$(awk '$1 == "tree" { print $2 }' "$D/meta")
  [ -n "$created" ] && [ $(($(date +%s) - created)) -le "$MAX_AGE" ] || echo "older than $MAX_AGE s"
  if now_inv=$(inv_id); then [ "$inv" = "$now_inv" ] || echo "production's inventory or the Pis' versions moved since it was built"
  else echo "production's inventory not hashed"; fi
  if now_tree=$(tree_id); then
    if [ "$tree" != "$now_tree" ]; then
      if [ -f "$D/tree.list" ]; then echo "the files that build the base changed since: $(tree_changed "$D/tree.list")"
      else echo "the files that build the base changed since"; fi
    fi
  else echo "the files that build the base not hashed"; fi
  for m in "${MACHINES[@]}"; do
    u=$(uuid "$m") || { echo "$m not created"; continue; }
    [ "$(awk -v m="$m" '$1 == "domain" && $2 == m { print $3 }' "$D/meta")" = "$u" ] || { echo "$m is another domain than the snapshot's"; continue; }
    s=$(snap_state "$u")
    case "$s" in
      has) ;;
      gone) echo "$m's domain gone" ;;
      error) say "libvirt does not answer for $m - nothing judged" >&2; exit 1 ;;
      *) echo "$m's snapshot missing" ;;
    esac
  done
  disk_short
}
drop_record() { rm -rf "$D"; }

case "${1:-}" in
  begin)
    drop_record
    why=$(disk_short)
    [ -z "$why" ] || die "$why - not built"
    mkdir -p "$D"
    inv=$(inv_id) || { say "production's inventory not hashed - this base will not be saved"; exit 0; }
    tree=$(tree_id) || { say "the files that build the base not hashed - this base will not be saved"; exit 0; }
    printf 'inventory %s\ntree %s\n' "$inv" "$tree" > "$D/pending"
    tree_list > "$D/pending.tree" || rm -f "$D/pending.tree"
    say "begun: what builds this base hashed" ;;
  based)
    [ -f "$D/pending" ] || { say "no pending base (its begin did not hash it) - it will not be saved"; exit 0; }
    echo "based $(date +%s)" >> "$D/pending"
    say "the base built" ;;
  save)
    [ "${COPY_SNAPSHOT:-on}" != off ] || { say "COPY_SNAPSHOT=off - not saved"; exit 0; }
    scripts/copy-lock.sh
    saved=()
    fail() {  # a save that fails never fails the build: what it made dropped, said, the run goes on
      local u
      for u in "${saved[@]}"; do vlong snapshot-delete "$u" "$SNAP" > /dev/null 2>&1 || say "the snapshot of $u not deleted - delete it by hand"; done
      drop_record
      say "NOT SAVED: $* - the next run builds again"; exit 0
    }
    [ -f "$D/pending" ] && grep -q '^based ' "$D/pending" || fail "no base this build made (begin and based in _copy:base) - a copy after a run is no base"
    inv=$(inv_id) || fail "production's inventory not hashed"
    tree=$(tree_id) || fail "the files that build the base not hashed"
    [ "inventory $inv" = "$(grep '^inventory ' "$D/pending")" ] || fail "production's inventory moved while the base was built"
    [ "tree $tree" = "$(grep '^tree ' "$D/pending")" ] || fail "the files that build the base changed while it was built"
    for m in "${MACHINES[@]}"; do
      u=$(uuid "$m") || fail "$m not created"
      st=$(v domstate "$u" --reason) || fail "no domain for $m"
      [ "$st" = "shut off (shutdown)" ] || fail "$m is '$st' - only a domain shut down by itself is snapshotted (a forced power-off is a crash)"
    done
    rm -f "$D/meta" "$D/meta.unproven" "$D/meta.tmp" "$D/tree.list" "$D/tree.unproven"
    for m in "${MACHINES[@]}"; do
      u=$(uuid "$m")
      s=$(snap_state "$u")
      [ "$s" != error ] || fail "libvirt does not answer for $m"
      [ "$s" != has ] || vlong snapshot-delete "$u" "$SNAP" > /dev/null || fail "$m's old snapshot not deleted"
      vlong snapshot-create-as "$u" "$SNAP" --atomic > /dev/null || fail "$m's snapshot not made"
      saved+=("$u")
      echo "domain $m $u" >> "$D/meta.tmp"
    done
    # the record last, and unproven: a save cut short leaves none; a base whose cold boot or Argo layer fails is never
    # reused (proven, at the build's end, makes it the record)
    printf 'created %s\ninventory %s\ntree %s\n' "$(date +%s)" "$inv" "$tree" >> "$D/meta.tmp"
    mv "$D/meta.tmp" "$D/meta.unproven"
    [ ! -f "$D/pending.tree" ] || mv "$D/pending.tree" "$D/tree.unproven"
    rm -f "$D/pending"
    say "saved $(date -u +%FT%TZ): the base of ${MACHINES[*]} - unproven until this build's Argo layer is up" ;;
  proven)
    [ -f "$D/meta.unproven" ] || { say "no unproven snapshot (none saved by this build) - nothing to prove"; exit 0; }
    mv "$D/meta.unproven" "$D/meta"
    [ ! -f "$D/tree.unproven" ] || mv "$D/tree.unproven" "$D/tree.list"
    say "proven: the base booted cold and the Argo layer built on it - reused for $MAX_AGE s" ;;
  status)
    why=$(stale)
    if [ -z "$why" ]; then say "fresh"; exit 0; fi
    say "stale: $(echo "$why" | paste -sd ';' | sed 's/;/; /g')"; exit 3 ;;
  revert)
    scripts/copy-lock.sh
    why=$(stale)
    if [ -n "$why" ]; then say "stale - the copy is built: $(echo "$why" | paste -sd ';' | sed 's/;/; /g')"; exit 3; fi
    broken() { say "REVERT FAILED: $* - the snapshot dropped, the copy is built"; drop_record; exit 3; }
    busy() { say "REVERT NOT JUDGED: libvirt did not answer in time ($*) - the snapshot dropped; wait for libvirt, then any run builds"; drop_record; exit 1; }
    "$VAGRANT" halt || broken "the halt failed"
    for m in "${MACHINES[@]}"; do
      u=$(uuid "$m")
      st=$(v domstate "$u") || busy "the state of $m"
      [ "$st" = "shut off" ] || broken "$m is '$st' after the halt"
      # a managed save image (libvirt-guests saved the domain at the host's shutdown) would start the domain from it
      v managedsave-remove "$u" > /dev/null || busy "the managed save of $m"
      rc=0
      vlong snapshot-revert "$u" "$SNAP" || rc=$?
      [ "$rc" -ne 124 ] || busy "the revert of $m"
      [ "$rc" -eq 0 ] || broken "$m not reverted"
      st=$(v domstate "$u") || busy "the state of $m after its revert"
      [ "$st" = "shut off" ] || broken "$m not shut off after its revert ('$st')"
    done
    say "reverted: the base as built $(date -u -d "@$(awk '$1 == "created" { print $2 }' "$D/meta")" +%FT%TZ) - shut off for the cold boot" ;;
  forget)
    drop_record
    say "the snapshot forgotten: ${2:-no reason given} - the next run builds" ;;
  used)
    mkdir -p "$C"
    date -u +%FT%TZ > "$C/copy-used"
    say "the copy marked used: change, check and playbook refuse it until a fresh Argo layer (ready or build)" ;;
  layered)
    rm -f "$C/copy-used" ;;
  unused)
    [ ! -f "$C/copy-used" ] || die "REFUSED: the copy was halted after a run ($(cat "$C/copy-used")) - its Argo layer and the last unit on it; task test:copy:ready first" ;;
  drop)
    scripts/copy-lock.sh
    drop_record
    rm -f "$C/copy-used"
    "$VAGRANT" destroy -f
    say "dropped: the next run builds" ;;
  disk)
    why=$(disk_short)
    [ -z "$why" ] || die "$why"
    say "the host's disk: enough (${NEED_GB} GB needed)" ;;
  *) echo "usage: $0 begin | based | save | proven | revert | forget <why> | used | layered | unused | status | drop | disk" >&2; exit 2 ;;
esac
