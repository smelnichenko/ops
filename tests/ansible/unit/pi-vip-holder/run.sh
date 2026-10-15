#!/bin/bash
# The Pi holding the VIP (tasks/pi-vip-holder.yml), each Pi's `ip` stubbed (its own PATH, through its own interpreter)
# and an unreachable Pi's ssh refused: the holder found whichever Pi it is, also while the other is down (the case a
# task pinned to the first Pi failed); no Pi holding it and both holding it refused, saying so; an address the VIP
# is the start of (192.168.11.50 for .5) is not it; the VIP's prefix length whatever it is (production's is /24).
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "pi-vip-holder: no ansible-playbook found (PATH, repo venv)"; exit 2; }
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
PY=$(command -v python3)
for pi in pi1 pi2; do
  mkdir -p "$W/$pi"
  # `ip -o -4 addr show to <vip>/32` as iproute2 prints it: the line when this Pi has the address ($ADDR_<pi>), nothing else
  printf '#!/bin/sh\na=$(eval echo "\\${ADDR_%s:-}")\n[ -n "$a" ] && printf "2: eth0    inet %%s scope global secondary proto 0x12 eth0\\\\       valid_lft forever preferred_lft forever\\n" "$a"\nexit 0\n' \
    "$pi" > "$W/$pi/ip"
  printf '#!/bin/sh\nPATH="%s:$PATH" exec "%s" "$@"\n' "$W/$pi" "$PY" > "$W/py-$pi"
  chmod +x "$W/$pi/ip" "$W/py-$pi"
done
# a Pi that is down: its ssh refused as ssh says it (exit 255) - this harness's own, before the unit runner's fence
printf '#!/bin/sh\necho "ssh: connect to host 192.0.2.1 port 22: Connection timed out" >&2\nexit 255\n' > "$W/ssh"
chmod +x "$W/ssh"
cat > "$W/play.yml" <<PLAY
- hosts: localhost
  gather_facts: false
  vars:
    keepalived_vip: 192.168.11.5
  tasks:
    - ansible.builtin.include_tasks: $ROOT/deploy/ansible/playbooks/tasks/pi-vip-holder.yml
    - ansible.builtin.debug:
        msg: "HOLDER={{ pi_vip_holder }}"
PLAY
inv() {  # the Pis down given as arguments: reached over ssh (refused), the others locally through their own PATH
  printf 'all:\n  hosts:\n    localhost: { ansible_connection: local, ansible_python_interpreter: %s }\n  children:\n    pis:\n      hosts:\n' "$PY"
  for pi in pi1 pi2; do
    case " $* " in
      *" $pi "*) printf '        %s: { ansible_connection: ssh, ansible_host: 192.0.2.1 }\n' "$pi" ;;
      *) printf '        %s: { ansible_connection: local, ansible_python_interpreter: %s }\n' "$pi" "$W/py-$pi" ;;
    esac
  done
}
fails=0
case_() {  # name, want (0 passes / 1 fails), output must contain, pi1's address, pi2's address, [the Pis down]
  local name=$1 want=$2 grep=$3 a1=$4 a2=$5; shift 5
  inv "$@" > "$W/inv.yml"
  out=$(env PATH="$W:$PATH" ADDR_pi1="$a1" ADDR_pi2="$a2" ANSIBLE_NOCOLOR=1 ANSIBLE_HOST_KEY_CHECKING=0 \
        "$AP" -i "$W/inv.yml" "$W/play.yml" 2>&1); rc=$?; [ "$rc" = 0 ] || rc=1
  if [ "$rc" = "$want" ] && grep -qF -- "$grep" <<< "$out"; then echo "PASS $name"
  else echo "FAIL $name (rc $rc, want $want)"; printf '%s\n' "$out" | grep -E 'HOLDER|msg|FAILED|fatal' | tail -4 | sed 's/^/    /'
    fails=$((fails + 1)); fi
}
case_ "pi1 holds the VIP: pi1" 0 "HOLDER=pi1" 192.168.11.5/24 ""
case_ "pi2 holds the VIP: pi2" 0 "HOLDER=pi2" "" 192.168.11.5/24
case_ "pi1 down, pi2 holds the VIP: pi2 (the first Pi pinned failed here)" 0 "HOLDER=pi2" "" 192.168.11.5/24 pi1
case_ "  a /32 VIP the same" 0 "HOLDER=pi2" "" 192.168.11.5/32 pi1
case_ "no Pi holds it: refused, saying so" 1 "no Pi holds the VIP 192.168.11.5" "" ""
case_ "  pi1 down and pi2 without it: refused, pi1 named unreachable" 1 "unreachable: pi1" "" "" pi1
case_ "both hold it (a split keepalived): refused, both named" 1 "held by pi1 and pi2" 192.168.11.5/24 192.168.11.5/24
case_ "an address the VIP is the start of (.50) is not the VIP" 1 "no Pi holds the VIP" 192.168.11.50/24 ""
echo "pi-vip-holder: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
exit $((fails > 0))
