#!/bin/bash
# The Wave 0 copies' room check (tasks/upgrade-backup-space.yml) on localhost, du, df, kubectl and containerd stubbed:
# room for the copy and the kubelet's eviction floor (15% of the filesystem) kept after it passes; room for the copy
# that would end under the floor is refused, naming it; too little room for the copy is refused. On the image store's
# filesystem (containerd's root - ten's one disk) the copy must also leave it under the kubelet's image GC threshold
# less 5 (its configz): the merge's pre-pull refuses past it (tasks/image-store-room.yml) - a copy ending between 80%
# and 85% passed here and blocked the step's merge. And the Pi backup store (the gateway's own backend directory, from
# its unit) keeps 10% of its volume free after the copy: a full store stops CNPG's WAL archiving too.
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
printf '#!/bin/sh\ncase "$*" in *avail,size*) printf "Avail Size\\n%%s %%s\\n" "$STORE_FREE" "$STORE_SIZE";; *avail*) printf "Avail\\n%%s\\n" "$FREE";; *size*) printf "Size\\n%%s\\n" "$SIZE";;\n  *source*/z*) printf "Filesystem\\n/dev/%%s\\n" "${STORE_DEV:-a}";; *source*) printf "Filesystem\\n/dev/a\\n";; esac\n' > "$W/df"
# the kubelet's configz (its image GC threshold) and containerd's root; the gateway's unit (its backend directory)
printf '#!/bin/sh\necho "{ path=/usr/bin/versitygw ; argv[]=/usr/bin/versitygw --port :9000 posix --sidecar /s/.sidecar /s/buckets ; ignore_errors=no }"\n' > "$W/systemctl"
chmod +x "$W/systemctl"
printf '#!/bin/sh\necho "{\\"kubeletconfig\\": {\\"imageGCHighThresholdPercent\\": ${GC_HIGH:-85}}}"\n' > "$W/kubectl"
# containerd 1.7 quotes its root "/z", 2.x '/z' (QUOTE=1)
printf '#!/bin/sh\nif [ -n "$QUOTE" ]; then printf "version = 4\\nroot = \x27/z\x27\\n"; else printf "version = 2\\nroot = \\"/z\\"\\n"; fi\n' > "$W/containerd"
chmod +x "$W/du" "$W/df" "$W/kubectl" "$W/containerd"
cat > "$W/play.yml" <<PLAY
- hosts: localhost
  gather_facts: false
  vars:
    space_dirs: [/x]
    local_dir: /y
    upload_part_bytes: 0
    kubeconfig: /k
    upgrade_backup_store_host: localhost
  tasks:
    - ansible.builtin.include_tasks: $ROOT/deploy/ansible/playbooks/tasks/upgrade-backup-space.yml
PLAY
fails=0
case_() {  # name, want (0 passes / 1 fails), output must contain, SRC FREE SIZE (GiB)
  local name=$1 want=$2 grep=$3
  out=$(env PATH="$W:$PATH" SRC=$(($4 * GiB)) FREE=$(($5 * GiB)) SIZE=$(($6 * GiB)) STORE_DEV=${7:-a} QUOTE=${QUOTE:-} \
        STORE_FREE=$(( ${STORE_FREE_GIB:-1000} * GiB )) STORE_SIZE=$(( ${STORE_SIZE_GIB:-2000} * GiB )) ANSIBLE_NOCOLOR=1 \
        "$AP" -c local -i localhost, "$W/play.yml" 2>&1); rc=$?; [ "$rc" = 0 ] || rc=1
  if [ "$rc" = "$want" ] && { [ -z "$grep" ] || grep -qF -- "$grep" <<< "$out"; }; then echo "PASS $name"
  else echo "FAIL $name (rc $rc, want $want)"; printf '%s\n' "$out" | tail -5 | sed 's/^/    /'; fails=$((fails + 1)); fi
}
case_ "room for the copy, the floor kept after it" 0 "" 10 300 900
case_ "room for the copy, under the eviction floor after it" 1 "under the kubelet's eviction floor" 170 300 900
case_ "no room for the copy" 1 "not enough room" 310 300 900
# 900 GiB, 300 free: a 130 GiB copy ends at 81.1% used - above the floor (15%), past the image store's 80%
# the refusal by its number - 20% of 900 GiB (the failed task's cmd, printed beside it, holds the words without it)
case_ "on the image store's filesystem: a copy past its GC threshold less 5 refused" 1 "past the image store's bound 193273528320" 130 300 900
case_ "  the image store elsewhere: the eviction floor alone" 0 "" 130 300 900 b
QUOTE=1 case_ "  containerd 2.x's quoting: the same refusal" 1 "past the image store's bound 193273528320" 130 300 900
case_ "  a copy that stays under it passes" 0 "" 100 300 900
# the store: 2000 GiB, 10% kept free (200 GiB) - a 100 GiB copy fits in 400 GiB free, not in 250
STORE_FREE_GIB=400 case_ "the Pi store: room for the copy and 10% of its volume after it" 0 "" 100 300 900 b
STORE_FREE_GIB=250 case_ "  under 10% free after it: refused" 1 "the Pi store would keep 161061273600 bytes free" 100 300 900 b
echo "backup-space: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
exit $((fails > 0))
