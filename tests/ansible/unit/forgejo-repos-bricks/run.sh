#!/bin/bash
# setup-gluster's guard before a new forgejo-repos volume (tasks/forgejo-repos-bricks-empty.yml), on localhost with
# temporary bricks: all empty goes on; pi2's brick holding anything refuses; pi1's holding something refuses unless the
# playbook's mark is there (its own half-done copy), which goes on.
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "forgejo-repos-bricks: no ansible-playbook found (PATH, repo venv)"; exit 2; }
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cat > "$W/play.yml" <<PLAY
- hosts: localhost
  gather_facts: false
  vars:
    forgejo_repos_mark: $W/mark
    forgejo_repos_bricks:
      - {host: localhost, brick: $W/pi1, may_hold_copy: true}
      - {host: localhost, brick: $W/pi2, may_hold_copy: false}
      - {host: localhost, brick: $W/arbiter, may_hold_copy: false}
  tasks:
    - ansible.builtin.include_tasks: $ROOT/deploy/ansible/playbooks/tasks/forgejo-repos-bricks-empty.yml
PLAY
fails=0
case_() {  # name, want (0 goes on / 1 refused), output must contain; set up by the caller
  out=$(ANSIBLE_NOCOLOR=1 "$AP" -c local -i localhost, "$W/play.yml" 2>&1); rc=$?; [ "$rc" = 0 ] || rc=1
  if [ "$rc" = "$2" ] && { [ -z "$3" ] || grep -qF -- "$3" <<< "$out"; }; then echo "PASS $1"
  else echo "FAIL $1 (rc $rc, want $2)"; printf '%s\n' "$out" | tail -4 | sed 's/^/    /'; fails=$((fails + 1)); fi
}
reset() { rm -rf "$W/pi1" "$W/pi2" "$W/arbiter" "$W/mark"; mkdir -p "$W/pi1" "$W/pi2" "$W/arbiter"; }
reset; case_ "every brick empty: goes on" 0 ""
reset; touch "$W/pi2/leftover"; case_ "pi2's brick not empty: refused" 1 "$W/pi2 on localhost is not empty"
reset; mkdir "$W/arbiter/.glusterfs"; case_ "the arbiter's brick holding a volume's metadata: refused" 1 "$W/arbiter"
reset; touch "$W/pi1/repo"; case_ "pi1's not empty, no mark: refused" 1 "$W/pi1 on localhost is not empty"
reset; touch "$W/pi1/repo" "$W/mark"; case_ "pi1's holding the playbook's own copy (marked): goes on" 0 ""
reset; touch "$W/pi2/leftover" "$W/mark"; case_ "the mark covers pi1's brick only: pi2's refused" 1 "$W/pi2"
echo "forgejo-repos-bricks: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
