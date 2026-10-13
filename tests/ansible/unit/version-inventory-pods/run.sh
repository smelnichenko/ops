#!/bin/bash
# scripts/version-inventory.sh lists the images that run or are set to run - and not the pods that come and go with a
# CI pipeline: Woodpecker's (wp-...) and the local-path provisioner's helper pods (helper-pod-create/delete-pvc-...,
# its busybox, about 20 s around each pipeline's workspace volume). One caught by a step's check failed it (03-istio-1.26,
# 2026-10-13: "image busybox latest"). kubectl stubbed with those pods; helm, dpkg-query and systemctl stubbed empty.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/stubs" "$W/bin"
pod() {  # pod <namespace> <name> <image> [<phase>]
  printf '{"kind": "Pod", "metadata": {"namespace": "%s", "name": "%s"}, "spec": {"containers": [{"image": "%s"}]},
    "status": {"phase": "%s"}}' "$1" "$2" "$3" "${4:-Running}"
}
{
  echo '{"items": ['
  pod local-path-storage helper-pod-create-pvc-0fa19bae busybox; echo ,
  pod local-path-storage helper-pod-delete-pvc-62110102 busybox; echo ,
  pod local-path-storage local-path-provisioner-567b5f79b9-5mw22 rancher/local-path-provisioner:v0.0.31; echo ,
  pod woodpecker wp-01m4sc1fv2xc437gcnj8b6sdyh alpine:3.22; echo ,
  pod schnappy-infra helper-pod-lookalike example/app:1.0; echo ,
  pod schnappy-infra done-job example/finished:2.0 Succeeded
  echo ']}'
} > "$W/pods.json"
cat > "$W/stubs/kubectl" <<STUB_KUBECTL
#!/bin/sh
case "\$*" in
  "get pods,cronjobs,jobs -A -o json") cat "$W/pods.json" ;;
  *"-o json"*) echo '{"items": [], "serverVersion": {"gitVersion": "v0"}}' ;;
  *) exit 1 ;;
esac
STUB_KUBECTL
printf '#!/bin/sh\ncase "$*" in "list -A -o json") echo "[]";; *) exit 1;; esac\n' > "$W/stubs/helm"
printf '#!/bin/sh\nexit 0\n' > "$W/stubs/dpkg-query"
printf '#!/bin/sh\necho /lib/systemd/system/containerd.service\n' > "$W/stubs/systemctl"
chmod +x "$W/stubs/"*
fails=0
check() {  # name, got, want
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
}
out=$(PATH="$W/stubs:$PATH" INVENTORY_BIN_DIR="$W/bin" KUBECONFIG=/dev/null bash scripts/version-inventory.sh 2>&1)
images=$(grep '^image ' <<< "$out" | paste -sd,)
check "the provisioner's helper pods (busybox) left out" "$(grep -c '^image busybox' <<< "$out")" 0
check "Woodpecker's pipeline pods left out" "$(grep -c '^image alpine' <<< "$out")" 0
check "the provisioner itself, a lookalike name elsewhere listed; a finished pod not" "$images" \
  "image example/app 1.0,image rancher/local-path-provisioner v0.0.31"
echo "version-inventory-pods: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
