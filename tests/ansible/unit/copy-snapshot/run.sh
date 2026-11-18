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
mkdir -p "$W/tests/ansible"
for f in tests/ansible/copy/pi-apt-versions.yml tests/ansible/vagrant-only.yml tests/ansible/vagrant-only-play.yml \
    tests/ansible/isolate-pis.yml scripts/copy-host-guard.sh; do echo "# $f" > "$W/$f"; done
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
printf 'os debian 13.7\nk8s server v1.36.6\npkg containerd 2.2\npi pi1 consul 1.20.6\nhelm kube-system/cilium cilium-1.20.4 1.20.4\ncontainerd-unit /usr/lib/systemd/system/containerd.service\nimage monitor abc123\nhelm argocd/argocd argo-cd-10 v3\n' \
  > "$W/tests/ansible/copy/prod-inventory.txt"
echo "pi: 1" > "$W/tests/ansible/copy/pi-versions.yml"
{ printf '#!/bin/sh\necho "vagrant $*" >> "%s/calls"\n' "$T"; echo '[ -z "${HALT_FAILS:-}" ] || [ "$1" != halt ] || exit 1'; echo 'exit 0'; } > "$T/bin/vagrant"
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
  snapshot-list) [ -z "\${LIST_ERR:-}" ] || { echo "error: Timed out during operation: cannot acquire state change lock" >&2; exit 1; }
                 [ -d "\$D/\$2" ] || gone "\$2"; ls "\$D/\$2" | grep '^snap-' | sed 's/^snap-//' ;;
  snapshot-create-as) [ "\${CREATE_FAILS_ON:-}" != "\$2" ] || { echo "error: internal error: unable to save" >&2; exit 1; }; : > "\$D/\$2/snap-\$3" ;;
  snapshot-delete) rm -f "\$D/\$2/snap-\$3" ;;
  snapshot-revert) [ -z "\${REVERT_HANGS:-}" ] || exit 124; [ -f "\$D/\$2/snap-\$3" ] && [ ! -f "\$D/\$2/revert-fails" ] || exit 1
                   [ -z "\${REVERT_LEAVES_RUNNING:-}" ] || echo running > "\$D/\$2/state" ;;
  managedsave-remove) [ -z "\${MANAGEDSAVE_FAILS:-}" ] || exit 1; [ -d "\$D/\$2" ] || gone "\$2"; rm -f "\$D/\$2/managedsave" ;;
  pool-dumpxml) [ -n "\${POOL_EMPTY:-}" ] || echo "<pool><target><path>$T/pool</path></target></pool>" ;;
esac
STUB
# timeout: each call's bound logged ("<seconds> <virsh verb>"), then run
printf '#!/bin/sh\necho "$1 $5" >> "%s/timeouts"\nshift\nexec "$@"\n' "$T" > "$T/bin/timeout"
# df: DF_EMPTY - a header and no number
printf '#!/bin/sh\n[ -z "${DF_EMPTY:-}" ] || { echo "Avail"; exit 0; }\nexec /bin/df "$@"\n' > "$T/bin/df"
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
run() { rm -f "$T/calls" "$T/timeouts"; if env PATH="$T/bin:$PATH" VIRSH="virsh -c qemu:///system" VAGRANT=vagrant COPY_SNAPSHOT_MAX_AGE="${AGE:-86400}" \
  COPY_SNAPSHOT="${SNAPSHOT:-on}" VIRSH_FAIL="${VIRSH_FAIL:-}" REVERT_HANGS="${REVERT_HANGS:-}" DOMSTATE_FAILS="${DOMSTATE_FAILS:-}" \
  CREATE_FAILS_ON="${CREATE_FAILS_ON:-}" LIST_ERR="${LIST_ERR:-}" MANAGEDSAVE_FAILS="${MANAGEDSAVE_FAILS:-}" HALT_FAILS="${HALT_FAILS:-}" \
  REVERT_LEAVES_RUNNING="${REVERT_LEAVES_RUNNING:-}" POOL_EMPTY="${POOL_EMPTY:-}" DF_EMPTY="${DF_EMPTY:-}" \
  COPY_POOL_PATH="${POOL_PATH-$T/pool}" COPY_DISK_NEED_GB="${NEED:-1}" bash "$W/scripts/copy-snapshot.sh" "$@" > "$T/out" 2>&1; then echo rc=0; else echo "rc=$?"; fi; }
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

# save's failure paths: each NOT SAVED, the build never failed, nothing left
dom; built
check "save, a domain's state not read: NOT SAVED, no snapshot made, its pending gone" \
  "$(DOMSTATE_FAILS=1 run save) $(rec) $(calls 'virsh snapshot-create') $(said 'NOT SAVED') $([ -f "$W/.copy/snapshot/pending" ] && echo pending || echo gone)" "rc=0 none  1 gone"
dom; built
check "save, a snapshot failing half way (the second domain's): the first one's deleted, NOT SAVED, no record" \
  "$(CREATE_FAILS_ON=uuid-pi2 run save) $(rec) $(calls 'virsh snapshot-delete') $(ls "$T/dom/uuid-pi1" | grep -c '^snap-') $(said 'NOT SAVED')" \
  "rc=0 none virsh snapshot-delete uuid-pi1 copy-base| 0 1"
dom; built; : > "$T/dom/uuid-pi1/snap-copy-base"
r=$(run save)
check "save over an old snapshot of the name: deleted before it is made again" \
  "$r $(grep -n 'uuid-pi1' "$T/calls" | grep -E 'snapshot-(delete|create-as)' | sed 's/^[0-9]*://' | cut -d' ' -f2 | tr '\n' ' ')" \
  "rc=0 snapshot-delete snapshot-create-as "
saved; dom; built; run save > /dev/null
check "  a proven record there before a save: gone (never a proven record beside a new unproven base)" "$(rec)" "unproven"
dom; built
check "save, libvirt not answering for a domain (its snapshots not listed): NOT SAVED" "$(LIST_ERR=1 run save) $(rec) $(said 'NOT SAVED')" "rc=0 none 1"
check "the bounds: a read 30 s, a snapshot made 600 s" "$(dom; built; run save > /dev/null; sort -u "$T/timeouts" | tr '\n' ' ')" \
  "30 domstate 30 snapshot-list 600 snapshot-create-as "
# stale: libvirt answering, a domain's snapshots not listed - no verdict
saved
check "status, the domain's snapshots not listed (libvirt busy) though libvirt answers: no verdict (exit 1)" "$(LIST_ERR=1 run status) $(said 'libvirt does not answer for')" "rc=1 1"
# each input of the base's hash
for l in "k8s server v1.36.7" "containerd-unit /etc/systemd/system/containerd.service" "helm kube-system/cilium cilium-1.20.5 1.20.5"; do
  saved; echo "$l" >> "$W/tests/ansible/copy/prod-inventory.txt"
  check "  the base's inventory line moved ($(echo "$l" | cut -d' ' -f1-2)): stale" "$(run status)" "rc=3"
  restore
done
for f in Vagrantfile tests/ansible/copy/pi-apt-versions.yml tests/ansible/vagrant-only.yml tests/ansible/vagrant-only-play.yml \
    tests/ansible/isolate-pis.yml scripts/copy-host-guard.sh; do
  saved; echo "# moved" >> "$W/$f"
  check "  $f changed: stale" "$(run status)" "rc=3"
  restore
done
saved; sed -i 's/cmds: \[vagrant up\]/cmds: [vagrant up, echo more]/' "$W/Taskfile.yml"
check "  _copy:base's steps changed: stale" "$(run status)" "rc=3"
restore
saved; DF=$(DF_EMPTY=1 run status)
check "  the disk's free space not read (no number): stale, said - never 'enough'" "$DF $(said 'free space of')" "rc=3 1"
check "  the pool's path not read: stale, said" "$(POOL_PATH= POOL_EMPTY=1 run status) $(said 'pool path not read')" "rc=3 1"
check "begin over a record there: the record gone (a base built anew is no former base)" "$(saved; run begin > /dev/null; rec)" "none"
# revert's failure paths
saved
check "revert, the halt failing: the record dropped, exit 3 (the same run builds)" "$(HALT_FAILS=1 run revert) $(rec)" "rc=3 none"
saved
check "revert, a managed save not removed: no verdict (exit 1), the record dropped" "$(MANAGEDSAVE_FAILS=1 run revert) $(rec) $(said 'REVERT NOT JUDGED')" "rc=1 none 1"
saved
check "revert, a domain running after its revert: the record dropped, exit 3" "$(REVERT_LEAVES_RUNNING=1 run revert) $(rec) $(said 'not shut off after its revert')" "rc=3 none 1"
saved; run revert > /dev/null
check "the bounds in a revert: reads 30 s, the revert 600 s" "$(grep -c '^600 snapshot-revert' "$T/timeouts") $(grep -c '^600 ' "$T/timeouts") $(grep -c '^30 domstate' "$T/timeouts")" "3 3 6"

# test:copy:ready's revert path, the Taskfile's own shell: a reverted base that does not come up forgotten at each step
RD=$T/ready; mkdir -p "$RD/scripts" "$RD/deploy/ansible/venv/bin" "$RD/bin"
for s in copy-snapshot.sh; do printf '#!/bin/sh\necho "snap $*" >> "%s/calls"\n[ "$1" != revert ] || exit "${REVERT_RC:-0}"\nexit 0\n' "$RD" > "$RD/scripts/$s"; done
printf '#!/bin/sh\necho "vagrant $*" >> "%s/calls"\n[ "${FAIL_AT:-}" != up ] || exit 1\n' "$RD" > "$RD/bin/vagrant"
printf '#!/bin/sh\necho "playbook $*" >> "%s/calls"\ncase "$*" in *vms-ready*) [ "${FAIL_AT:-}" != ready ] || exit 1 ;; *base-fingerprint*) [ "${FAIL_AT:-}" != fp ] || exit 1 ;; esac\n' "$RD" > "$RD/deploy/ansible/venv/bin/ansible-playbook"
printf '#!/bin/sh\necho "task $*" >> "%s/calls"\n[ "${FAIL_AT:-}" != argo ] || [ "$1" != test:copy:argo ] || exit 1\n' "$RD" > "$RD/bin/task"
chmod +x "$RD/scripts/"* "$RD/deploy/ansible/venv/bin/"* "$RD/bin/"*
READY=$(python3 -c 'import yaml
t = yaml.safe_load(open("'"$OPS"'/Taskfile.yml"))["tasks"]["test:copy:ready"]["cmds"]
print([c["cmd"] for c in t if isinstance(c, dict) and "revert" in str(c.get("cmd", ""))][0])')
ready() { rm -f "$RD/calls"; (cd "$RD" && env PATH="$RD/bin:$PATH" "$@" bash -c "$READY") > /dev/null 2>&1; echo "rc=$? $(grep -c 'snap forget' "$RD/calls")"; }
check "ready: reverted, up, ready and layered - nothing forgotten" "$(ready)" "rc=0 0"
for at in up ready argo; do
  check "  the reverted base not coming up ($at failing): forgotten, the run failed" "$(ready FAIL_AT=$at)" "rc=1 1"
done
check "  COPY_FINGERPRINT set and its play failing: forgotten too" "$(ready FAIL_AT=fp COPY_FINGERPRINT=x)" "rc=1 1"
check "ready, stale (3): built - test:copy:build, nothing forgotten" "$(ready REVERT_RC=3) $(grep -c 'task test:copy:build' "$RD/calls")" "rc=0 0 1"
check "ready, libvirt not answering (1): the run failed, nothing built" "$(ready REVERT_RC=1) $(grep -c 'task test:copy:build' "$RD/calls")" "rc=1 0 0"
echo "copy-snapshot: $([ "$fails" -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ "$fails" -eq 0 ]
