#!/bin/bash
# External Secrets' Helm release record (ten's Helm install of 2026-04-05: chart 2.2.0, installCRDs on) forgotten at
# the step that takes External Secrets to its target (44): Argo CD owns it from step 41, the record stays - and one
# `helm uninstall external-secrets` deletes every CRD it names, every ExternalSecret, and through owner references their
# Secrets (the CRDs' Prune=false/Delete=false hold against Argo only). deploy/ansible/playbooks/eso-helm-forget.yml
# deletes Helm's storage Secrets of that release alone (owner=helm, name=external-secrets), said first, nothing in a
# preview; the step drops its inventory line, and a copy built after it installs no such release (its base line).
# The playbook run on localhost, kubectl a stub logging its calls.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
step=$(grep -l "^argo-chart external-secrets " tests/ansible/upgrade/steps/*.txt | tail -1)
check "the step taking External Secrets to its target runs the playbook" \
  "$(grep -c '^playbook eso-helm-forget.yml$' "$step")" 1
check "  drops the Helm release's inventory line" \
  "$(grep -c '^- helm external-secrets/external-secrets ' "$step")" 1
check "  and a copy built after it installs none (its base line)" \
  "$(grep -c '^base .*-e external_secrets_by_helm_override=false' "$step")" 1
check "the targets build derives it, restating nothing" \
  "$(grep -c 'external_secrets_by_helm_override=false' <(sed -n '/test:upgrade:build-targets:/,/^  test:upgrade:build:/p' Taskfile.yml))" 0
[ -f deploy/ansible/playbooks/eso-helm-forget.yml ] || { echo "FAIL no deploy/ansible/playbooks/eso-helm-forget.yml"; echo "eso-helm-record: $((fails + 1)) FAILED"; exit 1; }
check "no helm uninstall anywhere in its tasks" \
  "$(grep -v '^\s*#' deploy/ansible/playbooks/eso-helm-forget.yml | grep -c 'helm.*uninstall\|helm.*delete')" 0
mkdir "$W/bin"
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
echo "kubectl $*" >> "$W/calls"
case "$*" in
  *" get secret "*) [ -z "${RECORDS:-}" ] || printf 'secret/sh.helm.release.v1.external-secrets.v1\nsecret/sh.helm.release.v1.external-secrets.v2\n' ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W "$PY" - <<'PY'
import os, yaml
W = os.environ["W"]
play = yaml.safe_load(open("deploy/ansible/playbooks/eso-helm-forget.yml"))
for p in play:
    p.pop("become", None)
    p["hosts"] = "target"
yaml.safe_dump(play, open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
open(os.path.join(W, "hosts.yml"), "w").write(
    "all:\n  hosts:\n    target: {ansible_connection: local, ansible_python_interpreter: '{{ ansible_playbook_python }}'}\n")
PY
run() {  # run <env...> [-- ansible args]: the calls made
  : > "$W/calls"
  env "$@" PATH="$W/bin:$PATH" W="$W" ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" -e kubeconfig=/x \
    ${CHECK:+--check} > "$W/out" 2>&1
  echo "rc=$? $(grep -c ' delete secret ' "$W/calls") deletes"
}
LABEL="-l owner=helm,name=external-secrets"
check "the release's records there: deleted by their label alone, the run green" "$(run RECORDS=1)" "rc=0 1 deletes"
check "  by the label only (owner=helm, name=external-secrets) in its namespace" \
  "$(grep ' delete secret ' "$W/calls" | grep -c -- "-n external-secrets .*$LABEL\|$LABEL.*-n external-secrets")" 1
check "  said first" "$(grep -c 'sh.helm.release.v1.external-secrets.v2' "$W/out")" 1
check "none there: nothing deleted, green" "$(run RECORDS=)" "rc=0 0 deletes"
check "a preview: nothing deleted" "$(CHECK=1 run RECORDS=1)" "rc=0 0 deletes"
echo "eso-helm-record: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
