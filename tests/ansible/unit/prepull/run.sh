#!/bin/bash
# upgrade-prepull.yml as the playbook holds it, run by ansible-playbook on localhost (become dropped, the retry delay
# 0), crictl a stub that logs its arguments: no images refuses, nor does anything that is no image reference (a flag,
# two words); each image pulled through containerd's socket by name (ten has no crictl.yaml - crictl tried its
# deprecated default endpoints); a registry's passing failure retried, a lasting one fails the pull. The image store
# (df a stub, the kubelet's config a file here) under the kubelet's image GC threshold less 5 before the pulls and
# after - the pulled images are unused until their rollout, and GC deletes those first: too full before, nothing
# pulled; too full after, the run fails; the threshold read from the kubelet's config (85, its default, without one).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
ln -s "$PWD/deploy/ansible/playbooks/tasks" "$W/tasks"  # the play's includes, beside its copy
# FAILS=<n>: the first n pulls fail (a registry's 5xx)
cat > "$W/bin/crictl" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
n=$(wc -l < "$CALLS")
[ "$n" -gt "${FAILS:-0}" ] || { echo "pull failed: 503" >&2; exit 1; }
STUB
# USED=<before>,<after>: the image store's use in percent, per df call (50 without)
cat > "$W/bin/df" <<'STUB'
#!/bin/bash
echo "df $*" >> "$W/df-calls"
n=$(wc -l < "$W/df-calls")
IFS=, read -r -a used <<< "${USED:-50,50}"
echo "Use%"; echo " ${used[$((n - 1))]:-${used[-1]}}%"
STUB
chmod +x "$W/bin/crictl" "$W/bin/df"
W=$W "$PY" - <<'PY'
import os, yaml
W = os.environ["W"]
play = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-prepull.yml"))
for p in play:
    p.pop("become", None)
    for t in p["tasks"]:
        if "delay" in t:
            t["delay"] = 0
yaml.safe_dump(play, open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
open(os.path.join(W, "hosts.yml"), "w").write(
    "all:\n  hosts:\n    target: {ansible_connection: local, ansible_python_interpreter: '{{ ansible_playbook_python }}'}\n")
PY
fails=0
case_() {  # case_ <name> <want rc 0|1> <want calls, ; between> <ansible-playbook args...>
  local name=$1 want=$2 calls=$3; shift 3
  : > "$W/calls"; : > "$W/df-calls"
  printf '%s\n' "kind: KubeletConfiguration" ${GC_HIGH:+"imageGCHighThresholdPercent: $GC_HIGH"} > "$W/kubelet.yaml"
  out=$(PATH="$W/bin:$PATH" CALLS="$W/calls" W="$W" ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" \
    -e kubelet_config="$W/kubelet.yaml" -e image_store="$W" "$@" 2>&1); rc=$?
  [ "$rc" = 0 ] || rc=1
  got=$(paste -sd';' "$W/calls")
  if [ "$rc" = "$want" ] && [ "$got" = "$calls" ]; then echo "PASS $name"; return; fi
  echo "FAIL $name (rc $rc, want $want)"; echo "    got:  $got"; echo "    want: $calls"; fails=$((fails + 1))
}
E="--runtime-endpoint unix:///run/containerd/containerd.sock --image-endpoint unix:///run/containerd/containerd.sock"
case_ "no images: refused, nothing pulled" 1 "" -e images=
D=sha256:$(printf 'f%.0s' {1..64})
case_ "each image pulled through containerd's socket" 0 "$E pull docker.io/a/b:1;$E pull ghcr.io/c/d:2@$D" \
  -e images=docker.io/a/b:1,ghcr.io/c/d:2@$D
FAILS=1 case_ "a pull failing once: retried, pulled" 0 "$E pull docker.io/a/b:1;$E pull docker.io/a/b:1" \
  -e images=docker.io/a/b:1
FAILS=9 case_ "a pull failing every time: the run fails" 1 "$E pull x:1;$E pull x:1;$E pull x:1;$E pull x:1" \
  -e images=x:1
# a value that is no image reference - a crictl flag, two words - refused before any pull
case_ "a flag for an image: refused, nothing pulled" 1 "" -e images=--debug
case_ "two words for an image: refused, nothing pulled" 1 "" -e '{"images": "a/b:1 --insecure"}'
USED=65,66 case_ "the image store at 65%, then 66% (GC at 85): pulled" 0 "$E pull x:1" -e images=x:1
USED=80,80 case_ "at 80% before (GC at 85, less 5): refused, nothing pulled" 1 "" -e images=x:1
USED=70,81 case_ "at 81% after the pulls: the run fails" 1 "$E pull x:1" -e images=x:1
GC_HIGH=70 USED=66,66 case_ "the kubelet's own threshold read (70): 66% refused, nothing pulled" 1 "" -e images=x:1
echo "prepull: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
