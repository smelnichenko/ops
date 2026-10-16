#!/bin/bash
# setup-pi-restore-check.yml's command-line tasks through Ansible on a real FAT filesystem, mounted as the Pis'
# /boot/firmware is (vfat, codepage 437, shortname=mixed): the unit harness's tmpfs let Ansible's backup name (a time
# with ':') pass, the Pi's FAT refused it (pi2, 2026-10-16). A loop mount wants a privileged container, so not CI - run
# it before a change to these tasks:
#   docker run --rm --privileged -v "$PWD:/w:ro" -w /w --entrypoint bash git.pmon.dev/schnappy/ansible-lint:latest \
#     tests/ansible/fat-cmdline/run.sh
# The play reaches its target through a chroot (/tgt, this container's own root bound there): the target's
# /boot/firmware is the FAT, the controller's a decoy - a copy reading the controller's file (no remote_src) keeps
# the decoy. Cases: pi2's file as it is (no newline at its end) - both flags appended, one line, the original kept
# byte for byte, "reboot it"; the same run again - nothing changed, the kept original untouched; a line with
# cgroup_disable=memory - taken off, the flags on, the original kept; a kept copy older than the line - replaced; a line
# already right - not written, no copy made.
set -u
# it mounts over /boot/firmware and makes loop devices: inside a container only, never on a host (a Pi's own boot
# partition would be hidden under the test's)
[ -e /.dockerenv ] || [ -e /run/.containerenv ] || { echo "FAT-CMDLINE: not in a container - refused"; exit 2; }
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
}
command -v mkfs.vfat > /dev/null || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dosfstools > /dev/null; } \
  || apk add -q dosfstools
[ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237
for i in 0 1 2 3 4 5 6 7; do [ -e /dev/loop$i ] || mknod /dev/loop$i b 7 $i; done
dd if=/dev/zero of=/tmp/fat.img bs=1M count=32 status=none && mkfs.vfat /tmp/fat.img > /dev/null \
  || { echo "FAT-CMDLINE: no FAT image made"; exit 2; }
trap 'umount /tgt/boot/firmware /tgt/dev /tgt/proc /tgt /boot/firmware 2> /dev/null' EXIT
mkdir -p /tgt /boot/firmware && mount --bind / /tgt && mount --rbind /dev /tgt/dev && mount -t proc proc /tgt/proc \
  && mount -o loop,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed /tmp/fat.img /tgt/boot/firmware \
  && mount -t tmpfs decoy /boot/firmware || { echo "FAT-CMDLINE: not mounted (a privileged container?)"; exit 2; }
check "the target's command line partition FAT, as the Pis'; the controller's another" \
  "$(findmnt -n -o FSTYPE /tgt/boot/firmware) $(findmnt -n -o FSTYPE /boot/firmware)" "vfat tmpfs"
DECOY='console=tty1 root=PARTUUID=deadbeef-02 rootwait'
echo "$DECOY" > /boot/firmware/cmdline.txt
F=/tgt/boot/firmware/cmdline.txt
# pi2's line as its file holds it: 169 bytes, no newline at its end (2026-10-16)
PI2='console=tty1 console=serial0,115200 root=PARTUUID=771933d1-02 rootfstype=ext4 fsck.repair=yes rootwait cfg80211.ieee80211_regdom=EE ds=nocloud;i=rpi-imager-1775291628561'
mkdir -p /work && echo "cpuset cpu io pids" > /work/controllers && echo "$PI2" > /work/proc
# the playbook's own tasks from the command line's on, its paths and validator (the target's /boot/firmware); the reads
# pointed at fixtures (/work: the same files in the chroot)
python3 - <<'PYPLAY'
import yaml
p = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-restore-check.yml"))[0]
names = [t["name"] for t in p["tasks"]]
tasks = p["tasks"][names.index("The Pi's kernel command line"):]
v = dict(p["vars"], pi_cgroup_controllers="/work/controllers", pi_booted_cmdline="/work/proc")
yaml.safe_dump([{"hosts": "all", "gather_facts": False, "vars": v, "tasks": tasks}], open("/work/play.yml", "w"),
               sort_keys=False)
PYPLAY
run() {  # rc and the message's cause - or the error that stopped it (an Errno: the FAT refused a write)
  local out rc
  out=$(ANSIBLE_NOCOLOR=1 ansible-playbook -i /tgt, -c community.general.chroot \
    -e ansible_python_interpreter="$(command -v python3)" /work/play.yml 2>&1); rc=$?
  echo "rc=$rc $(grep -oE 'Errno [0-9]+|turns it on now: reboot it|turns it on: reboot it' <<< "$out" | head -1)"
}
kept() {  # kept <the original's bytes>: kept, MISSING, or what the copy holds instead
  if [ ! -e "$F.before-memory-cgroup" ]; then echo MISSING
  elif cmp -s <(printf '%s' "$1") "$F.before-memory-cgroup"; then echo kept
  else echo "HOLDS $(head -c 60 "$F.before-memory-cgroup")"; fi
}
printf '%s' "$PI2" > "$F"
check "pi2's file: both flags appended, said to reboot" "$(run)" "rc=2 turns it on now: reboot it"
check "  one line, ending with both flags" \
  "$(grep -c '' "$F") $(grep -c ' ds=nocloud;i=rpi-imager-1775291628561 cgroup_enable=memory cgroup_memory=1$' "$F")" "1 1"
check "  the target's original kept byte for byte (a FAT-safe name), the controller's untouched" \
  "$(kept "$PI2") $(cat /boot/firmware/cmdline.txt) $(ls /boot/firmware | wc -l)" "kept $DECOY 1"
cp "$F" /work/after
check "the same run again: nothing changed, the original still the original" \
  "$(run) $(cmp -s /work/after "$F" && echo untouched) $(kept "$PI2") $(ls /tgt/boot/firmware | grep -c '^cmdline.txt')" \
  "rc=2 turns it on: reboot it untouched kept 2"
rm "$F.before-memory-cgroup"
DIS='console=tty1 root=PARTUUID=771933d1-02 cgroup_disable=memory rootwait'
printf '%s\n' "$DIS" > "$F"
check "a line with cgroup_disable=memory: taken off, both flags on, the original kept" \
  "$(run) $(grep -c 'cgroup_disable' "$F") $(grep -c ' rootwait cgroup_enable=memory cgroup_memory=1$' "$F") $(kept "$DIS"$'\n')" \
  "rc=2 turns it on now: reboot it 0 1 kept"
printf '%s\n' "console=tty1 root=PARTUUID=00000000-02 rootwait" > "$F.before-memory-cgroup"; printf '%s' "$PI2" > "$F"
check "a kept copy older than the line: replaced on the FAT" "$(run) $(kept "$PI2")" "rc=2 turns it on now: reboot it kept"
rm "$F.before-memory-cgroup"
echo "console=tty1 root=X rootwait cgroup_enable=memory cgroup_memory=1" > "$F"; cp "$F" /work/right
check "a line already right: not written, no copy made" \
  "$(run) $(cmp -s /work/right "$F" && echo untouched) $(ls /tgt/boot/firmware | grep -c '^cmdline.txt')" \
  "rc=2 turns it on: reboot it untouched 1"
echo "FAT-CMDLINE: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
