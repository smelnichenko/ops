#!/bin/bash
# The Wave 0 copies' room check (tasks/upgrade-backup-space.yml) on localhost, du and df stubbed: room for the copy
# and the kubelet's eviction floor (15% of the filesystem) kept after it passes; room for the copy that would end under
# the floor is refused, naming it; too little room for the copy is refused.
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "backup-space: no ansible-playbook found (PATH, repo venv)"; exit 2; }
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
GiB=1073741824
# du -sbc: the sources' size (SRC); df --output=avail|size -B1: FREE and SIZE
printf '#!/bin/sh\nprintf "%%s\\ttotal\\n" "$SRC"\n' > "$W/du"
printf '#!/bin/sh\ncase "$*" in *avail*) printf "Avail\\n%%s\\n" "$FREE";; *size*) printf "Size\\n%%s\\n" "$SIZE";; esac\n' > "$W/df"
chmod +x "$W/du" "$W/df"
cat > "$W/play.yml" <<PLAY
- hosts: localhost
  gather_facts: false
  vars:
    space_dirs: [/x]
    local_dir: /y
    upload_part_bytes: 0
  tasks:
    - ansible.builtin.include_tasks: $ROOT/deploy/ansible/playbooks/tasks/upgrade-backup-space.yml
PLAY
fails=0
case_() {  # name, want (0 passes / 1 fails), output must contain, SRC FREE SIZE (GiB)
  local name=$1 want=$2 grep=$3
  out=$(env PATH="$W:$PATH" SRC=$(($4 * GiB)) FREE=$(($5 * GiB)) SIZE=$(($6 * GiB)) ANSIBLE_NOCOLOR=1 \
        "$AP" -c local -i localhost, "$W/play.yml" 2>&1); rc=$?; [ "$rc" = 0 ] || rc=1
  if [ "$rc" = "$want" ] && { [ -z "$grep" ] || grep -qF -- "$grep" <<< "$out"; }; then echo "PASS $name"
  else echo "FAIL $name (rc $rc, want $want)"; printf '%s\n' "$out" | tail -5 | sed 's/^/    /'; fails=$((fails + 1)); fi
}
case_ "room for the copy, the floor kept after it" 0 "" 10 300 900
case_ "room for the copy, under the eviction floor after it" 1 "under the kubelet's eviction floor" 170 300 900
case_ "no room for the copy" 1 "not enough room" 310 300 900
echo "backup-space: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
exit $((fails > 0))
