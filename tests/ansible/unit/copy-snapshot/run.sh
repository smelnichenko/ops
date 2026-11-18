#!/bin/bash
# scripts/copy-snapshot.sh (plan 125: the copy's base snapshotted at the build's cold-boot halt) in a scratch ops tree (a
# git repo of its own: the base's files, a Taskfile, the inventory record, a stub copy-lock) against stub vagrant and
# virsh, every call logged; the domains by the UUIDs vagrant holds (.vagrant/machines/<m>/libvirt/id):
#   save    a domain powered off by force, or one still running: no snapshot, no record - and never a failed build
#           (exit 0, said); else one snapshot per domain by its UUID, the record last; COPY_SNAPSHOT=off: nothing
#   status  fresh; stale - no record, a day old, production's inventory moved, the base's files or the Taskfile's base
#           steps changed (not a check's file), a snapshot gone, another domain under a machine's name; libvirt not
#           answering is no verdict (exit 1), never "missing"; read-only (the inventory record untouched)
#   revert  stale: exit 3, nothing halted; fresh: halted, each domain reverted, left shut off; a domain not reverting:
#           the snapshot dropped and exit 3 (the same run builds) - never a half revert kept
#   drop    the record gone, the copy destroyed
set -u
cd "$(dirname "$0")/../../../.." || exit 1
OPS=$PWD
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
W=$T/ops; mkdir -p "$W/scripts" "$W/tests/ansible/copy" "$W/deploy/ansible/playbooks" "$W/.copy" "$T/bin" "$T/dom"
cp "$OPS/scripts/copy-snapshot.sh" "$W/scripts/"
printf '#!/bin/sh\necho "copy-lock" >> "%s/calls"\n' "$T" > "$W/scripts/copy-lock.sh"; chmod +x "$W/scripts/copy-lock.sh"
echo "Vagrant.configure" > "$W/Vagrantfile"
echo "- hosts: pis" > "$W/deploy/ansible/playbooks/setup-consul.yml"
echo "- hosts: all" > "$W/tests/ansible/copy/survival-check.yml"
cat > "$W/Taskfile.yml" << 'EOF_TF'
version: '3'
tasks:
  _copy:base:
    cmds: [vagrant up]
  _vagrant:pi-stack:
    cmds: [echo pis]
  test:copy:check:
    cmds: [echo checks]
EOF_TF
echo "prod v1" > "$W/tests/ansible/copy/prod-inventory.txt"
echo "pi: 1" > "$W/tests/ansible/copy/pi-versions.yml"
{ printf '#!/bin/sh\necho "vagrant $*" >> "%s/calls"\n' "$T"; echo 'exit 0'; } > "$T/bin/vagrant"
# virsh by UUID: $T/dom/<uuid>/state (and reason), snapshots as files beside it; VIRSH_FAIL=1 fails every call
cat > "$T/bin/virsh" << STUB
#!/bin/sh
shift 2
echo "virsh \$*" >> "$T/calls"
[ -z "\${VIRSH_FAIL:-}" ] || { echo "error: failed to connect to the hypervisor" >&2; exit 1; }
D=$T/dom
case "\$1" in
  domstate) [ -d "\$D/\$2" ] || exit 1; if [ "\${3:-}" = --reason ]; then echo "\$(cat "\$D/\$2/state") (\$(cat "\$D/\$2/reason"))"; else cat "\$D/\$2/state"; fi ;;
  snapshot-list) [ -d "\$D/\$2" ] || exit 1; ls "\$D/\$2" | grep '^snap-' | sed 's/^snap-//' ;;
  snapshot-create-as) : > "\$D/\$2/snap-\$3" ;;
  snapshot-delete) rm -f "\$D/\$2/snap-\$3" ;;
  snapshot-revert) [ -f "\$D/\$2/snap-\$3" ] && [ ! -f "\$D/\$2/revert-fails" ] || exit 1 ;;
esac
STUB
chmod +x "$T/bin/"*
dom() {  # dom <state> <reason>: the three machines' domains, vagrant's ids pointing at them
  rm -rf "$T/dom"; mkdir -p "$T/dom"
  for m in kubeadm pi1 pi2; do
    u=uuid-$m; mkdir -p "$T/dom/$u" "$W/.vagrant/machines/$m/libvirt"
    echo "${1:-shut off}" > "$T/dom/$u/state"; echo "${2:-shutdown}" > "$T/dom/$u/reason"
    echo "$u" > "$W/.vagrant/machines/$m/libvirt/id"
  done
}
git -C "$W" init -q -b main && git -C "$W" add -A && git -C "$W" -c user.name=t -c user.email=t@t commit -qm t
run() { rm -f "$T/calls"; if env PATH="$T/bin:$PATH" VIRSH="virsh -c qemu:///system" VAGRANT=vagrant COPY_SNAPSHOT_MAX_AGE="${AGE:-86400}" \
  COPY_SNAPSHOT="${SNAPSHOT:-on}" VIRSH_FAIL="${VIRSH_FAIL:-}" bash "$W/scripts/copy-snapshot.sh" "$@" > "$T/out" 2>&1; then echo rc=0; else echo "rc=$?"; fi; }
calls() { grep -E "^($1)" "$T/calls" 2> /dev/null | tr '\n' '|'; }
meta() { [ -f "$W/.copy/snapshot/meta" ] && echo meta || echo no-meta; }

# save
dom "shut off" destroyed
check "save, a domain powered off by force: no snapshot, no record - and the build not failed (exit 0, said)" \
  "$(run save) $(meta) $(calls 'virsh snapshot-create') $(grep -c 'only a domain shut down by itself' "$T/out")" "rc=0 no-meta  1"
dom running unknown
check "save, a domain running: refused the same" "$(run save) $(meta)" "rc=0 no-meta"
dom; check "save, COPY_SNAPSHOT=off: nothing" "$(SNAPSHOT=off run save) $(meta) $(calls virsh)" "rc=0 no-meta "
r=$(run save)
check "save: the lock, each domain's snapshot by its UUID - nothing halted or booted here (the build does)" \
  "$r $(calls 'copy-lock|vagrant|virsh snapshot-create') $(meta)" \
  "rc=0 copy-lock|virsh snapshot-create-as uuid-kubeadm copy-base --atomic|virsh snapshot-create-as uuid-pi1 copy-base --atomic|virsh snapshot-create-as uuid-pi2 copy-base --atomic| meta"
check "  the record: each machine's domain, its age, inventory and tree" "$(awk '{print $1}' "$W/.copy/snapshot/meta" | tr '\n' ' ')" "domain domain domain created inventory tree "

# status
check "status, just saved: fresh" "$(run status)" "rc=0"
check "  read-only: the inventory record untouched, nothing halted or locked" "$(run status; calls 'vagrant|copy-lock') $(git -C "$W" status --short -- tests/ansible/copy | wc -l)" "rc=0 0"
check "  a day old: stale" "$(AGE=-1 run status) $(grep -c 'older than' "$T/out")" "rc=3 1"
echo "prod v2" > "$W/tests/ansible/copy/prod-inventory.txt"
check "  production's inventory moved: stale" "$(run status) $(grep -c "production's inventory or the Pis' versions moved" "$T/out")" "rc=3 1"
git -C "$W" checkout -q -- tests/ansible/copy/prod-inventory.txt
echo "# x" >> "$W/deploy/ansible/playbooks/setup-consul.yml"
check "  a file building the base changed (the working tree's): stale" "$(run status) $(grep -c 'files that build the base changed' "$T/out")" "rc=3 1"
git -C "$W" checkout -q -- deploy/ansible/playbooks/setup-consul.yml
sed -i 's/cmds: \[echo pis\]/cmds: [echo pis, echo gluster]/' "$W/Taskfile.yml"
check "  a base step added in the Taskfile: stale" "$(run status) $(grep -c 'files that build the base changed' "$T/out")" "rc=3 1"
git -C "$W" checkout -q -- Taskfile.yml
sed -i 's/cmds: \[echo checks\]/cmds: [echo checks, echo more]/' "$W/Taskfile.yml"; echo "# y" >> "$W/tests/ansible/copy/survival-check.yml"
check "  a check's step or file changed (not the base's): fresh" "$(run status)" "rc=0"
git -C "$W" checkout -q -- Taskfile.yml tests/ansible/copy/survival-check.yml
rm "$T/dom/uuid-pi2/snap-copy-base"
check "  a snapshot gone: stale, named" "$(run status) $(grep -c "pi2's snapshot missing" "$T/out")" "rc=3 1"
: > "$T/dom/uuid-pi2/snap-copy-base"
echo uuid-other > "$W/.vagrant/machines/pi1/libvirt/id"
check "  another domain under a machine's name (a copy rebuilt since): stale" "$(run status) $(grep -c 'pi1 is another domain' "$T/out")" "rc=3 1"
echo uuid-pi1 > "$W/.vagrant/machines/pi1/libvirt/id"
check "  libvirt not answering: no verdict (exit 1), never 'missing'" "$(VIRSH_FAIL=1 run status) $(grep -c 'libvirt does not answer' "$T/out")" "rc=1 1"
check "  every one back: fresh" "$(run status)" "rc=0"

# revert
echo "prod v2" > "$W/tests/ansible/copy/prod-inventory.txt"
check "revert, stale: exit 3, nothing halted or reverted" "$(run revert) $(calls 'vagrant|virsh snapshot-revert')" "rc=3 "
git -C "$W" checkout -q -- tests/ansible/copy/prod-inventory.txt
r=$(run revert)
check "revert, fresh: the lock, halted, each domain reverted by its UUID, left shut off - not booted here" \
  "$r $(calls 'copy-lock|vagrant|virsh snapshot-revert')" \
  "rc=0 copy-lock|vagrant halt|virsh snapshot-revert uuid-kubeadm copy-base|virsh snapshot-revert uuid-pi1 copy-base|virsh snapshot-revert uuid-pi2 copy-base|"
touch "$T/dom/uuid-pi1/revert-fails"
check "revert, the second domain not reverting: the snapshot dropped, exit 3 (the same run builds) - never kept half" \
  "$(run revert) $(meta) $(grep -c 'REVERT FAILED: pi1 not reverted' "$T/out")" "rc=3 no-meta 1"
rm -f "$T/dom/uuid-pi1/revert-fails"
check "  then stale: no record" "$(run status) $(grep -c 'no snapshot record' "$T/out")" "rc=3 1"

# drop
dom; run save > /dev/null
check "drop: the lock, the record gone, the copy destroyed" "$(run drop) $(meta) $(calls 'copy-lock|vagrant')" "rc=0 no-meta copy-lock|vagrant destroy -f|"
echo "copy-snapshot: $([ $fails -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails -eq 0 ]
