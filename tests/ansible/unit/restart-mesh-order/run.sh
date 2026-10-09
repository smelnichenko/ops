#!/bin/bash
# restart-mesh-workloads.yml (the Istio steps 03-09): the data tier restarts first and is back - Ready, not only on the
# new sidecar - before the apps restart onto it (production has one Postgres primary, one Kafka broker, one ScyllaDB
# node): a StatefulSet's replicas ready and updated, a CNPG cluster healthy with every instance ready, a Strimzi pod
# set's pods ready. A pod that has the new sidecar is not yet a pod that serves. The playbook on localhost against a
# kubectl stub: its pods take the target sidecar when their owner restarts, and the data tier turns ready only polls
# later; the stub records whether it was ready when the Deployment restarted. An owner it cannot restart still fails.
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
mkdir "$W/bin" "$W/s"
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
# state: $S/<owner> exists once restarted; $S/polls.<owner> counts the readiness reads since
S=$W/s
echo "kubectl $*" >> "$W/calls"
a=" $* "
# READY_AFTER: polls until a data workload is ready; SLOW (one of db, pg, kafka) takes 6 - each kind's own wait shown
after() { [ "$1" = "${SLOW:-}" ] && echo 6 || echo "${READY_AFTER:-3}"; }
ready() { [ -e "$S/$1" ] && [ "$(cat "$S/polls.$1" 2>/dev/null || echo 0)" -ge "$(after "$1")" ]; }
poll() { [ -e "$S/$1" ] && echo $(( $(cat "$S/polls.$1" 2>/dev/null || echo 0) + 1 )) > "$S/polls.$1"; }
v() { [ -e "$S/$1" ] && echo 1.27.9 || echo 1.26.8; }
case "$a" in
  *" rollout status "*) exit 0 ;;
  *" get deployment istiod "*) echo "docker.io/istio/pilot:1.27.9" ;;
  *" get daemonset istio-cni-node "*) echo "docker.io/istio/install-cni:1.27.9" ;;
  *" get pods,replicasets -A -o json "*)
    pod() { echo "{\"kind\": \"Pod\", \"metadata\": {\"namespace\": \"$1\", \"name\": \"$2\", \"ownerReferences\": [{\"kind\": \"$3\", \"name\": \"$4\"}]},
      \"status\": {\"phase\": \"Running\"}, \"spec\": {\"containers\": [{\"name\": \"istio-proxy\", \"image\": \"istio/proxyv2:$5\"}]}}"; }
    echo "{\"items\": [$(pod d db-0 StatefulSet db "$(v db)"), $(pod d pg-1 Cluster pg "$(v pg)"),
      $(pod d kafka-0 StrimziPodSet kafka "$(v kafka)"), $(pod a web-x ReplicaSet web-rs "$(v web)"),
      {\"kind\": \"ReplicaSet\", \"metadata\": {\"namespace\": \"a\", \"name\": \"web-rs\", \"ownerReferences\": [{\"kind\": \"Deployment\", \"name\": \"web\"}]}}
      ${ODD:+, $(pod a odd-0 Lonely odd 1.26.8)}]}" ;;
  *" rollout restart statefulset/db "*) touch "$S/db" ;;
  *" annotate clusters.postgresql.cnpg.io pg "*) touch "$S/pg" ;;
  *" annotate strimzipodsets.core.strimzi.io kafka "*) touch "$S/kafka" ;;
  *" rollout restart deployment/web "*)
    touch "$S/web"
    { ready db && ready pg && ready kafka && echo "web restarted: data tier ready" || echo "web restarted: data tier NOT ready"; } >> "$W/order" ;;
  *" get statefulset db "*) poll db; r=0; ready db && r=1
    echo "{\"spec\": {\"replicas\": 1}, \"status\": {\"readyReplicas\": $r, \"updatedReplicas\": 1, \"currentRevision\": \"b\", \"updateRevision\": \"b\"}}" ;;
  *" get clusters.postgresql.cnpg.io pg "*) poll pg; ph="Upgrading cluster"; r=1; ready pg && { ph="Cluster in healthy state"; r=2; }
    echo "{\"spec\": {\"instances\": 2}, \"status\": {\"phase\": \"$ph\", \"readyInstances\": $r}}" ;;
  *" get strimzipodsets.core.strimzi.io kafka "*) poll kafka; r=0; ready kafka && r=1
    echo "{\"status\": {\"pods\": 1, \"readyPods\": $r}}" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W "$PY" - <<'PY'
import os, yaml
W = os.environ["W"]
play = yaml.safe_load(open("deploy/ansible/playbooks/restart-mesh-workloads.yml"))
for p in play:
    p.pop("become", None)
    p["hosts"] = "target"
    for t in p["tasks"]:  # the stub answers at once: no wait between tries
        if "delay" in t:
            t["delay"] = 0
yaml.safe_dump(play, open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
open(os.path.join(W, "hosts.yml"), "w").write(
    "all:\n  hosts:\n    target: {ansible_connection: local, ansible_python_interpreter: '{{ ansible_playbook_python }}'}\n")
PY
run() {  # run <env...>: rc
  rm -f "$W"/s/* "$W/calls" "$W/order"
  env "$@" PATH="$W/bin:$PATH" W="$W" ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" -e kubeconfig=/x \
    -e istio_version=1.27.9 > "$W/out" 2>&1
  echo "rc=$?"
}
check "the data tier ready (3 reads after its restart): green" "$(run X=1)" "rc=0"
check "  the apps restarted onto a data tier that is ready again, not only on the new sidecar" \
  "$(cat "$W/order" 2>/dev/null)" "web restarted: data tier ready"
check "  each data workload's readiness read" \
  "$(grep -c -e ' get statefulset db ' "$W/calls") $(grep -c ' get clusters.postgresql.cnpg.io pg ' "$W/calls") \
$(grep -c ' get strimzipodsets.core.strimzi.io kafka ' "$W/calls")" "$(echo 3 3 3)"
for slow in db pg kafka; do
  run SLOW=$slow > /dev/null
  check "  $slow the last one ready: the apps waited for it" "$(cat "$W/order" 2>/dev/null)" "web restarted: data tier ready"
done
check "an owner it cannot restart: refused before any restart" \
  "$(run ODD=1) $(grep -c -E ' rollout restart | annotate ' "$W/calls")" "rc=2 0"
check "a data workload never ready: the apps not restarted" "$(run READY_AFTER=999 | cut -c1-4) $(grep -c 'deployment/web' "$W/calls")" \
  "rc=2 0"
echo "restart-mesh-order: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
