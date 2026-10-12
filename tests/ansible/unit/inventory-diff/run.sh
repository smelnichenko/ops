#!/bin/bash
# scripts/inventory-diff.sh's rules: the same inventory matches; an application image is ignored; a CRD more is allowed
# and named, a CRD missing fails; any other line more or missing fails; an allowed-missing line may be missing, never
# different.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
base='crd gateway-api v1.2.1
crd-name gateways.gateway.networking.k8s.io
crd-name kafkas.kafka.strimzi.io
image docker.io/library/redis 8.2.3
pkg kubelet 1.34.6-1.1 (held)'
case_() { # name, want (0 match / 1 differ), actual lines, [allowed-missing lines], [output must contain]
  printf '%s\n' "$base" > "$W/expected"; printf '%s\n' "$3" > "$W/actual"; printf '%s\n' "${4:-}" > "$W/allowed"
  out=$(scripts/inventory-diff.sh "$W/expected" "$W/actual" "$W/allowed" 2>&1); rc=$?
  if [ "$rc" = "$2" ] && { [ -z "${5:-}" ] || grep -qF -- "$5" <<< "$out"; }; then echo "PASS $1"
  else echo "FAIL $1 (rc $rc, want $2)"; printf '%s\n' "$out" | sed 's/^/    /'; fails=$((fails + 1)); fi
}
case_ "the same inventory matches" 0 "$base" "" "inventories match"
case_ "an application image is ignored" 0 "$base
image git.pmon.dev/schnappy/monitor abc1234"
case_ "a CRD more is allowed, and named" 0 "$base
crd-name newthings.example.io" "" "new CRDs (allowed): newthings.example.io"
case_ "a CRD missing fails" 1 "$(grep -v kafkas <<< "$base")" "" "-crd-name kafkas.kafka.strimzi.io"
case_ "a CRD missing on the allowed list may be missing" 0 "$(grep -v kafkas <<< "$base")" "crd-name kafkas.kafka.strimzi.io"
case_ "another line more fails" 1 "$base
image docker.io/library/redis 8.4.0" "" "+image docker.io/library/redis 8.4.0"
case_ "the CRD bundle's version line is not a CRD: a new one fails" 1 "$(sed 's/v1.2.1/v1.5.1/' <<< "$base")"
case_ "an allowed-missing line there but different fails" 1 "$(sed 's/8.2.3/8.4.0/' <<< "$base")" "image docker.io/library/redis 8.2.3"
case_ "the copy's image-build tools are ignored" 0 "$base
binary /usr/local/bin/nerdctl 2.0.3
binary /usr/local/bin/buildkitd 3637d1b"
case_ "a runc outside the packages fails (it runs instead of the package's)" 1 "$base
binary /usr/local/bin/nerdctl 2.0.3
binary /usr/local/bin/runc 1.2.4" "" "+binary /usr/local/bin/runc 1.2.4"
# a tag restated by hand in the three lists (production's inventory and the two allow-lists): Woodpecker's, outside
# the steps - one list left behind passed every check that reads only one of them (the test-quality review, 2026-10-12)
U=tests/ansible/upgrade
for img in woodpeckerci/woodpecker-server woodpeckerci/woodpecker-agent; do
  tags=$(for l in prod-inventory vagrant-allowed-missing targets-allowed-missing; do
    awk -v i="docker.io/$img" '$1 == "image" && $2 == i {print $3}' "$U/$l.txt"; done | sort -u | tr '\n' ' ')
  if [ "$(echo $tags | wc -w)" = 1 ]; then echo "PASS $img: one tag in the three lists ($tags)"
  else echo "FAIL $img: the three lists name tags '$tags' - one release, written in each"; fails=$((fails + 1)); fi
done
echo "inventory-diff: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
