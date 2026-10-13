#!/bin/bash
# scripts/version-inventory.sh lists the images that run or are set to run - and not the pods that come and go with a
# CI pipeline: Woodpecker's (wp-...) and the local-path provisioner's helper pods (helper-pod-create/delete-pvc-...,
# its busybox, about 20 s around each pipeline's workspace volume). One caught by a step's check failed it (03-istio-1.26,
# 2026-10-13: "image busybox latest"). Nor Velero's repository maintenance Jobs (labelled velero.io/repo-name): they
# run Velero's own image, listed by its Deployment, and the version before an upgrade stays in them for hours
# (10-velero's done, 2026-10-13: "velero v1.18.0"). Any other Job is listed finished or not: a hook's image is a version
# the steps move (init-users' postgres, the Scylla schema's scylla - a full run of 2026-10-13 failed when finished Jobs
# were left out). kubectl stubbed with those; helm, dpkg-query and systemctl stubbed empty.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/stubs" "$W/bin"
pod() {  # pod <namespace> <name> <image> [<phase>]
  printf '{"kind": "Pod", "metadata": {"namespace": "%s", "name": "%s"}, "spec": {"containers": [{"image": "%s"}]},
    "status": {"phase": "%s"}}' "$1" "$2" "$3" "${4:-Running}"
}
job() {  # job <namespace> <name> <image> <status json> [<labels json>]: a Job no CronJob owns
  printf '{"kind": "Job", "metadata": {"namespace": "%s", "name": "%s", "labels": %s}, "spec": {"template": {"spec":
    {"containers": [{"image": "%s"}]}}}, "status": %s}' "$1" "$2" "${5:-{\}}" "$3" "$4"
}
maint='{"velero.io/repo-name": "schnappy-default-kopia"}'
done='{"succeeded": 1, "conditions": [{"type": "Complete", "status": "True"}]}'
failed='{"failed": 1, "conditions": [{"type": "Failed", "status": "True"}]}'
{
  echo '{"items": ['
  pod local-path-storage helper-pod-create-pvc-0fa19bae busybox; echo ,
  pod local-path-storage helper-pod-delete-pvc-62110102 busybox; echo ,
  pod local-path-storage local-path-provisioner-567b5f79b9-5mw22 rancher/local-path-provisioner:v0.0.31; echo ,
  pod woodpecker wp-01m4sc1fv2xc437gcnj8b6sdyh alpine:3.22; echo ,
  pod schnappy-infra helper-pod-lookalike example/app:1.0; echo ,
  pod schnappy-infra done-job example/finished:2.0 Succeeded; echo ,
  job velero repo-maintain-1 velero/velero:v1.18.0 "$done" "$maint"; echo ,
  job velero repo-maintain-2 velero/velero:v1.18.1 "$failed" "$maint"; echo ,
  job velero repo-maintain-3 velero/velero:v1.18.2 '{"active": 1}' "$maint"; echo ,
  job schnappy-production init-users postgres:17-alpine "$done"; echo ,
  job schnappy-production scylla-schema scylladb/scylla:6.2 "$failed"; echo ,
  pod schnappy-infra local-registry registry.local:5000/tools/busybox
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
check "the provisioner itself, a lookalike name elsewhere, a hook Job complete or failed listed (a registry's port no \
tag); a finished pod, Velero's maintenance Jobs (any state) not" "$images" \
  "image example/app 1.0,image postgres 17-alpine,image rancher/local-path-provisioner v0.0.31,\
image registry.local:5000/tools/busybox latest,image scylladb/scylla 6.2"
echo "version-inventory-pods: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
