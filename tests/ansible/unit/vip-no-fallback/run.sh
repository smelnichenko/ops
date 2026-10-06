#!/bin/bash
# The Pis' floating address comes from the inventory alone: production's and the Vagrant copy's state it, and no
# playbook falls back to one or writes production's out - a fallback to production's address let a run against an inventory without it reach
# production (the copy is fenced off, but the run then tests nothing it meant to).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AI=$(command -v ansible-inventory 2>/dev/null \
  || { [ -x deploy/ansible/venv/bin/ansible-inventory ] && echo deploy/ansible/venv/bin/ansible-inventory; })
[ -x "${AI:-}" ] || { echo "vip-no-fallback: no ansible-inventory found (PATH, repo venv)"; exit 2; }
fails=0
check() {  # name, ok (0/1)
  if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
vip() { "$AI" -i "deploy/ansible/inventory/$1.yml" --host "$2" 2>/dev/null < /dev/null \
  | python3 -c 'import json, sys; print(json.load(sys.stdin).get("keepalived_vip", ""))'; }
[ "$(vip production pi1)" = 192.168.11.5 ]; check "production's inventory states it (pi1)" $?
[ "$(vip production target)" = 192.168.11.5 ]; check "production's inventory states it (ten)" $?
[ "$(vip vagrant pi1)" = 192.168.56.50 ]; check "the copy's inventory states its own" $?
# any fallback spelling (default, d), and production's VIP written out anywhere but a comment
hits=$(grep -rnE "keepalived_vip *\| *(default|d) *\(" deploy/ansible/playbooks)
[ -z "$hits" ]; check "no playbook falls back for the VIP${hits:+: $hits}" $?
hits=$(grep -rnE "192\.168\.11\.5([^0-9]|$)" deploy/ansible/playbooks | grep -vE '^[^:]+:[0-9]+: *#')
[ -z "$hits" ]; check "production's VIP in no playbook${hits:+: $hits}" $?
echo "vip-no-fallback: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
