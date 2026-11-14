#!/bin/bash
# scripts/copy-unit.sh - the upgrade cycle's proof of a Renovate unit on the copy - against throwaway repos (an origin
# and a clone each for infra, platform and ops; the unit's branches pushed to origin): its plan (--plan) for an infra
# and platform unit (test:copy:change on the branches, main where a repo has none), an ops Kubernetes bump
# (upgrade-kubeadm with the version, restarts expected), a Cilium bump (setup-kubeadm --tags cilium), the Pis' vars
# files (their upgrade playbooks, the branch's file passed, Vault's Vagrant vars beside), several at once in
# production's order; a value production's Argo charts carry (cert_manager_version) no playbook; refused: a changed
# value with no known proof, a value that is no version, no branch anywhere, a branch that changes nothing a proof
# runs, a name that is no unit's.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
OPS=$PWD
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }
for r in infra platform ops; do
  g init -q --bare "$W/origin/$r.git"
  g clone -q "$W/origin/$r.git" "$W/src/$r" 2> /dev/null
done
mkdir -p "$W/src/ops/deploy/ansible/playbooks" "$W/src/ops/deploy/ansible/vars" "$W/src/infra/clusters" "$W/src/platform/helm"
cat > "$W/src/ops/deploy/ansible/playbooks/setup-kubeadm.yml" <<'Y'
- name: kubeadm
  hosts: target
  vars:
    k8s_version: "1.36"
    k8s_package_version: "1.36.6-1.1"
    cilium_version: "1.20.4"
    cert_manager_version: "v1.21.3"
    some_other_version: "1.0"
  tasks: []
Y
printf 'forgejo_version: "15.0.11"\n' > "$W/src/ops/deploy/ansible/vars/forgejo.yml"
printf 'vault_version: "1.21.4"\n' > "$W/src/ops/deploy/ansible/vars/vault.yml"
printf 'patroni_version: "4.1.5"\n' > "$W/src/ops/deploy/ansible/vars/patroni.yml"
echo "image: a:1" > "$W/src/infra/clusters/v.yaml"; echo "image: b:1" > "$W/src/platform/helm/v.yaml"
for r in infra platform ops; do (cd "$W/src/$r" && g add -A && g commit -qm base && g push -q origin main 2> /dev/null); done
# unit <repo> <unit> <sed on a file> <file>: the unit's branch on origin, the clone left on main
unit() {
  (cd "$W/src/$1" && g switch -q -c "renovate/$2" && sed -i "$3" "$4" && g commit -qam "$2" && g push -q origin "renovate/$2" 2> /dev/null \
    && g switch -q main && g branch -q -D "renovate/$2")
}
unit infra wave-patches 's/a:1/a:2/' clusters/v.yaml
unit platform wave-patches 's/b:1/b:2/' helm/v.yaml
unit infra observability 's/a:1/a:3/' clusters/v.yaml
unit ops kubernetes-1.36.7 's/1.36.6-1.1/1.36.7-1.1/' deploy/ansible/playbooks/setup-kubeadm.yml
unit ops cilium-1.21 's/"1.20.4"/"1.21.0"/' deploy/ansible/playbooks/setup-kubeadm.yml
unit ops forgejo 's/15.0.11/15.0.12/' deploy/ansible/vars/forgejo.yml
unit ops vault 's/1.21.4/1.21.5/' deploy/ansible/vars/vault.yml
unit ops follows 's/v1.21.3/v1.21.4/' deploy/ansible/playbooks/setup-kubeadm.yml
unit ops unknown 's/"1.0"/"1.1"/' deploy/ansible/playbooks/setup-kubeadm.yml
unit ops bad-value 's/"1.20.4"/"1.21.0; rm -rf x"/' deploy/ansible/playbooks/setup-kubeadm.yml
(cd "$W/src/ops" && g switch -q -c renovate/pis && sed -i 's/15.0.11/15.0.12/' deploy/ansible/vars/forgejo.yml \
  && sed -i 's/4.1.5/4.1.6/' deploy/ansible/vars/patroni.yml && sed -i 's/1.36.6-1.1/1.36.7-1.1/' deploy/ansible/playbooks/setup-kubeadm.yml \
  && g commit -qam pis && g push -q origin renovate/pis 2> /dev/null && g switch -q main && g branch -q -D renovate/pis)
(cd "$W/src/ops" && g switch -q -c renovate/docs-only && echo x > README && g add README && g commit -qm d \
  && g push -q origin renovate/docs-only 2> /dev/null && g switch -q main && g branch -q -D renovate/docs-only)
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi; }
plan() { COPY_UNIT_SRC="$W/src" bash "$OPS/scripts/copy-unit.sh" "$1" --plan 2>&1; }
check "infra and platform: test:copy:change on both branches" "$(plan wave-patches)" \
  "test:copy:change INFRA_REF=renovate/wave-patches PLATFORM_REF=renovate/wave-patches"
check "infra alone: platform's main stands for it" "$(plan observability)" \
  "test:copy:change INFRA_REF=renovate/observability PLATFORM_REF=main"
check "Kubernetes: upgrade-kubeadm to the version (the package's revision dropped), restarts expected" "$(plan kubernetes-1.36.7)" \
  "test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml ARGS='-e k8s_upgrade_to=1.36.7' RESTARTS_EXPECTED=true"
check "Cilium: setup-kubeadm's Cilium tasks at the version" "$(plan cilium-1.21)" \
  "test:copy:playbook PLAYBOOK=setup-kubeadm.yml ARGS='--tags cilium -e cilium_version=1.21.0'"
out=$(plan forgejo)
f=$(sed -n "s/^test:copy:playbook PLAYBOOK=upgrade-forgejo.yml ARGS='-e @\([^']*\)'$/\1/p" <<< "$out")
check "Forgejo: upgrade-forgejo with the branch's vars file" "$( [ -n "$f" ] && cat "$f")" 'forgejo_version: "15.0.12"'
check "  written in the ops repo's .copy (not this one's)" "$(case "$f" in "$W/src/ops/.copy/"*) echo yes;; *) echo "no: $f";; esac)" yes
out=$(plan vault)
check "Vault: upgrade-vault with the branch's vars, the Vagrant vars beside" \
  "$(sed -E "s/@[^ ]*vault.yml/@VAULT/" <<< "$out")" "test:copy:playbook PLAYBOOK=upgrade-vault.yml ARGS='-e @VAULT -e @vars/vault-vagrant.yml'"
out=$(plan pis)
check "several parts at once: Kubernetes first, then Patroni, then Forgejo (production's order)" \
  "$(sed -nE 's/^test:copy:playbook PLAYBOOK=([a-z-]+\.yml).*/\1/p' <<< "$out" | tr '\n' ' ')" "upgrade-kubeadm.yml upgrade-patroni.yml upgrade-forgejo.yml "
out=$(plan follows); rc=$?
check "a value production's Argo charts carry: no playbook for it - nothing to prove from ops, refused as such" \
  "$rc $(grep -c 'nothing to prove' <<< "$out")" "1 1"
out=$(plan unknown); rc=$?
check "a changed value with no known proof: refused, named" "$rc $(grep -c 'REFUSED.*some_other_version' <<< "$out")" "1 1"
out=$(plan bad-value); rc=$?
check "a value that is no version (a command in it): refused" "$rc $(grep -c 'REFUSED.*no version' <<< "$out")" "1 1"
out=$(plan docs-only); rc=$?
check "a branch changing nothing a proof runs: refused" "$rc $(grep -c 'nothing to prove' <<< "$out")" "1 1"
out=$(plan no-such); rc=$?
check "no branch anywhere: refused, no such unit" "$rc $(grep -c 'no such unit' <<< "$out")" "1 1"
out=$(plan 'Bad/Name'); rc=$?
check "a name that is no unit's: refused before anything" "$rc $(grep -c '^REFUSED' <<< "$out")" "2 1"
check "the clones stay on main (the unit's branches fetched beside, never checked out)" \
  "$(for r in infra platform ops; do git -C "$W/src/$r" branch --show-current; done | sort -u)" "main"
echo "copy-unit: $([ $fails -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails -eq 0 ]
