#!/bin/bash
# scripts/copy-unit.sh - the upgrade cycle's proof of a Renovate unit on the copy - against throwaway repos (an origin
# and a clone each for infra, platform and ops; the unit's branches pushed to origin): its plan (--plan) for an infra
# and platform unit (test:copy:change on the branches, main where a repo has none), an ops Kubernetes bump
# (upgrade-kubeadm with the version, restarts expected), a Cilium bump (setup-kubeadm --tags cilium), the Pis' vars
# files (their upgrade playbooks, the branch's file passed, Vault's Vagrant vars beside), several at once in
# production's order; a value production's Argo charts carry (cert_manager_version) no playbook; refused: a changed
# value with no known proof, a value that is no version, no branch anywhere, a branch that changes nothing a proof
# runs, a name that is no unit's. Argo CD's and node_exporter's new values handed to main's playbook (else main's version
# is proven); a value handed to Ansible that is no version or hash (a template, a connection setting, a YAML tag) and a
# changed task in setup-kubeadm refused.
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
    cnpg_chart_version: "0.29.1"
    some_other_version: "1.0"
  tasks: []
Y
cat > "$W/src/ops/deploy/ansible/playbooks/setup-argocd.yml" <<'Y'
- name: argocd
  hosts: target
  vars:
    argocd_chart_default: "10.9.7"
    argocd_chart_version: "{{ argocd_version | default(argocd_chart_default) }}"
    argocd_image_pins:
      "10.2.2": v3.4.10
    argocd_namespace: argocd
  tasks: []
Y
cat > "$W/src/ops/deploy/ansible/playbooks/setup-host-hardening.yml" <<'Y'
- name: hardening
  hosts: target
  vars:
    node_exporter_version: "1.12.1"
    node_exporter_sha256: "b51d8a76aa2a9156a55d501aca6276fae09e262259a5e4e831d2c2222f084e63"
    node_exporter_port: 9100
  tasks: []
Y
cat > "$W/src/ops/deploy/ansible/playbooks/setup-caddy.yml" <<'Y'
- name: caddy
  hosts: pi1,pi2
  vars:
    caddy_version: "2.10.0"
    peer_ip: "10.0.0.2"
  tasks: []
Y
cat > "$W/src/ops/deploy/ansible/playbooks/setup-consul.yml" <<'Y'
- name: consul
  hosts: pi1,pi2,target
  vars:
    consul_version: "1.20.6"
    consul_checksums:
      arm64: 96ba60faadde5d92f36d536818a6382159344983c79529015e5d991fd1199d4b
      amd64: 37fc6f213a44c6db3a2b912966fb1415939e9b189ce1bc1eb07b7f87449a28c2
    consul_datacenter: "schnappy"
  tasks: []
Y
cat > "$W/src/ops/deploy/ansible/playbooks/setup-istio.yml" <<'Y'
- name: istio
  hosts: target
  vars:
    istio_version: "1.31.1"
  tasks: []
Y
printf 'forgejo_version: "15.0.11"\nforgejo_checksums:\n  arm64: %s\n' "$(printf 'cd%.0s' $(seq 32))" > "$W/src/ops/deploy/ansible/vars/forgejo.yml"
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
unit ops argocd 's/"10.9.7"/"10.18.0"/' deploy/ansible/playbooks/setup-argocd.yml
unit ops argocd-pin 's/v3.4.10/v3.4.11/' deploy/ansible/playbooks/setup-argocd.yml
unit ops argocd-ns 's/argocd_namespace: argocd/argocd_namespace: elsewhere/' deploy/ansible/playbooks/setup-argocd.yml
unit ops argocd-tasks 's/tasks: \[\]/tasks: [{debug: {msg: x}}]/' deploy/ansible/playbooks/setup-argocd.yml
unit ops argocd-bad 's/"10.9.7"/"10.18.0 -e x=y"/' deploy/ansible/playbooks/setup-argocd.yml
unit ops node-exporter 's/"1.12.1"/"1.13.0"/; s/b51d8a76aa2a9156a55d501aca6276fae09e262259a5e4e831d2c2222f084e63/'"$(printf 'ab%.0s' $(seq 32))"'/' deploy/ansible/playbooks/setup-host-hardening.yml
unit ops node-exporter-port 's/node_exporter_port: 9100/node_exporter_port: 9101/' deploy/ansible/playbooks/setup-host-hardening.yml
unit ops caddy 's/"2.10.0"/"2.10.2"/' deploy/ansible/playbooks/setup-caddy.yml
unit ops consul 's/"1.20.6"/"1.20.7"/; s/96ba60faadde5d92f36d536818a6382159344983c79529015e5d991fd1199d4b/1111111111111111111111111111111111111111111111111111111111111111/; s/37fc6f213a44c6db3a2b912966fb1415939e9b189ce1bc1eb07b7f87449a28c2/2222222222222222222222222222222222222222222222222222222222222222/' deploy/ansible/playbooks/setup-consul.yml
unit ops consul-dc 's/"1.20.6"/"1.20.7"/; s/"schnappy"/"other"/' deploy/ansible/playbooks/setup-consul.yml
unit ops consul-task 's/"1.20.6"/"1.20.7"/; s/tasks: \[\]/tasks: [{name: x, command: id}]/' deploy/ansible/playbooks/setup-consul.yml
unit ops caddy-peer 's/"2.10.0"/"2.10.2"/; s/10.0.0.2/10.0.0.3/' deploy/ansible/playbooks/setup-caddy.yml
unit ops caddy-task 's/"2.10.0"/"2.10.2"/; s/tasks: \[\]/tasks: [{name: x, command: id}]/' deploy/ansible/playbooks/setup-caddy.yml
unit ops caddy-bad 's/"2.10.0"/"2.10.2 -e x=y"/' deploy/ansible/playbooks/setup-caddy.yml
# Istio's version restated in setup-istio.yml moves with infra's istiod chart (wave-patches, 2026-11-16)
unit infra istio-follow 's/a:1/a:4/' clusters/v.yaml
unit ops istio-follow 's/"1.31.1"/"1.31.4"/' deploy/ansible/playbooks/setup-istio.yml
unit infra istio-task 's/a:1/a:5/' clusters/v.yaml
# a data operator's chart version restated in setup-kubeadm's play vars moves with infra's chart (2026-11-17)
unit infra data-follow 's/a:1/a:7/' clusters/v.yaml
unit ops data-follow 's/"0.29.1"/"0.29.2"/' deploy/ansible/playbooks/setup-kubeadm.yml
unit ops istio-task 's/"1.31.1"/"1.31.4"/; s/tasks: \[\]/tasks: [{name: x, command: id}]/' deploy/ansible/playbooks/setup-istio.yml
unit ops istio-alone 's/"1.31.1"/"1.31.4"/' deploy/ansible/playbooks/setup-istio.yml
unit infra istio-other 's/a:1/a:6/' clusters/v.yaml
unit ops istio-other 's/istio_version: "1.31.1"/istio_version: "1.31.1"\n    istio_cni_version: "1.31.4"/' deploy/ansible/playbooks/setup-istio.yml
# what the copy hands Ansible on this workstation: a version or a hash, never a template, never a connection setting
unit ops vault-jinja 's/"1.21.4"/"{{ lookup('"'"'pipe'"'"', '"'"'id'"'"') }}"/' deploy/ansible/vars/vault.yml
unit ops forgejo-conn 's/^forgejo_version: "15.0.11"$/forgejo_version: "15.0.12"\nansible_ssh_common_args: "1"/' deploy/ansible/vars/forgejo.yml
unit ops forgejo-hash-jinja 's/: cdcd[c-d]*$/: "{{ x }}"/' deploy/ansible/vars/forgejo.yml
unit ops forgejo-vault-tag 's/"15.0.11"/!vault |\n  $ANSIBLE_VAULT;1.1;AES256/' deploy/ansible/vars/forgejo.yml
unit ops argocd-pin-jinja 's/v3.4.10/"{{ lookup('"'"'env'"'"', '"'"'HOME'"'"') }}"/' deploy/ansible/playbooks/setup-argocd.yml
unit ops kubeadm-task 's/tasks: \[\]/tasks: [{name: x, command: id, tags: [cilium]}]/; s/"1.20.4"/"1.21.0"/' deploy/ansible/playbooks/setup-kubeadm.yml
unit ops kubeadm-follow-jinja 's/"v1.21.3"/"{{ lookup('"'"'pipe'"'"', '"'"'id'"'"') }}"/; s/"1.20.4"/"1.21.0"/' deploy/ansible/playbooks/setup-kubeadm.yml
unit ops argocd-task 's/"10.9.7"/"10.18.0"/; s/tasks: \[\]/tasks: [{name: x, command: id}]/' deploy/ansible/playbooks/setup-argocd.yml
unit ops node-exporter-task 's/"1.12.1"/"1.13.0"/; s/tasks: \[\]/tasks: [{name: x, command: id}]/' deploy/ansible/playbooks/setup-host-hardening.yml
# a vars file as production's is: its unchanged values no versions (an arch, a host name) - its version moved alone
(cd "$W/src/ops" && printf 'vault_version: "1.21.4"\nvault_arch: "arm64"\nvault_pi_dns: "vault.schnappy.io"\nvault_checksums:\n  arm64: %s\n  amd64: %s\nvault_unseal_shares: 3\nvault_tls: true\nvault_peers: ["1.0.0", "1.0.1"]\n' "$(printf 'aa%.0s' $(seq 32))" "$(printf 'bb%.0s' $(seq 32))" > deploy/ansible/vars/vault.yml \
  && g commit -qam "vault vars as production's" && g push -q origin main 2> /dev/null)
unit ops vault-real 's/"1.21.4"/"1.21.5"/; s/  arm64: aa*$/  arm64: '"$(printf 'cc%.0s' $(seq 32))"'/' deploy/ansible/vars/vault.yml
unit ops vault-flag 's/vault_tls: true/vault_tls: false/; s/"1.21.4"/"1.21.5"/' deploy/ansible/vars/vault.yml
unit ops vault-list 's/\["1.0.0", "1.0.1"\]/["1.0.0", "1.0.2"]/; s/"1.21.4"/"1.21.5"/' deploy/ansible/vars/vault.yml
unit ops vault-list-jinja 's/\["1.0.0", "1.0.1"\]/["1.0.0", "{{ x }}"]/' deploy/ansible/vars/vault.yml
unit ops vault-nested-jinja 's/  amd64: bb*$/  amd64: "{{ lookup('"'"'pipe'"'"', '"'"'id'"'"') }}"/' deploy/ansible/vars/vault.yml
(cd "$W/src/ops" && g switch -q -c renovate/pis && sed -i 's/15.0.11/15.0.12/' deploy/ansible/vars/forgejo.yml \
  && sed -i 's/4.1.5/4.1.6/' deploy/ansible/vars/patroni.yml && sed -i 's/1.36.6-1.1/1.36.7-1.1/' deploy/ansible/playbooks/setup-kubeadm.yml \
  && g commit -qam pis && g push -q origin renovate/pis 2> /dev/null && g switch -q main && g branch -q -D renovate/pis)
(cd "$W/src/ops" && g switch -q -c renovate/docs-only && echo x > README && g add README && g commit -qm d \
  && g push -q origin renovate/docs-only 2> /dev/null && g switch -q main && g branch -q -D renovate/docs-only)
# a unit that also changes what vouches for the build hashes (a vendor's key) - the operator's, never a unit's
(cd "$W/src/ops" && g switch -q -c renovate/vault-keyed && sed -i 's/1.21.4/1.21.5/' deploy/ansible/vars/vault.yml \
  && mkdir -p renovate/keys && echo key > renovate/keys/hashicorp.asc && g add -A && g commit -qm k \
  && g push -q origin renovate/vault-keyed 2> /dev/null && g switch -q main && g branch -q -D renovate/vault-keyed)
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
check "Forgejo: upgrade-forgejo with the branch's vars file" "$( [ -n "$f" ] && head -1 "$f")" 'forgejo_version: "15.0.12"'
check "  written in the ops repo's .copy (not this one's)" "$(case "$f" in "$W/src/ops/.copy/"*) echo yes;; *) echo "no: $f";; esac)" yes
out=$(plan vault)
check "Vault: upgrade-vault with the branch's vars, the Vagrant vars beside" \
  "$(sed -E "s/@[^ ]*vault.yml/@VAULT/" <<< "$out")" "test:copy:playbook PLAYBOOK=upgrade-vault.yml ARGS='-e @VAULT -e @vars/vault-vagrant.yml'"
out=$(plan pis)
check "several parts at once: Kubernetes first, then Patroni, then Forgejo (production's order)" \
  "$(sed -nE 's/^test:copy:playbook PLAYBOOK=([a-z-]+\.yml).*/\1/p' <<< "$out" | tr '\n' ' ')" "upgrade-kubeadm.yml upgrade-patroni.yml upgrade-forgejo.yml "
# the copy runs main's playbook: the unit's new values must reach it (-e), or main's version is what gets proven
vars_of() { sed -n "s/^test:copy:playbook PLAYBOOK=$1 ARGS='-e @\([^ ']*\).*/\1/p" <<< "$2"; }
out=$(plan argocd); f=$(vars_of setup-argocd.yml "$out")
check "Argo CD's chart: setup-argocd on the copy with the branch's chart version handed to it, its Vault values beside, its pods restarting" \
  "$(sed "s|@$f|@VARS|" <<< "$out") | $( [ -n "$f" ] && cat "$f")" \
  "test:copy:playbook PLAYBOOK=setup-argocd.yml ARGS='-e @VARS -e @vars/vault-vagrant.yml' RESTARTS_EXPECTED=true | argocd_chart_default: 10.18.0"
out=$(plan argocd-pin); f=$(vars_of setup-argocd.yml "$out")
check "an image pinned on a chart: the same proof, the branch's pins handed to it" "$( [ -n "$f" ] && tr '\n' ' ' < "$f")" \
  "argocd_image_pins:   10.2.2: v3.4.11 "
out=$(plan argocd-ns); rc=$?
check "another setup-argocd value: refused, named" "$rc $(grep -c 'REFUSED.*setup-argocd.yml argocd_namespace' <<< "$out")" "1 1"
out=$(plan argocd-tasks); rc=$?
check "setup-argocd's tasks changed, no value: refused" "$rc $(grep -c 'REFUSED.*setup-argocd.yml (its tasks)' <<< "$out")" "1 1"
out=$(plan argocd-bad); rc=$?
check "Argo CD's chart no version: refused" "$rc $(grep -c 'REFUSED.*no version' <<< "$out")" "1 1"
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
out=$(plan node-exporter); f=$(vars_of setup-host-hardening.yml "$out")
check "node_exporter's version and its hash: production's setup-host-hardening on the copy, the branch's two handed to it" \
  "$(sed "s|@$f|@VARS|" <<< "$out") | $( [ -n "$f" ] && tr '\n' ' ' < "$f")" \
  "test:copy:playbook PLAYBOOK=setup-host-hardening.yml ARGS='-e @VARS' | node_exporter_sha256: $(printf 'ab%.0s' $(seq 32)) node_exporter_version: 1.13.0 "
for u in vault-jinja forgejo-conn forgejo-hash-jinja forgejo-vault-tag argocd-pin-jinja; do
  out=$(plan "$u"); rc=$?
  check "  $u: a value the copy would hand Ansible that is no version or hash (a template, a connection setting, a tag): refused" \
    "$rc $(grep -c '^REFUSED' <<< "$out") $(grep -c 'test:copy:playbook' <<< "$out")" "1 1 0"
done
out=$(plan kubeadm-task); rc=$?
check "setup-kubeadm's tasks changed beside its Cilium version (main's tasks are what the copy runs): refused" \
  "$rc $(grep -c 'REFUSED.*setup-kubeadm.yml (its tasks)' <<< "$out")" "1 1"
for u in argocd-task node-exporter-task; do
  out=$(plan "$u"); rc=$?
  check "  $u: its playbook's tasks changed beside its version (production would run them, the copy main's): refused" \
    "$rc $(grep -c '(its tasks)' <<< "$out")" "1 1"
done
out=$(plan kubeadm-follow-jinja); rc=$?
check "a value production's charts carry (no proof of its own) made a template beside a Cilium bump: refused (no-downgrade's loop renders every value)" \
  "$rc $(grep -c 'REFUSED' <<< "$out")" "1 1"
out=$(plan vault-real)
check "a vars file as production's (an arch, a host name, a count, a flag, a list unchanged): its version and hash moved - proven" \
  "$(grep -c '^test:copy:playbook PLAYBOOK=upgrade-vault.yml' <<< "$out")" "1"
for u in vault-flag vault-list; do
  out=$(plan "$u")
  check "  $u: a flag flipped / a list of versions changed beside it - proven (no template in either)" \
    "$(grep -c '^test:copy:playbook PLAYBOOK=upgrade-vault.yml' <<< "$out")" "1"
done
for u in vault-list-jinja vault-nested-jinja; do
  out=$(plan "$u"); rc=$?
  check "  $u: a template inside a list / inside a nested value: refused" "$rc $(grep -c '^REFUSED' <<< "$out")" "1 1"
done
out=$(plan node-exporter-port); rc=$?
check "  another of its values (its port): refused, no known proof" "$rc $(grep -c 'node_exporter_port' <<< "$out")" "1 1"
out=$(plan caddy); f=$(vars_of setup-caddy.yml "$out")
check "Caddy's version: production's setup-caddy on the copy's Pis, the branch's version handed to it (it builds the pinned one)" \
  "$(sed "s|@$f|@VARS|" <<< "$out") | $( [ -n "$f" ] && tr '\n' ' ' < "$f")" \
  "test:copy:playbook PLAYBOOK=setup-caddy.yml ARGS='-e @VARS' | caddy_version: 2.10.2 "
out=$(plan consul); f=$(vars_of upgrade-consul.yml "$out")
check "Consul's version: production's upgrade-consul on the copy (the rolling upgrade), the branch's version and hashes handed to it" \
  "$(sed "s|@$f|@VARS|" <<< "$out" | grep upgrade-consul) | $( [ -n "$f" ] && awk '{ gsub(/["\047]/, "") } /consul_version:/ { v = $2 } /amd64:/ { a = substr($2, 1, 4) } /arm64:/ { r = substr($2, 1, 4) } END { print v, a, r }' "$f")" \
  "test:copy:playbook PLAYBOOK=upgrade-consul.yml ARGS='-e @VARS' | 1.20.7 2222 1111"
for u in consul-dc consul-task; do
  out=$(plan "$u"); rc=$?
  check "  $u: another of its values, or its tasks: refused" \
    "$rc $(grep -c '^REFUSED' <<< "$out") $(grep -c 'test:copy:playbook' <<< "$out")" "1 1 0"
done
for u in caddy-peer caddy-task caddy-bad; do
  out=$(plan "$u"); rc=$?
  check "  $u: another of its values, its tasks, or no version beside it: refused" \
    "$rc $(grep -c '^REFUSED' <<< "$out") $(grep -c 'test:copy:playbook' <<< "$out")" "1 1 0"
done
out=$(plan istio-follow); rc=$?
check "Istio's version in setup-istio.yml beside infra's chart: no ops step of its own (it moves with the chart, Argo on the copy)" \
  "$rc $out" "0 test:copy:change INFRA_REF=renovate/istio-follow PLATFORM_REF=main"
out=$(plan data-follow); rc=$?
check "a data operator's chart version in setup-kubeadm's play vars beside infra's chart: no ops step of its own (Argo on the copy)" \
  "$rc $out" "0 test:copy:change INFRA_REF=renovate/data-follow PLATFORM_REF=main"
out=$(plan istio-task); rc=$?
check "  setup-istio's tasks changed beside it: refused" "$rc $(grep -c 'REFUSED.*setup-istio.yml (its tasks)' <<< "$out")" "1 1"
out=$(plan istio-other); rc=$?
check "  another value in setup-istio.yml (not a chart's restated version): refused" \
  "$rc $(grep -c 'REFUSED.*setup-istio.yml istio_cni_version' <<< "$out")" "1 1"
out=$(plan istio-alone); rc=$?
check "  setup-istio's version alone, no chart moving with it: nothing to prove - refused" "$rc $(grep -c 'nothing to prove' <<< "$out")" "1 1"
out=$(plan vault-keyed); rc=$?
check "a unit changing the vendors' keys (renovate/keys): refused, never proven" \
  "$rc $(grep -c 'changes what vouches for the build hashes (renovate/keys/hashicorp.asc)' <<< "$out")" "1 1"
# run mode: the branch's build hashes checked (COPY_UNIT_PINS, a stub saying its arguments) before any proof step; a
# check that fails refuses the unit, nothing proven (task, a stub saying what it was asked)
mkdir -p "$W/bin"
# the task stub notes the locale's encoding as Ansible reads it at its start (it refuses any but UTF-8)
printf '#!/bin/bash\necho "task $*" >> "$W/ran"\npython3 -c "import locale; locale.setlocale(locale.LC_ALL, \\"\\"); print(locale.getlocale()[1])" > "$W/locale" 2>&1\n' > "$W/bin/task"
printf '#!/bin/bash\necho "pins $*" >> "$W/ran"\nexit "${PINS_RC:-0}"\n' > "$W/bin/pins"
chmod +x "$W/bin/task" "$W/bin/pins"
runit() { rm -f "$W/ran"; PATH="$W/bin:$PATH" W="$W" COPY_UNIT_SRC="$W/src" COPY_UNIT_PINS="$W/bin/pins" \
  bash "$OPS/scripts/copy-unit.sh" "$1" > "$W/run.out" 2>&1; echo $?; }
rc=$(runit vault)
check "run: the build hashes checked first - the branch's changed pins (--check --changed --base main --ref renovate/vault) against main's keys - then the proof; proven" \
  "$rc $(head -1 "$W/ran") | $(sed -n 2p "$W/ran" | cut -d' ' -f1-2) | $(grep -c 'PROVEN' "$W/run.out")" \
  "0 pins --check --changed --base main --ref renovate/vault --root $W/src/ops --keys $OPS/renovate/keys | task test:copy:playbook | 1"
check "  its proof steps in a UTF-8 locale - Ansible refuses any other (LC_ALL=C: 'Detected None', the runner's first build 2026-11-16)" \
  "$(tr -d '-' < "$W/locale" | tr 'A-Z' 'a-z')" "utf8"
rc=$(PINS_RC=1 runit vault)
check "run: a build-hash check that fails refuses the unit - no proof step run" \
  "$rc $(grep -c '^task' "$W/ran") $(grep -c "REFUSED: renovate/vault's build hashes" "$W/run.out")" "1 0 1"
rc=$(runit wave-patches)
check "run: a unit with no ops branch: no build-hash check (infra's and platform's charts carry no ops pin)" \
  "$rc $(grep -c '^pins' "$W/ran")" "0 0"
check "the clones stay on main (the unit's branches fetched beside, never checked out)" \
  "$(for r in infra platform ops; do git -C "$W/src/$r" branch --show-current; done | sort -u)" "main"
echo "copy-unit: $([ $fails -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails -eq 0 ]
