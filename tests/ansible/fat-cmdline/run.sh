#!/bin/bash
# setup-pi-restore-check.yml's command-line tasks through Ansible on a real FAT filesystem, mounted as the Pis'
# /boot/firmware is (vfat, codepage 437, shortname=mixed): the unit harness's tmpfs let Ansible's backup name (a time
# with ':') pass, the Pi's FAT refused it (pi2, 2026-10-16). A loop mount wants a privileged container, so not CI - run
# it before a change to these tasks:
#   docker run --rm --privileged -v "$PWD:/w:ro" -w /w --entrypoint bash git.pmon.dev/schnappy/ansible-lint:latest \
#     tests/ansible/fat-cmdline/run.sh
# Cases: pi2's line - both flags appended, one line, the original kept, "reboot it"; the same run again - nothing
# changed, the kept original untouched; a line already right - no copy made.
set -u
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
}
(command -v mkfs.vfat || { apt-get update -qq && apt-get install -y -qq dosfstools; } || apk add -q dosfstools) \
  > /dev/null 2>&1
[ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237
for i in 0 1 2 3 4 5 6 7; do [ -e /dev/loop$i ] || mknod /dev/loop$i b 7 $i; done
dd if=/dev/zero of=/tmp/fat.img bs=1M count=32 status=none && mkfs.vfat /tmp/fat.img > /dev/null \
  || { echo "FAT-CMDLINE: no FAT image made"; exit 2; }
mkdir -p /boot/firmware
mount -o loop,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed /tmp/fat.img /boot/firmware \
  || { echo "FAT-CMDLINE: not mounted (a privileged container?)"; exit 2; }
trap 'umount /boot/firmware 2> /dev/null' EXIT
check "the command line's partition FAT, as the Pis'" "$(findmnt -n -o FSTYPE /boot/firmware)" vfat
F=/boot/firmware/cmdline.txt
PI2='console=tty1 console=serial0,115200 root=PARTUUID=771933d1-02 rootfstype=ext4 fsck.repair=yes rootwait cfg80211.ieee80211_regdom=EE ds=nocloud;i=rpi-imager-1775291628561'
mkdir -p /work && echo "cpuset cpu io pids" > /work/controllers && echo "$PI2" > /work/proc
# the playbook's own tasks from the command line's on, its paths and validator; the reads pointed at fixtures
python3 - <<'PYPLAY'
import yaml
p = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-restore-check.yml"))[0]
names = [t["name"] for t in p["tasks"]]
tasks = p["tasks"][names.index("The Pi's kernel command line"):]
v = {k: p["vars"][k] for k in ("pi_cmdline_path", "pi_cmdline_valid")}
v.update(pi_cgroup_controllers="/work/controllers", pi_booted_cmdline="/work/proc")
yaml.safe_dump([{"hosts": "localhost", "connection": "local", "gather_facts": False, "vars": v, "tasks": tasks}],
               open("/work/play.yml", "w"), sort_keys=False)
PYPLAY
run() {  # rc and the message's cause
  local out rc
  out=$(ANSIBLE_NOCOLOR=1 ansible-playbook -i localhost, /work/play.yml 2>&1); rc=$?
  grep -oE 'Errno [0-9]+[^"]*' <<< "$out" | head -1
  echo "rc=$rc $(grep -oE 'turns it on now: reboot it|turns it on: reboot it' <<< "$out" | head -1)"
}
printf '%s\n' "$PI2" > "$F"
check "pi2's line: both flags appended, said to reboot" "$(run | tail -1)" "rc=2 turns it on now: reboot it"
check "  one line, ending with both flags" \
  "$(grep -c '' "$F") $(grep -c ' ds=nocloud;i=rpi-imager-1775291628561 cgroup_enable=memory cgroup_memory=1$' "$F")" "1 1"
check "  the original kept (a FAT-safe name)" \
  "$(cmp -s <(printf '%s\n' "$PI2") "$F.before-memory-cgroup" && echo kept)" kept
check "the same run again: nothing changed, the original still the original" \
  "$(run | tail -1) $(cmp -s <(printf '%s\n' "$PI2") "$F.before-memory-cgroup" && echo kept) $(ls /boot/firmware | grep -c '^cmdline.txt')" \
  "rc=2 turns it on: reboot it kept 2"
rm "$F.before-memory-cgroup"
echo "console=tty1 root=X rootwait cgroup_enable=memory cgroup_memory=1" > "$F"
check "a line already right: nothing written, no copy made" \
  "$(run | tail -1 | cut -d' ' -f1) $(ls /boot/firmware | grep -c '^cmdline.txt')" "rc=2 1"
echo "FAT-CMDLINE: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
