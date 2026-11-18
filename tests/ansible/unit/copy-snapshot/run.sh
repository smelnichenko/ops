#!/bin/bash
# scripts/copy-snapshot.sh (plan 125) in a scratch ops tree (a git repo of its own: the copy-building files, the
# inventory record, stub copy scripts) against stub vagrant, virsh and ansible-playbook, every call logged:
#   save    refused with a change on the copy, or a domain not shut off after the halt (no record); else halted, one
#           snapshot per domain, the build's records kept, the record written last, up, ready, settled
#   status  fresh; stale - no record, a day old, production's inventory moved, the copy-building files changed, a
#           snapshot gone; the inventory unread is no verdict
#   revert  stale: exit 3, nothing halted or reverted; fresh: halted, each domain reverted, the records back, up, ready,
#           settled - main moved since: mirrored, preloaded, its refs and records rewritten, settled on the mirror
#   drop    the record gone, the copy destroyed
set -u
cd "$(dirname "$0")/../../../.." || exit 1
OPS=$PWD
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
W=$T/ops; mkdir -p "$W/scripts" "$W/tests/ansible/copy" "$W/deploy/ansible/inventory" "$W/.copy" "$T/bin" "$T/infra" "$T/platform"
cp "$OPS/scripts/copy-snapshot.sh" "$W/scripts/"
echo "Vagrant.configure" > "$W/Vagrantfile"
echo "- hosts: all" > "$W/tests/ansible/copy/vms-ready.yml"
echo "- hosts: all" > "$W/tests/ansible/copy/argo-settled.yml"
echo "prod v1" > "$W/tests/ansible/copy/prod-inventory.txt"
echo "pi: 1" > "$W/tests/ansible/copy/pi-versions.yml"
log() { printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$1" "$T"; }
# the copy scripts the revert calls, and the inventory reader
for s in copy-main-current.sh vagrant-gitops-mirror.py vagrant-preload-images.sh vagrant-inventory.sh copy-refs.sh; do
  { log "$s"; case $s in
      copy-refs.sh) echo '[ "$1" = change ] && { cat "'"$T"'/change" 2> /dev/null || echo no; exit 0; }' ;;
      vagrant-inventory.sh) echo "echo inventory-now > $W/.copy/vagrant-inventory.txt" ;;
    esac; echo 'exit 0'; } > "$W/scripts/$s"; chmod +x "$W/scripts/$s"
done
{ log inventory-read; echo 'exit "$(cat '"$T"'/inv.rc 2> /dev/null || echo 0)"'; } > "$T/bin/inv-read"
{ log vagrant; echo 'exit 0'; } > "$T/bin/vagrant"
# virsh: domains in $T/dom/<name>/state, snapshots as files beside it
cat > "$T/bin/virsh" << STUB
#!/bin/sh
echo "virsh \$*" | sed 's/^virsh -c qemu:\/\/\/system /virsh /' >> "$T/calls"
shift 2
D=$T/dom
case "\$1" in
  domstate) [ -d "\$D/\$2" ] || exit 1; cat "\$D/\$2/state" ;;
  snapshot-list) [ -d "\$D/\$2" ] || exit 1; ls "\$D/\$2" | grep '^snap-' | sed 's/^snap-//' ;;
  snapshot-create-as) : > "\$D/\$2/snap-\$3" ;;
  snapshot-delete) rm -f "\$D/\$2/snap-\$3" ;;
  snapshot-revert) [ -f "\$D/\$2/snap-\$3" ] || exit 1 ;;
esac
STUB
{ log ansible-playbook; echo 'exit 0'; } > "$T/bin/ansible-playbook"
chmod +x "$T/bin/"*
dom() { rm -rf "$T/dom"; for d in ops_kubeadm ops_pi1 ops_pi2; do mkdir -p "$T/dom/$d"; echo "${1:-shut off}" > "$T/dom/$d/state"; done; }
git -C "$W" init -q && git -C "$W" add -A && git -C "$W" -c user.name=t -c user.email=t@t commit -qm t
for r in infra platform; do git -C "$T/$r" init -q -b main && git -C "$T/$r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one; done
mkdir -p "$T/repos"; ln -s "$T/infra" "$T/repos/infra" 2> /dev/null; ln -s "$T/platform" "$T/repos/platform" 2> /dev/null
# the script reads ../infra and ../platform beside ops
ln -s "$T/infra" "$T/infra-link" 2> /dev/null
records() { for r in copy-built copy-refs argo-apps.txt scrape-pools.json vagrant-inventory-build.txt vagrant-inventory.txt; do echo "$r as built" > "$W/.copy/$r"; done
  for r in infra platform; do echo "$r $(git -C "$T/$r" rev-parse main)"; done > "$W/.copy/copy-built"; }
run() { rm -f "$T/calls"; if env PATH="$T/bin:$PATH" VIRSH="virsh -c qemu:///system" VAGRANT=vagrant COPY_ANSIBLE="$T/bin/ansible-playbook" \
  COPY_INVENTORY_READ="$T/bin/inv-read" COPY_SNAPSHOT_MAX_AGE="${AGE:-86400}" bash "$W/scripts/copy-snapshot.sh" "$@" > "$T/out" 2>&1; then echo rc=0; else echo "rc=$?"; fi; }
calls() { grep -E "^($1)" "$T/calls" 2> /dev/null | tr '\n' '|'; }

# save
dom; records; echo yes > "$T/change"
check "save with a change on the copy: refused, nothing halted" "$(run save) $(calls 'vagrant|virsh')" "rc=1 "
echo no > "$T/change"; dom running
check "save with a domain still running after the halt: refused, no record" "$(run save) $([ -f "$W/.copy/snapshot/meta" ] && echo meta || echo no-meta)" "rc=1 no-meta"
dom; records
r=$(run save)
check "save: halted, each domain snapshotted, up, ready, settled - in that order" "$r $(calls 'vagrant|virsh snapshot-create-as|ansible-playbook' | sed 's/ -i inventory\/vagrant.yml//g; s/ -e [^|]*//g')" \
  "rc=0 vagrant halt|virsh snapshot-create-as ops_kubeadm copy-built --atomic|virsh snapshot-create-as ops_pi1 copy-built --atomic|virsh snapshot-create-as ops_pi2 copy-built --atomic|vagrant up --no-provision|ansible-playbook ../../tests/ansible/copy/vms-ready.yml|ansible-playbook ../../tests/ansible/copy/argo-settled.yml|"
check "  the build's records kept, the record holding its age, inventory and tree" \
  "$(ls "$W/.copy/snapshot" | tr '\n' ' ') $(awk '{print $1}' "$W/.copy/snapshot/meta" | tr '\n' ' ')" \
  "argo-apps.txt copy-built copy-refs meta scrape-pools.json vagrant-inventory-build.txt vagrant-inventory.txt  created inventory tree "

# status
check "status, just saved: fresh" "$(run status)" "rc=0"
check "  the inventory unread: no verdict (exit 1)" "$(echo 1 > "$T/inv.rc"; run status; rm -f "$T/inv.rc")" "rc=1"
check "  a day old (max age 0): stale, said" "$(AGE=-1 run status) $(grep -c 'older than' "$T/out")" "rc=3 1"
echo "prod v2" > "$W/tests/ansible/copy/prod-inventory.txt"
check "  production's inventory moved: stale" "$(run status) $(grep -c "production's inventory or the Pis' versions moved" "$T/out")" "rc=3 1"
echo "prod v1" > "$W/tests/ansible/copy/prod-inventory.txt"
echo "# changed" >> "$W/Vagrantfile"
check "  ops' copy-building files changed (the working tree's): stale" "$(run status) $(grep -c "copy-building files changed" "$T/out")" "rc=3 1"
git -C "$W" checkout -q -- Vagrantfile
rm "$T/dom/ops_pi2/snap-copy-built"
check "  a domain's snapshot gone: stale, named" "$(run status) $(grep -c 'ops_pi2 or its snapshot missing' "$T/out")" "rc=3 1"
: > "$T/dom/ops_pi2/snap-copy-built"
check "  every one back: fresh" "$(run status)" "rc=0"

# revert
echo "prod v2" > "$W/tests/ansible/copy/prod-inventory.txt"
check "revert, stale: exit 3, nothing halted or reverted" "$(run revert) $(calls 'vagrant|virsh snapshot-revert')" "rc=3 "
echo "prod v1" > "$W/tests/ansible/copy/prod-inventory.txt"
for r in copy-refs argo-apps.txt; do echo "a change's" > "$W/.copy/$r"; done
r=$(run revert)
check "revert, fresh, main unmoved: halted, each reverted, up, ready, settled - no mirror" \
  "$r $(calls 'vagrant|virsh snapshot-revert|vagrant-gitops' | tr -s '|')" \
  "rc=0 vagrant halt|virsh snapshot-revert ops_kubeadm copy-built|virsh snapshot-revert ops_pi1 copy-built|virsh snapshot-revert ops_pi2 copy-built|vagrant up --no-provision|"
check "  the build's records back (a change's gone)" "$(cat "$W/.copy/copy-refs") / $(cat "$W/.copy/argo-apps.txt")" "copy-refs as built / argo-apps.txt as built"
git -C "$T/infra" -c user.name=t -c user.email=t@t commit -q --allow-empty -m two
r=$(run revert)
check "revert, infra's main moved since: mirrored, preloaded, refs set, settled on the mirror, the build's inventory rewritten" \
  "$r $(calls 'copy-main-current|vagrant-gitops|vagrant-preload|copy-refs.sh set|vagrant-inventory' | tr -s '|') $(grep -c 'expect_mirror=true' "$T/calls") $(cat "$W/.copy/vagrant-inventory-build.txt")" \
  "rc=0 copy-main-current.sh ../infra ../platform|vagrant-gitops-mirror.py --infra-ref main --platform-ref main|vagrant-preload-images.sh ../infra ../platform main main|copy-refs.sh set main main|vagrant-inventory.sh | 1 inventory-now"
want=$(git -C "$T/infra" rev-parse main)
check "  copy-built names main's commit now (40 hex, not the snapshot's)" "$(awk '$1 == "infra" { print $2 }' "$W/.copy/copy-built") ${#want}" "$want 40"
rm "$T/dom/ops_kubeadm/snap-copy-built"
check "revert with a snapshot gone: stale (3) - never a half revert" "$(run revert) $(calls 'virsh snapshot-revert')" "rc=3 "

# drop
check "drop: the record gone, the copy destroyed" "$(run drop) $([ -e "$W/.copy/snapshot" ] && echo kept || echo gone) $(calls vagrant)" "rc=0 gone vagrant destroy -f|"
check "  then stale: no record" "$(run status) $(grep -c 'no snapshot record' "$T/out")" "rc=3 1"
echo "copy-snapshot: $([ $fails -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails -eq 0 ]
