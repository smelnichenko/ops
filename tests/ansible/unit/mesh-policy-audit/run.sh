#!/bin/bash
# scripts/mesh-policy-audit.py against a stub kubectl (the cluster as JSON fixtures): a policy selecting pods with a
# proxy (a container, or a native sidecar) passes; one selecting nothing (unless allowed), a proxy-less pod (allowed or
# not), or only finished ones fails, named (exit 3); a failure gone by a later read is none; a namespace-wide one and
# another namespace's are not judged, one attached by targetRef named; a kubectl failure is exit 1, never a pass.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
pod() {  # pod <ns> <name> <component> <proxy: container|native|none> [phase]
  local c='[{"name":"app"}]' i='[]'
  [ "$4" = container ] && c='[{"name":"app"},{"name":"istio-proxy"}]'
  [ "$4" = native ] && i='[{"name":"istio-proxy","restartPolicy":"Always"}]'
  printf '{"metadata":{"namespace":"%s","name":"%s","labels":{"app.kubernetes.io/component":"%s"}},"spec":{"containers":%s,"initContainers":%s},"status":{"phase":"%s"}}' \
    "$1" "$2" "$3" "$c" "$i" "${5:-Running}"
}
pol() {  # pol <kind> <ns> <name> [component]
  local s='{}'; [ -n "${4:-}" ] && s="{\"selector\":{\"matchLabels\":{\"app.kubernetes.io/component\":\"$4\"}}}"
  printf '{"kind":"%s","metadata":{"namespace":"%s","name":"%s"},"spec":%s}' "$1" "$2" "$3" "$s"
}
cat > "$T/kubectl" <<'STUB'
#!/bin/sh
case "$*" in
  "get pods -A -o json")
    # a pods.json.<n> for the n-th read when there is one (a cluster changing between reads)
    n=$(( $(cat "$T/reads" 2> /dev/null || echo 0) + 1 )); echo "$n" > "$T/reads"
    if [ -f "$T/pods.json.$n" ]; then cat "$T/pods.json.$n"; else cat "$T/pods.json"; fi ;;
  "get authorizationpolicies.security.istio.io -A -o json") cat "$T/ap.json" ;;
  "get peerauthentications.security.istio.io -A -o json") cat "$T/pa.json" ;;
  "get requestauthentications.security.istio.io -A -o json") [ -n "${FAIL_RA:-}" ] && { echo "the server is down" >&2; exit 1; }; echo '{"items":[]}' ;;
  *) echo "stub: unexpected $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$T/kubectl"
world() {  # world <pods...> -- <aps...> -- <pas...>
  local p="" a="" b="" part=p x
  for x in "$@"; do
    if [ "$x" = -- ]; then part=$([ $part = p ] && echo a || echo b); continue; fi
    case $part in p) p="$p${p:+,}$x" ;; a) a="$a${a:+,}$x" ;; b) b="$b${b:+,}$x" ;; esac
  done
  printf '{"items":[%s]}' "$p" > "$T/pods.json"; printf '{"items":[%s]}' "$a" > "$T/ap.json"; printf '{"items":[%s]}' "$b" > "$T/pa.json"
}
run() { rm -f "$T/reads"; if T="$T" KUBECTL="$T/kubectl" READ_GAP=0 python3 scripts/mesh-policy-audit.py "$@" > "$T/out" 2>&1; then echo rc=0; else echo "rc=$?"; fi; }
world "$(pod schnappy-production pg-1 database container)" "$(pod schnappy-production k-0 kafka native)" -- \
  "$(pol AuthorizationPolicy schnappy-production p-db database)" "$(pol AuthorizationPolicy schnappy-production p-ns)" -- \
  "$(pol PeerAuthentication schnappy-production p-k kafka)" "$(pol PeerAuthentication kagent p-other nothing)"
check "every policy selecting a pod with a proxy (a container, a native sidecar); namespace-wide and other namespaces not judged" \
  "$(run) $(grep -c 'every policy enforced by a proxy' "$T/out")" "rc=0 1"
world "$(pod schnappy-production pg-1 database container)" "$(pod schnappy-production sc-0 scylla none)" "$(pod schnappy-test old-1 masi container Succeeded)" -- \
  "$(pol AuthorizationPolicy schnappy-production p-pg postgres)" "$(pol AuthorizationPolicy schnappy-production p-sc scylla)" \
  "$(pol AuthorizationPolicy schnappy-test p-masi masi)" -- "$(pol PeerAuthentication schnappy-test p-ok database)"
check "nothing selected, only proxy-less pods, only a finished pod, another namespace's pod: each named, exit 3" \
  "$(run) $(grep -oE 'schnappy-[a-z]+/p-[a-z]+' "$T/out" | sort -u | tr '\n' ' ')" \
  "rc=3 schnappy-production/p-pg schnappy-production/p-sc schnappy-test/p-masi schnappy-test/p-ok "
check "  allowed: a policy for what the namespace does not run - never one over a pod without a proxy" \
  "$(run --allow schnappy-production/p-pg --allow schnappy-production/p-sc --allow schnappy-test/p-masi --allow schnappy-test/p-ok) $(grep -oE 'schnappy-[a-z]+/p-[a-z]+' "$T/out" | sort -u | tr '\n' ' ')" \
  "rc=3 schnappy-production/p-sc "
world "$(pod schnappy-production pg-1 database container)" "$(pod schnappy-production pg-2 database none)" -- \
  "$(pol AuthorizationPolicy schnappy-production p-db database)" -- ""
check "a policy over two instances, one without a proxy: named with that pod" "$(run) $(grep -c 'NO PROXY ON pg-2' "$T/out")" "rc=3 1"
world "$(pod schnappy-production pg-1 database container)" -- "$(pol AuthorizationPolicy schnappy-production p-db database)" -- ""
printf '{"items":[]}' > "$T/pods.json.1"
check "a pod gone in the first read, back in the second (a roll): no finding" "$(run) $(grep -c 'every policy enforced' "$T/out")" "rc=0 1"
rm -f "$T/pods.json.1"
printf '{"items":[]}' > "$T/pods.json.1"; printf '{"items":[]}' > "$T/pods.json.2"; printf '{"items":[]}' > "$T/pods.json.3"
check "  gone in every read: named" "$(run)" "rc=3"
rm -f "$T"/pods.json.[123]
world "$(pod schnappy-production pg-1 database container)" -- \
  '{"kind":"AuthorizationPolicy","metadata":{"namespace":"schnappy-production","name":"p-tr"},"spec":{"targetRefs":[{"kind":"Service","name":"x"}]}}' -- ""
check "a policy attached by targetRef: named, not judged" "$(run) $(grep -c 'p-tr .*attached by targetRef - not judged' "$T/out")" "rc=0 1"
check "a kubectl failure: exit 1, never a pass" "$(FAIL_RA=1 run) $(grep -c 'reading requestauthentications.security.istio.io failed' "$T/out")" "rc=1 1"
check "an unknown argument refused" "$(run --alow x)" "rc=1"
echo "mesh-policy-audit: $([ $fails -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails -eq 0 ]
