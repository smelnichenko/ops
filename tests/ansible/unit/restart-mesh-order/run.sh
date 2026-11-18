#!/bin/bash
# restart-mesh-workloads.yml (the Istio steps 03-09): the data tier restarts first and is back - Ready, not only on the
# new sidecar - before the apps restart onto it (production has one Postgres primary, one Kafka broker, one ScyllaDB
# node): a StatefulSet's replicas ready and updated, a CNPG cluster healthy with every instance ready, a Strimzi pod
# set's pods ready. A pod that has the new sidecar is not yet a pod that serves. The playbook on localhost against a
# kubectl stub: its pods take the target sidecar when their owner restarts, and the data tier turns ready only polls
# later; the stub records whether it was ready when the Deployment restarted. An owner it cannot restart still fails.
# And the sidecar's mode: istiod's ENABLE_NATIVE_SIDECARS flipped (or unset - native, Istio's default since 1.27), every
# pod of the other mode is restarted though its version is the target's; a pod's own nativeSidecar annotation decides
# for it; pods already in their mode are left alone.
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
# TARGET: the version restarted onto (1.27.9; 1.26.9 - before native was Istio's default); the old one before it
v() { [ -e "$S/$1" ] || [ -n "${SAME_VERSION:-}" ] && echo "${TARGET:-1.27.9}" || echo 1.26.8; }
# the sidecar's mode: OLD_MODE before its owner restarts it, NEW_MODE after (classic | native)
m() { [ -e "$S/$1" ] && echo "${NEW_MODE:-classic}" || echo "${OLD_MODE:-classic}"; }
case "$a" in
  *" rollout status "*) exit 0 ;;
  # the env's value by the playbook's exact jsonpath (a malformed one reads nothing)
  *" get deployment istiod -o jsonpath={.spec.template.spec.containers[0].env[?(@.name==\"ENABLE_NATIVE_SIDECARS\")].value} "*)
    printf '%s' "${NATIVE_ENV-false}" ;;
  *" get deployment istiod "*ENABLE_NATIVE*) exit 0 ;;
  *" get deployment istiod "*) echo "docker.io/istio/pilot:${TARGET:-1.27.9}" ;;
  *" get daemonset istio-cni-node "*) echo "docker.io/istio/install-cni:${TARGET:-1.27.9}" ;;
  *" get pods,replicasets -A -o json "*)
    pod() {  # pod <ns> <name> <owner kind> <owner> <version> [<mode> [<its nativeSidecar annotation> [<labels json>]]]
      # mode: classic, native, or init (an istio-proxy init container without restartPolicy Always - no native sidecar)
      local proxy="{\"name\": \"istio-proxy\", \"image\": \"istio/proxyv2:$5\"" ann="" lab=""
      [ -z "${7:-}" ] || ann=", \"annotations\": {\"sidecar.istio.io/nativeSidecar\": \"$7\"}"
      [ -z "${8:-}" ] || lab=", \"labels\": $8"
      case "${6:-classic}" in
        native) spec="\"initContainers\": [$proxy, \"restartPolicy\": \"Always\"}], \"containers\": [{\"name\": \"app\"}]" ;;
        init) spec="\"initContainers\": [$proxy}], \"containers\": [{\"name\": \"app\"}]" ;;
        *) spec="\"containers\": [$proxy}]" ;;
      esac
      echo "{\"kind\": \"Pod\", \"metadata\": {\"namespace\": \"$1\", \"name\": \"$2\", \"ownerReferences\": [{\"kind\": \"$3\", \"name\": \"$4\"}]$ann$lab},
      \"status\": {\"phase\": \"Running\"}, \"spec\": {$spec}}"; }
    echo "{\"items\": [$(pod d db-0 StatefulSet db "$(v db)" "$(m db)"), $(pod d pg-1 Cluster pg "$(v pg)" "$(m pg)"),
      $(pod d kafka-0 StrimziPodSet kafka "$(v kafka)" "$(m kafka)"), $(pod a web-x ReplicaSet web-rs "$(v web)" "$( [ -e "$S/web" ] && m web || echo "${WEB_MODE:-$(m web)}")" "${WEB_ANN:-}"),
      $(pod g gw-x ReplicaSet gw-rs "$(v gw)" classic "" '{"sidecar.istio.io/inject": "false", "gateway.networking.k8s.io/gateway-name": "gw"}'),
      {\"kind\": \"ReplicaSet\", \"metadata\": {\"namespace\": \"g\", \"name\": \"gw-rs\", \"ownerReferences\": [{\"kind\": \"Deployment\", \"name\": \"gw\"}]}}
      ${JOB:+, $(pod a job-x Job job-1 "$(v job)" classic)},
      {\"kind\": \"ReplicaSet\", \"metadata\": {\"namespace\": \"a\", \"name\": \"web-rs\", \"ownerReferences\": [{\"kind\": \"Deployment\", \"name\": \"web\"}]}}
      ${ODD:+, $(pod a odd-0 Lonely odd 1.26.8)}]}" ;;
  *" rollout restart statefulset/db "*) touch "$S/db" ;;
  *" annotate clusters.postgresql.cnpg.io pg "*) touch "$S/pg" ;;
  *" annotate strimzipodsets.core.strimzi.io kafka "*) touch "$S/kafka" ;;
  *" rollout restart deployment/gw "*) touch "$S/gw" ;;
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
run() {  # run <env...>: rc - TARGET=<version> among them the version restarted onto (its -e istio_version too)
  local t=1.27.9 a
  for a in "$@"; do case "$a" in TARGET=*) t=${a#TARGET=} ;; esac; done
  rm -f "$W"/s/* "$W/calls" "$W/order"
  env "$@" PATH="$W/bin:$PATH" W="$W" ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" -e kubeconfig=/x \
    -e istio_version="$t" > "$W/out" 2>&1
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
# the mode: every sidecar on the target version already
restarted() { grep -c -E ' rollout restart | annotate ' "$W/calls"; }
check "native sidecars switched on (istiod's ENABLE_NATIVE_SIDECARS true), every pod classic: all four restarted, the data tier first, green" \
  "$(run SAME_VERSION=1 NATIVE_ENV=true NEW_MODE=native) $(restarted) $(cat "$W/order" 2>/dev/null)" "rc=0 4 web restarted: data tier ready"
check "  unset (Istio's default since 1.27: native): the same" "$(run SAME_VERSION=1 NATIVE_ENV= NEW_MODE=native) $(restarted)" "rc=0 4"
check "  every pod native already: nothing restarted" "$(run SAME_VERSION=1 NATIVE_ENV=true OLD_MODE=native NEW_MODE=native) $(restarted)" "rc=0 0"
check "  a pod whose own annotation keeps it classic (nativeSidecar false): left alone, the other three restarted" \
  "$(run SAME_VERSION=1 NATIVE_ENV=true NEW_MODE=native WEB_ANN=false) $(restarted) $(grep -c 'deployment/web' "$W/calls")" "rc=0 3 0"
check "classic again (ENABLE_NATIVE_SIDECARS false), every pod native: all restarted onto classic" \
  "$(run SAME_VERSION=1 NATIVE_ENV=false OLD_MODE=native NEW_MODE=classic) $(restarted)" "rc=0 4"
check "  a pod native by its own annotation (the Kafka backup's kind): left alone" \
  "$(run SAME_VERSION=1 NATIVE_ENV=false OLD_MODE=native NEW_MODE=classic WEB_ANN=true) $(grep -c 'deployment/web' "$W/calls")" "rc=0 0"
check "  restarted pods coming back in the wrong mode: never green (the wait for the mode, not the version alone)" \
  "$(run SAME_VERSION=1 NATIVE_ENV=true NEW_MODE=classic | cut -c1-4)" "rc=2"
# a gateway's pod (the proxy its workload): its version judged, never its mode - native switched on, it stays classic
check "  a gateway's pod (inject false, its Gateway's label): never restarted for its mode, the run green" \
  "$(run SAME_VERSION=1 NATIVE_ENV=true NEW_MODE=native) $(grep -c 'deployment/gw' "$W/calls")" "rc=0 0"
check "  but restarted for its version (an Istio upgrade)" "$(run NATIVE_ENV=false) $(grep -c 'deployment/gw' "$W/calls")" "rc=0 1"
check "unset below 1.27 (classic was Istio's default then): classic pods left alone" \
  "$(run TARGET=1.26.9 SAME_VERSION=1 NATIVE_ENV=) $(restarted)" "rc=0 0"
check "  a value neither true nor false: Istio's default for the version (1.27: native) - classic pods restarted" \
  "$(run SAME_VERSION=1 NATIVE_ENV=maybe NEW_MODE=native) $(restarted)" "rc=0 4"
check "  an annotation True (any case): native for that pod" \
  "$(run SAME_VERSION=1 NATIVE_ENV=false OLD_MODE=native NEW_MODE=classic WEB_ANN=True) $(grep -c 'deployment/web' "$W/calls")" "rc=0 0"
check "an istio-proxy init container without restartPolicy Always: no native sidecar - restarted onto one" \
  "$(run SAME_VERSION=1 NATIVE_ENV=true OLD_MODE=native NEW_MODE=native WEB_MODE=init) $(grep -c 'deployment/web' "$W/calls")" "rc=0 1"
check "a Job's pod of the other mode: listed, never restarted (it ends on its own), the run green" \
  "$(run SAME_VERSION=1 NATIVE_ENV=true OLD_MODE=native NEW_MODE=native JOB=1) $(restarted)" "rc=0 0"
echo "restart-mesh-order: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
