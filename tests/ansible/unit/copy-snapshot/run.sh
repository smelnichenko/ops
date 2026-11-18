#!/bin/bash
# scripts/copy-snapshot.sh (the copy's base snapshotted at the build's cold-boot halt) in a scratch ops tree (a git repo
# of its own: the base's files, a Taskfile, the inventory record, a stub copy-lock) against stub vagrant and virsh, every
# call logged; the machines the Vagrantfile defines, their domains by the UUIDs vagrant holds:
#   begin/based/save/proven  a base saved only when this build made it (begin, based), its hashes as at its start, every
#           domain shut down by itself; the record unproven until the build's end (proven); a save refused never fails
#           the build (exit 0, said); COPY_SNAPSHOT=off saves nothing; begin refuses a host short of disk
#   status  fresh; stale - unproven, no record, a day old, production's inventory lines the base holds moved (not
#           another's), the base's files (untracked too, the apt pins' script) or its Taskfile steps changed (not a
#           check's), a hash not computed, a snapshot gone, a domain gone, another domain under a machine's name, the
#           disk short; libvirt not answering is no verdict (exit 1); read-only
#   revert  stale: exit 3, nothing halted; fresh: halted, a managed save removed, each domain reverted, left shut off; a
#           domain not reverting: the record dropped, exit 3; libvirt not answering in time: the record dropped, exit 1
#   forget, used/layered/unused, drop, disk
set -u
cd "$(dirname "$0")/../../../.." || exit 1
OPS=$PWD
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
W=$T/ops; mkdir -p "$W/scripts" "$W/tests/ansible/copy" "$W/deploy/ansible/playbooks" "$W/.copy" "$T/bin" "$T/dom" "$T/pool"
cp "$OPS/scripts/copy-snapshot.sh" "$W/scripts/"
printf '#!/bin/sh\necho "copy-lock" >> "%s/calls"\n' "$T" > "$W/scripts/copy-lock.sh"; chmod +x "$W/scripts/copy-lock.sh"
printf '#!/bin/sh\necho pin\n' > "$W/scripts/pi-apt-pin.sh"
cat > "$W/Vagrantfile" << 'EOF_VF'
Vagrant.configure("2") do |config|
  config.vm.define "pi1" do |pi1|
  end
  # config.vm.define "old" do |o|
  config.vm.define "pi2" do |pi2|
  end
  config.vm.define "kubeadm" do |k|
  end
end
EOF_VF
echo "- hosts: pis" > "$W/deploy/ansible/playbooks/setup-consul.yml"
echo "- hosts: all" > "$W/tests/ansible/copy/survival-check.yml"
cat > "$W/Taskfile.yml" << 'EOF_TF'
version: '3'
tasks:
  _copy:base:
    cmds: [vagrant up]
  _vagrant:pi-stack:
    cmds: [echo pis]
  test:copy:build:
    cmds: [echo build]
  test:copy:check:
    cmds: [echo checks]
EOF_TF
printf 'os debian 13.7\nk8s server v1.36.6\npkg containerd 2.2\npi pi1 consul 1.20.6\nhelm kube-system/cilium cilium-1.20.4 1.20.4\nimage monitor abc123\nhelm argocd/argocd argo-cd-10 v3\n' \
  > "$W/tests/ansible/copy/prod-inventory.txt"
echo "pi: 1" > "$W/tests/ansible/copy/pi-versions.yml"
{ printf '#!/bin/sh\necho "vagrant $*" >> "%s/calls"\n' "$T"; echo 'exit 0'; } > "$T/bin/vagrant"
# virsh by UUID: $T/dom/<uuid>/state (and reason), snapshots as files beside it; VIRSH_FAIL=1 fails every call (libvirt
# down), REVERT_HANGS=1 a revert timed out (124), DOMSTATE_FAILS=1 every domstate
cat > "$T/bin/virsh" << STUB
#!/bin/sh
shift 2
echo "virsh \$*" >> "$T/calls"
[ -z "\${VIRSH_FAIL:-}" ] || { echo "error: failed to connect to the hypervisor" >&2; exit 1; }
D=$T/dom
gone() { echo "error: failed to get domain '\$1'" >&2; exit 1; }
case "\$1" in
  uri) echo qemu:///system ;;
  domstate) [ -z "\${DOMSTATE_FAILS:-}" ] || exit 1; [ -d "\$D/\$2" ] || gone "\$2"
            if [ "\${3:-}" = --reason ]; then echo "\$(cat "\$D/\$2/state") (\$(cat "\$D/\$2/reason"))"; else cat "\$D/\$2/state"; fi ;;
  snapshot-list) [ -d "\$D/\$2" ] || gone "\$2"; ls "\$D/\$2" | grep '^snap-' | sed 's/^snap-//' ;;
  snapshot-create-as) : > "\$D/\$2/snap-\$3" ;;
  snapshot-delete) rm -f "\$D/\$2/snap-\$3" ;;
  snapshot-revert) [ -z "\${REVERT_HANGS:-}" ] || exit 124; [ -f "\$D/\$2/snap-\$3" ] && [ ! -f "\$D/\$2/revert-fails" ] || exit 1 ;;
  managedsave-remove) [ -d "\$D/\$2" ] || gone "\$2"; rm -f "\$D/\$2/managedsave" ;;
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
printf '.vagrant/\n.copy/\n' > "$W/.gitignore"
git -C "$W" init -q -b main && git -C "$W" add -A && git -C "$W" -c user.name=t -c user.email=t@t commit -qm t
run() { rm -f "$T/calls"; if env PATH="$T/bin:$PATH" VIRSH="virsh -c qemu:///system" VAGRANT=vagrant COPY_SNAPSHOT_MAX_AGE="${AGE:-86400}" \
  COPY_SNAPSHOT="${SNAPSHOT:-on}" VIRSH_FAIL="${VIRSH_FAIL:-}" REVERT_HANGS="${REVERT_HANGS:-}" DOMSTATE_FAILS="${DOMSTATE_FAILS:-}" \
  COPY_POOL_PATH="$T/pool" COPY_DISK_NEED_GB="${NEED:-1}" bash "$W/scripts/copy-snapshot.sh" "$@" > "$T/out" 2>&1; then echo rc=0; else echo "rc=$?"; fi; }
calls() { grep -E "^($1)" "$T/calls" 2> /dev/null | tr '\n' '|'; }
rec() { [ -f "$W/.copy/snapshot/meta" ] && echo meta || { [ -f "$W/.copy/snapshot/meta.unproven" ] && echo unproven || echo none; }; }
built() { run begin > /dev/null; run based > /dev/null; }  # a build's base: begun, built
saved() { dom; built; run save > /dev/null; run proven > /dev/null; }  # a proven snapshot
said() { grep -c -- "$1" "$T/out"; }
TF0=$(cat "$W/Taskfile.yml"); INV0=$(cat "$W/tests/ansible/copy/prod-inventory.txt")
restore() { echo "$TF0" > "$W/Taskfile.yml"; echo "$INV0" > "$W/tests/ansible/copy/prod-inventory.txt"; git -C "$W" checkout -q -- . ; git -C "$W" clean -qfd -- deploy scripts; }

# begin, based, save, proven
dom
check "save without this build's base (no begin, no based - a copy after a run): NOT SAVED, the build not failed" \
  "$(run save) $(rec) $(calls 'virsh snapshot-create') $(said 'no base this build made')" "rc=0 none  1"
check "begin: what builds the base hashed now; based: the base marked complete" \
  "$(run begin) $(awk '{print $1}' "$W/.copy/snapshot/pending" | tr '\n' ' ')$(run based) $(grep -c '^based ' "$W/.copy/snapshot/pending")" \
  "rc=0 inventory tree rc=0 1"
dom "shut off" destroyed; built
check "save, a domain powered off by force: no snapshot, no record - the build not failed (exit 0, said)" \
  "$(run save) $(rec) $(calls 'virsh snapshot-create') $(said 'only a domain shut down by itself')" "rc=0 none  1"
dom running unknown; built
check "save, a domain running: refused the same" "$(run save) $(rec)" "rc=0 none"
dom; built; check "save, COPY_SNAPSHOT=off: nothing" "$(SNAPSHOT=off run save) $(rec) $(calls virsh)" "rc=0 none "
dom; built; r=$(run save)
check "save: the lock, each domain's snapshot by its UUID (the Vagrantfile's machines, a commented one not) - nothing halted" \
  "$r $(calls 'copy-lock|vagrant|virsh snapshot-create') $(rec)" \
  "rc=0 copy-lock|virsh snapshot-create-as uuid-pi1 copy-base --atomic|virsh snapshot-create-as uuid-pi2 copy-base --atomic|virsh snapshot-create-as uuid-kubeadm copy-base --atomic| unproven"
check "  the record unproven: each machine's domain, its age, inventory and tree; its pending consumed" \
  "$(awk '{print $1}' "$W/.copy/snapshot/meta.unproven" | tr '\n' ' ')$([ -f "$W/.copy/snapshot/pending" ] && echo pending || echo gone)" \
  "domain domain domain created inventory tree gone"
check "status, unproven (the build failed after its save): stale - never reused" "$(run status) $(said 'never proven')" "rc=3 1"
check "proven: the record reusable; status fresh" "$(run proven) $(rec) $(run status)" "rc=0 meta rc=0"
dom; built; echo "- hosts: pis # moved" > "$W/deploy/ansible/playbooks/setup-consul.yml"
check "save, a base file changed while the base was built: NOT SAVED" "$(run save) $(rec) $(said 'changed while it was built')" "rc=0 none 1"
restore; dom; built; echo "pi pi2 consul 1.20.7" >> "$W/tests/ansible/copy/prod-inventory.txt"
check "save, production's inventory (a base line) moved while it was built: NOT SAVED" "$(run save) $(rec) $(said 'moved while the base was built')" "rc=0 none 1"
restore; dom
check "begin, the host's disk short: refused before the build (rc 1, said), no pending" \
  "$(NEED=999999 run begin) $(said "the host's disk short") $([ -f "$W/.copy/snapshot/pending" ] && echo pending || echo none)" "rc=1 1 none"
echo "{broken" > "$W/Taskfile.yml"
check "begin, the Taskfile not read (no hash): said, the base never saved" "$(run begin) $(said 'not hashed') $(run based) $(run save) $(rec)" \
  "rc=0 1 rc=0 rc=0 none"
restore

# status
saved
check "status, just proven: fresh, read-only (nothing locked, halted or reverted)" "$(run status) $(calls 'copy-lock|vagrant|virsh snapshot-revert')" "rc=0 "
check "  a day old: stale" "$(AGE=-1 run status) $(said 'older than')" "rc=3 1"
echo "image monitor def456" >> "$W/tests/ansible/copy/prod-inventory.txt"; echo "crd-name x.y.z" >> "$W/tests/ansible/copy/prod-inventory.txt"
check "  production's inventory moved in lines no base holds (an app's image, a CRD): fresh" "$(run status)" "rc=0"
restore; echo "pkg containerd 2.3" >> "$W/tests/ansible/copy/prod-inventory.txt"
check "  in a line the base holds (a package): stale" "$(run status) $(said "inventory or the Pis' versions moved")" "rc=3 1"
restore; echo "pi: 2" > "$W/tests/ansible/copy/pi-versions.yml"
check "  the Pis' versions moved: stale" "$(run status)" "rc=3"
restore; echo "- hosts: pis # moved" > "$W/deploy/ansible/playbooks/setup-consul.yml"
check "  a file building the base changed (the working tree's): stale" "$(run status) $(said 'files that build the base changed')" "rc=3 1"
restore; echo "x: 1" > "$W/deploy/ansible/playbooks/group_vars_new.yml"
check "  a file under deploy/ansible added, untracked: stale" "$(run status)" "rc=3"
restore; echo "echo pin2" >> "$W/scripts/pi-apt-pin.sh"
check "  the apt pins' script changed: stale" "$(run status)" "rc=3"
restore; sed -i 's/cmds: \[echo pis\]/cmds: [echo pis, echo more]/' "$W/Taskfile.yml"
check "  a base step added in the Taskfile: stale" "$(run status)" "rc=3"
restore; sed -i 's/cmds: \[echo build\]/cmds: [echo build, echo more]/' "$W/Taskfile.yml"
check "  test:copy:build's steps changed: stale" "$(run status)" "rc=3"
restore; sed -i 's/cmds: \[echo checks\]/cmds: [echo checks, echo more]/' "$W/Taskfile.yml"; echo "- hosts: all # x" > "$W/tests/ansible/copy/survival-check.yml"
check "  a check's step or file changed (not the base's): fresh" "$(run status)" "rc=0"
restore; echo "{broken" > "$W/Taskfile.yml"
check "  the base's hash not computed (the Taskfile not read): stale, said - never fresh" "$(run status) $(said 'not hashed')" "rc=3 1"
restore; rm "$T/dom/uuid-pi1/snap-copy-base"
check "  a snapshot gone: stale" "$(run status) $(said "pi1's snapshot missing")" "rc=3 1"
saved; rm -rf "$T/dom/uuid-pi2"
check "  a domain gone (vagrant's id left): stale - never 'libvirt does not answer'" "$(run status) $(said "pi2's domain gone")" "rc=3 1"
saved; echo other-uuid > "$W/.vagrant/machines/kubeadm/libvirt/id"
check "  another domain under a machine's name: stale" "$(run status) $(said 'another domain than the snapshot')" "rc=3 1"
saved
check "  the host's disk short: stale" "$(NEED=999999 run status) $(said "the host's disk short")" "rc=3 1"
check "  libvirt not answering: no verdict (exit 1), never stale" "$(VIRSH_FAIL=1 run status) $(said 'libvirt does not answer')" "rc=1 1"
rm -rf "$W/.copy/snapshot"
check "  no record: stale" "$(run status) $(said 'no snapshot record')" "rc=3 1"

# revert
check "revert, stale: exit 3 - the lock, nothing halted or reverted" "$(run revert) $(calls 'copy-lock|vagrant|virsh snapshot-revert')" "rc=3 copy-lock|"
saved; : > "$T/dom/uuid-pi1/managedsave"
check "revert, fresh: halted, each domain's managed save removed and reverted by its UUID, left shut off" \
  "$(run revert) $(calls 'vagrant|virsh managedsave-remove|virsh snapshot-revert') $([ -f "$T/dom/uuid-pi1/managedsave" ] && echo kept || echo removed)" \
  "rc=0 vagrant halt|virsh managedsave-remove uuid-pi1|virsh snapshot-revert uuid-pi1 copy-base|virsh managedsave-remove uuid-pi2|virsh snapshot-revert uuid-pi2 copy-base|virsh managedsave-remove uuid-kubeadm|virsh snapshot-revert uuid-kubeadm copy-base| removed"
check "  the record kept (proven, reused for the day)" "$(rec)" "meta"
: > "$T/dom/uuid-pi2/revert-fails"
check "revert, a domain not reverting: the record dropped, exit 3 (the same run builds)" "$(run revert) $(rec) $(said 'REVERT FAILED')" "rc=3 none 1"
saved
check "revert, timed out (libvirt busy): the record dropped, exit 1 - no verdict, never a build racing it" \
  "$(REVERT_HANGS=1 run revert) $(rec) $(said 'REVERT NOT JUDGED')" "rc=1 none 1"
saved; echo running > "$T/dom/uuid-kubeadm/state"
check "revert, a domain still running after the halt: the record dropped, exit 3" "$(run revert) $(rec) $(said "kubeadm is 'running' after the halt")" "rc=3 none 1"

# forget, used/layered/unused, drop, disk
saved
check "forget: the record dropped, said with its reason" "$(run forget 'the reverted base did not come up') $(rec) $(said 'did not come up')" "rc=0 none 1"
check "used: change, check and playbook refused (unused exits 1, said); layered: taken again" \
  "$(run used) $(run unused) $(said 'halted after a run') $(run layered) $(run unused)" "rc=0 rc=1 1 rc=0 rc=0"
saved; run used > /dev/null
check "drop: the lock, the record and the used mark gone, the copy destroyed" \
  "$(run drop) $(calls 'copy-lock|vagrant') $(rec) $([ -f "$W/.copy/copy-used" ] && echo used || echo clean)" "rc=0 copy-lock|vagrant destroy -f| none clean"
check "disk: enough - 0; short - 1, said" "$(run disk) $(NEED=999999 run disk) $(said "the host's disk short")" "rc=0 rc=1 1"

echo "copy-snapshot: $([ "$fails" -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ "$fails" -eq 0 ]
